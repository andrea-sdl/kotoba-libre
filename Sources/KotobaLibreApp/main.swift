import AppKit
import Foundation
import KotobaLibreCore

// The app boots here instead of using a SwiftUI App entry point.
// That keeps launch control in one place and makes smoke-test setup easy.
@MainActor
private enum LaunchConfiguration {
    static func make() -> (initialSettings: AppSettings, appDelegate: AppDelegate) {
        let arguments = Set(CommandLine.arguments)
        guard arguments.contains("--smoke-test") else {
            let initialSettings = (try? AppDataStore().loadSettings()) ?? AppSettings()
            let appDelegate = AppDelegate()
            return (initialSettings, appDelegate)
        }

        // Smoke tests use a throwaway config directory so test runs never touch real user data.
        let smokeTestDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("kotobalibre-gui-smoke-\(UUID().uuidString)", isDirectory: true)
        let store = try! AppDataStore(baseDirectory: smokeTestDirectory)
        let appController = AppController(store: store, runtimeMode: .smokeTest)
        let runner = AppSmokeTestRunner(appController: appController, temporaryDirectory: smokeTestDirectory)
        let appDelegate = AppDelegate(appController: appController) { _ in
            runner.start()
        }
        return (AppSettings(), appDelegate)
    }
}

// AppKit is started manually because the app is driven by window controllers.
let application = NSApplication.shared
let launchConfiguration = LaunchConfiguration.make()
let initialSettings = launchConfiguration.initialSettings
_ = application.setActivationPolicy(initialSettings.appVisibilityMode.showsDockIcon ? .regular : .accessory)
application.delegate = launchConfiguration.appDelegate
application.run()
