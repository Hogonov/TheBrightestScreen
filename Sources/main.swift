// SPDX-License-Identifier: GPL-3.0-only
import AppKit

let app = NSApplication.shared
if CommandLine.arguments.contains("--diagnose") {
    print("Current display state (read-only probe):")
    print(BrightnessController().diagnosticLines().dropFirst(2).joined(separator: "\n"))
    let names = NSWorkspace.shared.runningApplications.compactMap(\.localizedName)
        .filter { ["BrightXDR", "BrightIntosh", "Vivid", "Brighter"].contains($0) }
    print("brightnessApps=\(names.joined(separator: ", "))")
    exit(0)
}

let identifier = Bundle.main.bundleIdentifier ?? "local.alexandr.Brighter"
let alreadyRunning = NSWorkspace.shared.runningApplications.first {
    $0.bundleIdentifier == identifier && $0.processIdentifier != ProcessInfo.processInfo.processIdentifier
}
if let alreadyRunning {
    if CommandLine.arguments.contains("--smoke-test") {
        print("Close the running Brighter before starting the smoke test.")
        exit(2)
    }
    // Forward direct executable / second-copy launches to the existing app so
    // its reopen handler can recover access even when the sun icon is hidden.
    guard let url = alreadyRunning.bundleURL else { exit(1) }
    let configuration = NSWorkspace.OpenConfiguration()
    configuration.createsNewApplicationInstance = false
    configuration.activates = true
    NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, error in
        if let error { fputs("Could not reopen Brighter: \(error.localizedDescription)\n", stderr) }
        exit(error == nil ? 0 : 1)
    }
    app.run()
    exit(0)
}
let delegate = AppDelegate(smokeTest: CommandLine.arguments.contains("--smoke-test"))
app.delegate = delegate
app.run()
