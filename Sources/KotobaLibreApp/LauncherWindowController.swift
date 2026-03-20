import AppKit
import Combine
import SwiftUI
import KotobaLibreCore

// These numbers keep the launcher panel sized like a Spotlight-style overlay.
private enum LauncherPanelMetrics {
    static let preferredWidth: CGFloat = 860
    static let minimumWidth: CGFloat = 560
    static let preferredVoiceWidth: CGFloat = 602
    static let minimumVoiceWidth: CGFloat = 420
    static let preferredTextHeight: CGFloat = 196
    static let preferredVoiceHeight: CGFloat = 336
    static let horizontalInset: CGFloat = 32
}

// LauncherPresentation keeps one panel controller flexible enough for text and voice entry flows.
enum LauncherPresentation: Equatable {
    case text
    case voice
}

// LauncherPanel is a custom NSPanel so the launcher can float above other apps
// without behaving like a full app window.
final class LauncherPanel: NSPanel {
    init() {
        super.init(
            contentRect: NSRect(
                origin: .zero,
                size: NSSize(width: LauncherPanelMetrics.preferredWidth, height: LauncherPanelMetrics.preferredTextHeight)
            ),
            styleMask: [.borderless, .nonactivatingPanel],
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
        hasShadow = false
        hidesOnDeactivate = false
        isMovableByWindowBackground = false
        animationBehavior = .utilityWindow
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

// This controller owns the floating launcher panel and handles focus handoff between apps.
@MainActor
final class LauncherWindowController: NSWindowController, NSWindowDelegate {
    private weak var appController: AppController?
    private let viewModel: LauncherViewModel
    private var eventMonitor: Any?
    private var previouslyFrontmostApplication: NSRunningApplication?
    private var shouldRestorePreviouslyFrontmostApplication = true

    var isVisible: Bool {
        window?.isVisible ?? false
    }

    var presentationMode: LauncherPresentation {
        viewModel.presentationMode
    }

    var selectedPresetID: String? {
        viewModel.selectedPresetID
    }

    func selectPreset(id: String?) {
        viewModel.selectedPresetID = id
    }

    init(appController: AppController) {
        self.appController = appController
        self.viewModel = LauncherViewModel(appController: appController)

        let panel = LauncherPanel()
        super.init(window: panel)

        let hostingView = NSHostingView(rootView: LauncherRootView(viewModel: viewModel))
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor
        panel.delegate = self
        panel.contentView = hostingView
        installKeyboardMonitor()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func prepare() {
        hide()
    }

    func showAndFocus(presentation: LauncherPresentation) {
        // Remember the previous app so we can return focus after the launcher closes.
        let frontmostApplication = NSWorkspace.shared.frontmostApplication
        previouslyFrontmostApplication = frontmostApplication == NSRunningApplication.current ? nil : frontmostApplication
        shouldRestorePreviouslyFrontmostApplication = true

        viewModel.prepareForPresentation(presentation)
        positionPanelOnActiveDisplay(presentation: presentation)
        // Visibility is tracked separately so hidden panels can stop their background motion.
        viewModel.setPanelVisible(true)
        window?.orderFrontRegardless()
        // The launcher should accept typing without surfacing the main window until a submission opens it.
        window?.makeKeyAndOrderFront(nil)
        viewModel.focusToken = UUID()
    }

    func finishVoiceCaptureAndSubmit() {
        viewModel.finishVoiceCaptureAndSubmit()
    }

    func suppressPreviousApplicationRestore() {
        shouldRestorePreviouslyFrontmostApplication = false
    }

    func hide() {
        // Hidden launcher content stays mounted, so visibility must drop before the panel leaves the screen.
        viewModel.setPanelVisible(false)
        window?.orderOut(nil)
        viewModel.cancelPresentation()
        restorePreviouslyFrontmostApplicationIfNeeded()
    }

    func windowDidResignKey(_ notification: Notification) {
        guard isVisible, viewModel.shouldHideOnFocusLoss else {
            return
        }

        hide()
    }

    func windowDidResignMain(_ notification: Notification) {
        guard isVisible, viewModel.shouldHideOnFocusLoss else {
            return
        }

        hide()
    }

    private func restorePreviouslyFrontmostApplicationIfNeeded() {
        defer {
            previouslyFrontmostApplication = nil
            shouldRestorePreviouslyFrontmostApplication = true
        }

        guard shouldRestorePreviouslyFrontmostApplication else {
            return
        }

        guard let previousApplication = previouslyFrontmostApplication else {
            return
        }

        guard previousApplication != NSRunningApplication.current else {
            return
        }

        DispatchQueue.main.async {
            // Activation is deferred so AppKit finishes hiding the launcher first.
            _ = previousApplication.activate()
        }
    }

    private func installKeyboardMonitor() {
        // The launcher handles only its own escape and submit keys.
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.window == self.window else {
                return event
            }

            if self.viewModel.presentationMode == .voice, self.viewModel.matchesVoiceShortcut(event) {
                self.viewModel.finishVoiceCaptureAndSubmit()
                return nil
            }

            switch event.keyCode {
            case 53:
                if self.viewModel.shouldHideOnEscape {
                    self.hide()
                    return nil
                }
                return event
            case 36, 76:
                self.viewModel.handlePrimaryAction()
                return nil
            default:
                return event
            }
        }
    }

    private func positionPanelOnActiveDisplay(presentation: LauncherPresentation) {
        guard let window else {
            return
        }

        // The launcher follows the active display so the shortcut feels local to the current workspace.
        let targetScreen = screenContainingMouse() ?? window.screen ?? NSScreen.main
        let frame = frameForPresentation(on: targetScreen, presentation: presentation)
        window.setFrame(frame, display: false)
    }

    private func screenContainingMouse() -> NSScreen? {
        let mouseLocation = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(mouseLocation, $0.frame, false) }
    }

    private func frameForPresentation(on screen: NSScreen?, presentation: LauncherPresentation) -> NSRect {
        let fallbackVisibleFrame = NSRect(x: 0, y: 0, width: LauncherPanelMetrics.preferredWidth, height: 900)
        let visibleFrame = screen?.visibleFrame ?? fallbackVisibleFrame

        let availableWidth = visibleFrame.width - (LauncherPanelMetrics.horizontalInset * 2)
        let preferredWidth = presentation == .voice
            ? LauncherPanelMetrics.preferredVoiceWidth
            : LauncherPanelMetrics.preferredWidth
        let minimumWidth = min(
            presentation == .voice ? LauncherPanelMetrics.minimumVoiceWidth : LauncherPanelMetrics.minimumWidth,
            visibleFrame.width
        )
        let width = min(
            preferredWidth,
            max(minimumWidth, availableWidth)
        )
        let height = presentation == .voice
            ? LauncherPanelMetrics.preferredVoiceHeight
            : LauncherPanelMetrics.preferredTextHeight

        let originX = visibleFrame.midX - (width / 2)
        let originY = visibleFrame.midY - (height / 2)

        return NSRect(x: originX, y: originY, width: width, height: height)
    }
}

// The view model keeps the launcher view simple and translates UI actions into AppController calls.
@MainActor
final class LauncherViewModel: ObservableObject {
    @Published private(set) var presentationMode: LauncherPresentation = .text
    @Published private(set) var isPanelVisible = false
    @Published var query = ""
    @Published var selectedPresetID: String?
    @Published var statusMessage = ""
    @Published var isError = false
    @Published var focusToken = UUID()
    @Published private(set) var voiceState: VoiceTranscriptionService.State = .idle
    @Published private(set) var voiceAudioLevel = 0.12

    private weak var appController: AppController?
    private var cancellables: Set<AnyCancellable> = []
    private let voiceTranscriptionService = VoiceTranscriptionService()
    private var voiceStartTask: Task<Void, Never>?
    private var voiceFinishTask: Task<Void, Never>?
    private var latestVoiceTranscript = ""

    init(appController: AppController) {
        self.appController = appController
        voiceTranscriptionService.onTranscriptChange = { [weak self] transcript in
            self?.latestVoiceTranscript = transcript
        }
        observeAppController(appController)
    }

    var presets: [Preset] {
        guard let appController else {
            return []
        }

        // The default preset is sorted first so pressing Enter does the expected thing.
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

    var defaultPresetID: String? {
        appController?.settings.defaultPresetId
    }

    var shouldHideOnFocusLoss: Bool {
        presentationMode == .text
    }

    var shouldHideOnEscape: Bool {
        presentationMode == .text
    }

    var voiceShortcutDisplayValue: String {
        voiceShortcutValue
            .split(separator: "+")
            .map { token in
                switch token {
                case "CmdOrCtrl":
                    return "⌘"
                case "Ctrl":
                    return "⌃"
                case "Alt":
                    return "⌥"
                case "Shift":
                    return "⇧"
                default:
                    return token.replacingOccurrences(of: "Key", with: "").replacingOccurrences(of: "Digit", with: "")
                }
            }
            .joined(separator: "")
    }

    var voiceShortcutValue: String {
        appController?.settings.voiceGlobalShortcut ?? AppSettings.defaultVoiceShortcut
    }

    func setPanelVisible(_ isVisible: Bool) {
        isPanelVisible = isVisible
    }

    func prepareForPresentation(_ presentation: LauncherPresentation) {
        presentationMode = presentation
        voiceFinishTask?.cancel()
        voiceFinishTask = nil
        statusMessage = ""
        isError = false
        resetSelectionToDefaultPreset()

        guard validateSharedLauncherState() else {
            cancelVoiceCapture(resetStatus: false)
            return
        }

        switch presentation {
        case .text:
            cancelVoiceCapture(resetStatus: false)
            focusToken = UUID()
        case .voice:
            query = ""
            latestVoiceTranscript = ""
            startVoiceCapture()
        }
    }

    func handlePrimaryAction() {
        switch presentationMode {
        case .text:
            submitTextLauncher()
        case .voice:
            finishVoiceCaptureAndSubmit()
        }
    }

    func matchesVoiceShortcut(_ event: NSEvent) -> Bool {
        GlobalShortcutRegistrar.shortcutString(from: event) == voiceShortcutValue
    }

    func finishVoiceCaptureAndSubmit() {
        guard presentationMode == .voice else {
            return
        }

        guard validateSharedLauncherState() else {
            return
        }

        guard voiceState == .listening else {
            if voiceState == .preparing {
                setStatus("Voice mode is still starting. Try the shortcut again in a moment.", isError: false)
            }
            return
        }

        guard let appController else {
            return
        }

        guard let targetID = selectedPresetID ?? presets.first?.id else {
            setStatus("No agent selected.", isError: true)
            return
        }

        voiceState = .finishing
        voiceAudioLevel = 0.24
        setStatus("Finishing transcription…", isError: false)
        voiceFinishTask?.cancel()
        voiceFinishTask = Task { [weak self] in
            guard let self else {
                return
            }

            do {
                let transcript = try await self.voiceTranscriptionService.stopAndFinalize()
                try appController.openPreset(id: targetID, query: transcript, preferMainWindow: true)
                self.resetForNextLaunch()
            } catch is CancellationError {
                self.voiceState = .idle
                self.voiceAudioLevel = 0.12
            } catch {
                self.voiceState = .idle
                self.voiceAudioLevel = 0.12
                self.setStatus(error.localizedDescription, isError: true)
                if let voiceError = error as? VoiceTranscriptionServiceError, voiceError == .noSpeechDetected {
                    self.startVoiceCapture()
                }
            }
        }
    }

    func cancelAndHide() {
        cancelVoiceCapture(resetStatus: true)
        appController?.hideLauncherWindow()
    }

    func cancelPresentation() {
        cancelVoiceCapture(resetStatus: false)
        presentationMode = .text
        resetForNextLaunch()
    }

    private func submitTextLauncher() {
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
            resetForNextLaunch()
        } catch {
            setStatus(error.localizedDescription, isError: true)
        }
    }

    private func startVoiceCapture() {
        cancelVoiceCapture(resetStatus: false)
        voiceState = .preparing
        voiceAudioLevel = 0.3
        setStatus("Preparing voice launcher…", isError: false)

        voiceStartTask = Task { [weak self] in
            guard let self, let appController = self.appController else {
                return
            }

            do {
                try await appController.ensureVoiceModePermissions()
                try self.voiceTranscriptionService.start()
                self.voiceState = .listening
                self.voiceAudioLevel = 0.7
                self.setStatus("Listening. Press \(self.voiceShortcutDisplayValue) again to send.", isError: false)
            } catch is CancellationError {
                self.voiceState = .idle
                self.voiceAudioLevel = 0.12
            } catch {
                self.voiceState = .idle
                self.voiceAudioLevel = 0.12
                self.setStatus(error.localizedDescription, isError: true)
            }
        }
    }

    private func cancelVoiceCapture(resetStatus: Bool) {
        voiceStartTask?.cancel()
        voiceStartTask = nil
        voiceFinishTask?.cancel()
        voiceFinishTask = nil
        voiceTranscriptionService.cancel()
        voiceState = .idle
        voiceAudioLevel = 0.12
        latestVoiceTranscript = ""
        if resetStatus {
            statusMessage = ""
            isError = false
        }
    }

    private func resetForNextLaunch() {
        // Reset after a successful launch so the next shortcut opens a clean prompt.
        query = ""
        latestVoiceTranscript = ""
        voiceState = .idle
        voiceAudioLevel = 0.12
        resetSelectionToDefaultPreset()
        statusMessage = ""
        isError = false
    }

    private func setStatus(_ message: String, isError: Bool) {
        statusMessage = message
        self.isError = isError
    }

    private func validateSharedLauncherState() -> Bool {
        guard let appController else {
            return false
        }

        if appController.settings.instanceBaseUrl == nil {
            setStatus("Configure instance URL first.", isError: true)
            return false
        }

        if presets.isEmpty {
            setStatus("No agents configured yet. Add one in Settings.", isError: true)
            return false
        }

        ensureSelectedPreset()
        return true
    }

    private func ensureSelectedPreset() {
        if selectedPresetID == nil {
            resetSelectionToDefaultPreset()
        }
    }

    private func resetSelectionToDefaultPreset() {
        selectedPresetID = appController?.settings.defaultPresetId ?? presets.first?.id
    }

    private func observeAppController(_ appController: AppController) {
        // The launcher mirrors live preset and settings changes so newly added agents appear immediately.
        appController.$presets
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.handleAppStateChange()
            }
            .store(in: &cancellables)

        appController.$settings
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.handleAppStateChange()
            }
            .store(in: &cancellables)
    }

    private func handleAppStateChange() {
        guard let appController else {
            return
        }

        if let selectedPresetID, !appController.presets.contains(where: { $0.id == selectedPresetID }) {
            resetSelectionToDefaultPreset()
        } else if self.selectedPresetID == nil {
            resetSelectionToDefaultPreset()
        }

        objectWillChange.send()
    }
}
