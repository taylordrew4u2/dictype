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

    // MARK: - Randomised

    /// Replays many sessions where revisions land at arbitrary points relative
    /// to how far the typing has progressed.
    func testRandomisedSessionsConvergeOnTheExpectedText() {
        let words = ["the", "cow", "cows", "jumped", "jump", "over", "moon", "red", "read"]

        for seed in 0..<2_000 {
            var rng = SeededGenerator(seed: UInt64(seed))
            let tw = Typewriter()
            var screen = Screen(preexisting: "PRE:")
            var committed = ""
            var live = ""

            for _ in 0..<Int.random(in: 1...30, using: &rng) {
                let roll = Double.random(in: 0...1, using: &rng)
                if roll < 0.70 {
                    var parts = live.isEmpty ? [] : live.split(separator: " ").map(String.init)
                    if !parts.isEmpty, Double.random(in: 0...1, using: &rng) < 0.45 {
                        parts.removeLast(Int.random(in: 1...min(2, parts.count), using: &rng))
                    }
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
