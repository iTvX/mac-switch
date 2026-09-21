import Darwin
import Foundation

public final class SleepHelperServer: NSObject, NSXPCListenerDelegate, @unchecked Sendable {
    let queue = DispatchQueue(label: "com.maxyu.macswitch.sleep-helper")
    let coordinator: SleepLeaseCoordinator
    let requirement: String
    private var timer: DispatchSourceTimer?
    private var signals: [DispatchSourceSignal] = []
    public init(coordinator: SleepLeaseCoordinator, requirement: String) {
        self.coordinator = coordinator
        self.requirement = requirement
    }

    public func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        // Foundation validates every message against the peer's code identity (not a racy PID check).
        connection.setCodeSigningRequirement(requirement)
        let owner = UUID()
        connection.exportedInterface = NSXPCInterface(with: SleepHelperProtocol.self)
        connection.exportedObject = ClientSession(server: self, owner: owner)
        connection.invalidationHandler = { [weak self] in
            self?.queue.async { [weak self] in
                guard let self else { return }
                try? self.coordinator.disconnect(owner)
                self.scheduleRecoveryOrExpiration()
            }
        }
        connection.resume()
        return true
    }

    public func start(installSignalHandlers: Bool = true) {
        queue.async {
            try? self.coordinator.expire()
            self.scheduleRecoveryOrExpiration()
        }
        guard installSignalHandlers else { return }
        for number in [SIGTERM, SIGINT] {
            signal(number, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: number, queue: queue)
            source.setEventHandler { [self] in
                do { try coordinator.shutdown(); exit(0) }
                catch { exit(1) } // The recovery journal survives termination.
            }
            source.resume()
            signals.append(source)
        }
    }

    public func stopForUpdate() {
        queue.async {
            do { try self.coordinator.shutdown(); exit(0) }
            catch { exit(1) }
        }
    }

    func scheduleRecoveryOrExpiration() {
        timer?.cancel()
        timer = nil
        let retryDate = coordinator.needsRestoreRetry ? Date().addingTimeInterval(5) : nil
        guard let date = [coordinator.nextDeadline, retryDate].compactMap({ $0 }).min() else { return }
        let source = DispatchSource.makeTimerSource(queue: queue)
        source.schedule(deadline: .now() + min(86_400, max(0, date.timeIntervalSinceNow)))
        source.setEventHandler { [weak self] in
            guard let self else { return }
            try? self.coordinator.expire()
            self.scheduleRecoveryOrExpiration()
        }
        source.resume()
        timer = source
    }
}

final class Reply: @unchecked Sendable {
    let block: (String?) -> Void
    init(_ block: @escaping (String?) -> Void) { self.block = block }
}

final class ClientSession: NSObject, SleepHelperProtocol, @unchecked Sendable {
    let server: SleepHelperServer
    let owner: UUID
    init(server: SleepHelperServer, owner: UUID) { self.server = server; self.owner = owner }
    func setLidSleepDisabled(_ disabled: Bool, until deadline: Date?, reply: @escaping (String?) -> Void) {
        let reply = Reply(reply)
        server.queue.async { [self] in
            do {
                guard deadline?.timeIntervalSince1970.isFinite ?? true else { throw NSError(domain: SleepHelperIdentity.serviceIdentifier, code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid session deadline."]) }
                try server.coordinator.set(disabled, owner: owner, deadline: deadline)
                reply.block(nil)
            } catch { reply.block(error.localizedDescription) }
            server.scheduleRecoveryOrExpiration()
        }
    }
    func restoreLegacySleepSetting(reply: @escaping (String?) -> Void) {
        let reply = Reply(reply)
        server.queue.async { [self] in
            do { try server.coordinator.restoreLegacySetting(); reply.block(nil) }
            catch { reply.block(error.localizedDescription) }
            server.scheduleRecoveryOrExpiration()
        }
    }
}
