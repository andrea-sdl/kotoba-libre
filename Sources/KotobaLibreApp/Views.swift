import AppKit
import SwiftUI
import KotobaLibreCore

// This file holds the SwiftUI surface of the app:
// onboarding, settings tabs, and the floating launcher UI.
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

// OnboardingFlowView is the first-run experience shown when no instance URL exists yet.
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
        // Validation delegates to the core URL rules, so onboarding matches later save behavior.
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
        // The first step validates locally. The second step performs the real persisted save.
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

// The preview renders stored shortcut tokens as small keycaps.
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

// Stored shortcut tokens use web-style names. This helper turns them into Mac glyphs.
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

// SettingsNavigationGuard tracks which tab has unsaved edits and how to discard them.
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

// SettingsRootView hosts the tab shell and prevents tab switches when the current tab is dirty.
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
        .frame(minWidth: 980, alignment: .topLeading)
        .onChange(of: selectedTab) { nextTab in
            guard !isIgnoringNextSelectionChange else {
                isIgnoringNextSelectionChange = false
                return
            }

            guard nextTab != committedTab else {
                return
            }

            if navigationGuard.isDirty(committedTab) {
                // The selection is reverted first, then the alert decides whether the switch can continue.
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

// AgentEditorFields keeps the shared preset fields consistent between Settings and the titlebar sheet.
struct AgentEditorFields: View {
    @Binding var draft: Preset

    var body: some View {
        TextField("Name", text: $draft.name)
        Picker("Kind", selection: $draft.kind) {
            ForEach(PresetKind.allCases, id: \.self) { kind in
                Text(kind.rawValue.capitalized).tag(kind)
            }
        }
        TextField("Configured URL", text: $draft.urlTemplate)
        TextField("Tags", text: Binding(
            get: { draft.tags.joined(separator: ", ") },
            // The text field edits one comma-separated string, but the model stores an array.
            set: { draft.tags = $0.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) } }
        ))

        let validation = KotobaLibreCore.validateURLTemplate(draft.urlTemplate)
        Text(validation.valid ? "Template looks valid." : (validation.reason ?? "Invalid URL template."))
            .font(.footnote)
            .foregroundStyle(validation.valid ? .secondary : Color.red)
    }
}

// AgentManagerView edits the preset list used by the launcher and deep links.
struct AgentManagerView: View {
    @ObservedObject var appController: AppController
    @EnvironmentObject private var navigationGuard: SettingsNavigationGuard
    @State private var selectedPresetID: String?
    @State private var draft = Preset(id: "", name: "", urlTemplate: "https://", kind: .agent, tags: [], createdAt: "", updatedAt: "")
    @State private var statusMessage = ""
    @State private var statusIsError = false
    @State private var didLoadInitialDraft = false

    var body: some View {
        let presets = appController.sortedPresets()

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
                    ForEach(presets) { preset in
                        AgentListRow(
                            preset: preset,
                            isDefault: appController.settings.defaultPresetId == preset.id,
                            onToggleDefault: { toggleDefault(for: preset) }
                        )
                        .tag(preset.id)
                    }
                }
                .frame(minWidth: 320)
                .overlay {
                    if presets.isEmpty {
                        EmptyAgentStateView()
                    }
                }
                .onChange(of: selectedPresetID) { newValue in
                    // Selecting a row replaces the editable draft with the saved preset.
                    guard let newValue, let preset = appController.presets.first(where: { $0.id == newValue }) else {
                        return
                    }
                    draft = preset
                }

                Form {
                    AgentEditorFields(draft: $draft)

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
        // The dirty check compares the form against the selected preset, or against a fresh empty preset.
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

// The star button lives inside the row so default selection stays discoverable next to each preset.
private struct AgentListRow: View {
    let preset: Preset
    let isDefault: Bool
    let onToggleDefault: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button(action: onToggleDefault) {
                Image(systemName: isDefault ? "star.fill" : "star")
                    .foregroundStyle(isDefault ? Color.accentColor : .secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isDefault ? "Unset default agent" : "Set as default agent")
            .accessibilityHint("Marks \(preset.name) as the launcher default.")

            VStack(alignment: .leading, spacing: 4) {
                Text(preset.name)
                    .font(.headline)
                Text(preset.urlTemplate)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .accessibilityElement(children: .combine)
        }
    }
}

// Empty state copy explains why the launcher may currently have nothing to run.
private struct EmptyAgentStateView: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "person.crop.circle.badge.plus")
                .font(.system(size: 28))
                .foregroundStyle(.secondary)
            Text("No Agents Yet")
                .font(.headline)
            Text("Create your first agent to power the launcher.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }
}

// Draft state strips whitespace and tag ordering so the dirty check compares user intent, not formatting.
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

// These labels are written for the settings screen, not for serialization.
private extension AppVisibilityMode {
    var settingsLabel: String {
        switch self {
        case .dockAndMenuBar:
            return "Show both dock icon and menu bar"
        case .dockOnly:
            return "Show only dock icon"
        case .menuBarOnly:
            return "Show only menu bar"
        }
    }

    var settingsDescription: String {
        switch self {
        case .dockAndMenuBar:
            return "Keep the app in the Dock and add a menu bar shortcut for quick access."
        case .dockOnly:
            return "Keep the current app behavior with a Dock icon and no extra menu bar item."
        case .menuBarOnly:
            return "Hide the Dock icon and use the menu bar item for settings, showing the LibreChat window, and quitting."
        }
    }
}

// SettingsPanelView edits app-wide behavior such as host restriction, login launch, and visibility mode.
struct SettingsPanelView: View {
    @ObservedObject var appController: AppController
    @EnvironmentObject private var navigationGuard: SettingsNavigationGuard
    @State private var instanceBaseURL = ""
    @State private var autostartEnabled = false
    @State private var restrictHost = true
    @State private var useRouteReloadForLauncherChats = false
    @State private var debugLoggingEnabled = false
    @State private var launcherOpacity = 95.0
    @State private var appVisibilityMode = AppVisibilityMode.dockOnly
    @State private var statusMessage = ""
    @State private var statusIsError = false
    @State private var isShowingResetConfirmation = false
    @State private var isShowingCompatibilityConfirmation = false
    @State private var pendingCleanupPreview: AppController.SettingsChangePreview?
    @State private var liveCompatibilityPreview: AppController.SettingsChangePreview?
    @State private var liveValidationIssue: String?

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
                Toggle("Enable debug logs", isOn: $debugLoggingEnabled)
                VStack(alignment: .leading, spacing: 8) {
                    Text("App Visibility")
                    Picker("App Visibility", selection: $appVisibilityMode) {
                        ForEach(AppVisibilityMode.allCases, id: \.self) { mode in
                            Text(mode.settingsLabel)
                                .tag(mode)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.radioGroup)

                    Text(appVisibilityMode.settingsDescription)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                VStack(alignment: .leading) {
                    Text("Launcher Opacity \(Int(launcherOpacity))%")
                    Slider(value: $launcherOpacity, in: 50...100, step: 5)
                }
            }
            .formStyle(.grouped)

            if let liveValidationIssue {
                Text(liveValidationIssue)
                    .font(.footnote)
                    .foregroundStyle(Color.red)
            } else if let compatibilityMessage {
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
            refreshPreviewState()
        }
        .onChange(of: draftState) { _ in
            refreshPreviewState()
        }
        .onChange(of: appController.settings) { _ in
            refreshPreviewState()
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
        // The UI edits local @State first so changes can be canceled before saving.
        instanceBaseURL = appController.settings.instanceBaseUrl ?? ""
        autostartEnabled = appController.settings.autostartEnabled
        restrictHost = appController.settings.restrictHostToInstanceHost
        useRouteReloadForLauncherChats = appController.settings.useRouteReloadForLauncherChats
        debugLoggingEnabled = appController.settings.debugLoggingEnabled
        launcherOpacity = (appController.settings.launcherOpacity * 100).rounded()
        appVisibilityMode = appController.settings.appVisibilityMode
    }

    private func saveSettings() {
        do {
            let preview = try resolveCurrentPreview()
            if !preview.incompatiblePresets.isEmpty {
                // Host changes can invalidate saved presets, so the user gets a cleanup confirmation first.
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
        refreshPreviewState()
    }

    private var draftSettings: AppSettings {
        AppSettings(
            instanceBaseUrl: instanceBaseURL,
            globalShortcut: appController.settings.globalShortcut,
            autostartEnabled: autostartEnabled,
            restrictHostToInstanceHost: restrictHost,
            defaultPresetId: appController.settings.defaultPresetId,
            useRouteReloadForLauncherChats: useRouteReloadForLauncherChats,
            debugLoggingEnabled: debugLoggingEnabled,
            launcherOpacity: launcherOpacity / 100,
            appVisibilityMode: appVisibilityMode
        )
    }

    private var draftState: SettingsDraftState {
        SettingsDraftState(
            instanceBaseURL: instanceBaseURL,
            autostartEnabled: autostartEnabled,
            restrictHost: restrictHost,
            useRouteReloadForLauncherChats: useRouteReloadForLauncherChats,
            debugLoggingEnabled: debugLoggingEnabled,
            launcherOpacity: launcherOpacity,
            appVisibilityMode: appVisibilityMode
        )
    }

    private var savedState: SettingsDraftState {
        SettingsDraftState(
            instanceBaseURL: appController.settings.instanceBaseUrl ?? "",
            autostartEnabled: appController.settings.autostartEnabled,
            restrictHost: appController.settings.restrictHostToInstanceHost,
            useRouteReloadForLauncherChats: appController.settings.useRouteReloadForLauncherChats,
            debugLoggingEnabled: appController.settings.debugLoggingEnabled,
            launcherOpacity: (appController.settings.launcherOpacity * 100).rounded(),
            appVisibilityMode: appController.settings.appVisibilityMode
        )
    }

    private var compatibilityMessage: String? {
        guard let liveCompatibilityPreview, !liveCompatibilityPreview.incompatiblePresets.isEmpty else {
            return nil
        }

        return cleanupMessage(for: liveCompatibilityPreview.incompatiblePresets)
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
            refreshPreviewState()
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

    private func refreshPreviewState() {
        do {
            // Previewing here powers both the live warning text and the dirty-state tracking.
            liveCompatibilityPreview = try appController.previewSettingsChange(draftSettings)
            liveValidationIssue = nil
        } catch {
            liveCompatibilityPreview = nil
            liveValidationIssue = error.localizedDescription
        }

        navigationGuard.setDirty(draftState != savedState, for: .settings)
    }

    private func resolveCurrentPreview() throws -> AppController.SettingsChangePreview {
        let preview = try appController.previewSettingsChange(draftSettings)
        liveCompatibilityPreview = preview
        liveValidationIssue = nil
        return preview
    }
}

// SettingsDraftState holds only the fields that belong to the Settings tab dirty check.
private struct SettingsDraftState: Equatable {
    let instanceBaseURL: String
    let autostartEnabled: Bool
    let restrictHost: Bool
    let useRouteReloadForLauncherChats: Bool
    let debugLoggingEnabled: Bool
    let launcherOpacity: Double
    let appVisibilityMode: AppVisibilityMode
}

// ShortcutPanelView lets the user record and save the global launcher shortcut.
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
        // Recording mode counts as unsaved work because the user has started an in-progress edit.
        let isDirty = appController.shortcutDraft != appController.settings.globalShortcut || appController.isRecordingShortcut
        navigationGuard.setDirty(isDirty, for: .shortcuts)
    }
}

// AboutPanelView is intentionally simple. It acts as a quick usage guide inside the app.
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

// LauncherRootView is the compact overlay shown when the global shortcut fires.
struct LauncherRootView: View {
    @ObservedObject var viewModel: LauncherViewModel

    var body: some View {
        let presets = viewModel.presets

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
                    if presets.isEmpty {
                        Text("No agents")
                            .foregroundStyle(.secondary)
                            .frame(width: 220, alignment: .trailing)
                    } else {
                        Picker("Agent", selection: $viewModel.selectedPresetID) {
                            ForEach(presets) { preset in
                                Text(preset.name).tag(Optional(preset.id))
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

// NSTextField is used here because SwiftUI's text field is harder to fine-tune inside an NSPanel.
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
                // Focus is assigned asynchronously because the window may not be key yet during update.
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

// The coordinator bridges AppKit text field delegate callbacks back into SwiftUI bindings.
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

// The app logo is reused in onboarding and settings headers.
struct AppLogoView: View {
    private static let iconImage = AppResources.iconPNGURL.flatMap(NSImage.init(contentsOf:))

    var body: some View {
        HStack(spacing: 14) {
            if let image = Self.iconImage {
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
