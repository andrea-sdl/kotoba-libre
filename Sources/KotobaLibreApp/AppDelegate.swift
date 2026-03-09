import AppKit

// AppDelegate is a thin bridge from NSApplication lifecycle events to AppController.
final class AppDelegate: NSObject, NSApplicationDelegate {
    @MainActor private let appController: AppController
    @MainActor private let didFinishLaunchingHandler: ((AppController) -> Void)?

    @MainActor
    init(
        appController: AppController = AppController(),
        didFinishLaunchingHandler: ((AppController) -> Void)? = nil
    ) {
        self.appController = appController
        self.didFinishLaunchingHandler = didFinishLaunchingHandler
        super.init()
    }

    @MainActor
    func applicationDidFinishLaunching(_ notification: Notification) {
        appController.start()
        didFinishLaunchingHandler?(appController)
    }

    @MainActor
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // macOS calls this when the user clicks the Dock icon while windows are hidden.
        appController.restoreOrOpenPrimaryWindow()
        return true
    }

    @MainActor
    func application(_ application: NSApplication, open urls: [URL]) {
        // Deep links and custom URL scheme opens land here.
        appController.handleOpen(urls: urls)
    }

    @MainActor
    func applicationWillTerminate(_ notification: Notification) {
        appController.applicationWillTerminate()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // The app can stay alive in menu bar mode even if all windows are hidden.
        false
    }
}
