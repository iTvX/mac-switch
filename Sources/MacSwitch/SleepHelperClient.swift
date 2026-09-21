import Foundation
import ServiceManagement
import SleepHelperCore

protocol LidSleepControlling: Sendable {
    func setDisabled(_ disabled: Bool, until deadline: Date?) -> String?
    func restoreLegacySetting() -> String?
}

final class SleepHelperClient: LidSleepControlling, @unchecked Sendable {
    static let shared = SleepHelperClient()
    static let approvalMessage = "Keep Awake needs one-time authorization. Open Keep Awake settings, then allow Mac Switch in Login Items & Extensions."
    private let queue = DispatchQueue(label: "com.maxyu.macswitch.sleep-client")
    private var connection: NSXPCConnection?
    private var service: SMAppService { .daemon(plistName: SleepHelperIdentity.plistName) }
    var isReady: Bool { service.status == .enabled }

    func authorize() -> String? { queue.sync { prepare(allowRegistration: true) } }

    private func prepare(allowRegistration: Bool) -> String? {
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
            if let error = prepare(allowRegistration: false) { return error }
            return request { $0.setLidSleepDisabled(disabled, until: deadline, reply: $1) }
        }
    }

    func restoreLegacySetting() -> String? {
        queue.sync {
            if let error = prepare(allowRegistration: false) { return error }
            return request { $0.restoreLegacySleepSetting(reply: $1) }
        }
    }

    private func request(_ operation: (any SleepHelperProtocol, @escaping (String?) -> Void) -> Void) -> String? {
        if connection == nil {
            guard let team = SleepHelperIdentity.ownTeam(),
                  let requirement = SleepHelperIdentity.requirement(identifier: SleepHelperIdentity.serviceIdentifier, team: team) else {
                return "Could not verify the Keep Awake helper identity."
            }
            let newConnection = NSXPCConnection(machServiceName: SleepHelperIdentity.serviceIdentifier, options: .privileged)
            newConnection.remoteObjectInterface = NSXPCInterface(with: SleepHelperProtocol.self)
            newConnection.setCodeSigningRequirement(requirement)
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
            connection.invalidate()
            self.connection = nil
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
