import Foundation
import AVFoundation
import Speech
import ApplicationServices
import AppKit

enum PermissionState {
    case granted, denied, notDetermined

    var label: String {
        switch self {
        case .granted:       return "Ready"
        case .denied:        return "Needs attention"
        case .notDetermined: return "Pending"
        }
    }
}

final class Permissions: ObservableObject {
    @Published var microphone: PermissionState = .notDetermined
    @Published var speech: PermissionState = .notDetermined
    @Published var accessibility: PermissionState = .notDetermined

    private var timer: Timer?

    var allGranted: Bool {
        microphone == .granted && speech == .granted && accessibility == .granted
    }

    var grantedCount: Int {
        [microphone, speech, accessibility].filter { $0 == .granted }.count
    }

    private var activationObserver: NSObjectProtocol?

    init() {
        // refresh() starts the poll itself if anything is still outstanding.
        refresh()

        // Once setup is done the poll stops, but a permission can still be
        // revoked in System Settings. Re-checking when DicType comes back to the
        // front catches that at the moment the user returns from doing it.
        activationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.refresh()
        }
    }

    deinit {
        timer?.invalidate()
        if let activationObserver {
            NotificationCenter.default.removeObserver(activationObserver)
        }
    }

    /// Polls only while there is still something for the user to approve.
    ///
    /// The onboarding screen needs to turn green the moment a switch is flipped
    /// in System Settings, which nothing notifies us about. Polling forever
    /// afterwards just burns a wakeup a second for the life of the process.
    private func startPolling() {
        guard timer == nil, !allGranted else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    private func stopPolling() {
        timer?.invalidate()
        timer = nil
    }

    func refresh() {
        let mic: PermissionState
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:    mic = .granted
        case .notDetermined: mic = .notDetermined
        default:             mic = .denied
        }

        let spc: PermissionState
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized:    spc = .granted
        case .notDetermined: spc = .notDetermined
        default:             spc = .denied
        }

        let axs: PermissionState = AXIsProcessTrusted() ? .granted : .denied

        if mic != microphone { microphone = mic }
        if spc != speech { speech = spc }
        if axs != accessibility { accessibility = axs }

        if allGranted {
            stopPolling()
        } else {
            startPolling()
        }
    }

    // MARK: - Requests

    func requestMicrophone() {
        if microphone == .notDetermined {
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] _ in
                DispatchQueue.main.async { self?.refresh() }
            }
        } else {
            openPane("Privacy_Microphone")
        }
    }

    func requestSpeech() {
        if speech == .notDetermined {
            SFSpeechRecognizer.requestAuthorization { [weak self] _ in
                DispatchQueue.main.async { self?.refresh() }
            }
        } else {
            openPane("Privacy_SpeechRecognition")
        }
    }

    func requestAccessibility() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
        openPane("Privacy_Accessibility")
    }

    private func openPane(_ anchor: String) {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)")!
        NSWorkspace.shared.open(url)
    }
}
