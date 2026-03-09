import Foundation
import KotobaLibreCore

@main
struct KotobaLibreSelfTest {
    static func main() throws {
        var failures: [String] = []

        func expect(_ condition: @autoclosure () throws -> Bool, _ message: String) {
            do {
                if try !condition() {
                    failures.append(message)
                }
            } catch {
                failures.append("\(message): \(error.localizedDescription)")
            }
        }

        func expectThrows(_ message: String, _ work: () throws -> Void) {
            do {
                try work()
                failures.append(message)
            } catch {
            }
        }

        func settingsRestrictingHost() -> AppSettings {
            AppSettings(
                instanceBaseUrl: "https://chat.example.com",
                globalShortcut: AppSettings.defaultShortcut,
                autostartEnabled: false,
                restrictHostToInstanceHost: true,
                defaultPresetId: "preset-1",
                useRouteReloadForLauncherChats: false,
                launcherOpacity: 0.95
            )
        }

        expect(KotobaLibreCore.normalizeShortcutValue("⌘ + ⇧ + space") == "CmdOrCtrl+Shift+Space", "shortcutSymbolsAreNormalized cmd")
        expect(KotobaLibreCore.normalizeShortcutValue("ctrl + k") == "Ctrl+KeyK", "shortcutSymbolsAreNormalized ctrl")

        let normalizedSettings = KotobaLibreCore.normalizeSettings(
            AppSettings(
                instanceBaseUrl: "https://chat.example.com",
                globalShortcut: "commandorcontrol + option + v",
                autostartEnabled: false,
                restrictHostToInstanceHost: true,
                defaultPresetId: "preset-1",
                useRouteReloadForLauncherChats: false,
                launcherOpacity: 0.95,
                appVisibilityMode: .dockAndMenuBar
            )
        )
        expect(normalizedSettings.globalShortcut == "CmdOrCtrl+Alt+KeyV", "settingsNormalizeShortcutAliases")
        expect(normalizedSettings.appVisibilityMode == .dockAndMenuBar, "settingsPreserveVisibilityMode")

        let openURLParsed = try KotobaLibreCore.parseDeepLink("kotobalibre://open?url=https%3A%2F%2Fchat.example.com%2Fc%2F123")
        expect(openURLParsed == .openURL("https://chat.example.com/c/123"), "deepLinkOpenURLIsParsed")

        let presetParsed = try KotobaLibreCore.parseDeepLink("kotobalibre://preset/preset-1?query=hello%20world")
        expect(presetParsed == .openPreset(presetID: "preset-1", query: "hello world"), "deepLinkPresetIsParsed")

        expectThrows("deepLinkInvalidFails missing url") {
            _ = try KotobaLibreCore.parseDeepLink("kotobalibre://open")
        }
        expectThrows("deepLinkInvalidFails unsupported scheme") {
            _ = try KotobaLibreCore.parseDeepLink("ftp://example.com/app/open?url=https://chat.example.com")
        }

        let settings = settingsRestrictingHost()
        expect(try KotobaLibreCore.enforceDestination("https://chat.example.com/c/new", settings: settings).absoluteString == "https://chat.example.com/c/new", "hostRestrictionAllowsChatHost")
        expectThrows("hostRestrictionBlocksNonChatHost") {
            _ = try KotobaLibreCore.enforceDestination("https://example.com", settings: settings)
        }

        var unrestrictedSettings = settingsRestrictingHost()
        unrestrictedSettings.restrictHostToInstanceHost = false
        expect(try KotobaLibreCore.enforceDestination("https://example.com", settings: unrestrictedSettings).absoluteString == "https://example.com", "hostRestrictionCanBeDisabled")

        var missingInstanceSettings = settingsRestrictingHost()
        missingInstanceSettings.instanceBaseUrl = nil
        expectThrows("hostRestrictionRequiresInstanceWhenEnabled") {
            _ = try KotobaLibreCore.enforceDestination("https://chat.example.com/c/new", settings: missingInstanceSettings)
        }

        expect(KotobaLibreCore.expandTemplate("https://chat.example.com/search?q={query}", query: "hello world") == "https://chat.example.com/search?q=hello+world", "templateQueryPlaceholderIsEncoded")
        expect(KotobaLibreCore.expandTemplate("https://chat.example.com/c/new?agent_id=agent_aLfpSjQmQKt9nhbFi7BIs", query: "hello world") == "https://chat.example.com/c/new?agent_id=agent_aLfpSjQmQKt9nhbFi7BIs&prompt=hello%20world&submit=true", "templateQueryIsAppendedAsPromptWithSubmitWhenMissingPlaceholder")
        expect(KotobaLibreCore.expandTemplate("https://chat.example.com/c/new/support-agent", query: "hello world") == "https://chat.example.com/c/new/support-agent?prompt=hello%20world&submit=true", "templateQueryKeepsPathBasedAgentRoute")

        let input = [
            Preset(id: "", name: "  Agent One  ", urlTemplate: " https://chat.example.com/c/new?agent_id=1 ", kind: .agent, tags: [" support ", "support"], createdAt: "", updatedAt: ""),
            Preset(id: "dup", name: "Agent Two", urlTemplate: "https://chat.example.com/c/new?agent_id=2", kind: .agent, tags: [], createdAt: "unix-ms-1", updatedAt: ""),
            Preset(id: "dup", name: "Agent Three", urlTemplate: "https://chat.example.com/c/new?agent_id=3", kind: .agent, tags: [], createdAt: "unix-ms-2", updatedAt: "unix-ms-3")
        ]
        let normalizedPresets = KotobaLibreCore.normalizeLoadedPresets(input, nowProvider: { "unix-ms-now" })
        expect(normalizedPresets.count == 3, "loadedPresets count")
        expect(!normalizedPresets[0].id.isEmpty, "loadedPresets generated id")
        expect(normalizedPresets[1].id == "dup", "loadedPresets preserves first duplicate")
        expect(normalizedPresets[2].id != "dup", "loadedPresets changes second duplicate")
        expect(normalizedPresets[0].name == "Agent One", "loadedPresets trims name")
        expect(normalizedPresets[0].urlTemplate == "https://chat.example.com/c/new?agent_id=1", "loadedPresets trims url")
        expect(normalizedPresets[0].tags == ["support"], "loadedPresets normalize tags")
        expect(normalizedPresets[1].updatedAt == "unix-ms-1", "loadedPresets backfill updatedAt")

        let mismatchedPreset = Preset(id: "id-1", name: "Support Agent", urlTemplate: "https://other.example.com/c/new?agent_id=1", kind: .agent, tags: [], createdAt: "unix-ms-1", updatedAt: "unix-ms-2")
        expect(KotobaLibreCore.validateImportCompatibility(mismatchedPreset, allowedHost: "chat.example.com", row: 1) != nil, "importValidationRejectsHostMismatch")

        let matchingPreset = Preset(id: "id-1", name: "Support Agent", urlTemplate: "https://chat.example.com/c/new?agent_id=1", kind: .agent, tags: [], createdAt: "unix-ms-1", updatedAt: "unix-ms-2")
        expect(KotobaLibreCore.validateImportCompatibility(matchingPreset, allowedHost: "chat.example.com", row: 1) == nil, "importValidationAcceptsMatchingHost")
        expect(KotobaLibreCore.validatePresetCompatibility(matchingPreset, allowedHost: "chat.example.com") == nil, "presetCompatibilityAcceptsMatchingHost")
        expect(KotobaLibreCore.validatePresetCompatibility(mismatchedPreset, allowedHost: "chat.example.com") != nil, "presetCompatibilityRejectsHostMismatch")
        expect(try KotobaLibreCore.incompatiblePresets([matchingPreset, mismatchedPreset], settings: settingsRestrictingHost()) == [mismatchedPreset], "incompatiblePresetFiltering")

        let allowedSPAURL = URL(string: "https://chat.example.com/c/new?agent_id=agent_aLfpSjQmQKt9nhbFi7BIs&prompt=hello&submit=true")!
        expect(KotobaLibreCore.canUseSPANavigation(instanceHost: "chat.example.com", url: allowedSPAURL), "spaNavigationAllowedForLauncherSubmitURLOnInstanceHost")
        let allowedSPAHomeURL = URL(string: "https://chat.example.com/c/new?agent_id=agent_aLfpSjQmQKt9nhbFi7BIs")!
        expect(KotobaLibreCore.canUseSPANavigation(instanceHost: "chat.example.com", url: allowedSPAHomeURL), "spaNavigationAllowedForPlainAgentRouteOnInstanceHost")
        let blockedSPAURL = URL(string: "https://example.com/c/new?prompt=hello&submit=true")!
        expect(!KotobaLibreCore.canUseSPANavigation(instanceHost: "chat.example.com", url: blockedSPAURL), "spaNavigationBlockedForNonInstanceHost")

        let encodedSettings = try JSONEncoder().encode(AppSettings())
        let decodedSettings = try JSONDecoder().decode(AppSettings.self, from: encodedSettings)
        expect(decodedSettings == AppSettings(), "settingsRoundTrip")

        let legacySettingsJSON = """
        {"instanceBaseUrl":"https://chat.example.com","globalShortcut":"CmdOrCtrl+Shift+Space","autostartEnabled":false,"restrictHostToInstanceHost":true,"defaultPresetId":"preset-1","useRouteReloadForLauncherChats":false,"launcherOpacity":0.95}
        """.data(using: .utf8)!
        let decodedLegacySettings = try JSONDecoder().decode(AppSettings.self, from: legacySettingsJSON)
        expect(decodedLegacySettings.appVisibilityMode == .dockOnly, "settingsDecodeLegacyVisibilityDefault")

        let roundTripPreset = Preset(id: "id-1", name: "Support Agent", urlTemplate: "https://chat.example.com/c/new?agent=support", kind: .agent, tags: ["support", "internal"], createdAt: "unix-ms-1", updatedAt: "unix-ms-2")
        let encodedPreset = try JSONEncoder().encode(roundTripPreset)
        let decodedPreset = try JSONDecoder().decode(Preset.self, from: encodedPreset)
        expect(decodedPreset == roundTripPreset, "presetRoundTrip")

        let tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = try AppDataStore(baseDirectory: tempDirectory)
        try store.saveSettings(settingsRestrictingHost())
        try store.savePresets([Preset(id: "preset-1", name: "Support", urlTemplate: "https://chat.example.com/c/new?agent_id=1", kind: .agent, tags: [], createdAt: "unix-ms-1", updatedAt: "unix-ms-1")])
        expect(FileManager.default.fileExists(atPath: store.settingsURL.path), "storeWritesSettings")
        expect(FileManager.default.fileExists(atPath: store.presetsURL.path), "storeWritesPresets")
        expect(try store.loadSettings().instanceBaseUrl == "https://chat.example.com", "storeLoadsSettings")
        expect(try store.loadPresets().count == 1, "storeLoadsPresets")
        let savedWindowState = WindowFrameState(originX: 120, originY: 180, width: 980, height: 760)
        try store.saveMainWindowState(savedWindowState)
        expect(FileManager.default.fileExists(atPath: store.mainWindowStateURL.path), "storeWritesMainWindowState")
        expect(try store.loadMainWindowState() == savedWindowState, "storeLoadsMainWindowState")
        try store.resetConfiguration()
        expect(!FileManager.default.fileExists(atPath: store.settingsURL.path), "storeResetRemovesSettings")
        expect(!FileManager.default.fileExists(atPath: store.mainWindowStateURL.path), "storeResetRemovesMainWindowState")
        expect(try store.loadSettings() == AppSettings(), "storeResetLoadsDefaultSettings")
        expect(try store.loadMainWindowState() == nil, "storeResetLoadsEmptyMainWindowState")
        expect(try store.loadPresets().isEmpty, "storeResetLoadsEmptyPresets")

        if failures.isEmpty {
            print("KotobaLibreSelfTest: all checks passed (\(41) assertions)")
            return
        }

        fputs("KotobaLibreSelfTest failures:\n", stderr)
        for failure in failures {
            fputs("- \(failure)\n", stderr)
        }
        Foundation.exit(1)
    }
}
