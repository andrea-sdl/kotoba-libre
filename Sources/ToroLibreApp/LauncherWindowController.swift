import AppKit
import SwiftUI
import ToroLibreCore

private let defaultLauncherWindowSize = NSSize(width: 800, height: 64)

final class LauncherPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class LauncherWindowController: NSWindowController, NSWindowDelegate {
    private weak var appController: AppController?
    private let viewModel: LauncherViewModel
    private var eventMonitor: Any?

    var isVisible: Bool {
        window?.isVisible ?? false
    }

    init(appController: AppController) {
        self.appController = appController
        self.viewModel = LauncherViewModel(appController: appController)

        let window = LauncherPanel(
            contentRect: NSRect(origin: .zero, size: defaultLauncherWindowSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        window.title = "Librechat Spotlight"
        window.center()
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.isFloatingPanel = true
        window.hidesOnDeactivate = true
        window.becomesKeyOnlyIfNeeded = false
        window.level = .floating
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary, .transient, .ignoresCycle]

        super.init(window: window)
        self.window?.delegate = self
        self.window?.contentViewController = NSHostingController(
            rootView: LauncherRootView(viewModel: viewModel)
        )
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
        viewModel.refresh()
        updateFrameForActiveScreen()
        window?.alphaValue = CGFloat(appController?.settings.launcherOpacity ?? 0.95)
        window?.orderFrontRegardless()
        window?.makeKey()
        viewModel.focusToken = UUID()
    }

    func hide() {
        window?.close()
        viewModel.reset()
    }

    func windowDidResignKey(_ notification: Notification) {
        hide()
    }

    func windowDidResignMain(_ notification: Notification) {
        hide()
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

    private func updateFrameForActiveScreen() {
        guard let window else {
            return
        }

        let mouseLocation = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { NSMouseInRect(mouseLocation, $0.frame, false) }) ?? NSScreen.main
        let visibleFrame = screen?.visibleFrame ?? .zero
        guard visibleFrame.width > 0, visibleFrame.height > 0 else {
            window.setContentSize(defaultLauncherWindowSize)
            window.center()
            return
        }

        let width = defaultLauncherWindowSize.width
        let height = defaultLauncherWindowSize.height
        let origin = NSPoint(
            x: visibleFrame.midX - (width / 2),
            y: visibleFrame.midY - (height / 2)
        )
        window.setFrame(NSRect(origin: origin, size: NSSize(width: width, height: height)), display: false)
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
            try appController.openPreset(id: targetID, query: query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : query)
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
