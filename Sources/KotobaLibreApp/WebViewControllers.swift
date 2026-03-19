import AppKit
import AVFoundation
import SwiftUI
import KotobaLibreCore
import WebKit

// The main window and embedded web view live together in this file because they share one navigation flow.
private let defaultMainWindowSize = NSSize(width: 900, height: 660)
private let minimumMainWindowSize = NSSize(width: 700, height: 480)
private let onboardingWindowSize = NSSize(width: 860, height: 650)
private let onboardingMinimumWindowSize = NSSize(width: 860, height: 650)

// These identifiers keep the main window toolbar definition local to the web window controller file.
private enum MainWindowToolbarItem {
    static let addAgent = NSToolbarItem.Identifier("KotobaLibreAddAgent")
}

// WebResponseCompletion carries the metadata the native shell needs for badges and notifications.
struct WebResponseCompletion {
    let conversationTitle: String?
    let duration: TimeInterval
}

// MainWindowController owns the primary app window.
// It swaps between onboarding and web content and remembers the last usable frame.
@MainActor
final class MainWindowController: NSWindowController, NSWindowDelegate, NSToolbarDelegate {
    enum ContentKind: String {
        case onboarding
        case web
        case unknown
    }

    private weak var appController: AppController?
    private let store: AppDataStore
    private var webController: WebContentViewController?
    private var eventMonitor: Any?
    private let savedWindowFrame: NSRect?
    private var hasCompletedInitialFrameSetup = false
    private lazy var addAgentButton = makeAddAgentToolbarButton()
    private var currentAddAgentCandidate: WebAddPresetCandidate?
    private var addAgentSheetWindowController: AddAgentSheetWindowController?

    init(appController: AppController, store: AppDataStore) {
        self.store = store
        self.savedWindowFrame = Self.loadSavedWindowFrame(from: store)
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: defaultMainWindowSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = appDisplayName
        window.minSize = minimumMainWindowSize
        window.titlebarAppearsTransparent = true
        window.toolbarStyle = .unifiedCompact
        super.init(window: window)
        self.appController = appController
        self.window?.delegate = self
        installToolbar()
        installScreenObserver()
        installWindowFrameObservers()
        installShortcutMonitor()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func showOnboarding() {
        guard let appController else {
            return
        }

        updateAddAgentCandidate(nil)
        updateWindowTitle(nil)
        applyWindowSizing(for: .onboarding)
        window?.toolbar = nil
        let hostingController = NSHostingController(
            rootView: OnboardingFlowView(appController: appController)
        )
        window?.contentViewController = hostingController
    }

    func showWebView(settings: AppSettings) {
        // The web controller is reused so session state and browser history survive UI switches.
        applyWindowSizing(for: .web)
        installToolbar()
        let controller = ensureWebController()
        controller.apply(settings: settings)
        window?.contentViewController = controller
        updateWindowTitle(controller.currentConversationTitle)
    }

    func navigateToHome(settings: AppSettings) {
        guard let homeURL = try? KotobaLibreCore.parseInstanceBaseURL(settings) else {
            showOnboarding()
            return
        }

        updateAddAgentCandidate(nil)
        applyWindowSizing(for: .web)
        installToolbar()
        let controller = ensureWebController()
        controller.apply(settings: settings)
        window?.contentViewController = controller
        controller.load(url: homeURL)
        updateWindowTitle(controller.currentConversationTitle)
    }

    func open(url: URL, settings: AppSettings, instanceHost: String?, forceEmbedAllHosts: Bool = false, forceReload: Bool = false) {
        updateAddAgentCandidate(nil)
        installToolbar()
        let controller = ensureWebController()
        controller.apply(settings: settings)
        window?.contentViewController = controller
        controller.open(
            url: url,
            settings: settings,
            instanceHost: instanceHost,
            forceEmbedAllHosts: forceEmbedAllHosts,
            forceReload: forceReload
        )
        updateWindowTitle(controller.currentConversationTitle)
        showAndFocus()
    }

    var isVisible: Bool {
        window?.isVisible ?? false
    }

    var canNavigateBack: Bool {
        webController?.canNavigateBack ?? false
    }

    var canNavigateForward: Bool {
        webController?.canNavigateForward ?? false
    }

    var canSearchMessages: Bool {
        webController != nil
    }

    var canStopGenerating: Bool {
        webController?.isGeneratingResponse ?? false
    }

    func showAndFocus() {
        // The first show restores a saved frame. Later shows only clamp the frame to current screens.
        applyInitialWindowFrameIfNeeded()
        normalizeWindowFrameToAvailableScreens(centerIfNeeded: savedWindowFrame == nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func hide() {
        persistWindowFrame()
        window?.orderOut(nil)
    }

    func resetToDefaultSize() {
        let targetSize = contentKind == .onboarding ? onboardingWindowSize : defaultMainWindowSize
        window?.setContentSize(targetSize)
        window?.center()
        normalizeWindowFrameToAvailableScreens(centerIfNeeded: true)
        persistWindowFrame()
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        persistWindowFrame()
        sender.orderOut(nil)
        return false
    }

    func windowDidChangeScreen(_ notification: Notification) {
        normalizeWindowFrameToAvailableScreens()
    }

    func windowDidBecomeKey(_ notification: Notification) {
        appController?.markResponsesRead()
    }

    func persistStateForTermination() {
        persistWindowFrame()
    }

    var contentKind: ContentKind {
        guard let contentViewController = window?.contentViewController else {
            return .unknown
        }

        if contentViewController is WebContentViewController {
            return .web
        }

        if contentViewController is NSHostingController<OnboardingFlowView> {
            return .onboarding
        }

        return .unknown
    }

    private func ensureWebController() -> WebContentViewController {
        if let webController {
            return webController
        }

        // External links are delegated back to AppController so runtime mode can decide what is allowed.
        let created = WebContentViewController()
        created.externalNavigationHandler = { [weak appController] url in
            appController?.openExternally(url)
        }
        created.authenticationSessionStarter = { [weak appController] url, callbackURLScheme in
            appController?.startAuthenticationSession(for: url, callbackURLScheme: callbackURLScheme) == true
        }
        created.appNavigationHandler = { [weak appController] url in
            appController?.handleEmbeddedAppNavigation(url) == true
        }
        created.addAgentCandidateHandler = { [weak self] candidate in
            self?.updateAddAgentCandidate(candidate)
        }
        created.conversationTitleHandler = { [weak self] title in
            self?.updateWindowTitle(title)
        }
        created.responseCompletionHandler = { [weak appController] completion in
            appController?.handleWebResponseCompletion(completion)
        }
        webController = created
        return created
    }

    func queueAttachment(urls: [URL]) {
        guard !urls.isEmpty else {
            return
        }

        ensureWebController().queueAttachment(urls: urls)
    }

    func navigateBack() {
        webController?.navigateBack()
    }

    func navigateForward() {
        webController?.navigateForward()
    }

    func showConversationSearch() {
        webController?.showConversationSearch()
    }

    func stopGenerating() -> Bool {
        webController?.stopGenerating() ?? false
    }

    private func installShortcutMonitor() {
        // Returning nil consumes the event after shortcut recording handles it.
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

    private func installToolbar() {
        guard let window else {
            return
        }

        let toolbar = NSToolbar(identifier: "KotobaLibreMainToolbar")
        toolbar.delegate = self
        toolbar.allowsUserCustomization = false
        toolbar.autosavesConfiguration = false
        toolbar.displayMode = .iconOnly
        window.toolbar = toolbar
    }

    private func installScreenObserver() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleScreenParametersDidChange(_:)),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    private func installWindowFrameObservers() {
        guard let window else {
            return
        }

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleWindowDidResize(_:)),
            name: NSWindow.didResizeNotification,
            object: window
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleWindowDidMove(_:)),
            name: NSWindow.didMoveNotification,
            object: window
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleWindowWillClose(_:)),
            name: NSWindow.willCloseNotification,
            object: window
        )
    }

    private func persistWindowFrame() {
        guard let window, hasCompletedInitialFrameSetup else {
            return
        }

        // Frames are only persisted after the initial placement logic runs once.
        let state = WindowFrameState(frame: window.frame)
        do {
            try store.saveMainWindowState(state)
        } catch {
            debugLog("KotobaLibre Window: failed to save state -> \(error.localizedDescription)")
        }
    }

    @objc private func handleScreenParametersDidChange(_ notification: Notification) {
        normalizeWindowFrameToAvailableScreens()
    }

    @objc private func handleWindowDidResize(_ notification: Notification) {
        persistWindowFrame()
    }

    @objc private func handleWindowDidMove(_ notification: Notification) {
        persistWindowFrame()
    }

    @objc private func handleWindowWillClose(_ notification: Notification) {
        persistWindowFrame()
    }

    private func normalizeWindowFrameToAvailableScreens(centerIfNeeded: Bool = false) {
        guard let window else {
            return
        }

        let screens = NSScreen.screens
        guard !screens.isEmpty else {
            return
        }

        let currentFrame = window.frame
        let targetScreen = bestScreen(for: currentFrame, preferredScreen: window.screen) ?? screens[0]
        // Screen layouts can change while the app is closed. Clamp the saved frame back onto a visible screen.
        let adjustedFrame = adjustedFrame(currentFrame, in: targetScreen.visibleFrame, centerIfNeeded: centerIfNeeded)

        guard !framesMatch(currentFrame, adjustedFrame) else {
            return
        }

        window.setFrame(adjustedFrame, display: false)
        persistWindowFrame()
    }

    private func bestScreen(for frame: NSRect, preferredScreen: NSScreen?) -> NSScreen? {
        let screens = NSScreen.screens
        let matchingScreen = screens.max { lhs, rhs in
            intersectionArea(of: lhs.visibleFrame, and: frame) < intersectionArea(of: rhs.visibleFrame, and: frame)
        }

        if let matchingScreen, intersectionArea(of: matchingScreen.visibleFrame, and: frame) > 0 {
            return matchingScreen
        }

        return preferredScreen ?? NSScreen.main
    }

    private func adjustedFrame(_ frame: NSRect, in visibleFrame: NSRect, centerIfNeeded: Bool) -> NSRect {
        var adjustedFrame = frame.standardized
        let minimumSize = window?.minSize ?? minimumMainWindowSize
        adjustedFrame.size.width = min(max(adjustedFrame.width, minimumSize.width), visibleFrame.width)
        adjustedFrame.size.height = min(max(adjustedFrame.height, minimumSize.height), visibleFrame.height)

        let needsCentering = centerIfNeeded || intersectionArea(of: visibleFrame, and: adjustedFrame) == 0
        if needsCentering {
            adjustedFrame.origin.x = visibleFrame.midX - (adjustedFrame.width / 2)
            adjustedFrame.origin.y = visibleFrame.midY - (adjustedFrame.height / 2)
        } else {
            adjustedFrame.origin.x = min(
                max(adjustedFrame.origin.x, visibleFrame.minX),
                visibleFrame.maxX - adjustedFrame.width
            )
            adjustedFrame.origin.y = min(
                max(adjustedFrame.origin.y, visibleFrame.minY),
                visibleFrame.maxY - adjustedFrame.height
            )
        }

        return adjustedFrame.integral
    }

    private func intersectionArea(of lhs: NSRect, and rhs: NSRect) -> CGFloat {
        let intersection = lhs.intersection(rhs)
        guard !intersection.isNull else {
            return 0
        }

        return intersection.width * intersection.height
    }

    private func framesMatch(_ lhs: NSRect, _ rhs: NSRect) -> Bool {
        abs(lhs.origin.x - rhs.origin.x) < 1 &&
        abs(lhs.origin.y - rhs.origin.y) < 1 &&
        abs(lhs.size.width - rhs.size.width) < 1 &&
        abs(lhs.size.height - rhs.size.height) < 1
    }

    private func applyInitialWindowFrameIfNeeded() {
        guard let window, !hasCompletedInitialFrameSetup else {
            return
        }

        // A saved frame wins. Otherwise the first launch starts centered with the default size.
        if let savedWindowFrame {
            window.setFrame(savedWindowFrame, display: false)
        } else {
            window.center()
        }

        hasCompletedInitialFrameSetup = true
    }

    private func applyWindowSizing(for contentKind: ContentKind) {
        guard let window else {
            return
        }

        let minimumSize = contentKind == .onboarding ? onboardingMinimumWindowSize : minimumMainWindowSize
        window.minSize = minimumSize

        guard !hasCompletedInitialFrameSetup else {
            normalizeWindowFrameToAvailableScreens()
            return
        }

        let defaultSize = contentKind == .onboarding ? onboardingWindowSize : defaultMainWindowSize
        window.setContentSize(defaultSize)
    }

    private static func loadSavedWindowFrame(from store: AppDataStore) -> NSRect? {
        guard let savedState = try? store.loadMainWindowState() else {
            return nil
        }

        return savedState.rect
    }

    private func debugLog(_ message: String) {
        guard appController?.settings.debugLoggingEnabled == true else {
            return
        }

        print(message)
    }

    private func updateAddAgentCandidate(_ candidate: WebAddPresetCandidate?) {
        currentAddAgentCandidate = candidate
        addAgentButton.isEnabled = candidate != nil
        addAgentButton.title = candidate?.kind == .link ? "Add Link" : "Add Agent"
        addAgentButton.toolTip = candidate?.kind == .link
            ? "Save the current LibreChat link into Kotoba Libre."
            : "Save the current LibreChat agent into Kotoba Libre."
    }

    private func presentAddAgentSheetFromTitlebar() {
        guard let webController else {
            return
        }

        webController.fetchCurrentAddAgentCandidate { [weak self] liveCandidate in
            guard let self else {
                return
            }

            let candidate = liveCandidate ?? self.currentAddAgentCandidate
            guard let candidate, let appController, let window else {
                return
            }

            let preset = appController.makePreset(from: candidate)
            addAgentSheetWindowController?.dismiss()
            let sheetController = AddAgentSheetWindowController(
                appController: appController,
                initialPreset: preset
            ) { [weak self] in
                self?.addAgentSheetWindowController = nil
            }
            addAgentSheetWindowController = sheetController
            sheetController.beginSheet(on: window)
        }
    }

    private func makeAddAgentToolbarButton() -> NSButton {
        let button = NSButton(title: "Add Agent", target: self, action: #selector(handleAddAgentToolbarButton))
        button.setButtonType(.momentaryPushIn)
        button.bezelStyle = .rounded
        button.isBordered = true
        button.controlSize = .small
        button.contentTintColor = .systemBlue
        button.image = NSImage(
            systemSymbolName: "plus.circle",
            accessibilityDescription: "Add Agent"
        )
        button.imagePosition = .imageLeading
        button.isEnabled = false
        button.toolTip = "Save the current LibreChat agent into Kotoba Libre."
        return button
    }

    @objc private func handleAddAgentToolbarButton() {
        presentAddAgentSheetFromTitlebar()
    }

    private func updateWindowTitle(_ conversationTitle: String?) {
        let trimmedTitle = conversationTitle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        window?.title = trimmedTitle.isEmpty ? appDisplayName : "\(trimmedTitle) - \(appDisplayName)"
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.flexibleSpace, MainWindowToolbarItem.addAgent]
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        return [.flexibleSpace, MainWindowToolbarItem.addAgent]
    }

    func toolbar(
        _ toolbar: NSToolbar,
        itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
        guard itemIdentifier == MainWindowToolbarItem.addAgent else {
            return nil
        }

        let item = NSToolbarItem(itemIdentifier: itemIdentifier)
        item.label = "Add Agent"
        item.paletteLabel = "Add Agent"
        item.toolTip = "Save the current LibreChat agent into Kotoba Libre."
        item.view = addAgentButton
        return item
    }
}

// WindowFrameState is stored as plain doubles. This extension converts it back to AppKit geometry.
private extension WindowFrameState {
    init(frame: NSRect) {
        self.init(
            originX: frame.origin.x,
            originY: frame.origin.y,
            width: frame.size.width,
            height: frame.size.height
        )
    }

    var rect: NSRect {
        NSRect(x: originX, y: originY, width: width, height: height)
    }
}

// WebContentViewController wraps WKWebView and contains the rules for embedded vs external navigation.
@MainActor
final class WebContentViewController: NSViewController, WKNavigationDelegate, WKUIDelegate, WKDownloadDelegate {
    private static let logHandlerName = "kotobaLibreLog"
    private static let addAgentCandidateHandlerName = "kotobaLibreAddAgentCandidate"
    private static let launcherProgressHandlerName = "kotobaLibreLauncherProgress"
    private static let desktopEventHandlerName = "kotobaLibreDesktopEvent"
    private static let supportedAuthenticationCallbackScheme = "kotobalibre"
    private static let appIdentityHeaderName = "X-Kotoba-Libre"
    private static let appIdentityHeaderValue = "\(appDisplayName)/\(AppResources.appVersionDisplayString)"
    private static let attachmentPickerRetryDelay: TimeInterval = 0.35
    private static let attachmentPickerRetryLimit = 12

    private enum ExternalNavigationPolicy {
        case singleHost(String?)
        case embedAllHosts
    }

    // Popup windows get their own controller so JavaScript-created windows can close independently.
    private final class PopupWindowController: NSWindowController, NSWindowDelegate {
        private static let defaultSize = NSSize(width: 720, height: 640)

        var onClose: (() -> Void)?

        init(webView: WKWebView) {
            let window = NSWindow(
                contentRect: NSRect(origin: .zero, size: Self.defaultSize),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.title = appDisplayName
            window.minSize = NSSize(width: 420, height: 320)
            window.titlebarAppearsTransparent = true
            window.contentView = webView

            super.init(window: window)
            window.delegate = self
        }

        init(webView: WKWebView, windowFeatures: WKWindowFeatures) {
            let requestedWidth = CGFloat(windowFeatures.width?.doubleValue ?? Double(Self.defaultSize.width))
            let requestedHeight = CGFloat(windowFeatures.height?.doubleValue ?? Double(Self.defaultSize.height))
            let initialSize = NSSize(
                width: max(420, requestedWidth),
                height: max(320, requestedHeight)
            )
            let window = NSWindow(
                contentRect: NSRect(origin: .zero, size: initialSize),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.title = appDisplayName
            window.minSize = NSSize(width: 420, height: 320)
            window.titlebarAppearsTransparent = true
            window.contentView = webView

            super.init(window: window)
            window.delegate = self
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        func showAndFocus() {
            window?.center()
            window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }

        func windowWillClose(_ notification: Notification) {
            onClose?()
        }
    }

    // JavaScript posts log lines to this handler so native debug logging can see SPA-side decisions.
    private final class ScriptMessageHandler: NSObject, WKScriptMessageHandler {
        var onMessage: ((String) -> Void)?

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            if let text = message.body as? String {
                onMessage?(text)
            } else {
                onMessage?("Unexpected message body: \(message.body)")
            }
        }
    }

    // This message handler forwards structured route data from the injected observer script.
    private final class DictionaryMessageHandler: NSObject, WKScriptMessageHandler {
        var onMessage: ((Any) -> Void)?

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            onMessage?(message.body)
        }
    }

    // This badge keeps launcher-triggered route changes feeling intentional instead of stalled.
    @MainActor
    private final class LauncherProgressBadgeView: NSVisualEffectView {
        private let spinner = NSProgressIndicator()
        private let label = NSTextField(labelWithString: "")

        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)

            material = .hudWindow
            blendingMode = .withinWindow
            state = .active
            wantsLayer = true
            layer?.cornerRadius = 14
            layer?.masksToBounds = true
            translatesAutoresizingMaskIntoConstraints = false
            alphaValue = 0
            isHidden = true

            spinner.style = .spinning
            spinner.controlSize = .small
            spinner.isIndeterminate = true
            spinner.translatesAutoresizingMaskIntoConstraints = false

            label.font = .systemFont(ofSize: 12, weight: .medium)
            label.textColor = .secondaryLabelColor
            label.translatesAutoresizingMaskIntoConstraints = false
            label.lineBreakMode = .byTruncatingTail
            label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

            addSubview(spinner)
            addSubview(label)

            NSLayoutConstraint.activate([
                spinner.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
                spinner.centerYAnchor.constraint(equalTo: centerYAnchor),
                label.leadingAnchor.constraint(equalTo: spinner.trailingAnchor, constant: 8),
                label.topAnchor.constraint(equalTo: topAnchor, constant: 8),
                label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
                label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12)
            ])
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        func setMessage(_ message: String) {
            label.stringValue = message
        }

        func show(animated: Bool) {
            spinner.startAnimation(nil)
            guard isHidden || alphaValue < 1 else {
                return
            }

            isHidden = false
            if animated {
                alphaValue = 0
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.16
                    animator().alphaValue = 1
                }
            } else {
                alphaValue = 1
            }
        }

        func hide(animated: Bool) {
            spinner.stopAnimation(nil)
            guard !isHidden else {
                return
            }

            let completeHide = { [weak self] in
                self?.alphaValue = 0
                self?.isHidden = true
            }

            if animated {
                NSAnimationContext.runAnimationGroup({ context in
                    context.duration = 0.16
                    animator().alphaValue = 0
                }, completionHandler: { [weak self] in
                    Task { @MainActor [weak self] in
                        self?.alphaValue = 0
                        self?.isHidden = true
                    }
                })
            } else {
                completeHide()
            }
        }
    }

    // This overlay gives the app a lightweight native search UI for the current conversation.
    @MainActor
    private final class ConversationSearchBarView: NSVisualEffectView {
        private let searchField = NSSearchField()
        private let previousButton = NSButton()
        private let nextButton = NSButton()
        private let closeButton = NSButton()

        var onSearchChange: ((String) -> Void)?
        var onFindPrevious: ((String) -> Void)?
        var onFindNext: ((String) -> Void)?
        var onClose: (() -> Void)?

        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)

            material = .hudWindow
            blendingMode = .withinWindow
            state = .active
            wantsLayer = true
            layer?.cornerRadius = 14
            layer?.masksToBounds = true
            translatesAutoresizingMaskIntoConstraints = false
            alphaValue = 0
            isHidden = true

            searchField.placeholderString = "Search messages"
            searchField.sendsSearchStringImmediately = true
            searchField.target = self
            searchField.action = #selector(handleSearchChanged)
            searchField.translatesAutoresizingMaskIntoConstraints = false

            previousButton.bezelStyle = .texturedRounded
            previousButton.controlSize = .small
            previousButton.image = NSImage(systemSymbolName: "chevron.up", accessibilityDescription: "Previous match")
            previousButton.target = self
            previousButton.action = #selector(handleFindPrevious)
            previousButton.translatesAutoresizingMaskIntoConstraints = false

            nextButton.bezelStyle = .texturedRounded
            nextButton.controlSize = .small
            nextButton.image = NSImage(systemSymbolName: "chevron.down", accessibilityDescription: "Next match")
            nextButton.target = self
            nextButton.action = #selector(handleFindNext)
            nextButton.translatesAutoresizingMaskIntoConstraints = false

            closeButton.bezelStyle = .texturedRounded
            closeButton.controlSize = .small
            closeButton.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: "Close search")
            closeButton.target = self
            closeButton.action = #selector(handleClose)
            closeButton.translatesAutoresizingMaskIntoConstraints = false

            addSubview(searchField)
            addSubview(previousButton)
            addSubview(nextButton)
            addSubview(closeButton)

            NSLayoutConstraint.activate([
                searchField.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
                searchField.centerYAnchor.constraint(equalTo: centerYAnchor),
                searchField.widthAnchor.constraint(equalToConstant: 220),
                previousButton.leadingAnchor.constraint(equalTo: searchField.trailingAnchor, constant: 8),
                previousButton.centerYAnchor.constraint(equalTo: centerYAnchor),
                nextButton.leadingAnchor.constraint(equalTo: previousButton.trailingAnchor, constant: 6),
                nextButton.centerYAnchor.constraint(equalTo: centerYAnchor),
                closeButton.leadingAnchor.constraint(equalTo: nextButton.trailingAnchor, constant: 6),
                closeButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
                closeButton.centerYAnchor.constraint(equalTo: centerYAnchor),
                topAnchor.constraint(equalTo: searchField.topAnchor, constant: -10),
                bottomAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 10)
            ])
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        var query: String {
            searchField.stringValue
        }

        func show(animated: Bool) {
            guard isHidden || alphaValue < 1 else {
                focus()
                return
            }

            isHidden = false
            if animated {
                alphaValue = 0
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.14
                    animator().alphaValue = 1
                }
            } else {
                alphaValue = 1
            }
            focus()
        }

        func hide(animated: Bool) {
            if animated {
                NSAnimationContext.runAnimationGroup({ context in
                    context.duration = 0.14
                    animator().alphaValue = 0
                }, completionHandler: { [weak self] in
                    Task { @MainActor [weak self] in
                        self?.alphaValue = 0
                        self?.isHidden = true
                    }
                })
            } else {
                alphaValue = 0
                isHidden = true
            }
        }

        func focus() {
            window?.makeFirstResponder(searchField)
            searchField.selectText(nil)
        }

        @objc private func handleSearchChanged() {
            onSearchChange?(searchField.stringValue)
        }

        @objc private func handleFindPrevious() {
            onFindPrevious?(searchField.stringValue)
        }

        @objc private func handleFindNext() {
            onFindNext?(searchField.stringValue)
        }

        @objc private func handleClose() {
            onClose?()
        }
    }

    let webView: WKWebView
    var externalNavigationHandler: ((URL) -> Void)?
    var authenticationSessionStarter: ((URL, String) -> Bool)?
    var appNavigationHandler: ((URL) -> Bool)?
    var addAgentCandidateHandler: ((WebAddPresetCandidate?) -> Void)?
    var conversationTitleHandler: ((String?) -> Void)?
    var responseCompletionHandler: ((WebResponseCompletion) -> Void)?
    var debugLoggingEnabled = false
    private(set) var currentConversationTitle: String?
    private(set) var isGeneratingResponse = false
    private var hasLoadedRemoteContent = false
    private var externalNavigationPolicy: ExternalNavigationPolicy = .singleHost(nil)
    private var popupWindowControllers: [ObjectIdentifier: PopupWindowController] = [:]
    private var popupNavigationPolicies: [ObjectIdentifier: ExternalNavigationPolicy] = [:]
    private let logMessageHandler = ScriptMessageHandler()
    private let addAgentMessageHandler = DictionaryMessageHandler()
    private let launcherProgressMessageHandler = DictionaryMessageHandler()
    private let desktopEventMessageHandler = DictionaryMessageHandler()
    private let launcherProgressBadgeView = LauncherProgressBadgeView()
    private let conversationSearchBarView = ConversationSearchBarView()
    private var pendingLauncherProgressShow: DispatchWorkItem?
    private var pendingLauncherProgressHide: DispatchWorkItem?
    private var pendingQueuedAttachments: [URL] = []
    private var pendingAttachmentPickerRetry: DispatchWorkItem?
    private var pendingAttachmentPickerRetryCount = 0
    private var currentSettings = AppSettings()

    init() {
        let configuration = WKWebViewConfiguration()
        configuration.allowsAirPlayForMediaPlayback = false
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = true
        // These scripts are injected before the page app boots so launcher navigation can seed state early.
        configuration.userContentController.add(logMessageHandler, name: Self.logHandlerName)
        configuration.userContentController.add(addAgentMessageHandler, name: Self.addAgentCandidateHandlerName)
        configuration.userContentController.add(launcherProgressMessageHandler, name: Self.launcherProgressHandlerName)
        configuration.userContentController.add(desktopEventMessageHandler, name: Self.desktopEventHandlerName)
        configuration.userContentController.addUserScript(
            WKUserScript(
                source: Self.loggerBootstrapScript,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: false
            )
        )
        configuration.userContentController.addUserScript(
            WKUserScript(
                source: Self.launcherBootstrapScript,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: true
            )
        )
        configuration.userContentController.addUserScript(
            WKUserScript(
                source: Self.addAgentObserverScript,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: true
            )
        )
        configuration.userContentController.addUserScript(
            WKUserScript(
                source: Self.desktopStateObserverScript,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: true
            )
        )
        self.webView = WKWebView(frame: .zero, configuration: configuration)
        super.init(nibName: nil, bundle: nil)
        self.webView.navigationDelegate = self
        self.webView.uiDelegate = self
        self.webView.allowsBackForwardNavigationGestures = true
        logMessageHandler.onMessage = { [weak self] message in
            self?.debugLog("KotobaLibre SPA: \(message)")
        }
        addAgentMessageHandler.onMessage = { [weak self] body in
            self?.addAgentCandidateHandler?(Self.parseAddAgentCandidate(from: body))
        }
        launcherProgressMessageHandler.onMessage = { [weak self] body in
            self?.handleLauncherProgressMessage(body)
        }
        desktopEventMessageHandler.onMessage = { [weak self] body in
            self?.handleDesktopEventMessage(body)
        }
        conversationSearchBarView.onSearchChange = { [weak self] query in
            self?.runConversationSearch(query: query, backwards: false)
        }
        conversationSearchBarView.onFindPrevious = { [weak self] query in
            self?.runConversationSearch(query: query, backwards: true)
        }
        conversationSearchBarView.onFindNext = { [weak self] query in
            self?.runConversationSearch(query: query, backwards: false)
        }
        conversationSearchBarView.onClose = { [weak self] in
            self?.conversationSearchBarView.hide(animated: true)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        let containerView = NSView()
        containerView.addSubview(webView)
        containerView.addSubview(launcherProgressBadgeView)
        containerView.addSubview(conversationSearchBarView)
        webView.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            webView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            webView.topAnchor.constraint(equalTo: containerView.topAnchor),
            webView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),
            launcherProgressBadgeView.centerXAnchor.constraint(equalTo: containerView.centerXAnchor),
            launcherProgressBadgeView.topAnchor.constraint(equalTo: containerView.topAnchor, constant: 18),
            launcherProgressBadgeView.widthAnchor.constraint(lessThanOrEqualToConstant: 260),
            conversationSearchBarView.topAnchor.constraint(equalTo: containerView.topAnchor, constant: 18),
            conversationSearchBarView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -18)
        ])

        view = containerView
    }

    func apply(settings: AppSettings) {
        // Navigation decisions depend on the latest settings even while the web view instance is reused.
        currentSettings = settings
        debugLoggingEnabled = settings.debugLoggingEnabled
    }

    var canNavigateBack: Bool {
        webView.canGoBack
    }

    var canNavigateForward: Bool {
        webView.canGoForward
    }

    func load(url: URL) {
        if isLauncherChatTransition(url) {
            showLauncherProgress("Loading agent…")
        } else {
            hideLauncherProgress(animated: false)
        }
        hasLoadedRemoteContent = true
        debugLog("KotobaLibre SPA: load(url:) -> \(url.absoluteString)")
        webView.load(appNavigationRequest(for: url))
    }

    func open(url: URL, settings: AppSettings, instanceHost: String?, forceEmbedAllHosts: Bool = false, forceReload: Bool = false) {
        let shouldShowLauncherProgress = isLauncherChatTransition(url)
        apply(settings: settings)
        if forceEmbedAllHosts {
            externalNavigationPolicy = .embedAllHosts
        } else {
            externalNavigationPolicy = .singleHost(embeddedHost(for: url, instanceHost: instanceHost, settings: settings))
        }

        // Same-host launches can stay inside the existing SPA once remote content has loaded at least once.
        if !forceReload, KotobaLibreCore.canUseSPANavigation(instanceHost: instanceHost, url: url), hasLoadedRemoteContent {
            if shouldShowLauncherProgress {
                showLauncherProgress("Opening agent…")
            }
            let script = spaNavigationScript(
                destination: url.absoluteString,
                useRouteReload: settings.useRouteReloadForLauncherChats
            )
            webView.evaluateJavaScript(script) { [weak self] _, error in
                if let error {
                    let message = error.localizedDescription
                    self?.debugLog("KotobaLibre SPA: evaluateJavaScript failed -> \(message)")
                    if message.localizedCaseInsensitiveContains("unsupported type") {
                        self?.debugLog("KotobaLibre SPA: ignoring unsupported evaluateJavaScript return type")
                        return
                    }
                    self?.showLauncherProgress("Reloading agent…", delay: 0)
                    self?.load(url: url)
                }
            }
            return
        }

        load(url: url)
    }

    func queueAttachment(urls: [URL]) {
        cancelPendingAttachmentPickerRetry(resetCounter: true)
        pendingQueuedAttachments = Array(urls.prefix(1))
    }

    func navigateBack() {
        guard webView.canGoBack else {
            return
        }

        webView.goBack()
    }

    func navigateForward() {
        guard webView.canGoForward else {
            return
        }

        webView.goForward()
    }

    func showConversationSearch() {
        conversationSearchBarView.show(animated: true)
    }

    func stopGenerating() -> Bool {
        guard isGeneratingResponse else {
            return false
        }

        let script = """
        (() => {
          try {
            const stopGenerating = globalThis.__kotobaLibreStopGenerating;
            return typeof stopGenerating === "function" ? stopGenerating() : false;
          } catch (_) {
            return false;
          }
        })();
        """
        webView.evaluateJavaScript(script) { [weak self] _, error in
            if let error {
                self?.debugLog("KotobaLibre Stop: evaluateJavaScript failed -> \(error.localizedDescription)")
            }
        }
        return true
    }

    func fetchCurrentAddAgentCandidate(completion: @escaping (WebAddPresetCandidate?) -> Void) {
        let script = """
        (() => {
          try {
            const readCandidate = globalThis.__kotobaLibreReadAddAgentCandidate;
            return typeof readCandidate === "function" ? readCandidate() : null;
          } catch (_) {
            return null;
          }
        })();
        """

        webView.evaluateJavaScript(script) { [weak self] result, error in
            if let error {
                self?.debugLog("KotobaLibre Add Agent: evaluateJavaScript failed -> \(error.localizedDescription)")
            }

            completion(Self.parseAddAgentCandidate(from: result as Any))
        }
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void
    ) {
        if navigationAction.shouldPerformDownload {
            decisionHandler(.download)
            return
        }

        guard let url = navigationAction.request.url else {
            decisionHandler(.allow)
            return
        }

        let currentEmbeddedHost: String? = switch navigationPolicy(for: webView) {
        case .embedAllHosts:
            webView.url?.host?.lowercased()
        case let .singleHost(host):
            host ?? webView.url?.host?.lowercased()
        }
        logNavigationAction(navigationAction, webView: webView, currentEmbeddedHost: currentEmbeddedHost)

        if routeAppNavigationIfNeeded(url, webView: webView, currentEmbeddedHost: currentEmbeddedHost) {
            debugLog("KotobaLibre Nav: decision=cancel reason=app-route url=\(url.absoluteString)")
            decisionHandler(.cancel)
            return
        }

        if promotePopupAuthenticationRequestIfNeeded(url, webView: webView) {
            debugLog("KotobaLibre Nav: decision=cancel reason=popup-auth-handoff url=\(url.absoluteString)")
            decisionHandler(.cancel)
            return
        }

        if shouldKeepPopupNavigationEmbedded(url, webView: webView) {
            debugLog("KotobaLibre Nav: decision=allow reason=popup-embedded url=\(url.absoluteString)")
            decisionHandler(.allow)
            return
        }

        if shouldOpenExternalNavigationInDefaultBrowser(url, webView: webView, currentEmbeddedHost: currentEmbeddedHost) {
            debugLog("KotobaLibre Nav: decision=cancel reason=browser-host-mismatch url=\(url.absoluteString)")
            externalNavigationHandler?(url)
            decisionHandler(.cancel)
            return
        }

        if shouldOpenExternally(url, currentEmbeddedHost: currentEmbeddedHost) {
            debugLog("KotobaLibre Nav: decision=cancel reason=external-browser url=\(url.absoluteString)")
            externalNavigationHandler?(url)
            decisionHandler(.cancel)
            return
        }

        if shouldReloadNavigationActionWithAppIdentityHeader(navigationAction) {
            debugLog("KotobaLibre Nav: decision=cancel reason=inject-header url=\(url.absoluteString)")
            webView.load(appNavigationRequest(for: navigationAction.request))
            decisionHandler(.cancel)
            return
        }

        debugLog("KotobaLibre Nav: decision=allow reason=default url=\(url.absoluteString)")
        decisionHandler(.allow)
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationResponse: WKNavigationResponse,
        decisionHandler: @escaping @MainActor @Sendable (WKNavigationResponsePolicy) -> Void
    ) {
        if !navigationResponse.canShowMIMEType {
            debugLog("KotobaLibre NavResponse: decision=download url=\(navigationResponse.response.url?.absoluteString ?? "<unknown>") mime=\(navigationResponse.response.mimeType ?? "<unknown>")")
            decisionHandler(.download)
            return
        }

        debugLog("KotobaLibre NavResponse: decision=allow url=\(navigationResponse.response.url?.absoluteString ?? "<unknown>") mime=\(navigationResponse.response.mimeType ?? "<unknown>")")
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, didReceiveServerRedirectForProvisionalNavigation navigation: WKNavigation!) {
        let currentEmbeddedHost: String? = switch navigationPolicy(for: webView) {
        case .embedAllHosts:
            webView.backForwardList.currentItem?.url.host?.lowercased()
        case let .singleHost(host):
            host ?? webView.backForwardList.currentItem?.url.host?.lowercased()
        }

        guard let redirectedURL = webView.url else {
            debugLog("KotobaLibre Redirect: missing redirected URL")
            return
        }

        if shouldOpenExternalNavigationInDefaultBrowser(
            redirectedURL,
            webView: webView,
            currentEmbeddedHost: currentEmbeddedHost
        ) {
            webView.stopLoading()
            externalNavigationHandler?(redirectedURL)
            debugLog("KotobaLibre Redirect: moved server redirect into browser -> \(redirectedURL.absoluteString)")
            return
        }

        debugLog("KotobaLibre Redirect: stayed-in-place url=\(redirectedURL.absoluteString) currentEmbeddedHost=\(currentEmbeddedHost ?? "<nil>")")
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        if webView == self.webView {
            cancelPendingAttachmentPickerRetry(resetCounter: false)
        }
        debugLog("KotobaLibre NavLifecycle: didStartProvisional url=\(webView.url?.absoluteString ?? "<unknown>")")
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        debugLog("KotobaLibre NavLifecycle: didCommit url=\(webView.url?.absoluteString ?? "<unknown>")")
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        if webView == self.webView {
            hasLoadedRemoteContent = true
            updateConversationTitle(webView.title)
            if !isLauncherAutoSubmitTransition(webView.url) {
                hideLauncherProgress()
            }
            attemptPendingAttachmentIfNeeded(resetRetryWindow: true)
        }
        popupWindowControllers[ObjectIdentifier(webView)]?.window?.title = webView.title ?? appDisplayName
        debugLog("KotobaLibre SPA: didFinish -> \(webView.url?.absoluteString ?? "<unknown>")")
    }

    // JavaScript popup requests need a native host window or WebKit silently drops them.
    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        let currentEmbeddedHost: String? = switch navigationPolicy(for: webView) {
        case .embedAllHosts:
            webView.url?.host?.lowercased()
        case let .singleHost(host):
            host ?? webView.url?.host?.lowercased()
        }

        if let url = navigationAction.request.url, routeAuthenticationRequestIfNeeded(for: url, from: webView.url) {
            debugLog("KotobaLibre Popup: intercepted createWebView auth handoff url=\(url.absoluteString)")
            return nil
        }

        if
            let url = navigationAction.request.url,
            shouldOpenExternally(url, currentEmbeddedHost: currentEmbeddedHost)
        {
            debugLog("KotobaLibre Popup: routed off-host popup request to external browser url=\(url.absoluteString)")
            externalNavigationHandler?(url)
            return nil
        }

        configuration.preferences.javaScriptCanOpenWindowsAutomatically = true

        let popupWebView = WKWebView(frame: .zero, configuration: configuration)
        showPopupWindow(for: popupWebView, windowFeatures: windowFeatures)
        debugLog("KotobaLibre Popup: created for \(navigationAction.request.url?.absoluteString ?? "<unknown>")")
        return popupWebView
    }

    func webViewDidClose(_ webView: WKWebView) {
        guard let popupWindowController = popupWindowControllers[ObjectIdentifier(webView)] else {
            return
        }

        popupWindowController.close()
    }

    // The media-permission delegate bridges WebKit page requests to the app-level capture permission.
    func webView(
        _ webView: WKWebView,
        requestMediaCapturePermissionFor origin: WKSecurityOrigin,
        initiatedByFrame frame: WKFrameInfo,
        type: WKMediaCaptureType,
        decisionHandler: @escaping @MainActor (WKPermissionDecision) -> Void
    ) {
        debugLog("KotobaLibre Media Capture: requested type \(type.rawValue) from \(origin.protocol)://\(origin.host)")

        switch type {
        case .microphone:
            decidePermission(for: .audio, decisionHandler: decisionHandler)
        case .camera:
            decidePermission(for: .video, decisionHandler: decisionHandler)
        case .cameraAndMicrophone:
            decidePermission(for: .audio) { microphoneDecision in
                guard microphoneDecision == .grant else {
                    decisionHandler(.deny)
                    return
                }

                self.decidePermission(for: .video, decisionHandler: decisionHandler)
            }
        @unknown default:
            decisionHandler(.deny)
        }
    }

    // macOS cancels file uploads unless the app provides the native picker via this delegate.
    func webView(
        _ webView: WKWebView,
        runOpenPanelWith parameters: WKOpenPanelParameters,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping @MainActor ([URL]?) -> Void
    ) {
        if !pendingQueuedAttachments.isEmpty {
            let urls = parameters.allowsMultipleSelection ? pendingQueuedAttachments : Array(pendingQueuedAttachments.prefix(1))
            cancelPendingAttachmentPickerRetry(resetCounter: true)
            pendingQueuedAttachments = []
            completionHandler(urls)
            return
        }

        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = parameters.allowsDirectories
        panel.allowsMultipleSelection = parameters.allowsMultipleSelection
        panel.resolvesAliases = true

        if panel.runModal() == .OK {
            completionHandler(panel.urls)
        } else {
            completionHandler(nil)
        }
    }

    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
        download.delegate = self
    }

    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
        download.delegate = self
    }

    // Downloads need an app-chosen writable destination before WebKit will start writing bytes.
    func download(
        _ download: WKDownload,
        decideDestinationUsing response: URLResponse,
        suggestedFilename: String,
        completionHandler: @escaping @MainActor (URL?) -> Void
    ) {
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = suggestedFilename
        panel.isExtensionHidden = false
        panel.directoryURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first

        if panel.runModal() == .OK {
            completionHandler(panel.url)
        } else {
            completionHandler(nil)
        }
    }

    func downloadDidFinish(_ download: WKDownload) {
        debugLog("KotobaLibre Download: finished")
    }

    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        debugLog("KotobaLibre Download: failed -> \(error.localizedDescription)")
    }

    private func decidePermission(
        for mediaType: AVMediaType,
        decisionHandler: @escaping @MainActor (WKPermissionDecision) -> Void
    ) {
        let currentStatus = MediaCaptureAuthorization.authorizationStatus(for: mediaType)
        switch currentStatus {
        case .authorized:
            decisionHandler(.grant)
        case .denied, .restricted:
            decisionHandler(.deny)
        case .notDetermined:
            MediaCaptureAuthorization.requestSystemAccess(for: mediaType) { updatedStatus in
                decisionHandler(updatedStatus == .authorized ? .grant : .deny)
            }
        @unknown default:
            decisionHandler(.deny)
        }
    }

    private func debugLog(_ message: String) {
        guard debugLoggingEnabled else {
            return
        }

        print(message)
    }

    private func handleDesktopEventMessage(_ rawValue: Any) {
        guard let payload = rawValue as? [String: Any], let type = payload["type"] as? String else {
            return
        }

        switch type {
        case "title":
            updateConversationTitle(payload["title"] as? String)
        case "response-started":
            isGeneratingResponse = true
        case "response-finished":
            isGeneratingResponse = false
            let title = payload["title"] as? String
            updateConversationTitle(title)
            let durationMilliseconds = payload["durationMs"] as? Double ?? 0
            responseCompletionHandler?(
                WebResponseCompletion(
                    conversationTitle: normalizedConversationTitle(title),
                    duration: durationMilliseconds / 1_000
                )
            )
        default:
            break
        }
    }

    private func updateConversationTitle(_ rawTitle: String?) {
        let normalizedTitle = normalizedConversationTitle(rawTitle)
        guard currentConversationTitle != normalizedTitle else {
            return
        }

        currentConversationTitle = normalizedTitle
        conversationTitleHandler?(normalizedTitle)
    }

    private func normalizedConversationTitle(_ rawTitle: String?) -> String? {
        let trimmedTitle = rawTitle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmedTitle.isEmpty ? nil : trimmedTitle
    }

    private func attemptPendingAttachmentIfNeeded(resetRetryWindow: Bool = false) {
        guard !pendingQueuedAttachments.isEmpty else {
            return
        }

        guard isReadyForQueuedAttachment else {
            debugLog("KotobaLibre Attach: discarding queued attachment because the page left the new chat route")
            clearQueuedAttachments()
            return
        }

        if resetRetryWindow {
            cancelPendingAttachmentPickerRetry(resetCounter: true)
        }

        let script = """
        (() => {
          try {
            const openAttachmentPicker = globalThis.__kotobaLibreOpenAttachmentPicker;
            return typeof openAttachmentPicker === "function" ? openAttachmentPicker() : false;
          } catch (_) {
            return false;
          }
        })();
        """
        webView.evaluateJavaScript(script) { [weak self] result, error in
            guard let self else {
                return
            }

            if let error {
                self.debugLog("KotobaLibre Attach: evaluateJavaScript failed -> \(error.localizedDescription)")
                self.scheduleAttachmentPickerRetryIfNeeded()
                return
            }

            let openedPicker = (result as? Bool) ?? ((result as? NSNumber)?.boolValue ?? false)
            if !openedPicker {
                self.debugLog("KotobaLibre Attach: page did not expose an attachment picker")
                self.scheduleAttachmentPickerRetryIfNeeded()
                return
            }

            self.cancelPendingAttachmentPickerRetry(resetCounter: true)
        }
    }

    private var isReadyForQueuedAttachment: Bool {
        guard let currentURL = webView.url else {
            return true
        }

        let path = currentURL.path.lowercased()
        return path == "/c/new" || path.hasPrefix("/c/new/")
    }

    private func scheduleAttachmentPickerRetryIfNeeded() {
        guard !pendingQueuedAttachments.isEmpty else {
            return
        }

        guard isReadyForQueuedAttachment else {
            debugLog("KotobaLibre Attach: clearing queued attachment after route changed")
            clearQueuedAttachments()
            return
        }

        guard pendingAttachmentPickerRetryCount < Self.attachmentPickerRetryLimit else {
            debugLog("KotobaLibre Attach: clearing queued attachment after retry limit")
            clearQueuedAttachments()
            return
        }

        pendingAttachmentPickerRetryCount += 1
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else {
                return
            }

            self.pendingAttachmentPickerRetry = nil
            self.attemptPendingAttachmentIfNeeded()
        }

        pendingAttachmentPickerRetry?.cancel()
        pendingAttachmentPickerRetry = workItem
        DispatchQueue.main.asyncAfter(
            deadline: .now() + Self.attachmentPickerRetryDelay,
            execute: workItem
        )
    }

    private func cancelPendingAttachmentPickerRetry(resetCounter: Bool) {
        pendingAttachmentPickerRetry?.cancel()
        pendingAttachmentPickerRetry = nil
        if resetCounter {
            pendingAttachmentPickerRetryCount = 0
        }
    }

    private func clearQueuedAttachments() {
        cancelPendingAttachmentPickerRetry(resetCounter: true)
        pendingQueuedAttachments = []
    }

    private func runConversationSearch(query: String, backwards: Bool) {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else {
            return
        }

        let configuration = WKFindConfiguration()
        configuration.backwards = backwards
        configuration.wraps = true
        webView.find(trimmedQuery, configuration: configuration) { [weak self] _ in
            self?.debugLog("KotobaLibre Search: query=\(trimmedQuery) backwards=\(backwards)")
        }
    }

    private func logNavigationAction(_ navigationAction: WKNavigationAction, webView: WKWebView, currentEmbeddedHost: String?) {
        guard let url = navigationAction.request.url else {
            debugLog("KotobaLibre Nav: request missing URL")
            return
        }

        let sourceURL = webView.url?.absoluteString ?? "<nil>"
        let targetFrameDescription: String
        if let targetFrame = navigationAction.targetFrame {
            targetFrameDescription = targetFrame.isMainFrame ? "main" : "subframe"
        } else {
            targetFrameDescription = "new-window"
        }

        debugLog(
            """
            KotobaLibre Nav: request url=\(url.absoluteString) source=\(sourceURL) \
            currentEmbeddedHost=\(currentEmbeddedHost ?? "<nil>") targetFrame=\(targetFrameDescription) \
            navType=\(navigationTypeDescription(navigationAction.navigationType))
            """
        )
    }

    private func navigationTypeDescription(_ navigationType: WKNavigationType) -> String {
        switch navigationType {
        case .linkActivated:
            return "linkActivated"
        case .formSubmitted:
            return "formSubmitted"
        case .backForward:
            return "backForward"
        case .reload:
            return "reload"
        case .formResubmitted:
            return "formResubmitted"
        case .other:
            return "other"
        @unknown default:
            return "unknown"
        }
    }

    private func handleLauncherProgressMessage(_ rawValue: Any) {
        guard let payload = rawValue as? [String: Any] else {
            return
        }

        guard let phase = payload["phase"] as? String else {
            return
        }

        switch phase {
        case "loading-page", "opening-agent":
            showLauncherProgress("Opening agent…")
        case "page-ready", "waiting-for-editor":
            showLauncherProgress("Waiting for editor…", delay: 0)
        case "preparing-prompt":
            showLauncherProgress("Preparing prompt…", delay: 0)
        case "submitting-prompt":
            showLauncherProgress("Submitting prompt…", delay: 0)
        case "route-remount":
            showLauncherProgress("Refreshing chat…", delay: 0)
        case "reloading-page":
            showLauncherProgress("Reloading agent…", delay: 0)
        case "submitted":
            hideLauncherProgress(delay: 0.35)
        case "ready":
            hideLauncherProgress()
        default:
            break
        }
    }

    private func showLauncherProgress(_ message: String, delay: TimeInterval = 0.15) {
        pendingLauncherProgressHide?.cancel()
        pendingLauncherProgressHide = nil
        launcherProgressBadgeView.setMessage(message)

        let workItem = DispatchWorkItem { [weak self] in
            guard let self else {
                return
            }

            self.pendingLauncherProgressShow = nil
            self.launcherProgressBadgeView.show(animated: true)
        }

        pendingLauncherProgressShow?.cancel()
        pendingLauncherProgressShow = workItem

        if delay <= 0 {
            workItem.perform()
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
        }
    }

    private func hideLauncherProgress(animated: Bool = true, delay: TimeInterval = 0.2) {
        pendingLauncherProgressShow?.cancel()
        pendingLauncherProgressShow = nil

        let workItem = DispatchWorkItem { [weak self] in
            guard let self else {
                return
            }

            self.pendingLauncherProgressHide = nil
            self.launcherProgressBadgeView.hide(animated: animated)
        }

        pendingLauncherProgressHide?.cancel()
        pendingLauncherProgressHide = workItem

        if delay <= 0 {
            workItem.perform()
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
        }
    }

    private func isLauncherChatTransition(_ url: URL?) -> Bool {
        guard let url, let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return false
        }

        let path = components.path.lowercased()
        let isNewChatPath =
            path == "/c/new" ||
            path.hasPrefix("/c/new/") ||
            path.hasSuffix("/c/new") ||
            path.contains("/c/new/")
        guard isNewChatPath else {
            return false
        }

        let queryItems = components.queryItems ?? []
        return queryItems.contains(where: { item in
            let key = item.name.lowercased()
            return key == "agent_id" || key == "prompt" || key == "q"
        })
    }

    private func isLauncherAutoSubmitTransition(_ url: URL?) -> Bool {
        guard let url, let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return false
        }

        let queryItems = components.queryItems ?? []
        let hasPrompt = queryItems.contains(where: { item in
            let key = item.name.lowercased()
            return (key == "prompt" || key == "q") && !(item.value ?? "").isEmpty
        })
        let requestsSubmit = queryItems.contains(where: { item in
            item.name.caseInsensitiveCompare("submit") == .orderedSame &&
                (item.value ?? "").caseInsensitiveCompare("true") == .orderedSame
        })

        return hasPrompt && requestsSubmit
    }

    private func embeddedHost(for url: URL, instanceHost: String?, settings: AppSettings) -> String? {
        if settings.restrictHostToInstanceHost {
            return instanceHost
        }

        // When host restriction is off, embed whichever host the user intentionally opened.
        guard let host = url.host?.lowercased() else {
            return instanceHost
        }

        if let instanceHost, host.caseInsensitiveCompare(instanceHost) == .orderedSame {
            return instanceHost
        }

        return host
    }

    private func navigationPolicy(for webView: WKWebView) -> ExternalNavigationPolicy {
        popupNavigationPolicies[ObjectIdentifier(webView)] ?? externalNavigationPolicy
    }

    private func routeAppNavigationIfNeeded(_ url: URL, webView: WKWebView, currentEmbeddedHost: String?) -> Bool {
        guard shouldRouteThroughApp(url, currentEmbeddedHost: currentEmbeddedHost) else {
            return false
        }

        let handled = appNavigationHandler?(url) ?? false
        if handled, popupWindowControllers[ObjectIdentifier(webView)] != nil {
            popupWindowControllers[ObjectIdentifier(webView)]?.close()
        }
        return handled
    }

    private func shouldRouteThroughApp(_ url: URL, currentEmbeddedHost: String?) -> Bool {
        let scheme = url.scheme?.lowercased()
        if scheme == Self.supportedAuthenticationCallbackScheme {
            return true
        }

        guard
            scheme == "https",
            url.path.hasPrefix("/app/"),
            let currentEmbeddedHost,
            let host = url.host?.lowercased()
        else {
            return false
        }

        return host.caseInsensitiveCompare(currentEmbeddedHost) == .orderedSame
    }

    private func shouldReloadNavigationActionWithAppIdentityHeader(_ navigationAction: WKNavigationAction) -> Bool {
        // WebKit only lets us replace top-level loads, so subframe requests keep their original headers.
        guard navigationAction.targetFrame?.isMainFrame != false else {
            return false
        }

        guard let url = navigationAction.request.url, url.scheme?.lowercased() == "https" else {
            return false
        }

        return navigationAction.request.value(forHTTPHeaderField: Self.appIdentityHeaderName) != Self.appIdentityHeaderValue
    }

    private func appNavigationRequest(for url: URL) -> URLRequest {
        appNavigationRequest(for: URLRequest(url: url))
    }

    private func appNavigationRequest(for request: URLRequest) -> URLRequest {
        // The site reads this header to identify embedded app requests and the running app version.
        var updatedRequest = request
        updatedRequest.setValue(Self.appIdentityHeaderValue, forHTTPHeaderField: Self.appIdentityHeaderName)
        return updatedRequest
    }

    private func shouldOpenExternalNavigationInDefaultBrowser(
        _ url: URL,
        webView: WKWebView,
        currentEmbeddedHost: String?
    ) -> Bool {
        guard currentSettings.openExternalAuthenticationLinksInNewWindow else {
            return false
        }

        guard popupWindowControllers[ObjectIdentifier(webView)] == nil else {
            return false
        }

        return shouldOpenExternally(url, currentEmbeddedHost: currentEmbeddedHost)
    }
    private func showPopupWindow(for popupWebView: WKWebView, windowFeatures: WKWindowFeatures? = nil) {
        popupWebView.navigationDelegate = self
        popupWebView.uiDelegate = self
        popupWebView.allowsBackForwardNavigationGestures = true

        let popupWindowController: PopupWindowController
        if let windowFeatures {
            popupWindowController = PopupWindowController(webView: popupWebView, windowFeatures: windowFeatures)
        } else {
            popupWindowController = PopupWindowController(webView: popupWebView)
        }

        let popupIdentifier = ObjectIdentifier(popupWebView)
        popupWindowControllers[popupIdentifier] = popupWindowController
        popupNavigationPolicies[popupIdentifier] = .embedAllHosts
        popupWindowController.onClose = { [weak self, weak popupWebView] in
            guard let self, let popupWebView else {
                return
            }

            self.cleanupPopupWindow(for: popupWebView)
        }
        popupWindowController.showAndFocus()
    }

    private func startAuthenticationSessionIfPossible(for url: URL) -> Bool {
        guard let callbackScheme = authenticationCallbackScheme(in: url) else {
            return false
        }

        return authenticationSessionStarter?(url, callbackScheme) == true
    }

    private func routeAuthenticationRequestIfNeeded(for url: URL, from sourceURL: URL? = nil) -> Bool {
        guard currentSettings.openExternalAuthenticationLinksInNewWindow else {
            return false
        }

        guard looksLikeAuthenticationTransition(to: url, from: sourceURL) else {
            return false
        }

        if startAuthenticationSessionIfPossible(for: url) {
            debugLog("KotobaLibre Auth: routed popup through ASWebAuthenticationSession -> \(url.absoluteString)")
            return true
        }

        externalNavigationHandler?(url)
        debugLog("KotobaLibre Auth: fell back to external browser -> \(url.absoluteString)")
        return true
    }

    private func promotePopupAuthenticationRequestIfNeeded(_ url: URL, webView: WKWebView) -> Bool {
        guard popupWindowControllers[ObjectIdentifier(webView)] != nil else {
            return false
        }

        guard routeAuthenticationRequestIfNeeded(for: url, from: webView.url) else {
            return false
        }

        popupWindowControllers[ObjectIdentifier(webView)]?.close()
        return true
    }

    private func shouldKeepPopupNavigationEmbedded(_ url: URL, webView: WKWebView) -> Bool {
        guard popupWindowControllers[ObjectIdentifier(webView)] != nil else {
            return false
        }

        let scheme = url.scheme?.lowercased()
        return scheme == "https" || scheme == "about"
    }

    private func looksLikeAuthenticationURL(_ url: URL) -> Bool {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return false
        }

        let host = url.host?.lowercased() ?? ""
        let path = url.path.lowercased()
        let queryItemNames = Set((components.queryItems ?? []).map { $0.name.lowercased() })

        if host.contains("auth") || host.contains("login") || host.contains("oauth") {
            return true
        }

        if path.contains("/oauth") || path.contains("/authorize") || path.contains("/auth/") || path.contains("/login") || path.contains("/signin") || path.contains("/saml") {
            return true
        }

        let authQueryKeys: Set<String> = [
            "client_id",
            "redirect_uri",
            "redirect_url",
            "response_type",
            "scope",
            "state",
            "code_challenge",
            "code_challenge_method",
            "login_hint",
            "prompt"
        ]
        return !queryItemNames.isDisjoint(with: authQueryKeys)
    }

    private func looksLikeAuthenticationTransition(to destinationURL: URL, from sourceURL: URL?) -> Bool {
        if looksLikeAuthenticationURL(destinationURL) {
            return true
        }

        guard let sourceURL else {
            return false
        }

        return looksLikeAuthenticationURL(sourceURL)
    }

    private func authenticationCallbackScheme(in url: URL) -> String? {
        guard let callbackURL = authenticationCallbackURL(in: url) else {
            return nil
        }

        guard callbackURL.scheme?.lowercased() == Self.supportedAuthenticationCallbackScheme else {
            return nil
        }

        return Self.supportedAuthenticationCallbackScheme
    }

    private func authenticationCallbackURL(in url: URL) -> URL? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }

        let callbackKeys: Set<String> = [
            "redirect_uri",
            "redirect_url",
            "redirecturl",
            "redirect",
            "return_to",
            "returnto",
            "callback",
            "callback_url"
        ]

        for item in components.queryItems ?? [] {
            guard callbackKeys.contains(item.name.lowercased()) else {
                continue
            }

            guard let value = item.value, let callbackURL = decodedURL(from: value) else {
                continue
            }

            return callbackURL
        }

        return nil
    }

    private func decodedURL(from rawValue: String) -> URL? {
        if let directURL = URL(string: rawValue) {
            return directURL
        }

        guard let decodedValue = rawValue.removingPercentEncoding else {
            return nil
        }

        return URL(string: decodedValue)
    }

    private func cleanupPopupWindow(for webView: WKWebView) {
        let popupIdentifier = ObjectIdentifier(webView)
        popupNavigationPolicies.removeValue(forKey: popupIdentifier)
        if let popupWindowController = popupWindowControllers.removeValue(forKey: popupIdentifier) {
            popupWindowController.window?.delegate = nil
        }
        webView.navigationDelegate = nil
        webView.uiDelegate = nil
    }

    private func shouldOpenExternally(_ url: URL, currentEmbeddedHost: String?) -> Bool {
        let scheme = url.scheme?.lowercased()
        if scheme == "about" {
            return false
        }

        if scheme != "https" {
            return true
        }

        guard let currentEmbeddedHost else {
            return false
        }

        guard let host = url.host?.lowercased() else {
            return true
        }

        return host.caseInsensitiveCompare(currentEmbeddedHost) != .orderedSame
    }

    private static let loggerBootstrapScript = """
    (() => {
      const postMessage = (...parts) => {
        const message = parts.map((part) => {
          if (typeof part === "string") return part;
          try {
            return JSON.stringify(part);
          } catch (_) {
            return String(part);
          }
        }).join(" ");
        try {
          window.webkit?.messageHandlers?.\(logHandlerName).postMessage(message);
        } catch (_) {
        }
        try {
          console.debug("[KotobaLibre SPA]", ...parts);
        } catch (_) {
        }
      };
      globalThis.__kotobaLibreLog = postMessage;
      postMessage("logger bootstrap", window.location.href);
    })();
    """

    private static let launcherBootstrapScript = """
    (() => {
      const postLauncherProgress = (phase) => {
        try {
          window.webkit?.messageHandlers?.\(launcherProgressHandlerName).postMessage({ phase });
        } catch (_) {
        }
      };
      try {
        const url = new URL(window.location.href);
        if (!(url.pathname === "/c/new" || url.pathname.startsWith("/c/new/"))) return;
        const agentId = url.searchParams.get("agent_id");
        const prompt = url.searchParams.get("prompt") ?? url.searchParams.get("q") ?? "";
        const shouldAutoSubmit =
          (url.searchParams.get("submit") ?? "").toLowerCase() === "true" &&
          prompt.length > 0;
        if (shouldAutoSubmit) {
          postLauncherProgress("loading-page");
          window.addEventListener("load", () => postLauncherProgress("page-ready"), { once: true });
        }
        if (agentId) {
          localStorage.setItem("agent_id__0", agentId);
          globalThis.__kotobaLibreLog?.("launcher bootstrap seeded agent_id__0", agentId);
        }
      } catch (_) {
      }
    })();
    """

    private static let addAgentObserverScript = """
    (() => {
      const trimText = (value) => typeof value === "string" ? value.trim() : "";
      const basePath = () => {
        const baseHref = document.querySelector("base")?.getAttribute("href") ?? "/";
        try {
          const value = new URL(baseHref, window.location.origin).pathname || "/";
          if (value === "/") return "";
          return value.endsWith("/") ? value.slice(0, -1) : value;
        } catch (_) {
          return "";
        }
      };
      const routePath = (url) => {
        let pathname = url.pathname;
        const currentBasePath = basePath();
        if (currentBasePath && pathname === currentBasePath) {
          pathname = "/";
        } else if (currentBasePath && pathname.startsWith(`${currentBasePath}/`)) {
          pathname = pathname.slice(currentBasePath.length) || "/";
        }
        if (!pathname.startsWith("/")) {
          pathname = `/${pathname}`;
        }
        return pathname;
      };
      const prettifyWords = (value) => {
        const normalized = trimText(value)
          .replace(/(\\d)-(?=\\d)/g, "$1.")
          .replace(/[-_]+/g, " ")
          .replace(/\\s+/g, " ");
        if (!normalized) {
          return "";
        }
        return normalized
          .split(" ")
          .map((word) => word ? word.charAt(0).toUpperCase() + word.slice(1) : "")
          .join(" ");
      };
      const readCandidate = () => {
        try {
          const url = new URL(window.location.href);
          const currentRoutePath = routePath(url);
          const agentID = trimText(url.searchParams.get("agent_id") ?? "");
          if (currentRoutePath.startsWith("/agents") && agentID) {
            return {
              sourceURL: url.href,
              presetKind: "agent",
              presetValue: agentID,
              presetName: trimText(document.querySelector('div[role="dialog"] h2')?.textContent ?? ""),
            };
          }

          const endpoint = trimText(url.searchParams.get("endpoint") ?? "");
          const model = trimText(url.searchParams.get("model") ?? "");
          if (currentRoutePath === "/c/new" && endpoint && model) {
            return {
              sourceURL: url.href,
              presetKind: "link",
              presetValue: url.href,
              presetName: [prettifyWords(endpoint), prettifyWords(model)].filter(Boolean).join(" "),
            };
          }

          return null;
        } catch (_) {
          return null;
        }
      };
      const postCandidate = () => {
        try {
          window.webkit?.messageHandlers?.\(addAgentCandidateHandlerName).postMessage(readCandidate());
        } catch (_) {
        }
      };
      let queued = false;
      const schedule = () => {
        if (queued) return;
        queued = true;
        queueMicrotask(() => {
          queued = false;
          postCandidate();
        });
      };
      const wrapHistory = (methodName) => {
        const original = history[methodName];
        if (typeof original !== "function") return;
        history[methodName] = function(...args) {
          const result = original.apply(this, args);
          schedule();
          return result;
        };
      };
      wrapHistory("pushState");
      wrapHistory("replaceState");
      globalThis.__kotobaLibreReadAddAgentCandidate = readCandidate;
      window.addEventListener("popstate", schedule);
      window.addEventListener("hashchange", schedule);
      window.addEventListener("load", schedule);
      document.addEventListener("readystatechange", schedule);
      const observer = new MutationObserver(schedule);
      const beginObserving = () => {
        if (!document.documentElement) return;
        observer.observe(document.documentElement, {
          subtree: true,
          childList: true,
          characterData: true,
        });
      };
      beginObserving();
      schedule();
    })();
    """

    private static let desktopStateObserverScript = """
    (() => {
      const postDesktopEvent = (type, payload = {}) => {
        try {
          window.webkit?.messageHandlers?.\(desktopEventHandlerName).postMessage({ type, ...payload });
        } catch (_) {
        }
      };
      const trimText = (value) => typeof value === "string" ? value.trim() : "";
      const selectorList = [
        "[data-testid='stop-generating-button']",
        "[data-testid='stop-button']",
        "button[aria-label*='Stop' i]",
        "button[title*='Stop' i]",
        "button[data-testid='send-button'][aria-label*='Stop' i]",
        "button[data-testid='send-button'][title*='Stop' i]",
      ];
      const findStopButton = () => {
        for (const selector of selectorList) {
          const match = document.querySelector(selector);
          if (match instanceof HTMLElement && !match.hasAttribute("disabled")) {
            return match;
          }
        }
        const buttons = Array.from(document.querySelectorAll("button"));
        return buttons.find((button) => {
          if (!(button instanceof HTMLElement) || button.hasAttribute("disabled")) {
            return false;
          }
          const description = [
            button.getAttribute("aria-label") ?? "",
            button.getAttribute("title") ?? "",
            button.textContent ?? "",
          ].join(" ").toLowerCase();
          return description.includes("stop") && description.includes("generat");
        }) ?? null;
      };
      const fileInputSelectors = [
        "input[type='file']",
        "input[type='file'][multiple]",
      ];
      const attachmentButtonSelectors = [
        "[data-testid='attach-file-button']",
        "[data-testid='upload-button']",
        "button[aria-label*='Attach' i]",
        "button[aria-label*='Upload' i]",
        "button[title*='Attach' i]",
        "button[title*='Upload' i]",
      ];
      const openAttachmentPicker = () => {
        for (const selector of fileInputSelectors) {
          const input = document.querySelector(selector);
          if (input instanceof HTMLInputElement && !input.disabled) {
            input.click();
            return true;
          }
        }
        for (const selector of attachmentButtonSelectors) {
          const button = document.querySelector(selector);
          if (button instanceof HTMLElement && !button.hasAttribute("disabled")) {
            button.click();
            return true;
          }
        }
        return false;
      };
      const state = {
        title: "",
        isGenerating: false,
        generationStartedAt: 0,
      };
      const currentTitle = () => trimText(document.title);
      const syncTitle = () => {
        const title = currentTitle();
        if (title === state.title) return;
        state.title = title;
        postDesktopEvent("title", { title });
      };
      const syncGeneration = () => {
        const isGenerating = !!findStopButton();
        if (isGenerating === state.isGenerating) return;
        state.isGenerating = isGenerating;
        if (isGenerating) {
          state.generationStartedAt = Date.now();
          postDesktopEvent("response-started", { title: currentTitle() });
          return;
        }
        const durationMs = state.generationStartedAt > 0 ? Date.now() - state.generationStartedAt : 0;
        state.generationStartedAt = 0;
        postDesktopEvent("response-finished", { title: currentTitle(), durationMs });
      };
      let queued = false;
      const scheduleSync = () => {
        if (queued) return;
        queued = true;
        queueMicrotask(() => {
          queued = false;
          syncTitle();
          syncGeneration();
        });
      };
      const wrapHistory = (methodName) => {
        const original = history[methodName];
        if (typeof original !== "function") return;
        history[methodName] = function(...args) {
          const result = original.apply(this, args);
          scheduleSync();
          return result;
        };
      };
      globalThis.__kotobaLibreStopGenerating = () => {
        const button = findStopButton();
        if (!(button instanceof HTMLElement)) {
          return false;
        }
        button.click();
        return true;
      };
      globalThis.__kotobaLibreOpenAttachmentPicker = openAttachmentPicker;
      wrapHistory("pushState");
      wrapHistory("replaceState");
      window.addEventListener("load", scheduleSync);
      window.addEventListener("hashchange", scheduleSync);
      window.addEventListener("popstate", scheduleSync);
      document.addEventListener("readystatechange", scheduleSync);
      const beginObserving = () => {
        const titleElement = document.querySelector("title");
        if (titleElement instanceof HTMLElement) {
          new MutationObserver(scheduleSync).observe(titleElement, {
            childList: true,
            characterData: true,
            subtree: true,
          });
        }
        if (!document.documentElement) {
          window.setTimeout(beginObserving, 50);
          return;
        }
        new MutationObserver(scheduleSync).observe(document.documentElement, {
          subtree: true,
          childList: true,
          attributes: true,
          attributeFilter: ["title", "aria-label", "disabled", "data-testid"],
        });
      };
      beginObserving();
      window.setInterval(syncGeneration, 750);
      scheduleSync();
    })();
    """

    private func spaNavigationScript(destination: String, useRouteReload: Bool) -> String {
        let payloadData = try? JSONEncoder().encode(destination)
        let payload = payloadData.flatMap { String(data: $0, encoding: .utf8) } ?? "\"\(destination)\""
        let routeReloadValue = useRouteReload ? "true" : "false"

        // The script tries several in-page navigation strategies before falling back to a full page load.
        // That keeps launcher opens fast while still working across LibreChat route changes.
        return """
        (() => {
          void (async function() {
            try {
            const log = (...parts) => {
              try {
                globalThis.__kotobaLibreLog?.(...parts);
              } catch (_) {
              }
            };
            const next = new URL(\(payload));
            const useRouteReloadForLauncherChats = \(routeReloadValue);
            const baseHref = document.querySelector("base")?.getAttribute("href") ?? "/";
            const basePath = (() => {
              try {
                const value = new URL(baseHref, window.location.origin).pathname || "/";
                if (value === "/") return "";
                return value.endsWith("/") ? value.slice(0, -1) : value;
              } catch (_) {
                return "";
              }
            })();
            const toAppPath = (urlLike) => {
              const value = new URL(urlLike, window.location.origin);
              return `${value.pathname}${value.search}${value.hash}`;
            };
            const toRouterPath = (urlLike) => {
              const value = new URL(urlLike, window.location.origin);
              let pathname = value.pathname;
              if (basePath && pathname === basePath) {
                pathname = "/";
              } else if (basePath && pathname.startsWith(`${basePath}/`)) {
                pathname = pathname.slice(basePath.length) || "/";
              }
              if (!pathname.startsWith("/")) {
                pathname = `/${pathname}`;
              }
              return `${pathname}${value.search}${value.hash}`;
            };
            const targetAppPath = toAppPath(next.href);
            const targetRouterPath = toRouterPath(next.href);
            const isNewChatTarget = next.pathname === "/c/new" || next.pathname.startsWith("/c/new/");
            const targetAgentId = next.searchParams.get("agent_id");
            const targetPrompt = next.searchParams.get("prompt") ?? next.searchParams.get("q") ?? "";
            const shouldAutoSubmitFromQuery =
              (next.searchParams.get("submit") ?? "").toLowerCase() === "true" &&
              (next.searchParams.has("prompt") || next.searchParams.has("q"));
            const postLauncherProgress = (phase) => {
              try {
                window.webkit?.messageHandlers?.\(Self.launcherProgressHandlerName).postMessage({ phase });
              } catch (_) {
              }
            };
            log("spa start", {
              href: next.href,
              targetAppPath,
              targetRouterPath,
              basePath,
              shouldAutoSubmitFromQuery,
              useRouteReloadForLauncherChats,
            });
            if (isNewChatTarget) {
              postLauncherProgress("opening-agent");
            }
            const seedLauncherSelection = () => {
              if (!isNewChatTarget) return;
              if (targetAgentId) {
                localStorage.setItem("agent_id__0", targetAgentId);
                log("seedLauncherSelection", targetAgentId);
              }
            };
            seedLauncherSelection();
            if (useRouteReloadForLauncherChats && shouldAutoSubmitFromQuery) {
              postLauncherProgress("reloading-page");
              log("branch route reload flag -> window.location.assign");
              window.location.assign(next.href);
              return;
            }
            const locationValue = () => `${window.location.pathname}${window.location.search}${window.location.hash}`;
            const isAtTargetLocation = () => locationValue() === targetAppPath;
            const delay = (ms) => new Promise((resolve) => window.setTimeout(resolve, ms));
            const nextVisualTick = () =>
              new Promise((resolve) => {
                if (typeof window.requestAnimationFrame === "function") {
                  window.requestAnimationFrame(() => resolve());
                  return;
                }
                window.setTimeout(resolve, 16);
              });
            const waitForCondition = async (predicate, timeoutMs, intervalMs = 30) => {
              const started = Date.now();
              while (Date.now() - started < timeoutMs) {
                if (predicate()) return true;
                await delay(intervalMs);
              }
              return predicate();
            };
            const waitForResult = async (resolver, timeoutMs = 5000, intervalMs = 30) => {
              const started = Date.now();
              while (Date.now() - started < timeoutMs) {
                const result = resolver();
                if (result) return result;
                await delay(intervalMs);
              }
              return resolver();
            };
            const waitForTargetLocation = async (timeoutMs) =>
              await waitForCondition(isAtTargetLocation, timeoutMs, 30);
            const waitForRouteToApply = async () => {
              await nextVisualTick();
              await nextVisualTick();
            };
            const pushWithHistory = (value) => {
              if (!(window.history && typeof window.history.pushState === "function")) return false;
              const current = locationValue();
              if (current !== value) {
                window.history.pushState({}, "", value);
                log("pushWithHistory", { from: current, to: value });
              }
              window.dispatchEvent(new PopStateEvent("popstate", { state: window.history.state }));
              document.dispatchEvent(new PopStateEvent("popstate", { state: window.history.state }));
              window.dispatchEvent(new Event("pushstate"));
              return true;
            };
            const routeWithRouter = async (value) => {
              const nextPush =
                globalThis.next?.router?.push ??
                globalThis.__next_router__?.push ??
                globalThis.__NEXT_ROUTER__?.push;
              if (typeof nextPush === "function") {
                log("routeWithRouter using push", value);
                const result = nextPush(value);
                if (result && typeof result.then === "function") await result;
                await waitForRouteToApply();
                const reached = await waitForTargetLocation(1200);
                log("routeWithRouter push result", reached);
                return reached;
              }
              const genericNavigate =
                globalThis.__next_router__?.navigate ??
                globalThis.__NEXT_ROUTER__?.navigate ??
                globalThis.__remixRouter?.navigate;
              if (typeof genericNavigate === "function") {
                log("routeWithRouter using navigate", value);
                const result = genericNavigate(value);
                if (result && typeof result.then === "function") await result;
                await waitForRouteToApply();
                const reached = await waitForTargetLocation(1200);
                log("routeWithRouter navigate result", reached);
                return reached;
              }
              log("routeWithRouter unavailable");
              return false;
            };
            const navigateWithHistoryAndWait = async (value, timeoutMs = 1200) => {
              const appPath = toAppPath(value);
              if (!pushWithHistory(appPath)) {
                log("navigateWithHistoryAndWait failed to push", appPath);
                return false;
              }
              await waitForRouteToApply();
              if (timeoutMs > 0) {
                const reached = await waitForTargetLocation(timeoutMs);
                log("navigateWithHistoryAndWait target location", { appPath, reached });
              }
              log("navigateWithHistoryAndWait complete", appPath);
              return true;
            };
            const navigateInternally = async (value, timeoutMs = 1200) => {
              const routerPath = toRouterPath(value);
              if (await routeWithRouter(routerPath)) return true;
              log("navigateInternally falling back to history", routerPath);
              return await navigateWithHistoryAndWait(value, timeoutMs);
            };
            const waitForElement = async (resolver, timeoutMs = 5000) =>
              await waitForResult(resolver, timeoutMs, 30);
            const findPromptTextarea = async (previousTextarea = null) => {
              const replacementWaitMs = previousTextarea ? 260 : 5000;
              const nextTextarea = await waitForElement(
                () => {
                  const candidate = document.getElementById("prompt-textarea");
                  if (!(candidate instanceof HTMLTextAreaElement)) return null;
                  if (previousTextarea && candidate === previousTextarea) return null;
                  return candidate;
                },
                replacementWaitMs,
              );
              if (nextTextarea instanceof HTMLTextAreaElement) {
                return nextTextarea;
              }
              // Some LibreChat transitions keep the same textarea mounted, so fall back instead of idling.
              const fallbackTextarea = document.getElementById("prompt-textarea");
              return fallbackTextarea instanceof HTMLTextAreaElement ? fallbackTextarea : null;
            };
            const setTextareaValue = (textarea, value) => {
              const prototype = window.HTMLTextAreaElement?.prototype;
              const descriptor = prototype && Object.getOwnPropertyDescriptor(prototype, "value");
              if (descriptor && typeof descriptor.set === "function") {
                descriptor.set.call(textarea, value);
              } else {
                textarea.value = value;
              }
              textarea.dispatchEvent(new Event("input", { bubbles: true }));
              textarea.dispatchEvent(new Event("change", { bubbles: true }));
            };
            const waitForTextareaValue = async (textarea, value, timeoutMs = 180) => {
              if (!(textarea instanceof HTMLTextAreaElement)) return false;
              return await waitForCondition(() => textarea.value === value, timeoutMs, 16);
            };
            const submitPromptViaChatForm = async (prompt, previousTextarea = null) => {
              if (!prompt) {
                postLauncherProgress("ready");
                return true;
              }
              postLauncherProgress("waiting-for-editor");
              const textarea = await findPromptTextarea(previousTextarea);
              if (!(textarea instanceof HTMLTextAreaElement)) {
                log("submitPromptViaChatForm missing textarea");
                return false;
              }
              postLauncherProgress("preparing-prompt");
              setTextareaValue(textarea, prompt);
              await waitForTextareaValue(textarea, prompt, 180);
              if (textarea.value !== prompt) {
                log("submitPromptViaChatForm restoring prompt after rerender", {
                  expected: prompt,
                  actual: textarea.value,
                });
                setTextareaValue(textarea, prompt);
                await waitForTextareaValue(textarea, prompt, 180);
              }
              textarea.focus();
              textarea.setSelectionRange(prompt.length, prompt.length);
              const sendButton = await waitForElement(
                () => document.querySelector("[data-testid='send-button']:not([disabled])"),
                5000,
              );
              if (!(sendButton instanceof HTMLElement)) {
                log("submitPromptViaChatForm missing send button");
                return false;
              }
              postLauncherProgress("submitting-prompt");
              log("submitPromptViaChatForm clicking send");
              sendButton.click();
              postLauncherProgress("submitted");
              return true;
            };
            const setStoredLauncherConversation = (agentId) => {
              if (!agentId) return;
              const storedConvo = {
                conversationId: "new",
                endpoint: "agents",
                agent_id: agentId,
                title: "New Chat",
              };
              localStorage.setItem("agent_id__0", agentId);
              localStorage.setItem("lastConversationSetup_0", JSON.stringify(storedConvo));
              log("setStoredLauncherConversation", storedConvo);
            };
            const unwrapReactRootFiber = (candidate) => {
              if (!candidate || typeof candidate !== "object") return null;
              if (candidate.current && typeof candidate.current === "object") {
                return candidate.current;
              }
              if (candidate._internalRoot?.current && typeof candidate._internalRoot.current === "object") {
                return candidate._internalRoot.current;
              }
              if (candidate.child || candidate.memoizedProps) {
                return candidate;
              }
              return null;
            };
            const getReactRootFiber = () => {
              const findContainerFiber = (element) => {
                if (!(element instanceof Element)) return null;
                for (const key of Object.keys(element)) {
                  if (!key.startsWith("__reactContainer$")) continue;
                  const fiber = unwrapReactRootFiber(element[key]);
                  if (fiber) return fiber;
                }
                return null;
              };
              const directCandidates = [
                document.getElementById("root"),
                document.querySelector("[data-reactroot]"),
                document.body,
                document.documentElement,
              ];
              for (const candidate of directCandidates) {
                const fiber = findContainerFiber(candidate);
                if (fiber) return fiber;
              }
              const walker = document.createTreeWalker(document.documentElement, NodeFilter.SHOW_ELEMENT);
              let current = walker.currentNode;
              while (current) {
                const fiber = findContainerFiber(current);
                if (fiber) return fiber;
                current = walker.nextNode();
              }
              return null;
            };
            const findFiberValue = (predicate) => {
              const rootFiber = getReactRootFiber();
              if (!rootFiber) {
                log("findFiberValue missing root fiber");
                return null;
              }
              const seen = new Set();
              const queue = [rootFiber];
              while (queue.length > 0) {
                const fiber = queue.shift();
                if (!fiber || seen.has(fiber)) continue;
                seen.add(fiber);
                const memoizedValue = fiber.memoizedProps?.value;
                if (predicate(memoizedValue, fiber)) {
                  return memoizedValue;
                }
                if (fiber.child) queue.push(fiber.child);
                if (fiber.sibling) queue.push(fiber.sibling);
              }
              return null;
            };
            const getChatContext = () =>
              findFiberValue((value) =>
                value &&
                typeof value === "object" &&
                typeof value.newConversation === "function" &&
                Object.prototype.hasOwnProperty.call(value, "conversation"),
              );
            const waitForChatContext = async (timeoutMs = 240) =>
              await waitForResult(() => getChatContext(), timeoutMs, 20);
            const waitForPlainNewConversation = async (timeoutMs = 5000) => {
              const started = Date.now();
              while (Date.now() - started < timeoutMs) {
                const chatContext = getChatContext();
                const conversation = chatContext?.conversation;
                if (
                  conversation &&
                  conversation.conversationId === "new" &&
                  !conversation.agent_id
                ) {
                  log("waitForPlainNewConversation ready", {
                    conversationId: conversation.conversationId,
                  });
                  return chatContext;
                }
                await delay(30);
              }
              log("waitForPlainNewConversation timed out");
              return getChatContext();
            };
            const waitForChatContextConversation = async (agentId, timeoutMs = 5000) => {
              const started = Date.now();
              while (Date.now() - started < timeoutMs) {
                const chatContext = getChatContext();
                const conversation = chatContext?.conversation;
                if (
                  conversation &&
                  conversation.conversationId === "new" &&
                  conversation.endpoint === "agents" &&
                  conversation.agent_id === agentId
                ) {
                  log("waitForChatContextConversation ready", {
                    conversationId: conversation.conversationId,
                    agentId: conversation.agent_id,
                  });
                  return chatContext;
                }
                await delay(30);
              }
              log("waitForChatContextConversation timed out", agentId);
              return getChatContext();
            };
            const startAgentChatViaReactContext = async () => {
              if (useRouteReloadForLauncherChats) return false;
              if (!isNewChatTarget) return false;
              const agentId = targetAgentId;
              if (!agentId) return false;
              const prompt = targetPrompt;
              try {
                const chatContext = await waitForChatContext(240);
                if (!chatContext) {
                  log("startAgentChatViaReactContext missing chat context");
                  return false;
                }
                const currentConversation =
                  chatContext.conversation && typeof chatContext.conversation === "object"
                    ? chatContext.conversation
                    : {};
                const template = {
                  ...currentConversation,
                  conversationId: "new",
                  endpoint: "agents",
                  agent_id: agentId,
                  title: "New Chat",
                };
                const preset = {
                  endpoint: "agents",
                  agent_id: agentId,
                  title: "New Chat",
                };
                setStoredLauncherConversation(agentId);
                log("startAgentChatViaReactContext invoking newConversation", {
                  previousConversationId: currentConversation?.conversationId ?? null,
                  agentId,
                });
                const previousTextarea = document.getElementById("prompt-textarea");
                chatContext.newConversation({ template, preset });
                // Start waiting for the fresh composer immediately so the prompt can land as soon as it remounts.
                const submitTask = submitPromptViaChatForm(prompt, previousTextarea);
                await waitForChatContextConversation(agentId, 5000);
                await waitForElement(
                  () =>
                    window.location.pathname === `${basePath}/c/new` ||
                    window.location.pathname === "/c/new"
                      ? document.body
                      : null,
                  5000,
                );
                if (window.history && typeof window.history.replaceState === "function") {
                  window.history.replaceState({}, "", targetAppPath);
                  log("startAgentChatViaReactContext replaced history", targetAppPath);
                }
                return await submitTask;
              } catch (error) {
                log("startAgentChatViaReactContext exception", String(error));
                return false;
              }
            };
            const findNativeNewChatTrigger = () => {
              const selectors = [
                "[data-testid='wide-header-new-chat-button']",
                "[data-testid='nav-new-chat-button']",
                "a[href='/c/new'][data-testid]",
                "button[aria-label='New Chat']",
              ];
              for (const selector of selectors) {
                const match = document.querySelector(selector);
                if (match instanceof HTMLElement && !match.hasAttribute("disabled")) {
                  return match;
                }
              }
              return null;
            };
            const startPlainNewConversation = async () => {
              if (!isNewChatTarget || targetAgentId) return false;
              const nativeTrigger = findNativeNewChatTrigger();
              if (!(nativeTrigger instanceof HTMLElement)) {
                log("startPlainNewConversation missing native trigger");
                return false;
              }
              log("startPlainNewConversation clicking native new chat");
              const previousTextarea = document.getElementById("prompt-textarea");
              nativeTrigger.click();
              const plainNewConversation = await waitForPlainNewConversation(5000);
              if (!plainNewConversation) {
                log("startPlainNewConversation missing new conversation state after click");
                return false;
              }
              await waitForElement(
                () =>
                  window.location.pathname === `${basePath}/c/new` ||
                  window.location.pathname === "/c/new"
                    ? document.body
                    : null,
                5000,
              );
              if (!targetPrompt) {
                postLauncherProgress("ready");
                return true;
              }
              return await submitPromptViaChatForm(targetPrompt, previousTextarea);
            };
            const startAgentChatViaMarketplace = async () => {
              if (!shouldAutoSubmitFromQuery || useRouteReloadForLauncherChats) return false;
              if (!isNewChatTarget) return false;
              const agentId = targetAgentId;
              const prompt = targetPrompt;
              if (!agentId) {
                log("startAgentChatViaMarketplace missing agent id");
                return false;
              }
              try {
                const response = await fetch(`${basePath}/api/agents/${encodeURIComponent(agentId)}`, {
                  credentials: "same-origin",
                });
                if (!response.ok) {
                  log("startAgentChatViaMarketplace fetch failed", response.status);
                  return false;
                }
                const agent = await response.json();
                const agentName = typeof agent?.name === "string" ? agent.name.trim() : "";
                const category = typeof agent?.category === "string" ? agent.category.trim() : "";
                const categoryPath = category && category !== "promoted"
                  ? `/agents/${encodeURIComponent(category)}`
                  : "/agents";
                const marketplaceParams = new URLSearchParams();
                if (agentName) marketplaceParams.set("q", agentName);
                marketplaceParams.set("tl_agent_id", agentId);
                const marketplaceTarget = `${categoryPath}?${marketplaceParams.toString()}`;
                log("startAgentChatViaMarketplace target", marketplaceTarget);
                if (!(await navigateInternally(marketplaceTarget, 450))) {
                  log("startAgentChatViaMarketplace failed to navigate to marketplace");
                  return false;
                }
                const agentCard = await waitForElement(() => {
                  const cards = Array.from(document.querySelectorAll("[role='button'][aria-label]"));
                  return cards.find((card) => {
                    const label = card.getAttribute("aria-label") ?? "";
                    return label.includes(agentName);
                  }) ?? null;
                }, 5000);
                if (!(agentCard instanceof HTMLElement)) {
                  log("startAgentChatViaMarketplace missing agent card", agentName);
                  return false;
                }
                log("startAgentChatViaMarketplace opening card", agentName);
                agentCard.click();
                const dialog = await waitForElement(
                  () => document.querySelector("[role='dialog']"),
                  5000,
                );
                if (!(dialog instanceof HTMLElement)) {
                  log("startAgentChatViaMarketplace missing dialog");
                  return false;
                }
                const buttons = Array.from(dialog.querySelectorAll("button:not([disabled])"));
                const startButton = buttons[buttons.length - 1];
                if (!(startButton instanceof HTMLElement)) {
                  log("startAgentChatViaMarketplace missing start button");
                  return false;
                }
                log("startAgentChatViaMarketplace clicking Start Chat");
                startButton.click();
                // Waiting for the composer in parallel trims the empty-state pause after the dialog closes.
                const submitTask = submitPromptViaChatForm(prompt);
                await waitForElement(
                  () =>
                    toRouterPath(window.location.href).startsWith("/c/new") &&
                    window.location.search.includes(`agent_id=${encodeURIComponent(agentId)}`)
                      ? document.body
                      : null,
                  5000,
                );
                log("startAgentChatViaMarketplace after Start Chat", window.location.href);
                return await submitTask;
              } catch (error) {
                log("startAgentChatViaMarketplace exception", String(error));
                return false;
              }
            };
            const performSubmitRouteRemount = async () => {
              if (!shouldAutoSubmitFromQuery || useRouteReloadForLauncherChats) return false;
              // LibreChat only processes launcher-style query params once per ChatRoute mount.
              const remountPath = `/search?tl_remount=${Date.now()}`;
              postLauncherProgress("route-remount");
              log("performSubmitRouteRemount start", remountPath);
              if (!(await navigateInternally(remountPath, 180))) {
                log("performSubmitRouteRemount failed to navigate to remount path");
                return false;
              }
              await waitForRouteToApply();
              const result = await navigateInternally(targetRouterPath, 1400);
              if (result) {
                postLauncherProgress("ready");
              }
              log("performSubmitRouteRemount result", result);
              return result;
            };
            if (await startAgentChatViaReactContext()) return;
            if (await startPlainNewConversation()) return;
            if (await startAgentChatViaMarketplace()) return;
            if (await performSubmitRouteRemount()) return;
            if (await navigateInternally(targetRouterPath, shouldAutoSubmitFromQuery ? 1400 : 200)) {
              if (!shouldAutoSubmitFromQuery) {
                postLauncherProgress("ready");
              }
              return;
            }
            if (pushWithHistory(targetAppPath)) {
              const reached = await waitForTargetLocation(600);
              if (reached) {
                if (!shouldAutoSubmitFromQuery) {
                  postLauncherProgress("ready");
                }
                return;
              }
            }
            // Preserve the exact preset destination when SPA routing cannot carry it through.
            postLauncherProgress("reloading-page");
            log("falling back to window.location.assign", next.href);
            window.location.assign(next.href);
            } catch (error) {
              try {
                globalThis.__kotobaLibreLog?.("spa script exception", String(error));
              } catch (_) {
              }
            }
          })();
        })();
        """
    }

    private static func parseAddAgentCandidate(from rawValue: Any) -> WebAddPresetCandidate? {
        guard let dictionary = rawValue as? [String: Any] else {
            return nil
        }

        let sourceURLString = (dictionary["sourceURL"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let presetKind = (dictionary["presetKind"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let presetValue = (dictionary["presetValue"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let presetName = (dictionary["presetName"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

        guard
            let sourceURL = URL(string: sourceURLString),
            let kind = PresetKind(rawValue: presetKind),
            !presetValue.isEmpty
        else {
            return nil
        }

        return WebAddPresetCandidate(
            sourceURL: sourceURL,
            kind: kind,
            presetValue: presetValue,
            presetName: presetName
        )
    }
}
