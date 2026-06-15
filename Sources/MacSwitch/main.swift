import AppKit

if CommandLine.arguments.contains("--self-test-safe") {
    let exitCode = RegressionDiagnostics.runSafe()
    exit(exitCode)
}

let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate
application.run()
