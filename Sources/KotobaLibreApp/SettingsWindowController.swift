import AppKit
import SwiftUI
import KotobaLibreCore

// This controller hosts the SwiftUI settings tabs inside a standard AppKit window.
@MainActor
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    private weak var appController: AppController?
    private var eventMonitor: Any?

    var isVisible: Bool {
        window?.isVisible ?? false
    }

    init(appController: AppController) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1220, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "\(appDisplayName) Settings"
        window.center()
        window.setFrameAutosaveName("KotobaLibreSettingsWindow")
        super.init(window: window)
        self.appController = appController
        self.window?.delegate = self
        self.window?.contentViewController = NSHostingController(rootView: SettingsRootView(appController: appController))
        installShortcutMonitor()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func showAndFocus() {
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func hide() {
        window?.orderOut(nil)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        // Hiding instead of destroying keeps the window fast to reopen and preserves tab state.
        sender.orderOut(nil)
        return false
    }

    private func installShortcutMonitor() {
        // Returning nil tells AppKit that the key event was handled and should not continue.
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard
                let self,
                let window = self.window,
                event.window == window,
                self.appController?.handleShortcutKeyEvent(event) == true
            else {
                return event
            }

            return nil
        }
    }
}
