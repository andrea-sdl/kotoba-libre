import AppKit

// AppDelegate is a thin bridge from NSApplication lifecycle events to AppController.
final class AppDelegate: NSObject, NSApplicationDelegate {
    @MainActor private let appController: AppController
    @MainActor private let didFinishLaunchingHandler: ((AppController) -> Void)?
    @MainActor private var pendingOpenURLs: [URL] = []
    @MainActor private var pendingFileURLs: [URL] = []
    @MainActor private var hasFinishedLaunching = false

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
        hasFinishedLaunching = true
        if !pendingOpenURLs.isEmpty {
            appController.debugLog("KotobaLibre Dock: delivering \(pendingOpenURLs.count) pending URL open(s) after launch")
            appController.handleOpen(urls: pendingOpenURLs)
            pendingOpenURLs.removeAll()
        }
        if !pendingFileURLs.isEmpty {
            appController.debugLog("KotobaLibre Dock: delivering \(pendingFileURLs.count) pending file open(s) after launch")
            appController.handleOpenFiles(pendingFileURLs)
            pendingFileURLs.removeAll()
        }
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
        appController.debugLog("KotobaLibre Dock: application(_:open:) received \(urls.count) URL(s)")
        let fileURLs = urls.filter(\.isFileURL)
        let nonFileURLs = urls.filter { !$0.isFileURL }

        if hasFinishedLaunching {
            if !fileURLs.isEmpty {
                appController.debugLog("KotobaLibre Dock: application(_:open:) routing \(fileURLs.count) file URL(s) through handleOpenFiles")
                appController.handleOpenFiles(fileURLs)
            }
            if !nonFileURLs.isEmpty {
                appController.handleOpen(urls: nonFileURLs)
            }
        } else {
            pendingFileURLs.append(contentsOf: fileURLs)
            pendingOpenURLs.append(contentsOf: nonFileURLs)
        }
    }

    @MainActor
    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        let fileURLs = filenames.map { URL(fileURLWithPath: $0) }
        appController.debugLog("KotobaLibre Dock: application(_:openFiles:) received \(fileURLs.count) file URL(s)")
        if hasFinishedLaunching {
            appController.handleOpenFiles(fileURLs)
        } else {
            pendingFileURLs.append(contentsOf: fileURLs)
        }
        sender.reply(toOpenOrPrint: .success)
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
