import XCTest
@testable import DicType

/// Exercises the revision state machine without posting real keyboard events.
///
/// The failure that matters is emitting more backspaces than the app itself
/// typed: that would delete text the user wrote by hand. `Screen` models the
/// target text field and fails the test if that ever happens.
final class TypewriterTests: XCTestCase {

    /// Stands in for the text field the keystrokes land in.
    private struct Screen {
        private(set) var buffer: String
        private let preexistingCount: Int
        private var owned = 0
        private(set) var overDeletions = 0

        init(preexisting: String = "") {
            buffer = preexisting
            preexistingCount = preexisting.count
        }

        mutating func apply(_ k: Keystroke) {
            switch k {
            case .backspace:
                if owned == 0 { overDeletions += 1 }
                if !buffer.isEmpty { buffer.removeLast() }
                owned = max(0, owned - 1)
            case .character(let c):
                buffer.append(c)
                owned += 1
            }
        }

        /// Everything the app typed, excluding whatever was already there.
        var typed: String { String(buffer.dropFirst(preexistingCount)) }

        /// Whatever was already there, which must never be touched.
        var untouched: String { String(buffer.prefix(preexistingCount)) }
    }

    /// Drains the typewriter onto the screen. Returns once it goes idle.
    private func drain(_ tw: Typewriter, into screen: inout Screen) {
        for _ in 0..<100_000 {
            guard let k = tw.nextKeystroke() else { return }
            screen.apply(k)
        }
        XCTFail("typewriter never went idle")
    }

    // MARK: - The reported bug

    func testRevisingAWordThatIsAlreadyFullyTyped() {
        let tw = Typewriter()
        var screen = Screen()

        tw.setLive("the cow jumped")
        drain(tw, into: &screen)
        XCTAssertEqual(screen.typed, "the cow jumped")

        // The recogniser hears the plural once more audio arrives. Before the
        // fix this appended the divergent tail, giving "the cow jumpeds jumped".
        tw.setLive("the cows jumped")
        drain(tw, into: &screen)

        XCTAssertEqual(screen.typed, "the cows jumped")
        XCTAssertEqual(screen.overDeletions, 0)
    }

    func testRevisingTextThatHasNotBeenTypedYetCostsNoDeletions() {
        let tw = Typewriter()
        var screen = Screen()

        tw.setLive("the cow jumped")
        for _ in 0..<7 {                                  // only "the cow" lands
            if let k = tw.nextKeystroke() { screen.apply(k) }
        }

        tw.setLive("the cows jumped")
        var deletions = 0
        while let k = tw.nextKeystroke() {
            if k == .backspace { deletions += 1 }
            screen.apply(k)
        }

        XCTAssertEqual(screen.typed, "the cows jumped")
        XCTAssertEqual(deletions, 0, "revising untyped text should be free")
    }

    // MARK: - Safety

    func testNeverDeletesTextTheUserTypedThemselves() {
        let tw = Typewriter()
        var screen = Screen(preexisting: "USER TEXT>")

        tw.setLive("abc")
        drain(tw, into: &screen)
        tw.setLive("")                                    // recogniser retracts all
        drain(tw, into: &screen)

        XCTAssertEqual(screen.typed, "")
        XCTAssertEqual(screen.untouched, "USER TEXT>")
        XCTAssertEqual(screen.overDeletions, 0)
    }

    func testCommittedTextIsNeverRevised() {
        let tw = Typewriter()
        var screen = Screen()

        tw.setLive("first sentence")
        tw.commitLive()
        drain(tw, into: &screen)

        tw.setLive("x")                                   // unrelated new utterance
        drain(tw, into: &screen)

        XCTAssertEqual(screen.typed, "first sentence x")
        XCTAssertEqual(screen.overDeletions, 0)
    }

    func testStackedRevisionsBeforeAnyKeystrokeIsEmitted() {
        let tw = Typewriter()
        var screen = Screen()

        tw.setLive("hello world")
        drain(tw, into: &screen)
        tw.setLive("hello wor")                           // debt accrues
        tw.setLive("hello w")                             // and grows again
        drain(tw, into: &screen)

        XCTAssertEqual(screen.typed, "hello w")
        XCTAssertEqual(screen.overDeletions, 0)
    }

    func testBufferStaysBoundedAcrossManyUtterances() {
        let tw = Typewriter()
        var screen = Screen()

        for n in 0..<200 {
            tw.setLive("utterance number \(n)")
            tw.commitLive()
            drain(tw, into: &screen)
        }

        XCTAssertTrue(screen.typed.hasPrefix("utterance number 0 "))
        XCTAssertEqual(tw.backlog, 0)
    }

    func testClearDropsPendingOutputWithoutUndoingWhatWasTyped() {
        let tw = Typewriter()
        var screen = Screen()

        tw.setLive("abcdef")
        for _ in 0..<3 { if let k = tw.nextKeystroke() { screen.apply(k) } }
        tw.clear()
        drain(tw, into: &screen)

        XCTAssertEqual(screen.typed, "abc")
        XCTAssertEqual(screen.overDeletions, 0)
    }

    // MARK: - Bounded correction

    /// Counts deletions while draining, so a test can assert how much was erased.
    private func drainCountingDeletions(_ tw: Typewriter, into screen: inout Screen) -> Int {
        var deletions = 0
        for _ in 0..<100_000 {
            guard let k = tw.nextKeystroke() else { return deletions }
            if k == .backspace { deletions += 1 }
            screen.apply(k)
        }
        XCTFail("typewriter never went idle")
        return deletions
    }

    func testALateChangeNearTheStartDoesNotEraseTheWholeUtterance() {
        let tw = Typewriter()
        var screen = Screen()

        // A recogniser revising a long utterance: capitalising the first word,
        // then re-segmenting a word near the start. Unbounded, each of these
        // diverges at a low index and wipes out everything typed since.
        let stream = [
            "the quick brown fox jumps over the lazy dog",
            "The quick brown fox jumps over the lazy dog",
            "The quick brown foxes jumps over the lazy dog",
            "The quick brown foxes jump over the lazy dogs",
        ]

        var worstErase = 0
        for transcript in stream {
            tw.setLive(transcript)
            worstErase = max(worstErase, drainCountingDeletions(tw, into: &screen))
        }

        XCTAssertLessThanOrEqual(worstErase, 24, "a single correction erased too much")
        XCTAssertEqual(screen.overDeletions, 0)
        XCTAssertFalse(screen.typed.isEmpty)
    }

    func testCorrectionIsBoundedEvenWhenTheTranscriptChangesAtIndexZero() {
        for length in [30, 80, 200] {
            let tw = Typewriter()
            var screen = Screen()

            tw.setLive(String(repeating: "a", count: length))
            drain(tw, into: &screen)

            // Worst case: the very first character changes.
            tw.setLive("b" + String(repeating: "a", count: length - 1))
            let erased = drainCountingDeletions(tw, into: &screen)

            XCTAssertLessThanOrEqual(erased, 24, "length \(length) erased \(erased)")
            XCTAssertEqual(screen.overDeletions, 0, "length \(length)")
        }
    }

    func testOrdinaryGrowthNeverErasesAnything() {
        let tw = Typewriter()
        var screen = Screen()
        let words = "the cow jumped over the moon and kept on going".split(separator: " ")

        var erased = 0
        for n in 1...words.count {
            tw.setLive(words[0..<n].joined(separator: " "))
            erased += drainCountingDeletions(tw, into: &screen)
        }

        XCTAssertEqual(erased, 0, "growing text should never cost a deletion")
        XCTAssertEqual(screen.typed, words.joined(separator: " "))
    }

    // MARK: - Punctuation settles

    func testPunctuationSolidifiesTheSentenceBeforeIt() {
        let tw = Typewriter()
        var screen = Screen()

        tw.setLive("hello world.")
        drain(tw, into: &screen)
        XCTAssertEqual(screen.typed, "hello world.")

        // The recogniser tries to revise a word behind the full stop.
        tw.setLive("hello worlds.")
        let erased = drainCountingDeletions(tw, into: &screen)

        XCTAssertEqual(erased, 0, "a settled sentence must not be taken back")
        XCTAssertEqual(screen.typed, "hello world.", "no erasure and no duplication")
    }

    func testSpeechContinuesNormallyAfterASettledSentence() {
        let tw = Typewriter()
        var screen = Screen()

        tw.setLive("hello world.")
        drain(tw, into: &screen)
        tw.setLive("hello worlds.")                       // revision we refuse
        drain(tw, into: &screen)
        tw.setLive("hello worlds. how are you")           // then it keeps going
        drain(tw, into: &screen)

        XCTAssertEqual(screen.typed, "hello world. how are you")
        XCTAssertEqual(screen.overDeletions, 0)
    }

    // MARK: - Randomised

    /// When the recogniser only ever extends what it has said, the output must
    /// reproduce the transcript exactly — settling can never lose or reorder it.
    func testRandomisedGrowOnlySessionsReproduceTheTranscriptExactly() {
        let words = ["the", "cow", "jumped", "over", "moon", "red", "and", "then"]

        for seed in 0..<1_000 {
            var rng = SeededGenerator(seed: UInt64(seed))
            let tw = Typewriter()
            var screen = Screen(preexisting: "PRE:")
            var committed = ""
            var live = ""

            for _ in 0..<Int.random(in: 1...30, using: &rng) {
                let roll = Double.random(in: 0...1, using: &rng)
                if roll < 0.70 {
                    var parts = live.isEmpty ? [] : live.split(separator: " ").map(String.init)
                    parts.append(words.randomElement(using: &rng)!)
                    live = parts.joined(separator: " ")
                    tw.setLive(live)
                } else if roll < 0.80, !live.isEmpty {
                    tw.commitLive()
                    committed += live + " "
                    live = ""
                } else {
                    for _ in 0..<Int.random(in: 1...12, using: &rng) {
                        guard let k = tw.nextKeystroke() else { break }
                        screen.apply(k)
                    }
                }
            }

            drain(tw, into: &screen)

            XCTAssertEqual(screen.typed, committed + live, "seed \(seed)")
            XCTAssertEqual(screen.untouched, "PRE:", "seed \(seed)")
            XCTAssertEqual(screen.overDeletions, 0, "seed \(seed)")
            XCTAssertEqual(tw.backlog, 0, "seed \(seed)")
        }
    }

    /// Replays revision-heavy sessions — words retracted, first words
    /// re-capitalised, punctuation appearing — with typing lagging by varying
    /// amounts.
    ///
    /// The output is deliberately *not* asserted to equal the final transcript:
    /// settled text is allowed to stay as the user saw it even if the recogniser
    /// later changed its mind. What must always hold is that the app never
    /// deletes more than it typed, never reaches past the window, and always
    /// drains.
    func testRandomisedRevisionHeavySessionsStayWithinBounds() {
        let words = ["the", "cow", "cows", "jumped", "jump", "over", "moon", "red", "read"]

        for seed in 0..<2_000 {
            var rng = SeededGenerator(seed: UInt64(seed))
            let tw = Typewriter()
            var screen = Screen(preexisting: "PRE:")
            var live = ""
            var worstErase = 0

            for _ in 0..<Int.random(in: 1...30, using: &rng) {
                let roll = Double.random(in: 0...1, using: &rng)
                if roll < 0.72 {
                    var parts = live.isEmpty ? [] : live.split(separator: " ").map(String.init)
                    if !parts.isEmpty, Double.random(in: 0...1, using: &rng) < 0.4 {
                        parts.removeLast(Int.random(in: 1...min(3, parts.count), using: &rng))
                    }
                    if !parts.isEmpty, Double.random(in: 0...1, using: &rng) < 0.15 {
                        parts[0] = parts[0].uppercased()
                    }
                    var word = words.randomElement(using: &rng)!
                    if Double.random(in: 0...1, using: &rng) < 0.12 { word += "." }
                    parts.append(word)
                    live = parts.joined(separator: " ")
                    tw.setLive(live)
                } else if roll < 0.80, !live.isEmpty {
                    tw.commitLive()
                    live = ""
                } else {
                    var erased = 0
                    for _ in 0..<Int.random(in: 1...14, using: &rng) {
                        guard let k = tw.nextKeystroke() else { break }
                        if k == .backspace { erased += 1 }
                        screen.apply(k)
                    }
                    worstErase = max(worstErase, erased)
                }
            }

            worstErase = max(worstErase, drainCountingDeletions(tw, into: &screen))

            XCTAssertEqual(screen.untouched, "PRE:", "seed \(seed)")
            XCTAssertEqual(screen.overDeletions, 0, "seed \(seed)")
            XCTAssertEqual(tw.backlog, 0, "seed \(seed)")
            XCTAssertLessThanOrEqual(worstErase, 24, "seed \(seed) erased too much")
        }
    }
}

/// Deterministic generator so a failing seed can be reproduced exactly.
private struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) { state = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407 }

    mutating func next() -> UInt64 {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return state
    }
}
