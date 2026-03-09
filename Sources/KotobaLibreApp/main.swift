import AppKit
import Foundation
import KotobaLibreCore

@MainActor
private enum LaunchConfiguration {
    static func make() -> (initialSettings: AppSettings, appDelegate: AppDelegate) {
        let arguments = Set(CommandLine.arguments)
        guard arguments.contains("--smoke-test") else {
            let initialSettings = (try? AppDataStore().loadSettings()) ?? AppSettings()
            let appDelegate = AppDelegate()
            return (initialSettings, appDelegate)
        }

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

let application = NSApplication.shared
let launchConfiguration = LaunchConfiguration.make()
let initialSettings = launchConfiguration.initialSettings
_ = application.setActivationPolicy(initialSettings.appVisibilityMode.showsDockIcon ? .regular : .accessory)
application.delegate = launchConfiguration.appDelegate
application.run()
