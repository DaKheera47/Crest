import AppKit

/// Owns the native lifetime of one held-Control gesture, in its original
/// window. Cancellation never changes the underlying tab or first responder.
@MainActor
final class BrowserTabSwitcherKeyboardSession: NSObject {
    // MARK: - Variables

    private let model: BrowserTabSwitcherModel
    private let shortcuts: BrowserShortcutStore
    private weak var window: NSWindow?

    var isActive: Bool { model.isPresented }

    // MARK: - Initializers

    init(model: BrowserTabSwitcherModel, window: NSWindow, shortcuts: BrowserShortcutStore) {
        self.model = model
        self.shortcuts = shortcuts
        self.window = window
        super.init()
        let center = NotificationCenter.default
        for name in [NSWindow.didResignKeyNotification, NSWindow.willCloseNotification] {
            center.addObserver(self, selector: #selector(cancel), name: name, object: window)
        }
        center.addObserver(
            self, selector: #selector(cancel), name: NSApplication.didResignActiveNotification, object: NSApp)
    }

    isolated deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Actions - Input

    /// The default binding becomes a held gesture. Exact custom assignments,
    /// including Control-Shift-Tab, retain priority over its reverse alias.
    static func begins(_ event: NSEvent, shortcuts: BrowserShortcutStore) -> Bool {
        guard event.type == .keyDown, event.keyCode == 48,
            shortcuts.shortcut(for: .mostRecentTab) == ShortcutCommand.mostRecentTab.defaultShortcut,
            let chord = BrowserShortcut(event: event),
            chord.modifiers == .control || chord.modifiers == [.control, .shift]
        else { return false }
        return chord.modifiers == .control || shortcuts.commands(assignedTo: chord).isEmpty
    }

    /// Modifier releases pass through to the other native observers. Only
    /// switcher navigation and Escape are consumed.
    func handle(_ event: NSEvent, keyWindow: NSWindow?) -> Bool {
        guard isActive, let window, keyWindow === window,
            NSApp.modalWindow == nil, window.attachedSheet == nil,
            shortcuts.shortcut(for: .mostRecentTab) == ShortcutCommand.mostRecentTab.defaultShortcut,
            event.modifierFlags.intersection([.command, .option]).isEmpty
        else {
            cancel()
            return false
        }
        if event.type == .flagsChanged {
            if !event.modifierFlags.contains(.control) { model.commit() }
            return false
        }
        guard event.type == .keyDown else { return false }
        if event.keyCode == 53 {
            cancel()
            return true
        }
        guard event.keyCode == 48, event.modifierFlags.contains(.control) else {
            cancel()
            return false
        }
        if let chord = BrowserShortcut(event: event), chord.modifiers.contains(.shift),
            !shortcuts.commands(assignedTo: chord).isEmpty
        {
            cancel()
            return false
        }
        model.advance(reversed: event.modifierFlags.contains(.shift))
        return true
    }

    @objc private func cancel() {
        model.cancel()
    }
}
