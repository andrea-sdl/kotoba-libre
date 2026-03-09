import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    @MainActor
    private lazy var appController = AppController()

    @MainActor
    func applicationDidFinishLaunching(_ notification: Notification) {
        appController.start()
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
