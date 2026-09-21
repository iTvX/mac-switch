import Darwin
import Foundation
import SleepHelperCore

struct HelperFailure: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

struct SystemSleepPower: SleepPowerControlling {
    private func run(_ arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        process.arguments = arguments
        process.environment = ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "LC_ALL": "C"]
        process.standardInput = FileHandle.nullDevice
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        let done = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in done.signal() }
        try process.run()
        if done.wait(timeout: .now() + 5) != .success {
            process.terminate()
            if done.wait(timeout: .now() + 1) != .success { kill(process.processIdentifier, SIGKILL) }
            throw HelperFailure(message: "The system sleep request timed out.")
        }
        guard process.terminationStatus == 0 else { throw HelperFailure(message: "macOS rejected the sleep setting.") }
        return String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    }

    func isSleepDisabled() throws -> Bool {
        for line in try run(["-g", "live"]).split(separator: "\n") {
            let fields = line.split(whereSeparator: \.isWhitespace)
            if fields.first == "SleepDisabled", fields.count == 2, ["0", "1"].contains(fields[1]) { return fields[1] == "1" }
        }
        throw HelperFailure(message: "macOS did not report its sleep setting.")
    }

    func setSleepDisabled(_ disabled: Bool) throws {
        _ = try run(["-a", "disablesleep", disabled ? "1" : "0"])
        guard try isSleepDisabled() == disabled else { throw HelperFailure(message: "macOS did not confirm the sleep setting.") }
    }
}

struct RecoveryStore: SleepRecoveryStoring {
    // Fixed root-owned location. There are no client-provided paths or shell commands.
    private let directory = URL(fileURLWithPath: "/Library/Application Support/MacSwitchSleepHelper", isDirectory: true)
    private var file: URL { directory.appendingPathComponent("recovery") }
    func needsRecovery() throws -> Bool { FileManager.default.fileExists(atPath: file.path) }
    func setNeedsRecovery(_ value: Bool) throws {
        if value {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            let attributes = try FileManager.default.attributesOfItem(atPath: directory.path)
            guard attributes[.type] as? FileAttributeType == .typeDirectory,
                  attributes[.ownerAccountID] as? Int == 0,
                  (attributes[.posixPermissions] as? Int ?? 0) & 0o022 == 0 else {
                throw HelperFailure(message: "The sleep recovery directory is not secure.")
            }
            try Data("1".utf8).write(to: file, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        } else if FileManager.default.fileExists(atPath: file.path) {
            try FileManager.default.removeItem(at: file)
        }
    }
}

final class HelperServer: NSObject, NSXPCListenerDelegate, @unchecked Sendable {
    let queue = DispatchQueue(label: "com.maxyu.macswitch.sleep-helper")
    let coordinator: SleepLeaseCoordinator
    let requirement: String
    private var timer: DispatchSourceTimer?
    private var signals: [DispatchSourceSignal] = []
    init(coordinator: SleepLeaseCoordinator, requirement: String) {
        self.coordinator = coordinator
        self.requirement = requirement
    }

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
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

    func start() {
        queue.async {
            try? self.coordinator.expire()
            self.scheduleRecoveryOrExpiration()
        }
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

    func scheduleRecoveryOrExpiration() {
        timer?.cancel()
        timer = nil
        let retryDate = coordinator.needsRestoreRetry ? Date().addingTimeInterval(5) : nil
        guard let date = [coordinator.nextDeadline, retryDate].compactMap({ $0 }).min() else { return }
        let source = DispatchSource.makeTimerSource(queue: queue)
        source.schedule(deadline: .now() + max(0, date.timeIntervalSinceNow))
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
    let server: HelperServer
    let owner: UUID
    init(server: HelperServer, owner: UUID) { self.server = server; self.owner = owner }
    func setLidSleepDisabled(_ disabled: Bool, until deadline: Date?, reply: @escaping (String?) -> Void) {
        let reply = Reply(reply)
        server.queue.async { [self] in
            do {
                guard deadline?.timeIntervalSince1970.isFinite ?? true else { throw HelperFailure(message: "Invalid session deadline.") }
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

guard getuid() == 0,
      let team = SleepHelperIdentity.ownTeam(),
      let requirement = SleepHelperIdentity.requirement(identifier: SleepHelperIdentity.appIdentifier, team: team) else { exit(78) }
do {
    let coordinator = try SleepLeaseCoordinator(power: SystemSleepPower(), recovery: RecoveryStore())
    let server = HelperServer(coordinator: coordinator, requirement: requirement)
    let listener = NSXPCListener(machServiceName: SleepHelperIdentity.serviceIdentifier)
    listener.delegate = server
    server.start()
    listener.resume()
    RunLoop.current.run()
} catch { exit(1) }
