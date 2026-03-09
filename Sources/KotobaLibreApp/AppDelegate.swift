import AppKit

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
        appController.restoreOrOpenPrimaryWindow()
        return true
    }

    @MainActor
    func application(_ application: NSApplication, open urls: [URL]) {
        appController.handleOpen(urls: urls)
    }

    @MainActor
    func applicationWillTerminate(_ notification: Notification) {
        appController.applicationWillTerminate()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
