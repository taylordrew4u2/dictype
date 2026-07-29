import Foundation
import CoreGraphics

/// A single key event the typewriter wants to produce.
enum Keystroke: Equatable {
    case character(Character)
    case backspace
}

/// Emits synthesized keystrokes at a human, log-normally distributed cadence.
///
/// The typewriter owns the text it is meant to have produced, rather than a
/// queue of characters to append. Speech recognisers revise what they have
/// already reported — "the cow" becomes "the cows" once more audio arrives — so
/// the visible output has to be able to move backwards, not only forwards.
///
/// Three pieces of state describe that:
///
///   text           the full intended output
///   emitted        how much of `text` has physically been typed
///   revisableFrom  index before which text is final and must never be undone
///
/// A revision only costs backspaces for characters that were actually typed.
/// Revising text that is still waiting its turn is free, which is the common
/// case when speech outruns the fingers.
final class Typewriter {

    // MARK: - Tunables

    /// Average typing speed in words per minute.
    ///
    /// Written from the UI and read on the typing queue, so it is guarded.
    var targetWPM: Double {
        get { settingsLock.lock(); defer { settingsLock.unlock() }; return _targetWPM }
        set { settingsLock.lock(); _targetWPM = newValue; settingsLock.unlock() }
    }

    /// Rhythm variability. 0 is metronomic, 0.6+ looks erratic.
    var jitterSigma: Double {
        get { settingsLock.lock(); defer { settingsLock.unlock() }; return _jitterSigma }
        set { settingsLock.lock(); _jitterSigma = newValue; settingsLock.unlock() }
    }

    /// Per-word chance of a 0.2–1.0s thinking pause.
    private let hesitationOdds: Double = 0.11

    /// Chance of a tiny micro-pause before a word boundary.
    private let microPauseOdds: Double = 0.09

    private var _targetWPM: Double = 62
    private var _jitterSigma: Double = 0.42
    private let settingsLock = NSLock()

    // MARK: - Output state

    private var text: [Character] = []
    private var emitted = 0
    private var revisableFrom = 0
    private var backspaceDebt = 0

    private let lock = NSLock()
    private let src = CGEventSource(stateID: .combinedSessionState)
    private let workQueue = DispatchQueue(label: "com.taylordrew.dictype.typewriter")

    /// Virtual key code for Delete (backspace). Carbon's kVK_Delete.
    private let deleteKey: CGKeyCode = 51

    init() { schedule(after: 30) }

    // MARK: - Input

    /// Replaces the revisable tail with `incoming`.
    ///
    /// Call this with each partial transcript. Characters shared with what is
    /// already on screen are left alone; anything typed past the point where the
    /// two diverge is scheduled for deletion.
    func setLive(_ incoming: String) {
        let new = Array(incoming)

        lock.lock()
        defer { lock.unlock() }

        let existing = Array(text[revisableFrom...])
        var i = 0
        while i < existing.count && i < new.count && existing[i] == new[i] { i += 1 }

        // Absolute index of the first character the two versions disagree on.
        let divergence = revisableFrom + i

        // Only characters already on screen need deleting. `emitted` is the
        // logical cursor; the physical one sits `backspaceDebt` further right
        // until the debt is paid, so adding to the debt keeps both consistent.
        if emitted > divergence {
            backspaceDebt += emitted - divergence
            emitted = divergence
        }

        text.replaceSubrange(revisableFrom..., with: new)
    }

    /// Marks everything typed so far as final and starts a new utterance.
    ///
    /// Nothing before this point can be revised afterwards, so a later
    /// recognition pass can never backspace into an earlier sentence.
    func commitLive() {
        lock.lock()
        text.append(" ")
        revisableFrom = text.count
        lock.unlock()
    }

    /// Drops all pending output. Does not undo anything already typed.
    func clear() {
        lock.lock()
        text.removeAll()
        emitted = 0
        revisableFrom = 0
        backspaceDebt = 0
        lock.unlock()
    }

    /// Keystrokes still owed, counting deletions.
    var backlog: Int {
        lock.lock(); defer { lock.unlock() }
        return (text.count - emitted) + backspaceDebt
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

        return clampInterval(ms)
    }

    /// Corrections run quicker than composition — people delete in a burst.
    private func deleteInterval() -> Int {
        clampInterval(baseIntervalMs * Double.random(in: 0.35...0.7))
    }

    private func clampInterval(_ ms: Double) -> Int {
        var ms = ms

        // Catch up when speech has outrun the fingers.
        let depth = backlog
        if depth > 220      { ms *= 0.45 }
        else if depth > 120 { ms *= 0.65 }
        else if depth > 60  { ms *= 0.85 }

        return Int(min(max(ms, 14), 2_500))
    }

    // MARK: - Loop

    private func schedule(after ms: Int) {
        workQueue.asyncAfter(deadline: .now() + .milliseconds(ms)) { [weak self] in
            self?.tick()
        }
    }

    /// Advances the state machine one step and reports what to type.
    ///
    /// Split out from `tick` so the revision logic — the part that can corrupt
    /// the user's text if it is wrong — can be tested without posting real
    /// keyboard events.
    func nextKeystroke() -> Keystroke? {
        lock.lock()
        defer { lock.unlock() }

        // Deletions come first: until the debt is paid the characters on screen
        // past the cursor are stale, so typing over them would compound the error.
        if backspaceDebt > 0 {
            backspaceDebt -= 1
            return .backspace
        }

        if emitted < text.count {
            let c = text[emitted]
            emitted += 1
            return .character(c)
        }

        // Idle. Everything committed has been typed, so the finalised prefix can
        // be dropped and the buffer stays bounded over a long dictation session.
        if revisableFrom > 0 {
            text.removeFirst(revisableFrom)
            emitted -= revisableFrom
            revisableFrom = 0
        }
        return nil
    }

    private func tick() {
        guard let stroke = nextKeystroke() else {
            schedule(after: 25)                        // idle poll
            return
        }

        switch stroke {
        case .backspace:
            post(virtualKey: deleteKey, unicode: nil)
            schedule(after: deleteInterval())
        case .character(let c):
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
