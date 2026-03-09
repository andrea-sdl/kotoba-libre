import Foundation

// AppResources finds assets packaged with the SwiftPM resource bundle.
public enum AppResources {
    private static let resourceBundleName = "KotobaLibre_KotobaLibreCore.bundle"

    private static var resourceBundle: Bundle? {
        // SwiftPM resource bundle paths differ between app runs, tests, and built artifacts.
        let candidateURLs = [
            Bundle.main.bundleURL.appendingPathComponent(resourceBundleName, isDirectory: true),
            Bundle.main.resourceURL?.appendingPathComponent(resourceBundleName, isDirectory: true),
            Bundle.main.executableURL?
                .deletingLastPathComponent()
                .appendingPathComponent(resourceBundleName, isDirectory: true),
            Bundle.main.executableURL?
                .deletingLastPathComponent()
                .appendingPathComponent("../Resources/\(resourceBundleName)", isDirectory: true)
                .standardizedFileURL
        ].compactMap { $0 }

        for url in candidateURLs {
            if let bundle = Bundle(url: url) {
                return bundle
            }
        }

        // Final fallback scans already loaded bundles in case the expected path shape changed.
        return Bundle.allBundles.first { $0.bundleURL.lastPathComponent == resourceBundleName }
            ?? Bundle.allFrameworks.first { $0.bundleURL.lastPathComponent == resourceBundleName }
    }

    public static var iconPNGURL: URL? {
        resourceBundle?.url(forResource: "AppIcon", withExtension: "png")
    }

    public static var iconICNSURL: URL? {
        resourceBundle?.url(forResource: "AppIcon", withExtension: "icns")
    }
}
