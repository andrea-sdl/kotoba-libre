import Foundation

// AppResources finds assets packaged with the SwiftPM resource bundle.
public enum AppResources {
    private static let resourceBundleName = "KotobaLibre_KotobaLibreCore.bundle"
    private static let sourceFileURL = URL(fileURLWithPath: #filePath)

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

    // The About tab prefers a looping hero animation when the bundled video is available.
    public static var aboutAnimationURL: URL? {
        resourceBundle?.url(forResource: "AboutArtworkLoop", withExtension: "mp4")
    }

    // The onboarding welcome step uses its own hero image so the about artwork can stay out of the bundle.
    public static var onboardingArtworkURL: URL? {
        resourceBundle?.url(forResource: "OnboardingArtwork", withExtension: "png")
    }

    // The displayed version prefers packaged metadata and falls back to the repo VERSION file in development.
    public static var appVersionDisplayString: String {
        if let bundleVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String {
            let trimmedVersion = bundleVersion.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedVersion.isEmpty {
                return trimmedVersion
            }
        }

        for candidateURL in repositoryVersionCandidates() {
            guard let versionContents = try? String(contentsOf: candidateURL, encoding: .utf8) else {
                continue
            }

            let trimmedVersion = versionContents.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedVersion.isEmpty {
                return trimmedVersion
            }
        }

        return "Unknown"
    }

    public static var iconPNGURL: URL? {
        resourceBundle?.url(forResource: "AppIcon", withExtension: "png")
    }

    public static var iconICNSURL: URL? {
        resourceBundle?.url(forResource: "AppIcon", withExtension: "icns")
    }

    // Candidate VERSION files cover SwiftPM runs, direct CLI work, and source-based development.
    private static func repositoryVersionCandidates() -> [URL] {
        let baseDirectories = executableVersionSearchDirectories()
            + [URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)]
            + sourceFileVersionSearchDirectories()

        var seenPaths = Set<String>()
        var versionURLs: [URL] = []

        for directoryURL in baseDirectories {
            let standardizedURL = directoryURL.standardizedFileURL
            guard seenPaths.insert(standardizedURL.path).inserted else {
                continue
            }

            versionURLs.append(standardizedURL.appendingPathComponent("VERSION", isDirectory: false))
        }

        return versionURLs
    }

    // The executable may run from .build, an app bundle, or a release artifact.
    private static func executableVersionSearchDirectories() -> [URL] {
        guard let executableURL = Bundle.main.executableURL else {
            return []
        }

        return ancestorDirectories(startingAt: executableURL.deletingLastPathComponent(), maxDepth: 6)
    }

    // The source path gives a stable route back to the repo root during local development.
    private static func sourceFileVersionSearchDirectories() -> [URL] {
        ancestorDirectories(startingAt: sourceFileURL.deletingLastPathComponent(), maxDepth: 4)
    }

    private static func ancestorDirectories(startingAt directoryURL: URL, maxDepth: Int) -> [URL] {
        var directories: [URL] = []
        var currentURL = directoryURL

        for _ in 0..<maxDepth {
            directories.append(currentURL)
            currentURL = currentURL.deletingLastPathComponent()
        }

        return directories
    }
}
