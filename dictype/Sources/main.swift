// dictype.swift
// Live dictation -> synthesized keystrokes, typed one character at a time.
//
// Build:   swiftc -O dictype.swift -o dictype
// Run:     ./dictype            (from Terminal.app or iTerm)
// Stop:    Ctrl-C
//
// Permissions (granted to the TERMINAL app, since this is a CLI binary):
//   System Settings > Privacy & Security > Microphone        -> Terminal
//   System Settings > Privacy & Security > Speech Recognition -> Terminal
//   System Settings > Privacy & Security > Accessibility      -> Terminal
//
// Behavior: partial transcripts are diffed against what has already been
// typed. Divergent tail is erased with backspaces, new tail is queued and
// emitted at `charDelayMs` per character into whatever app has focus.

import Foundation
import AVFoundation
import Speech
import ApplicationServices

// MARK: - Config

let charDelayMs   = 40          // typing speed, ms per character
let localeID      = "en-US"
let onDeviceOnly  = true        // false = allow server-side recognition

// MARK: - Keystroke emitter

enum Op {
    case char(Character)
    case backspace
}

final class Typewriter {
    private var queue: [Op] = []
    private let lock = NSLock()
    private let src = CGEventSource(stateID: .combinedSessionState)
    private var timer: DispatchSourceTimer?

    init() {
        let t = DispatchSource.makeTimerSource(queue: DispatchQueue(label: "typewriter"))
        t.schedule(deadline: .now(), repeating: .milliseconds(charDelayMs))
        t.setEventHandler { [weak self] in self?.drain() }
        t.resume()
        timer = t
    }

    func enqueue(_ ops: [Op]) {
        lock.lock(); queue.append(contentsOf: ops); lock.unlock()
    }

    private func drain() {
        lock.lock()
        guard !queue.isEmpty else { lock.unlock(); return }
        let op = queue.removeFirst()
        lock.unlock()

        switch op {
        case .backspace:
            post(virtualKey: 51, unicode: nil)   // kVK_Delete
        case .char(let c):
            post(virtualKey: 0, unicode: Array(String(c).utf16))
        }
    }

    private func post(virtualKey: CGKeyCode, unicode: [UniChar]?) {
        for isDown in [true, false] {
            guard let e = CGEvent(keyboardEventSource: src,
                                  virtualKey: virtualKey,
                                  keyDown: isDown) else { continue }
            if var u = unicode {
                e.keyboardSetUnicodeString(stringLength: u.count, unicodeString: &u)
            }
            e.post(tap: .cghidEventTap)
        }
    }
}

// MARK: - Transcript differ

final class Differ {
    private var typed: String = ""
    private let writer: Typewriter

    init(writer: Typewriter) { self.writer = writer }

    /// Feed a (possibly revised) partial transcript.
    func update(_ incoming: String) {
        let a = Array(typed), b = Array(incoming)
        var i = 0
        while i < a.count && i < b.count && a[i] == b[i] { i += 1 }

        var ops: [Op] = []
        ops.append(contentsOf: Array(repeating: Op.backspace, count: a.count - i))
        ops.append(contentsOf: b[i...].map { Op.char($0) })

        if !ops.isEmpty { writer.enqueue(ops) }
        typed = incoming
    }

    /// Call when a sentence is finalized; commits text and resets state.
    func commit() {
        writer.enqueue([.char(" ")])
        typed = ""
    }
}

// MARK: - Recognition session

final class Session {
    private let engine = AVAudioEngine()
    private let recognizer: SFSpeechRecognizer
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private let differ: Differ

    init?(differ: Differ) {
        guard let r = SFSpeechRecognizer(locale: Locale(identifier: localeID)) else { return nil }
        self.recognizer = r
        self.differ = differ
    }

    func start() throws {
        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        if onDeviceOnly { req.requiresOnDeviceRecognition = true }
        request = req

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buf, _ in
            req.append(buf)
        }

        engine.prepare()
        try engine.start()

        task = recognizer.recognitionTask(with: req) { [weak self] result, error in
            guard let self else { return }
            if let result {
                self.differ.update(result.bestTranscription.formattedString)
                if result.isFinal {
                    self.differ.commit()
                    self.restart()
                }
            }
            if error != nil { self.restart() }
        }
    }

    private func restart() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        request?.endAudio()
        task?.cancel()
        task = nil
        request = nil
        // brief pause avoids hammering the recognizer on repeated errors
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            try? self?.start()
        }
    }
}

// MARK: - Entry

func requireAccessibility() {
    let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
    if !AXIsProcessTrustedWithOptions(opts) {
        FileHandle.standardError.write("Grant Accessibility to this terminal, then rerun.\n".data(using: .utf8)!)
        exit(1)
    }
}

requireAccessibility()

let writer = Typewriter()
let differ = Differ(writer: writer)
guard let session = Session(differ: differ) else {
    FileHandle.standardError.write("Recognizer unavailable for locale \(localeID).\n".data(using: .utf8)!)
    exit(1)
}

SFSpeechRecognizer.requestAuthorization { status in
    guard status == .authorized else {
        FileHandle.standardError.write("Speech recognition not authorized.\n".data(using: .utf8)!)
        exit(1)
    }
    DispatchQueue.main.async {
        do {
            try session.start()
            print("Listening. Focus a text field. Ctrl-C to quit.")
        } catch {
            FileHandle.standardError.write("Audio start failed: \(error)\n".data(using: .utf8)!)
            exit(1)
        }
    }
}

RunLoop.main.run()
