import AppKit
import KotobaLibreCore

let application = NSApplication.shared
let appDelegate = AppDelegate()
let initialSettings = (try? AppDataStore().loadSettings()) ?? AppSettings()
_ = application.setActivationPolicy(initialSettings.appVisibilityMode.showsDockIcon ? .regular : .accessory)
application.delegate = appDelegate
application.run()
