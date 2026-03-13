import AppKit
import SwiftUI
import KotobaLibreCore

// This file holds the SwiftUI surface of the app:
// onboarding, settings tabs, and the floating launcher UI.
private enum OnboardingStep: Int, CaseIterable {
    case welcome
    case instance
    case permissions
    case complete

    var title: String {
        switch self {
        case .welcome:
            return "Welcome"
        case .instance:
            return "Instance"
        case .permissions:
            return "Permissions"
        case .complete:
            return "Complete"
        }
    }

    var headline: String {
        switch self {
        case .welcome:
            return "Welcome to Kotoba Libre"
        case .instance:
            return "Choose your LibreChat home"
        case .permissions:
            return "Turn on voice features when you want them"
        case .complete:
            return "You're ready to go"
        }
    }

    var detail: String {
        switch self {
        case .welcome:
            return "Kotoba Libre is a macOS wrapper for LibreChat web apps, built to make chats and agents easier to reach from native shortcuts and launchers."
        case .instance:
            return "Add the one LibreChat base URL Kotoba Libre should use everywhere."
        case .permissions:
            return "Voice permissions are optional. You can allow them now or later when you first use voice input."
        case .complete:
            return "Your instance is configured and the app is ready to open LibreChat."
        }
    }

    var symbolName: String {
        switch self {
        case .welcome:
            return "sparkles.rectangle.stack"
        case .instance:
            return "network"
        case .permissions:
            return "hand.raised"
        case .complete:
            return "sparkles"
        }
    }

    var sidebarDetail: String {
        switch self {
        case .welcome:
            return "What the app helps you do"
        case .instance:
            return "Set the LibreChat URL"
        case .permissions:
            return "Optional voice access"
        case .complete:
            return "Save and open LibreChat"
        }
    }
}

private enum OnboardingField: Hashable {
    case instanceBaseURL
}

// OnboardingLayout keeps the wizard spacing in one place so every step uses the same frame.
private enum OnboardingLayout {
    static let wizardWidth: CGFloat = 860
    static let wizardHeight: CGFloat = 650
    static let sidebarWidth: CGFloat = 220
    static let contentPadding: CGFloat = 24
    static let footerHeight: CGFloat = 72
}

// OnboardingFlowView is the first-run experience shown when no instance URL exists yet.
struct OnboardingFlowView: View {
    @ObservedObject var appController: AppController
    @State private var currentStep: OnboardingStep = .welcome
    @State private var instanceBaseURL = ""
    @State private var statusMessage = ""
    @State private var statusIsError = false
    @FocusState private var focusedField: OnboardingField?

    var body: some View {
        OnboardingShellView(currentStep: currentStep) {
            currentStepView
        } footer: {
            OnboardingFooterBar(
                primaryActionTitle: primaryActionTitle,
                message: footerMessage,
                isError: footerMessageIsError,
                isPrimaryDisabled: primaryActionDisabled,
                showsBackAction: currentStep != .welcome,
                showsPrimaryAction: true,
                onBack: showPreviousStep,
                onPrimaryAction: submitCurrentStep
            )
        }
        .background {
            AppGlassBackground()
        }
        .fontDesign(.serif)
        .frame(width: OnboardingLayout.wizardWidth, height: OnboardingLayout.wizardHeight)
        .onAppear {
            instanceBaseURL = appController.settings.instanceBaseUrl ?? ""
            focusedField = currentStep == .instance ? .instanceBaseURL : nil
        }
        .onChange(of: currentStep) {
            focusedField = currentStep == .instance ? .instanceBaseURL : nil
            refreshShortcutPermissionsIfNeeded()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshShortcutPermissionsIfNeeded()
        }
    }

    @ViewBuilder
    private var currentStepView: some View {
        switch currentStep {
        case .welcome:
            onboardingWelcomeStep
        case .instance:
            onboardingInstanceStep
        case .permissions:
            onboardingPermissionsStep
        case .complete:
            onboardingCompleteStep
        }
    }

    private var onboardingWelcomeStep: some View {
        OnboardingWelcomeStepView()
    }

    private var onboardingInstanceStep: some View {
        OnboardingInstanceStepView(
            instanceBaseURL: $instanceBaseURL,
            focusedField: $focusedField,
            validation: instanceValidation,
            onSubmit: submitCurrentStep
        )
    }

    private var onboardingPermissionsStep: some View {
        OnboardingPermissionsStepView(appController: appController)
    }

    private var onboardingCompleteStep: some View {
        OnboardingCompleteStepView(
            instanceBaseURL: instanceBaseURL,
            microphonePermissionState: appController.microphonePermissionState,
            speechPermissionState: appController.speechRecognitionPermissionState,
            launcherShortcut: appController.shortcutDraft,
            voiceShortcut: appController.voiceShortcutDraft,
            showAppWindowShortcut: appController.showAppWindowShortcutDraft
        )
    }

    private var primaryActionTitle: String {
        switch currentStep {
        case .welcome:
            return "Start Configuration"
        case .instance:
            return "Continue"
        case .permissions:
            return "Continue"
        case .complete:
            return "Start Using LibreChat"
        }
    }

    private var primaryActionDisabled: Bool {
        switch currentStep {
        case .welcome, .permissions, .complete:
            return false
        case .instance:
            return !instanceValidation.valid
        }
    }

    private var footerMessage: String {
        if currentStep == .welcome || currentStep == .instance {
            return ""
        }

        if !statusMessage.isEmpty {
            return statusMessage
        }

        return ""
    }

    private var footerMessageIsError: Bool {
        if currentStep == .welcome || currentStep == .instance {
            return false
        }

        if !statusMessage.isEmpty {
            return statusIsError
        }

        switch currentStep {
        case .welcome:
            return false
        case .instance:
            return !instanceValidation.valid
        case .permissions, .complete:
            return false
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
        // Each step only advances when its local requirements are satisfied. Saving happens at the end.
        switch currentStep {
        case .welcome:
            withAnimation(.easeInOut(duration: 0.18)) {
                currentStep = .instance
            }
            setStatus("", isError: false)
        case .instance:
            guard instanceValidation.valid else {
                setStatus("", isError: false)
                focusedField = .instanceBaseURL
                return
            }

            withAnimation(.easeInOut(duration: 0.18)) {
                currentStep = .permissions
            }
            refreshPermissionState()
            setStatus("", isError: false)
        case .permissions:
            withAnimation(.easeInOut(duration: 0.18)) {
                currentStep = .complete
            }
            setStatus("", isError: false)
        case .complete:
            do {
                try appController.completeOnboarding(
                    instanceBaseURL: instanceBaseURL,
                    launcherShortcut: appController.shortcutDraft,
                    voiceShortcut: appController.voiceShortcutDraft,
                    showAppWindowShortcut: appController.showAppWindowShortcutDraft
                )
                setStatus("", isError: false)
            } catch {
                setStatus(error.localizedDescription, isError: true)
            }
        }
    }

    private func showPreviousStep() {
        withAnimation(.easeInOut(duration: 0.18)) {
            switch currentStep {
            case .welcome:
                currentStep = .welcome
            case .instance:
                currentStep = .welcome
            case .permissions:
                currentStep = .instance
            case .complete:
                currentStep = .permissions
            }
        }
    }

    private func setStatus(_ message: String, isError: Bool) {
        statusMessage = message
        statusIsError = isError
    }

    private func refreshShortcutPermissionsIfNeeded() {
        guard currentStep == .permissions else {
            return
        }

        refreshPermissionState()
    }

    private func refreshPermissionState() {
        appController.refreshMicrophonePermissionState()
        appController.refreshSpeechRecognitionPermissionState()
    }

}

// OnboardingShellView keeps the left rail, header, content, and footer aligned in one shared frame.
private struct OnboardingShellView<Content: View, Footer: View>: View {
    let currentStep: OnboardingStep
    let content: Content
    let footer: Footer

    init(
        currentStep: OnboardingStep,
        @ViewBuilder content: () -> Content,
        @ViewBuilder footer: () -> Footer
    ) {
        self.currentStep = currentStep
        self.content = content()
        self.footer = footer()
    }

    var body: some View {
        HStack(spacing: 0) {
            OnboardingSidebar(currentStep: currentStep)
                .padding(OnboardingLayout.contentPadding)
                .padding(.top, 16)
                .frame(width: OnboardingLayout.sidebarWidth, alignment: .topLeading)
                .frame(maxHeight: .infinity, alignment: .topLeading)

            Divider()
                .padding(.vertical, 16)

            VStack(spacing: 0) {
                OnboardingMainColumn(step: currentStep) {
                    content
                }
                .frame(maxHeight: .infinity, alignment: .topLeading)

                Divider()
                    .padding(.horizontal, OnboardingLayout.contentPadding)

                footer
                    .padding(.horizontal, OnboardingLayout.contentPadding)
                    .padding(.bottom, 16)
                    .frame(height: OnboardingLayout.footerHeight)
                    .frame(maxWidth: .infinity, alignment: .bottomTrailing)
            }
            .frame(maxHeight: .infinity)
        }
    }
}

// OnboardingMainColumn keeps every step aligned under the same shared title and supporting copy.
private struct OnboardingMainColumn<Content: View>: View {
    let step: OnboardingStep
    let content: Content

    init(step: OnboardingStep, @ViewBuilder content: () -> Content) {
        self.step = step
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            OnboardingStepHeader(step: step)
            content
                .frame(maxWidth: .infinity, alignment: .topLeading)

            Spacer(minLength: 0)
        }
        .padding(OnboardingLayout.contentPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

// OnboardingStepHeader keeps the active step title and supporting copy consistent across pages.
private struct OnboardingStepHeader: View {
    let step: OnboardingStep

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Step \(step.rawValue + 1) of \(OnboardingStep.allCases.count)", systemImage: step.symbolName)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)

            Text(step.headline)
                .font(.system(size: 29, weight: .bold, design: .serif))
                .lineLimit(2)
                .minimumScaleFactor(0.92)

            Text(step.detail)
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// OnboardingWelcomeStepView introduces the product before asking for setup details.
private struct OnboardingWelcomeStepView: View {
    private static let artworkImage = AppResources.aboutArtworkURL.flatMap(NSImage.init(contentsOf:))

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if let artwork = Self.artworkImage {
                Image(nsImage: artwork)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(maxWidth: .infinity)
                    .frame(height: 148)
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .strokeBorder(.white.opacity(0.12), lineWidth: 1)
                    }
                    .accessibilityHidden(true)
            }

            GlassPanel(cornerRadius: 22, padding: 18) {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Kotoba Libre wraps your LibreChat web app in a focused Mac experience.")
                        .font(.title3.weight(.semibold))
                        .fixedSize(horizontal: false, vertical: true)

                    Text("Use it to jump into chats and agents faster, without digging through browser tabs.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    VStack(alignment: .leading, spacing: 10) {
                        OnboardingWelcomeFeatureRow(
                            systemImage: "message.badge.waveform",
                            title: "Quick access to chats",
                            detail: "Open your LibreChat home in a dedicated desktop window whenever you need it."
                        )
                        OnboardingWelcomeFeatureRow(
                            systemImage: "command.square",
                            title: "Shortcut-driven launchers",
                            detail: "Bring up text or voice launchers from anywhere on macOS with global shortcuts."
                        )
                        OnboardingWelcomeFeatureRow(
                            systemImage: "person.2.badge.gearshape",
                            title: "Faster agent access",
                            detail: "Save agent links once, then launch the right workspace or assistant with less friction."
                        )
                    }
                }
            }
        }
    }
}

// OnboardingInstanceStepView keeps the URL entry step focused on one decision and validates near the field.
private struct OnboardingInstanceStepView: View {
    @Binding var instanceBaseURL: String
    @FocusState.Binding var focusedField: OnboardingField?
    let validation: ValidationResult
    let onSubmit: () -> Void

    private var trimmedValue: String {
        instanceBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var shouldShowValidation: Bool {
        !trimmedValue.isEmpty
    }

    var body: some View {
        GlassPanel(cornerRadius: 22, padding: 18) {
            VStack(alignment: .leading, spacing: 14) {
                GlassField("LibreChat Base URL") {
                    TextField("https://chat.example.com", text: $instanceBaseURL)
                        .disableAutocorrection(true)
                        .focused($focusedField, equals: OnboardingField.instanceBaseURL)
                        .onSubmit {
                            if validation.valid {
                                onSubmit()
                            }
                        }
                        .glassTextInput()
                }

                Text("Use the full hosted or self-hosted HTTPS URL for the LibreChat home you want this app to open.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if shouldShowValidation {
                    OnboardingValidationRow(
                        message: validation.valid
                            ? "That URL looks valid and ready to use."
                            : (validation.reason ?? "Enter a valid LibreChat URL."),
                        isValid: validation.valid
                    )
                }
            }
        }
    }
}

// OnboardingWelcomeFeatureRow keeps the welcome benefits easy to scan without a dense paragraph.
private struct OnboardingWelcomeFeatureRow: View {
    let systemImage: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: systemImage)
                .font(.title3.weight(.semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

// OnboardingPermissionsStepView defers optional voice permissions to a dedicated, skippable review step.
private struct OnboardingPermissionsStepView: View {
    @ObservedObject var appController: AppController

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            OnboardingMicrophonePermissionRow(appController: appController)
            OnboardingSpeechPermissionRow(appController: appController)

            Text("Kotoba Libre only prompts for these when you choose Allow, and you can turn them on later in Settings.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// OnboardingCompleteStepView confirms the setup choices before the final save.
private struct OnboardingCompleteStepView: View {
    let instanceBaseURL: String
    let microphonePermissionState: MicrophonePermissionState
    let speechPermissionState: SpeechRecognitionPermissionState
    let launcherShortcut: String
    let voiceShortcut: String
    let showAppWindowShortcut: String

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            GlassPanel(cornerRadius: 22, padding: 18) {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Review your setup")
                        .font(.title3.weight(.semibold))

                    OnboardingSummaryRow(
                        title: "LibreChat home",
                        value: instanceBaseURL.trimmingCharacters(in: .whitespacesAndNewlines),
                        systemImage: "network"
                    )
                    OnboardingSummaryRow(
                        title: "Voice input",
                        value: permissionSummary(for: microphonePermissionState),
                        systemImage: "mic"
                    )
                    OnboardingSummaryRow(
                        title: "Speech recognition",
                        value: permissionSummary(for: speechPermissionState),
                        systemImage: "waveform"
                    )
                }
            }

            GlassPanel(cornerRadius: 22, padding: 18) {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Your shortcuts")
                        .font(.title3.weight(.semibold))

                    OnboardingShortcutRow(
                        title: "Text Launcher",
                        detail: "Open the Spotlight-style text launcher",
                        shortcut: launcherShortcut,
                        systemImage: "command.square"
                    )
                    OnboardingShortcutRow(
                        title: "Voice Launcher",
                        detail: "Open the voice input launcher",
                        shortcut: voiceShortcut,
                        systemImage: "mic"
                    )
                    OnboardingShortcutRow(
                        title: "Show App Window",
                        detail: "Bring the main window to front",
                        shortcut: showAppWindowShortcut,
                        systemImage: "macwindow"
                    )

                    Text("You can change these anytime in Settings.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func permissionSummary(for state: MicrophonePermissionState) -> String {
        switch state {
        case .granted:
            return "Ready"
        case .notDetermined:
            return "Not enabled yet"
        case .denied:
            return "Blocked in System Settings"
        case .restricted:
            return "Restricted on this Mac"
        }
    }

    private func permissionSummary(for state: SpeechRecognitionPermissionState) -> String {
        switch state {
        case .granted:
            return "Ready"
        case .notDetermined:
            return "Not enabled yet"
        case .denied:
            return "Blocked in System Settings"
        case .restricted:
            return "Restricted on this Mac"
        }
    }
}

// OnboardingShortcutRow teaches the user a global shortcut in a compact, scannable row.
private struct OnboardingShortcutRow: View {
    let title: String
    let detail: String
    let shortcut: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.title3.weight(.semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            ShortcutPreviewView(shortcut: shortcut)
        }
        .accessibilityElement(children: .combine)
    }
}

// OnboardingValidationRow keeps success and error feedback close to the field it refers to.
private struct OnboardingValidationRow: View {
    let message: String
    let isValid: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: isValid ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(isValid ? Color.accentColor : Color.red)

            Text(message)
                .font(.footnote)
                .foregroundStyle(isValid ? .secondary : Color.red)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}

// OnboardingSidebar gives the wizard a compact left rail with progress and product context.
private struct OnboardingSidebar: View {
    let currentStep: OnboardingStep

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(OnboardingStep.allCases, id: \.rawValue) { step in
                    OnboardingStepBadge(step: step, currentStep: currentStep)
                }
            }

            Spacer()

            Text("You can change settings later too.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .contain)
    }
}

// OnboardingStepBadge turns each onboarding step into a readable, compact status row.
private struct OnboardingStepBadge: View {
    let step: OnboardingStep
    let currentStep: OnboardingStep

    private var isCompleted: Bool {
        currentStep.rawValue > step.rawValue
    }

    private var tint: Color {
        currentStep.rawValue >= step.rawValue ? .accentColor : .secondary
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            stepMarker

            VStack(alignment: .leading, spacing: 2) {
                Text(step.title)
                Text(step.sidebarDetail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .font(.footnote.weight(.semibold))
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .foregroundStyle(tint)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(currentStep == step ? Color.accentColor.opacity(0.12) : Color.primary.opacity(0.03))
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(step.title), \(accessibilityStatus)")
    }

    private var accessibilityStatus: String {
        if currentStep.rawValue > step.rawValue {
            return "completed"
        }
        if currentStep == step {
            return "current step"
        }
        return "up next"
    }

    @ViewBuilder
    private var stepMarker: some View {
        if isCompleted {
            Image(systemName: "checkmark.circle.fill")
                .font(.body.weight(.semibold))
        } else {
            ZStack {
                Circle()
                    .strokeBorder(currentStep == step ? tint : Color.secondary.opacity(0.55), lineWidth: currentStep == step ? 0 : 1.4)
                    .background(
                        Circle()
                            .fill(currentStep == step ? tint : Color.clear)
                    )
                Text("\(step.rawValue + 1)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(currentStep == step ? Color.white : .secondary)
            }
            .frame(width: 20, height: 20)
        }
    }
}

// OnboardingFooterBar anchors feedback and navigation inside the wizard without extra stacked panels.
private struct OnboardingFooterBar: View {
    let primaryActionTitle: String
    let message: String
    let isError: Bool
    let isPrimaryDisabled: Bool
    let showsBackAction: Bool
    let showsPrimaryAction: Bool
    let onBack: () -> Void
    let onPrimaryAction: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            if !message.isEmpty {
                OnboardingInlineMessage(message: message, isError: isError)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Spacer(minLength: 0)
            }

            if showsBackAction {
                Button("Back", action: onBack)
                    .buttonStyle(.glass)
                    .keyboardShortcut(.cancelAction)
            }

            if showsPrimaryAction {
                Button(primaryActionTitle, action: onPrimaryAction)
                    .buttonStyle(.glassProminent)
                    .disabled(isPrimaryDisabled)
                    .keyboardShortcut(.defaultAction)
            }
        }
    }
}

// OnboardingInlineMessage keeps validation and helper copy compact inside the wizard footer.
private struct OnboardingInlineMessage: View {
    let message: String
    let isError: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: isError ? "exclamationmark.triangle.fill" : "info.circle.fill")
                .foregroundStyle(isError ? Color.red : Color.accentColor)

            Text(message)
                .font(.footnote)
                .foregroundStyle(isError ? Color.red : .secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}

// OnboardingSummaryRow highlights the final setup state in a compact review list.
private struct OnboardingSummaryRow: View {
    let title: String
    let value: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .foregroundStyle(Color.accentColor)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.body.weight(.semibold))
                    .textSelection(.enabled)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

// OnboardingConfettiView adds a lightweight celebratory animation to the completion step.
private struct OnboardingConfettiView: View {
    private struct Particle: Identifiable {
        let id: Int
        let xSeed: CGFloat
        let delay: Double
        let size: CGFloat
        let color: Color
    }

    private let particles: [Particle] = [
        .init(id: 0, xSeed: 0.05, delay: 0.00, size: 10, color: .blue),
        .init(id: 1, xSeed: 0.14, delay: 0.20, size: 8, color: .orange),
        .init(id: 2, xSeed: 0.23, delay: 0.42, size: 9, color: .pink),
        .init(id: 3, xSeed: 0.31, delay: 0.08, size: 7, color: .green),
        .init(id: 4, xSeed: 0.39, delay: 0.50, size: 10, color: .yellow),
        .init(id: 5, xSeed: 0.48, delay: 0.15, size: 8, color: .mint),
        .init(id: 6, xSeed: 0.56, delay: 0.34, size: 9, color: .cyan),
        .init(id: 7, xSeed: 0.65, delay: 0.04, size: 7, color: .red),
        .init(id: 8, xSeed: 0.74, delay: 0.26, size: 10, color: .purple),
        .init(id: 9, xSeed: 0.83, delay: 0.12, size: 8, color: .indigo),
        .init(id: 10, xSeed: 0.91, delay: 0.46, size: 9, color: .teal)
    ]

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                let loopDuration = 2.8
                let time = timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: loopDuration)

                for particle in particles {
                    let phase = ((time + particle.delay).truncatingRemainder(dividingBy: loopDuration)) / loopDuration
                    let x = size.width * particle.xSeed
                    let y = size.height * CGFloat(phase)
                    let sway = sin((phase * .pi * 2) + Double(particle.id)) * 14
                    let rect = CGRect(
                        x: x + CGFloat(sway),
                        y: y,
                        width: particle.size,
                        height: particle.size * 1.6
                    )
                    let rotation = Angle(degrees: phase * 360 + Double(particle.id * 9))
                    var transform = CGAffineTransform.identity
                    transform = transform.translatedBy(x: rect.midX, y: rect.midY)
                    transform = transform.rotated(by: CGFloat(rotation.radians))
                    transform = transform.translatedBy(x: -rect.midX, y: -rect.midY)

                    let path = Path(roundedRect: rect, cornerRadius: 3).applying(transform)
                    context.fill(path, with: .color(particle.color.opacity(0.9)))
                }
            }
        }
        .clipped()
        .accessibilityHidden(true)
    }
}

// OnboardingMicrophonePermissionRow keeps the onboarding permission summary compact and actionable.
private struct OnboardingMicrophonePermissionRow: View {
    @ObservedObject var appController: AppController

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Label("LibreChat Voice Input", systemImage: statusSymbolName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)

                Text(appController.microphonePermissionState.statusMessage)
                    .font(.footnote)
                    .foregroundStyle(statusColor)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 16)

            HStack(spacing: 8) {
                switch appController.microphonePermissionState {
                case .notDetermined:
                    Button(appController.isRequestingMicrophonePermission ? "Requesting..." : "Allow") {
                        appController.requestMicrophonePermission()
                    }
                    .buttonStyle(.glass)
                    .disabled(appController.isRequestingMicrophonePermission)
                case .granted:
                    Button("Refresh") {
                        appController.refreshMicrophonePermissionState()
                    }
                    .buttonStyle(.glass)
                case .denied, .restricted:
                    Button("Settings") {
                        appController.openMicrophonePrivacySettings()
                    }
                    .buttonStyle(.glass)

                    Button("Refresh") {
                        appController.refreshMicrophonePermissionState()
                    }
                    .buttonStyle(.glass)
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.primary.opacity(0.03))
        )
    }

    private var statusSymbolName: String {
        switch appController.microphonePermissionState {
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
        switch appController.microphonePermissionState {
        case .granted:
            return .secondary
        case .notDetermined, .denied, .restricted:
            return .orange
        }
    }
}

// OnboardingSpeechPermissionRow mirrors the microphone row for voice transcription setup.
private struct OnboardingSpeechPermissionRow: View {
    @ObservedObject var appController: AppController

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Label("Voice Launcher Transcription", systemImage: statusSymbolName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)

                Text(appController.speechRecognitionPermissionState.statusMessage)
                    .font(.footnote)
                    .foregroundStyle(statusColor)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 16)

            HStack(spacing: 8) {
                switch appController.speechRecognitionPermissionState {
                case .notDetermined:
                    Button(appController.isRequestingSpeechRecognitionPermission ? "Requesting..." : "Allow") {
                        appController.requestSpeechRecognitionPermission()
                    }
                    .buttonStyle(.glass)
                    .disabled(appController.isRequestingSpeechRecognitionPermission)
                case .granted:
                    Button("Refresh") {
                        appController.refreshSpeechRecognitionPermissionState()
                    }
                    .buttonStyle(.glass)
                case .denied, .restricted:
                    Button("Settings") {
                        appController.openSpeechRecognitionPrivacySettings()
                    }
                    .buttonStyle(.glass)

                    Button("Refresh") {
                        appController.refreshSpeechRecognitionPermissionState()
                    }
                    .buttonStyle(.glass)
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.primary.opacity(0.03))
        )
    }

    private var statusSymbolName: String {
        switch appController.speechRecognitionPermissionState {
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
        switch appController.speechRecognitionPermissionState {
        case .granted:
            return .secondary
        case .notDetermined, .denied, .restricted:
            return .orange
        }
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
        case "Fn":
            return "fn"
        default:
            return token.replacingOccurrences(of: "Key", with: "").replacingOccurrences(of: "Digit", with: "")
        }
    }
}

// AppGlassBackground adds a soft ambient backdrop so the glass surfaces have depth to refract.
struct AppGlassBackground: View {
    var body: some View {
        Color.clear
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
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
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
            .font(.system(size: 15, weight: .medium, design: .serif))
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

            AboutPanelView()
                .tabItem { Text("About") }
                .tag(SettingsTab.about)
        }
        .padding(20)
        .fontDesign(.serif)
        .frame(minWidth: 980, minHeight: 640, alignment: .topLeading)
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
                    Text("Manage and configure your Kotoba Libre agents and links. Star sets default.")
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
                        Button(draft.kind == .link ? "Save Link" : "Save Agent") { savePreset() }
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
    @State private var suppressAutosave = true
    @State private var pendingAutosaveTask: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Instance Settings")
                .font(.largeTitle.bold())
            Text("Choose the LibreChat instance this app should target.")
                .foregroundStyle(.secondary)

            Form {
                TextField("LibreChat Instance URL", text: $instanceBaseURL)
                Toggle("Restrict URLs to the configured instance host", isOn: $restrictHost)
                VStack(alignment: .leading, spacing: 6) {
                    Toggle("Use route reload for launcher chats", isOn: $useRouteReloadForLauncherChats)
                    Text("Enable this if the normal SPA navigation flow does not work correctly for launcher chats.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
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
                    Button("Export Agents") {
                        exportAgents()
                    }
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
        .onChange(of: draftState) {
            refreshPreviewState()
        }
        .onChange(of: instanceBaseURL) {
            scheduleAutosave(after: .milliseconds(450))
        }
        .onChange(of: restrictHost) {
            scheduleAutosave()
        }
        .onChange(of: useRouteReloadForLauncherChats) {
            scheduleAutosave()
        }
        .onChange(of: appController.settings) {
            reload()
            refreshPreviewState()
        }
        .confirmationDialog("Remove incompatible agents?", isPresented: $isShowingCompatibilityConfirmation, titleVisibility: .visible) {
            Button("Export and Apply") {
                exportAndSave()
            }
            if let pendingCleanupPreview {
                Button("Apply and Remove \(pendingCleanupPreview.incompatiblePresets.count) Agents", role: .destructive) {
                    commitSettings(showSuccessStatus: true)
                }
            }
            Button("Cancel", role: .cancel) {
                reload()
                refreshPreviewState()
            }
        } message: {
            if let pendingCleanupPreview {
                Text(cleanupMessage(for: pendingCleanupPreview.incompatiblePresets))
            }
        }
        .onDisappear {
            pendingAutosaveTask?.cancel()
        }
    }

    private func reload() {
        suppressAutosave = true
        pendingAutosaveTask?.cancel()
        // The UI edits local @State first so invalid URLs can be corrected before autosave retries.
        instanceBaseURL = appController.settings.instanceBaseUrl ?? ""
        restrictHost = appController.settings.restrictHostToInstanceHost
        useRouteReloadForLauncherChats = appController.settings.useRouteReloadForLauncherChats
        pendingCleanupPreview = nil
        suppressAutosave = false
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
            showAppWindowShortcut: appController.settings.showAppWindowShortcut,
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
        return "\(incompatiblePresets.count) configured agent\(incompatiblePresets.count == 1 ? "" : "s") no longer match this LibreChat host while host restriction is enabled. Export them before continuing if you want a backup.\(namesText)"
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
                reload()
                refreshPreviewState()
                return
            }
            commitSettings(exportedCount: count, showSuccessStatus: true)
        } catch {
            setStatus("Export failed: \(error.localizedDescription)", isError: true)
        }
    }

    private func scheduleAutosave(after delay: Duration = .zero) {
        guard !suppressAutosave else {
            return
        }

        pendingAutosaveTask?.cancel()
        pendingAutosaveTask = Task { @MainActor in
            if delay > .zero {
                try? await Task.sleep(for: delay)
            }

            guard !Task.isCancelled else {
                return
            }

            autosaveSettings()
        }
    }

    private func autosaveSettings() {
        guard !suppressAutosave else {
            return
        }

        do {
            let preview = try resolveCurrentPreview()
            guard draftState != savedState else {
                setStatus("", isError: false)
                pendingCleanupPreview = nil
                return
            }

            if !preview.incompatiblePresets.isEmpty {
                // Autosave pauses here so the user can confirm the preset cleanup side effect.
                pendingCleanupPreview = preview
                isShowingCompatibilityConfirmation = true
                return
            }

            commitSettings(showSuccessStatus: false)
        } catch {
            setStatus(error.localizedDescription, isError: true)
        }
    }

    private func commitSettings(exportedCount: Int? = nil, showSuccessStatus: Bool) {
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
            } else if showSuccessStatus {
                setStatus("Settings saved.", isError: false)
            } else {
                setStatus("", isError: false)
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
                    HStack(alignment: .center, spacing: 16) {
                        Text("App Visibility")

                        Spacer()

                        Picker("App Visibility", selection: $appVisibilityMode) {
                            ForEach(AppVisibilityMode.allCases, id: \.self) { mode in
                                Text(mode.settingsLabel)
                                    .tag(mode)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                    }

                    Text(appVisibilityMode.settingsDescription)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text("Launcher Opacity \(Int(launcherOpacity))%")
                    Slider(value: $launcherOpacity, in: 50...100, step: 5)
                }
                VStack(alignment: .leading, spacing: 12) {
                    Text("Permissions")
                        .font(.headline)

                    HStack(alignment: .top, spacing: 20) {
                        MicrophonePermissionSection(
                            appController: appController,
                            title: "LibreChat Microphone Access",
                            description: "LibreChat can record from the microphone for voice input. Kotoba Libre only requests this permission so that LibreChat feature can work when you use it.",
                            showsCardBackground: false
                        )
                        .frame(maxWidth: .infinity, alignment: .topLeading)

                        Divider()
                            .frame(maxHeight: .infinity)

                        SpeechRecognitionPermissionSection(
                            appController: appController,
                            title: "Voice Launcher Transcription",
                            description: "Voice mode uses Apple speech recognition to turn your recording into the prompt that gets sent to the selected agent.",
                            showsCardBackground: false
                        )
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                    }
                }
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
            showAppWindowShortcut: appController.settings.showAppWindowShortcut,
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

// ShortcutPanelView lets the user record and save the app's global shortcuts.
struct ShortcutPanelView: View {
    @ObservedObject var appController: AppController
    @EnvironmentObject private var navigationGuard: SettingsNavigationGuard
    @State private var statusMessage = ""
    @State private var statusIsError = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Shortcuts")
                .font(.largeTitle.bold())
            Text("Configure separate shortcuts for typed prompts, voice mode, and the main app window.")
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
                            do {
                                try appController.saveShortcutDraft()
                                setStatus("Reset to default: \(AppSettings.defaultShortcut)", isError: false)
                            } catch {
                                setStatus(error.localizedDescription, isError: true)
                            }
                        }
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
                            do {
                                try appController.saveVoiceShortcutDraft()
                                setStatus("Reset to default: \(AppSettings.defaultVoiceShortcut)", isError: false)
                            } catch {
                                setStatus(error.localizedDescription, isError: true)
                            }
                        }
                    }

                    if appController.isRecordingVoiceShortcut {
                        Text("Listening for a shortcut...")
                            .foregroundStyle(.secondary)
                    } else if let registrationIssue = appController.voiceShortcutRegistrationIssue {
                        Text(registrationIssue)
                            .foregroundStyle(Color.red)
                    }
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("Show App Window Shortcut")
                        .font(.headline)
                    Text("Shows the main Kotoba Libre window, and hides it again if you press the shortcut while it is already visible.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    ShortcutPreviewView(shortcut: appController.showAppWindowShortcutDraft)

                    HStack {
                        Button(appController.isRecordingShowAppWindowShortcut ? "Stop" : "Record Shortcut") {
                            if appController.isRecordingShowAppWindowShortcut {
                                appController.stopShortcutRecording()
                                setStatus("Show window shortcut capture canceled.", isError: false)
                            } else {
                                appController.beginShowAppWindowShortcutRecording()
                                setStatus("Press a key combination (Esc to cancel).", isError: false)
                            }
                        }
                        Button("Reset Default") {
                            appController.resetShowAppWindowShortcutDraft()
                            do {
                                try appController.saveShowAppWindowShortcutDraft()
                                setStatus("Reset to default: \(AppSettings.defaultShowAppWindowShortcut)", isError: false)
                            } catch {
                                setStatus(error.localizedDescription, isError: true)
                            }
                        }
                    }

                    if appController.isRecordingShowAppWindowShortcut {
                        Text("Listening for a shortcut...")
                            .foregroundStyle(.secondary)
                    } else if let registrationIssue = appController.showAppWindowShortcutRegistrationIssue {
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
        .onChange(of: appController.showAppWindowShortcutDraft) {
            updateDirtyState()
        }
        .onChange(of: appController.isRecordingShortcut) { previousValue, newValue in
            handleTextRecordingChange(from: previousValue, to: newValue)
        }
        .onChange(of: appController.isRecordingVoiceShortcut) { previousValue, newValue in
            handleVoiceRecordingChange(from: previousValue, to: newValue)
        }
        .onChange(of: appController.isRecordingShowAppWindowShortcut) { previousValue, newValue in
            handleShowAppWindowRecordingChange(from: previousValue, to: newValue)
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
        appController.discardShowAppWindowShortcutDraftChanges()
        updateDirtyState()
    }

    private func handleTextRecordingChange(from previousValue: Bool, to newValue: Bool) {
        updateDirtyState()
        guard previousValue, !newValue else {
            return
        }

        guard appController.shortcutDraft != appController.settings.globalShortcut else {
            return
        }

        do {
            try appController.saveShortcutDraft()
            setStatus("Text launcher shortcut saved.", isError: false)
        } catch {
            setStatus(error.localizedDescription, isError: true)
        }
    }

    private func handleVoiceRecordingChange(from previousValue: Bool, to newValue: Bool) {
        updateDirtyState()
        guard previousValue, !newValue else {
            return
        }

        guard appController.voiceShortcutDraft != appController.settings.voiceGlobalShortcut else {
            return
        }

        do {
            try appController.saveVoiceShortcutDraft()
            setStatus("Voice launcher shortcut saved.", isError: false)
        } catch {
            setStatus(error.localizedDescription, isError: true)
        }
    }

    private func handleShowAppWindowRecordingChange(from previousValue: Bool, to newValue: Bool) {
        updateDirtyState()
        guard previousValue, !newValue else {
            return
        }

        guard appController.showAppWindowShortcutDraft != appController.settings.showAppWindowShortcut else {
            return
        }

        do {
            try appController.saveShowAppWindowShortcutDraft()
            setStatus("Show app window shortcut saved.", isError: false)
        } catch {
            setStatus(error.localizedDescription, isError: true)
        }
    }

    private func updateDirtyState() {
        // Recording mode counts as unsaved work because the user has started an in-progress edit.
        let isDirty =
            appController.shortcutDraft != appController.settings.globalShortcut ||
            appController.voiceShortcutDraft != appController.settings.voiceGlobalShortcut ||
            appController.showAppWindowShortcutDraft != appController.settings.showAppWindowShortcut ||
            appController.isRecordingShortcut ||
            appController.isRecordingVoiceShortcut ||
            appController.isRecordingShowAppWindowShortcut
        navigationGuard.setDirty(isDirty, for: .shortcuts)
    }
}

// AboutPanelView keeps the app summary visible even when the settings window is compact.
struct AboutPanelView: View {
    private static let contentPadding: CGFloat = 20
    private static let minimumHeroHeight: CGFloat = 420
    private static let overlayWidth: CGFloat = 420

    var body: some View {
        GeometryReader { geometry in
            let heroHeight = max(
                Self.minimumHeroHeight,
                geometry.size.height - (Self.contentPadding * 2)
            )

            Group {
                if let heroImage {
                    Image(nsImage: heroImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .frame(height: heroHeight)
                        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 22, style: .continuous)
                                .strokeBorder(.white.opacity(0.12), lineWidth: 1)
                        }
                        .overlay(alignment: .leading) {
                            AboutPanelHeroOverlay(
                                usesImageBackground: true
                            )
                            .frame(maxWidth: Self.overlayWidth, alignment: .leading)
                            .padding(28)
                        }
                        .shadow(color: .black.opacity(0.12), radius: 18, y: 10)
                        .accessibilityHidden(true)
                } else {
                    AboutPanelHeroOverlay(
                        usesImageBackground: false
                    )
                    .padding(28)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                }
            }
            .padding(Self.contentPadding)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private var heroImage: NSImage? {
        guard let heroImageURL = AppResources.aboutArtworkURL else {
            return nil
        }

        return NSImage(contentsOf: heroImageURL)
    }
}

// AboutPanelHeroOverlay keeps the descriptive copy readable while letting the artwork stay visible.
private struct AboutPanelHeroOverlay: View {
    let usesImageBackground: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("About")
                .font(.largeTitle.bold())
                .foregroundStyle(primaryTextColor)

            VStack(alignment: .leading, spacing: 6) {
                Text("Version \(AppResources.appVersionDisplayString)")
                    .font(.headline)
                    .foregroundStyle(primaryTextColor)
                Text("Quick launcher wrapper for self-hosted LibreChat instances.")
                    .foregroundStyle(secondaryTextColor)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("1. Configure your instance URL in Settings.")
                Text("2. Add one or more agents with URL templates.")
                Text("3. Use the global shortcut to ask directly from the Spotlight-style launcher.")
            }
            .font(.body.weight(.medium))
            .foregroundStyle(primaryTextColor)
        }
        .padding(24)
        .background(backgroundPanel)
        .accessibilityElement(children: .contain)
    }

    private var primaryTextColor: Color {
        .primary
    }

    private var secondaryTextColor: Color {
        .secondary
    }

    private var backgroundPanel: some View {
        RoundedRectangle(cornerRadius: 20, style: .continuous)
            .fill(.white.opacity(0.95))
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(.white.opacity(0.35), lineWidth: 1)
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
                    VStack(spacing: 18) {
                        HStack(spacing: 16) {
                            VoiceLauncherIndicator(
                                audioLevel: viewModel.voiceAudioLevel,
                                state: viewModel.voiceState,
                                diameter: 92
                            )

                            Text(voiceTitle)
                                .font(.system(size: 28, weight: .bold, design: .rounded))
                        }
                        .frame(maxWidth: .infinity, alignment: .center)

                        Text(voiceSubtitle)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 460)

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
                    .padding(.top, 24)
                    .padding(.bottom, 26)
                }
            }
            .background(
                LauncherPanelSurface(
                    opacity: viewModel.opacity,
                    presentationMode: viewModel.presentationMode
                )
            )

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

// LauncherPanelSurface keeps the launcher glass readable while letting a soft halo drift around it.
private struct LauncherPanelSurface: View {
    let opacity: Double
    let presentationMode: LauncherPresentation

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)

        ZStack {
            shape
                .fill(Color(nsColor: .windowBackgroundColor).opacity(opacity))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.black.opacity(0.12), lineWidth: 1)
                )
                .overlay(
                    shape
                        .launcherGlowOverlay(isVoice: presentationMode == .voice)
                )
        }
    }
}

// These helpers adapt the MIT-licensed IntelligenceGlow reference implementation
// for the launcher surfaces. See THIRD_PARTY_NOTICES.md for attribution details.
private extension InsettableShape {
    @MainActor
    func launcherGlowOverlay(isVoice: Bool) -> some View {
        launcherGlowStroke(
            lineWidths: isVoice ? [2.5, 4.5, 7.5] : [2, 3.5, 6],
            blurs: isVoice ? [0, 2, 6] : [0, 2, 5],
            updateInterval: 0.42,
            animationDurations: isVoice ? [0.44, 0.58, 0.76] : [0.40, 0.54, 0.70]
        )
        .opacity(isVoice ? 0.82 : 0.68)
    }

    @MainActor
    func launcherGlowStroke(
        lineWidths: [CGFloat],
        blurs: [CGFloat],
        updateInterval: TimeInterval,
        animationDurations: [TimeInterval]
    ) -> some View {
        LauncherGlowStrokeView(
            shape: self,
            lineWidths: lineWidths,
            blurs: blurs,
            updateInterval: updateInterval,
            animationDurations: animationDurations
        )
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// LauncherGlowStrokeView adapts the layered animated stroke from the MIT-licensed
// IntelligenceGlow reference implementation. See THIRD_PARTY_NOTICES.md for the
// full attribution and license notice.
private struct LauncherGlowStrokeView<S: InsettableShape>: View {
    let shape: S
    let lineWidths: [CGFloat]
    let blurs: [CGFloat]
    let updateInterval: TimeInterval
    let animationDurations: [TimeInterval]

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var stops: [Gradient.Stop] = .launcherGlowStyle

    var body: some View {
        let layerCount = min(lineWidths.count, blurs.count, animationDurations.count)
        let gradient = AngularGradient(
            gradient: Gradient(stops: stops),
            center: .center
        )

        ZStack {
            ForEach(0..<layerCount, id: \.self) { index in
                shape
                    .strokeBorder(gradient, lineWidth: lineWidths[index])
                    .blur(radius: blurs[index])
                    .animation(
                        reduceMotion ? .linear(duration: 0) : .easeInOut(duration: animationDurations[index]),
                        value: stops
                    )
            }
        }
        .task(id: updateInterval) {
            guard !reduceMotion else {
                stops = .launcherGlowStyle
                return
            }

            while !Task.isCancelled {
                stops = .launcherGlowStyle
                try? await Task.sleep(for: .seconds(updateInterval))
            }
        }
    }
}

// The palette stays airy and oceanic while the randomized stop locations keep the motion organic.
private extension Array where Element == Gradient.Stop {
    static var launcherGlowStyle: [Gradient.Stop] {
        [
            Color(red: 0.47, green: 0.83, blue: 1.00),
            Color(red: 0.62, green: 0.95, blue: 0.86),
            Color(red: 0.99, green: 0.79, blue: 0.62),
            Color(red: 0.96, green: 0.66, blue: 0.78),
            Color(red: 0.66, green: 0.74, blue: 1.00),
            Color(red: 0.83, green: 0.73, blue: 0.98)
        ]
        .map { Gradient.Stop(color: $0, location: Double.random(in: 0...1)) }
        .sorted { $0.location < $1.location }
    }
}

// VoiceLauncherIndicator gives voice mode a distinct animated listening surface without showing raw text.
private struct VoiceLauncherIndicator: View {
    let audioLevel: Double
    let state: VoiceTranscriptionService.State
    let diameter: CGFloat

    init(audioLevel: Double, state: VoiceTranscriptionService.State, diameter: CGFloat = 208) {
        self.audioLevel = audioLevel
        self.state = state
        self.diameter = diameter
    }

    var body: some View {
        TimelineView(.animation) { context in
            let timestamp = context.date.timeIntervalSinceReferenceDate
            let pulseScale = pulseScale(at: timestamp)
            let ringScale = ringScale(at: timestamp)
            let coreDiameter = diameter * 0.663
            let middleRingDiameter = diameter * 0.788
            let outerRingDiameter = diameter * 0.904
            let symbolSize = diameter * 0.25

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
                    .frame(width: coreDiameter, height: coreDiameter)
                    .scaleEffect(pulseScale)

                Circle()
                    .stroke(Color.accentColor.opacity(0.34), lineWidth: 2)
                    .frame(width: middleRingDiameter, height: middleRingDiameter)
                    .scaleEffect(ringScale)

                Circle()
                    .stroke(Color.white.opacity(0.42), lineWidth: 1)
                    .frame(width: outerRingDiameter, height: outerRingDiameter)
                    .scaleEffect(0.96 + (ringScale - 1.0) * 0.6)

                Image(systemName: symbolName)
                    .font(.system(size: symbolSize, weight: .semibold))
                    .foregroundStyle(Color.white)
                    .shadow(color: .black.opacity(0.16), radius: 10, x: 0, y: 6)
            }
            .frame(width: diameter, height: diameter)
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
    static let iconImage = AppResources.iconPNGURL.flatMap(NSImage.init(contentsOf:))

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
