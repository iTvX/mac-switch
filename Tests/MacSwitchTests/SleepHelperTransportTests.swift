import Foundation
import Security
import XCTest
import SleepHelperCore
@testable import MacSwitch

final class SleepHelperTransportTests: XCTestCase, @unchecked Sendable {
    func testProductionClientNotifiesLeaseLossAndReconnectsOverXPC() async throws {
        let power = TransportPower()
        let server = SleepHelperServer(coordinator: try SleepLeaseCoordinator(power: power, recovery: TransportRecovery()), requirement: try currentProcessRequirement())
        let harness = DisconnectableListener(server: server)
        defer { harness.close() }
        let client = SleepHelperClient(connectionFactory: { harness.connect() }, serviceValidation: { nil })
        let disconnected = expectation(description: "Production invalidation handler reports the lost lease")
        let observer = try XCTUnwrap(client.observeLeaseLoss { disconnected.fulfill() })
        XCTAssertNil(client.setDisabled(true, until: nil))
        XCTAssertTrue(power.disabled)
        harness.disconnectPeer()
        await fulfillment(of: [disconnected], timeout: 3)
        client.removeLeaseObserver(observer)
        for _ in 0..<100 where power.disabled { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertFalse(power.disabled)
        XCTAssertNil(client.setDisabled(true, until: Date().addingTimeInterval(60)))
        XCTAssertTrue(power.disabled)
        XCTAssertNil(client.setDisabled(false, until: nil))
        XCTAssertFalse(power.disabled)
    }

    func testAuthenticatedXPCRequestsAndDisconnectCleanup() async throws {
        let power = TransportPower()
        let recovery = TransportRecovery()
        let coordinator = try SleepLeaseCoordinator(power: power, recovery: recovery)
        let requirement = try currentProcessRequirement()
        let server = SleepHelperServer(coordinator: coordinator, requirement: requirement)
        server.start(installSignalHandlers: false)
        let listener = NSXPCListener.anonymous()
        listener.delegate = server
        listener.resume()
        defer { listener.invalidate() }
        let connection = NSXPCConnection(listenerEndpoint: listener.endpoint)
        connection.remoteObjectInterface = NSXPCInterface(with: SleepHelperProtocol.self)
        connection.setCodeSigningRequirement(requirement)
        connection.resume()
        defer { connection.invalidate() }
        for enabled in [true, false, true, true] {
            let completed = expectation(description: "XPC request \(enabled)")
            let proxy = try XCTUnwrap(connection.remoteObjectProxyWithErrorHandler { error in
                XCTFail(error.localizedDescription)
                completed.fulfill()
            } as? any SleepHelperProtocol)
            proxy.setLidSleepDisabled(enabled, until: Date().addingTimeInterval(60)) { error in
                XCTAssertNil(error)
                completed.fulfill()
            }
            await fulfillment(of: [completed], timeout: 3)
            XCTAssertEqual(power.disabled, enabled)
        }
        XCTAssertEqual(power.writes, [true, false, true], "Updating a lease does not cycle the system setting")
        connection.invalidate()
        for _ in 0..<100 where power.disabled { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertFalse(power.disabled)
        XCTAssertFalse(recovery.pending)
        withExtendedLifetime(server) {}
    }

    func testXPCRejectsAnUnexpectedPeerBeforeMutatingPower() async throws {
        let power = TransportPower()
        let server = SleepHelperServer(coordinator: try SleepLeaseCoordinator(power: power, recovery: TransportRecovery()), requirement: "identifier \"invalid.peer.identifier\"")
        let listener = NSXPCListener.anonymous()
        listener.delegate = server
        listener.resume()
        defer { listener.invalidate() }
        let connection = NSXPCConnection(listenerEndpoint: listener.endpoint)
        connection.remoteObjectInterface = NSXPCInterface(with: SleepHelperProtocol.self)
        connection.resume()
        defer { connection.invalidate() }
        let rejected = expectation(description: "Wrong peer rejected")
        let proxy = try XCTUnwrap(connection.remoteObjectProxyWithErrorHandler { _ in rejected.fulfill() } as? any SleepHelperProtocol)
        proxy.setLidSleepDisabled(true, until: nil) { _ in XCTFail("Untrusted peer reached the service") }
        await fulfillment(of: [rejected], timeout: 3)
        XCTAssertTrue(power.writes.isEmpty)
        withExtendedLifetime(server) {}
    }

    func testAtomicAppReplacementNotifiesTheHelper() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let app = directory.appendingPathComponent("Example.app")
        try FileManager.default.createDirectory(at: app, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let replaced = expectation(description: "App replacement observed")
        let monitor = try ExecutableReplacementMonitor(urls: [app]) { replaced.fulfill() }
        try FileManager.default.moveItem(at: app, to: directory.appendingPathComponent("old.app"))
        await fulfillment(of: [replaced], timeout: 3)
        withExtendedLifetime(monitor) {}
    }

    private func currentProcessRequirement() throws -> String {
        var dynamic: SecCode?, code: SecStaticCode?, requirement: SecRequirement?, text: CFString?
        XCTAssertEqual(SecCodeCopySelf([], &dynamic), errSecSuccess)
        XCTAssertEqual(SecCodeCopyStaticCode(try XCTUnwrap(dynamic), [], &code), errSecSuccess)
        XCTAssertEqual(SecCodeCopyDesignatedRequirement(try XCTUnwrap(code), [], &requirement), errSecSuccess)
        XCTAssertEqual(SecRequirementCopyString(try XCTUnwrap(requirement), [], &text), errSecSuccess)
        return try XCTUnwrap(text) as String
    }
}

private final class DisconnectableListener: NSObject, NSXPCListenerDelegate, @unchecked Sendable {
    private let server: SleepHelperServer
    private let listener = NSXPCListener.anonymous()
    private let lock = NSLock()
    private var peers: [NSXPCConnection] = []
    init(server: SleepHelperServer) {
        self.server = server
        super.init()
        listener.delegate = self
        listener.resume()
    }
    func connect() -> NSXPCConnection { NSXPCConnection(listenerEndpoint: listener.endpoint) }
    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        lock.withLock { peers.append(connection) }
        return server.listener(listener, shouldAcceptNewConnection: connection)
    }
    func disconnectPeer() { lock.withLock { peers }.forEach { $0.invalidate() } }
    func close() { disconnectPeer(); listener.invalidate() }
}

private final class TransportPower: SleepPowerControlling, @unchecked Sendable {
    private let lock = NSLock()
    private var state = false
    private var recorded: [Bool] = []
    var disabled: Bool { lock.withLock { state } }
    var writes: [Bool] { lock.withLock { recorded } }
    func isSleepDisabled() throws -> Bool { disabled }
    func setSleepDisabled(_ disabled: Bool) throws { lock.withLock { state = disabled; recorded.append(disabled) } }
}
private final class TransportRecovery: SleepRecoveryStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var state = false
    var pending: Bool { lock.withLock { state } }
    func needsRecovery() throws -> Bool { pending }
    func setNeedsRecovery(_ value: Bool) throws { lock.withLock { state = value } }
}
