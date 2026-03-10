import AppKit
import SwiftUI
import KotobaLibreCore

// These bounds keep the settings window comfortably readable while still fitting on smaller displays.
private let minimumSettingsContentSize = NSSize(width: 980, height: 640)

// AutoSizingHostingController reports SwiftUI's fitted size back to AppKit so the window can follow it.
@MainActor
private final class AutoSizingHostingController<Content: View>: NSHostingController<Content> {
    var onFittingSizeChange: ((NSSize) -> Void)?
    private var lastReportedSize = NSSize.zero

    override func viewDidLayout() {
        super.viewDidLayout()
        reportFittingSizeIfNeeded()
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        reportFittingSizeIfNeeded()
    }

    private func reportFittingSizeIfNeeded() {
        view.layoutSubtreeIfNeeded()
        let fittingSize = view.fittingSize
        guard fittingSize.width > 0, fittingSize.height > 0 else {
            return
        }

        guard
            abs(lastReportedSize.width - fittingSize.width) >= 1 ||
            abs(lastReportedSize.height - fittingSize.height) >= 1
        else {
            return
        }

        lastReportedSize = fittingSize
        preferredContentSize = fittingSize
        onFittingSizeChange?(fittingSize)
    }
}

// This controller hosts the SwiftUI settings tabs inside a standard AppKit window.
@MainActor
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    private weak var appController: AppController?
    private var eventMonitor: Any?
    private let hostingController: AutoSizingHostingController<SettingsRootView>

    var isVisible: Bool {
        window?.isVisible ?? false
    }

    init(appController: AppController) {
        let hostingController = AutoSizingHostingController(rootView: SettingsRootView(appController: appController))
        self.hostingController = hostingController
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1220, height: 680),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "\(appDisplayName) Settings"
        window.center()
        window.setFrameAutosaveName("KotobaLibreSettingsWindow")
        window.contentMinSize = minimumSettingsContentSize
        super.init(window: window)
        self.appController = appController
        self.window?.delegate = self
        if #available(macOS 13.0, *) {
            self.hostingController.sizingOptions = [.preferredContentSize]
        }
        self.hostingController.onFittingSizeChange = { [weak self] fittingSize in
            self?.resizeWindowHeightToFitContent(fittingSize)
        }
        self.window?.contentViewController = self.hostingController
        installShortcutMonitor()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func showAndFocus() {
        resizeWindowHeightToFitContent(hostingController.preferredContentSize)
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

    private func resizeWindowHeightToFitContent(_ fittingSize: NSSize) {
        guard let window else {
            return
        }

        let currentContentRect = window.contentRect(forFrameRect: window.frame)
        let targetContentHeight = max(minimumSettingsContentSize.height, fittingSize.height)
        let targetContentWidth = max(minimumSettingsContentSize.width, currentContentRect.width, fittingSize.width)

        guard
            abs(currentContentRect.height - targetContentHeight) >= 1 ||
            abs(currentContentRect.width - targetContentWidth) >= 1
        else {
            return
        }

        window.contentMinSize = NSSize(
            width: minimumSettingsContentSize.width,
            height: targetContentHeight
        )

        var nextFrame = window.frameRect(
            forContentRect: NSRect(origin: .zero, size: NSSize(width: targetContentWidth, height: targetContentHeight))
        )
        nextFrame.origin.x = window.frame.origin.x
        nextFrame.origin.y = window.frame.maxY - nextFrame.height
        window.setFrame(nextFrame, display: true, animate: window.isVisible)
    }
}
