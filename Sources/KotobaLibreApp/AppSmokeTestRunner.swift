import AppKit
import Foundation
import KotobaLibreCore

// This executable drives a small end-to-end smoke test inside the real app process.
@MainActor
final class AppSmokeTestRunner {
    private let appController: AppController
    private let temporaryDirectory: URL

    init(appController: AppController, temporaryDirectory: URL) {
        self.appController = appController
        self.temporaryDirectory = temporaryDirectory
    }

    func start() {
        // The app launches first, then the smoke test continues asynchronously on the main actor.
        Task { @MainActor in
            do {
                try await run()
                finish(exitCode: 0, message: "KotobaLibre GUI smoke test: passed")
            } catch {
                finish(exitCode: 1, message: "KotobaLibre GUI smoke test: failed - \(error.localizedDescription)")
            }
        }
    }

    private func run() async throws {
        // Keep the scenario linear so failures map to a clear user-facing flow.
        try await assertInitialOnboardingState()
        try await assertDetectedLinkCandidateMapsToLinkPreset()
        let preset = try await completeOnboardingAndCreatePreset()
        try await assertSettingsAndLauncherWindows()
        try await assertLauncherSelectionResetsToDefault(presetID: preset.id)
        try await assertTogglePrimaryWindowRefocusesVisibleWindow()
        try await assertPresetLaunch(presetID: preset.id)
        try await assertResetConfiguration()
    }

    private func assertDetectedLinkCandidateMapsToLinkPreset() async throws {
        let candidate = WebAddPresetCandidate(
            sourceURL: URL(string: "https://chat.example.com/c/new?endpoint=anthropic&model=claude-opus-4-6")!,
            kind: .link,
            presetValue: "https://chat.example.com/c/new?endpoint=anthropic&model=claude-opus-4-6",
            presetName: "Anthropic Claude Opus 4.6"
        )

        let preset = appController.makePreset(from: candidate)
        try expect(preset.kind == .link, "detected chat links should save as link presets")
        try expect(preset.urlTemplate == candidate.presetValue, "link presets should keep the detected URL")
        try expect(preset.name == candidate.presetName, "link presets should reuse the detected display name")
    }

    private func assertInitialOnboardingState() async throws {
        await settle()

        let snapshot = appController.smokeTestSnapshot()
        try expect(snapshot.mainWindowVisible, "main window should be visible on launch")
        try expect(snapshot.settingsWindowVisible == false, "settings window should start hidden")
        try expect(snapshot.launcherWindowVisible == false, "launcher window should start hidden")
        try expect(snapshot.mainContentKind == .onboarding, "clean launch should show onboarding")
        try expect(snapshot.hasInstanceBaseURL == false, "clean launch should not have an instance URL")
        try expect(snapshot.globalShortcutsEnabled == false, "clean launch should keep global shortcuts disabled until onboarding finishes")
    }

    private func completeOnboardingAndCreatePreset() async throws -> Preset {
        try appController.completeOnboarding(
            instanceBaseURL: "https://chat.example.com",
            launcherShortcut: AppSettings.defaultShortcut,
            voiceShortcut: AppSettings.defaultVoiceShortcut,
            showAppWindowShortcut: AppSettings.defaultShowAppWindowShortcut
        )
        await settle()

        let postOnboardingSnapshot = appController.smokeTestSnapshot()
        try expect(postOnboardingSnapshot.mainContentKind == .web, "completing onboarding should show the web container")
        try expect(postOnboardingSnapshot.hasInstanceBaseURL, "instance URL should be saved after onboarding")
        try expect(postOnboardingSnapshot.globalShortcutsEnabled, "completing onboarding should enable global shortcuts")
        try expect(postOnboardingSnapshot.mainWindowWidth >= 900, "post-onboarding window should reset to the larger default width")
        try expect(postOnboardingSnapshot.mainWindowHeight >= 660, "post-onboarding window should reset to the larger default height")

        var preset = appController.makeEmptyPreset()
        preset.name = "Smoke Test Agent"
        preset.urlTemplate = "https://chat.example.com/c/new?agent_id=smoke-test-agent"

        let savedPreset = try appController.upsertPreset(preset)
        try appController.setDefaultPreset(id: savedPreset.id)
        await settle()

        let presetSnapshot = appController.smokeTestSnapshot()
        try expect(presetSnapshot.presetCount == 1, "smoke test should save one preset")
        try expect(presetSnapshot.defaultPresetID == savedPreset.id, "saved preset should become the default")
        return savedPreset
    }

    private func assertSettingsAndLauncherWindows() async throws {
        appController.showSettingsWindow()
        await settle()

        var snapshot = appController.smokeTestSnapshot()
        try expect(snapshot.settingsWindowVisible, "settings window should open")

        appController.showLauncherWindow()
        await settle()

        snapshot = appController.smokeTestSnapshot()
        try expect(snapshot.launcherWindowVisible, "launcher window should open")
        try expect(snapshot.launcherWindowKey, "launcher window should become key when opened")
        try expect(snapshot.mainWindowKey == false, "main window should not stay key while the launcher is open")
    }

    private func assertPresetLaunch(presetID: String) async throws {
        try appController.openPreset(id: presetID, query: "Smoke test prompt", preferMainWindow: true)
        await settle()

        let snapshot = appController.smokeTestSnapshot()
        try expect(snapshot.mainWindowVisible, "main window should remain visible after launching a preset")
        try expect(snapshot.launcherWindowVisible == false, "launcher should hide after launching a preset")
        try expect(snapshot.mainContentKind == .web, "preset launch should keep the web container active")
    }

    private func assertLauncherSelectionResetsToDefault(presetID: String) async throws {
        var alternatePreset = appController.makeEmptyPreset()
        alternatePreset.name = "Smoke Test Alternate Agent"
        alternatePreset.urlTemplate = "https://chat.example.com/c/new?agent_id=smoke-test-alternate-agent"

        let savedAlternatePreset = try appController.upsertPreset(alternatePreset)
        await settle()
        try expect(savedAlternatePreset.id != presetID, "alternate preset should differ from the default preset")

        appController.showLauncherWindow()
        await settle()

        var snapshot = appController.smokeTestSnapshot()
        try expect(snapshot.launcherSelectedPresetID == presetID, "launcher should start with the default preset selected")

        appController.selectLauncherPreset(id: savedAlternatePreset.id)
        await settle()

        snapshot = appController.smokeTestSnapshot()
        try expect(snapshot.launcherSelectedPresetID == savedAlternatePreset.id, "launcher selection should change when a different preset is chosen")

        appController.hideLauncherWindow()
        await settle()

        appController.showLauncherWindow()
        await settle()

        snapshot = appController.smokeTestSnapshot()
        try expect(snapshot.launcherSelectedPresetID == presetID, "reopening the launcher should restore the default preset selection")

        appController.selectLauncherPreset(id: savedAlternatePreset.id)
        await settle()

        appController.showVoiceLauncherWindow()
        await settle()

        snapshot = appController.smokeTestSnapshot()
        try expect(snapshot.launcherSelectedPresetID == presetID, "switching launcher modes should reset selection to the default preset")
    }

    private func assertTogglePrimaryWindowRefocusesVisibleWindow() async throws {
        appController.showSettingsWindow()
        await settle()

        var snapshot = appController.smokeTestSnapshot()
        try expect(snapshot.mainWindowVisible, "main window should still be visible before toggling focus")
        try expect(snapshot.mainWindowKey == false, "main window should not be key while settings are focused")

        appController.togglePrimaryWindow()
        await settle()

        snapshot = appController.smokeTestSnapshot()
        try expect(snapshot.mainWindowVisible, "toggle should keep the visible main window open when it is unfocused")
        try expect(snapshot.mainWindowKey, "toggle should bring the visible main window to the foreground when it is unfocused")
    }

    private func assertResetConfiguration() async throws {
        try appController.resetConfiguration()
        await settle()

        let snapshot = appController.smokeTestSnapshot()
        try expect(snapshot.mainWindowVisible, "main window should stay visible after reset")
        try expect(snapshot.presetCount == 0, "reset should remove saved presets")
        try expect(snapshot.hasInstanceBaseURL == false, "reset should clear the saved instance URL")
        try expect(snapshot.mainContentKind == .onboarding, "reset should return the app to onboarding")
        try expect(snapshot.globalShortcutsEnabled == false, "reset should disable global shortcuts again")
    }

    private func settle() async {
        // AppKit and WebKit update asynchronously, so each assertion waits for the UI to settle.
        try? await Task.sleep(nanoseconds: 250_000_000)
        await Task.yield()
    }

    private func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        guard condition() else {
            throw SmokeTestFailure(message: message)
        }
    }

    private func finish(exitCode: Int32, message: String) {
        // Always clean up the temporary directory, even on failure.
        print(message)
        appController.applicationWillTerminate()
        try? FileManager.default.removeItem(at: temporaryDirectory)
        fflush(stdout)
        fflush(stderr)
        Foundation.exit(exitCode)
    }
}

// LocalizedError gives the failure message a clean surface for the smoke-test summary.
private struct SmokeTestFailure: LocalizedError {
    let message: String

    var errorDescription: String? {
        message
    }
}
