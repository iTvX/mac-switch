import XCTest
@testable import MacSwitch

final class DiagnosticExportTests: XCTestCase {
    func testSupportExportOmitsDeviceNamesAndMediaMetadata() {
        let examples: [(SwitchKind, String)] = [
            (.bluetoothAudio, "Private Person's Headphones (AA:BB:CC:DD:EE:FF)"),
            (.playMusic, "Private Artist - Unreleased Song")
        ]
        for (kind, secret) in examples {
            let output = DiagnosticExport.switchLine(kind, snapshot: .init(
                isOn: true, isAvailable: true, subtitle: secret, warning: nil
            ))
            XCTAssertFalse(output.contains(secret))
            XCTAssertTrue(output.contains("on"))
            XCTAssertTrue(output.contains("subtitle=present"))
        }
    }

    func testSupportExportOmitsFreeFormWarningsAndErrors() {
        let secret = "Private-Client-Archive on external disk; token=example-only"
        let output = DiagnosticExport.switchLine(.ejectDisk, snapshot: .init(
            isOn: false, isAvailable: false, subtitle: nil, warning: secret
        ))
        XCTAssertFalse(output.contains(secret))
        XCTAssertTrue(output.contains("unavailable"))
        XCTAssertTrue(output.contains("warning=present"))
        XCTAssertFalse(DiagnosticExport.errorSummary(secret).contains(secret))
        XCTAssertNotEqual(DiagnosticExport.errorSummary(secret), "none")
        XCTAssertEqual(DiagnosticExport.errorSummary(nil), "none")
    }

    func testAbsentDetailsRemainDistinguishable() {
        XCTAssertEqual(
            DiagnosticExport.switchLine(.playMusic, snapshot: .init(
                isOn: false, isAvailable: true, subtitle: nil, warning: nil
            )),
            "- Play Music: off (subtitle=none, warning=none)"
        )
    }
}
