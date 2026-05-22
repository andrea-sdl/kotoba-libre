import Foundation
import JavaScriptCore
import KotobaLibreCore

// This is a lightweight executable regression suite for the core module.
// The project uses it instead of `swift test` for simple local and CI validation.
@main
struct KotobaLibreSelfTest {
    static func main() throws {
        var failures: [String] = []
        var assertionCount = 0

        // Local helpers collect failures so the suite can report all broken behaviors in one run.
        func expect(_ condition: @autoclosure () throws -> Bool, _ message: String) {
            assertionCount += 1
            do {
                if try !condition() {
                    failures.append(message)
                }
            } catch {
                failures.append("\(message): \(error.localizedDescription)")
            }
        }

        func expectThrows(_ message: String, _ work: () throws -> Void) {
            assertionCount += 1
            do {
                try work()
                failures.append(message)
            } catch {
            }
        }

        // Most URL policy tests share the same host-restricted baseline settings.
        func settingsRestrictingHost() -> AppSettings {
            AppSettings(
                instanceBaseUrl: "https://chat.example.com",
                globalShortcut: AppSettings.defaultShortcut,
                voiceGlobalShortcut: AppSettings.defaultVoiceShortcut,
                autostartEnabled: false,
                restrictHostToInstanceHost: true,
                defaultPresetId: "preset-1",
                useRouteReloadForLauncherChats: false,
                launcherOpacity: 0.95,
                backgroundResponseNotificationsEnabled: true,
                longResponseNotificationThresholdSeconds: AppSettings.defaultLongResponseNotificationThresholdSeconds
            )
        }

        expect(KotobaLibreCore.normalizeShortcutValue("⌘ + ⇧ + space") == "CmdOrCtrl+Shift+Space", "shortcutSymbolsAreNormalized cmd")
        expect(KotobaLibreCore.normalizeShortcutValue("ctrl + k") == "Ctrl+KeyK", "shortcutSymbolsAreNormalized ctrl")
        expect(KotobaLibreCore.normalizeShortcutValue("ctrl + option + k") == "Ctrl+Alt+KeyK", "shortcutSymbolsAreNormalized showAppWindowDefault")
        expect(AppSettings.defaultShortcut == "Ctrl+Alt+Space", "settingsDefaultLauncherShortcutMatchesRequestedValue")
        expect(AppSettings.defaultVoiceShortcut == "Ctrl+Alt+V", "settingsDefaultVoiceShortcutMatchesRequestedValue")
        expect(AppSettings.defaultShowAppWindowShortcut == "Ctrl+Alt+K", "settingsDefaultShowWindowShortcutMatchesRequestedValue")
        expect(AppSettings.defaultMCPAutoReconnectIntervalMinutes == 30, "settingsDefaultMCPReconnectIntervalMatchesRequestedValue")
        let sequentialMCPReconnectResult = try runMCPBridgeRegressionScenario(Self.sequentialMCPReconnectScenario)
        expect(sequentialMCPReconnectResult.uiClicked == 2, "mcpBridgeClicksSequentialVisibleConnectControls")
        expect(sequentialMCPReconnectResult.reinitialized == 0, "mcpBridgeAvoidsAPIFallbackWhenSequentialUIClicksWork")
        expect(sequentialMCPReconnectResult.connected == 2, "mcpBridgeCountsTwoSequentialUIReconnects")
        expect(sequentialMCPReconnectResult.errors.isEmpty, "mcpBridgeSequentialUIReconnectHasNoErrors")

        let fallbackMCPReconnectResult = try runMCPBridgeRegressionScenario(Self.remainingMCPAPIFallbackScenario)
        expect(fallbackMCPReconnectResult.uiClicked == 1, "mcpBridgeClicksAvailableUIControlBeforeFallback")
        expect(fallbackMCPReconnectResult.reinitialized == 1, "mcpBridgeFallsBackToAPIForRemainingDisconnectedServer")
        expect(fallbackMCPReconnectResult.connected == 2, "mcpBridgeConnectsUIAndAPIFallbackServers")
        expect(fallbackMCPReconnectResult.errors.isEmpty, "mcpBridgeMixedUIAndAPIFallbackHasNoErrors")

        let connectingFallbackMCPReconnectResult = try runMCPBridgeRegressionScenario(Self.connectingMCPAPIFallbackScenario)
        expect(connectingFallbackMCPReconnectResult.uiClicked == 1, "mcpBridgeClicksUIControlBeforeConnectingFallback")
        expect(connectingFallbackMCPReconnectResult.reinitialized == 1, "mcpBridgeFallsBackToAPIWhenUIConnectingReturnsDisconnected")
        expect(connectingFallbackMCPReconnectResult.connected == 1, "mcpBridgeConnectsAfterConnectingFallback")
        expect(connectingFallbackMCPReconnectResult.errors.isEmpty, "mcpBridgeConnectingFallbackHasNoErrors")

        let authRetryMCPReconnectResult = try runMCPBridgeRegressionScenario(Self.authRefreshMCPReconnectScenario)
        expect(authRetryMCPReconnectResult.reinitialized == 1, "mcpBridgeReinitializesAfterAuthRefresh")
        expect(authRetryMCPReconnectResult.connected == 1, "mcpBridgeConnectsAfterAuthRefreshRetry")
        expect(authRetryMCPReconnectResult.errors.isEmpty, "mcpBridgeAuthRefreshRetryHasNoErrors")

        let safeReloadMCPReconnectResult = try runMCPBridgeRegressionScenario(Self.reloadAllowedMCPReconnectScenario)
        expect(safeReloadMCPReconnectResult.reloadPerformed, "mcpBridgePerformsSafeReloadAfterReconnect")
        expect(!safeReloadMCPReconnectResult.reloadDeferred, "mcpBridgeDoesNotDeferSafeReload")
        expect(safeReloadMCPReconnectResult.reloadCount == 1, "mcpBridgeSchedulesOneSafeReload")

        let unsafeReloadMCPReconnectResult = try runMCPBridgeRegressionScenario(
            Self.reloadAllowedMCPReconnectScenario,
            reloadAfterReconnect: false
        )
        expect(!unsafeReloadMCPReconnectResult.reloadPerformed, "mcpBridgeDoesNotReloadWhenNativeGateIsUnsafe")
        expect(unsafeReloadMCPReconnectResult.reloadDeferred, "mcpBridgeDefersReloadWhenNativeGateIsUnsafe")
        expect(unsafeReloadMCPReconnectResult.reloadCount == 0, "mcpBridgeSkipsReloadWhenNativeGateIsUnsafe")

        let focusedEditableReloadResult = try runMCPBridgeRegressionScenario(Self.focusedEditableBlocksMCPReloadScenario)
        expect(!focusedEditableReloadResult.reloadPerformed, "mcpBridgeDoesNotReloadFocusedEditablePage")
        expect(focusedEditableReloadResult.reloadDeferred, "mcpBridgeDefersFocusedEditableReload")
        expect(focusedEditableReloadResult.reloadCount == 0, "mcpBridgeFocusedEditableHasNoReloadCall")

        let draftReloadResult = try runMCPBridgeRegressionScenario(Self.draftBlocksMCPReloadScenario)
        expect(!draftReloadResult.reloadPerformed, "mcpBridgeDoesNotReloadComposerDraft")
        expect(draftReloadResult.reloadDeferred, "mcpBridgeDefersComposerDraftReload")
        expect(draftReloadResult.reloadCount == 0, "mcpBridgeComposerDraftHasNoReloadCall")

        let pendingSafeReloadResult = try runMCPBridgeRegressionScenario(
            Self.noReconnectMCPReloadScenario,
            reloadPendingSync: true
        )
        expect(pendingSafeReloadResult.connected == 0, "mcpBridgePendingReloadDoesNotReconnectConnectedServers")
        expect(pendingSafeReloadResult.reloadPerformed, "mcpBridgePerformsPendingSafeReload")
        expect(pendingSafeReloadResult.reloadCount == 1, "mcpBridgePendingSafeReloadSchedulesOnce")

        let noReconnectReloadResult = try runMCPBridgeRegressionScenario(Self.noReconnectMCPReloadScenario)
        expect(!noReconnectReloadResult.reloadPerformed, "mcpBridgeSkipsReloadWithoutReconnectOrPendingSync")
        expect(!noReconnectReloadResult.reloadDeferred, "mcpBridgeDoesNotDeferReloadWithoutReconnectOrPendingSync")
        expect(noReconnectReloadResult.reloadCount == 0, "mcpBridgeNoReconnectHasNoReloadCall")

        let appControllerSource = try sourceFile(named: "Sources/KotobaLibreApp/AppController.swift")
        expect(
            appControllerSource.contains("scheduleDeferredMCPAutoReconnect(reason: \"window-show-settled\")"),
            "mcpSchedulerWindowShowSchedulesSettledRetry"
        )
        expect(
            appControllerSource.contains("scheduleDeferredMCPAutoReconnect(reason: \"page-load-settled\")"),
            "mcpSchedulerPageLoadSchedulesSettledRetry"
        )
        expect(
            appControllerSource.contains("try? await Task.sleep(nanoseconds: 5_000_000_000)"),
            "mcpSchedulerUsesShortSettledRetryDelay"
        )
        expect(
            appControllerSource.contains("mcpAutoReconnectDeferredTask?.cancel()"),
            "mcpSchedulerCancelsStaleSettledRetry"
        )
        expect(
            appControllerSource.contains("shouldRunMCPAutoReconnectAfterCurrentRun = true"),
            "mcpSchedulerQueuesSkippedSettledRetry"
        )
        expect(
            appControllerSource.contains("runMCPAutoReconnect(reason: \"pending-after-active\")"),
            "mcpSchedulerRunsQueuedRetryAfterActiveRun"
        )
        expect(
            appControllerSource.contains("NSWorkspace.didWakeNotification"),
            "mcpSchedulerObservesWorkspaceWake"
        )
        expect(
            appControllerSource.contains("NSWorkspace.screensDidWakeNotification"),
            "mcpSchedulerObservesScreensWake"
        )
        expect(
            appControllerSource.contains("NSWorkspace.sessionDidBecomeActiveNotification"),
            "mcpSchedulerObservesSessionActive"
        )
        expect(
            appControllerSource.contains("scheduleMCPAutoReconnectCatchUp(reason: \"app-active\")"),
            "mcpSchedulerSchedulesCatchUpWhenAppBecomesActive"
        )
        expect(
            appControllerSource.contains("mcpAutoReconnectCatchUpTask?.cancel()"),
            "mcpSchedulerDebouncesCatchUpRuns"
        )
        expect(
            appControllerSource.contains("guard runtimeMode == .standard"),
            "mcpSchedulerKeepsSmokeRuntimeGuards"
        )
        expect(
            appControllerSource.contains("hasPendingMCPUIRefresh"),
            "mcpSchedulerTracksDeferredUIRefresh"
        )

        let normalizedSettings = KotobaLibreCore.normalizeSettings(
            AppSettings(
                instanceBaseUrl: "https://chat.example.com",
                globalShortcut: "commandorcontrol + option + v",
                voiceGlobalShortcut: "ctrl + shift + m",
                showAppWindowShortcut: "ctrl + option + k",
                autostartEnabled: false,
                restrictHostToInstanceHost: true,
                defaultPresetId: "preset-1",
                useRouteReloadForLauncherChats: false,
                debugLoggingEnabled: true,
                launcherOpacity: 0.95,
                appVisibilityMode: .dockAndMenuBar,
                backgroundResponseNotificationsEnabled: false,
                longResponseNotificationThresholdSeconds: 14,
                mcpAutoReconnectEnabled: false,
                mcpAutoReconnectIntervalMinutes: 45
            )
        )
        expect(normalizedSettings.globalShortcut == "CmdOrCtrl+Alt+KeyV", "settingsNormalizeShortcutAliases")
        expect(normalizedSettings.voiceGlobalShortcut == "Ctrl+Shift+KeyM", "settingsNormalizeVoiceShortcutAliases")
        expect(normalizedSettings.showAppWindowShortcut == "Ctrl+Alt+KeyK", "settingsNormalizeShowAppWindowShortcutAliases")
        expect(normalizedSettings.appVisibilityMode == .dockAndMenuBar, "settingsPreserveVisibilityMode")
        expect(normalizedSettings.debugLoggingEnabled, "settingsPreserveDebugLoggingFlag")
        expect(!normalizedSettings.backgroundResponseNotificationsEnabled, "settingsPreserveBackgroundResponseNotificationToggle")
        expect(normalizedSettings.longResponseNotificationThresholdSeconds == 14, "settingsPreserveLongResponseThreshold")
        expect(!normalizedSettings.mcpAutoReconnectEnabled, "settingsPreserveMCPAutoReconnectToggle")
        expect(normalizedSettings.mcpAutoReconnectIntervalMinutes == 45, "settingsPreserveMCPAutoReconnectInterval")
        expect(KotobaLibreCore.validateShortcutConfiguration(normalizedSettings).valid, "settingsAllowDistinctTextAndVoiceShortcuts")

        let normalizedNotificationThreshold = KotobaLibreCore.normalizeSettings(
            AppSettings(longResponseNotificationThresholdSeconds: 0)
        )
        expect(
            normalizedNotificationThreshold.longResponseNotificationThresholdSeconds == 1,
            "settingsClampLongResponseThresholdToMinimum"
        )
        let normalizedInvalidMCPReconnectInterval = KotobaLibreCore.normalizeSettings(
            AppSettings(mcpAutoReconnectIntervalMinutes: 0)
        )
        expect(
            normalizedInvalidMCPReconnectInterval.mcpAutoReconnectIntervalMinutes == AppSettings.defaultMCPAutoReconnectIntervalMinutes,
            "settingsDefaultInvalidMCPReconnectInterval"
        )
        let normalizedMinimumMCPReconnectInterval = KotobaLibreCore.normalizeSettings(
            AppSettings(mcpAutoReconnectIntervalMinutes: 1)
        )
        expect(normalizedMinimumMCPReconnectInterval.mcpAutoReconnectIntervalMinutes == 1, "settingsAllowMinimumMCPReconnectInterval")
        let normalizedHighMCPReconnectInterval = KotobaLibreCore.normalizeSettings(
            AppSettings(mcpAutoReconnectIntervalMinutes: 7_200)
        )
        expect(normalizedHighMCPReconnectInterval.mcpAutoReconnectIntervalMinutes == 240, "settingsClampMCPReconnectIntervalToMaximum")

        let conflictingShortcuts = AppSettings(
            instanceBaseUrl: "https://chat.example.com",
            globalShortcut: "CmdOrCtrl+Shift+Space",
            voiceGlobalShortcut: "commandorcontrol + shift + space"
        )
        expect(!KotobaLibreCore.validateShortcutConfiguration(conflictingShortcuts).valid, "settingsRejectMatchingTextAndVoiceShortcuts")

        let duplicateWindowShortcutSettings = AppSettings(
            instanceBaseUrl: "https://chat.example.com",
            globalShortcut: "CmdOrCtrl+Shift+Space",
            voiceGlobalShortcut: "Ctrl+Shift+KeyM",
            showAppWindowShortcut: "commandorcontrol + shift + space"
        )
        expect(!KotobaLibreCore.validateShortcutConfiguration(duplicateWindowShortcutSettings).valid, "settingsRejectMatchingAppWindowShortcut")

        let openURLParsed = try KotobaLibreCore.parseDeepLink("kotobalibre://open?url=https%3A%2F%2Fchat.example.com%2Fc%2F123")
        expect(openURLParsed == .openURL("https://chat.example.com/c/123"), "deepLinkOpenURLIsParsed")

        let presetParsed = try KotobaLibreCore.parseDeepLink("kotobalibre://preset/preset-1?query=hello%20world")
        expect(presetParsed == .openPreset(presetID: "preset-1", query: "hello world"), "deepLinkPresetIsParsed")

        let webOpenParsed = try KotobaLibreCore.parseDeepLink("https://chat.example.com/app/open?url=https%3A%2F%2Fchat.example.com%2Fc%2F123")
        expect(webOpenParsed == .openURL("https://chat.example.com/c/123"), "webDeepLinkOpenURLIsParsed")

        let mappedCustomSchemeURL = try KotobaLibreCore.mapCustomSchemeURLToInstanceURL(
            URL(string: "kotobalibre://auth/callback?code=123&state=abc")!,
            instanceBaseURL: "https://chat.example.com"
        )
        expect(mappedCustomSchemeURL?.absoluteString == "https://chat.example.com/auth/callback?code=123&state=abc", "customSchemeMapsToInstanceRelativeURL")

        let mappedCustomSchemeHostURL = try KotobaLibreCore.mapCustomSchemeURLToInstanceURL(
            URL(string: "kotobalibre://chat.example.com/auth/callback?code=123")!,
            instanceBaseURL: "https://ignored.example.com"
        )
        expect(mappedCustomSchemeHostURL?.absoluteString == "https://chat.example.com/auth/callback?code=123", "customSchemeHostMapsToHTTPSURL")

        let mappedCustomSchemeHostWithPortURL = try KotobaLibreCore.mapCustomSchemeURLToInstanceURL(
            URL(string: "kotobalibre://chat.example.com:3000/oauth/openid/callback?code=123")!,
            instanceBaseURL: "https://ignored.example.com"
        )
        expect(mappedCustomSchemeHostWithPortURL?.absoluteString == "https://chat.example.com:3000/oauth/openid/callback?code=123", "customSchemeHostWithPortMapsToHTTPSURL")

        expectThrows("deepLinkInvalidFails missing url") {
            _ = try KotobaLibreCore.parseDeepLink("kotobalibre://open")
        }
        expectThrows("deepLinkInvalidFails unsupported scheme") {
            _ = try KotobaLibreCore.parseDeepLink("ftp://example.com/app/open?url=https://chat.example.com")
        }

        let settings = settingsRestrictingHost()
        expect(try KotobaLibreCore.enforceDestination("https://chat.example.com/c/new", settings: settings).absoluteString == "https://chat.example.com/c/new", "hostRestrictionAllowsChatHost")
        expect(try KotobaLibreCore.matchesConfiguredInstanceHost(URL(string: "https://chat.example.com/c/new")!, settings: settings), "configuredInstanceHostMatchesChatHost")
        expect(!(try KotobaLibreCore.matchesConfiguredInstanceHost(URL(string: "https://example.com/c/new")!, settings: settings)), "configuredInstanceHostRejectsOtherHost")
        expect(try KotobaLibreCore.matchesConfiguredInstanceOrigin(URL(string: "https://chat.example.com:443/c/new")!, settings: settings), "configuredInstanceOriginAllowsDefaultHTTPSPort")
        let portScopedSettings = AppSettings(instanceBaseUrl: "https://localhost:3000")
        expect(try KotobaLibreCore.matchesConfiguredInstanceOrigin(URL(string: "https://localhost:3000/c/new")!, settings: portScopedSettings), "configuredInstanceOriginMatchesExplicitPort")
        expect(!(try KotobaLibreCore.matchesConfiguredInstanceOrigin(URL(string: "https://localhost:5173/c/new")!, settings: portScopedSettings)), "configuredInstanceOriginRejectsDifferentPort")
        expectThrows("hostRestrictionBlocksNonChatHost") {
            _ = try KotobaLibreCore.enforceDestination("https://example.com", settings: settings)
        }
        expectThrows("instanceURLRejectsSingleLabelHost") {
            _ = try KotobaLibreCore.parseInstanceBaseURL(AppSettings(instanceBaseUrl: "https://chat"))
        }
        expectThrows("instanceURLRejectsUnknownTopLevelDomain") {
            _ = try KotobaLibreCore.parseInstanceBaseURL(AppSettings(instanceBaseUrl: "https://chat.librechat"))
        }
        expect(try KotobaLibreCore.parseInstanceBaseURL(AppSettings(instanceBaseUrl: "https://chat.example.com"))?.absoluteString == "https://chat.example.com", "instanceURLAllowsPublicHost")
        expect(
            try KotobaLibreCore.parseInstanceBaseURL(AppSettings(instanceBaseUrl: "\u{FEFF}https://chat.example.com\u{200B}"))?.absoluteString == "https://chat.example.com",
            "instanceURLIgnoresInvisiblePasteCharacters"
        )
        expect(
            KotobaLibreCore.normalizeSettings(AppSettings(instanceBaseUrl: "\u{200B}https://chat.example.com")).instanceBaseUrl == "https://chat.example.com",
            "settingsNormalizeInvisibleURLPasteCharacters"
        )

        var unrestrictedSettings = settingsRestrictingHost()
        unrestrictedSettings.restrictHostToInstanceHost = false
        expect(try KotobaLibreCore.enforceDestination("https://example.com", settings: unrestrictedSettings).absoluteString == "https://example.com", "hostRestrictionCanBeDisabled")

        var missingInstanceSettings = settingsRestrictingHost()
        missingInstanceSettings.instanceBaseUrl = nil
        expect(!(try KotobaLibreCore.matchesConfiguredInstanceHost(URL(string: "https://chat.example.com/c/new")!, settings: missingInstanceSettings)), "configuredInstanceHostRequiresConfiguredInstance")
        expectThrows("hostRestrictionRequiresInstanceWhenEnabled") {
            _ = try KotobaLibreCore.enforceDestination("https://chat.example.com/c/new", settings: missingInstanceSettings)
        }

        expect(KotobaLibreCore.expandTemplate("https://chat.example.com/search?q={query}", query: "hello world") == "https://chat.example.com/search?q=hello+world", "templateQueryPlaceholderIsEncoded")
        expect(KotobaLibreCore.expandTemplate("https://chat.example.com/c/new?agent_id=agent_aLfpSjQmQKt9nhbFi7BIs", query: "hello world") == "https://chat.example.com/c/new?agent_id=agent_aLfpSjQmQKt9nhbFi7BIs&prompt=hello%20world&submit=true", "templateQueryIsAppendedAsPromptWithSubmitWhenMissingPlaceholder")
        expect(KotobaLibreCore.expandTemplate("https://chat.example.com/c/new/support-agent", query: "hello world") == "https://chat.example.com/c/new/support-agent?prompt=hello%20world&submit=true", "templateQueryKeepsPathBasedAgentRoute")

        let input = [
            Preset(id: "", name: "  Agent One  ", urlTemplate: " https://chat.example.com/c/new?agent_id=1 ", kind: .agent, createdAt: "", updatedAt: ""),
            Preset(id: "dup", name: "Agent Two", urlTemplate: "https://chat.example.com/c/new?agent_id=2", kind: .agent, createdAt: "unix-ms-1", updatedAt: ""),
            Preset(id: "dup", name: "Agent Three", urlTemplate: "https://chat.example.com/c/new?agent_id=3", kind: .agent, createdAt: "unix-ms-2", updatedAt: "unix-ms-3")
        ]
        let normalizedPresets = KotobaLibreCore.normalizeLoadedPresets(input, nowProvider: { "unix-ms-now" })
        expect(normalizedPresets.count == 3, "loadedPresets count")
        expect(!normalizedPresets[0].id.isEmpty, "loadedPresets generated id")
        expect(normalizedPresets[1].id == "dup", "loadedPresets preserves first duplicate")
        expect(normalizedPresets[2].id != "dup", "loadedPresets changes second duplicate")
        expect(normalizedPresets[0].name == "Agent One", "loadedPresets trims name")
        expect(normalizedPresets[0].urlTemplate == "1", "loadedPresets stores only the agent id")
        expect(normalizedPresets[1].updatedAt == "unix-ms-1", "loadedPresets backfill updatedAt")

        let existingPreset = Preset(
            id: "preset-1",
            name: "Support Agent",
            urlTemplate: "https://chat.example.com/c/new?agent_id=1",
            kind: .agent,
            createdAt: "unix-ms-old",
            updatedAt: "unix-ms-old"
        )
        let editedPreset = Preset(
            id: "preset-1",
            name: "Updated Support Agent",
            urlTemplate: "https://chat.example.com/c/new?agent_id=2",
            kind: .agent,
            createdAt: "unix-ms-ignored",
            updatedAt: "unix-ms-ignored"
        )
        let normalizedEditedPreset = KotobaLibreCore.normalizePreset(
            editedPreset,
            existing: existingPreset,
            now: "unix-ms-new"
        )
        expect(normalizedEditedPreset.createdAt == "unix-ms-old", "normalizePresetPreservesCreatedAtForExisting")
        expect(normalizedEditedPreset.updatedAt == "unix-ms-new", "normalizePresetRefreshesUpdatedAtForExisting")
        expect(normalizedEditedPreset.urlTemplate == "2", "normalizePresetStoresAgentIDsInsteadOfFullURLs")

        let mismatchedPreset = Preset(id: "id-1", name: "Support Agent", urlTemplate: "https://other.example.com/c/new?agent_id=1", kind: .link, createdAt: "unix-ms-1", updatedAt: "unix-ms-2")
        expect(KotobaLibreCore.validateImportCompatibility(mismatchedPreset, allowedHost: "chat.example.com", row: 1) != nil, "importValidationRejectsHostMismatch")

        let matchingPreset = Preset(id: "id-1", name: "Support Agent", urlTemplate: "https://chat.example.com/c/new?agent_id=1", kind: .link, createdAt: "unix-ms-1", updatedAt: "unix-ms-2")
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
        let agentDestination = try KotobaLibreCore.destinationString(
            for: Preset(id: "id-1", name: "Support Agent", urlTemplate: "agent_123", kind: .agent, createdAt: "unix-ms-1", updatedAt: "unix-ms-2"),
            instanceBaseURL: "https://chat.example.com",
            query: "hello"
        )
        expect(agentDestination == "https://chat.example.com/c/new?agent_id=agent_123&prompt=hello&submit=true", "agentDestinationBuildsFromStoredAgentID")

        let encodedSettings = try JSONEncoder().encode(AppSettings())
        let decodedSettings = try JSONDecoder().decode(AppSettings.self, from: encodedSettings)
        expect(decodedSettings == AppSettings(), "settingsRoundTrip")
        expect(decodedSettings.openExternalAuthenticationLinksInNewWindow, "settingsDefaultExternalAuthWindowEnabled")
        expect(decodedSettings.backgroundResponseNotificationsEnabled, "settingsDefaultBackgroundResponseNotificationsEnabled")
        expect(
            decodedSettings.longResponseNotificationThresholdSeconds == AppSettings.defaultLongResponseNotificationThresholdSeconds,
            "settingsDefaultLongResponseThreshold"
        )
        expect(decodedSettings.mcpAutoReconnectEnabled, "settingsDefaultMCPAutoReconnectEnabled")
        expect(
            decodedSettings.mcpAutoReconnectIntervalMinutes == AppSettings.defaultMCPAutoReconnectIntervalMinutes,
            "settingsDefaultMCPAutoReconnectInterval"
        )

        let legacySettingsJSON = """
        {"instanceBaseUrl":"https://chat.example.com","globalShortcut":"CmdOrCtrl+Shift+Space","autostartEnabled":false,"restrictHostToInstanceHost":true,"defaultPresetId":"preset-1","useRouteReloadForLauncherChats":false,"launcherOpacity":0.95}
        """.data(using: .utf8)!
        let decodedLegacySettings = try JSONDecoder().decode(AppSettings.self, from: legacySettingsJSON)
        expect(decodedLegacySettings.appVisibilityMode == .dockOnly, "settingsDecodeLegacyVisibilityDefault")
        expect(!decodedLegacySettings.debugLoggingEnabled, "settingsDecodeLegacyDebugLoggingDefault")
        expect(decodedLegacySettings.voiceGlobalShortcut == AppSettings.defaultVoiceShortcut, "settingsDecodeLegacyVoiceShortcutDefault")
        expect(decodedLegacySettings.showAppWindowShortcut == AppSettings.defaultShowAppWindowShortcut, "settingsDecodeLegacyShowAppWindowShortcutDefault")
        expect(decodedLegacySettings.openExternalAuthenticationLinksInNewWindow, "settingsDecodeLegacyExternalAuthWindowDefault")
        expect(decodedLegacySettings.backgroundResponseNotificationsEnabled, "settingsDecodeLegacyBackgroundResponseNotificationsDefault")
        expect(
            decodedLegacySettings.longResponseNotificationThresholdSeconds == AppSettings.defaultLongResponseNotificationThresholdSeconds,
            "settingsDecodeLegacyLongResponseThresholdDefault"
        )
        expect(decodedLegacySettings.mcpAutoReconnectEnabled, "settingsDecodeLegacyMCPAutoReconnectDefault")
        expect(
            decodedLegacySettings.mcpAutoReconnectIntervalMinutes == AppSettings.defaultMCPAutoReconnectIntervalMinutes,
            "settingsDecodeLegacyMCPAutoReconnectIntervalDefault"
        )
        expect(AppResources.iconPNGURL?.lastPathComponent == "AppIcon.png", "appResourcesResolvePNG")
        expect(AppResources.iconICNSURL?.lastPathComponent == "AppIcon.icns", "appResourcesResolveICNS")

        let roundTripPreset = Preset(id: "id-1", name: "Support Agent", urlTemplate: "https://chat.example.com/c/new?agent=support", kind: .agent, createdAt: "unix-ms-1", updatedAt: "unix-ms-2")
        let encodedPreset = try JSONEncoder().encode(roundTripPreset)
        let decodedPreset = try JSONDecoder().decode(Preset.self, from: encodedPreset)
        expect(decodedPreset == roundTripPreset, "presetRoundTrip")

        let tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = try AppDataStore(baseDirectory: tempDirectory)
        try store.saveSettings(settingsRestrictingHost())
        try store.savePresets([Preset(id: "preset-1", name: "Support", urlTemplate: "https://chat.example.com/c/new?agent_id=1", kind: .agent, createdAt: "unix-ms-1", updatedAt: "unix-ms-1")])
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
            print("KotobaLibreSelfTest: all checks passed (\(assertionCount) assertions)")
            return
        }

        // CI and scripts read stderr on failure, so the report is printed there.
        fputs("KotobaLibreSelfTest failures:\n", stderr)
        for failure in failures {
            fputs("- \(failure)\n", stderr)
        }
        Foundation.exit(1)
    }

    private static func runMCPBridgeRegressionScenario(
        _ scenarioScript: String,
        reloadAfterReconnect: Bool = true,
        reloadPendingSync: Bool = false
    ) throws -> MCPBridgeRunResult {
        let bridgeScript = try extractMCPAutoReconnectScript()
        guard let context = JSContext() else {
            throw SelfTestFailure("could not create JavaScript context")
        }

        var exceptionMessage: String?
        context.exceptionHandler = { _, exception in
            exceptionMessage = exception?.toString() ?? "unknown JavaScript exception"
        }

        let harness = """
        \(mcpBridgeJavaScriptPreamble)
        \(scenarioScript)
        var __finished = false;
        var __resultJSON = null;
        var __error = null;
        (async function() {
          try {
            var __result = await (async function(reloadAfterReconnect, reloadPendingSync) {
        \(bridgeScript)
            })(\(reloadAfterReconnect ? "true" : "false"), \(reloadPendingSync ? "true" : "false"));
            __result.reloadCount = globalThis.__reloadCount || 0;
            __resultJSON = JSON.stringify(__result);
          } catch (error) {
            __error = String(error && error.stack ? error.stack : error);
          } finally {
            __finished = true;
          }
        })();
        """

        context.evaluateScript(harness)
        if let exceptionMessage {
            throw SelfTestFailure(exceptionMessage)
        }

        let deadline = Date().addingTimeInterval(1)
        while context.objectForKeyedSubscript("__finished")?.toBool() != true && Date() < deadline {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01))
        }

        guard context.objectForKeyedSubscript("__finished")?.toBool() == true else {
            throw SelfTestFailure("MCP bridge scenario timed out")
        }

        if let errorValue = context.objectForKeyedSubscript("__error"),
           !errorValue.isNull,
           !errorValue.isUndefined,
           let message = errorValue.toString(),
           !message.isEmpty {
            throw SelfTestFailure(message)
        }

        guard let resultJSON = context.objectForKeyedSubscript("__resultJSON")?.toString() else {
            throw SelfTestFailure("MCP bridge scenario returned no JSON result")
        }

        return try JSONDecoder().decode(MCPBridgeRunResult.self, from: Data(resultJSON.utf8))
    }

    private static func extractMCPAutoReconnectScript() throws -> String {
        let source = try sourceFile(named: "Sources/KotobaLibreApp/WebViewControllers.swift")
        let marker = "private static let mcpAutoReconnectScript = \"\"\""
        let terminator = "\n    \"\"\""
        guard let start = source.range(of: marker)?.upperBound else {
            throw SelfTestFailure("MCP reconnect bridge script marker was not found")
        }
        guard let end = source.range(of: terminator, range: start..<source.endIndex)?.lowerBound else {
            throw SelfTestFailure("MCP reconnect bridge script terminator was not found")
        }

        return String(source[start..<end])
    }

    private static func sourceFile(named relativePath: String) throws -> String {
        let url = try repositoryRoot().appendingPathComponent(relativePath)
        return try String(contentsOf: url, encoding: .utf8)
    }

    private static func repositoryRoot() throws -> URL {
        let fileManager = FileManager.default
        var directory = URL(fileURLWithPath: fileManager.currentDirectoryPath, isDirectory: true)
        for _ in 0..<8 {
            let packageURL = directory.appendingPathComponent("Package.swift")
            let appSourceURL = directory.appendingPathComponent("Sources/KotobaLibreApp/WebViewControllers.swift")
            if fileManager.fileExists(atPath: packageURL.path), fileManager.fileExists(atPath: appSourceURL.path) {
                return directory
            }
            directory.deleteLastPathComponent()
        }

        throw SelfTestFailure("could not find repository root from \(fileManager.currentDirectoryPath)")
    }

    private static let mcpBridgeJavaScriptPreamble = #"""
    if (typeof globalThis === "undefined") {
      this.globalThis = this;
    }
    function AbortController() {
      this.signal = {};
      this.abort = function() {
        this.signal.aborted = true;
      };
    }
    function URL(input, base) {
      var value = String(input);
      if (base && value.indexOf("http://") !== 0 && value.indexOf("https://") !== 0) {
        var baseString = String(base);
        if (value.charAt(0) === "/") {
          var originMatch = baseString.match(/^(https?:\/\/[^\/]+)/);
          value = (originMatch ? originMatch[1] : baseString.replace(/\/$/, "")) + value;
        } else {
          value = baseString.replace(/\/?$/, "/") + value;
        }
      }
      this.href = value;
      var protocolMatch = value.match(/^([a-z]+:)/);
      this.protocol = protocolMatch ? protocolMatch[1] : "";
      var pathMatch = value.match(/^https?:\/\/[^\/]+([^?#]*)/);
      this.pathname = pathMatch ? (pathMatch[1] || "/") : (value.charAt(0) === "/" ? value : "/");
    }
    function __response(status, body) {
      return {
        ok: status >= 200 && status < 300,
        status: status,
        json: async function() {
          return body;
        },
      };
    }
    function __mockElement(config) {
      config = config || {};
      return {
        disabled: config.disabled === true,
        value: config.value || "",
        textContent: config.text || "",
        isContentEditable: config.contentEditable === true,
        parentElement: config.parent || null,
        getAttribute: function(name) {
          return name === "aria-label" ? (config.label || null) : null;
        },
        matches: function(selector) {
          if (selector === "[disabled]") return this.disabled;
          if (
            selector.indexOf("textarea") !== -1 ||
            selector.indexOf("input") !== -1 ||
            selector.indexOf("contenteditable") !== -1 ||
            selector.indexOf("role='textbox'") !== -1 ||
            selector.indexOf('role="textbox"') !== -1
          ) {
            return config.editable === true || config.contentEditable === true;
          }
          return false;
        },
        closest: function() {
          return null;
        },
        getBoundingClientRect: function() {
          return config.visible === false ? { width: 0, height: 0 } : { width: 80, height: 32 };
        },
        click: config.click || function() {},
      };
    }
    function __installBrowserMock(config) {
      config = config || {};
      globalThis.__reloadCount = 0;
      var textarea = __mockElement({
        editable: true,
        text: "",
        value: config.textareaValue || "",
        visible: config.textareaVisible !== false,
      });
      globalThis.window = {
        location: {
          protocol: "https:",
          origin: "https://chat.example.test",
          href: "https://chat.example.test/c/new",
          reload: config.reload || function() {
            globalThis.__reloadCount += 1;
          },
        },
        setTimeout: function(callback) {
          callback();
          return 1;
        },
        clearTimeout: function() {},
        getComputedStyle: function() {
          return { display: "block", visibility: "visible", opacity: "1", pointerEvents: "auto" };
        },
        dispatchEvent: function() {},
        open: config.open || function() {},
      };
      globalThis.document = {
        activeElement: config.activeElement || null,
        hasFocus: function() {
          return config.documentHasFocus === true;
        },
        querySelector: function() {
          return null;
        },
        querySelectorAll: function(selector) {
          if (selector === "textarea") {
            return config.textareaVisible === false ? [] : [textarea];
          }
          if (
            selector.indexOf("textarea") !== -1 ||
            selector.indexOf("input") !== -1 ||
            selector.indexOf("contenteditable") !== -1 ||
            selector.indexOf("role='textbox'") !== -1 ||
            selector.indexOf('role="textbox"') !== -1
          ) {
            if (config.editableElements) return config.editableElements;
            return config.textareaVisible === false ? [] : [textarea];
          }
          if (selector.indexOf('aria-label="Connect"') !== -1 || selector.indexOf('aria-label="Reconnect"') !== -1) {
            return config.controls ? config.controls() : [];
          }
          return [];
        },
      };
      globalThis.CustomEvent = function(type, init) {
        this.type = type;
        this.detail = init && init.detail;
      };
      globalThis.fetch = config.fetchImpl;
    }
    """#

    private static let sequentialMCPReconnectScenario = #"""
    var connectedA = false;
    var connectedB = false;
    var parentA = __mockElement({ text: "Server A Connect" });
    var parentB = __mockElement({ text: "Server B Reconnect" });
    var buttonA = __mockElement({
      label: "Connect",
      text: "Connect",
      parent: parentA,
      click: function() {
        connectedA = true;
      },
    });
    var buttonB = __mockElement({
      label: "Reconnect",
      text: "Reconnect",
      parent: parentB,
      click: function() {
        connectedB = true;
      },
    });
    __installBrowserMock({
      controls: function() {
        return connectedA ? (connectedB ? [] : [buttonB]) : [buttonA];
      },
      fetchImpl: async function(url) {
        if (url.endsWith("/api/mcp/connection/status")) {
          return __response(200, {
            connectionStatus: {
              a: { connectionState: connectedA ? "connected" : "disconnected" },
              b: { connectionState: connectedB ? "connected" : "error" },
            },
          });
        }
        if (url.indexOf("/reinitialize") !== -1) {
          throw new Error("API fallback should not run when sequential UI clicks reconnect both servers");
        }
        throw new Error("unexpected fetch " + url);
      },
    });
    """#

    private static let remainingMCPAPIFallbackScenario = #"""
    var clickedA = false;
    var postedB = false;
    __installBrowserMock({
      controls: function() {
        if (clickedA) return [];
        return [
          __mockElement({
            label: "Connect",
            text: "Connect",
            parent: __mockElement({ text: "Server A" }),
            click: function() {
              clickedA = true;
            },
          }),
        ];
      },
      fetchImpl: async function(url, options) {
        if (url.endsWith("/api/mcp/connection/status")) {
          return __response(200, {
            connectionStatus: {
              a: { connectionState: clickedA ? "connected" : "disconnected" },
              b: { connectionState: postedB ? "connected" : "disconnected" },
            },
          });
        }
        if (url.endsWith("/api/mcp/b/reinitialize")) {
          postedB = options && options.method === "POST";
          return __response(200, { success: true });
        }
        if (url.endsWith("/api/mcp/a/reinitialize")) {
          throw new Error("server a should be handled by UI");
        }
        throw new Error("unexpected fetch " + url);
      },
    });
    """#

    private static let connectingMCPAPIFallbackScenario = #"""
    var clicked = false;
    var statusRequestsAfterClick = 0;
    var posted = false;
    __installBrowserMock({
      controls: function() {
        if (clicked) return [];
        return [
          __mockElement({
            label: "Connect",
            text: "Connect",
            parent: __mockElement({ text: "Server A" }),
            click: function() {
              clicked = true;
            },
          }),
        ];
      },
      fetchImpl: async function(url, options) {
        if (url.endsWith("/api/mcp/connection/status")) {
          if (posted) {
            return __response(200, {
              connectionStatus: {
                a: { connectionState: "connected" },
              },
            });
          }
          if (clicked) {
            statusRequestsAfterClick += 1;
          }
          return __response(200, {
            connectionStatus: {
              a: {
                connectionState: clicked && statusRequestsAfterClick < 2
                  ? "connecting"
                  : "disconnected",
              },
            },
          });
        }
        if (url.endsWith("/api/mcp/a/reinitialize")) {
          posted = options && options.method === "POST";
          return __response(200, { success: true });
        }
        throw new Error("unexpected fetch " + url);
      },
    });
    """#

    private static let authRefreshMCPReconnectScenario = #"""
    var statusRequests = 0;
    var postHadBearer = false;
    __installBrowserMock({
      textareaVisible: false,
      fetchImpl: async function(url, options) {
        if (url.endsWith("/api/auth/refresh")) {
          return __response(200, { token: "fresh-token" });
        }
        if (url.endsWith("/api/mcp/connection/status")) {
          statusRequests += 1;
          if (statusRequests === 1) return __response(401, {});
          return __response(200, {
            connectionStatus: {
              test: { connectionState: statusRequests === 2 ? "disconnected" : "connected" },
            },
          });
        }
        if (url.endsWith("/api/mcp/test/reinitialize")) {
          postHadBearer = options && options.headers && options.headers.Authorization === "Bearer fresh-token";
          if (!postHadBearer) throw new Error("reinitialize did not use refreshed bearer token");
          return __response(200, { success: true });
        }
        throw new Error("unexpected fetch " + url);
      },
    });
    """#

    private static let reloadAllowedMCPReconnectScenario = #"""
    var posted = false;
    __installBrowserMock({
      textareaVisible: false,
      fetchImpl: async function(url, options) {
        if (url.endsWith("/api/mcp/connection/status")) {
          return __response(200, {
            connectionStatus: {
              test: { connectionState: posted ? "connected" : "disconnected" },
            },
          });
        }
        if (url.endsWith("/api/mcp/test/reinitialize")) {
          posted = options && options.method === "POST";
          return __response(200, { success: true });
        }
        throw new Error("unexpected fetch " + url);
      },
    });
    """#

    private static let focusedEditableBlocksMCPReloadScenario = #"""
    var posted = false;
    var focusedTextarea = __mockElement({ editable: true, value: "", visible: true });
    __installBrowserMock({
      activeElement: focusedTextarea,
      documentHasFocus: true,
      editableElements: [focusedTextarea],
      fetchImpl: async function(url, options) {
        if (url.endsWith("/api/mcp/connection/status")) {
          return __response(200, {
            connectionStatus: {
              test: { connectionState: posted ? "connected" : "disconnected" },
            },
          });
        }
        if (url.endsWith("/api/mcp/test/reinitialize")) {
          posted = options && options.method === "POST";
          return __response(200, { success: true });
        }
        throw new Error("unexpected fetch " + url);
      },
    });
    """#

    private static let draftBlocksMCPReloadScenario = #"""
    var posted = false;
    __installBrowserMock({
      textareaValue: "unfinished prompt",
      fetchImpl: async function(url, options) {
        if (url.endsWith("/api/mcp/connection/status")) {
          return __response(200, {
            connectionStatus: {
              test: { connectionState: posted ? "connected" : "disconnected" },
            },
          });
        }
        if (url.endsWith("/api/mcp/test/reinitialize")) {
          posted = options && options.method === "POST";
          return __response(200, { success: true });
        }
        throw new Error("unexpected fetch " + url);
      },
    });
    """#

    private static let noReconnectMCPReloadScenario = #"""
    __installBrowserMock({
      textareaVisible: false,
      fetchImpl: async function(url) {
        if (url.endsWith("/api/mcp/connection/status")) {
          return __response(200, {
            connectionStatus: {
              test: { connectionState: "connected" },
            },
          });
        }
        if (url.indexOf("/reinitialize") !== -1) {
          throw new Error("API fallback should not run for connected servers");
        }
        throw new Error("unexpected fetch " + url);
      },
    });
    """#
}

private struct MCPBridgeRunResult: Decodable {
    let uiClicked: Int
    let reinitialized: Int
    let connected: Int
    let reloadPerformed: Bool
    let reloadDeferred: Bool
    let reloadCount: Int
    let errors: [String]
}

private struct SelfTestFailure: LocalizedError {
    let message: String

    init(_ message: String) {
        self.message = message
    }

    var errorDescription: String? {
        message
    }
}
