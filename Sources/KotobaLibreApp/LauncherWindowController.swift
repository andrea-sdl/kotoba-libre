import AppKit
import SwiftUI
import KotobaLibreCore

private enum LauncherPanelMetrics {
    static let preferredWidth: CGFloat = 860
    static let minimumWidth: CGFloat = 560
    static let preferredHeight: CGFloat = 138
    static let horizontalInset: CGFloat = 32
    static let topInset: CGFloat = 88
    static let bottomInset: CGFloat = 24
}

final class LauncherPanel: NSPanel {
    init() {
        super.init(
            contentRect: NSRect(
                origin: .zero,
                size: NSSize(width: LauncherPanelMetrics.preferredWidth, height: LauncherPanelMetrics.preferredHeight)
            ),
            styleMask: [.nonactivatingPanel, .titled, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        title = "Kotoba Libre Launcher"
        isFloatingPanel = false
        level = .floating
        collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary, .transient, .ignoresCycle]
        isReleasedWhenClosed = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        hidesOnDeactivate = false
        isMovableByWindowBackground = false
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        animationBehavior = .utilityWindow

        standardWindowButton(.closeButton)?.isHidden = true
        standardWindowButton(.miniaturizeButton)?.isHidden = true
        standardWindowButton(.zoomButton)?.isHidden = true
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class LauncherWindowController: NSWindowController, NSWindowDelegate {
    private weak var appController: AppController?
    private let viewModel: LauncherViewModel
    private var eventMonitor: Any?
    private var previouslyFrontmostApplication: NSRunningApplication?

    var isVisible: Bool {
        window?.isVisible ?? false
    }

    init(appController: AppController) {
        self.appController = appController
        self.viewModel = LauncherViewModel(appController: appController)

        let panel = LauncherPanel()
        super.init(window: panel)

        panel.delegate = self
        panel.contentView = NSHostingView(rootView: LauncherRootView(viewModel: viewModel))
        installKeyboardMonitor()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func prepare() {
        hide()
    }

    func showAndFocus() {
        let frontmostApplication = NSWorkspace.shared.frontmostApplication
        previouslyFrontmostApplication = frontmostApplication == NSRunningApplication.current ? nil : frontmostApplication

        viewModel.refresh()
        positionPanelOnActiveDisplay()
        NSApp.activate(ignoringOtherApps: true)
        window?.orderFrontRegardless()
        window?.makeKeyAndOrderFront(nil)
        viewModel.focusToken = UUID()
    }

    func hide() {
        window?.orderOut(nil)
        viewModel.reset()
        restorePreviouslyFrontmostApplicationIfNeeded()
    }

    func windowDidResignKey(_ notification: Notification) {
        guard isVisible else {
            return
        }

        hide()
    }

    func windowDidResignMain(_ notification: Notification) {
        guard isVisible else {
            return
        }

        hide()
    }

    private func restorePreviouslyFrontmostApplicationIfNeeded() {
        guard let previousApplication = previouslyFrontmostApplication else {
            return
        }

        previouslyFrontmostApplication = nil
        guard previousApplication != NSRunningApplication.current else {
            return
        }

        DispatchQueue.main.async {
            previousApplication.activate(options: [.activateIgnoringOtherApps])
        }
    }

    private func installKeyboardMonitor() {
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.window == self.window else {
                return event
            }

            switch event.keyCode {
            case 53:
                self.hide()
                return nil
            case 36, 76:
                self.viewModel.submit()
                return nil
            default:
                return event
            }
        }
    }

    private func positionPanelOnActiveDisplay() {
        guard let window else {
            return
        }

        let targetScreen = screenContainingMouse() ?? window.screen ?? NSScreen.main
        let frame = frameForPresentation(on: targetScreen)
        window.setFrame(frame, display: false)
    }

    private func screenContainingMouse() -> NSScreen? {
        let mouseLocation = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(mouseLocation, $0.frame, false) }
    }

    private func frameForPresentation(on screen: NSScreen?) -> NSRect {
        let fallbackVisibleFrame = NSRect(x: 0, y: 0, width: LauncherPanelMetrics.preferredWidth, height: 900)
        let visibleFrame = screen?.visibleFrame ?? fallbackVisibleFrame

        let availableWidth = visibleFrame.width - (LauncherPanelMetrics.horizontalInset * 2)
        let minimumWidth = min(LauncherPanelMetrics.minimumWidth, visibleFrame.width)
        let width = min(
            LauncherPanelMetrics.preferredWidth,
            max(minimumWidth, availableWidth)
        )
        let height = LauncherPanelMetrics.preferredHeight

        let originX = visibleFrame.midX - (width / 2)
        let originY = max(
            visibleFrame.minY + LauncherPanelMetrics.bottomInset,
            visibleFrame.maxY - LauncherPanelMetrics.topInset - height
        )

        return NSRect(x: originX, y: originY, width: width, height: height)
    }
}

@MainActor
final class LauncherViewModel: ObservableObject {
    @Published var query = ""
    @Published var selectedPresetID: String?
    @Published var statusMessage = ""
    @Published var isError = false
    @Published var focusToken = UUID()

    private weak var appController: AppController?

    init(appController: AppController) {
        self.appController = appController
    }

    var presets: [Preset] {
        guard let appController else {
            return []
        }

        let defaultPresetID = appController.settings.defaultPresetId
        return appController.presets.sorted { lhs, rhs in
            let lhsDefault = lhs.id == defaultPresetID ? 1 : 0
            let rhsDefault = rhs.id == defaultPresetID ? 1 : 0
            if lhsDefault != rhsDefault {
                return lhsDefault > rhsDefault
            }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    var opacity: Double {
        appController?.settings.launcherOpacity ?? 0.95
    }

    func refresh() {
        statusMessage = ""
        isError = false

        if selectedPresetID == nil {
            selectedPresetID = appController?.settings.defaultPresetId ?? presets.first?.id
        }

        if appController?.settings.instanceBaseUrl == nil {
            setStatus("Configure instance URL first.", isError: true)
        } else if presets.isEmpty {
            setStatus("No agents configured yet. Add one in Settings.", isError: true)
        }
    }

    func submit() {
        guard let appController else {
            return
        }

        guard let targetID = selectedPresetID ?? presets.first?.id else {
            setStatus("No agent selected.", isError: true)
            return
        }

        do {
            try appController.openPreset(
                id: targetID,
                query: query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : query,
                preferMainWindow: true
            )
            reset()
        } catch {
            setStatus(error.localizedDescription, isError: true)
        }
    }

    func reset() {
        query = ""
        selectedPresetID = appController?.settings.defaultPresetId ?? presets.first?.id
        statusMessage = ""
        isError = false
    }

    private func setStatus(_ message: String, isError: Bool) {
        statusMessage = message
        self.isError = isError
    }
}
