import AppKit
import AVFoundation
import SwiftUI
import KotobaLibreCore
import WebKit

// The main window and embedded web view live together in this file because they share one navigation flow.
private let defaultMainWindowSize = NSSize(width: 800, height: 600)
private let minimumMainWindowSize = NSSize(width: 800, height: 600)

// These identifiers keep the main window toolbar definition local to the web window controller file.
private enum MainWindowToolbarItem {
    static let addAgent = NSToolbarItem.Identifier("KotobaLibreAddAgent")
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
    private var currentAddAgentCandidate: WebAddAgentCandidate?
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
        let hostingController = NSHostingController(
            rootView: OnboardingFlowView(appController: appController)
        )
        window?.contentViewController = hostingController
    }

    func showWebView(settings: AppSettings) {
        // The web controller is reused so session state and browser history survive UI switches.
        let controller = ensureWebController()
        controller.debugLoggingEnabled = settings.debugLoggingEnabled
        window?.contentViewController = controller
    }

    func navigateToHome(settings: AppSettings) {
        guard let homeURL = try? KotobaLibreCore.parseInstanceBaseURL(settings) else {
            showOnboarding()
            return
        }

        updateAddAgentCandidate(nil)
        let controller = ensureWebController()
        controller.debugLoggingEnabled = settings.debugLoggingEnabled
        window?.contentViewController = controller
        controller.load(url: homeURL)
    }

    func open(url: URL, settings: AppSettings, instanceHost: String?, forceEmbedAllHosts: Bool = false) {
        updateAddAgentCandidate(nil)
        let controller = ensureWebController()
        controller.debugLoggingEnabled = settings.debugLoggingEnabled
        window?.contentViewController = controller
        controller.open(
            url: url,
            settings: settings,
            instanceHost: instanceHost,
            forceEmbedAllHosts: forceEmbedAllHosts
        )
        showAndFocus()
    }

    func showAndFocus() {
        // The first show restores a saved frame. Later shows only clamp the frame to current screens.
        applyInitialWindowFrameIfNeeded()
        normalizeWindowFrameToAvailableScreens(centerIfNeeded: savedWindowFrame == nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func resetToDefaultSize() {
        window?.setContentSize(defaultMainWindowSize)
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
        created.addAgentCandidateHandler = { [weak self] candidate in
            self?.updateAddAgentCandidate(candidate)
        }
        webController = created
        return created
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
        adjustedFrame.size.width = min(max(adjustedFrame.width, minimumMainWindowSize.width), visibleFrame.width)
        adjustedFrame.size.height = min(max(adjustedFrame.height, minimumMainWindowSize.height), visibleFrame.height)

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

    private func updateAddAgentCandidate(_ candidate: WebAddAgentCandidate?) {
        currentAddAgentCandidate = candidate
        addAgentButton.isEnabled = candidate != nil
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

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.flexibleSpace, MainWindowToolbarItem.addAgent]
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.flexibleSpace, MainWindowToolbarItem.addAgent]
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
    private static let supportedAuthenticationCallbackScheme = "kotobalibre"

    private enum ExternalNavigationPolicy {
        case singleHost(String?)
        case embedAllHosts
    }

    // Popup windows get their own controller so JavaScript-created windows can close independently.
    private final class PopupWindowController: NSWindowController, NSWindowDelegate {
        private static let defaultSize = NSSize(width: 720, height: 640)

        let hostedWebView: WKWebView
        var onClose: (() -> Void)?

        init(webView: WKWebView, windowFeatures: WKWindowFeatures) {
            self.hostedWebView = webView

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

    let webView: WKWebView
    var externalNavigationHandler: ((URL) -> Void)?
    var authenticationSessionStarter: ((URL, String) -> Bool)?
    var addAgentCandidateHandler: ((WebAddAgentCandidate?) -> Void)?
    var debugLoggingEnabled = false
    private var hasLoadedRemoteContent = false
    private var externalNavigationPolicy: ExternalNavigationPolicy = .singleHost(nil)
    private var popupWindowControllers: [ObjectIdentifier: PopupWindowController] = [:]
    private var popupNavigationPolicies: [ObjectIdentifier: ExternalNavigationPolicy] = [:]
    private let logMessageHandler = ScriptMessageHandler()
    private let addAgentMessageHandler = DictionaryMessageHandler()

    init() {
        let configuration = WKWebViewConfiguration()
        configuration.allowsAirPlayForMediaPlayback = false
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = true
        // These scripts are injected before the page app boots so launcher navigation can seed state early.
        configuration.userContentController.add(logMessageHandler, name: Self.logHandlerName)
        configuration.userContentController.add(addAgentMessageHandler, name: Self.addAgentCandidateHandlerName)
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
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        view = webView
    }

    func load(url: URL) {
        hasLoadedRemoteContent = true
        debugLog("KotobaLibre SPA: load(url:) -> \(url.absoluteString)")
        webView.load(URLRequest(url: url))
    }

    func open(url: URL, settings: AppSettings, instanceHost: String?, forceEmbedAllHosts: Bool = false) {
        if forceEmbedAllHosts {
            externalNavigationPolicy = .embedAllHosts
        } else {
            externalNavigationPolicy = .singleHost(embeddedHost(for: url, instanceHost: instanceHost, settings: settings))
        }

        // Same-host launches can stay inside the existing SPA once remote content has loaded at least once.
        if KotobaLibreCore.canUseSPANavigation(instanceHost: instanceHost, url: url), hasLoadedRemoteContent {
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
                    self?.load(url: url)
                }
            }
            return
        }

        load(url: url)
    }

    func fetchCurrentAddAgentCandidate(completion: @escaping (WebAddAgentCandidate?) -> Void) {
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

        if promotePopupNavigationToAuthenticationSessionIfNeeded(url, webView: webView) {
            decisionHandler(.cancel)
            return
        }

        if shouldKeepPopupNavigationEmbedded(url, webView: webView) {
            decisionHandler(.allow)
            return
        }

        if shouldOpenExternally(url, currentEmbeddedHost: currentEmbeddedHost) {
            externalNavigationHandler?(url)
            decisionHandler(.cancel)
            return
        }

        decisionHandler(.allow)
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationResponse: WKNavigationResponse,
        decisionHandler: @escaping @MainActor @Sendable (WKNavigationResponsePolicy) -> Void
    ) {
        if !navigationResponse.canShowMIMEType {
            decisionHandler(.download)
            return
        }

        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        if webView == self.webView {
            hasLoadedRemoteContent = true
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
        if let url = navigationAction.request.url, routeAuthenticationRequestIfNeeded(for: url) {
            return nil
        }

        configuration.preferences.javaScriptCanOpenWindowsAutomatically = true

        let popupWebView = WKWebView(frame: .zero, configuration: configuration)
        popupWebView.navigationDelegate = self
        popupWebView.uiDelegate = self
        popupWebView.allowsBackForwardNavigationGestures = true

        let popupWindowController = PopupWindowController(webView: popupWebView, windowFeatures: windowFeatures)
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

    private func startAuthenticationSessionIfSupported(for url: URL) -> Bool {
        guard looksLikeAuthenticationURL(url) else {
            return false
        }

        guard let callbackScheme = authenticationCallbackScheme(in: url) else {
            return false
        }

        return authenticationSessionStarter?(url, callbackScheme) == true
    }

    private func routeAuthenticationRequestIfNeeded(for url: URL) -> Bool {
        guard looksLikeAuthenticationURL(url) else {
            return false
        }

        if startAuthenticationSessionIfSupported(for: url) {
            debugLog("KotobaLibre Auth: routed popup through ASWebAuthenticationSession -> \(url.absoluteString)")
            return true
        }

        externalNavigationHandler?(url)
        debugLog("KotobaLibre Auth: fell back to external browser -> \(url.absoluteString)")
        return true
    }

    private func promotePopupNavigationToAuthenticationSessionIfNeeded(_ url: URL, webView: WKWebView) -> Bool {
        guard popupWindowControllers[ObjectIdentifier(webView)] != nil else {
            return false
        }

        guard routeAuthenticationRequestIfNeeded(for: url) else {
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
      try {
        const url = new URL(window.location.href);
        if (!(url.pathname === "/c/new" || url.pathname.startsWith("/c/new/"))) return;
        const agentId = url.searchParams.get("agent_id");
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
      const readCandidate = () => {
        try {
          const url = new URL(window.location.href);
          const currentRoutePath = routePath(url);
          const agentID = trimText(url.searchParams.get("agent_id") ?? "");
          if (!currentRoutePath.startsWith("/agents") || !agentID) {
            return null;
          }
          return {
            sourceURL: url.href,
            agentID,
            agentName: trimText(document.querySelector('div[role="dialog"] h2')?.textContent ?? ""),
          };
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
            const shouldAutoSubmitFromQuery =
              (next.searchParams.get("submit") ?? "").toLowerCase() === "true" &&
              (next.searchParams.has("prompt") || next.searchParams.has("q"));
            log("spa start", {
              href: next.href,
              targetAppPath,
              targetRouterPath,
              basePath,
              shouldAutoSubmitFromQuery,
              useRouteReloadForLauncherChats,
            });
            const seedLauncherSelection = () => {
              if (!(next.pathname === "/c/new" || next.pathname.startsWith("/c/new/"))) return;
              const agentId = next.searchParams.get("agent_id");
              if (agentId) {
                localStorage.setItem("agent_id__0", agentId);
                log("seedLauncherSelection", agentId);
              }
            };
            seedLauncherSelection();
            if (useRouteReloadForLauncherChats && shouldAutoSubmitFromQuery) {
              log("branch route reload flag -> window.location.assign");
              window.location.assign(next.href);
              return;
            }
            const locationValue = () => `${window.location.pathname}${window.location.search}${window.location.hash}`;
            const isAtTargetLocation = () => locationValue() === targetAppPath;
            const delay = (ms) => new Promise((resolve) => window.setTimeout(resolve, ms));
            const waitForTargetLocation = async (timeoutMs) => {
              const started = Date.now();
              while (Date.now() - started < timeoutMs) {
                if (isAtTargetLocation()) return true;
                await delay(60);
              }
              return isAtTargetLocation();
            };
            const waitForRouteToApply = async () => {
              await delay(0);
              await delay(80);
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
                await delay(timeoutMs);
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
            const waitForElement = async (resolver, timeoutMs = 5000) => {
              const started = Date.now();
              while (Date.now() - started < timeoutMs) {
                const result = resolver();
                if (result) return result;
                await delay(60);
              }
              return resolver();
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
            const submitPromptViaChatForm = async (prompt, previousTextarea = null) => {
              if (!prompt) return true;
              const textarea = await waitForElement(
                () => {
                  const candidate = document.getElementById("prompt-textarea");
                  if (!(candidate instanceof HTMLTextAreaElement)) return null;
                  if (previousTextarea && candidate === previousTextarea) return null;
                  return candidate;
                },
                5000,
              );
              if (!(textarea instanceof HTMLTextAreaElement)) {
                log("submitPromptViaChatForm missing textarea");
                return false;
              }
              setTextareaValue(textarea, prompt);
              await delay(120);
              if (textarea.value !== prompt) {
                log("submitPromptViaChatForm restoring prompt after rerender", {
                  expected: prompt,
                  actual: textarea.value,
                });
                setTextareaValue(textarea, prompt);
                await delay(120);
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
              log("submitPromptViaChatForm clicking send");
              sendButton.click();
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
                await delay(60);
              }
              log("waitForChatContextConversation timed out", agentId);
              return getChatContext();
            };
            const startAgentChatViaReactContext = async () => {
              if (useRouteReloadForLauncherChats) return false;
              if (!(next.pathname === "/c/new" || next.pathname.startsWith("/c/new/"))) return false;
              const agentId = next.searchParams.get("agent_id");
              if (!agentId) return false;
              const prompt = next.searchParams.get("prompt") ?? next.searchParams.get("q") ?? "";
              try {
                const chatContext = getChatContext();
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
                return await submitPromptViaChatForm(prompt, previousTextarea);
              } catch (error) {
                log("startAgentChatViaReactContext exception", String(error));
                return false;
              }
            };
            const startAgentChatViaMarketplace = async () => {
              if (!shouldAutoSubmitFromQuery || useRouteReloadForLauncherChats) return false;
              if (!(next.pathname === "/c/new" || next.pathname.startsWith("/c/new/"))) return false;
              const agentId = next.searchParams.get("agent_id");
              const prompt = next.searchParams.get("prompt") ?? next.searchParams.get("q") ?? "";
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
                await waitForElement(
                  () =>
                    toRouterPath(window.location.href).startsWith("/c/new") &&
                    window.location.search.includes(`agent_id=${encodeURIComponent(agentId)}`)
                      ? document.body
                      : null,
                  5000,
                );
                log("startAgentChatViaMarketplace after Start Chat", window.location.href);
                return await submitPromptViaChatForm(prompt);
              } catch (error) {
                log("startAgentChatViaMarketplace exception", String(error));
                return false;
              }
            };
            const performSubmitRouteRemount = async () => {
              if (!shouldAutoSubmitFromQuery || useRouteReloadForLauncherChats) return false;
              // LibreChat only processes launcher-style query params once per ChatRoute mount.
              const remountPath = `/search?tl_remount=${Date.now()}`;
              log("performSubmitRouteRemount start", remountPath);
              if (!(await navigateInternally(remountPath, 180))) {
                log("performSubmitRouteRemount failed to navigate to remount path");
                return false;
              }
              await delay(120);
              const result = await navigateInternally(targetRouterPath, 1400);
              log("performSubmitRouteRemount result", result);
              return result;
            };
            if (await startAgentChatViaReactContext()) return;
            if (await startAgentChatViaMarketplace()) return;
            if (await performSubmitRouteRemount()) return;
            if (await navigateInternally(targetRouterPath, shouldAutoSubmitFromQuery ? 1400 : 200)) return;
            if (pushWithHistory(targetAppPath)) {
              const reached = await waitForTargetLocation(600);
              if (reached) return;
            }
            // Preserve the exact preset destination when SPA routing cannot carry it through.
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

    private static func parseAddAgentCandidate(from rawValue: Any) -> WebAddAgentCandidate? {
        guard let dictionary = rawValue as? [String: Any] else {
            return nil
        }

        let sourceURLString = (dictionary["sourceURL"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let agentID = (dictionary["agentID"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let agentName = (dictionary["agentName"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

        guard
            let sourceURL = URL(string: sourceURLString),
            !agentID.isEmpty
        else {
            return nil
        }

        return WebAddAgentCandidate(
            sourceURL: sourceURL,
            agentID: agentID,
            agentName: agentName
        )
    }
}
