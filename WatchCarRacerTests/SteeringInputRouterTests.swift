import XCTest
@testable import WatchCarRacer

final class SteeringInputRouterTests: XCTestCase {
    private let streamID = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!

    func testFreshActiveWatchHasPriorityAndPreservesValueWhileTouchIsIdle() {
        var router = SteeringInputRouter()

        let snapshot = router.steeringSnapshot(
            at: 10,
            watch: reading(value: 0.72),
            touchValue: -0.4,
            isTouchDragging: false
        )

        XCTAssertEqual(snapshot.value, 0.72)
        XCTAssertEqual(snapshot.source, .watch)
        XCTAssertEqual(snapshot.availability, .available)
    }

    func testLocalReceiptIsFreshAt250MillisecondsAndStaleAt251Milliseconds() throws {
        var receiver = PhoneSteeringReceiver()
        let packet = SteeringPacket(
            streamID: streamID,
            sequence: 1,
            state: .active,
            value: 0.65
        )
        try receiver.receive(data: packet.encodedData(), at: 20)

        let freshReading = receiver.routingReading(
            isSessionActive: true,
            isReachable: true,
            at: 20.25
        )
        var freshRouter = SteeringInputRouter()
        let freshSnapshot = freshRouter.steeringSnapshot(
            at: 20.25,
            watch: freshReading,
            touchValue: -0.2,
            isTouchDragging: false
        )

        XCTAssertEqual(freshReading.availability, .active)
        XCTAssertEqual(freshSnapshot.source, .watch)
        XCTAssertEqual(freshSnapshot.value, 0.65)

        let staleReading = receiver.routingReading(
            isSessionActive: true,
            isReachable: true,
            at: 20.251
        )
        var staleRouter = SteeringInputRouter()
        let staleSnapshot = staleRouter.steeringSnapshot(
            at: 20.251,
            watch: staleReading,
            touchValue: -0.2,
            isTouchDragging: false
        )

        XCTAssertEqual(staleReading.availability, .stale)
        XCTAssertEqual(staleSnapshot.source, .touch)
        XCTAssertEqual(staleSnapshot.value, -0.2)
        XCTAssertEqual(staleSnapshot.availability, .fallback(.stale))
    }

    func testUnavailableAndNonActiveWatchStatesSelectTouchFallback() {
        let unavailableStates: [WatchSteeringAvailability] = [
            .sessionInactive,
            .unreachable,
            .stale,
            .needsCalibration,
            .motionUnavailable,
            .noPacket,
        ]

        for availability in unavailableStates {
            var router = SteeringInputRouter()
            let snapshot = router.steeringSnapshot(
                at: 5,
                watch: reading(value: 0.9, availability: availability),
                touchValue: 0.35,
                isTouchDragging: false
            )

            XCTAssertEqual(snapshot.source, .touch, "Failed for \(availability)")
            XCTAssertEqual(snapshot.value, 0.35, "Failed for \(availability)")
            XCTAssertEqual(snapshot.availability, .fallback(availability))
        }
    }

    func testWatchLossBlendsToNeutralIn125MillisecondsAndStaysClearBefore300Milliseconds() {
        var router = SteeringInputRouter()
        let active = reading(value: 0.8)
        let unavailable = reading(value: 0, availability: .unreachable)

        XCTAssertEqual(
            router.steeringSnapshot(
                at: 0,
                watch: active,
                touchValue: 0,
                isTouchDragging: false
            ).value,
            0.8
        )

        let lossStart = router.steeringSnapshot(
            at: 1,
            watch: unavailable,
            touchValue: 0,
            isTouchDragging: false
        )
        let halfway = router.steeringSnapshot(
            at: 1.0625,
            watch: unavailable,
            touchValue: 0,
            isTouchDragging: false
        )
        let completed = router.steeringSnapshot(
            at: 1.125,
            watch: unavailable,
            touchValue: 0,
            isTouchDragging: false
        )
        let before300Milliseconds = router.steeringSnapshot(
            at: 1.299,
            watch: unavailable,
            touchValue: 0,
            isTouchDragging: false
        )

        XCTAssertEqual(SteeringInputRouter.transitionDuration, 0.125)
        XCTAssertEqual(lossStart.source, .touch)
        XCTAssertEqual(lossStart.value, 0.8)
        XCTAssertEqual(halfway.value, 0.4, accuracy: 0.000_001)
        XCTAssertEqual(completed.value, 0, accuracy: 0.000_001)
        XCTAssertEqual(before300Milliseconds.value, 0)
    }

    func testTouchDragOverridesWatchAndHoldsAcrossReconnection() {
        var router = SteeringInputRouter()
        _ = router.steeringSnapshot(
            at: 0,
            watch: reading(value: 0.8),
            touchValue: 0,
            isTouchDragging: false
        )

        let takeover = router.steeringSnapshot(
            at: 0.01,
            watch: reading(value: 0.8),
            touchValue: -0.6,
            isTouchDragging: true
        )
        let disconnected = router.steeringSnapshot(
            at: 0.02,
            watch: reading(value: 0, availability: .unreachable),
            touchValue: -0.6,
            isTouchDragging: true
        )
        let reconnected = router.steeringSnapshot(
            at: 0.03,
            watch: reading(sequence: 2, value: 0.95),
            touchValue: -0.6,
            isTouchDragging: true
        )

        for snapshot in [takeover, disconnected, reconnected] {
            XCTAssertEqual(snapshot.source, .touch)
            XCTAssertEqual(snapshot.value, -0.6)
        }
    }

    func testTouchReleaseBlendsSmoothlyToFreshWatchWithoutInitialJump() {
        var router = SteeringInputRouter()
        let active = reading(value: 0.8)

        _ = router.steeringSnapshot(
            at: 0,
            watch: active,
            touchValue: -0.6,
            isTouchDragging: true
        )
        let release = router.steeringSnapshot(
            at: 0.02,
            watch: active,
            touchValue: -0.6,
            isTouchDragging: false
        )
        let halfway = router.steeringSnapshot(
            at: 0.0825,
            watch: active,
            touchValue: -0.6,
            isTouchDragging: false
        )
        let completed = router.steeringSnapshot(
            at: 0.145,
            watch: active,
            touchValue: -0.6,
            isTouchDragging: false
        )

        XCTAssertEqual(release.source, .watch)
        XCTAssertEqual(release.availability, .transitioning)
        XCTAssertEqual(release.value, -0.6, "Release must not jump to the Watch value")
        XCTAssertEqual(halfway.value, 0.1, accuracy: 0.000_001)
        XCTAssertEqual(completed.value, 0.8)
        XCTAssertEqual(completed.availability, .available)
    }

    func testReachabilityFlappingCannotRestoreRetiredWatchSample() {
        var router = SteeringInputRouter()
        let original = reading(value: 0.9)

        _ = router.steeringSnapshot(
            at: 0,
            watch: original,
            touchValue: 0,
            isTouchDragging: false
        )
        _ = router.steeringSnapshot(
            at: 0.1,
            watch: reading(value: 0, availability: .unreachable),
            touchValue: 0,
            isTouchDragging: false
        )
        let sameSampleAfterFlap = router.steeringSnapshot(
            at: 0.11,
            watch: original,
            touchValue: 0,
            isTouchDragging: false
        )
        _ = router.steeringSnapshot(
            at: 0.225,
            watch: original,
            touchValue: 0,
            isTouchDragging: false
        )
        let retiredSample = router.steeringSnapshot(
            at: 0.226,
            watch: original,
            touchValue: 0,
            isTouchDragging: false
        )
        let newSample = router.steeringSnapshot(
            at: 0.227,
            watch: reading(sequence: 2, value: 0.4),
            touchValue: 0,
            isTouchDragging: false
        )

        XCTAssertEqual(sameSampleAfterFlap.source, .touch)
        XCTAssertLessThan(sameSampleAfterFlap.value, 0.9)
        XCTAssertEqual(retiredSample.value, 0)
        XCTAssertEqual(retiredSample.availability, .fallback(.awaitingFreshPacket))
        XCTAssertEqual(newSample.source, .watch)
        XCTAssertEqual(newSample.availability, .transitioning)
        XCTAssertEqual(newSample.value, 0, "A new sample starts a blend instead of jumping")
    }

    func testResetClearsTransitionAndRetiresBufferedWatchValue() {
        var router = SteeringInputRouter()
        let buffered = reading(value: -0.85)

        _ = router.steeringSnapshot(
            at: 0,
            watch: buffered,
            touchValue: 0,
            isTouchDragging: false
        )
        _ = router.steeringSnapshot(
            at: 0.1,
            watch: reading(value: 0, availability: .stale),
            touchValue: 0,
            isTouchDragging: false
        )

        router.reset(retiring: buffered)

        let afterReset = router.steeringSnapshot(
            at: 1,
            watch: buffered,
            touchValue: 0,
            isTouchDragging: false
        )

        XCTAssertEqual(afterReset.value, 0)
        XCTAssertEqual(afterReset.source, .touch)
        XCTAssertEqual(afterReset.availability, .fallback(.awaitingFreshPacket))
    }

    private func reading(
        sequence: UInt64 = 1,
        value: Double,
        availability: WatchSteeringAvailability = .active
    ) -> WatchSteeringReading {
        WatchSteeringReading(
            value: value,
            availability: availability,
            sampleID: WatchSteeringSampleID(streamID: streamID, sequence: sequence)
        )
    }
}
