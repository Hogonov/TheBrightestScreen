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
let alreadyRunning = NSWorkspace.shared.runningApplications.contains {
    $0.bundleIdentifier == identifier && $0.processIdentifier != ProcessInfo.processInfo.processIdentifier
}
guard !alreadyRunning else {
    print("Brighter is already running. Use the sun icon in the menu bar.")
    exit(CommandLine.arguments.contains("--smoke-test") ? 2 : 0)
}
let delegate = AppDelegate(smokeTest: CommandLine.arguments.contains("--smoke-test"))
app.delegate = delegate
app.run()
