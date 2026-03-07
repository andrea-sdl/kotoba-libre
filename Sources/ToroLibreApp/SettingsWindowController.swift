import AppKit
import SwiftUI
import ToroLibreCore

@MainActor
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    private weak var appController: AppController?
    private var eventMonitor: Any?

    init(appController: AppController) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1220, height: 860),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "\(appDisplayName) - Agent Manager"
        window.center()
        window.setFrameAutosaveName("ToroLibreSettingsWindow")
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
        sender.orderOut(nil)
        return false
    }

    private func installShortcutMonitor() {
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
