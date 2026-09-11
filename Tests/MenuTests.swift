// SPDX-License-Identifier: GPL-3.0-only
import AppKit

@main
enum MenuTests {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        var openedMenus = 0
        var quietLaunch = false
        var automaticallyRestored = false
        let observer = NotificationCenter.default.addObserver(
            forName: NSMenu.didBeginTrackingNotification, object: nil, queue: .main
        ) { notification in
            guard let menu = notification.object as? NSMenu,
                  menu === delegate.statusItem?.menu else { return }
            openedMenus += 1
            let timer = Timer(timeInterval: 0.15, repeats: false) { _ in menu.cancelTracking() }
            RunLoop.main.add(timer, forMode: .common)
        }
        let timer = Timer(timeInterval: 1, repeats: false) { _ in
            quietLaunch = openedMenus == 0 && delegate.statusItem.isVisible
            delegate.statusItem.isVisible = false
        }
        RunLoop.main.add(timer, forMode: .common)
        let reopen = Timer(timeInterval: 2, repeats: false) { _ in
            // Restoration must happen on its own, before any reopen event.
            automaticallyRestored = delegate.statusItem.isVisible && openedMenus == 0
            // Visible windows can include HDR trigger windows; they must not
            // prevent recovery. Repeated events must not nest popup menus.
            _ = delegate.applicationShouldHandleReopen(app, hasVisibleWindows: true)
            _ = delegate.applicationShouldHandleReopen(app, hasVisibleWindows: true)
        }
        RunLoop.main.add(reopen, forMode: .common)
        let finish = Timer(timeInterval: 4, repeats: false) { _ in
            let visible = delegate.statusItem.isVisible
            let icon = delegate.statusItem.button?.image != nil
            let brightnessUntouched = !delegate.controller.enabled
            let nonRemovable = !delegate.statusItem.behavior.contains(.removalAllowed)
            let passed = openedMenus == 1 && quietLaunch && automaticallyRestored && visible && icon && nonRemovable && brightnessUntouched
            print("MENU RESULT openings=\(openedMenus) quietLaunch=\(quietLaunch) automaticallyRestored=\(automaticallyRestored) visible=\(visible) icon=\(icon) nonRemovable=\(nonRemovable) brightnessUntouched=\(brightnessUntouched)")
            fflush(stdout)
            NotificationCenter.default.removeObserver(observer)
            exit(passed ? 0 : 1)
        }
        RunLoop.main.add(finish, forMode: .common)
        app.run()
    }
}
