import Carbon.HIToolbox
import Foundation

/// The keys that jump to the next session from any app. Off by default, since a global shortcut takes the keys
/// away from every other app.
enum NextSessionShortcut: String, CaseIterable, Identifiable {
    case off, controlOptionJ, controlOptionCommandJ, controlOptionSpace
    var id: Self { self }

    var symbols: String? {
        switch self {
        case .off: nil
        case .controlOptionJ: "⌃⌥J"
        case .controlOptionCommandJ: "⌃⌥⌘J"
        case .controlOptionSpace: String(localized: "⌃⌥Space")
        }
    }

    fileprivate var key: (code: UInt32, modifiers: UInt32)? {
        switch self {
        case .off: nil
        case .controlOptionJ: (UInt32(kVK_ANSI_J), UInt32(controlKey | optionKey))
        case .controlOptionCommandJ: (UInt32(kVK_ANSI_J), UInt32(controlKey | optionKey | cmdKey))
        case .controlOptionSpace: (UInt32(kVK_Space), UInt32(controlKey | optionKey))
        }
    }
}

/// One system-wide shortcut through Carbon's hot keys, which need no Accessibility permission.
@MainActor
final class GlobalShortcut {
    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private let action: () -> Void

    init(action: @escaping () -> Void) {
        self.action = action
    }

    /// Registers the shortcut, replacing the previous one. Returns false when another app already holds the keys.
    @discardableResult
    func register(_ shortcut: NextSessionShortcut) -> Bool {
        unregister()
        guard let key = shortcut.key else { return true }
        installHandler()
        let id = EventHotKeyID(signature: OSType(0x5444_4E42), id: 1) // "TDNB"
        return RegisterEventHotKey(key.code, key.modifiers, id, GetApplicationEventTarget(), 0, &hotKey) == noErr
    }

    private func unregister() {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        hotKey = nil
    }

    private func installHandler() {
        guard handler == nil else { return }
        var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let context = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, _, context in
            guard let context else { return noErr }
            let shortcut = Unmanaged<GlobalShortcut>.fromOpaque(context).takeUnretainedValue()
            MainActor.assumeIsolated { shortcut.action() }
            return noErr
        }, 1, &type, context, &handler)
    }
}
