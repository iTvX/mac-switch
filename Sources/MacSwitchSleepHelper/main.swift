import Darwin
import Foundation
import MachO
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
        if let disabled = SleepPowerState.parse(try run(["-g", "live"])) { return disabled }
        throw HelperFailure(message: "macOS did not report its sleep setting.")
    }

    func setSleepDisabled(_ disabled: Bool) throws {
        _ = try run(["-a", "disablesleep", disabled ? "1" : "0"])
        guard try isSleepDisabled() == disabled else { throw HelperFailure(message: "macOS did not confirm the sleep setting.") }
    }
}

struct RecoveryStore: SleepRecoveryStoring {
    // Fixed root-owned location. There are no client-provided paths or shell commands.
    private let directory = URL(fileURLWithPath: "/var/db/com.maxyu.macswitch.sleep-helper", isDirectory: true)
    private var file: URL { directory.appendingPathComponent("recovery") }
    private func validateDirectory() throws {
        let attributes = try FileManager.default.attributesOfItem(atPath: directory.path)
        guard attributes[.type] as? FileAttributeType == .typeDirectory,
              attributes[.ownerAccountID] as? Int == 0,
              (attributes[.posixPermissions] as? Int ?? 0) & 0o022 == 0 else {
            throw HelperFailure(message: "The sleep recovery directory is not secure.")
        }
    }
    func needsRecovery() throws -> Bool {
        guard FileManager.default.fileExists(atPath: directory.path) else { return false }
        try validateDirectory()
        guard FileManager.default.fileExists(atPath: file.path) else { return false }
        let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
        guard attributes[.type] as? FileAttributeType == .typeRegular,
              attributes[.ownerAccountID] as? Int == 0 else {
            throw HelperFailure(message: "The sleep recovery record is not secure.")
        }
        return true
    }
    func setNeedsRecovery(_ value: Bool) throws {
        if value {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            try validateDirectory()
            try Data("1".utf8).write(to: file, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        } else if try needsRecovery() {
            try FileManager.default.removeItem(at: file)
        }
    }
}

guard getuid() == 0,
      let team = SleepHelperIdentity.ownTeam(),
      let requirement = SleepHelperIdentity.requirement(identifier: SleepHelperIdentity.appIdentifier, team: team) else { exit(78) }
do {
    let coordinator = try SleepLeaseCoordinator(power: SystemSleepPower(), recovery: RecoveryStore())
    let server = SleepHelperServer(coordinator: coordinator, requirement: requirement)
    let listener = NSXPCListener(machServiceName: SleepHelperIdentity.serviceIdentifier)
    listener.delegate = server
    server.start()
    var pathSize: UInt32 = 0
    _ = _NSGetExecutablePath(nil, &pathSize)
    var pathBuffer = [CChar](repeating: 0, count: Int(pathSize))
    guard _NSGetExecutablePath(&pathBuffer, &pathSize) == 0 else {
        throw HelperFailure(message: "Could not locate the sleep helper executable.")
    }
    let executable = URL(fileURLWithPath: String(cString: pathBuffer)).resolvingSymlinksInPath()
    let app = executable.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let watchedURLs = app.pathExtension == "app" ? [executable, app] : [executable]
    let replacementMonitor = try ExecutableReplacementMonitor(urls: watchedURLs) { server.stopForUpdate() }
    listener.resume()
    withExtendedLifetime((server, listener, replacementMonitor)) { dispatchMain() }
} catch { exit(1) }
