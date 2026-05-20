import AVFoundation
import Foundation
import Speech

// This file centralizes microphone and media-capture permission checks used by SwiftUI and WebKit.
enum PrivacyUsageDescription {
    static let microphoneKey = "NSMicrophoneUsageDescription"
    static let cameraKey = "NSCameraUsageDescription"
    static let speechRecognitionKey = "NSSpeechRecognitionUsageDescription"

    static var hasMicrophoneDescription: Bool {
        hasDescription(for: microphoneKey)
    }

    static var hasSpeechRecognitionDescription: Bool {
        hasDescription(for: speechRecognitionKey)
    }

    static func hasMediaCaptureDescription(for mediaType: AVMediaType) -> Bool {
        switch mediaType {
        case .audio:
            return hasDescription(for: microphoneKey)
        case .video:
            return hasDescription(for: cameraKey)
        default:
            return false
        }
    }

    private static func hasDescription(for key: String) -> Bool {
        guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String else {
            return false
        }

        return !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

enum MediaCaptureAuthorization {
    static func authorizationStatus(for mediaType: AVMediaType) -> AVAuthorizationStatus {
        AVCaptureDevice.authorizationStatus(for: mediaType)
    }

    static func requestSystemAccess(
        for mediaType: AVMediaType,
        completion: @escaping @MainActor (AVAuthorizationStatus) -> Void
    ) {
        guard PrivacyUsageDescription.hasMediaCaptureDescription(for: mediaType) else {
            Task { @MainActor in
                completion(.denied)
            }
            return
        }

        let currentStatus = authorizationStatus(for: mediaType)
        guard currentStatus == .notDetermined else {
            Task { @MainActor in
                completion(currentStatus)
            }
            return
        }

        AVCaptureDevice.requestAccess(for: mediaType) { _ in
            Task { @MainActor in
                completion(authorizationStatus(for: mediaType))
            }
        }
    }
}

// The UI uses this reduced state to explain what macOS currently allows for microphone input.
enum MicrophonePermissionState: Equatable {
    case notDetermined
    case granted
    case denied
    case restricted
    case unavailableInLaunchMode

    init(status: AVAuthorizationStatus) {
        switch status {
        case .notDetermined:
            self = .notDetermined
        case .authorized:
            self = .granted
        case .denied:
            self = .denied
        case .restricted:
            self = .restricted
        @unknown default:
            self = .denied
        }
    }

    static var current: Self {
        guard PrivacyUsageDescription.hasMicrophoneDescription else {
            return .unavailableInLaunchMode
        }

        return Self(status: MediaCaptureAuthorization.authorizationStatus(for: .audio))
    }

    static func requestSystemAccess(completion: @escaping @MainActor (Self) -> Void) {
        guard PrivacyUsageDescription.hasMicrophoneDescription else {
            Task { @MainActor in
                completion(.unavailableInLaunchMode)
            }
            return
        }

        MediaCaptureAuthorization.requestSystemAccess(for: .audio) { status in
            completion(Self(status: status))
        }
    }

    static func requestSystemAccess() async -> Self {
        await withCheckedContinuation { continuation in
            requestSystemAccess { updatedState in
                continuation.resume(returning: updatedState)
            }
        }
    }

    var statusMessage: String {
        switch self {
        case .notDetermined:
            return "Microphone access has not been requested yet. Kotoba Libre only asks for it so LibreChat can use its microphone input."
        case .granted:
            return "Microphone access is enabled. LibreChat can use its microphone input inside Kotoba Libre."
        case .denied:
            return "Microphone access is turned off. LibreChat's microphone input will stay unavailable until you allow Kotoba Libre in System Settings > Privacy & Security > Microphone."
        case .restricted:
            return "Microphone access is restricted by macOS or a device policy. LibreChat's microphone input will stay unavailable until that restriction is removed."
        case .unavailableInLaunchMode:
            return "Microphone permission is unavailable in this launch mode. Run the packaged app bundle so macOS can read Kotoba Libre's privacy description."
        }
    }
}

// The voice launcher also needs speech recognition permission to transcribe audio into a prompt.
enum SpeechRecognitionPermissionState: Equatable {
    case notDetermined
    case granted
    case denied
    case restricted
    case unavailableInLaunchMode

    init(status: SFSpeechRecognizerAuthorizationStatus) {
        switch status {
        case .notDetermined:
            self = .notDetermined
        case .authorized:
            self = .granted
        case .denied:
            self = .denied
        case .restricted:
            self = .restricted
        @unknown default:
            self = .denied
        }
    }

    static var current: Self {
        guard PrivacyUsageDescription.hasSpeechRecognitionDescription else {
            return .unavailableInLaunchMode
        }

        return Self(status: SFSpeechRecognizer.authorizationStatus())
    }

    static func requestSystemAccess(completion: @escaping @MainActor (Self) -> Void) {
        guard PrivacyUsageDescription.hasSpeechRecognitionDescription else {
            Task { @MainActor in
                completion(.unavailableInLaunchMode)
            }
            return
        }

        let currentStatus = current
        guard currentStatus == .notDetermined else {
            Task { @MainActor in
                completion(currentStatus)
            }
            return
        }

        SFSpeechRecognizer.requestAuthorization { status in
            Task { @MainActor in
                completion(Self(status: status))
            }
        }
    }

    static func requestSystemAccess() async -> Self {
        await withCheckedContinuation { continuation in
            requestSystemAccess { updatedState in
                continuation.resume(returning: updatedState)
            }
        }
    }

    var statusMessage: String {
        switch self {
        case .notDetermined:
            return "Speech recognition access has not been requested yet. Kotoba Libre needs it to turn voice launcher audio into a prompt."
        case .granted:
            return "Speech recognition access is enabled. Voice launcher prompts can be transcribed on this Mac."
        case .denied:
            return "Speech recognition access is turned off. Voice mode stays unavailable until you allow Kotoba Libre in System Settings > Privacy & Security > Speech Recognition."
        case .restricted:
            return "Speech recognition access is restricted by macOS or a device policy. Voice mode stays unavailable until that restriction is removed."
        case .unavailableInLaunchMode:
            return "Speech recognition permission is unavailable in this launch mode. Run the packaged app bundle so macOS can read Kotoba Libre's privacy description."
        }
    }
}
