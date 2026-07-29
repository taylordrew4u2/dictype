import Foundation
import AVFoundation
import Speech

final class DictationEngine: ObservableObject {

    @Published var isListening = false
    @Published var lastHeard = ""
    @Published var errorMessage: String?

    let typewriter = Typewriter()
    private lazy var differ = Differ(writer: typewriter)

    private let engine = AVAudioEngine()
    private var recognizer: SFSpeechRecognizer?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?

    private var onDeviceOnly = true
    private var consecutiveFailures = 0
    private var restarting = false
    private var stopped = true

    var localeID = "en-US"

    // MARK: - Control

    func start() {
        guard stopped else { return }
        stopped = false
        errorMessage = nil
        consecutiveFailures = 0
        differ.reset()

        guard let r = SFSpeechRecognizer(locale: Locale(identifier: localeID)) else {
            fail("No speech recognizer available for \(localeID).")
            return
        }
        guard r.isAvailable else {
            fail("The \(localeID) recognizer is temporarily unavailable.")
            return
        }
        if onDeviceOnly && !r.supportsOnDeviceRecognition {
            onDeviceOnly = false
        }
        recognizer = r

        beginSession()
    }

    func stop() {
        stopped = true
        restarting = false
        teardown()
        typewriter.clear()
        differ.reset()
        DispatchQueue.main.async { self.isListening = false }
    }

    // MARK: - Session

    private func beginSession() {
        guard let recognizer, !stopped else { return }
        restarting = false

        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        req.requiresOnDeviceRecognition = onDeviceOnly
        request = req

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)

        guard format.sampleRate > 0, format.channelCount > 0 else {
            fail("No usable microphone input was found.")
            return
        }

        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buf, _ in
            req.append(buf)
        }

        engine.prepare()
        do {
            try engine.start()
        } catch {
            fail("Could not start audio: \(error.localizedDescription)")
            return
        }

        DispatchQueue.main.async { self.isListening = true }

        task = recognizer.recognitionTask(with: req) { [weak self] result, error in
            guard let self, !self.stopped else { return }

            if let result {
                self.consecutiveFailures = 0
                let text = result.bestTranscription.formattedString
                DispatchQueue.main.async { self.lastHeard = text }
                self.differ.update(text)
                if result.isFinal {
                    self.differ.commit()
                    self.restart()
                }
            }

            if let error {
                let ns = error as NSError
                // 216 and 301 are ordinary cancellation codes during restart.
                if ns.code != 216 && ns.code != 301 {
                    self.consecutiveFailures += 1
                    if self.consecutiveFailures >= 5 {
                        self.fail("Speech recognition kept failing: \(ns.localizedDescription)")
                        return
                    }
                }
                self.restart()
            }
        }
    }

    private func restart() {
        guard !restarting, !stopped else { return }
        restarting = true
        teardown()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.beginSession()
        }
    }

    private func teardown() {
        engine.inputNode.removeTap(onBus: 0)
        if engine.isRunning { engine.stop() }
        request?.endAudio()
        task?.cancel()
        task = nil
        request = nil
    }

    private func fail(_ message: String) {
        stopped = true
        teardown()
        DispatchQueue.main.async {
            self.errorMessage = message
            self.isListening = false
        }
    }
}
