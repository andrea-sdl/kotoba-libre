import AppKit
import SwiftUI
import KotobaLibreCore

private enum OnboardingStep: Int, CaseIterable {
    case instance
    case shortcut

    var title: String {
        switch self {
        case .instance:
            return "LibreChat Instance"
        case .shortcut:
            return "Launcher Shortcut"
        }
    }
}

private enum OnboardingField: Hashable {
    case instanceBaseURL
}

struct OnboardingFlowView: View {
    @ObservedObject var appController: AppController
    @State private var currentStep: OnboardingStep = .instance
    @State private var instanceBaseURL = ""
    @State private var statusMessage = ""
    @State private var statusIsError = false
    @FocusState private var focusedField: OnboardingField?

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 12) {
                    AppLogoView()
                    Text("Set up Kotoba Libre once, then launch LibreChat from anywhere.")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                HStack(spacing: 10) {
                    ForEach(OnboardingStep.allCases, id: \.rawValue) { step in
                        let symbolName = if currentStep.rawValue > step.rawValue {
                            "checkmark.circle.fill"
                        } else if currentStep == step {
                            "circle.fill"
                        } else {
                            "circle"
                        }

                        HStack(spacing: 8) {
                            Image(systemName: symbolName)
                            Text(step.title)
                        }
                        .font(.footnote.weight(.semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            Capsule(style: .continuous)
                                .fill(currentStep == step ? Color.accentColor.opacity(0.16) : Color.secondary.opacity(0.10))
                        )
                        .foregroundStyle(currentStep.rawValue >= step.rawValue ? Color.accentColor : .secondary)
                    }
                }
            }

            Group {
                switch currentStep {
                case .instance:
                    onboardingInstanceStep
                case .shortcut:
                    onboardingShortcutStep
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            if !statusMessage.isEmpty {
                Text(statusMessage)
                    .font(.footnote)
                    .foregroundStyle(statusIsError ? Color.red : .secondary)
            }

            HStack {
                if currentStep == .shortcut {
                    Button("Back") {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            currentStep = .instance
                        }
                    }
                }

                Spacer()

                Button(currentStep == .instance ? "Continue" : "Finish Setup") {
                    submitCurrentStep()
                }
                .buttonStyle(.borderedProminent)
                .disabled(currentStep == .instance && !instanceValidation.valid)
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            LinearGradient(
                colors: [Color(nsColor: .windowBackgroundColor), Color.accentColor.opacity(0.12)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .onAppear {
            instanceBaseURL = appController.settings.instanceBaseUrl ?? ""
            focusedField = .instanceBaseURL
        }
        .onChange(of: currentStep) { nextStep in
            focusedField = nextStep == .instance ? .instanceBaseURL : nil
        }
    }

    private var onboardingInstanceStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Where is your LibreChat instance running?")
                .font(.system(size: 28, weight: .bold, design: .rounded))
            Text("Enter the base URL for the hosted or self-hosted LibreChat instance you want Kotoba Libre to open.")
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 10) {
                TextField("https://chat.example.com", text: $instanceBaseURL)
                    .textFieldStyle(.roundedBorder)
                    .disableAutocorrection(true)
                    .focused($focusedField, equals: OnboardingField.instanceBaseURL)
                    .onSubmit {
                        if instanceValidation.valid {
                            submitCurrentStep()
                        }
                    }

                Text(instanceValidation.valid ? "Looks good. We’ll keep navigation pinned to this host by default." : (instanceValidation.reason ?? "Enter a valid HTTPS URL."))
                    .font(.footnote)
                    .foregroundStyle(instanceValidation.valid ? .secondary : Color.red)
            }

            Spacer()
        }
    }

    private var onboardingShortcutStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Choose the shortcut that opens the launcher.")
                .font(.system(size: 28, weight: .bold, design: .rounded))
            Text("Record a new shortcut now, or keep the default if it already works for you. You can change it later from Settings.")
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 14) {
                Text("Current Shortcut")
                    .font(.headline)

                ShortcutPreviewView(shortcut: appController.shortcutDraft)

                HStack {
                    Button(appController.isRecordingShortcut ? "Stop Recording" : "Record Shortcut") {
                        if appController.isRecordingShortcut {
                            appController.stopShortcutRecording()
                            setStatus("Shortcut capture canceled.", isError: false)
                        } else {
                            appController.beginShortcutRecording()
                            setStatus("Press the shortcut you want to use. Press Esc to cancel.", isError: false)
                        }
                    }

                    Button("Use Default") {
                        appController.resetShortcutDraft()
                        setStatus("Shortcut reset to \(AppSettings.defaultShortcut).", isError: false)
                    }
                }

                if appController.isRecordingShortcut {
                    Text("Listening for a shortcut...")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else if let registrationIssue = appController.shortcutRegistrationIssue {
                    Text(registrationIssue)
                        .font(.footnote)
                        .foregroundStyle(Color.red)
                }
            }

            Spacer()
        }
    }

    private var instanceValidation: ValidationResult {
        let candidate = instanceBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !candidate.isEmpty else {
            return ValidationResult(valid: false, reason: "Enter your LibreChat base URL to continue.")
        }

        do {
            _ = try KotobaLibreCore.parseInstanceBaseURL(AppSettings(instanceBaseUrl: candidate))
            return ValidationResult(valid: true)
        } catch {
            return ValidationResult(valid: false, reason: error.localizedDescription)
        }
    }

    private func submitCurrentStep() {
        switch currentStep {
        case .instance:
            guard instanceValidation.valid else {
                setStatus(instanceValidation.reason ?? "Enter a valid LibreChat URL.", isError: true)
                return
            }

            withAnimation(.easeInOut(duration: 0.18)) {
                currentStep = .shortcut
            }
            setStatus("", isError: false)
        case .shortcut:
            do {
                try appController.completeOnboarding(
                    instanceBaseURL: instanceBaseURL,
                    shortcut: appController.shortcutDraft
                )
                setStatus("", isError: false)
            } catch {
                setStatus(error.localizedDescription, isError: true)
            }
        }
    }

    private func setStatus(_ message: String, isError: Bool) {
        statusMessage = message
        statusIsError = isError
    }
}

private struct ShortcutPreviewView: View {
    let shortcut: String

    var body: some View {
        HStack(spacing: 8) {
            ForEach(shortcutDisplayParts(shortcut), id: \.self) { part in
                Text(part)
                    .font(.system(.body, design: .rounded).weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(Color.secondary.opacity(0.14)))
            }
        }
    }
}

private func shortcutDisplayParts(_ shortcut: String) -> [String] {
    shortcut.split(separator: "+").map { token in
        switch token {
        case "CmdOrCtrl":
            return "⌘"
        case "Ctrl":
            return "⌃"
        case "Alt":
            return "⌥"
        case "Shift":
            return "⇧"
        default:
            return token.replacingOccurrences(of: "Key", with: "").replacingOccurrences(of: "Digit", with: "")
        }
    }
}

private enum SettingsTab: Int, Hashable {
    case agents
    case settings
    case shortcuts
    case about
}

@MainActor
private final class SettingsNavigationGuard: ObservableObject {
    private var dirtyTabs = Set<SettingsTab>()
    private var discardHandlers: [SettingsTab: () -> Void] = [:]

    func registerDiscardHandler(for tab: SettingsTab, handler: @escaping () -> Void) {
        discardHandlers[tab] = handler
    }

    func setDirty(_ dirty: Bool, for tab: SettingsTab) {
        if dirty {
            dirtyTabs.insert(tab)
        } else {
            dirtyTabs.remove(tab)
        }
    }

    func isDirty(_ tab: SettingsTab) -> Bool {
        dirtyTabs.contains(tab)
    }

    func discardChanges(for tab: SettingsTab) {
        discardHandlers[tab]?()
        dirtyTabs.remove(tab)
    }
}

struct SettingsRootView: View {
    @ObservedObject var appController: AppController
    @StateObject private var navigationGuard = SettingsNavigationGuard()
    @State private var selectedTab: SettingsTab = .agents
    @State private var committedTab: SettingsTab = .agents
    @State private var pendingTab: SettingsTab?
    @State private var isShowingUnsavedChangesAlert = false
    @State private var isIgnoringNextSelectionChange = false

    var body: some View {
        TabView(selection: $selectedTab) {
            AgentManagerView(appController: appController)
                .environmentObject(navigationGuard)
                .tabItem { Text("Agents") }
                .tag(SettingsTab.agents)

            SettingsPanelView(appController: appController)
                .environmentObject(navigationGuard)
                .tabItem { Text("Settings") }
                .tag(SettingsTab.settings)

            ShortcutPanelView(appController: appController)
                .environmentObject(navigationGuard)
                .tabItem { Text("Shortcuts") }
                .tag(SettingsTab.shortcuts)

            AboutPanelView(openSettings: appController.showSettingsWindow)
                .tabItem { Text("About") }
                .tag(SettingsTab.about)
        }
        .padding(20)
        .frame(minWidth: 980, minHeight: 500)
        .onChange(of: selectedTab) { nextTab in
            guard !isIgnoringNextSelectionChange else {
                isIgnoringNextSelectionChange = false
                return
            }

            guard nextTab != committedTab else {
                return
            }

            if navigationGuard.isDirty(committedTab) {
                pendingTab = nextTab
                isIgnoringNextSelectionChange = true
                selectedTab = committedTab
                isShowingUnsavedChangesAlert = true
                return
            }

            committedTab = nextTab
        }
        .alert("Discard unsaved changes?", isPresented: $isShowingUnsavedChangesAlert) {
            Button("Discard Changes", role: .destructive) {
                navigationGuard.discardChanges(for: committedTab)
                guard let pendingTab else {
                    return
                }

                committedTab = pendingTab
                isIgnoringNextSelectionChange = true
                selectedTab = pendingTab
                self.pendingTab = nil
            }
            Button("Stay Here", role: .cancel) {
                pendingTab = nil
            }
        } message: {
            Text("Save or discard the current page before switching to another settings section.")
        }
    }
}

struct AgentManagerView: View {
    @ObservedObject var appController: AppController
    @EnvironmentObject private var navigationGuard: SettingsNavigationGuard
    @State private var selectedPresetID: String?
    @State private var draft = Preset(id: "", name: "", urlTemplate: "https://", kind: .agent, tags: [], createdAt: "", updatedAt: "")
    @State private var statusMessage = ""
    @State private var statusIsError = false
    @State private var didLoadInitialDraft = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Agents")
                        .font(.largeTitle.bold())
                    Text("Manage and configure your Kotoba Libre agents. Star sets default.")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Export JSON") { exportPresets() }
                Button("Import JSON") { importPresets() }
                Button("+ Add Agent") { resetDraft() }
            }

            HSplitView {
                List(selection: $selectedPresetID) {
                    ForEach(appController.sortedPresets()) { preset in
                        HStack {
                            Button(appController.settings.defaultPresetId == preset.id ? "★" : "☆") {
                                toggleDefault(for: preset)
                            }
                            .buttonStyle(.plain)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(preset.name)
                                    .font(.headline)
                                Text(preset.urlTemplate)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                        .tag(preset.id)
                    }
                }
                .frame(minWidth: 320)
                .onChange(of: selectedPresetID) { newValue in
                    guard let newValue, let preset = appController.presets.first(where: { $0.id == newValue }) else {
                        return
                    }
                    draft = preset
                }

                Form {
                    TextField("Name", text: $draft.name)
                    Picker("Kind", selection: $draft.kind) {
                        ForEach(PresetKind.allCases, id: \.self) { kind in
                            Text(kind.rawValue.capitalized).tag(kind)
                        }
                    }
                    TextField("Configured URL", text: $draft.urlTemplate)
                    TextField("Tags", text: Binding(
                        get: { draft.tags.joined(separator: ", ") },
                        set: { draft.tags = $0.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) } }
                    ))

                    let validation = KotobaLibreCore.validateURLTemplate(draft.urlTemplate)
                    Text(validation.valid ? "Template looks valid." : (validation.reason ?? "Invalid URL template."))
                        .font(.footnote)
                        .foregroundStyle(validation.valid ? .secondary : Color.red)

                    HStack {
                        Button("Save Agent") { savePreset() }
                            .buttonStyle(.borderedProminent)
                        Button("Open URL") { openDraftURL() }
                        Button("Clear") { resetDraft() }
                        if !draft.id.isEmpty {
                            Button("Delete", role: .destructive) { deletePreset() }
                        }
                    }
                }
                .formStyle(.grouped)
                .frame(minWidth: 420)
            }

            if !statusMessage.isEmpty {
                Text(statusMessage)
                    .foregroundStyle(statusIsError ? Color.red : .secondary)
            }
        }
        .onAppear {
            navigationGuard.registerDiscardHandler(for: .agents, handler: discardChanges)
            guard !didLoadInitialDraft else {
                updateDirtyState()
                return
            }

            didLoadInitialDraft = true
            resetDraft()
        }
        .onChange(of: selectedPresetID) { _ in
            updateDirtyState()
        }
        .onChange(of: draftSnapshot) { _ in
            updateDirtyState()
        }
        .onChange(of: appController.settings.instanceBaseUrl) { _ in
            updateDirtyState()
        }
    }

    private func resetDraft() {
        selectedPresetID = nil
        draft = appController.makeEmptyPreset()
        setStatus("Creating new agent.", isError: false)
        updateDirtyState()
    }

    private func savePreset() {
        guard appController.settings.instanceBaseUrl != nil else {
            setStatus("Set instance URL first.", isError: true)
            return
        }

        do {
            draft = try appController.upsertPreset(draft)
            selectedPresetID = draft.id
            setStatus("Saved agent: \(draft.name)", isError: false)
        } catch {
            setStatus(error.localizedDescription, isError: true)
        }
    }

    private func deletePreset() {
        do {
            try appController.deletePreset(id: draft.id)
            resetDraft()
            setStatus("Deleted agent.", isError: false)
        } catch {
            setStatus(error.localizedDescription, isError: true)
        }
    }

    private func openDraftURL() {
        do {
            try appController.openDraftURL(draft.urlTemplate)
            setStatus("Opened URL.", isError: false)
        } catch {
            setStatus(error.localizedDescription, isError: true)
        }
    }

    private func importPresets() {
        do {
            let result = try appController.importPresetsFromPanel()
            if result.imported == 0, result.skipped == 0 {
                return
            }
            let preview = result.errors.prefix(3).joined(separator: " ")
            let summary = "Imported \(result.imported), skipped \(result.skipped)."
            setStatus(preview.isEmpty ? summary : "\(summary) \(preview)", isError: !preview.isEmpty)
        } catch {
            setStatus("Import failed: \(error.localizedDescription)", isError: true)
        }
    }

    private func exportPresets() {
        do {
            let count = try appController.exportPresetsFromPanel()
            if count > 0 {
                setStatus("Exported \(count) agents.", isError: false)
            }
        } catch {
            setStatus("Export failed: \(error.localizedDescription)", isError: true)
        }
    }

    private func toggleDefault(for preset: Preset) {
        do {
            let nextID = appController.settings.defaultPresetId == preset.id ? nil : preset.id
            try appController.setDefaultPreset(id: nextID)
            setStatus(nextID == nil ? "Default cleared." : "Default set to \(preset.name).", isError: false)
        } catch {
            setStatus(error.localizedDescription, isError: true)
        }
    }

    private func setStatus(_ message: String, isError: Bool) {
        statusMessage = message
        statusIsError = isError
    }

    private var draftSnapshot: PresetDraftState {
        PresetDraftState(preset: draft)
    }

    private var baselineSnapshot: PresetDraftState {
        if let selectedPresetID, let preset = appController.presets.first(where: { $0.id == selectedPresetID }) {
            return PresetDraftState(preset: preset)
        }
        return PresetDraftState(preset: appController.makeEmptyPreset())
    }

    private func discardChanges() {
        if let selectedPresetID, let preset = appController.presets.first(where: { $0.id == selectedPresetID }) {
            draft = preset
        } else {
            draft = appController.makeEmptyPreset()
        }
        updateDirtyState()
    }

    private func updateDirtyState() {
        navigationGuard.setDirty(draftSnapshot != baselineSnapshot, for: .agents)
    }
}

private struct PresetDraftState: Equatable {
    let name: String
    let urlTemplate: String
    let kind: PresetKind
    let tags: [String]

    init(preset: Preset) {
        self.name = preset.name.trimmingCharacters(in: .whitespacesAndNewlines)
        self.urlTemplate = preset.urlTemplate.trimmingCharacters(in: .whitespacesAndNewlines)
        self.kind = preset.kind
        self.tags = KotobaLibreCore.normalizeTags(preset.tags)
    }
}

struct SettingsPanelView: View {
    @ObservedObject var appController: AppController
    @EnvironmentObject private var navigationGuard: SettingsNavigationGuard
    @State private var instanceBaseURL = ""
    @State private var autostartEnabled = false
    @State private var restrictHost = true
    @State private var useRouteReloadForLauncherChats = false
    @State private var launcherOpacity = 95.0
    @State private var statusMessage = ""
    @State private var statusIsError = false
    @State private var isShowingResetConfirmation = false
    @State private var isShowingCompatibilityConfirmation = false
    @State private var pendingCleanupPreview: AppController.SettingsChangePreview?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Instance Settings")
                .font(.largeTitle.bold())
            Text("Choose the LibreChat instance this app should target.")
                .foregroundStyle(.secondary)

            Form {
                TextField("LibreChat Instance URL", text: $instanceBaseURL)
                Toggle("Restrict URLs to the configured instance host", isOn: $restrictHost)
                Toggle("Launch Kotoba Libre at login", isOn: $autostartEnabled)
                Toggle("Use route reload for launcher chats", isOn: $useRouteReloadForLauncherChats)
                VStack(alignment: .leading) {
                    Text("Launcher Opacity \(Int(launcherOpacity))%")
                    Slider(value: $launcherOpacity, in: 50...100, step: 5)
                }
            }
            .formStyle(.grouped)

            if let compatibilityMessage {
                VStack(alignment: .leading, spacing: 10) {
                    Text(compatibilityMessage)
                        .font(.footnote)
                        .foregroundStyle(Color.red)
                    Button("Export Agents Before Saving") {
                        exportAgents()
                    }
                }
            }

            HStack {
                Button("Save Settings") { saveSettings() }
                    .buttonStyle(.borderedProminent)

                Button("Reset Config", role: .destructive) {
                    isShowingResetConfirmation = true
                }
            }

            if !statusMessage.isEmpty {
                Text(statusMessage)
                    .foregroundStyle(statusIsError ? Color.red : .secondary)
            }
        }
        .onAppear {
            navigationGuard.registerDiscardHandler(for: .settings, handler: discardChanges)
            reload()
            updateDirtyState()
        }
        .onChange(of: draftState) { _ in
            updateDirtyState()
        }
        .onChange(of: appController.settings) { _ in
            updateDirtyState()
        }
        .confirmationDialog("Reset configuration?", isPresented: $isShowingResetConfirmation, titleVisibility: .visible) {
            Button("Reset Configuration", role: .destructive) {
                resetConfiguration()
            }
            Button("Cancel", role: .cancel) {
            }
        } message: {
            Text("This removes the saved LibreChat instance, agents, and shortcut so onboarding appears again.")
        }
        .confirmationDialog("Remove incompatible agents?", isPresented: $isShowingCompatibilityConfirmation, titleVisibility: .visible) {
            Button("Export and Save") {
                exportAndSave()
            }
            if let pendingCleanupPreview {
                Button("Save and Remove \(pendingCleanupPreview.incompatiblePresets.count) Agents", role: .destructive) {
                    commitSettings()
                }
            }
            Button("Cancel", role: .cancel) {
                pendingCleanupPreview = nil
            }
        } message: {
            if let pendingCleanupPreview {
                Text(cleanupMessage(for: pendingCleanupPreview.incompatiblePresets))
            }
        }
    }

    private func reload() {
        instanceBaseURL = appController.settings.instanceBaseUrl ?? ""
        autostartEnabled = appController.settings.autostartEnabled
        restrictHost = appController.settings.restrictHostToInstanceHost
        useRouteReloadForLauncherChats = appController.settings.useRouteReloadForLauncherChats
        launcherOpacity = (appController.settings.launcherOpacity * 100).rounded()
    }

    private func saveSettings() {
        do {
            let preview = try appController.previewSettingsChange(draftSettings)
            if !preview.incompatiblePresets.isEmpty {
                pendingCleanupPreview = preview
                isShowingCompatibilityConfirmation = true
                return
            }

            commitSettings()
        } catch {
            setStatus(error.localizedDescription, isError: true)
        }
    }

    private func setStatus(_ message: String, isError: Bool) {
        statusMessage = message
        statusIsError = isError
    }

    private func resetConfiguration() {
        do {
            try appController.resetConfiguration()
        } catch {
            setStatus(error.localizedDescription, isError: true)
        }
    }

    private func discardChanges() {
        reload()
        updateDirtyState()
    }

    private var draftSettings: AppSettings {
        AppSettings(
            instanceBaseUrl: instanceBaseURL,
            globalShortcut: appController.settings.globalShortcut,
            autostartEnabled: autostartEnabled,
            restrictHostToInstanceHost: restrictHost,
            defaultPresetId: appController.settings.defaultPresetId,
            useRouteReloadForLauncherChats: useRouteReloadForLauncherChats,
            launcherOpacity: launcherOpacity / 100
        )
    }

    private var draftState: SettingsDraftState {
        SettingsDraftState(
            instanceBaseURL: instanceBaseURL,
            autostartEnabled: autostartEnabled,
            restrictHost: restrictHost,
            useRouteReloadForLauncherChats: useRouteReloadForLauncherChats,
            launcherOpacity: launcherOpacity
        )
    }

    private var savedState: SettingsDraftState {
        SettingsDraftState(
            instanceBaseURL: appController.settings.instanceBaseUrl ?? "",
            autostartEnabled: appController.settings.autostartEnabled,
            restrictHost: appController.settings.restrictHostToInstanceHost,
            useRouteReloadForLauncherChats: appController.settings.useRouteReloadForLauncherChats,
            launcherOpacity: (appController.settings.launcherOpacity * 100).rounded()
        )
    }

    private var compatibilityMessage: String? {
        guard let preview = try? appController.previewSettingsChange(draftSettings), !preview.incompatiblePresets.isEmpty else {
            return nil
        }

        return cleanupMessage(for: preview.incompatiblePresets)
    }

    private func cleanupMessage(for incompatiblePresets: [Preset]) -> String {
        let names = incompatiblePresets.prefix(3).map(\.name)
        let suffix = incompatiblePresets.count > 3 ? " and \(incompatiblePresets.count - 3) more" : ""
        let namesText = names.isEmpty ? "" : " Affected agents: \(names.joined(separator: ", "))\(suffix)."
        return "\(incompatiblePresets.count) configured agent\(incompatiblePresets.count == 1 ? "" : "s") no longer match this LibreChat host while host restriction is enabled. Export them before saving if you want a backup.\(namesText)"
    }

    private func exportAgents() {
        do {
            let count = try appController.exportPresetsFromPanel()
            if count > 0 {
                setStatus("Exported \(count) agents.", isError: false)
            }
        } catch {
            setStatus("Export failed: \(error.localizedDescription)", isError: true)
        }
    }

    private func exportAndSave() {
        do {
            let count = try appController.exportPresetsFromPanel()
            guard count > 0 else {
                setStatus("Export canceled. Settings were not changed.", isError: false)
                pendingCleanupPreview = nil
                return
            }
            commitSettings(exportedCount: count)
        } catch {
            setStatus("Export failed: \(error.localizedDescription)", isError: true)
        }
    }

    private func commitSettings(exportedCount: Int? = nil) {
        do {
            let result = try appController.saveSettings(draftSettings)
            reload()
            updateDirtyState()
            pendingCleanupPreview = nil

            let removedCount = result.removedPresets.count
            if let exportedCount, removedCount > 0 {
                setStatus("Exported \(exportedCount) agents. Settings saved and removed \(removedCount) incompatible agents.", isError: false)
            } else if removedCount > 0 {
                setStatus("Settings saved. Removed \(removedCount) incompatible agents.", isError: false)
            } else {
                setStatus("Settings saved.", isError: false)
            }
        } catch {
            setStatus(error.localizedDescription, isError: true)
        }
    }

    private func updateDirtyState() {
        navigationGuard.setDirty(draftState != savedState, for: .settings)
    }
}

private struct SettingsDraftState: Equatable {
    let instanceBaseURL: String
    let autostartEnabled: Bool
    let restrictHost: Bool
    let useRouteReloadForLauncherChats: Bool
    let launcherOpacity: Double
}

struct ShortcutPanelView: View {
    @ObservedObject var appController: AppController
    @EnvironmentObject private var navigationGuard: SettingsNavigationGuard
    @State private var statusMessage = ""
    @State private var statusIsError = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Shortcuts")
                .font(.largeTitle.bold())
            Text("Global shortcut for opening the Spotlight launcher.")
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 12) {
                Text("Global Shortcut")
                    .font(.headline)
                ShortcutPreviewView(shortcut: appController.shortcutDraft)

                HStack {
                    Button(appController.isRecordingShortcut ? "Stop" : "Record Shortcut") {
                        if appController.isRecordingShortcut {
                            appController.stopShortcutRecording()
                            setStatus("Shortcut capture canceled.", isError: false)
                        } else {
                            appController.beginShortcutRecording()
                            setStatus("Press a key combination (Esc to cancel).", isError: false)
                        }
                    }
                    Button("Reset Default") {
                        appController.resetShortcutDraft()
                        setStatus("Reset to default: \(AppSettings.defaultShortcut)", isError: false)
                    }
                    Button("Save Shortcut") {
                        do {
                            try appController.saveShortcutDraft()
                            setStatus("Shortcut saved.", isError: false)
                        } catch {
                            setStatus(error.localizedDescription, isError: true)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }

                if appController.isRecordingShortcut {
                    Text("Listening for a shortcut...")
                        .foregroundStyle(.secondary)
                }
            }

            if !statusMessage.isEmpty {
                Text(statusMessage)
                    .foregroundStyle(statusIsError ? Color.red : .secondary)
            } else if let registrationIssue = appController.shortcutRegistrationIssue {
                Text(registrationIssue)
                    .foregroundStyle(Color.red)
            }

            Spacer()
        }
        .onAppear {
            navigationGuard.registerDiscardHandler(for: .shortcuts, handler: discardChanges)
            updateDirtyState()
        }
        .onChange(of: appController.shortcutDraft) { _ in
            updateDirtyState()
        }
        .onChange(of: appController.isRecordingShortcut) { _ in
            updateDirtyState()
        }
        .onChange(of: appController.settings) { _ in
            updateDirtyState()
        }
    }

    private func setStatus(_ message: String, isError: Bool) {
        statusMessage = message
        statusIsError = isError
    }

    private func discardChanges() {
        appController.discardShortcutDraftChanges()
        updateDirtyState()
    }

    private func updateDirtyState() {
        let isDirty = appController.shortcutDraft != appController.settings.globalShortcut || appController.isRecordingShortcut
        navigationGuard.setDirty(isDirty, for: .shortcuts)
    }
}

struct AboutPanelView: View {
    let openSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("About")
                .font(.largeTitle.bold())
            Text("Quick launcher wrapper for self-hosted LibreChat instances.")
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 8) {
                Text("1. Configure your instance URL in Settings.")
                Text("2. Add one or more agents with URL templates.")
                Text("3. Use the global shortcut to ask directly from the Spotlight-style launcher.")
            }

            Button("Open Settings Window", action: openSettings)

            Spacer()
        }
    }
}

struct LauncherRootView: View {
    @ObservedObject var viewModel: LauncherViewModel

    private var selectedPresetBinding: Binding<String> {
        Binding(
            get: { viewModel.selectedPresetID ?? viewModel.presets.first?.id ?? "" },
            set: { viewModel.selectedPresetID = $0 }
        )
    }

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 14) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(.secondary)

                LauncherSearchField(
                    text: $viewModel.query,
                    focusToken: viewModel.focusToken,
                    onSubmit: viewModel.submit
                )
                .frame(maxWidth: .infinity, minHeight: 44)

                Group {
                    if viewModel.presets.isEmpty {
                        Text("No agents")
                            .foregroundStyle(.secondary)
                            .frame(width: 220, alignment: .trailing)
                    } else {
                        Picker("Agent", selection: selectedPresetBinding) {
                            ForEach(viewModel.presets) { preset in
                                Text(preset.name).tag(preset.id)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .frame(width: 220, alignment: .trailing)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(Color.white.opacity(0.58))
                        )
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity, minHeight: 78)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color(nsColor: .windowBackgroundColor).opacity(viewModel.opacity))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(Color.white.opacity(0.6), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.16), radius: 18, x: 0, y: 10)
            )

            if !viewModel.statusMessage.isEmpty {
                Text(viewModel.statusMessage)
                    .foregroundStyle(viewModel.isError ? Color.red : .secondary)
                    .font(.footnote)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.clear)
    }
}

private struct LauncherSearchField: NSViewRepresentable {
    @Binding var text: String
    let focusToken: UUID
    let onSubmit: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, onSubmit: onSubmit)
    }

    func makeNSView(context: Context) -> NSTextField {
        let textField = NSTextField()
        textField.isBordered = false
        textField.isBezeled = false
        textField.drawsBackground = false
        textField.isEditable = true
        textField.isSelectable = true
        textField.focusRingType = .none
        textField.font = .systemFont(ofSize: 20, weight: .medium)
        textField.alignment = .center
        textField.placeholderString = "Ask Kotoba Libre"
        textField.delegate = context.coordinator
        textField.lineBreakMode = .byTruncatingTail
        return textField
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {
        if nsView.stringValue != text {
            nsView.stringValue = text
        }

        if context.coordinator.lastFocusToken != focusToken {
            context.coordinator.lastFocusToken = focusToken
            DispatchQueue.main.async {
                guard let window = nsView.window else {
                    return
                }

                window.makeFirstResponder(nsView)
                if let editor = window.fieldEditor(true, for: nsView) as? NSTextView {
                    editor.alignment = .center
                    editor.selectedRange = NSRange(location: nsView.stringValue.count, length: 0)
                }
            }
        }
    }
}

private final class Coordinator: NSObject, NSTextFieldDelegate {
    @Binding private var text: String
    private let onSubmit: () -> Void
    var lastFocusToken = UUID()

    init(text: Binding<String>, onSubmit: @escaping () -> Void) {
        self._text = text
        self.onSubmit = onSubmit
    }

    func controlTextDidChange(_ obj: Notification) {
        guard let textField = obj.object as? NSTextField else {
            return
        }
        text = textField.stringValue
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            onSubmit()
            return true
        }

        return false
    }
}

struct AppLogoView: View {
    var body: some View {
        HStack(spacing: 14) {
            if let iconURL = AppResources.iconPNGURL, let image = NSImage(contentsOf: iconURL) {
                Image(nsImage: image)
                    .resizable()
                    .frame(width: 56, height: 56)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            Text(appDisplayName)
                .font(.system(size: 34, weight: .bold, design: .rounded))
        }
    }
}
