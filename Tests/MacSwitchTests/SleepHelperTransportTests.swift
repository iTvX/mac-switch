import Foundation
import Security
import XCTest
import SleepHelperCore

final class SleepHelperTransportTests: XCTestCase, @unchecked Sendable {
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

    private func currentProcessRequirement() throws -> String {
        var dynamic: SecCode?, code: SecStaticCode?, requirement: SecRequirement?, text: CFString?
        XCTAssertEqual(SecCodeCopySelf([], &dynamic), errSecSuccess)
        XCTAssertEqual(SecCodeCopyStaticCode(try XCTUnwrap(dynamic), [], &code), errSecSuccess)
        XCTAssertEqual(SecCodeCopyDesignatedRequirement(try XCTUnwrap(code), [], &requirement), errSecSuccess)
        XCTAssertEqual(SecRequirementCopyString(try XCTUnwrap(requirement), [], &text), errSecSuccess)
        return try XCTUnwrap(text) as String
    }
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
