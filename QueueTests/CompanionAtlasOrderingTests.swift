import XCTest
@testable import Queue

final class CompanionAtlasOrderingTests: XCTestCase {
    func testTextureNamesSortInFilenameOrder() {
        let shuffled = [
            "working_010.png",
            "working_002.png",
            "working_000.png",
            "working_011.png",
            "working_001.png",
        ]
        let ordered = CompanionTextureStore.sortedTextureNames(shuffled)
        XCTAssertEqual(
            ordered,
            [
                "working_000.png",
                "working_001.png",
                "working_002.png",
                "working_010.png",
                "working_011.png",
            ]
        )
    }

    func testClipMappingUsesExpectedAtlases() {
        let working = CompanionAnimationClip.clip(for: .working, reduceMotion: false)
        XCTAssertEqual(working.atlas, .working)
        XCTAssertEqual(working.playback, .loop)

        let deep = CompanionAnimationClip.clip(for: .deepFocus, reduceMotion: false)
        XCTAssertEqual(deep.atlas, .deepFocus)
        XCTAssertEqual(deep.playback, .loop)

        let done = CompanionAnimationClip.clip(for: .celebrating, reduceMotion: false)
        XCTAssertEqual(done.atlas, .completed)
        XCTAssertEqual(done.playback, .playOnceHoldLast)

        let expired = CompanionAnimationClip.clip(for: .timerExpired, reduceMotion: false)
        XCTAssertEqual(expired.atlas, .expired)
        XCTAssertEqual(expired.playback, .playOnceHoldLast)

        let reduced = CompanionAnimationClip.clip(for: .working, reduceMotion: true)
        XCTAssertEqual(reduced.playback, .staticFrame)
    }
}
