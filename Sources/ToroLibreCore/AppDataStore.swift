import Foundation

public final class AppDataStore: @unchecked Sendable {
    public let baseDirectory: URL
    public let settingsURL: URL
    public let presetsURL: URL

    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(baseDirectory: URL? = nil, fileManager: FileManager = .default) throws {
        self.fileManager = fileManager

        if let baseDirectory {
            self.baseDirectory = baseDirectory
        } else {
            let appSupport = try fileManager.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            self.baseDirectory = appSupport
                .appendingPathComponent(appDisplayName, isDirectory: true)
                .appendingPathComponent("config", isDirectory: true)
        }

        self.settingsURL = self.baseDirectory.appendingPathComponent(settingsFileName, isDirectory: false)
        self.presetsURL = self.baseDirectory.appendingPathComponent(presetsFileName, isDirectory: false)
        self.encoder = JSONEncoder()
        self.encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.decoder = JSONDecoder()

        try ensureBaseDirectory()
    }

    public func loadSettings() throws -> AppSettings {
        guard fileManager.fileExists(atPath: settingsURL.path) else {
            return AppSettings()
        }

        let data = try Data(contentsOf: settingsURL)
        let decoded = try decoder.decode(AppSettings.self, from: data)
        return ToroLibreCore.normalizeSettings(decoded)
    }

    public func saveSettings(_ settings: AppSettings) throws {
        try ensureBaseDirectory()
        let normalized = try ToroLibreCore.normalizeInstanceBaseURL(ToroLibreCore.normalizeSettings(settings))
        let data = try encoder.encode(normalized)
        try data.write(to: settingsURL, options: .atomic)
    }

    public func loadPresets() throws -> [Preset] {
        guard fileManager.fileExists(atPath: presetsURL.path) else {
            return []
        }

        let data = try Data(contentsOf: presetsURL)
        let decoded = try decoder.decode([Preset].self, from: data)
        let normalized = ToroLibreCore.normalizeLoadedPresets(decoded)
        if normalized != decoded {
            try savePresets(normalized)
        }
        return normalized
    }

    public func savePresets(_ presets: [Preset]) throws {
        try ensureBaseDirectory()
        let data = try encoder.encode(presets)
        try data.write(to: presetsURL, options: .atomic)
    }

    public func exportPresets(settings: AppSettings, presets: [Preset]) throws -> Data {
        let payload = ToroLibreCore.exportPayload(settings: settings, presets: presets)
        return try encoder.encode(payload)
    }

    public func resetConfiguration() throws {
        try removeItemIfPresent(at: settingsURL)
        try removeItemIfPresent(at: presetsURL)
    }

    private func ensureBaseDirectory() throws {
        if !fileManager.fileExists(atPath: baseDirectory.path) {
            try fileManager.createDirectory(at: baseDirectory, withIntermediateDirectories: true)
        }
    }

    private func removeItemIfPresent(at url: URL) throws {
        guard fileManager.fileExists(atPath: url.path) else {
            return
        }

        try fileManager.removeItem(at: url)
    }
}
