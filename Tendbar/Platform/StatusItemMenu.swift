import AppKit

/// A right click on the menu bar item opens a short menu (Settings, updates, Quit); a left click still opens the
/// panel. SwiftUI's `MenuBarExtra` has no context menu, so a local monitor takes right clicks on the item's own
/// window and lets every other event through untouched.
@MainActor
final class StatusItemMenu: NSObject {
    /// Set by a SwiftUI view, since only a view can open the Settings scene.
    var openSettings: (() -> Void)?
    var updates: SoftwareUpdate?
    private var monitor: Any?

    func start() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .rightMouseDown) { [weak self] event in
            guard let self, let window = event.window, Self.isStatusItem(window), let button = window.contentView else {
                return event
            }
            self.show(under: button)
            return nil
        }
    }

    /// Local events only reach this app's windows, so a status bar window here is Tendbar's own item.
    private static func isStatusItem(_ window: NSWindow) -> Bool {
        String(describing: type(of: window)).contains("StatusBarWindow")
    }

    private func show(under button: NSView) {
        let menu = NSMenu()
        if openSettings != nil {
            menu.addItem(item(String(localized: "Settings…"), action: #selector(settings), key: ","))
        }
        if updates?.isAvailable == true {
            menu.addItem(item(String(localized: "Check for updates…"), action: #selector(checkForUpdates)))
        }
        if !menu.items.isEmpty { menu.addItem(.separator()) }
        menu.addItem(item(String(localized: "Quit Tendbar"), action: #selector(quit), key: "q"))
        let y = button.isFlipped ? button.bounds.maxY + 4 : -4
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: y), in: button)
    }

    private func item(_ title: String, action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    @objc private func settings() {
        openSettings?()
    }

    @objc private func checkForUpdates() {
        updates?.checkNow()
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }
}
