import AVFoundation
import Foundation
import Speech

// VoiceTranscriptionService owns the native audio capture and live speech recognition pipeline.
final class VoiceTranscriptionService {
    enum State: Equatable {
        case idle
        case preparing
        case listening
        case finishing
    }

    private let audioEngine = AVAudioEngine()
    private var speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var finishContinuation: CheckedContinuation<String, Error>?
    private var finishFallbackTask: Task<Void, Never>?
    private var latestTranscript = ""
    private var installedTapFormat: AVAudioFormat?

    var onTranscriptChange: ((String) -> Void)?

    private(set) var state: State = .idle

    @MainActor
    func start() throws {
        guard state == .idle else {
            throw VoiceTranscriptionServiceError.alreadyRunning
        }

        guard let speechRecognizer = SFSpeechRecognizer(locale: .autoupdatingCurrent) else {
            throw VoiceTranscriptionServiceError.recognizerUnavailable
        }

        guard speechRecognizer.isAvailable else {
            throw VoiceTranscriptionServiceError.recognitionUnavailable
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.taskHint = .dictation
        request.addsPunctuation = true
        if speechRecognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }

        latestTranscript = ""
        onTranscriptChange?("")
        self.speechRecognizer = speechRecognizer
        recognitionRequest = request
        state = .preparing

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        installTap(on: inputNode, format: format, request: request)

        do {
            recognitionTask = speechRecognizer.recognitionTask(with: request) { [weak self] result, error in
                Task { @MainActor in
                    self?.handleRecognitionUpdate(result: result, error: error)
                }
            }

            audioEngine.prepare()
            try audioEngine.start()
            state = .listening
        } catch {
            teardownRecognition(cancel: true)
            stopCapturingAudio()
            state = .idle
            throw error
        }
    }

    @MainActor
    func stopAndFinalize() async throws -> String {
        guard state == .listening || state == .preparing else {
            throw VoiceTranscriptionServiceError.notRunning
        }

        state = .finishing
        stopCapturingAudio()
        recognitionRequest?.endAudio()

        return try await withCheckedThrowingContinuation { continuation in
            finishContinuation = continuation
            scheduleFallbackCompletionIfNeeded()
        }
    }

    @MainActor
    func cancel() {
        resolveFinishIfNeeded(with: .failure(CancellationError()))
        teardownRecognition(cancel: true)
        stopCapturingAudio()
        latestTranscript = ""
        onTranscriptChange?("")
        state = .idle
    }

    private func installTap(
        on inputNode: AVAudioInputNode,
        format: AVAudioFormat,
        request: SFSpeechAudioBufferRecognitionRequest
    ) {
        if installedTapFormat != nil {
            inputNode.removeTap(onBus: 0)
        }

        installedTapFormat = format
        inputNode.installTap(onBus: 0, bufferSize: 1_024, format: format) { buffer, _ in
            request.append(buffer)
        }
    }

    @MainActor
    private func scheduleFallbackCompletionIfNeeded() {
        finishFallbackTask?.cancel()
        finishFallbackTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.2))
            await MainActor.run {
                self?.completeFromLatestTranscriptIfNeeded()
                self?.teardownRecognition(cancel: false)
                self?.state = .idle
            }
        }
    }

    @MainActor
    private func handleRecognitionUpdate(result: SFSpeechRecognitionResult?, error: Error?) {
        if let result {
            latestTranscript = result.bestTranscription.formattedString
            onTranscriptChange?(latestTranscript)

            if result.isFinal {
                completeFromLatestTranscriptIfNeeded()
                teardownRecognition(cancel: false)
                state = .idle
                return
            }
        }

        guard let error else {
            return
        }

        // Finalization can surface a terminal error after the best partial result was already delivered.
        if state == .finishing, !latestTranscript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            completeFromLatestTranscriptIfNeeded()
        } else {
            resolveFinishIfNeeded(with: .failure(error))
        }

        teardownRecognition(cancel: false)
        state = .idle
    }

    @MainActor
    private func completeFromLatestTranscriptIfNeeded() {
        let trimmedTranscript = latestTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTranscript.isEmpty else {
            resolveFinishIfNeeded(with: .failure(VoiceTranscriptionServiceError.noSpeechDetected))
            return
        }

        resolveFinishIfNeeded(with: .success(trimmedTranscript))
    }

    @MainActor
    private func resolveFinishIfNeeded(with result: Result<String, Error>) {
        finishFallbackTask?.cancel()
        finishFallbackTask = nil

        guard let finishContinuation else {
            return
        }

        self.finishContinuation = nil
        switch result {
        case let .success(transcript):
            finishContinuation.resume(returning: transcript)
        case let .failure(error):
            finishContinuation.resume(throwing: error)
        }
    }

    @MainActor
    private func stopCapturingAudio() {
        if installedTapFormat != nil {
            audioEngine.inputNode.removeTap(onBus: 0)
            installedTapFormat = nil
        }

        if audioEngine.isRunning {
            audioEngine.stop()
        }
    }

    @MainActor
    private func teardownRecognition(cancel: Bool) {
        if cancel {
            recognitionTask?.cancel()
        }

        recognitionTask = nil
        recognitionRequest = nil
        speechRecognizer = nil
    }
}

// VoiceTranscriptionServiceError keeps user-facing failures readable inside the launcher.
enum VoiceTranscriptionServiceError: LocalizedError {
    case alreadyRunning
    case notRunning
    case recognizerUnavailable
    case recognitionUnavailable
    case noSpeechDetected

    var errorDescription: String? {
        switch self {
        case .alreadyRunning:
            return "Voice transcription is already running."
        case .notRunning:
            return "Voice transcription is not running."
        case .recognizerUnavailable:
            return "Speech recognition is unavailable for the current system language."
        case .recognitionUnavailable:
            return "Speech recognition is temporarily unavailable on this Mac."
        case .noSpeechDetected:
            return "No speech was detected. Try again and press the voice shortcut when you're done."
        }
    }
}
