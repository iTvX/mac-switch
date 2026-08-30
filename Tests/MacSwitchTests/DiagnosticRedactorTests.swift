import XCTest
@testable import MacSwitch

final class DiagnosticRedactorTests: XCTestCase {
    func testRedactsArbitraryMacOSAndLinuxHomeDirectories() {
        let macOSHomePath = ["", "Users", "example", "Applications", "Mac Switch.app"].joined(separator: "/")
        let linuxHomePath = ["", "home", "example", ".config", "mac-switch"].joined(separator: "/")
        XCTAssertEqual(
            DiagnosticRedactor.redact(macOSHomePath),
            "~/Applications/Mac Switch.app"
        )
        XCTAssertEqual(
            DiagnosticRedactor.redact(linuxHomePath),
            "~/.config/mac-switch"
        )
    }
}
