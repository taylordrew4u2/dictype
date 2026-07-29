import Foundation
import AVFoundation
import Speech
import ApplicationServices
import AppKit

enum PermissionState {
    case granted, denied, notDetermined

    var label: String {
        switch self {
        case .granted:       return "Granted"
        case .denied:        return "Blocked"
        case .notDetermined: return "Needed"
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

    init() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.refresh()
        }
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
