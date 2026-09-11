// SPDX-License-Identifier: GPL-3.0-only
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    let controller = BrightnessController()
    private(set) var statusItem: NSStatusItem!
    private var statusVisibilityObservation: NSKeyValueObservation?
    private var menuIsOpen = false
    private var menuPresentationPending = false
    private let toggleItem = NSMenuItem(title: "Включить XDR", action: #selector(toggle), keyEquivalent: "")
    private let statusLabel = NSTextField(wrappingLabelWithString: "Готов к включению")
    private let boostLabel = NSTextField(labelWithString: "Усиление XDR · 100%")
    private var slider: NSSlider!
    private var signalSources: [DispatchSourceSignal] = []
    private let smokeTest: Bool
    private var smokeBaseline: [CGDirectDisplayID: GammaTable] = [:]
    private var brightnessBaseline: [CGDirectDisplayID: Float] = [:]

    init(smokeTest: Bool = false) { self.smokeTest = smokeTest }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        buildMenu()
        controller.onChange = { [weak self] in self?.updateMenu() }
        observeWorkspace()
        for number in [SIGTERM, SIGINT, SIGHUP] {
            signal(number, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: number, queue: .main)
            source.setEventHandler { NSApp.terminate(nil) }
            source.resume()
            signalSources.append(source)
        }
        if smokeTest { startSmokeTest() }
        else if CommandLine.arguments.contains("--enable") { controller.maximize() }
        updateMenu()
    }

    func applicationWillTerminate(_ notification: Notification) {
        statusVisibilityObservation = nil
        controller.disable()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        showControls()
        return false
    }

    private func showControls() {
        guard let statusItem else { return }
        statusItem.isVisible = true
        updateMenu()
        guard !menuIsOpen, !menuPresentationPending else { return }
        menuPresentationPending = true
        // A visible status item can still be clipped by a crowded menu bar or
        // the camera housing. Opening the app must provide access independently.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.menuPresentationPending = false
            guard !self.menuIsOpen else { return }
            NSApp.activate(ignoringOtherApps: true)
            self.statusItem.menu?.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
        }
    }

    private func buildMenu() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.autosaveName = "BrighterStatusItem"
        // The menu bar is the app's primary interface throughout its lifetime.
        statusItem.behavior = []
        statusItem.isVisible = true
        statusVisibilityObservation = statusItem.observe(\.isVisible, options: [.new]) { [weak self] _, change in
            guard change.newValue == false else { return }
            // Avoid changing the property inside its own KVO notification.
            DispatchQueue.main.async { [weak self] in
                guard let self, self.statusVisibilityObservation != nil else { return }
                self.statusItem.isVisible = true
            }
        }
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.delegate = self
        let header = NSView(frame: NSRect(x: 0, y: 0, width: 320, height: 85))
        let title = NSTextField(labelWithString: "Brighter")
        title.font = .systemFont(ofSize: 21, weight: .semibold)
        title.frame = NSRect(x: 20, y: 51, width: 280, height: 26)
        statusLabel.font = .systemFont(ofSize: 12)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.frame = NSRect(x: 20, y: 7, width: 280, height: 38)
        header.addSubview(title)
        header.addSubview(statusLabel)
        let headerItem = NSMenuItem()
        headerItem.view = header
        menu.addItem(headerItem)
        menu.addItem(.separator())
        let maximum = NSMenuItem(title: "Максимальная яркость", action: #selector(maximize), keyEquivalent: "")
        maximum.image = NSImage(systemSymbolName: "sun.max.fill", accessibilityDescription: nil)
        maximum.target = self
        menu.addItem(maximum)
        toggleItem.target = self
        menu.addItem(toggleItem)

        let controls = NSView(frame: NSRect(x: 0, y: 0, width: 320, height: 65))
        boostLabel.font = .systemFont(ofSize: 12, weight: .medium)
        boostLabel.frame = NSRect(x: 20, y: 38, width: 280, height: 18)
        slider = NSSlider(value: 100, minValue: 0, maxValue: 100, target: self, action: #selector(sliderChanged))
        slider.frame = NSRect(x: 18, y: 9, width: 284, height: 24)
        slider.isContinuous = true
        slider.setAccessibilityLabel("Усиление XDR в процентах")
        controls.addSubview(boostLabel)
        controls.addSubview(slider)
        let controlItem = NSMenuItem()
        controlItem.view = controls
        menu.addItem(controlItem)
        menu.addItem(.separator())
        let diagnostics = NSMenuItem(title: "Диагностика…", action: #selector(showDiagnostics), keyEquivalent: "")
        diagnostics.target = self
        menu.addItem(diagnostics)
        let about = NSMenuItem(title: "О Brighter…", action: #selector(showAbout), keyEquivalent: "")
        about.target = self
        menu.addItem(about)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Выключить и выйти", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
        statusItem.menu = menu
    }

    func menuWillOpen(_ menu: NSMenu) { menuIsOpen = true; updateMenu() }
    func menuDidClose(_ menu: NSMenu) { menuIsOpen = false }

    private func updateMenu() {
        guard statusItem != nil else { return }
        let active = controller.boostedDisplayCount > 0
        statusItem.button?.image = NSImage(systemSymbolName: active ? "sun.max.fill" : "sun.max",
                                           accessibilityDescription: "Brighter")
        statusItem.button?.toolTip = "Brighter · \(controller.status)"
        statusLabel.stringValue = controller.status
        toggleItem.title = controller.enabled ? "Выключить XDR" : "Включить XDR"
        toggleItem.state = controller.enabled ? .on : .off
        slider.doubleValue = controller.amount * 100
        boostLabel.stringValue = "Усиление XDR · \(Int((controller.amount * 100).rounded()))%"
    }

    private func observeWorkspace() {
        let workspace = NSWorkspace.shared.notificationCenter
        workspace.addObserver(self, selector: #selector(spaceChanged), name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)
        workspace.addObserver(self, selector: #selector(screensSleep), name: NSWorkspace.screensDidSleepNotification, object: nil)
        workspace.addObserver(self, selector: #selector(screensWake), name: NSWorkspace.screensDidWakeNotification, object: nil)
        workspace.addObserver(self, selector: #selector(systemSleep), name: NSWorkspace.willSleepNotification, object: nil)
        workspace.addObserver(self, selector: #selector(systemWake), name: NSWorkspace.didWakeNotification, object: nil)
        workspace.addObserver(self, selector: #selector(sessionInactive), name: NSWorkspace.sessionDidResignActiveNotification, object: nil)
        workspace.addObserver(self, selector: #selector(sessionActive), name: NSWorkspace.sessionDidBecomeActiveNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(screensChanged), name: NSApplication.didChangeScreenParametersNotification, object: nil)
    }

    @objc private func maximize() { controller.maximize() }
    @objc private func toggle() { controller.enabled ? controller.disable() : controller.enable() }
    @objc private func sliderChanged() { controller.amount = slider.doubleValue / 100 }
    @objc private func quit() { NSApp.terminate(nil) }
    @objc private func spaceChanged() { controller.spaceChanged() }
    @objc private func screensChanged() { controller.screenParametersChanged() }
    @objc private func screensSleep() { controller.suspend("screens") }
    @objc private func screensWake() { controller.resume("screens") }
    @objc private func systemSleep() { controller.suspend("system") }
    @objc private func systemWake() { controller.resume("system") }
    @objc private func sessionInactive() { controller.suspend("session") }
    @objc private func sessionActive() { controller.resume("session") }

    @objc private func showAbout() {
        let alert = NSAlert()
        alert.messageText = "Brighter 1.0"
        alert.informativeText = "Бесплатное приложение для XDR-яркости.\n\n«Максимальная яркость» поднимает системную яркость и включает усиление XDR. Клавиши яркости продолжают работать. При выключении исходная яркость возвращается, если вы не изменили её вручную.\n\nДоступный максимум регулирует macOS.\nОсновано на подходе BrightIntosh · GPL-3.0."
        alert.runModal()
    }

    @objc private func showDiagnostics() {
        let alert = NSAlert()
        alert.messageText = "Диагностика Brighter"
        alert.informativeText = controller.diagnosticLines().joined(separator: "\n\n")
        alert.addButton(withTitle: "Закрыть")
        alert.addButton(withTitle: "Скопировать")
        if alert.runModal() == .alertSecondButtonReturn {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(alert.informativeText, forType: .string)
        }
    }

    private func startSmokeTest() {
        for screen in controller.supportedScreens {
            smokeBaseline[screen.displayID] = try? GammaTable.read(display: screen.displayID)
            brightnessBaseline[screen.displayID] = controller.hardware.read(screen.displayID)
        }
        print("BEFORE\n" + controller.diagnosticLines().joined(separator: "\n"))
        controller.maximize()
        for second in [2, 5, 7] {
            DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(second)) {
                print("T+\(second)\n" + self.controller.diagnosticLines().joined(separator: "\n"))
                fflush(stdout)
            }
        }
        // Exercise the same callback used after Spaces changes, without taking
        // control of the user's desktop. Physical switching is a separate check.
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            self.controller.suspend("test")
            self.controller.resume("test")
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { self.controller.spaceChanged() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 9) {
            print("ACTIVE\n" + self.controller.diagnosticLines().joined(separator: "\n"))
            let active = self.controller.boostedDisplayCount > 0 && self.controller.verifyAppliedGamma()
            let tinyWindows = NSApp.windows.filter { $0 is HDRTrigger }.allSatisfy {
                $0.frame.width <= 1 && $0.frame.height <= 1 && $0.ignoresMouseEvents && !$0.canBecomeKey
            }
            self.controller.disable()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                let restored = !self.smokeBaseline.isEmpty && self.smokeBaseline.allSatisfy { id, baseline in
                    (try? GammaTable.read(display: id)).map { baseline.approximatelyEquals($0) } ?? false
                }
                let nativeRestored = self.brightnessBaseline.allSatisfy { id, original in
                    self.controller.hardware.read(id).map { abs($0 - original) < 0.01 } ?? false
                }
                let windowsClosed = NSApp.windows.filter { $0 is HDRTrigger && $0.isVisible }.isEmpty
                print("RESTORED\n" + self.controller.diagnosticLines().joined(separator: "\n"))
                print("RESULT active=\(active) tinyWindows=\(tinyWindows) gammaRestored=\(restored) nativeRestored=\(nativeRestored) windowsClosed=\(windowsClosed)")
                fflush(stdout)
                exit(active && tinyWindows && restored && nativeRestored && windowsClosed ? 0 : 1)
            }
        }
    }
}
