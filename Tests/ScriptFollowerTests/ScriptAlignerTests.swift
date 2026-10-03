import XCTest
@testable import ScriptFollower

final class ScriptAlignerTests: XCTestCase {

    private let script = """
    Welcome back to the channel. Today we are going to look at three ways to make your videos \
    easier to follow. First, add captions. Second, keep your sentences short. Third, look at the camera.
    """

    private func heard(_ s: String) -> [String] { ScriptAligner.normalizedWords(in: s) }

    func testNormalizationFoldsCaseAccentsAndPunctuation() {
        XCTAssertEqual(ScriptAligner.normalize("Café!"), "cafe")
        XCTAssertEqual(ScriptAligner.normalizedWords(in: "Hello, World — it's me."), ["hello", "world", "its", "me"])
    }

    func testFollowsAReaderWordByWord() {
        var a = ScriptAligner(script: script)
        XCTAssertTrue(a.consume(heard: heard("welcome back to the channel")))
        XCTAssertEqual(a.script[a.currentIndex], "channel")
        XCTAssertTrue(a.consume(heard: heard("welcome back to the channel today we are going")))
        XCTAssertEqual(a.script[a.currentIndex], "going")
    }

    func testToleratesMisheardWords() {
        var a = ScriptAligner(script: script)
        // "chanel" and "todays" are recognizer slips; the reader is still followed.
        XCTAssertTrue(a.consume(heard: heard("welcome back to the chanel todays we are")))
        XCTAssertEqual(a.script[a.currentIndex], "are")
    }

    func testIgnoresFillerAndShortWordsAlone() {
        var a = ScriptAligner(script: script)
        a.consume(heard: heard("welcome back"))
        let before = a.currentIndex
        XCTAssertFalse(a.consume(heard: heard("welcome back um uh")))
        XCTAssertEqual(a.currentIndex, before)
    }

    func testNeverMovesBackward() {
        var a = ScriptAligner(script: script)
        a.consume(heard: heard("first add captions second keep your sentences short"))
        let before = a.currentIndex
        XCTAssertFalse(a.consume(heard: heard("welcome back to the channel")))
        XCTAssertEqual(a.currentIndex, before)
    }

    func testRepeatedPhraseDoesNotStealThePlace() {
        // "look at" appears twice; the nearer occurrence must win.
        var a = ScriptAligner(script: script)
        a.consume(heard: heard("today we are going to look at"))
        XCTAssertEqual(a.script[a.currentIndex], "at")
        XCTAssertLessThan(a.currentIndex, 15)
    }

    func testFollowsASkippedSentenceOnlyWithAPhrase() {
        var a = ScriptAligner(script: script)
        a.consume(heard: heard("welcome back to the channel"))
        // A single word far ahead is not enough evidence...
        XCTAssertFalse(a.consume(heard: heard("welcome back to the channel camera")))
        // ...but a phrase is.
        XCTAssertTrue(a.consume(heard: heard("welcome back to the channel second keep your sentences")))
        XCTAssertEqual(a.script[a.currentIndex], "sentences")
    }

    func testEditDistanceEarlyExit() {
        XCTAssertEqual(ScriptAligner.editDistance("kitten", "sitting", cap: 3), 3)
        XCTAssertEqual(ScriptAligner.editDistance("abc", "xyzxyz", cap: 1), 2)
    }
}
