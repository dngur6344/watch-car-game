import XCTest
@testable import WatchCarRacer

final class TouchSteeringStateTests: XCTestCase {
    func testHorizontalPositionNormalizesAndClamps() {
        XCTAssertEqual(TouchSteeringState.normalized(horizontalPosition: 0, width: 200), -1)
        XCTAssertEqual(TouchSteeringState.normalized(horizontalPosition: 100, width: 200), 0)
        XCTAssertEqual(TouchSteeringState.normalized(horizontalPosition: 200, width: 200), 1)
        XCTAssertEqual(TouchSteeringState.normalized(horizontalPosition: -100, width: 200), -1)
        XCTAssertEqual(TouchSteeringState.normalized(horizontalPosition: 300, width: 200), 1)
        XCTAssertEqual(TouchSteeringState.normalized(horizontalPosition: .nan, width: 200), 0)
        XCTAssertEqual(TouchSteeringState.normalized(horizontalPosition: 100, width: 0), 0)
    }

    func testReleaseDecaysSteeringToExactCenter() {
        var state = TouchSteeringState(returnRate: 8)
        state.updateDrag(horizontalPosition: 200, width: 200)
        XCTAssertTrue(state.isDragging)
        XCTAssertEqual(state.value, 1)

        state.advance(by: 1)
        XCTAssertEqual(state.value, 1, "Dragging must hold the requested value")

        state.endDrag()
        state.advance(by: 0.25)
        XCTAssertFalse(state.isDragging)
        XCTAssertGreaterThan(state.value, 0)
        XCTAssertLessThan(state.value, 1)

        state.advance(by: 2)
        XCTAssertEqual(state.value, 0)
    }

    func testResetClearsValueAndDraggingState() {
        var state = TouchSteeringState()
        state.updateDrag(horizontalPosition: 0, width: 200)
        state.reset()

        XCTAssertEqual(state.value, 0)
        XCTAssertFalse(state.isDragging)
    }
}
