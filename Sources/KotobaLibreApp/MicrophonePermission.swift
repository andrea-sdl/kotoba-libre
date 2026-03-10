import AVFoundation
import Foundation

// This file centralizes microphone and media-capture permission checks used by SwiftUI and WebKit.
enum MediaCaptureAuthorization {
    static func authorizationStatus(for mediaType: AVMediaType) -> AVAuthorizationStatus {
        AVCaptureDevice.authorizationStatus(for: mediaType)
    }

    static func requestSystemAccess(
        for mediaType: AVMediaType,
        completion: @escaping @MainActor (AVAuthorizationStatus) -> Void
    ) {
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
        Self(status: MediaCaptureAuthorization.authorizationStatus(for: .audio))
    }

    static func requestSystemAccess(completion: @escaping @MainActor (Self) -> Void) {
        MediaCaptureAuthorization.requestSystemAccess(for: .audio) { status in
            completion(Self(status: status))
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
        }
    }
}
