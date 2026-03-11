import Foundation

// This file is the pure shared logic layer.
// It defines the data model plus normalization, validation, parsing, and URL policy helpers.
public let appBundleIdentifier = "com.andreagrassi.kotobalibre"
public let appDisplayName = "Kotoba Libre"
public let settingsFileName = "settings.json"
public let presetsFileName = "presets.json"
public let mainWindowStateFileName = "main-window-state.json"

// Visibility mode affects both AppKit activation policy and whether a status item is installed.
public enum AppVisibilityMode: String, Codable, CaseIterable, Equatable, Sendable {
    case dockAndMenuBar
    case dockOnly
    case menuBarOnly

    public var showsDockIcon: Bool {
        self != .menuBarOnly
    }

    public var showsMenuBarItem: Bool {
        self != .dockOnly
    }
}

// Presets currently cover both named agents and generic saved links.
public enum PresetKind: String, Codable, CaseIterable, Equatable, Sendable {
    case agent
    case link
}

// Preset is the saved launcher destination shown in the Agents tab.
public struct Preset: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var urlTemplate: String
    public var kind: PresetKind
    public var createdAt: String
    public var updatedAt: String

    public init(
        id: String,
        name: String,
        urlTemplate: String,
        kind: PresetKind,
        createdAt: String,
        updatedAt: String
    ) {
        self.id = id
        self.name = name
        self.urlTemplate = urlTemplate
        self.kind = kind
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

// AppSettings is persisted user configuration.
// Defaults are chosen so a missing or older settings file can still decode safely.
public struct AppSettings: Codable, Equatable, Sendable {
    public static let defaultShortcut = "CmdOrCtrl+Shift+Space"
    public static let defaultVoiceShortcut = "CmdOrCtrl+Alt+V"
    public static let defaultShowAppWindowShortcut = "Ctrl+Alt+KeyK"

    public var instanceBaseUrl: String?
    public var globalShortcut: String
    public var voiceGlobalShortcut: String
    public var showAppWindowShortcut: String
    public var autostartEnabled: Bool
    public var restrictHostToInstanceHost: Bool
    public var defaultPresetId: String?
    public var useRouteReloadForLauncherChats: Bool
    public var debugLoggingEnabled: Bool
    public var launcherOpacity: Double
    public var appVisibilityMode: AppVisibilityMode

    enum CodingKeys: String, CodingKey {
        case instanceBaseUrl
        case globalShortcut
        case voiceGlobalShortcut
        case showAppWindowShortcut
        case autostartEnabled
        case restrictHostToInstanceHost
        case defaultPresetId
        case useRouteReloadForLauncherChats
        case debugLoggingEnabled
        case launcherOpacity
        case appVisibilityMode
    }

    public init(
        instanceBaseUrl: String? = nil,
        globalShortcut: String = AppSettings.defaultShortcut,
        voiceGlobalShortcut: String = AppSettings.defaultVoiceShortcut,
        showAppWindowShortcut: String = AppSettings.defaultShowAppWindowShortcut,
        autostartEnabled: Bool = false,
        restrictHostToInstanceHost: Bool = true,
        defaultPresetId: String? = nil,
        useRouteReloadForLauncherChats: Bool = false,
        debugLoggingEnabled: Bool = false,
        launcherOpacity: Double = 0.95,
        appVisibilityMode: AppVisibilityMode = .dockOnly
    ) {
        self.instanceBaseUrl = instanceBaseUrl
        self.globalShortcut = globalShortcut
        self.voiceGlobalShortcut = voiceGlobalShortcut
        self.showAppWindowShortcut = showAppWindowShortcut
        self.autostartEnabled = autostartEnabled
        self.restrictHostToInstanceHost = restrictHostToInstanceHost
        self.defaultPresetId = defaultPresetId
        self.useRouteReloadForLauncherChats = useRouteReloadForLauncherChats
        self.debugLoggingEnabled = debugLoggingEnabled
        self.launcherOpacity = launcherOpacity
        self.appVisibilityMode = appVisibilityMode
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // decodeIfPresent keeps backward compatibility with older files that do not know newer keys.
        instanceBaseUrl = try container.decodeIfPresent(String.self, forKey: .instanceBaseUrl)
        globalShortcut = try container.decodeIfPresent(String.self, forKey: .globalShortcut) ?? AppSettings.defaultShortcut
        voiceGlobalShortcut = try container.decodeIfPresent(String.self, forKey: .voiceGlobalShortcut) ?? AppSettings.defaultVoiceShortcut
        showAppWindowShortcut = try container.decodeIfPresent(String.self, forKey: .showAppWindowShortcut) ?? AppSettings.defaultShowAppWindowShortcut
        autostartEnabled = try container.decodeIfPresent(Bool.self, forKey: .autostartEnabled) ?? false
        restrictHostToInstanceHost = try container.decodeIfPresent(Bool.self, forKey: .restrictHostToInstanceHost) ?? true
        defaultPresetId = try container.decodeIfPresent(String.self, forKey: .defaultPresetId)
        useRouteReloadForLauncherChats = try container.decodeIfPresent(Bool.self, forKey: .useRouteReloadForLauncherChats) ?? false
        debugLoggingEnabled = try container.decodeIfPresent(Bool.self, forKey: .debugLoggingEnabled) ?? false
        launcherOpacity = try container.decodeIfPresent(Double.self, forKey: .launcherOpacity) ?? 0.95
        appVisibilityMode = try container.decodeIfPresent(AppVisibilityMode.self, forKey: .appVisibilityMode) ?? .dockOnly
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(instanceBaseUrl, forKey: .instanceBaseUrl)
        try container.encode(globalShortcut, forKey: .globalShortcut)
        try container.encode(voiceGlobalShortcut, forKey: .voiceGlobalShortcut)
        try container.encode(showAppWindowShortcut, forKey: .showAppWindowShortcut)
        try container.encode(autostartEnabled, forKey: .autostartEnabled)
        try container.encode(restrictHostToInstanceHost, forKey: .restrictHostToInstanceHost)
        try container.encodeIfPresent(defaultPresetId, forKey: .defaultPresetId)
        try container.encode(useRouteReloadForLauncherChats, forKey: .useRouteReloadForLauncherChats)
        try container.encode(debugLoggingEnabled, forKey: .debugLoggingEnabled)
        try container.encode(launcherOpacity, forKey: .launcherOpacity)
        try container.encode(appVisibilityMode, forKey: .appVisibilityMode)
    }
}

// WindowFrameState stores NSRect in Codable-friendly scalar values.
public struct WindowFrameState: Codable, Equatable, Sendable {
    public var originX: Double
    public var originY: Double
    public var width: Double
    public var height: Double

    public init(originX: Double, originY: Double, width: Double, height: Double) {
        self.originX = originX
        self.originY = originY
        self.width = width
        self.height = height
    }
}

// ValidationResult is used by the UI to render live validation messages.
public struct ValidationResult: Equatable, Sendable {
    public var valid: Bool
    public var reason: String?

    public init(valid: Bool, reason: String? = nil) {
        self.valid = valid
        self.reason = reason
    }
}

// Import results report both hard failures and rows that were skipped during validation.
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

// Deep links are normalized into a small action enum before the app layer routes them.
public enum DeepLinkAction: Equatable, Sendable {
    case openURL(String)
    case openPreset(presetID: String, query: String?)
    case openSettings
}

// Export payload wraps presets with metadata so exports can evolve without changing the raw preset array format.
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

// KotobaLibreCore is a namespace for stateless helpers used by both the app and self-test targets.
public enum KotobaLibreCore {
    public static func nowMarker(date: Date = Date()) -> String {
        "unix-ms-\(Int(date.timeIntervalSince1970 * 1_000))"
    }

    public static func normalizeShortcutToken(_ token: String) -> String {
        // User input accepts symbols, aliases, and plain keys. Storage uses one canonical token set.
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
        case "fn", "function":
            return "Fn"
        case "spacebar", "space":
            return "Space"
        default:
            if lower.hasPrefix("f"), let functionKeyNumber = Int(lower.dropFirst()), (1...24).contains(functionKeyNumber) {
                return "F\(functionKeyNumber)"
            }

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

        // Dedupe keeps accidental repeated modifiers from producing invalid shortcut strings.
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
        let voiceShortcut = normalizeShortcutValue(normalized.voiceGlobalShortcut)
        normalized.voiceGlobalShortcut = voiceShortcut.isEmpty ? AppSettings.defaultVoiceShortcut : voiceShortcut
        let showAppWindowShortcut = normalizeShortcutValue(normalized.showAppWindowShortcut)
        normalized.showAppWindowShortcut = showAppWindowShortcut.isEmpty ? AppSettings.defaultShowAppWindowShortcut : showAppWindowShortcut

        if let defaultPresetID = normalized.defaultPresetId?.trimmingCharacters(in: .whitespacesAndNewlines), !defaultPresetID.isEmpty {
            normalized.defaultPresetId = defaultPresetID
        } else {
            normalized.defaultPresetId = nil
        }

        normalized.launcherOpacity = min(max(normalized.launcherOpacity, 0.5), 1.0)

        return normalized
    }

    public static func validateShortcutConfiguration(_ settings: AppSettings) -> ValidationResult {
        let normalizedSettings = normalizeSettings(settings)
        let shortcuts = [
            normalizedSettings.globalShortcut,
            normalizedSettings.voiceGlobalShortcut,
            normalizedSettings.showAppWindowShortcut
        ]
        guard Set(shortcuts).count == shortcuts.count else {
            return ValidationResult(valid: false, reason: "Text launcher, voice launcher, and app window shortcuts must be different")
        }

        return ValidationResult(valid: true)
    }

    public static func normalizePreset(_ preset: Preset, existing: Preset? = nil, now: String = nowMarker()) -> Preset {
        // Existing presets keep their original creation time. New saves always refresh updatedAt.
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

        let updatedAt: String
        if existing != nil {
            updatedAt = now
        } else if preset.updatedAt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            updatedAt = now
        } else {
            updatedAt = preset.updatedAt
        }

        return Preset(
            id: presetID,
            name: preset.name.trimmingCharacters(in: .whitespacesAndNewlines),
            urlTemplate: normalizePresetValue(
                preset.urlTemplate.trimmingCharacters(in: .whitespacesAndNewlines),
                kind: preset.kind
            ),
            kind: preset.kind,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    public static func normalizeLoadedPresets(_ presets: [Preset], nowProvider: () -> String = { nowMarker() }) -> [Preset] {
        var seenIDs = Set<String>()

        // Load-time repair keeps old exports usable by fixing empty ids, duplicate ids, and missing timestamps.
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
            current.urlTemplate = normalizePresetValue(
                current.urlTemplate.trimmingCharacters(in: .whitespacesAndNewlines),
                kind: current.kind
            )

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

        // Templates are validated by parsing a safe sample URL after replacing the query placeholder.
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

    public static func normalizePresetValue(_ rawValue: String, kind: PresetKind) -> String {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)

        switch kind {
        case .agent:
            return agentID(from: trimmed) ?? trimmed
        case .link:
            return trimmed
        }
    }

    public static func agentID(from rawValue: String) -> String? {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }

        if let url = URL(string: trimmed), let agentID = queryValue(url, key: "agent_id")?.trimmingCharacters(in: .whitespacesAndNewlines), !agentID.isEmpty {
            return agentID
        }

        if trimmed.contains("://") {
            return nil
        }

        return trimmed
    }

    public static func validatePresetValue(_ value: String, kind: PresetKind) -> ValidationResult {
        switch kind {
        case .agent:
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                return ValidationResult(valid: false, reason: "Agent ID cannot be empty")
            }
            guard let normalizedAgentID = agentID(from: trimmed), !normalizedAgentID.isEmpty else {
                return ValidationResult(valid: false, reason: "Agent URLs must include an agent_id query parameter")
            }
            return ValidationResult(valid: true)
        case .link:
            return validateURLTemplate(value)
        }
    }

    public static func parseURLTemplateCandidate(_ urlTemplate: String) throws -> URL {
        // {query} is replaced with sample data so URL parsing can validate the overall shape.
        let candidate = urlTemplate.replacingOccurrences(of: "{query}", with: "example")
        guard let url = URL(string: candidate) else {
            throw KotobaLibreError.invalidURLTemplate("Invalid URL template: malformed URL")
        }
        return url
    }

    public static func parseInstanceBaseURL(_ settings: AppSettings) throws -> URL? {
        guard let raw = settings.instanceBaseUrl?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return nil
        }

        // Query and fragment parts are stripped because the instance URL is meant to be a clean base.
        guard let url = URL(string: raw), var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw KotobaLibreError.invalidInstanceURL("Invalid instance URL: malformed URL")
        }

        guard components.scheme?.lowercased() == "https" else {
            throw KotobaLibreError.invalidInstanceURL("Kotoba Libre instance URL must start with https://")
        }

        guard components.host != nil else {
            throw KotobaLibreError.invalidInstanceURL("Kotoba Libre instance URL must include a host")
        }

        components.query = nil
        components.fragment = nil
        guard let normalized = components.url else {
            throw KotobaLibreError.invalidInstanceURL("Invalid instance URL: malformed URL")
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

    public static func presetTemplateHost(_ preset: Preset) throws -> String? {
        if preset.kind == .agent {
            return nil
        }

        return try parseURLTemplateCandidate(preset.urlTemplate).host?.lowercased()
    }

    public static func validatePresetCompatibility(_ preset: Preset, allowedHost: String) -> String? {
        if preset.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "name cannot be empty"
        }

        let validation = validatePresetValue(preset.urlTemplate, kind: preset.kind)
        if !validation.valid {
            return validation.reason ?? "Invalid URL template"
        }

        if preset.kind == .agent {
            return nil
        }

        do {
            let host = try presetTemplateHost(preset) ?? ""
            if host.caseInsensitiveCompare(allowedHost) != .orderedSame {
                return "host '\(host)' is not compatible with configured LibreChat host '\(allowedHost)'"
            }
        } catch {
            return error.localizedDescription
        }

        return nil
    }

    public static func incompatiblePresets(_ presets: [Preset], settings: AppSettings) throws -> [Preset] {
        // Compatibility filtering is only relevant when host restriction is turned on.
        guard settings.restrictHostToInstanceHost, let allowedHost = try settingsInstanceHost(settings) else {
            return []
        }

        return presets.filter { preset in
            validatePresetCompatibility(preset, allowedHost: allowedHost) != nil
        }
    }

    public static func enforceDestination(_ urlString: String, settings: AppSettings) throws -> URL {
        // Every destination is checked here so launcher opens and deep links obey the same policy.
        guard let url = URL(string: urlString), let scheme = url.scheme?.lowercased() else {
            throw KotobaLibreError.invalidDestination("Invalid destination URL: malformed URL")
        }

        guard scheme == "https" else {
            throw KotobaLibreError.invalidDestination("Only https URLs are supported")
        }

        if settings.restrictHostToInstanceHost {
            let allowedHost = try settingsInstanceHost(settings).flatMap { $0.isEmpty ? nil : $0 }
            guard let allowedHost else {
                throw KotobaLibreError.invalidDestination("Set your Kotoba Libre instance URL in Settings before opening destinations")
            }

            let host = (url.host ?? "").lowercased()
            guard host == allowedHost else {
                throw KotobaLibreError.invalidDestination("Destination host '\(host)' is blocked by current policy")
            }
        }

        return url
    }

    public static func validateImportCompatibility(_ preset: Preset, allowedHost: String, row: Int) -> String? {
        if let issue = validatePresetCompatibility(preset, allowedHost: allowedHost) {
            if preset.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return "Row \(row): \(issue)"
            }
            return "Row \(row) ('\(preset.name)'): \(issue)"
        }

        return nil
    }

    public static func importCandidates(from data: Data) throws -> [Preset] {
        let decoder = JSONDecoder()
        // Imports accept either a raw preset array or the richer export payload wrapper.
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

    public static func previewDestination(for preset: Preset, instanceBaseURL: String?) throws -> String {
        try destinationString(for: preset, instanceBaseURL: instanceBaseURL, query: nil)
    }

    public static func destinationString(for preset: Preset, instanceBaseURL: String?, query: String?) throws -> String {
        switch preset.kind {
        case .agent:
            guard let baseURL = try parseInstanceBaseURL(AppSettings(instanceBaseUrl: instanceBaseURL)) else {
                throw KotobaLibreError.invalidDestination("Set your LibreChat instance URL to preview or open agents")
            }
            guard let agentID = agentID(from: preset.urlTemplate), !agentID.isEmpty else {
                throw KotobaLibreError.invalidDestination("Agent ID cannot be empty")
            }

            let normalizedBaseURL = baseURL.absoluteString.hasSuffix("/") ? baseURL.absoluteString : "\(baseURL.absoluteString)/"
            guard
                let base = URL(string: normalizedBaseURL),
                var components = URLComponents(url: URL(string: "c/new", relativeTo: base)?.absoluteURL ?? baseURL, resolvingAgainstBaseURL: false)
            else {
                throw KotobaLibreError.invalidDestination("Invalid LibreChat instance URL")
            }

            var items = components.queryItems ?? []
            items.removeAll { $0.name == "agent_id" }
            items.append(URLQueryItem(name: "agent_id", value: agentID))
            components.queryItems = items

            guard let destination = components.url?.absoluteString else {
                throw KotobaLibreError.invalidDestination("Invalid agent destination URL")
            }

            return appendQuery(to: destination, query: query)
        case .link:
            return expandTemplate(preset.urlTemplate, query: query)
        }
    }

    public static func expandTemplate(_ urlTemplate: String, query: String?) -> String {
        // There are two modes:
        // 1. Replace {query} when the template wants full control.
        // 2. Append prompt and submit parameters when the template is just a destination URL.
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

        return appendQuery(to: templated, query: query)
    }

    private static func appendQuery(to destination: String, query: String?) -> String {
        guard let query, !query.isEmpty, var components = URLComponents(string: destination) else {
            return destination
        }

        var items = (components.queryItems ?? []).filter { item in
            !["prompt", "q", "submit"].contains(item.name)
        }
        items.append(URLQueryItem(name: "prompt", value: query))
        items.append(URLQueryItem(name: "submit", value: "true"))
        components.queryItems = items
        return components.url?.absoluteString ?? destination
    }

    public static func canUseSPANavigation(instanceHost: String?, url: URL) -> Bool {
        // SPA navigation is only trusted for the configured instance host.
        guard let instanceHost, let host = url.host else {
            return false
        }

        return host.caseInsensitiveCompare(instanceHost) == .orderedSame
    }

    public static func parseDeepLink(_ raw: String) throws -> DeepLinkAction {
        guard let url = URL(string: raw), let scheme = url.scheme?.lowercased() else {
            throw KotobaLibreError.invalidDeepLink("Invalid deep link URL: malformed URL")
        }

        switch scheme {
        case "kotobalibre":
            return try parseCustomScheme(url)
        case "https":
            return try parseWebLink(url)
        default:
            throw KotobaLibreError.invalidDeepLink("Unsupported deep link scheme")
        }
    }

    public static func queryValue(_ url: URL, key: String) -> String? {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first(where: { $0.name == key })?
            .value
    }

    private static func parseCustomScheme(_ url: URL) throws -> DeepLinkAction {
        // kotobalibre://... deep links are used for native handoff from outside the app.
        switch url.host?.lowercased() {
        case "open":
            guard let destination = queryValue(url, key: "url") else {
                throw KotobaLibreError.invalidDeepLink("Missing ?url= parameter")
            }
            return .openURL(destination)
        case "preset":
            let presetID = url.pathComponents.dropFirst().first ?? ""
            guard !presetID.isEmpty else {
                throw KotobaLibreError.invalidDeepLink("Missing preset id in deep link")
            }
            return .openPreset(presetID: presetID, query: queryValue(url, key: "query"))
        case "settings":
            return .openSettings
        case let host?:
            throw KotobaLibreError.invalidDeepLink("Unsupported deep link host: \(host)")
        case nil:
            throw KotobaLibreError.invalidDeepLink("Invalid deep link host")
        }
    }

    private static func parseWebLink(_ url: URL) throws -> DeepLinkAction {
        // Matching https links provide the same actions for browser-based entry points.
        switch url.path {
        case "/app/open":
            guard let destination = queryValue(url, key: "url") else {
                throw KotobaLibreError.invalidDeepLink("Missing ?url= parameter")
            }
            return .openURL(destination)
        case "/app/settings":
            return .openSettings
        default:
            if url.path.hasPrefix("/app/preset/") {
                let presetID = String(url.path.dropFirst("/app/preset/".count))
                guard !presetID.isEmpty else {
                    throw KotobaLibreError.invalidDeepLink("Missing preset id in deep link")
                }
                return .openPreset(presetID: presetID, query: queryValue(url, key: "query"))
            }
            throw KotobaLibreError.invalidDeepLink("Unsupported web deep-link path")
        }
    }
}

// Core errors are shared across app, deep link, and import flows, so the messages stay user-facing.
public enum KotobaLibreError: LocalizedError, Equatable {
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
