import XCTest
@testable import WatchCarRacer

final class FeedbackCoordinatorTests: XCTestCase {
    func testNearMissAndCollisionMapOnceAndDuplicatesAreIgnored() {
        let firstID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let secondID = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
        var ids = [firstID, secondID].makeIterator()
        var coordinator = GameFeedbackCoordinator(makeEventID: { ids.next()! })
        let nearMiss = GameEvent.nearMiss(obstacleID: 7, kind: .trafficCar, bonus: 100)
        let collision = GameEvent.collision(obstacleID: 9, kind: .barrier)

        let feedback = coordinator.feedback(for: [nearMiss, nearMiss, collision, collision])

        XCTAssertEqual(
            feedback,
            [
                GameFeedback(eventID: firstID, kind: .nearMiss(bonus: 100)),
                GameFeedback(eventID: secondID, kind: .collision)
            ]
        )
        XCTAssertTrue(coordinator.feedback(for: [collision, nearMiss]).isEmpty)
    }

    func testResetAllowsSameLogicalEventInNewRunWithNewID() {
        let firstID = UUID(uuidString: "AAAAAAAA-1111-1111-1111-111111111111")!
        let secondID = UUID(uuidString: "BBBBBBBB-2222-2222-2222-222222222222")!
        var ids = [firstID, secondID].makeIterator()
        var coordinator = GameFeedbackCoordinator(makeEventID: { ids.next()! })
        let event = GameEvent.collision(obstacleID: 0, kind: .trafficCar)

        XCTAssertEqual(coordinator.feedback(for: [event]).first?.eventID, firstID)
        coordinator.reset()
        XCTAssertEqual(coordinator.feedback(for: [event]).first?.eventID, secondID)
    }

    func testProceduralCuesAreSelfContainedAndDistinct() {
        let nearMiss = ProceduralFeedbackAudio.waveData(for: .nearMiss)
        let collision = ProceduralFeedbackAudio.waveData(for: .collision)

        XCTAssertEqual(String(decoding: nearMiss.prefix(4), as: UTF8.self), "RIFF")
        XCTAssertEqual(String(decoding: nearMiss.dropFirst(8).prefix(4), as: UTF8.self), "WAVE")
        XCTAssertNotEqual(nearMiss, collision)
        XCTAssertGreaterThan(nearMiss.count, 44)
        XCTAssertGreaterThan(collision.count, nearMiss.count)
    }
}

@MainActor
final class FeedbackIntegrationTests: XCTestCase {
    func testControllerFansEachAcceptedEventToEveryFeedbackSinkOnce() {
        let eventID = UUID(uuidString: "CCCCCCCC-3333-3333-3333-333333333333")!
        let player = RecordingPhoneFeedbackPlayer()
        let watch = RecordingWatchFeedbackSender()
        let controller = GameSessionController(
            seed: 1,
            feedbackPlayer: player,
            watchFeedbackSender: watch,
            makeFeedbackEventID: { eventID }
        )
        let event = GameEvent.nearMiss(obstacleID: 3, kind: .barrier, bonus: 100)

        controller.receive(snapshot: controller.scene.currentSnapshot, events: [event, event])
        controller.receive(snapshot: controller.scene.currentSnapshot, events: [event])

        XCTAssertEqual(player.feedback, [GameFeedback(eventID: eventID, kind: .nearMiss(bonus: 100))])
        XCTAssertEqual(
            watch.packets,
            [WatchFeedbackPacket(eventID: eventID, kind: .nearMiss)]
        )
        XCTAssertEqual(controller.scene.presentedFeedback.count, 1)
        XCTAssertEqual(controller.feedbackDeliveryFailures, 0)
    }

    func testWatchSendFailureCannotChangeSnapshotScoreOrPhase() {
        let watch = RecordingWatchFeedbackSender(error: FeedbackTestError.unavailable)
        let controller = GameSessionController(seed: 12, watchFeedbackSender: watch)
        let base = controller.scene.currentSnapshot
        let snapshot = GameSnapshot(
            phase: .running,
            playerX: base.playerX,
            playerWidth: base.playerWidth,
            playerLength: base.playerLength,
            roadHalfWidth: base.roadHalfWidth,
            laneWidth: base.laneWidth,
            obstacles: base.obstacles,
            score: 245,
            speed: 18,
            elapsedTime: base.elapsedTime,
            distance: base.distance,
            spawnInterval: base.spawnInterval
        )
        let sceneSnapshotBeforeFeedback = controller.scene.currentSnapshot

        controller.receive(
            snapshot: snapshot,
            events: [.collision(obstacleID: 4, kind: .trafficCar)]
        )

        XCTAssertEqual(controller.scene.currentSnapshot, sceneSnapshotBeforeFeedback)
        XCTAssertEqual(controller.score, 245)
        XCTAssertEqual(controller.speed, 65)
        XCTAssertEqual(controller.phase, .running)
        XCTAssertEqual(controller.feedbackDeliveryFailures, 1)
        XCTAssertEqual(watch.packets.count, 1)
    }

    func testRetryClearsRunGateWithoutReplayingOldFeedback() {
        let ids = FeedbackIDSequence()
        let player = RecordingPhoneFeedbackPlayer()
        let watch = RecordingWatchFeedbackSender()
        let controller = GameSessionController(
            seed: 2,
            feedbackPlayer: player,
            watchFeedbackSender: watch,
            makeFeedbackEventID: { ids.next() }
        )
        let event = GameEvent.collision(obstacleID: 0, kind: .barrier)

        controller.receive(snapshot: controller.scene.currentSnapshot, events: [event])
        controller.retry()

        XCTAssertEqual(player.feedback.count, 1)
        XCTAssertEqual(watch.packets.count, 1)
        XCTAssertTrue(controller.scene.presentedFeedback.isEmpty)

        controller.receive(snapshot: controller.scene.currentSnapshot, events: [event])

        XCTAssertEqual(player.feedback.count, 2)
        XCTAssertEqual(watch.packets.count, 2)
        XCTAssertNotEqual(player.feedback[0].eventID, player.feedback[1].eventID)
    }
}

@MainActor
private final class RecordingPhoneFeedbackPlayer: PhoneFeedbackPlaying {
    private(set) var feedback: [GameFeedback] = []

    func play(_ feedback: GameFeedback) {
        self.feedback.append(feedback)
    }
}

@MainActor
private final class RecordingWatchFeedbackSender: WatchFeedbackSending {
    private(set) var packets: [WatchFeedbackPacket] = []
    private let error: (any Error)?

    init(error: (any Error)? = nil) {
        self.error = error
    }

    func sendFeedback(_ packet: WatchFeedbackPacket) throws {
        packets.append(packet)
        if let error {
            throw error
        }
    }
}

private enum FeedbackTestError: Error {
    case unavailable
}

private final class FeedbackIDSequence {
    private var value: UInt64 = 0

    func next() -> UUID {
        value += 1
        return UUID(uuidString: String(format: "00000000-0000-0000-0000-%012llu", value))!
    }
}
