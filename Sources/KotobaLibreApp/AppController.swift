import AppKit
import Foundation
import ServiceManagement
import SwiftUI
import KotobaLibreCore

// WebAddAgentCandidate captures the agent page state needed to create a local saved agent.
struct WebAddAgentCandidate: Equatable {
    let sourceURL: URL
    let newChatURL: String
    let agentID: String
    let agentName: String
}

// AppController is the main coordinator for the desktop app.
// It owns persisted state, window controllers, global shortcuts, and app-level side effects.
@MainActor
final class AppController: NSObject, ObservableObject {
    enum RuntimeMode {
        case standard
        case smokeTest

        // Smoke tests skip system integrations so tests stay deterministic and permission-free.
        var shouldRegisterSystemIntegrations: Bool {
            self == .standard
        }

        var shouldOpenExternalURLs: Bool {
            self == .standard
        }
    }

    // These values are shown in the Shortcuts UI to explain what macOS actually accepted.
    struct ShortcutDiagnostics {
        let activeShortcut: String
        let backend: String
        let carbonRegistered: Bool
        let eventTapInstalled: Bool
        let accessibilityGranted: Bool
        let inputMonitoringGranted: Bool
        let lastCarbonStatusDescription: String
    }

    // Saving settings can remove incompatible presets when host restriction changes.
    // This preview lets the UI explain the cleanup before it happens.
    struct SettingsChangePreview {
        let normalizedSettings: AppSettings
        let incompatiblePresets: [Preset]
    }

    // The save result tells the UI if presets were removed as a side effect.
    struct SettingsSaveResult {
        let removedPresets: [Preset]
    }

    // Smoke tests read this snapshot instead of reaching into window objects directly.
    struct SmokeTestSnapshot {
        let hasInstanceBaseURL: Bool
        let presetCount: Int
        let defaultPresetID: String?
        let mainWindowVisible: Bool
        let settingsWindowVisible: Bool
        let launcherWindowVisible: Bool
        let mainContentKind: MainWindowController.ContentKind
    }

    // Published state here drives all SwiftUI settings and onboarding views.
    @Published private(set) var settings: AppSettings = AppSettings()
    @Published private(set) var presets: [Preset] = []
    @Published private(set) var shortcutRegistrationIssue: String?
    @Published private(set) var shortcutDiagnostics = ShortcutDiagnostics(
        activeShortcut: AppSettings.defaultShortcut,
        backend: "Unavailable",
        carbonRegistered: false,
        eventTapInstalled: false,
        accessibilityGranted: false,
        inputMonitoringGranted: false,
        lastCarbonStatusDescription: "n/a"
    )
    @Published var shortcutDraft: String = AppSettings.defaultShortcut
    @Published var isRecordingShortcut = false

    private let store: AppDataStore
    private let runtimeMode: RuntimeMode
    private let shortcutRegistrar = GlobalShortcutRegistrar()
    private var statusItem: NSStatusItem?
    private lazy var mainWindowController = MainWindowController(appController: self, store: store)
    private lazy var settingsWindowController = SettingsWindowController(appController: self)
    private lazy var launcherWindowController = LauncherWindowController(appController: self)

    init(store: AppDataStore? = nil, runtimeMode: RuntimeMode = .standard) {
        self.store = try! (store ?? AppDataStore())
        self.runtimeMode = runtimeMode
        super.init()
    }

    func start() {
        // Startup is defensive. A bad file should reset to safe defaults instead of aborting launch.
        do {
            settings = try store.loadSettings()
        } catch {
            settings = AppSettings()
        }

        do {
            presets = try store.loadPresets()
        } catch {
            presets = []
        }

        if settings.defaultPresetId != nil, !presets.contains(where: { $0.id == settings.defaultPresetId }) {
            // Clear stale default references so the launcher never points at a missing preset.
            settings.defaultPresetId = nil
            try? persistSettings()
        }

        shortcutDraft = settings.globalShortcut
        setupApplicationMenu()
        applyAppIcon()
        applyAppVisibilityMode(settings.appVisibilityMode)
        if runtimeMode.shouldRegisterSystemIntegrations {
            try? syncAutostart(enabled: settings.autostartEnabled)
            registerGlobalShortcutIfPossible(promptForPermission: false)
        } else {
            refreshShortcutDiagnostics()
        }
        refreshMainWindowContent(openHomeIfNeeded: settings.instanceBaseUrl != nil)
        launcherWindowController.prepare()
        mainWindowController.showAndFocus()
    }

    func restoreOrOpenPrimaryWindow() {
        // The primary window is either the onboarding flow or the embedded LibreChat window.
        if let window = mainWindowController.window, window.isVisible {
            mainWindowController.showAndFocus()
            return
        }

        if settings.instanceBaseUrl == nil {
            refreshMainWindowContent(openHomeIfNeeded: false)
            mainWindowController.showAndFocus()
            return
        }

        refreshMainWindowContent(openHomeIfNeeded: false)
        mainWindowController.showAndFocus()
    }

    func handleOpen(urls: [URL]) {
        // Each URL is handled independently so one bad deep link does not block the rest.
        for url in urls {
            do {
                try handleDeepLink(url.absoluteString)
            } catch {
                NSSound.beep()
            }
        }
    }

    func showSettingsWindow() {
        settingsWindowController.showAndFocus()
    }

    func showLauncherWindow() {
        launcherWindowController.showAndFocus()
    }

    func hideLauncherWindow() {
        launcherWindowController.hide()
    }

    func toggleLauncherWindow() {
        if launcherWindowController.isVisible {
            launcherWindowController.hide()
        } else {
            showLauncherWindow()
        }
    }

    func openExternally(_ url: URL) {
        guard runtimeMode.shouldOpenExternalURLs else {
            return
        }

        NSWorkspace.shared.open(url)
    }

    func applicationWillTerminate() {
        mainWindowController.persistStateForTermination()
    }

    func makeEmptyPreset(kind: PresetKind = .agent) -> Preset {
        // New presets start with a suggested template so the editor is not completely blank.
        let marker = KotobaLibreCore.nowMarker()
        return Preset(
            id: "",
            name: "",
            urlTemplate: suggestPresetTemplate(instanceBaseURL: settings.instanceBaseUrl),
            kind: kind,
            createdAt: marker,
            updatedAt: marker
        )
    }

    func makePreset(from candidate: WebAddAgentCandidate) -> Preset {
        var preset = makeEmptyPreset(kind: .agent)
        let trimmedName = candidate.agentName.trimmingCharacters(in: .whitespacesAndNewlines)
        preset.name = trimmedName.isEmpty ? candidate.agentID : trimmedName
        preset.urlTemplate = candidate.newChatURL.trimmingCharacters(in: .whitespacesAndNewlines)
        return preset
    }

    func sortedPresets() -> [Preset] {
        presets.sorted { lhs, rhs in
            lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    func previewSettingsChange(_ nextSettings: AppSettings) throws -> SettingsChangePreview {
        let previousHost = try KotobaLibreCore.settingsInstanceHost(settings)
        var normalized = KotobaLibreCore.normalizeSettings(nextSettings)
        normalized = try KotobaLibreCore.normalizeInstanceBaseURL(normalized)
        let nextHost = try KotobaLibreCore.settingsInstanceHost(normalized)
        // Revalidation only matters when host pinning is on and the effective host changed.
        let shouldRevalidatePresets =
            normalized.restrictHostToInstanceHost &&
            (
                settings.restrictHostToInstanceHost != normalized.restrictHostToInstanceHost ||
                !hostsMatch(previousHost, nextHost)
            )
        let incompatiblePresets = shouldRevalidatePresets
            ? try KotobaLibreCore.incompatiblePresets(presets, settings: normalized)
            : []
        return SettingsChangePreview(
            normalizedSettings: normalized,
            incompatiblePresets: incompatiblePresets
        )
    }

    func saveSettings(_ nextSettings: AppSettings) throws -> SettingsSaveResult {
        let previousSettings = settings
        let previousPresets = presets
        let preview = try previewSettingsChange(nextSettings)
        var normalized = preview.normalizedSettings
        let removedPresetIDs = Set(preview.incompatiblePresets.map(\.id))
        if !removedPresetIDs.isEmpty {
            // Incompatible presets are removed before save so storage and UI stay in sync.
            presets.removeAll { removedPresetIDs.contains($0.id) }
            if let defaultPresetID = normalized.defaultPresetId, removedPresetIDs.contains(defaultPresetID) {
                normalized.defaultPresetId = nil
            }
        }
        settings = normalized
        shortcutDraft = normalized.globalShortcut
        do {
            try persistSettings()
            if !removedPresetIDs.isEmpty {
                try persistPresets()
            }
            if runtimeMode.shouldRegisterSystemIntegrations {
                try syncAutostart(enabled: normalized.autostartEnabled)
            }
            applyAppVisibilityMode(normalized.appVisibilityMode)
        } catch {
            restoreTransientState(settings: previousSettings, presets: previousPresets)
            if runtimeMode.shouldRegisterSystemIntegrations {
                registerGlobalShortcutIfPossible(promptForPermission: false)
            } else {
                refreshShortcutDiagnostics()
            }
            throw error
        }

        // Re-register after a successful save so the latest shortcut and visibility settings take effect.
        if runtimeMode.shouldRegisterSystemIntegrations {
            registerGlobalShortcutIfPossible(promptForPermission: true)
        } else {
            refreshShortcutDiagnostics()
        }
        refreshMainWindowContent(openHomeIfNeeded: previousSettings.instanceBaseUrl != normalized.instanceBaseUrl)
        if normalized.instanceBaseUrl != nil {
            mainWindowController.showAndFocus()
        }

        return SettingsSaveResult(removedPresets: preview.incompatiblePresets)
    }

    func completeOnboarding(instanceBaseURL: String, shortcut: String) throws {
        var updated = settings
        updated.instanceBaseUrl = instanceBaseURL
        updated.globalShortcut = shortcut

        _ = try saveSettings(updated)
        settingsWindowController.hide()
        mainWindowController.showAndFocus()
    }

    func resetConfiguration() throws {
        hideLauncherWindow()
        try store.resetConfiguration()

        // Resetting returns the app to the same state as a fresh install.
        settings = AppSettings()
        presets = []
        shortcutDraft = AppSettings.defaultShortcut
        isRecordingShortcut = false
        settingsWindowController.hide()

        do {
            if runtimeMode.shouldRegisterSystemIntegrations {
                try syncAutostart(enabled: false)
            }
        } catch {
            if runtimeMode.shouldRegisterSystemIntegrations {
                registerGlobalShortcutIfPossible(promptForPermission: false)
            } else {
                refreshShortcutDiagnostics()
            }
            refreshMainWindowContent(openHomeIfNeeded: false)
            mainWindowController.resetToDefaultSize()
            mainWindowController.showAndFocus()
            throw error
        }

        applyAppVisibilityMode(settings.appVisibilityMode)
        if runtimeMode.shouldRegisterSystemIntegrations {
            registerGlobalShortcutIfPossible(promptForPermission: false)
        } else {
            refreshShortcutDiagnostics()
        }
        refreshMainWindowContent(openHomeIfNeeded: false)
        mainWindowController.resetToDefaultSize()
        mainWindowController.showAndFocus()
    }

    func setDefaultPreset(id: String?) throws {
        var updated = settings
        updated.defaultPresetId = id
        _ = try saveSettings(updated)
    }

    func saveShortcutDraft() throws {
        var updated = settings
        updated.globalShortcut = shortcutDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        _ = try saveSettings(updated)
    }

    func resetShortcutDraft() {
        shortcutDraft = AppSettings.defaultShortcut
        isRecordingShortcut = false
    }

    func discardShortcutDraftChanges() {
        shortcutDraft = settings.globalShortcut
        if isRecordingShortcut {
            stopShortcutRecording()
        }
    }

    func beginShortcutRecording() {
        suspendGlobalShortcut()
        isRecordingShortcut = true
    }

    func stopShortcutRecording() {
        isRecordingShortcut = false
        resumeSavedShortcutRegistration(promptForPermission: false)
    }

    func captureShortcut(_ shortcut: String) {
        shortcutDraft = shortcut
        isRecordingShortcut = false
        resumeSavedShortcutRegistration(promptForPermission: false)
    }

    func upsertPreset(_ preset: Preset) throws -> Preset {
        let existing = presets.first(where: { $0.id == preset.id })
        let normalized = KotobaLibreCore.normalizePreset(preset, existing: existing)

        guard !normalized.name.isEmpty else {
            throw KotobaLibreError.invalidDestination("Preset name cannot be empty")
        }

        let validation = KotobaLibreCore.validateURLTemplate(normalized.urlTemplate)
        guard validation.valid else {
            throw KotobaLibreError.invalidDestination(validation.reason ?? "Invalid URL template")
        }

        if
            settings.restrictHostToInstanceHost,
            let allowedHost = try KotobaLibreCore.settingsInstanceHost(settings),
            let issue = KotobaLibreCore.validatePresetCompatibility(normalized, allowedHost: allowedHost)
        {
            // Presets are blocked here before they ever reach storage.
            throw KotobaLibreError.invalidDestination("Agent '\(normalized.name)' \(issue)")
        }

        if let index = presets.firstIndex(where: { $0.id == normalized.id }) {
            presets[index] = normalized
        } else {
            presets.append(normalized)
        }

        try persistPresets()
        return normalized
    }

    func deletePreset(id: String) throws {
        let originalCount = presets.count
        presets.removeAll { $0.id == id }
        guard presets.count != originalCount else {
            throw KotobaLibreError.invalidDestination("Preset not found")
        }

        if settings.defaultPresetId == id {
            var updated = settings
            updated.defaultPresetId = nil
            _ = try saveSettings(updated)
        } else {
            try persistPresets()
        }
    }

    func importPresetsFromPanel() throws -> ImportPresetsResult {
        guard let allowedHost = try KotobaLibreCore.settingsInstanceHost(settings) else {
            throw KotobaLibreError.invalidDestination("Set your Kotoba Libre instance URL in Settings before importing agents")
        }

        // Import uses a native file picker because this is a macOS desktop flow.
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false

        guard panel.runModal() == .OK, let url = panel.url else {
            return ImportPresetsResult(imported: 0, skipped: 0, errors: [])
        }

        let data = try Data(contentsOf: url)
        let candidates = try KotobaLibreCore.importCandidates(from: data)
        var existingIDs = Set(presets.map(\.id))
        var imported = 0
        var errors: [String] = []

        for (index, preset) in candidates.enumerated() {
            var normalized = KotobaLibreCore.normalizePreset(preset)
            let row = index + 1
            if let error = KotobaLibreCore.validateImportCompatibility(normalized, allowedHost: allowedHost, row: row) {
                errors.append(error)
                continue
            }

            // Imported IDs must be unique inside the local preset list.
            if normalized.id.isEmpty || existingIDs.contains(normalized.id) {
                normalized.id = UUID().uuidString
            }

            existingIDs.insert(normalized.id)
            presets.append(normalized)
            imported += 1
        }

        if imported > 0 {
            try persistPresets()
        }

        return ImportPresetsResult(imported: imported, skipped: errors.count, errors: errors)
    }

    func exportPresetsFromPanel() throws -> Int {
        guard !presets.isEmpty else {
            return 0
        }

        // Export keeps the current host in the payload so another install can validate imports later.
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "kotobalibre-agents-\(Self.exportStamp()).json"

        guard panel.runModal() == .OK, let url = panel.url else {
            return 0
        }

        let data = try store.exportPresets(settings: settings, presets: presets)
        try data.write(to: url, options: .atomic)
        return presets.count
    }

    func openDraftURL(_ urlString: String) throws {
        try openURLString(urlString)
    }

    func openPreset(id: String, query: String?, preferMainWindow: Bool = false) throws {
        guard let preset = presets.first(where: { $0.id == id }) else {
            throw KotobaLibreError.invalidDestination("Preset '\(id)' not found")
        }

        let destination = KotobaLibreCore.expandTemplate(preset.urlTemplate, query: query)
        try openURLString(destination, preferMainWindow: preferMainWindow)
    }

    func openURLString(_ destination: String, preferMainWindow: Bool = false) throws {
        let target = try KotobaLibreCore.enforceDestination(destination, settings: settings)
        try openResolvedURL(target, preferMainWindow: preferMainWindow)
    }

    func handleShortcutKeyEvent(_ event: NSEvent) -> Bool {
        guard isRecordingShortcut else {
            return false
        }

        // Esc exits recording mode without changing the saved shortcut.
        if event.keyCode == 53 {
            stopShortcutRecording()
            return true
        }

        guard let shortcut = GlobalShortcutRegistrar.shortcutString(from: event) else {
            return false
        }

        captureShortcut(shortcut)
        return true
    }

    private func handleDeepLink(_ rawURL: String) throws {
        // Core parsing returns a small action enum so app-side routing stays simple.
        switch try KotobaLibreCore.parseDeepLink(rawURL) {
        case let .openURL(destination):
            try openURLString(destination)
        case let .openPreset(presetID, query):
            try openPreset(id: presetID, query: query)
        case .openSettings:
            showSettingsWindow()
        }
    }

    private func openResolvedURL(_ url: URL, preferMainWindow: Bool = false) throws {
        let instanceHost = try KotobaLibreCore.settingsInstanceHost(settings)
        mainWindowController.open(
            url: url,
            settings: settings,
            instanceHost: instanceHost,
            forceEmbedAllHosts: preferMainWindow
        )

        hideLauncherWindow()
    }

    func smokeTestSnapshot() -> SmokeTestSnapshot {
        SmokeTestSnapshot(
            hasInstanceBaseURL: settings.instanceBaseUrl != nil,
            presetCount: presets.count,
            defaultPresetID: settings.defaultPresetId,
            mainWindowVisible: mainWindowController.window?.isVisible ?? false,
            settingsWindowVisible: settingsWindowController.isVisible,
            launcherWindowVisible: launcherWindowController.isVisible,
            mainContentKind: mainWindowController.contentKind
        )
    }

    private func persistSettings() throws {
        try store.saveSettings(settings)
    }

    private func persistPresets() throws {
        try store.savePresets(presets)
    }

    private func restoreTransientState(settings previousSettings: AppSettings, presets previousPresets: [Preset]) {
        settings = previousSettings
        presets = previousPresets
        shortcutDraft = previousSettings.globalShortcut
    }

    private func suspendGlobalShortcut() {
        // While recording, the current global shortcut is turned off to avoid self-trigger loops.
        shortcutRegistrar.unregisterCurrentShortcut()
        shortcutRegistrationIssue = nil
        refreshShortcutDiagnostics()
    }

    private func resumeSavedShortcutRegistration(promptForPermission: Bool) {
        guard !isRecordingShortcut else {
            return
        }

        registerGlobalShortcutIfPossible(promptForPermission: promptForPermission)
    }

    private func registerGlobalShortcut(promptForPermission: Bool) throws {
        try shortcutRegistrar.register(shortcut: settings.globalShortcut, promptForPermission: promptForPermission) { [weak self] in
            Task { @MainActor in
                self?.toggleLauncherWindow()
            }
        }
        shortcutRegistrationIssue = nil
        refreshShortcutDiagnostics()
    }

    private func registerGlobalShortcutIfPossible(promptForPermission: Bool) {
        do {
            try registerGlobalShortcut(promptForPermission: promptForPermission)
        } catch {
            shortcutRegistrationIssue = error.localizedDescription
            refreshShortcutDiagnostics()
        }
    }

    private func refreshShortcutDiagnostics() {
        // The UI shows both permission state and the active backend to help debug macOS shortcut issues.
        let runtime = shortcutRegistrar.runtimeStatus()
        let activeShortcut = runtime.activeShortcut ?? settings.globalShortcut
        let carbonStatus = runtime.lastCarbonStatus.map { "\($0)" } ?? "n/a"
        shortcutDiagnostics = ShortcutDiagnostics(
            activeShortcut: activeShortcut,
            backend: runtime.backend,
            carbonRegistered: runtime.carbonRegistered,
            eventTapInstalled: runtime.eventTapInstalled,
            accessibilityGranted: runtime.accessibilityGranted,
            inputMonitoringGranted: runtime.inputMonitoringGranted,
            lastCarbonStatusDescription: carbonStatus
        )
    }

    private func refreshMainWindowContent(openHomeIfNeeded: Bool) {
        if settings.instanceBaseUrl == nil {
            mainWindowController.showOnboarding()
            return
        }

        // Once an instance exists, the main window always hosts the web container.
        mainWindowController.showWebView(settings: settings)
        if openHomeIfNeeded {
            mainWindowController.navigateToHome(settings: settings)
        }
    }

    private func setupApplicationMenu() {
        let mainMenu = NSMenu()
        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()
        let settingsItem = appMenu.addItem(withTitle: "Settings...", action: #selector(openSettingsFromMenu), keyEquivalent: ",")
        settingsItem.target = self
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit \(appDisplayName)", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = editMenu
        mainMenu.addItem(editItem)

        let windowItem = NSMenuItem()
        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        windowItem.submenu = windowMenu
        mainMenu.addItem(windowItem)

        NSApp.mainMenu = mainMenu
    }

    @objc private func openSettingsFromMenu() {
        showSettingsWindow()
    }

    @objc private func showMainWindowFromStatusItem() {
        restoreOrOpenPrimaryWindow()
    }

    private func applyAppVisibilityMode(_ mode: AppVisibilityMode) {
        if mode.showsMenuBarItem {
            installStatusItemIfNeeded()
        } else {
            removeStatusItem()
        }

        let targetPolicy: NSApplication.ActivationPolicy = mode.showsDockIcon ? .regular : .accessory
        guard NSApp.activationPolicy() != targetPolicy else {
            return
        }

        // Activation policy controls whether the app appears in the Dock or behaves like a menu bar utility.
        _ = NSApp.setActivationPolicy(targetPolicy)
        if mode.showsDockIcon {
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    private func applyAppIcon() {
        if let iconURL = AppResources.iconPNGURL, let image = NSImage(contentsOf: iconURL) {
            image.isTemplate = false
            NSApp.applicationIconImage = image
        }
    }

    private func installStatusItemIfNeeded() {
        guard statusItem == nil else {
            return
        }

        // The status item is only created in modes that expose a menu bar affordance.
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = statusItemImage()
            button.imagePosition = .imageOnly
            button.toolTip = appDisplayName
        }

        let menu = NSMenu()
        let showWindowItem = menu.addItem(withTitle: "Show LibreChat Window", action: #selector(showMainWindowFromStatusItem), keyEquivalent: "")
        showWindowItem.target = self
        let settingsItem = menu.addItem(withTitle: "Settings…", action: #selector(openSettingsFromMenu), keyEquivalent: "")
        settingsItem.target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit \(appDisplayName)", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = menu
        self.statusItem = statusItem
    }

    private func removeStatusItem() {
        guard let statusItem else {
            return
        }

        NSStatusBar.system.removeStatusItem(statusItem)
        self.statusItem = nil
    }

    private func statusItemImage() -> NSImage? {
        guard let image = NSImage(
            systemSymbolName: "bubble.left.and.bubble.right.fill",
            accessibilityDescription: appDisplayName
        ) else {
            return nil
        }

        image.isTemplate = true
        return image
    }

    private func syncAutostart(enabled: Bool) throws {
        if #available(macOS 13.0, *) {
            let service = SMAppService.mainApp
            if enabled {
                try service.register()
            } else if service.status == .enabled {
                try service.unregister()
            }
        }
    }

    private func suggestPresetTemplate(instanceBaseURL: String?) -> String {
        guard let instanceBaseURL, let baseURL = URL(string: instanceBaseURL.hasSuffix("/") ? instanceBaseURL : "\(instanceBaseURL)/") else {
            return "https://"
        }

        // The default template points at LibreChat's new-chat route relative to the configured instance.
        return URL(string: "c/new", relativeTo: baseURL)?.absoluteURL.absoluteString ?? instanceBaseURL
    }

    private static func exportStamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }

    private func hostsMatch(_ lhs: String?, _ rhs: String?) -> Bool {
        switch (lhs, rhs) {
        case let (lhs?, rhs?):
            return lhs.caseInsensitiveCompare(rhs) == .orderedSame
        case (nil, nil):
            return true
        default:
            return false
        }
    }
}
