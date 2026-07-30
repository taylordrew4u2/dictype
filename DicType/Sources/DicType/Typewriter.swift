import Foundation
import CoreGraphics

/// A single key event the typewriter wants to produce.
enum Keystroke: Equatable {
    case character(Character)
    case backspace
}

extension Character {
    /// Ends a sentence, so what precedes it can be treated as settled.
    var isSentenceEnd: Bool { self == "." || self == "!" || self == "?" }
}

/// Emits synthesized keystrokes at a human, log-normally distributed cadence.
///
/// The typewriter owns the text it is meant to have produced, rather than a
/// queue of characters to append. Speech recognisers revise what they have
/// already reported — "the cow" becomes "the cows" once more audio arrives — so
/// the visible output has to be able to move backwards, not only forwards.
///
/// But it must not move backwards very far. A recogniser keeps revising its
/// whole utterance until it declares the result final, so unbounded correction
/// means a late change near the start wipes out everything typed since.
///
/// Four pieces of state describe the balance:
///
///   text        the full intended output
///   emitted     how much of `text` has physically been typed
///   liveStart   where `text` stops being final and starts mirroring the
///               transcript tail; nothing before it is ever backspaced
///   baseline    the transcript prefix already treated as final
///
/// `baseline` is a string rather than an index because the transcript changes
/// length as the recogniser revises, so an index into our output stops pointing
/// at the same place in the transcript. Holding the settled prefix as text keeps
/// the two exactly in step.
///
/// A revision only costs backspaces for characters that were actually typed, and
/// never more than `revisionWindow` of them. Revising text that is still waiting
/// its turn is free, which is the common case when speech outruns the fingers.
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
    private var backspaceDebt = 0

    /// Where `text` stops being final and starts mirroring the recogniser's
    /// transcript tail. Nothing before this can ever be backspaced.
    private var liveStart = 0

    /// The transcript prefix already treated as final.
    ///
    /// The live region of `text` always mirrors the transcript tail *exactly*,
    /// which is what keeps the two in step. Settling therefore cannot be a bare
    /// index: the transcript changes length as the recogniser revises, so an
    /// index into our output stops pointing at the same place in the transcript.
    /// Holding the settled prefix as a string keeps the mapping exact.
    private var baseline = ""

    private let lock = NSLock()
    private let src = CGEventSource(stateID: .combinedSessionState)
    private let workQueue = DispatchQueue(label: "com.taylordrew.dictype.typewriter")

    /// Virtual key code for Delete (backspace). Carbon's kVK_Delete.
    private let deleteKey: CGKeyCode = 51

    /// How far back the recogniser may still revise, in characters.
    ///
    /// Roughly the last four words. This is the hard ceiling on how much text a
    /// single correction can erase; everything older has settled. Raising it
    /// buys more accurate corrections at the cost of more visible rewriting.
    private let revisionWindow = 24

    init() { schedule(after: 30) }

    // MARK: - Input

    /// Takes the recogniser's latest transcript for the current utterance.
    ///
    /// The whole transcript is passed every time, not just the new part. The
    /// live region of `text` is made to mirror its tail exactly, so the two stay
    /// in step; only characters already on screen that no longer match are
    /// scheduled for deletion.
    func setLive(_ incoming: String) {
        lock.lock()
        defer { lock.unlock() }

        // Settle first, using what has actually been typed since the last call.
        // Doing this afterwards instead would leave the floor a beat behind and
        // let a correction reach back further than intended.
        settle()

        let tail: [Character]
        if incoming.hasPrefix(baseline) {
            tail = Array(incoming.dropFirst(baseline.count))
        } else {
            // The recogniser rewrote something we had already settled. Neither
            // erasing it nor appending its version is right — one destroys text
            // the user watched appear, the other duplicates it. Keep ours, adopt
            // its transcript as the new baseline, and emit nothing for the
            // overlap. Whatever it says next simply continues from here.
            baseline = incoming
            liveStart = text.count
            tail = []
        }

        let existing = Array(text[liveStart...])
        var i = 0
        while i < existing.count && i < tail.count && existing[i] == tail[i] { i += 1 }

        // Absolute index of the first character the two versions disagree on.
        let divergence = liveStart + i

        // Only characters already on screen need deleting. `emitted` is the
        // logical cursor; the physical one sits `backspaceDebt` further right
        // until the debt is paid, so adding to the debt keeps both consistent.
        if emitted > divergence {
            backspaceDebt += emitted - divergence
            emitted = divergence
        }

        text.replaceSubrange(liveStart..., with: tail)
    }

    /// Moves the settled boundary forward so the recogniser can no longer take
    /// back text the user has already watched appear.
    ///
    /// A recogniser revises its whole utterance until it declares the result
    /// final, which can be a long time. Left unbounded, a late change near the
    /// start — a capitalisation, a re-segmented word — diverges at a low index
    /// and erases everything typed since. That is the "it goes back and erases
    /// what I just said" behaviour.
    ///
    /// Two rules move the boundary, and nothing behind it is ever backspaced:
    ///
    ///   * **Punctuation.** A full stop, question mark or exclamation mark that
    ///     has already been typed settles the sentence it ends. Saying "period"
    ///     locks in what came before it.
    ///   * **Distance.** Anything further back than `revisionWindow` characters
    ///     settles anyway, because recognisers revise the last word or two
    ///     constantly and older text almost never.
    ///
    /// Only text already on screen settles. Text still queued costs nothing to
    /// revise, so it stays free, which is the common case when speech outruns
    /// the fingers.
    private func settle() {
        let typed = min(emitted, text.count)
        var split = liveStart

        // Rule 1: the last sentence terminator that has actually been typed.
        var i = typed - 1
        while i >= liveStart {
            if text[i].isSentenceEnd {
                split = i + 1
                break
            }
            i -= 1
        }

        // Rule 2: distance from the live edge.
        split = max(split, min(typed, text.count - revisionWindow))

        guard split > liveStart else { return }
        baseline.append(contentsOf: text[liveStart..<split])
        liveStart = split
    }

    /// Drops settled characters from the front so a long dictation session does
    /// not grow the buffer without bound. Indices shift, so `emitted` moves too.
    private func trimSettledPrefix() {
        guard liveStart > 0, backspaceDebt == 0, emitted >= liveStart else { return }
        text.removeFirst(liveStart)
        emitted -= liveStart
        liveStart = 0
    }

    /// Marks everything typed so far as final and starts a new utterance.
    ///
    /// Nothing before this point can be revised afterwards, so a later
    /// recognition pass can never backspace into an earlier sentence.
    func commitLive() {
        lock.lock()
        text.append(" ")
        liveStart = text.count
        // A finished utterance means the next transcript starts from nothing.
        baseline = ""
        lock.unlock()
    }

    /// Drops all pending output. Does not undo anything already typed.
    func clear() {
        lock.lock()
        text.removeAll()
        emitted = 0
        liveStart = 0
        baseline = ""
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

        // Idle. Everything settled has been typed, so the finalised prefix can be
        // dropped and the buffer stays bounded over a long dictation session.
        trimSettledPrefix()
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
