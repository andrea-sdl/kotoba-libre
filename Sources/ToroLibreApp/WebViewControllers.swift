import AppKit
import SwiftUI
import ToroLibreCore
import WebKit

@MainActor
final class MainWindowController: NSWindowController, NSWindowDelegate {
    private weak var appController: AppController?
    private var webController: WebContentViewController?

    init(appController: AppController) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1280, height: 860),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = appDisplayName
        window.center()
        window.setFrameAutosaveName("ToroLibreMainWindow")
        super.init(window: window)
        self.appController = appController
        self.window?.delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func showFirstRun() {
        guard let appController else {
            return
        }

        let hostingController = NSHostingController(
            rootView: FirstRunView {
                appController.showSettingsWindow()
            }
        )
        window?.contentViewController = hostingController
    }

    func showWebView(settings: AppSettings) {
        let controller = ensureWebController(debugEnabled: settings.debugInWebview)
        window?.contentViewController = controller
    }

    func navigateToHome(settings: AppSettings) {
        guard let homeURL = try? ToroLibreCore.parseInstanceBaseURL(settings) else {
            showFirstRun()
            return
        }

        let controller = ensureWebController(debugEnabled: settings.debugInWebview)
        window?.contentViewController = controller
        controller.load(url: homeURL)
    }

    func open(url: URL, settings: AppSettings, instanceHost: String?) {
        let controller = ensureWebController(debugEnabled: settings.debugInWebview)
        window?.contentViewController = controller
        controller.open(
            url: url,
            settings: settings,
            instanceHost: instanceHost
        )
        showAndFocus()
    }

    func showAndFocus() {
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.orderOut(nil)
        return false
    }

    private func ensureWebController(debugEnabled: Bool) -> WebContentViewController {
        if let webController {
            webController.updateDebug(enabled: debugEnabled)
            return webController
        }

        let created = WebContentViewController(debugEnabled: debugEnabled)
        created.externalNavigationHandler = { [weak appController] url in
            appController?.openExternally(url)
        }
        webController = created
        return created
    }
}

@MainActor
final class SecondaryWebWindowController: NSWindowController {
    private let webController: WebContentViewController

    init(url: URL, settings: AppSettings, instanceHost: String?, onExternalOpen: @escaping (URL) -> Void) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1280, height: 860),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = appDisplayName
        window.center()

        self.webController = WebContentViewController(debugEnabled: settings.debugInWebview)
        super.init(window: window)
        self.window?.contentViewController = webController
        self.webController.externalNavigationHandler = onExternalOpen
        self.webController.open(url: url, settings: settings, instanceHost: instanceHost)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

@MainActor
final class WebContentViewController: NSViewController, WKNavigationDelegate {
    let webView: WKWebView
    var externalNavigationHandler: ((URL) -> Void)?
    private var hasLoadedRemoteContent = false
    private var currentInstanceHost: String?

    init(debugEnabled: Bool) {
        let configuration = WKWebViewConfiguration()
        configuration.allowsAirPlayForMediaPlayback = false
        self.webView = WKWebView(frame: .zero, configuration: configuration)
        super.init(nibName: nil, bundle: nil)
        self.webView.navigationDelegate = self
        self.webView.allowsBackForwardNavigationGestures = true
        updateDebug(enabled: debugEnabled)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        view = webView
    }

    func updateDebug(enabled: Bool) {
        webView.configuration.preferences.setValue(enabled, forKey: "developerExtrasEnabled")
        if #available(macOS 13.3, *) {
            webView.isInspectable = enabled
        }
    }

    func load(url: URL) {
        hasLoadedRemoteContent = true
        webView.load(URLRequest(url: url))
    }

    func open(url: URL, settings: AppSettings, instanceHost: String?) {
        currentInstanceHost = instanceHost

        if ToroLibreCore.canUseSPANavigation(instanceHost: instanceHost, url: url), hasLoadedRemoteContent {
            let script = spaNavigationScript(
                destination: url.absoluteString,
                debugEnabled: settings.debugInWebview,
                useRouteReload: settings.useRouteReloadForLauncherChats
            )
            webView.evaluateJavaScript(script) { [weak self] _, error in
                if error != nil {
                    self?.load(url: url)
                }
            }
            return
        }

        load(url: url)
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void
    ) {
        guard let url = navigationAction.request.url, url.scheme?.lowercased() == "https" else {
            decisionHandler(.allow)
            return
        }

        if let currentInstanceHost, let host = url.host, host.caseInsensitiveCompare(currentInstanceHost) != .orderedSame {
            externalNavigationHandler?(url)
            decisionHandler(.cancel)
            return
        }

        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        hasLoadedRemoteContent = true
    }

    private func spaNavigationScript(destination: String, debugEnabled: Bool, useRouteReload: Bool) -> String {
        let payloadData = try? JSONEncoder().encode(destination)
        let payload = payloadData.flatMap { String(data: $0, encoding: .utf8) } ?? "\"\(destination)\""
        let debugValue = debugEnabled ? "true" : "false"
        let routeReloadValue = useRouteReload ? "true" : "false"

        return """
        (async function() {
          try {
            const next = new URL(\(payload));
            const target = `${next.pathname}${next.search}${next.hash}`;
            const debug = \(debugValue);
            const useRouteReloadForLauncherChats = \(routeReloadValue);
            const debugLog = (...args) => {
              if (!debug) return;
              try { console.log("[Toro Libre Debug]", ...args); } catch (_) {}
            };
            const shouldAutoSubmitFromQuery =
              (next.searchParams.get("submit") ?? "").toLowerCase() === "true" &&
              (next.searchParams.has("prompt") || next.searchParams.has("q"));
            if (useRouteReloadForLauncherChats && shouldAutoSubmitFromQuery) {
              window.location.assign(next.href);
              return;
            }
            const locationValue = () => `${window.location.pathname}${window.location.search}${window.location.hash}`;
            const isAtTargetLocation = () => locationValue() === target;
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
              }
              window.dispatchEvent(new PopStateEvent("popstate", { state: window.history.state }));
              document.dispatchEvent(new PopStateEvent("popstate", { state: window.history.state }));
              window.dispatchEvent(new Event("pushstate"));
              return true;
            };
            const navigateWithHistoryAndWait = async (value, timeoutMs = 1200) => {
              if (!pushWithHistory(value)) return false;
              await waitForRouteToApply();
              return await waitForTargetLocation(timeoutMs);
            };
            const routeWithRouter = async (value) => {
              const nextPush =
                globalThis.next?.router?.push ??
                globalThis.__next_router__?.push ??
                globalThis.__NEXT_ROUTER__?.push;
              if (typeof nextPush === "function") {
                const result = nextPush(value);
                if (result && typeof result.then === "function") await result;
                await waitForRouteToApply();
                return await waitForTargetLocation(1200);
              }
              const genericNavigate =
                globalThis.__next_router__?.navigate ??
                globalThis.__NEXT_ROUTER__?.navigate ??
                globalThis.__remixRouter?.navigate;
              if (typeof genericNavigate === "function") {
                const result = genericNavigate(value);
                if (result && typeof result.then === "function") await result;
                await waitForRouteToApply();
                return await waitForTargetLocation(1200);
              }
              return false;
            };
            const clickFirstMatching = (selectors) => {
              for (const selector of selectors) {
                const element = document.querySelector(selector);
                if (element instanceof HTMLElement) {
                  element.click();
                  return true;
                }
              }
              return false;
            };
            const navigateViaLibreChatUi = async () => {
              if (!shouldAutoSubmitFromQuery) return false;
              if (!(next.pathname === "/c/new" || next.pathname.startsWith("/c/new/"))) return false;
              try {
                const current = new URL(window.location.href);
                current.search = next.search;
                window.history.replaceState(window.history.state, "", `${current.pathname}${current.search}${current.hash}`);
                window.dispatchEvent(new PopStateEvent("popstate", { state: window.history.state }));
              } catch (error) {
                debugLog("replaceState failed", error);
              }
              await delay(80);
              clickFirstMatching([
                "a[href='/search']",
                "a[href$='/search']",
                "[data-testid='nav-search-button']",
              ]);
              await delay(120);
              const clickedNewChat = clickFirstMatching([
                "[data-testid='nav-new-chat-button']",
                "a[href='/c/new']",
                "a[href$='/c/new']",
              ]);
              if (!clickedNewChat) return false;
              return await waitForTargetLocation(2000);
            };
            const performSubmitRouteRemount = async () => {
              if (!shouldAutoSubmitFromQuery) return false;
              const remountPath = `/search?tl_remount=${Date.now()}`;
              if (window.location.pathname !== "/search") {
                pushWithHistory(remountPath);
                await waitForRouteToApply();
              }
              return await navigateWithHistoryAndWait(target, 1600);
            };
            if (await routeWithRouter(target)) return;
            if (await navigateViaLibreChatUi()) return;
            if (await performSubmitRouteRemount()) return;
            if (pushWithHistory(target)) {
              const reached = await waitForTargetLocation(600);
              if (reached) return;
            }
            if (shouldAutoSubmitFromQuery) return;
            window.location.assign(next.href);
          } catch (error) {
            try { console.log("[Toro Libre Debug] navigation exception", error); } catch (_) {}
          }
        })();
        """
    }
}
