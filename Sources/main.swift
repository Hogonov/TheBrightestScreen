// SPDX-License-Identifier: GPL-3.0-only
import AppKit

// Keep UI tests and direct diagnostic runs out of the production menu-bar
// identity: Tahoe can attribute their items to the app hosting the shell.
guard let identifier = Bundle.main.bundleIdentifier else {
    fputs("Open the built Brighter.app bundle instead of an unbundled executable.\n", stderr)
    exit(64)
}
let smokeTest = CommandLine.arguments.contains("--smoke-test")
if smokeTest && identifier != "local.alexandr.Brighter.Diagnostics" {
    fputs("Run bash scripts/build.sh --test, then build/BrighterDiagnostics.app/Contents/MacOS/Brighter --smoke-test.\n", stderr)
    exit(64)
}
let app = NSApplication.shared
if CommandLine.arguments.contains("--diagnose") {
    print("Current display state (read-only probe):")
    print(BrightnessController().diagnosticLines().dropFirst(2).joined(separator: "\n"))
    let names = NSWorkspace.shared.runningApplications.compactMap(\.localizedName)
        .filter { ["BrightXDR", "BrightIntosh", "Vivid", "Brighter"].contains($0) }
    print("brightnessApps=\(names.joined(separator: ", "))")
    exit(0)
}

let runningApps = NSWorkspace.shared.runningApplications.filter {
    $0.processIdentifier != ProcessInfo.processInfo.processIdentifier
}
let productionIdentifiers = ["local.alexandr.Brighter", "local.alexandr.BrighterStandalone"]
if smokeTest && runningApps.contains(where: { productionIdentifiers.contains($0.bundleIdentifier ?? "") }) {
    fputs("Close the running Brighter before starting the smoke test.\n", stderr)
    exit(2)
}
if identifier == "local.alexandr.BrighterStandalone",
   runningApps.contains(where: { $0.bundleIdentifier == "local.alexandr.Brighter" }) {
    let alert = NSAlert()
    alert.messageText = "Закройте предыдущую версию Brighter"
    alert.informativeText = "Выберите «Выключить и выйти» в старой версии, затем откройте Brighter снова. Это позволит восстановить яркость перед обновлением."
    app.activate(ignoringOtherApps: true)
    alert.runModal()
    exit(2)
}
let alreadyRunning = runningApps.first {
    $0.bundleIdentifier == identifier
}
if let alreadyRunning {
    if smokeTest {
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
let delegate = AppDelegate(smokeTest: smokeTest)
app.delegate = delegate
app.run()
