import Foundation
import CoreGraphics

enum Op {
    case char(Character)
}

/// Emits synthesized keystrokes at a human, log-normally distributed cadence.
final class Typewriter {

    /// Average typing speed in words per minute.
    var targetWPM: Double = 62

    /// Rhythm variability. 0 is metronomic, 0.6+ looks erratic.
    var jitterSigma: Double = 0.42

    /// Per-word chance of a 0.2–1.0s thinking pause.
    var hesitationOdds: Double = 0.11

    /// Chance of a tiny micro-pause before a word boundary.
    var microPauseOdds: Double = 0.09

    private var queue: [Op] = []
    private let lock = NSLock()
    private let src = CGEventSource(stateID: .combinedSessionState)
    private let workQueue = DispatchQueue(label: "com.taylordrew.dictype.typewriter")
    private var running = true

    init() { schedule(after: 30) }

    func enqueue(_ ops: [Op]) {
        lock.lock(); queue.append(contentsOf: ops); lock.unlock()
    }

    func clear() {
        lock.lock(); queue.removeAll(); lock.unlock()
    }

    /// Characters still waiting to be typed.
    var backlog: Int {
        lock.lock(); defer { lock.unlock() }
        return queue.count
    }

    // MARK: - Cadence

    /// Standard WPM assumes a five-character word including its trailing space.
    private var baseIntervalMs: Double { 60_000.0 / (targetWPM * 5.0) }

    /// Box-Muller transform to a standard normal deviate.
    private func gaussian() -> Double {
        let u1 = Double.random(in: Double.leastNonzeroMagnitude...1)
        let u2 = Double.random(in: 0...1)
        return (-2 * Foundation.log(u1)).squareRoot() * cos(2 * .pi * u2)
    }

    /// Milliseconds to wait after emitting `c`, before the next keystroke.
    private func interval(after c: Character) -> Int {
        var ms = baseIntervalMs * exp(jitterSigma * gaussian())
        ms *= Double.random(in: 0.72...1.38)           // bursty, uneven rhythm

        switch c {
        case ".", "!", "?":
            ms *= Double.random(in: 3.2...5.0)         // end of thought
        case ",", ";", ":":
            ms *= Double.random(in: 1.8...2.8)         // clause break
        case " ":
            ms *= Double.random(in: 1.05...1.8)        // word boundary
            if Double.random(in: 0...1) < hesitationOdds {
                ms += Double.random(in: 180...950)     // hesitation
            }
            if Double.random(in: 0...1) < microPauseOdds {
                ms += Double.random(in: 70...260)      // tiny micro-pause
            }
        case let x where x.isUppercase:
            ms *= Double.random(in: 1.15...1.5)        // shift travel
        case let x where x.isNumber:
            ms *= Double.random(in: 1.25...1.8)        // number row reach
        default:
            if Double.random(in: 0...1) < 0.07 {
                ms += Double.random(in: 30...140)      // occasional hitch
            }
        }

        // Catch up when speech has outrun the fingers.
        let depth = backlog
        if depth > 220      { ms *= 0.45 }
        else if depth > 120 { ms *= 0.65 }
        else if depth > 60  { ms *= 0.85 }

        return Int(min(max(ms, 14), 2_500))
    }

    // MARK: - Loop

    private func schedule(after ms: Int) {
        guard running else { return }
        workQueue.asyncAfter(deadline: .now() + .milliseconds(ms)) { [weak self] in
            self?.tick()
        }
    }

    private func tick() {
        lock.lock()
        guard !queue.isEmpty else {
            lock.unlock()
            schedule(after: 25)                         // idle poll
            return
        }
        let op = queue.removeFirst()
        lock.unlock()

        switch op {
        case .char(let c):
            post(virtualKey: 0, unicode: Array(String(c).utf16))
            schedule(after: interval(after: c))
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

/// Diffs successive partial transcripts against what has already been typed.
final class Differ {
    private var typed: String = ""
    private let writer: Typewriter

    init(writer: Typewriter) { self.writer = writer }

    func update(_ incoming: String) {
        let a = Array(typed), b = Array(incoming)
        var i = 0
        while i < a.count && i < b.count && a[i] == b[i] { i += 1 }

        let newChars = b[i...]
        if !newChars.isEmpty {
            writer.enqueue(newChars.map { Op.char($0) })
        }
        typed = incoming
    }

    func commit() {
        writer.enqueue([.char(" ")])
        typed = ""
    }

    func reset() { typed = "" }
}
