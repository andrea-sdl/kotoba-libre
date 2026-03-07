import Foundation
import ToroLibreCore

@main
struct ToroLibreSelfTest {
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
                openInNewWindow: false,
                restrictHostToInstanceHost: true,
                defaultPresetId: "preset-1",
                debugInWebview: false,
                useRouteReloadForLauncherChats: false,
                accentColor: "blue",
                launcherOpacity: 0.95
            )
        }

        expect(ToroLibreCore.normalizeShortcutValue("⌘ + ⇧ + space") == "CmdOrCtrl+Shift+Space", "shortcutSymbolsAreNormalized cmd")
        expect(ToroLibreCore.normalizeShortcutValue("ctrl + k") == "Ctrl+KeyK", "shortcutSymbolsAreNormalized ctrl")

        let normalizedSettings = ToroLibreCore.normalizeSettings(
            AppSettings(
                instanceBaseUrl: "https://chat.example.com",
                globalShortcut: "commandorcontrol + option + v",
                autostartEnabled: false,
                openInNewWindow: false,
                restrictHostToInstanceHost: true,
                defaultPresetId: "preset-1",
                debugInWebview: false,
                useRouteReloadForLauncherChats: false,
                accentColor: "blue",
                launcherOpacity: 0.95
            )
        )
        expect(normalizedSettings.globalShortcut == "CmdOrCtrl+Alt+KeyV", "settingsNormalizeShortcutAliases")

        let openURLParsed = try ToroLibreCore.parseDeepLink("torolibre://open?url=https%3A%2F%2Fchat.example.com%2Fc%2F123")
        expect(openURLParsed == .openURL("https://chat.example.com/c/123"), "deepLinkOpenURLIsParsed")

        let presetParsed = try ToroLibreCore.parseDeepLink("torolibre://preset/preset-1?query=hello%20world")
        expect(presetParsed == .openPreset(presetID: "preset-1", query: "hello world"), "deepLinkPresetIsParsed")

        expectThrows("deepLinkInvalidFails missing url") {
            _ = try ToroLibreCore.parseDeepLink("torolibre://open")
        }
        expectThrows("deepLinkInvalidFails unsupported scheme") {
            _ = try ToroLibreCore.parseDeepLink("ftp://example.com/app/open?url=https://chat.example.com")
        }

        let settings = settingsRestrictingHost()
        expect(try ToroLibreCore.enforceDestination("https://chat.example.com/c/new", settings: settings).absoluteString == "https://chat.example.com/c/new", "hostRestrictionAllowsChatHost")
        expectThrows("hostRestrictionBlocksNonChatHost") {
            _ = try ToroLibreCore.enforceDestination("https://example.com", settings: settings)
        }

        var unrestrictedSettings = settingsRestrictingHost()
        unrestrictedSettings.restrictHostToInstanceHost = false
        expect(try ToroLibreCore.enforceDestination("https://example.com", settings: unrestrictedSettings).absoluteString == "https://example.com", "hostRestrictionCanBeDisabled")

        var missingInstanceSettings = settingsRestrictingHost()
        missingInstanceSettings.instanceBaseUrl = nil
        expectThrows("hostRestrictionRequiresInstanceWhenEnabled") {
            _ = try ToroLibreCore.enforceDestination("https://chat.example.com/c/new", settings: missingInstanceSettings)
        }

        expect(ToroLibreCore.expandTemplate("https://chat.example.com/search?q={query}", query: "hello world") == "https://chat.example.com/search?q=hello+world", "templateQueryPlaceholderIsEncoded")
        expect(ToroLibreCore.expandTemplate("https://chat.example.com/c/new?agent_id=agent_aLfpSjQmQKt9nhbFi7BIs", query: "hello world") == "https://chat.example.com/c/new?agent_id=agent_aLfpSjQmQKt9nhbFi7BIs&prompt=hello%20world&submit=true", "templateQueryIsAppendedAsPromptWithSubmitWhenMissingPlaceholder")

        let input = [
            Preset(id: "", name: "  Agent One  ", urlTemplate: " https://chat.example.com/c/new?agent_id=1 ", kind: .agent, tags: [" support ", "support"], createdAt: "", updatedAt: ""),
            Preset(id: "dup", name: "Agent Two", urlTemplate: "https://chat.example.com/c/new?agent_id=2", kind: .agent, tags: [], createdAt: "unix-ms-1", updatedAt: ""),
            Preset(id: "dup", name: "Agent Three", urlTemplate: "https://chat.example.com/c/new?agent_id=3", kind: .agent, tags: [], createdAt: "unix-ms-2", updatedAt: "unix-ms-3")
        ]
        let normalizedPresets = ToroLibreCore.normalizeLoadedPresets(input, nowProvider: { "unix-ms-now" })
        expect(normalizedPresets.count == 3, "loadedPresets count")
        expect(!normalizedPresets[0].id.isEmpty, "loadedPresets generated id")
        expect(normalizedPresets[1].id == "dup", "loadedPresets preserves first duplicate")
        expect(normalizedPresets[2].id != "dup", "loadedPresets changes second duplicate")
        expect(normalizedPresets[0].name == "Agent One", "loadedPresets trims name")
        expect(normalizedPresets[0].urlTemplate == "https://chat.example.com/c/new?agent_id=1", "loadedPresets trims url")
        expect(normalizedPresets[0].tags == ["support"], "loadedPresets normalize tags")
        expect(normalizedPresets[1].updatedAt == "unix-ms-1", "loadedPresets backfill updatedAt")

        let mismatchedPreset = Preset(id: "id-1", name: "Support Agent", urlTemplate: "https://other.example.com/c/new?agent_id=1", kind: .agent, tags: [], createdAt: "unix-ms-1", updatedAt: "unix-ms-2")
        expect(ToroLibreCore.validateImportCompatibility(mismatchedPreset, allowedHost: "chat.example.com", row: 1) != nil, "importValidationRejectsHostMismatch")

        let matchingPreset = Preset(id: "id-1", name: "Support Agent", urlTemplate: "https://chat.example.com/c/new?agent_id=1", kind: .agent, tags: [], createdAt: "unix-ms-1", updatedAt: "unix-ms-2")
        expect(ToroLibreCore.validateImportCompatibility(matchingPreset, allowedHost: "chat.example.com", row: 1) == nil, "importValidationAcceptsMatchingHost")

        let allowedSPAURL = URL(string: "https://chat.example.com/c/new?agent_id=agent_aLfpSjQmQKt9nhbFi7BIs&prompt=hello&submit=true")!
        expect(ToroLibreCore.canUseSPANavigation(instanceHost: "chat.example.com", url: allowedSPAURL), "spaNavigationAllowedForLauncherSubmitURLOnInstanceHost")
        let blockedSPAURL = URL(string: "https://example.com/c/new?prompt=hello&submit=true")!
        expect(!ToroLibreCore.canUseSPANavigation(instanceHost: "chat.example.com", url: blockedSPAURL), "spaNavigationBlockedForNonInstanceHost")

        let encodedSettings = try JSONEncoder().encode(AppSettings())
        let decodedSettings = try JSONDecoder().decode(AppSettings.self, from: encodedSettings)
        expect(decodedSettings == AppSettings(), "settingsRoundTrip")

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
        try store.resetConfiguration()
        expect(!FileManager.default.fileExists(atPath: store.settingsURL.path), "storeResetRemovesSettings")
        expect(try store.loadSettings() == AppSettings(), "storeResetLoadsDefaultSettings")
        expect(try store.loadPresets().isEmpty, "storeResetLoadsEmptyPresets")

        if failures.isEmpty {
            print("ToroLibreSelfTest: all checks passed (\(30) assertions)")
            return
        }

        fputs("ToroLibreSelfTest failures:\n", stderr)
        for failure in failures {
            fputs("- \(failure)\n", stderr)
        }
        Foundation.exit(1)
    }
}
