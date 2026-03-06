import AppKit
import Combine
import Foundation
import ServiceManagement
import SwiftUI
import ToroLibreCore

@MainActor
final class AppController: NSObject, ObservableObject {
    @Published private(set) var settings: AppSettings = AppSettings()
    @Published private(set) var presets: [Preset] = []
    @Published var shortcutDraft: String = AppSettings.defaultShortcut
    @Published var isRecordingShortcut = false

    let accentColorNames = ["blue", "purple", "pink", "red", "orange", "green", "teal", "graphite"]

    private let store: AppDataStore
    private let shortcutRegistrar = GlobalShortcutRegistrar()
    private lazy var mainWindowController = MainWindowController(appController: self)
    private lazy var settingsWindowController = SettingsWindowController(appController: self)
    private lazy var launcherWindowController = LauncherWindowController(appController: self)
    private var secondaryWindows: [UUID: SecondaryWebWindowController] = [:]
    private var windowCleanupDelegates: [UUID: WindowCleanupDelegate] = [:]

    override init() {
        self.store = try! AppDataStore()
        super.init()
    }

    func start() {
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
            settings.defaultPresetId = nil
            try? persistSettings()
        }

        shortcutDraft = settings.globalShortcut
        setupApplicationMenu()
        applyAppIcon()
        try? syncAutostart(enabled: settings.autostartEnabled)
        try? registerGlobalShortcut()
        refreshMainWindowContent(openHomeIfNeeded: settings.instanceBaseUrl != nil)
        launcherWindowController.prepare()

        if settings.instanceBaseUrl == nil {
            showSettingsWindow()
        }
    }

    func restoreOrOpenPrimaryWindow() {
        if let window = mainWindowController.window, window.isVisible {
            mainWindowController.showAndFocus()
            return
        }

        if settings.instanceBaseUrl == nil {
            settingsWindowController.showAndFocus()
            return
        }

        mainWindowController.showAndFocus()
    }

    func handleOpen(urls: [URL]) {
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
        NSWorkspace.shared.open(url)
    }

    func makeEmptyPreset(kind: PresetKind = .agent) -> Preset {
        let marker = ToroLibreCore.nowMarker()
        return Preset(
            id: "",
            name: "",
            urlTemplate: suggestPresetTemplate(instanceBaseURL: settings.instanceBaseUrl),
            kind: kind,
            tags: [],
            createdAt: marker,
            updatedAt: marker
        )
    }

    func sortedPresets() -> [Preset] {
        presets.sorted { lhs, rhs in
            lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    func saveSettings(_ nextSettings: AppSettings) throws {
        let previous = settings
        var normalized = ToroLibreCore.normalizeSettings(nextSettings)
        normalized = try ToroLibreCore.normalizeInstanceBaseURL(normalized)

        settings = normalized
        shortcutDraft = normalized.globalShortcut
        try persistSettings()
        try registerGlobalShortcut()
        try syncAutostart(enabled: normalized.autostartEnabled)
        refreshMainWindowContent(openHomeIfNeeded: previous.instanceBaseUrl != normalized.instanceBaseUrl)
    }

    func setDefaultPreset(id: String?) throws {
        var updated = settings
        updated.defaultPresetId = id
        try saveSettings(updated)
    }

    func saveShortcutDraft() throws {
        var updated = settings
        updated.globalShortcut = shortcutDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        try saveSettings(updated)
    }

    func resetShortcutDraft() {
        shortcutDraft = AppSettings.defaultShortcut
        isRecordingShortcut = false
    }

    func beginShortcutRecording() {
        isRecordingShortcut = true
    }

    func stopShortcutRecording() {
        isRecordingShortcut = false
    }

    func captureShortcut(_ shortcut: String) {
        shortcutDraft = shortcut
        isRecordingShortcut = false
    }

    func upsertPreset(_ preset: Preset) throws -> Preset {
        let existing = presets.first(where: { $0.id == preset.id })
        let normalized = ToroLibreCore.normalizePreset(preset, existing: existing)

        guard !normalized.name.isEmpty else {
            throw ToroLibreError.invalidDestination("Preset name cannot be empty")
        }

        let validation = ToroLibreCore.validateURLTemplate(normalized.urlTemplate)
        guard validation.valid else {
            throw ToroLibreError.invalidDestination(validation.reason ?? "Invalid URL template")
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
            throw ToroLibreError.invalidDestination("Preset not found")
        }

        if settings.defaultPresetId == id {
            var updated = settings
            updated.defaultPresetId = nil
            try saveSettings(updated)
        } else {
            try persistPresets()
        }
    }

    func importPresetsFromPanel() throws -> ImportPresetsResult {
        guard let allowedHost = try ToroLibreCore.settingsInstanceHost(settings) else {
            throw ToroLibreError.invalidDestination("Set your Toro Libre instance URL in Settings before importing agents")
        }

        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false

        guard panel.runModal() == .OK, let url = panel.url else {
            return ImportPresetsResult(imported: 0, skipped: 0, errors: [])
        }

        let data = try Data(contentsOf: url)
        let candidates = try ToroLibreCore.importCandidates(from: data)
        var existingIDs = Set(presets.map(\.id))
        var imported = 0
        var errors: [String] = []

        for (index, preset) in candidates.enumerated() {
            var normalized = ToroLibreCore.normalizePreset(preset)
            let row = index + 1
            if let error = ToroLibreCore.validateImportCompatibility(normalized, allowedHost: allowedHost, row: row) {
                errors.append(error)
                continue
            }

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

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "torolibre-agents-\(Self.exportStamp()).json"

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

    func openPreset(id: String, query: String?) throws {
        guard let preset = presets.first(where: { $0.id == id }) else {
            throw ToroLibreError.invalidDestination("Preset '\(id)' not found")
        }

        let destination = ToroLibreCore.expandTemplate(preset.urlTemplate, query: query)
        try openURLString(destination)
    }

    func openURLString(_ destination: String) throws {
        let target = try ToroLibreCore.enforceDestination(destination, settings: settings)
        try openResolvedURL(target)
    }

    func handleShortcutKeyEvent(_ event: NSEvent) -> Bool {
        guard isRecordingShortcut else {
            return false
        }

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
        switch try ToroLibreCore.parseDeepLink(rawURL) {
        case let .openURL(destination):
            try openURLString(destination)
        case let .openPreset(presetID, query):
            try openPreset(id: presetID, query: query)
        case .openSettings:
            showSettingsWindow()
        }
    }

    private func openResolvedURL(_ url: URL) throws {
        let instanceHost = try ToroLibreCore.settingsInstanceHost(settings)
        if let instanceHost, let host = url.host, host.caseInsensitiveCompare(instanceHost) != .orderedSame {
            openExternally(url)
            return
        }

        if settings.openInNewWindow {
            let identifier = UUID()
            let controller = SecondaryWebWindowController(
                url: url,
                settings: settings,
                instanceHost: instanceHost,
                onExternalOpen: { [weak self] target in
                    self?.openExternally(target)
                }
            )
            secondaryWindows[identifier] = controller
            controller.showWindow(nil)
            controller.window?.isReleasedWhenClosed = false
            let cleanupDelegate = WindowCleanupDelegate { [weak self] in
                self?.secondaryWindows.removeValue(forKey: identifier)
                self?.windowCleanupDelegates.removeValue(forKey: identifier)
            }
            windowCleanupDelegates[identifier] = cleanupDelegate
            controller.window?.delegate = cleanupDelegate
        } else {
            mainWindowController.open(url: url, settings: settings, instanceHost: instanceHost)
        }

        hideLauncherWindow()
    }

    private func persistSettings() throws {
        try store.saveSettings(settings)
    }

    private func persistPresets() throws {
        try store.savePresets(presets)
    }

    private func registerGlobalShortcut() throws {
        try shortcutRegistrar.register(shortcut: settings.globalShortcut) { [weak self] in
            Task { @MainActor in
                self?.toggleLauncherWindow()
            }
        }
    }

    private func refreshMainWindowContent(openHomeIfNeeded: Bool) {
        if settings.instanceBaseUrl == nil {
            mainWindowController.showFirstRun()
            return
        }

        mainWindowController.showWebView(settings: settings)
        if openHomeIfNeeded {
            mainWindowController.navigateToHome(settings: settings)
        }
    }

    private func setupApplicationMenu() {
        let mainMenu = NSMenu()
        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Settings...", action: #selector(openSettingsFromMenu), keyEquivalent: ",")
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

    private func applyAppIcon() {
        if let iconURL = AppResources.iconPNGURL, let image = NSImage(contentsOf: iconURL) {
            image.isTemplate = false
            NSApp.applicationIconImage = image
        }
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

        return URL(string: "c/new", relativeTo: baseURL)?.absoluteURL.absoluteString ?? instanceBaseURL
    }

    private static func exportStamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }
}

final class WindowCleanupDelegate: NSObject, NSWindowDelegate {
    private let onClose: () -> Void

    init(onClose: @escaping () -> Void) {
        self.onClose = onClose
    }

    func windowWillClose(_ notification: Notification) {
        onClose()
    }
}
