import Foundation
import ServiceManagement
import SleepHelperCore

protocol LidSleepControlling: Sendable {
    func setDisabled(_ disabled: Bool, until deadline: Date?) -> String?
    func restoreLegacySetting() -> String?
    func observeLeaseLoss(_ handler: @escaping @Sendable () -> Void) -> UUID?
    func removeLeaseObserver(_ id: UUID)
}

extension LidSleepControlling {
    func observeLeaseLoss(_ handler: @escaping @Sendable () -> Void) -> UUID? { nil }
    func removeLeaseObserver(_ id: UUID) {}
}

final class SleepHelperClient: LidSleepControlling, @unchecked Sendable {
    static let shared = SleepHelperClient()
    static let approvalMessage = "Keep Awake needs one-time authorization. Open Keep Awake settings, then allow Mac Switch in Login Items & Extensions."
    private let queue = DispatchQueue(label: "com.maxyu.macswitch.sleep-client")
    private var connection: NSXPCConnection?
    private var connectionGeneration: UUID?
    private let stateLock = NSLock()
    private var liveGeneration: UUID?
    private var observers: [UUID: @Sendable () -> Void] = [:]
    private let connectionFactory: (@Sendable () -> NSXPCConnection)?
    private let serviceValidation: (@Sendable () -> String?)?

    init(connectionFactory: (@Sendable () -> NSXPCConnection)? = nil, serviceValidation: (@Sendable () -> String?)? = nil) {
        self.connectionFactory = connectionFactory
        self.serviceValidation = serviceValidation
    }

    func observeLeaseLoss(_ handler: @escaping @Sendable () -> Void) -> UUID? {
        let id = UUID()
        stateLock.withLock { observers[id] = handler }
        return id
    }
    func removeLeaseObserver(_ id: UUID) { _ = stateLock.withLock { observers.removeValue(forKey: id) } }

    private func connectionLost(_ id: UUID) {
        let callbacks = stateLock.withLock { () -> [@Sendable () -> Void] in
            guard liveGeneration == id else { return [] }
            liveGeneration = nil
            return Array(observers.values)
        }
        callbacks.forEach { $0() }
        queue.async { [weak self] in
            guard let self, self.connectionGeneration == id else { return }
            self.connection?.invalidate()
            self.connection = nil
            self.connectionGeneration = nil
        }
    }
    private func discardConnection() {
        if let id = connectionGeneration { connectionLost(id) }
        connection?.invalidate()
        connection = nil
        connectionGeneration = nil
    }
    private var service: SMAppService { .daemon(plistName: SleepHelperIdentity.plistName) }
    var isReady: Bool { service.status == .enabled }

    func authorize() -> String? { queue.sync { prepare(allowRegistration: true) } }

    private func prepare(allowRegistration: Bool) -> String? {
        if let serviceValidation { return serviceValidation() }
        guard Bundle.main.bundleIdentifier == SleepHelperIdentity.appIdentifier,
              SleepHelperIdentity.ownTeam() != nil else {
            return "Keep Awake authorization requires the signed Mac Switch app. Install the latest release in Applications."
        }
        if service.status == .notRegistered, allowRegistration {
            do { try service.register() }
            catch {
                if service.status != .requiresApproval && service.status != .enabled {
                    return "Could not register Keep Awake access: \(error.localizedDescription)"
                }
            }
        }
        guard service.status == .enabled else { return Self.approvalMessage }
        return nil
    }

    func setDisabled(_ disabled: Bool, until deadline: Date?) -> String? {
        queue.sync {
            if let error = prepare(allowRegistration: false) { discardConnection(); return error }
            return request { $0.setLidSleepDisabled(disabled, until: deadline, reply: $1) }
        }
    }

    func restoreLegacySetting() -> String? {
        queue.sync {
            if let error = prepare(allowRegistration: false) { discardConnection(); return error }
            return request { $0.restoreLegacySleepSetting(reply: $1) }
        }
    }

    private func request(_ operation: (any SleepHelperProtocol, @escaping (String?) -> Void) -> Void) -> String? {
        if connectionGeneration != stateLock.withLock({ liveGeneration }) { discardConnection() }
        if connection == nil {
            let newConnection: NSXPCConnection
            if let connectionFactory {
                newConnection = connectionFactory()
            } else {
                guard let team = SleepHelperIdentity.ownTeam(),
                      let requirement = SleepHelperIdentity.requirement(identifier: SleepHelperIdentity.serviceIdentifier, team: team) else {
                    return "Could not verify the Keep Awake helper identity."
                }
                newConnection = NSXPCConnection(machServiceName: SleepHelperIdentity.serviceIdentifier, options: .privileged)
                newConnection.setCodeSigningRequirement(requirement)
            }
            let generation = UUID()
            connectionGeneration = generation
            stateLock.withLock { liveGeneration = generation }
            newConnection.remoteObjectInterface = NSXPCInterface(with: SleepHelperProtocol.self)
            newConnection.interruptionHandler = { [weak self] in self?.connectionLost(generation) }
            newConnection.invalidationHandler = { [weak self] in self?.connectionLost(generation) }
            newConnection.resume()
            connection = newConnection
        }
        guard let connection else { return "Keep Awake helper is unavailable." }
        let result = SleepHelperReply()
        guard let proxy = connection.remoteObjectProxyWithErrorHandler({ error in
            result.finish("Keep Awake helper could not complete the request: \(error.localizedDescription)")
        }) as? any SleepHelperProtocol else { return "Keep Awake helper is unavailable." }
        operation(proxy) { error in result.finish(error) }
        if result.semaphore.wait(timeout: .now() + 15) != .success {
            result.finish("Keep Awake helper timed out. Retry the operation.")
        }
        let error = result.error
        if error != nil {
            // Releasing a connection also releases its lease, even after an uncertain reply.
            discardConnection()
        }
        return error
    }
}

private final class SleepHelperReply: @unchecked Sendable {
    let semaphore = DispatchSemaphore(value: 0)
    private let lock = NSLock()
    private var finished = false
    private var storedError: String?
    var error: String? { lock.withLock { storedError } }
    func finish(_ error: String?) {
        lock.withLock {
            guard !finished else { return }
            storedError = error
            finished = true
            semaphore.signal()
        }
    }
}
