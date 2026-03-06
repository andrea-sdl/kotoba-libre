import AppKit
import SwiftUI
import ToroLibreCore

struct FirstRunView: View {
    let openSettings: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            AppLogoView()
            Text("Set up your instance to get started.")
                .font(.title3)
                .foregroundStyle(.secondary)
            Button("Open Settings", action: openSettings)
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
        .background(
            LinearGradient(
                colors: [Color(nsColor: .windowBackgroundColor), Color.blue.opacity(0.12)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }
}

struct SettingsRootView: View {
    @ObservedObject var appController: AppController
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            AgentManagerView(appController: appController)
                .tabItem { Text("Agents") }
                .tag(0)

            SettingsPanelView(appController: appController)
                .tabItem { Text("Settings") }
                .tag(1)

            ShortcutPanelView(appController: appController)
                .tabItem { Text("Shortcuts") }
                .tag(2)

            AboutPanelView(openSettings: appController.showSettingsWindow)
                .tabItem { Text("About") }
                .tag(3)
        }
        .padding(20)
        .frame(minWidth: 980, minHeight: 720)
    }
}

struct AgentManagerView: View {
    @ObservedObject var appController: AppController
    @State private var selectedPresetID: String?
    @State private var draft = Preset(id: "", name: "", urlTemplate: "https://", kind: .agent, tags: [], createdAt: "", updatedAt: "")
    @State private var statusMessage = ""
    @State private var statusIsError = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Agents")
                        .font(.largeTitle.bold())
                    Text("Manage and configure your Toro Libre agents. Star sets default.")
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

                    let validation = ToroLibreCore.validateURLTemplate(draft.urlTemplate)
                    Text(validation.valid ? "Template looks valid." : (validation.reason ?? "Invalid URL template."))
                        .font(.footnote)
                        .foregroundColor(validation.valid ? .secondary : .red)

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
                    .foregroundColor(statusIsError ? .red : .secondary)
            }
        }
        .onAppear { resetDraft() }
    }

    private func resetDraft() {
        selectedPresetID = nil
        draft = appController.makeEmptyPreset()
        setStatus("Creating new agent.", isError: false)
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
}

struct SettingsPanelView: View {
    @ObservedObject var appController: AppController
    @State private var instanceBaseURL = ""
    @State private var openInNewWindow = false
    @State private var autostartEnabled = false
    @State private var restrictHost = true
    @State private var debugInWebview = false
    @State private var useRouteReloadForLauncherChats = false
    @State private var accentColor = "blue"
    @State private var launcherOpacity = 95.0
    @State private var statusMessage = ""
    @State private var statusIsError = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Instance Settings")
                .font(.largeTitle.bold())
            Text("Choose the Toro Libre instance this app should target.")
                .foregroundStyle(.secondary)

            Form {
                TextField("Toro Libre Instance URL", text: $instanceBaseURL)
                Toggle("Restrict URLs to the configured instance host", isOn: $restrictHost)
                Toggle("Open presets in a new window", isOn: $openInNewWindow)
                Toggle("Launch Toro Libre at login", isOn: $autostartEnabled)
                Toggle("Debug In-Webview", isOn: $debugInWebview)
                Toggle("Use route reload for launcher chats", isOn: $useRouteReloadForLauncherChats)
                Picker("Accent Color", selection: $accentColor) {
                    ForEach(appController.accentColorNames, id: \.self) { colorName in
                        Text(colorName.capitalized).tag(colorName)
                    }
                }
                VStack(alignment: .leading) {
                    Text("Launcher Opacity \(Int(launcherOpacity))%")
                    Slider(value: $launcherOpacity, in: 50...100, step: 5)
                }
            }
            .formStyle(.grouped)

            Button("Save Settings") { saveSettings() }
                .buttonStyle(.borderedProminent)

            if !statusMessage.isEmpty {
                Text(statusMessage)
                    .foregroundColor(statusIsError ? .red : .secondary)
            }
        }
        .onAppear(perform: reload)
    }

    private func reload() {
        instanceBaseURL = appController.settings.instanceBaseUrl ?? ""
        openInNewWindow = appController.settings.openInNewWindow
        autostartEnabled = appController.settings.autostartEnabled
        restrictHost = appController.settings.restrictHostToInstanceHost
        debugInWebview = appController.settings.debugInWebview
        useRouteReloadForLauncherChats = appController.settings.useRouteReloadForLauncherChats
        accentColor = appController.settings.accentColor
        launcherOpacity = (appController.settings.launcherOpacity * 100).rounded()
    }

    private func saveSettings() {
        do {
            try appController.saveSettings(
                AppSettings(
                    instanceBaseUrl: instanceBaseURL,
                    globalShortcut: appController.shortcutDraft,
                    autostartEnabled: autostartEnabled,
                    openInNewWindow: openInNewWindow,
                    restrictHostToInstanceHost: restrictHost,
                    defaultPresetId: appController.settings.defaultPresetId,
                    debugInWebview: debugInWebview,
                    useRouteReloadForLauncherChats: useRouteReloadForLauncherChats,
                    accentColor: accentColor,
                    launcherOpacity: launcherOpacity / 100
                )
            )
            setStatus("Settings saved.", isError: false)
        } catch {
            setStatus(error.localizedDescription, isError: true)
        }
    }

    private func setStatus(_ message: String, isError: Bool) {
        statusMessage = message
        statusIsError = isError
    }
}

struct ShortcutPanelView: View {
    @ObservedObject var appController: AppController
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
                HStack(spacing: 8) {
                    ForEach(displayParts(for: appController.shortcutDraft), id: \.self) { part in
                        Text(part)
                            .font(.system(.body, design: .rounded).weight(.semibold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Capsule().fill(Color.secondary.opacity(0.14)))
                    }
                }

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
                    .foregroundColor(statusIsError ? .red : .secondary)
            }

            Spacer()
        }
    }

    private func displayParts(for shortcut: String) -> [String] {
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

    private func setStatus(_ message: String, isError: Bool) {
        statusMessage = message
        statusIsError = isError
    }
}

struct AboutPanelView: View {
    let openSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("About")
                .font(.largeTitle.bold())
            Text("Quick launcher wrapper for self-hosted Toro Libre instances.")
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
            ZStack(alignment: .trailing) {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color.white.opacity(0.9))

                LauncherSearchField(
                    text: $viewModel.query,
                    focusToken: viewModel.focusToken,
                    onSubmit: viewModel.submit
                )
                .padding(.leading, 72)
                .padding(.trailing, 234)
                .frame(maxWidth: .infinity, minHeight: 44)

                HStack {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(.secondary)
                        .padding(.leading, 18)
                    Spacer()
                }
                .frame(maxWidth: .infinity, minHeight: 44)

                HStack {
                    Spacer()
                    Group {
                        if viewModel.presets.isEmpty {
                            Text("No agents")
                                .foregroundStyle(.secondary)
                                .frame(width: 190, alignment: .trailing)
                        } else {
                            Picker("Agent", selection: selectedPresetBinding) {
                                ForEach(viewModel.presets) { preset in
                                    Text(preset.name).tag(preset.id)
                                }
                            }
                            .labelsHidden()
                            .font(.system(size: 16, weight: .medium, design: .rounded))
                            .frame(width: 190, alignment: .trailing)
                        }
                    }
                    .padding(.trailing, 14)
                }
                .frame(maxWidth: .infinity, minHeight: 44)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(width: 800)
            .frame(minHeight: 56)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.white.opacity(viewModel.opacity))
                    .shadow(color: .black.opacity(0.12), radius: 12, x: 0, y: 6)
            )

            if !viewModel.statusMessage.isEmpty {
                Text(viewModel.statusMessage)
                    .foregroundColor(viewModel.isError ? .red : .secondary)
                    .font(.footnote)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
        textField.placeholderString = "Ask..."
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
