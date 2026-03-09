import AppKit
import SwiftUI
import KotobaLibreCore

// AddAgentSheetViewModel owns the temporary preset draft shown in the titlebar add-agent sheet.
@MainActor
final class AddAgentSheetViewModel: ObservableObject {
    @Published var draft: Preset
    @Published var statusMessage = ""
    @Published var statusIsError = false

    private weak var appController: AppController?
    var dismiss: () -> Void

    init(appController: AppController, draft: Preset, dismiss: @escaping () -> Void) {
        self.appController = appController
        self.draft = draft
        self.dismiss = dismiss
    }

    func save() {
        guard let appController else {
            return
        }

        guard appController.settings.instanceBaseUrl != nil else {
            setStatus("Set the LibreChat instance URL first.", isError: true)
            return
        }

        do {
            draft = try appController.upsertPreset(draft)
            dismiss()
        } catch {
            setStatus(error.localizedDescription, isError: true)
        }
    }

    func cancel() {
        dismiss()
    }

    private func setStatus(_ message: String, isError: Bool) {
        statusMessage = message
        statusIsError = isError
    }
}

// AddAgentSheetView is the compact editor presented from the main window titlebar button.
private struct AddAgentSheetView: View {
    @ObservedObject var viewModel: AddAgentSheetViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Add Agent")
                .font(.title2.bold())

            Text("Review the detected LibreChat agent, then save it to the launcher list.")
                .foregroundStyle(.secondary)

            Form {
                AgentEditorFields(draft: $viewModel.draft)
            }
            .formStyle(.grouped)

            if !viewModel.statusMessage.isEmpty {
                Text(viewModel.statusMessage)
                    .font(.footnote)
                    .foregroundStyle(viewModel.statusIsError ? Color.red : .secondary)
            }

            HStack {
                Spacer()

                Button("Cancel", action: viewModel.cancel)
                    .keyboardShortcut(.cancelAction)

                Button("Save", action: viewModel.save)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 520)
    }
}

// This controller attaches the add-agent editor as a native sheet on the main window.
@MainActor
final class AddAgentSheetWindowController: NSWindowController, NSWindowDelegate {
    private let viewModel: AddAgentSheetViewModel
    private let hostingController: NSHostingController<AddAgentSheetView>
    private let onDidClose: () -> Void
    private var didClose = false

    init(appController: AppController, initialPreset: Preset, onDidClose: @escaping () -> Void) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 540, height: 360),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Add Agent"
        window.isReleasedWhenClosed = false
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true

        self.onDidClose = onDidClose
        let viewModel = AddAgentSheetViewModel(appController: appController, draft: initialPreset, dismiss: {})
        self.viewModel = viewModel
        self.hostingController = NSHostingController(rootView: AddAgentSheetView(viewModel: viewModel))
        super.init(window: window)

        self.viewModel.dismiss = { [weak self] in
            self?.dismiss()
        }
        if #available(macOS 13.0, *) {
            self.hostingController.sizingOptions = [.preferredContentSize]
        }

        self.window?.delegate = self
        self.window?.contentViewController = hostingController
        resizeSheetToFitContent()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func beginSheet(on parentWindow: NSWindow) {
        guard let window else {
            return
        }

        resizeSheetToFitContent()
        parentWindow.beginSheet(window)
    }

    func dismiss() {
        guard let window else {
            finishDismissalIfNeeded()
            return
        }

        if let parentWindow = window.sheetParent {
            parentWindow.endSheet(window)
            window.orderOut(nil)
        } else {
            window.orderOut(nil)
        }

        finishDismissalIfNeeded()
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        dismiss()
        return false
    }

    private func resizeSheetToFitContent() {
        guard let window else {
            return
        }

        hostingController.view.layoutSubtreeIfNeeded()
        let fittingSize = hostingController.view.fittingSize
        let targetSize = NSSize(width: max(520, fittingSize.width), height: max(320, fittingSize.height))
        window.setContentSize(targetSize)
    }

    private func finishDismissalIfNeeded() {
        guard !didClose else {
            return
        }

        didClose = true
        onDidClose()
    }
}
