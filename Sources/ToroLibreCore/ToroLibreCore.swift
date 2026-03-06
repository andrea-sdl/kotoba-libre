import Foundation

public let appBundleIdentifier = "com.andreagrassi.torolibre"
public let appDisplayName = "Toro Libre"
public let settingsFileName = "settings.json"
public let presetsFileName = "presets.json"

public enum PresetKind: String, Codable, CaseIterable, Equatable, Sendable {
    case agent
    case link
}

public struct Preset: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var urlTemplate: String
    public var kind: PresetKind
    public var tags: [String]
    public var createdAt: String
    public var updatedAt: String

    public init(
        id: String,
        name: String,
        urlTemplate: String,
        kind: PresetKind,
        tags: [String],
        createdAt: String,
        updatedAt: String
    ) {
        self.id = id
        self.name = name
        self.urlTemplate = urlTemplate
        self.kind = kind
        self.tags = tags
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct AppSettings: Codable, Equatable, Sendable {
    public static let defaultShortcut = "Alt+Shift+Space"

    public var instanceBaseUrl: String?
    public var globalShortcut: String
    public var autostartEnabled: Bool
    public var openInNewWindow: Bool
    public var restrictHostToInstanceHost: Bool
    public var defaultPresetId: String?
    public var debugInWebview: Bool
    public var useRouteReloadForLauncherChats: Bool
    public var accentColor: String
    public var launcherOpacity: Double

    public init(
        instanceBaseUrl: String? = nil,
        globalShortcut: String = AppSettings.defaultShortcut,
        autostartEnabled: Bool = false,
        openInNewWindow: Bool = false,
        restrictHostToInstanceHost: Bool = true,
        defaultPresetId: String? = nil,
        debugInWebview: Bool = false,
        useRouteReloadForLauncherChats: Bool = false,
        accentColor: String = "blue",
        launcherOpacity: Double = 0.95
    ) {
        self.instanceBaseUrl = instanceBaseUrl
        self.globalShortcut = globalShortcut
        self.autostartEnabled = autostartEnabled
        self.openInNewWindow = openInNewWindow
        self.restrictHostToInstanceHost = restrictHostToInstanceHost
        self.defaultPresetId = defaultPresetId
        self.debugInWebview = debugInWebview
        self.useRouteReloadForLauncherChats = useRouteReloadForLauncherChats
        self.accentColor = accentColor
        self.launcherOpacity = launcherOpacity
    }
}

public struct ValidationResult: Equatable, Sendable {
    public var valid: Bool
    public var reason: String?

    public init(valid: Bool, reason: String? = nil) {
        self.valid = valid
        self.reason = reason
    }
}

public struct ImportPresetsResult: Equatable, Sendable {
    public var imported: Int
    public var skipped: Int
    public var errors: [String]

    public init(imported: Int, skipped: Int, errors: [String]) {
        self.imported = imported
        self.skipped = skipped
        self.errors = errors
    }
}

public enum DeepLinkAction: Equatable, Sendable {
    case openURL(String)
    case openPreset(presetID: String, query: String?)
    case openSettings
}

public struct PresetExportPayload: Codable, Equatable, Sendable {
    public var version: Int
    public var exportedAt: String
    public var instanceBaseUrl: String?
    public var agents: [Preset]

    public init(version: Int, exportedAt: String, instanceBaseUrl: String?, agents: [Preset]) {
        self.version = version
        self.exportedAt = exportedAt
        self.instanceBaseUrl = instanceBaseUrl
        self.agents = agents
    }
}

public enum ToroLibreCore {
    public static func nowMarker(date: Date = Date()) -> String {
        "unix-ms-\(Int(date.timeIntervalSince1970 * 1_000))"
    }

    public static func normalizeShortcutToken(_ token: String) -> String {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = trimmed.lowercased()

        switch lower {
        case "⌘", "command", "cmd", "commandorcontrol", "commandorctrl", "cmdorctrl", "cmdorcontrol":
            return "CmdOrCtrl"
        case "⌃", "^", "control", "ctrl":
            return "Ctrl"
        case "⌥", "option", "alt":
            return "Alt"
        case "⇧", "shift":
            return "Shift"
        case "spacebar", "space":
            return "Space"
        default:
            if trimmed.count == 1, let scalar = trimmed.unicodeScalars.first {
                if CharacterSet.letters.contains(scalar) {
                    return "Key\(trimmed.uppercased())"
                }
                if CharacterSet.decimalDigits.contains(scalar) {
                    return "Digit\(trimmed)"
                }
            }

            return trimmed
        }
    }

    public static func normalizeShortcutValue(_ shortcut: String) -> String {
        var seen = Set<String>()
        var tokens: [String] = []

        for token in shortcut.split(separator: "+").map(String.init) {
            let normalized = normalizeShortcutToken(token)
            guard !normalized.isEmpty else {
                continue
            }

            let dedupeKey = normalized.lowercased()
            if seen.insert(dedupeKey).inserted {
                tokens.append(normalized)
            }
        }

        return tokens.joined(separator: "+")
    }

    public static func normalizeSettings(_ settings: AppSettings) -> AppSettings {
        var normalized = settings
        if let value = normalized.instanceBaseUrl?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty {
            normalized.instanceBaseUrl = value
        } else {
            normalized.instanceBaseUrl = nil
        }

        let shortcut = normalizeShortcutValue(normalized.globalShortcut)
        normalized.globalShortcut = shortcut.isEmpty ? AppSettings.defaultShortcut : shortcut

        if let defaultPresetID = normalized.defaultPresetId?.trimmingCharacters(in: .whitespacesAndNewlines), !defaultPresetID.isEmpty {
            normalized.defaultPresetId = defaultPresetID
        } else {
            normalized.defaultPresetId = nil
        }

        normalized.launcherOpacity = min(max(normalized.launcherOpacity, 0.5), 1.0)
        if normalized.accentColor.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            normalized.accentColor = "blue"
        }

        return normalized
    }

    public static func normalizeTags(_ tags: [String]) -> [String] {
        Array(
            Set(
                tags
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
            )
        )
        .sorted()
    }

    public static func normalizePreset(_ preset: Preset, existing: Preset? = nil, now: String = nowMarker()) -> Preset {
        let presetID = preset.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? UUID().uuidString
            : preset.id.trimmingCharacters(in: .whitespacesAndNewlines)

        let createdAt: String
        if let existing {
            createdAt = existing.createdAt
        } else if preset.createdAt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            createdAt = now
        } else {
            createdAt = preset.createdAt
        }

        let updatedAt = preset.updatedAt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? now
            : preset.updatedAt

        return Preset(
            id: presetID,
            name: preset.name.trimmingCharacters(in: .whitespacesAndNewlines),
            urlTemplate: preset.urlTemplate.trimmingCharacters(in: .whitespacesAndNewlines),
            kind: preset.kind,
            tags: normalizeTags(preset.tags),
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    public static func normalizeLoadedPresets(_ presets: [Preset], nowProvider: () -> String = { nowMarker() }) -> [Preset] {
        var seenIDs = Set<String>()

        return presets.map { preset in
            var current = preset
            let trimmedID = current.id.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedID.isEmpty || seenIDs.contains(trimmedID) {
                current.id = UUID().uuidString
            } else {
                current.id = trimmedID
            }
            seenIDs.insert(current.id)

            current.name = current.name.trimmingCharacters(in: .whitespacesAndNewlines)
            current.urlTemplate = current.urlTemplate.trimmingCharacters(in: .whitespacesAndNewlines)
            current.tags = normalizeTags(current.tags)

            let trimmedCreatedAt = current.createdAt.trimmingCharacters(in: .whitespacesAndNewlines)
            let trimmedUpdatedAt = current.updatedAt.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedCreatedAt.isEmpty {
                let now = nowProvider()
                current.createdAt = now
                current.updatedAt = trimmedUpdatedAt.isEmpty ? now : trimmedUpdatedAt
            } else {
                current.createdAt = trimmedCreatedAt
                current.updatedAt = trimmedUpdatedAt.isEmpty ? trimmedCreatedAt : trimmedUpdatedAt
            }

            return current
        }
    }

    public static func validateURLTemplate(_ urlTemplate: String) -> ValidationResult {
        if urlTemplate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return ValidationResult(valid: false, reason: "URL template cannot be empty")
        }

        do {
            let url = try parseURLTemplateCandidate(urlTemplate)
            guard url.scheme?.lowercased() == "https" else {
                return ValidationResult(valid: false, reason: "Only https URLs are supported")
            }
            guard url.host != nil else {
                return ValidationResult(valid: false, reason: "URL must contain a host")
            }
            return ValidationResult(valid: true)
        } catch {
            return ValidationResult(valid: false, reason: error.localizedDescription)
        }
    }

    public static func parseURLTemplateCandidate(_ urlTemplate: String) throws -> URL {
        let candidate = urlTemplate.replacingOccurrences(of: "{query}", with: "example")
        guard let url = URL(string: candidate) else {
            throw ToroLibreError.invalidURLTemplate("Invalid URL template: malformed URL")
        }
        return url
    }

    public static func parseInstanceBaseURL(_ settings: AppSettings) throws -> URL? {
        guard let raw = settings.instanceBaseUrl?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return nil
        }

        guard let url = URL(string: raw), var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw ToroLibreError.invalidInstanceURL("Invalid instance URL: malformed URL")
        }

        guard components.scheme?.lowercased() == "https" else {
            throw ToroLibreError.invalidInstanceURL("Toro Libre instance URL must start with https://")
        }

        guard components.host != nil else {
            throw ToroLibreError.invalidInstanceURL("Toro Libre instance URL must include a host")
        }

        components.query = nil
        components.fragment = nil
        guard let normalized = components.url else {
            throw ToroLibreError.invalidInstanceURL("Invalid instance URL: malformed URL")
        }

        return normalized
    }

    public static func normalizeInstanceBaseURL(_ settings: AppSettings) throws -> AppSettings {
        var normalized = settings
        if let url = try parseInstanceBaseURL(settings) {
            normalized.instanceBaseUrl = url.absoluteString
        } else {
            normalized.instanceBaseUrl = nil
        }
        return normalized
    }

    public static func settingsInstanceHost(_ settings: AppSettings) throws -> String? {
        try parseInstanceBaseURL(settings)?.host?.lowercased()
    }

    public static func enforceDestination(_ urlString: String, settings: AppSettings) throws -> URL {
        guard let url = URL(string: urlString), let scheme = url.scheme?.lowercased() else {
            throw ToroLibreError.invalidDestination("Invalid destination URL: malformed URL")
        }

        guard scheme == "https" else {
            throw ToroLibreError.invalidDestination("Only https URLs are supported")
        }

        if settings.restrictHostToInstanceHost {
            let allowedHost = try settingsInstanceHost(settings).flatMap { $0.isEmpty ? nil : $0 }
            guard let allowedHost else {
                throw ToroLibreError.invalidDestination("Set your Toro Libre instance URL in Settings before opening destinations")
            }

            let host = (url.host ?? "").lowercased()
            guard host == allowedHost else {
                throw ToroLibreError.invalidDestination("Destination host '\(host)' is blocked by current policy")
            }
        }

        return url
    }

    public static func validateImportCompatibility(_ preset: Preset, allowedHost: String, row: Int) -> String? {
        if preset.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Row \(row): name cannot be empty"
        }

        let validation = validateURLTemplate(preset.urlTemplate)
        if !validation.valid {
            let reason = validation.reason ?? "Invalid URL template"
            return "Row \(row) ('\(preset.name)'): \(reason)"
        }

        do {
            let url = try parseURLTemplateCandidate(preset.urlTemplate)
            let host = url.host ?? ""
            if host.caseInsensitiveCompare(allowedHost) != .orderedSame {
                return "Row \(row) ('\(preset.name)'): host '\(host)' is not compatible with configured LibreChat host '\(allowedHost)'"
            }
        } catch {
            return "Row \(row) ('\(preset.name)'): \(error.localizedDescription)"
        }

        return nil
    }

    public static func importCandidates(from data: Data) throws -> [Preset] {
        let decoder = JSONDecoder()
        if let direct = try? decoder.decode([Preset].self, from: data) {
            return direct
        }

        let payload = try decoder.decode(PresetExportPayload.self, from: data)
        return payload.agents
    }

    public static func exportPayload(settings: AppSettings, presets: [Preset], exportedAt: String = ISO8601DateFormatter().string(from: Date())) -> PresetExportPayload {
        PresetExportPayload(
            version: 1,
            exportedAt: exportedAt,
            instanceBaseUrl: settings.instanceBaseUrl,
            agents: presets
        )
    }

    public static func expandTemplate(_ urlTemplate: String, query: String?) -> String {
        let hasQueryTemplate = urlTemplate.contains("{query}")
        let templated: String
        if hasQueryTemplate {
            let encoded = (query ?? "").addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)?
                .replacingOccurrences(of: "%20", with: "+") ?? ""
            templated = urlTemplate.replacingOccurrences(of: "{query}", with: encoded)
        } else {
            templated = urlTemplate
        }

        if hasQueryTemplate {
            return templated
        }

        guard let query, !query.isEmpty, var components = URLComponents(string: templated) else {
            return templated
        }

        var items = (components.queryItems ?? []).filter { item in
            !["prompt", "q", "submit"].contains(item.name)
        }
        items.append(URLQueryItem(name: "prompt", value: query))
        items.append(URLQueryItem(name: "submit", value: "true"))
        components.queryItems = items
        return components.url?.absoluteString ?? templated
    }

    public static func canUseSPANavigation(instanceHost: String?, url: URL) -> Bool {
        guard let instanceHost, let host = url.host else {
            return false
        }

        return host.caseInsensitiveCompare(instanceHost) == .orderedSame
    }

    public static func parseDeepLink(_ raw: String) throws -> DeepLinkAction {
        guard let url = URL(string: raw), let scheme = url.scheme?.lowercased() else {
            throw ToroLibreError.invalidDeepLink("Invalid deep link URL: malformed URL")
        }

        switch scheme {
        case "torolibre":
            return try parseCustomScheme(url)
        case "https":
            return try parseWebLink(url)
        default:
            throw ToroLibreError.invalidDeepLink("Unsupported deep link scheme")
        }
    }

    public static func queryValue(_ url: URL, key: String) -> String? {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first(where: { $0.name == key })?
            .value
    }

    private static func parseCustomScheme(_ url: URL) throws -> DeepLinkAction {
        switch url.host?.lowercased() {
        case "open":
            guard let destination = queryValue(url, key: "url") else {
                throw ToroLibreError.invalidDeepLink("Missing ?url= parameter")
            }
            return .openURL(destination)
        case "preset":
            let presetID = url.pathComponents.dropFirst().first ?? ""
            guard !presetID.isEmpty else {
                throw ToroLibreError.invalidDeepLink("Missing preset id in deep link")
            }
            return .openPreset(presetID: presetID, query: queryValue(url, key: "query"))
        case "settings":
            return .openSettings
        case let host?:
            throw ToroLibreError.invalidDeepLink("Unsupported deep link host: \(host)")
        case nil:
            throw ToroLibreError.invalidDeepLink("Invalid deep link host")
        }
    }

    private static func parseWebLink(_ url: URL) throws -> DeepLinkAction {
        switch url.path {
        case "/app/open":
            guard let destination = queryValue(url, key: "url") else {
                throw ToroLibreError.invalidDeepLink("Missing ?url= parameter")
            }
            return .openURL(destination)
        case "/app/settings":
            return .openSettings
        default:
            if url.path.hasPrefix("/app/preset/") {
                let presetID = String(url.path.dropFirst("/app/preset/".count))
                guard !presetID.isEmpty else {
                    throw ToroLibreError.invalidDeepLink("Missing preset id in deep link")
                }
                return .openPreset(presetID: presetID, query: queryValue(url, key: "query"))
            }
            throw ToroLibreError.invalidDeepLink("Unsupported web deep-link path")
        }
    }
}

public enum ToroLibreError: LocalizedError, Equatable {
    case invalidURLTemplate(String)
    case invalidInstanceURL(String)
    case invalidDestination(String)
    case invalidDeepLink(String)

    public var errorDescription: String? {
        switch self {
        case let .invalidURLTemplate(message),
             let .invalidInstanceURL(message),
             let .invalidDestination(message),
             let .invalidDeepLink(message):
            return message
        }
    }
}
