import Foundation
import AVFoundation
import Speech

/// Captures the microphone, runs speech recognition, and feeds the recogniser's
/// output to the typewriter.
///
/// Every mutable property here is confined to the main thread. The recognition
/// callback arrives on a queue of the Speech framework's choosing, so it copies
/// what it needs and hops to main before touching engine state — previously it
/// raced with `start()` and `stop()` over `stopped`, `restarting` and
/// `consecutiveFailures`.
final class DictationEngine: ObservableObject {

    @Published var isListening = false
    @Published var lastHeard = ""
    @Published var errorMessage: String?

    let typewriter = Typewriter()

    private let engine = AVAudioEngine()
    private var recognizer: SFSpeechRecognizer?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?

    private var onDeviceOnly = true
    private var consecutiveFailures = 0
    private var restarting = false
    private var stopped = true

    /// Identifies the recognition session a callback belongs to.
    ///
    /// Cancelling a task does not guarantee it stops calling back, so a late
    /// result from a session we have already torn down can arrive after the next
    /// one has started. Comparing generations discards those.
    private var generation = 0

    var localeID = "en-US"

    // MARK: - Control

    func start() {
        assertMain()
        guard stopped else { return }
        stopped = false
        errorMessage = nil
        consecutiveFailures = 0
        typewriter.clear()

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
        assertMain()
        stopped = true
        restarting = false
        generation += 1
        teardown()
        typewriter.clear()
        isListening = false
    }

    // MARK: - Session

    private func beginSession() {
        assertMain()
        guard let recognizer, !stopped else { return }
        restarting = false

        generation += 1
        let session = generation

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
        // Runs on a realtime audio thread. `append` is the only call made from
        // there and is safe on it; nothing else in this class is touched.
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

        isListening = true

        task = recognizer.recognitionTask(with: req) { [weak self] result, error in
            // Read what is needed here, on whichever queue Speech used, then
            // hand plain values to the main thread. The result object itself is
            // not carried across.
            let transcript = result?.bestTranscription.formattedString
            let isFinal = result?.isFinal ?? false
            DispatchQueue.main.async {
                self?.handle(session: session,
                             transcript: transcript,
                             isFinal: isFinal,
                             error: error)
            }
        }
    }

    private func handle(session: Int,
                        transcript: String?,
                        isFinal: Bool,
                        error: Error?) {
        assertMain()
        guard session == generation, !stopped else { return }

        if let transcript {
            consecutiveFailures = 0
            lastHeard = transcript
            typewriter.setLive(transcript)
            if isFinal {
                typewriter.commitLive()
                restart()
                return
            }
        }

        if let error {
            let ns = error as NSError
            // 216 and 301 are ordinary cancellation codes during restart.
            if ns.code != 216 && ns.code != 301 {
                consecutiveFailures += 1
                if consecutiveFailures >= 5 {
                    fail("Speech recognition kept failing: \(ns.localizedDescription)")
                    return
                }
            }
            restart()
        }
    }

    private func restart() {
        assertMain()
        guard !restarting, !stopped else { return }
        restarting = true
        generation += 1
        teardown()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.beginSession()
        }
    }

    private func teardown() {
        assertMain()
        engine.inputNode.removeTap(onBus: 0)
        if engine.isRunning { engine.stop() }
        request?.endAudio()
        task?.cancel()
        task = nil
        request = nil
    }

    private func fail(_ message: String) {
        assertMain()
        stopped = true
        generation += 1
        teardown()
        errorMessage = message
        isListening = false
    }

    /// The engine is single-threaded by design. This catches a caller that
    /// forgets, in debug only, so a mistake never crashes a shipped build.
    private func assertMain() {
        #if DEBUG
        dispatchPrecondition(condition: .onQueue(.main))
        #endif
    }
}
