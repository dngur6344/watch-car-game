import XCTest
@testable import WatchCarRacer

final class RunResultTests: XCTestCase {
    func testRunResultIsAnImmutableValueSnapshot() {
        let result = RunResult(
            score: 340,
            previousBest: 250,
            localBest: 340,
            isNewBest: true
        )
        let copiedResult = result
        var results = [result]
        results[0] = RunResult(
            score: 10,
            previousBest: 340,
            localBest: 340,
            isNewBest: false
        )

        XCTAssertEqual(copiedResult.score, 340)
        XCTAssertEqual(copiedResult.previousBest, 250)
        XCTAssertEqual(copiedResult.localBest, 340)
        XCTAssertTrue(copiedResult.isNewBest)
        XCTAssertNotEqual(results[0], copiedResult)
    }

    func testSessionControlRoutesAreDistinctSharedValues() {
        let adaptive = SessionControlRoute.adaptiveWatchPreferred
        let touchOnly = SessionControlRoute.touchOnly

        XCTAssertNotEqual(adaptive, touchOnly)
        XCTAssertEqual(adaptive, .adaptiveWatchPreferred)
        XCTAssertEqual(touchOnly, .touchOnly)
    }
}
