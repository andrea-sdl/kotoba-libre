import AppKit
import Foundation
import KotobaLibreCore

@MainActor
final class AppSmokeTestRunner {
    private let appController: AppController
    private let temporaryDirectory: URL

    init(appController: AppController, temporaryDirectory: URL) {
        self.appController = appController
        self.temporaryDirectory = temporaryDirectory
    }

    func start() {
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
        try await assertInitialOnboardingState()
        let preset = try await completeOnboardingAndCreatePreset()
        try await assertSettingsAndLauncherWindows()
        try await assertPresetLaunch(presetID: preset.id)
        try await assertResetConfiguration()
    }

    private func assertInitialOnboardingState() async throws {
        await settle()

        let snapshot = appController.smokeTestSnapshot()
        try expect(snapshot.mainWindowVisible, "main window should be visible on launch")
        try expect(snapshot.settingsWindowVisible == false, "settings window should start hidden")
        try expect(snapshot.launcherWindowVisible == false, "launcher window should start hidden")
        try expect(snapshot.mainContentKind == .onboarding, "clean launch should show onboarding")
        try expect(snapshot.hasInstanceBaseURL == false, "clean launch should not have an instance URL")
    }

    private func completeOnboardingAndCreatePreset() async throws -> Preset {
        try appController.completeOnboarding(
            instanceBaseURL: "https://chat.example.com",
            shortcut: AppSettings.defaultShortcut
        )
        await settle()

        let postOnboardingSnapshot = appController.smokeTestSnapshot()
        try expect(postOnboardingSnapshot.mainContentKind == .web, "completing onboarding should show the web container")
        try expect(postOnboardingSnapshot.hasInstanceBaseURL, "instance URL should be saved after onboarding")

        var preset = appController.makeEmptyPreset()
        preset.name = "Smoke Test Agent"
        preset.urlTemplate = "https://chat.example.com/c/new?agent_id=smoke-test-agent"
        preset.tags = ["smoke", "test"]

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
    }

    private func assertPresetLaunch(presetID: String) async throws {
        try appController.openPreset(id: presetID, query: "Smoke test prompt", preferMainWindow: true)
        await settle()

        let snapshot = appController.smokeTestSnapshot()
        try expect(snapshot.mainWindowVisible, "main window should remain visible after launching a preset")
        try expect(snapshot.launcherWindowVisible == false, "launcher should hide after launching a preset")
        try expect(snapshot.mainContentKind == .web, "preset launch should keep the web container active")
    }

    private func assertResetConfiguration() async throws {
        try appController.resetConfiguration()
        await settle()

        let snapshot = appController.smokeTestSnapshot()
        try expect(snapshot.mainWindowVisible, "main window should stay visible after reset")
        try expect(snapshot.presetCount == 0, "reset should remove saved presets")
        try expect(snapshot.hasInstanceBaseURL == false, "reset should clear the saved instance URL")
        try expect(snapshot.mainContentKind == .onboarding, "reset should return the app to onboarding")
    }

    private func settle() async {
        try? await Task.sleep(nanoseconds: 250_000_000)
        await Task.yield()
    }

    private func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        guard condition() else {
            throw SmokeTestFailure(message: message)
        }
    }

    private func finish(exitCode: Int32, message: String) {
        print(message)
        appController.applicationWillTerminate()
        try? FileManager.default.removeItem(at: temporaryDirectory)
        fflush(stdout)
        fflush(stderr)
        Foundation.exit(exitCode)
    }
}

private struct SmokeTestFailure: LocalizedError {
    let message: String

    var errorDescription: String? {
        message
    }
}
