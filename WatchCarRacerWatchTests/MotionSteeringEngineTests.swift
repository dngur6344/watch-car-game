import XCTest
@testable import WatchCarRacerWatchApp

final class MotionSteeringEngineTests: XCTestCase {
    func testAngleWrapAcrossPiBoundary() {
        let from = 179.0 * Double.pi / 180
        let to = -179.0 * Double.pi / 180

        XCTAssertEqual(
            MotionSteeringCore.wrappedAngle(to - from),
            2.0 * Double.pi / 180,
            accuracy: 0.000_001
        )
    }

    func testCalibrationCentersLatestAttitude() throws {
        var core = MotionSteeringCore()
        XCTAssertNil(core.ingest(sample(rollDegrees: 12, timestamp: 1)))
        XCTAssertTrue(core.calibrateUsingLatestSample())

        XCTAssertEqual(
            try XCTUnwrap(core.ingest(sample(rollDegrees: 12, timestamp: 1.1))),
            0,
            accuracy: 0.000_001
        )
    }

    func testThreeDegreeDeadZoneProducesZero() {
        XCTAssertEqual(
            MotionSteeringCore.normalizedTarget(
                relativeAngle: 2.99 * .pi / 180,
                deadZone: 3 * .pi / 180,
                fullLock: 30 * .pi / 180
            ),
            0
        )
    }

    func testFullLockAndBeyondClampToUnitRange() {
        XCTAssertEqual(
            MotionSteeringCore.normalizedTarget(
                relativeAngle: 30 * .pi / 180,
                deadZone: 3 * .pi / 180,
                fullLock: 30 * .pi / 180
            ),
            1,
            accuracy: 0.000_001
        )
        XCTAssertEqual(
            MotionSteeringCore.normalizedTarget(
                relativeAngle: -90 * .pi / 180,
                deadZone: 3 * .pi / 180,
                fullLock: 30 * .pi / 180
            ),
            -1,
            accuracy: 0.000_001
        )
    }

    func testTimeBasedSmoothingUsesElapsedTime() throws {
        var configuration = MotionSteeringConfiguration()
        configuration.deadZoneRadians = 0
        configuration.filterTimeConstant = 0.05
        var core = MotionSteeringCore(configuration: configuration)
        XCTAssertNil(core.ingest(sample(rollDegrees: 0, timestamp: 10)))
        XCTAssertTrue(core.calibrateUsingLatestSample())

        let value = try XCTUnwrap(core.ingest(sample(rollDegrees: 30, timestamp: 10.05)))
        XCTAssertEqual(value, 1 - exp(-1), accuracy: 0.000_001)
    }

    func testProvisionalRightRollIsPositive() {
        let projection = MotionSteeringProjection.provisionalRightPositiveRoll
        XCTAssertGreaterThan(projection.angle(from: sample(rollDegrees: 10, timestamp: 0)), 0)
    }

    func testNonfiniteSampleSafelyInvalidatesCalibration() {
        var core = MotionSteeringCore()
        XCTAssertNil(core.ingest(sample(rollDegrees: 0, timestamp: 1)))
        XCTAssertTrue(core.calibrateUsingLatestSample())

        XCTAssertNil(core.ingest(MotionAttitudeSample(roll: .nan, pitch: 0, yaw: 0, timestamp: 2)))
        XCTAssertFalse(core.isCalibrated)
        XCTAssertEqual(core.filteredValue, 0)
    }

    private func sample(rollDegrees: Double, timestamp: TimeInterval) -> MotionAttitudeSample {
        MotionAttitudeSample(
            roll: rollDegrees * .pi / 180,
            pitch: 0,
            yaw: 0,
            timestamp: timestamp
        )
    }
}
