import AppKit
import ApplicationServices
import CoreGraphics
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
    private var previouslyFrontmostApplication: NSRunningApplication?

    var isVisible: Bool {
        window?.isVisible ?? false
    }

    init(appController: AppController) {
        self.appController = appController
        self.viewModel = LauncherViewModel(appController: appController)

        let window = LauncherPanel(
            contentRect: NSRect(origin: .zero, size: defaultLauncherWindowSize),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.title = "Librechat Spotlight"
        window.center()
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.isFloatingPanel = true
        window.hidesOnDeactivate = false
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
        let frontmostApplication = NSWorkspace.shared.frontmostApplication
        previouslyFrontmostApplication = frontmostApplication == NSRunningApplication.current ? nil : frontmostApplication

        viewModel.refresh()
        window?.alphaValue = CGFloat(appController?.settings.launcherOpacity ?? 0.95)
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.async { [weak self] in
            self?.updateFrameForActiveScreen()
            self?.window?.orderFrontRegardless()
            self?.window?.makeKeyAndOrderFront(nil)
            self?.viewModel.focusToken = UUID()
        }
    }

    func hide() {
        window?.orderOut(nil)
        viewModel.reset()
        restorePreviouslyFrontmostApplicationIfNeeded()
    }

    func windowDidResignKey(_ notification: Notification) {
        hide()
    }

    func windowDidResignMain(_ notification: Notification) {
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

    private func updateFrameForActiveScreen() {
        guard let window else {
            return
        }

        let screen = targetScreenForLauncher(window: window)
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

    private func targetScreenForLauncher(window: NSWindow) -> NSScreen? {
        if let frontmostApplication = previouslyFrontmostApplication ?? NSWorkspace.shared.frontmostApplication,
           let screen = screenForFrontmostApplicationUsingAccessibility(frontmostApplication) ?? screenForFrontmostApplication(frontmostApplication) {
            return screen
        }

        if let screen = window.screen {
            return screen
        }

        let mouseLocation = NSEvent.mouseLocation
        return NSScreen.screens.first(where: { NSMouseInRect(mouseLocation, $0.frame, false) }) ?? NSScreen.main
    }

    private func screenForFrontmostApplication(_ application: NSRunningApplication) -> NSScreen? {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let windowList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }

        let pid = application.processIdentifier
        let candidateBounds = windowList.lazy
            .filter { windowInfo in
                guard let ownerPID = windowInfo[kCGWindowOwnerPID as String] as? pid_t else {
                    return false
                }

                let layer = windowInfo[kCGWindowLayer as String] as? Int ?? 0
                let alpha = windowInfo[kCGWindowAlpha as String] as? Double ?? 1
                let width = (windowInfo[kCGWindowBounds as String] as? [String: Any]).flatMap { $0["Width"] as? Double } ?? 0
                let height = (windowInfo[kCGWindowBounds as String] as? [String: Any]).flatMap { $0["Height"] as? Double } ?? 0

                return ownerPID == pid && layer == 0 && alpha > 0 && width > 0 && height > 0
            }
            .compactMap { windowInfo -> CGRect? in
                guard let boundsDictionary = windowInfo[kCGWindowBounds as String] as? NSDictionary else {
                    return nil
                }

                return CGRect(dictionaryRepresentation: boundsDictionary)
            }
            .first

        guard let candidateBounds else {
            return nil
        }

        let midpoint = NSPoint(x: candidateBounds.midX, y: candidateBounds.midY)
        return NSScreen.screens.first(where: { NSMouseInRect(midpoint, $0.frame, false) })
    }

    private func screenForFrontmostApplicationUsingAccessibility(_ application: NSRunningApplication) -> NSScreen? {
        let appElement = AXUIElementCreateApplication(application.processIdentifier)

        var focusedWindowValue: CFTypeRef?
        let focusedWindowResult = AXUIElementCopyAttributeValue(
            appElement,
            kAXFocusedWindowAttribute as CFString,
            &focusedWindowValue
        )

        guard focusedWindowResult == .success,
              let windowElement = focusedWindowValue else {
            return nil
        }

        let windowAXElement = unsafeDowncast(windowElement, to: AXUIElement.self)

        guard let position = axPoint(for: windowAXElement, attribute: kAXPositionAttribute),
              let size = axSize(for: windowAXElement, attribute: kAXSizeAttribute) else {
            return nil
        }

        let bounds = CGRect(origin: position, size: size)
        let midpoint = NSPoint(x: bounds.midX, y: bounds.midY)
        return NSScreen.screens.first(where: { NSMouseInRect(midpoint, $0.frame, false) })
    }

    private func axPoint(for element: AXUIElement, attribute: String) -> CGPoint? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        guard result == .success,
              let axValue = value,
              CFGetTypeID(axValue) == AXValueGetTypeID() else {
            return nil
        }

        let typedValue = unsafeDowncast(axValue, to: AXValue.self)
        guard AXValueGetType(typedValue) == .cgPoint else {
            return nil
        }

        var point = CGPoint.zero
        guard AXValueGetValue(typedValue, .cgPoint, &point) else {
            return nil
        }

        return point
    }

    private func axSize(for element: AXUIElement, attribute: String) -> CGSize? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        guard result == .success,
              let axValue = value,
              CFGetTypeID(axValue) == AXValueGetTypeID() else {
            return nil
        }

        let typedValue = unsafeDowncast(axValue, to: AXValue.self)
        guard AXValueGetType(typedValue) == .cgSize else {
            return nil
        }

        var size = CGSize.zero
        guard AXValueGetValue(typedValue, .cgSize, &size) else {
            return nil
        }

        return size
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
