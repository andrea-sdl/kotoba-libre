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
        ZStack {
            AppGlassBackground()

            GlassEffectContainer(spacing: 24) {
                VStack(alignment: .leading, spacing: 24) {
                    HStack(alignment: .top, spacing: 24) {
                        VStack(alignment: .leading, spacing: 12) {
                            AppLogoView()
                            Text("Set up Kotoba Libre once, then launch LibreChat from anywhere.")
                                .font(.title3)
                                .foregroundStyle(.secondary)
                        }

                        Spacer(minLength: 24)

                        GlassEffectContainer(spacing: 10) {
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
                                    .foregroundStyle(currentStep.rawValue >= step.rawValue ? Color.accentColor : .secondary)
                                    .glassEffect(
                                        .regular.tint(currentStep == step ? Color.accentColor.opacity(0.18) : Color.white.opacity(0.08)),
                                        in: .capsule
                                    )
                                }
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
                        GlassStatusBanner(message: statusMessage, isError: statusIsError)
                    }

                    GlassEffectContainer(spacing: 12) {
                        HStack {
                            if currentStep == .shortcut {
                                Button("Back") {
                                    withAnimation(.easeInOut(duration: 0.18)) {
                                        currentStep = .instance
                                    }
                                }
                                .buttonStyle(.glass)
                            }

                            Spacer()

                            Button(currentStep == .instance ? "Continue" : "Finish Setup") {
                                submitCurrentStep()
                            }
                            .buttonStyle(.glassProminent)
                            .disabled(currentStep == .instance && !instanceValidation.valid)
                        }
                    }
                }
                .padding(32)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .onAppear {
            instanceBaseURL = appController.settings.instanceBaseUrl ?? ""
            focusedField = .instanceBaseURL
        }
        .onChange(of: currentStep) {
            focusedField = currentStep == .instance ? .instanceBaseURL : nil
        }
    }

    private var onboardingInstanceStep: some View {
        GlassPanel {
            VStack(alignment: .leading, spacing: 18) {
                Text("Where is your LibreChat instance running?")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                Text("Enter the base URL for the hosted or self-hosted LibreChat instance you want Kotoba Libre to open.")
                    .foregroundStyle(.secondary)

                GlassField("LibreChat Base URL") {
                    TextField("https://chat.example.com", text: $instanceBaseURL)
                        .disableAutocorrection(true)
                        .focused($focusedField, equals: OnboardingField.instanceBaseURL)
                        .onSubmit {
                            if instanceValidation.valid {
                                submitCurrentStep()
                            }
                        }
                        .glassTextInput()
                }

                GlassStatusBanner(
                    message: instanceValidation.valid ? "Looks good. We’ll keep navigation pinned to this host by default." : (instanceValidation.reason ?? "Enter a valid HTTPS URL."),
                    isError: !instanceValidation.valid
                )
            }
        }
    }

    private var onboardingShortcutStep: some View {
        GlassEffectContainer(spacing: 18) {
            VStack(alignment: .leading, spacing: 18) {
                GlassPanel {
                    VStack(alignment: .leading, spacing: 16) {
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
                                .buttonStyle(.glassProminent)

                                Button("Use Default") {
                                    appController.resetShortcutDraft()
                                    setStatus("Shortcut reset to \(AppSettings.defaultShortcut).", isError: false)
                                }
                                .buttonStyle(.glass)
                            }
                        }

                        if appController.isRecordingShortcut {
                            GlassStatusBanner(message: "Listening for a shortcut...", isError: false)
                        } else if let registrationIssue = appController.shortcutRegistrationIssue {
                            GlassStatusBanner(message: registrationIssue, isError: true)
                        }
                    }
                }

                MicrophonePermissionSection(
                    appController: appController,
                    title: "LibreChat Voice Input",
                    description: "LibreChat can use your microphone for voice input. Kotoba Libre only requests microphone access so that LibreChat feature can work inside the app."
                )

                SpeechRecognitionPermissionSection(
                    appController: appController,
                    title: "Voice Launcher Transcription",
                    description: "Voice mode uses Apple speech recognition to turn your recording into a prompt. You can configure its dedicated shortcut later in Settings."
                )
            }
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
                    .glassEffect(.regular, in: .capsule)
            }
        }
    }
}

// This shared section keeps the microphone permission copy and actions consistent in onboarding and settings.
private struct MicrophonePermissionSection: View {
    @ObservedObject var appController: AppController
    let title: String
    let description: String
    var showsCardBackground: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
            Text(description)
                .font(.footnote)
                .foregroundStyle(.secondary)

            Label(permissionState.statusMessage, systemImage: statusSymbolName)
                .font(.footnote)
                .foregroundStyle(statusColor)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 12) {
                switch permissionState {
                case .notDetermined:
                    Button(appController.isRequestingMicrophonePermission ? "Requesting..." : "Allow Microphone") {
                        appController.requestMicrophonePermission()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(appController.isRequestingMicrophonePermission)
                case .granted:
                    Button("Refresh Status") {
                        appController.refreshMicrophonePermissionState()
                    }
                case .denied, .restricted:
                    Button("Open System Settings") {
                        appController.openMicrophonePrivacySettings()
                    }
                    Button("Refresh Status") {
                        appController.refreshMicrophonePermissionState()
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(showsCardBackground ? 16 : 0)
        .background(backgroundView)
        .onAppear {
            appController.refreshMicrophonePermissionState()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            appController.refreshMicrophonePermissionState()
        }
    }

    private var permissionState: MicrophonePermissionState {
        appController.microphonePermissionState
    }

    private var statusSymbolName: String {
        switch permissionState {
        case .notDetermined:
            return "mic.badge.plus"
        case .granted:
            return "checkmark.circle.fill"
        case .denied:
            return "mic.slash.fill"
        case .restricted:
            return "lock.circle.fill"
        }
    }

    private var statusColor: Color {
        switch permissionState {
        case .granted:
            return .secondary
        case .notDetermined, .denied, .restricted:
            return .orange
        }
    }

    @ViewBuilder
    private var backgroundView: some View {
        if showsCardBackground {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.secondary.opacity(0.08))
        }
    }
}

// This shared section keeps speech recognition permission handling consistent anywhere voice mode is surfaced.
private struct SpeechRecognitionPermissionSection: View {
    @ObservedObject var appController: AppController
    let title: String
    let description: String
    var showsCardBackground: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
            Text(description)
                .font(.footnote)
                .foregroundStyle(.secondary)

            Label(permissionState.statusMessage, systemImage: statusSymbolName)
                .font(.footnote)
                .foregroundStyle(statusColor)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 12) {
                switch permissionState {
                case .notDetermined:
                    Button(appController.isRequestingSpeechRecognitionPermission ? "Requesting..." : "Allow Speech Recognition") {
                        appController.requestSpeechRecognitionPermission()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(appController.isRequestingSpeechRecognitionPermission)
                case .granted:
                    Button("Refresh Status") {
                        appController.refreshSpeechRecognitionPermissionState()
                    }
                case .denied, .restricted:
                    Button("Open System Settings") {
                        appController.openSpeechRecognitionPrivacySettings()
                    }
                    Button("Refresh Status") {
                        appController.refreshSpeechRecognitionPermissionState()
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(showsCardBackground ? 16 : 0)
        .background(backgroundView)
        .onAppear {
            appController.refreshSpeechRecognitionPermissionState()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            appController.refreshSpeechRecognitionPermissionState()
        }
    }

    private var permissionState: SpeechRecognitionPermissionState {
        appController.speechRecognitionPermissionState
    }

    private var statusSymbolName: String {
        switch permissionState {
        case .notDetermined:
            return "waveform.badge.mic"
        case .granted:
            return "checkmark.circle.fill"
        case .denied:
            return "waveform.slash"
        case .restricted:
            return "lock.circle.fill"
        }
    }

    private var statusColor: Color {
        switch permissionState {
        case .granted:
            return .secondary
        case .notDetermined, .denied, .restricted:
            return .orange
        }
    }

    @ViewBuilder
    private var backgroundView: some View {
        if showsCardBackground {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.secondary.opacity(0.08))
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

// AppGlassBackground adds a soft ambient backdrop so the glass surfaces have depth to refract.
struct AppGlassBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(nsColor: .windowBackgroundColor),
                    Color(nsColor: .underPageBackgroundColor),
                    Color.accentColor.opacity(0.16)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Circle()
                .fill(Color.accentColor.opacity(0.24))
                .frame(width: 320, height: 320)
                .blur(radius: 100)
                .offset(x: -220, y: -170)

            Circle()
                .fill(Color.white.opacity(0.18))
                .frame(width: 260, height: 260)
                .blur(radius: 90)
                .offset(x: 250, y: -120)

            Ellipse()
                .fill(Color.accentColor.opacity(0.12))
                .frame(width: 440, height: 240)
                .blur(radius: 120)
                .offset(x: 120, y: 220)
        }
        .ignoresSafeArea()
    }
}

// GlassPanel keeps repeated page sections visually consistent across onboarding, settings, and sheets.
struct GlassPanel<Content: View>: View {
    let cornerRadius: CGFloat
    let padding: CGFloat
    @ViewBuilder let content: Content

    init(cornerRadius: CGFloat = 24, padding: CGFloat = 20, @ViewBuilder content: () -> Content) {
        self.cornerRadius = cornerRadius
        self.padding = padding
        self.content = content()
    }

    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(padding)
            .glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
    }
}

// GlassStatusBanner surfaces validation and save feedback inside a compact glass capsule.
struct GlassStatusBanner: View {
    let message: String
    let isError: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: isError ? "exclamationmark.triangle.fill" : "info.circle.fill")
                .foregroundStyle(isError ? Color.red : Color.accentColor)

            Text(message)
                .foregroundStyle(isError ? Color.red : .secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.footnote)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .glassEffect(
            .regular.tint(isError ? Color.red.opacity(0.12) : Color.accentColor.opacity(0.10)),
            in: .capsule
        )
        .accessibilityElement(children: .combine)
    }
}

// GlassField groups a label with a single control so forms can stay readable without default grouped chrome.
struct GlassField<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            content
        }
    }
}

// GlassTextInputModifier gives text fields a consistent glass treatment while keeping native editing behavior.
struct GlassTextInputModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .textFieldStyle(.plain)
            .font(.system(size: 15, weight: .medium, design: .rounded))
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassEffect(.regular, in: .rect(cornerRadius: 16))
    }
}

extension View {
    func glassTextInput() -> some View {
        modifier(GlassTextInputModifier())
    }
}

private enum SettingsTab: Int, Hashable {
    case agents
    case settings
    case system
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

            SystemPanelView(appController: appController)
                .environmentObject(navigationGuard)
                .tabItem { Text("System") }
                .tag(SettingsTab.system)

            ShortcutPanelView(appController: appController)
                .environmentObject(navigationGuard)
                .tabItem { Text("Shortcuts") }
                .tag(SettingsTab.shortcuts)

            AboutPanelView(openSettings: appController.showSettingsWindow)
                .tabItem { Text("About") }
                .tag(SettingsTab.about)
        }
        .padding(20)
        .frame(minWidth: 980, minHeight: 560, alignment: .topLeading)
        .onChange(of: selectedTab) {
            let nextTab = selectedTab
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
    let instanceBaseURL: String?

    var body: some View {
        TextField("Name", text: $draft.name)
        Picker("Kind", selection: $draft.kind) {
            ForEach(PresetKind.allCases, id: \.self) { kind in
                Text(kind.rawValue.capitalized).tag(kind)
            }
        }
        TextField(destinationFieldTitle, text: $draft.urlTemplate)
            .onChange(of: draft.urlTemplate) {
                normalizeAgentValueIfNeeded(draft.urlTemplate)
            }
            .onChange(of: draft.kind) {
                normalizeAgentValueIfNeeded(draft.urlTemplate)
            }

        if let previewState {
            Text(previewState.message)
                .font(.footnote)
                .foregroundStyle(previewState.isError ? Color.red : .secondary)
                .textSelection(.enabled)
        }

        if draft.kind == .link {
            Text("Launcher searches append the query as `prompt` plus `submit=true` unless you use `{query}` in the URL.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }

        let validation = KotobaLibreCore.validatePresetValue(draft.urlTemplate, kind: draft.kind)
        Text(validation.valid ? validationSuccessMessage : (validation.reason ?? "Invalid value."))
            .font(.footnote)
            .foregroundStyle(validation.valid ? .secondary : Color.red)
    }

    private var destinationFieldTitle: String {
        switch draft.kind {
        case .agent:
            return "Agent ID or Agent URL"
        case .link:
            return "Configured URL"
        }
    }

    private var validationSuccessMessage: String {
        switch draft.kind {
        case .agent:
            return "Agent ID looks valid."
        case .link:
            return "Link looks valid."
        }
    }

    private var previewState: (message: String, isError: Bool)? {
        let trimmedValue = draft.urlTemplate.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedValue.isEmpty else {
            return nil
        }

        do {
            let preview = try KotobaLibreCore.previewDestination(for: draft, instanceBaseURL: instanceBaseURL)
            return ("Preview: \(preview)", false)
        } catch {
            return (error.localizedDescription, true)
        }
    }

    private func normalizeAgentValueIfNeeded(_ rawValue: String) {
        guard draft.kind == .agent else {
            return
        }

        let normalizedValue = KotobaLibreCore.normalizePresetValue(rawValue, kind: .agent)
        guard normalizedValue != rawValue else {
            return
        }

        draft.urlTemplate = normalizedValue
    }
}

// AgentManagerView edits the preset list used by the launcher and deep links.
struct AgentManagerView: View {
    @ObservedObject var appController: AppController
    @EnvironmentObject private var navigationGuard: SettingsNavigationGuard
    @State private var selectedPresetID: String?
    @State private var draft = Preset(id: "", name: "", urlTemplate: "https://", kind: .agent, createdAt: "", updatedAt: "")
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
                    .buttonStyle(.borderedProminent)
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
                .onChange(of: selectedPresetID) {
                    let newValue = selectedPresetID
                    // Selecting a row replaces the editable draft with the saved preset.
                    guard let newValue, let preset = appController.presets.first(where: { $0.id == newValue }) else {
                        return
                    }
                    draft = preset
                }

                Form {
                    AgentEditorFields(draft: $draft, instanceBaseURL: appController.settings.instanceBaseUrl)

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
        .frame(minHeight: 520, alignment: .topLeading)
        .onAppear {
            navigationGuard.registerDiscardHandler(for: .agents, handler: discardChanges)
            guard !didLoadInitialDraft else {
                updateDirtyState()
                return
            }

            didLoadInitialDraft = true
            resetDraft()
        }
        .onChange(of: selectedPresetID) {
            updateDirtyState()
        }
        .onChange(of: draftSnapshot) {
            updateDirtyState()
        }
        .onChange(of: appController.settings.instanceBaseUrl) {
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
            try appController.openDraftURL(draft)
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

// Draft state strips whitespace so the dirty check compares user intent, not formatting.
private struct PresetDraftState: Equatable {
    let name: String
    let urlTemplate: String
    let kind: PresetKind

    init(preset: Preset) {
        self.name = preset.name.trimmingCharacters(in: .whitespacesAndNewlines)
        self.urlTemplate = preset.urlTemplate.trimmingCharacters(in: .whitespacesAndNewlines)
        self.kind = preset.kind
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

// SettingsPanelView edits the LibreChat instance configuration that affects routing and host validation.
struct SettingsPanelView: View {
    @ObservedObject var appController: AppController
    @EnvironmentObject private var navigationGuard: SettingsNavigationGuard
    @State private var instanceBaseURL = ""
    @State private var restrictHost = true
    @State private var useRouteReloadForLauncherChats = false
    @State private var statusMessage = ""
    @State private var statusIsError = false
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
                Toggle("Use route reload for launcher chats", isOn: $useRouteReloadForLauncherChats)
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
        .onChange(of: draftState) {
            refreshPreviewState()
        }
        .onChange(of: appController.settings) {
            refreshPreviewState()
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
        restrictHost = appController.settings.restrictHostToInstanceHost
        useRouteReloadForLauncherChats = appController.settings.useRouteReloadForLauncherChats
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

    private func discardChanges() {
        reload()
        refreshPreviewState()
    }

    private var draftSettings: AppSettings {
        AppSettings(
            instanceBaseUrl: instanceBaseURL,
            globalShortcut: appController.settings.globalShortcut,
            voiceGlobalShortcut: appController.settings.voiceGlobalShortcut,
            autostartEnabled: appController.settings.autostartEnabled,
            restrictHostToInstanceHost: restrictHost,
            defaultPresetId: appController.settings.defaultPresetId,
            useRouteReloadForLauncherChats: useRouteReloadForLauncherChats,
            debugLoggingEnabled: appController.settings.debugLoggingEnabled,
            launcherOpacity: appController.settings.launcherOpacity,
            appVisibilityMode: appController.settings.appVisibilityMode
        )
    }

    private var draftState: SettingsDraftState {
        SettingsDraftState(
            instanceBaseURL: instanceBaseURL,
            restrictHost: restrictHost,
            useRouteReloadForLauncherChats: useRouteReloadForLauncherChats
        )
    }

    private var savedState: SettingsDraftState {
        SettingsDraftState(
            instanceBaseURL: appController.settings.instanceBaseUrl ?? "",
            restrictHost: appController.settings.restrictHostToInstanceHost,
            useRouteReloadForLauncherChats: appController.settings.useRouteReloadForLauncherChats
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
    let restrictHost: Bool
    let useRouteReloadForLauncherChats: Bool
}

// SystemPanelView groups app-level behavior, diagnostics, and microphone permission controls.
struct SystemPanelView: View {
    @ObservedObject var appController: AppController
    @EnvironmentObject private var navigationGuard: SettingsNavigationGuard
    @State private var autostartEnabled = false
    @State private var debugLoggingEnabled = false
    @State private var launcherOpacity = 95.0
    @State private var appVisibilityMode = AppVisibilityMode.dockOnly
    @State private var statusMessage = ""
    @State private var statusIsError = false
    @State private var isShowingResetConfirmation = false
    @State private var suppressAutosave = true

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("System")
                .font(.largeTitle.bold())
            Text("Control app-wide behavior, diagnostics, and LibreChat hardware permissions.")
                .foregroundStyle(.secondary)

            Form {
                Toggle("Launch Kotoba Libre at login", isOn: $autostartEnabled)
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
                VStack(alignment: .leading, spacing: 8) {
                    Text("Launcher Opacity \(Int(launcherOpacity))%")
                    Slider(value: $launcherOpacity, in: 50...100, step: 5)
                }
                MicrophonePermissionSection(
                    appController: appController,
                    title: "LibreChat Microphone Access",
                    description: "LibreChat can record from the microphone for voice input. Kotoba Libre only requests this permission so that LibreChat feature can work when you use it.",
                    showsCardBackground: false
                )
                SpeechRecognitionPermissionSection(
                    appController: appController,
                    title: "Voice Launcher Transcription",
                    description: "Voice mode uses Apple speech recognition to turn your recording into the prompt that gets sent to the selected agent.",
                    showsCardBackground: false
                )
                Button("Reset Config", role: .destructive) {
                    isShowingResetConfirmation = true
                }
            }
            .formStyle(.grouped)

            if !statusMessage.isEmpty {
                Text(statusMessage)
                    .foregroundStyle(statusIsError ? Color.red : .secondary)
            }

            Spacer()
        }
        .onAppear {
            navigationGuard.registerDiscardHandler(for: .system, handler: discardChanges)
            reload()
        }
        .onChange(of: autostartEnabled) {
            autosaveSettings()
        }
        .onChange(of: debugLoggingEnabled) {
            autosaveSettings()
        }
        .onChange(of: launcherOpacity) {
            autosaveSettings()
        }
        .onChange(of: appVisibilityMode) {
            autosaveSettings()
        }
        .onChange(of: appController.settings) {
            reload()
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
    }

    private func reload() {
        suppressAutosave = true
        autostartEnabled = appController.settings.autostartEnabled
        debugLoggingEnabled = appController.settings.debugLoggingEnabled
        launcherOpacity = (appController.settings.launcherOpacity * 100).rounded()
        appVisibilityMode = appController.settings.appVisibilityMode
        navigationGuard.setDirty(false, for: .system)
        suppressAutosave = false
    }

    private func autosaveSettings() {
        guard !suppressAutosave else {
            return
        }

        do {
            _ = try appController.saveSettings(draftSettings)
            setStatus("", isError: false)
        } catch {
            reload()
            setStatus(error.localizedDescription, isError: true)
        }
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
    }

    private func setStatus(_ message: String, isError: Bool) {
        statusMessage = message
        statusIsError = isError
    }

    private var draftSettings: AppSettings {
        AppSettings(
            instanceBaseUrl: appController.settings.instanceBaseUrl,
            globalShortcut: appController.settings.globalShortcut,
            voiceGlobalShortcut: appController.settings.voiceGlobalShortcut,
            autostartEnabled: autostartEnabled,
            restrictHostToInstanceHost: appController.settings.restrictHostToInstanceHost,
            defaultPresetId: appController.settings.defaultPresetId,
            useRouteReloadForLauncherChats: appController.settings.useRouteReloadForLauncherChats,
            debugLoggingEnabled: debugLoggingEnabled,
            launcherOpacity: launcherOpacity / 100,
            appVisibilityMode: appVisibilityMode
        )
    }
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
            Text("Configure separate shortcuts for typed prompts and voice mode.")
                .foregroundStyle(.secondary)

            Form {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Text Launcher Shortcut")
                        .font(.headline)
                    Text("Opens the Spotlight-style launcher with the text field.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
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
                                setStatus("Text launcher shortcut saved.", isError: false)
                            } catch {
                                setStatus(error.localizedDescription, isError: true)
                            }
                        }
                        .buttonStyle(.borderedProminent)
                    }

                    if appController.isRecordingShortcut {
                        Text("Listening for a shortcut...")
                            .foregroundStyle(.secondary)
                    } else if let registrationIssue = appController.shortcutRegistrationIssue {
                        Text(registrationIssue)
                            .foregroundStyle(Color.red)
                    }
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("Voice Launcher Shortcut")
                        .font(.headline)
                    Text("Opens the persistent voice launcher and, when pressed again, sends the finished transcript to the selected agent.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    ShortcutPreviewView(shortcut: appController.voiceShortcutDraft)

                    HStack {
                        Button(appController.isRecordingVoiceShortcut ? "Stop" : "Record Shortcut") {
                            if appController.isRecordingVoiceShortcut {
                                appController.stopShortcutRecording()
                                setStatus("Voice shortcut capture canceled.", isError: false)
                            } else {
                                appController.beginVoiceShortcutRecording()
                                setStatus("Press a key combination (Esc to cancel).", isError: false)
                            }
                        }
                        Button("Reset Default") {
                            appController.resetVoiceShortcutDraft()
                            setStatus("Reset to default: \(AppSettings.defaultVoiceShortcut)", isError: false)
                        }
                        Button("Save Shortcut") {
                            do {
                                try appController.saveVoiceShortcutDraft()
                                setStatus("Voice launcher shortcut saved.", isError: false)
                            } catch {
                                setStatus(error.localizedDescription, isError: true)
                            }
                        }
                        .buttonStyle(.borderedProminent)
                    }

                    if appController.isRecordingVoiceShortcut {
                        Text("Listening for a shortcut...")
                            .foregroundStyle(.secondary)
                    } else if let registrationIssue = appController.voiceShortcutRegistrationIssue {
                        Text(registrationIssue)
                            .foregroundStyle(Color.red)
                    }
                }
            }
            .formStyle(.grouped)

            if !statusMessage.isEmpty {
                Text(statusMessage)
                    .foregroundStyle(statusIsError ? Color.red : .secondary)
            }

            Spacer()
        }
        .onAppear {
            navigationGuard.registerDiscardHandler(for: .shortcuts, handler: discardChanges)
            updateDirtyState()
        }
        .onChange(of: appController.shortcutDraft) {
            updateDirtyState()
        }
        .onChange(of: appController.voiceShortcutDraft) {
            updateDirtyState()
        }
        .onChange(of: appController.isRecordingShortcut) {
            updateDirtyState()
        }
        .onChange(of: appController.isRecordingVoiceShortcut) {
            updateDirtyState()
        }
        .onChange(of: appController.settings) {
            updateDirtyState()
        }
    }

    private func setStatus(_ message: String, isError: Bool) {
        statusMessage = message
        statusIsError = isError
    }

    private func discardChanges() {
        appController.discardShortcutDraftChanges()
        appController.discardVoiceShortcutDraftChanges()
        updateDirtyState()
    }

    private func updateDirtyState() {
        // Recording mode counts as unsaved work because the user has started an in-progress edit.
        let isDirty =
            appController.shortcutDraft != appController.settings.globalShortcut ||
            appController.voiceShortcutDraft != appController.settings.voiceGlobalShortcut ||
            appController.isRecordingShortcut ||
            appController.isRecordingVoiceShortcut
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
        let selectedPreset = presets.first { $0.id == viewModel.selectedPresetID }
        let selectedPresetName = if let selectedPreset {
            selectedPreset.id == viewModel.defaultPresetID ? "\(selectedPreset.name) (Default)" : selectedPreset.name
        } else {
            "Choose agent"
        }

        VStack(spacing: 8) {
            Group {
                switch viewModel.presentationMode {
                case .text:
                    HStack(spacing: 12) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundStyle(.secondary)

                        LauncherSearchField(
                            text: $viewModel.query,
                            focusToken: viewModel.focusToken,
                            onSubmit: viewModel.handlePrimaryAction
                        )
                        .frame(maxWidth: .infinity, minHeight: 44)

                        if presets.isEmpty {
                            Text("No agents")
                                .foregroundStyle(.secondary)
                                .frame(width: 236, alignment: .trailing)
                        } else {
                            LauncherAgentMenu(
                                presets: presets,
                                selectedPresetID: viewModel.selectedPresetID,
                                selectedPresetName: selectedPresetName,
                                defaultPresetID: viewModel.defaultPresetID
                            ) { presetID in
                                viewModel.selectedPresetID = presetID
                            }
                        }
                    }
                    .accessibilityElement(children: .contain)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity, minHeight: 64)
                case .voice:
                    VStack(spacing: 20) {
                        VoiceLauncherIndicator(
                            audioLevel: viewModel.voiceAudioLevel,
                            state: viewModel.voiceState
                        )

                        VStack(spacing: 6) {
                            Text(voiceTitle)
                                .font(.system(size: 28, weight: .bold, design: .rounded))

                            Text(voiceSubtitle)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }

                        HStack(spacing: 12) {
                            if presets.isEmpty {
                                Text("No agents")
                                    .foregroundStyle(.secondary)
                                    .frame(width: 236, alignment: .leading)
                            } else {
                                LauncherAgentMenu(
                                    presets: presets,
                                    selectedPresetID: viewModel.selectedPresetID,
                                    selectedPresetName: selectedPresetName,
                                    defaultPresetID: viewModel.defaultPresetID
                                ) { presetID in
                                    viewModel.selectedPresetID = presetID
                                }
                            }

                            Button("Cancel") {
                                viewModel.cancelAndHide()
                            }
                            .buttonStyle(.glass)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 28)
                    .padding(.vertical, 26)
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color(nsColor: .windowBackgroundColor).opacity(viewModel.opacity))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(Color.black.opacity(0.12), lineWidth: 1)
                    )
            )
            .shadow(color: .black.opacity(0.16), radius: 18, x: 0, y: 10)

            if !viewModel.statusMessage.isEmpty {
                Text(viewModel.statusMessage)
                    .foregroundStyle(viewModel.isError ? Color.red : .secondary)
                    .font(.footnote)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .background(Color.clear)
    }

    private var voiceTitle: String {
        switch viewModel.voiceState {
        case .idle:
            return "Voice Launcher"
        case .preparing:
            return "Preparing Voice Mode"
        case .listening:
            return "Listening"
        case .finishing:
            return "Finishing Transcript"
        }
    }

    private var voiceSubtitle: String {
        switch viewModel.voiceState {
        case .idle:
            return "Choose an agent, then start speaking."
        case .preparing:
            return "Requesting access and warming up Apple's speech transcription."
        case .listening:
            return "Speak naturally, then press \(viewModel.voiceShortcutDisplayValue) again to send."
        case .finishing:
            return "Transcribing your last words and preparing the prompt."
        }
    }
}

// VoiceLauncherIndicator gives voice mode a distinct animated listening surface without showing raw text.
private struct VoiceLauncherIndicator: View {
    let audioLevel: Double
    let state: VoiceTranscriptionService.State

    var body: some View {
        TimelineView(.animation) { context in
            let timestamp = context.date.timeIntervalSinceReferenceDate
            let pulseScale = pulseScale(at: timestamp)
            let ringScale = ringScale(at: timestamp)

            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.accentColor.opacity(0.88),
                                Color.accentColor.opacity(0.26),
                                Color.white.opacity(0.72)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 138, height: 138)
                    .scaleEffect(pulseScale)

                Circle()
                    .stroke(Color.accentColor.opacity(0.34), lineWidth: 2)
                    .frame(width: 164, height: 164)
                    .scaleEffect(ringScale)

                Circle()
                    .stroke(Color.white.opacity(0.42), lineWidth: 1)
                    .frame(width: 188, height: 188)
                    .scaleEffect(0.96 + (ringScale - 1.0) * 0.6)

                Image(systemName: symbolName)
                    .font(.system(size: 52, weight: .semibold))
                    .foregroundStyle(Color.white)
                    .shadow(color: .black.opacity(0.16), radius: 10, x: 0, y: 6)
            }
            .frame(width: 208, height: 208)
        }
        .accessibilityLabel(accessibilityLabel)
    }

    private var symbolName: String {
        switch state {
        case .idle:
            return "waveform"
        case .preparing:
            return "waveform.badge.mic"
        case .listening:
            return "waveform.circle.fill"
        case .finishing:
            return "waveform.badge.magnifyingglass"
        }
    }

    private var accessibilityLabel: String {
        switch state {
        case .idle:
            return "Voice launcher is idle"
        case .preparing:
            return "Voice launcher is preparing"
        case .listening:
            return "Voice launcher is listening"
        case .finishing:
            return "Voice launcher is finishing the transcript"
        }
    }

    private func pulseScale(at timestamp: TimeInterval) -> Double {
        switch state {
        case .idle:
            return 1.0
        case .preparing:
            return 0.96 + ((sin(timestamp * 2.2) + 1.0) * 0.03)
        case .listening:
            return 0.94 + (((sin(timestamp * 4.8) + 1.0) / 2.0) * (0.08 + audioLevel * 0.1))
        case .finishing:
            return 0.98 + ((sin(timestamp * 3.0) + 1.0) * 0.02)
        }
    }

    private func ringScale(at timestamp: TimeInterval) -> Double {
        switch state {
        case .idle:
            return 1.0
        case .preparing:
            return 1.02 + ((sin(timestamp * 1.6) + 1.0) * 0.04)
        case .listening:
            return 1.04 + (((sin(timestamp * 3.6) + 1.0) / 2.0) * (0.14 + audioLevel * 0.18))
        case .finishing:
            return 1.06 + ((sin(timestamp * 2.4) + 1.0) * 0.04)
        }
    }
}

// LauncherAgentMenu presents the current agent as a compact control with a clearer visual hierarchy.
private struct LauncherAgentMenu: View {
    let presets: [Preset]
    let selectedPresetID: String?
    let selectedPresetName: String
    let defaultPresetID: String?
    let onSelect: (String) -> Void

    var body: some View {
        Menu {
            ForEach(presets) { preset in
                Button {
                    onSelect(preset.id)
                } label: {
                    LauncherAgentMenuRow(
                        presetName: preset.name,
                        isSelected: preset.id == selectedPresetID,
                        isDefault: preset.id == defaultPresetID
                    )
                }
            }
        } label: {
            HStack(spacing: 10) {
                Text(selectedPresetName)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Spacer(minLength: 10)

                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.accentColor.opacity(0.88))
            }
            .frame(width: 236, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.white.opacity(0.62))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Color.black.opacity(0.08), lineWidth: 1)
                    )
            )
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .accessibilityLabel("Agent")
        .accessibilityValue(selectedPresetName)
        .accessibilityHint("Choose which agent the launcher uses.")
    }
}

// LauncherAgentMenuRow keeps the menu entries consistent and highlights selection state.
private struct LauncherAgentMenuRow: View {
    let presetName: String
    let isSelected: Bool
    let isDefault: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: isSelected ? "checkmark.circle.fill" : (isDefault ? "star.circle.fill" : "circle"))
                .foregroundStyle(isSelected ? Color.accentColor : .secondary)

            Text(presetName)
                .lineLimit(1)

            if isDefault {
                Spacer(minLength: 8)

                Text("Default")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
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
                    .padding(6)
                    .frame(width: 56, height: 56)
                    .glassEffect(.regular, in: .rect(cornerRadius: 18))
            }
            Text(appDisplayName)
                .font(.system(size: 34, weight: .bold, design: .rounded))
        }
    }
}
