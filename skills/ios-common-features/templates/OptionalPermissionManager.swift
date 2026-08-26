import AVFoundation
import CoreLocation
import UserNotifications

/// Non-blocking permission requests. Every function returns whether the
/// permission is granted — never throws, never blocks a feature's existence.
/// Callers must always provide a working degraded path for the `false` case.
public enum OptionalPermissionManager {

    /// Camera access (e.g. for a receipt/document scanner). Falls back to
    /// photo-library picking when denied — never disable the whole feature.
    public static func requestCamera() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            return true
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .video)
        case .denied, .restricted:
            return false
        @unknown default:
            return false
        }
    }

    /// Microphone access. Falls back to a silent/no-audio mode when denied.
    public static func requestMicrophone() async -> Bool {
        switch AVAudioApplication.shared.recordPermission {
        case .granted:
            return true
        case .undetermined:
            return await AVAudioApplication.requestRecordPermission()
        case .denied:
            return false
        @unknown default:
            return false
        }
    }

    /// When-In-Use location only — never request "Always" unless a specific,
    /// disclosed background feature genuinely needs it.
    public static func requestLocationWhenInUse(manager: CLLocationManager = .init()) async -> Bool {
        await withCheckedContinuation { continuation in
            let delegate = LocationPermissionDelegate { granted in
                continuation.resume(returning: granted)
            }
            manager.delegate = delegate
            switch manager.authorizationStatus {
            case .authorizedWhenInUse, .authorizedAlways:
                continuation.resume(returning: true)
            case .notDetermined:
                manager.requestWhenInUseAuthorization()
                // delegate resumes the continuation on the callback
                objc_setAssociatedObject(manager, &AssociatedKeys.delegate, delegate, .OBJC_ASSOCIATION_RETAIN)
            default:
                continuation.resume(returning: false)
            }
        }
    }

    /// Notification permission — request only at the point the user schedules
    /// their first reminder/alarm, never on cold launch.
    public static func requestNotifications(options: UNAuthorizationOptions = [.alert, .sound, .badge]) async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: options)) ?? false
    }

    /// Current notification status, for deciding whether to show the nudge
    /// banner vs. the native prompt (denied → banner opens Settings;
    /// notDetermined → banner opens the native prompt directly).
    public static func notificationStatus() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }
}

private enum AssociatedKeys {
    static var delegate = "OptionalPermissionManager.locationDelegate"
}

private final class LocationPermissionDelegate: NSObject, CLLocationManagerDelegate {
    private let onResult: (Bool) -> Void
    private var didRespond = false

    init(onResult: @escaping (Bool) -> Void) {
        self.onResult = onResult
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard !didRespond else { return }
        didRespond = true
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            onResult(true)
        default:
            onResult(false)
        }
    }
}
