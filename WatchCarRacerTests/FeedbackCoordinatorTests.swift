import SpriteKit
import XCTest
@testable import WatchCarRacer

@MainActor
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
                GameFeedback(
                    eventID: firstID,
                    kind: .nearMiss(bonus: 100),
                    obstacleID: 7,
                    spatialContext: nil,
                    nearMissGrade: .standard,
                    chainTier: 1,
                    isHapticEligible: true
                ),
                GameFeedback(
                    eventID: secondID,
                    kind: .collision,
                    obstacleID: 9,
                    spatialContext: nil,
                    nearMissGrade: nil,
                    chainTier: 0,
                    isHapticEligible: true
                )
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

    func testSideAndClosenessUseDocumentedInclusiveBoundaries() throws {
        struct SideCase {
            let relativeX: Double
            let expected: FeedbackSide
        }
        let sideCases = [
            SideCase(relativeX: -0.500_001, expected: .left),
            SideCase(relativeX: -0.5, expected: .center),
            SideCase(relativeX: 0.5, expected: .center),
            SideCase(relativeX: 0.500_001, expected: .right),
        ]

        for (index, testCase) in sideCases.enumerated() {
            let presentation = makePresentation(
                event: .collision(obstacleID: UInt64(index), kind: .barrier),
                relativeX: testCase.relativeX,
                playerWidth: 2,
                obstacleWidth: 2,
                nearMissMargin: 1,
                elapsedTime: 0
            )
            let context = try XCTUnwrap(presentation.spatialContext)
            XCTAssertEqual(context.side, testCase.expected, "relativeX=\(testCase.relativeX)")
            XCTAssertEqual(context.closeness, 1, accuracy: 0.000_001)
        }
    }

    func testNearMissClosenessGradeBoundaryTable() throws {
        struct GradeCase {
            let edgeGap: Double
            let closeness: Double
            let grade: NearMissFeedbackGrade
        }
        let cases = [
            GradeCase(edgeGap: 0, closeness: 1, grade: .strong),
            GradeCase(edgeGap: 0.2, closeness: 0.5, grade: .strong),
            GradeCase(edgeGap: 0.200_001, closeness: 0.499_997_5, grade: .standard),
            GradeCase(edgeGap: 0.4, closeness: 0, grade: .standard),
        ]
        var coordinator = GameFeedbackCoordinator()

        for (index, testCase) in cases.enumerated() {
            let obstacleID = UInt64(index + 10)
            let presentation = makePresentation(
                event: .nearMiss(obstacleID: obstacleID, kind: .trafficCar, bonus: 100),
                relativeX: 1 + testCase.edgeGap,
                playerWidth: 1,
                obstacleWidth: 1,
                nearMissMargin: 0.4,
                elapsedTime: Double(index)
            )

            let context = try XCTUnwrap(presentation.spatialContext)
            let feedback = try XCTUnwrap(coordinator.feedback(for: [presentation]).first)
            XCTAssertEqual(context.side, .right)
            XCTAssertEqual(context.closeness, testCase.closeness, accuracy: 0.000_001)
            XCTAssertEqual(feedback.nearMissGrade, testCase.grade)
            XCTAssertEqual(
                feedback.watchKind,
                testCase.grade == .strong ? .nearMissStrong : .nearMiss
            )
        }
    }

    func testChainUsesSimulationTimeCapsAtThreeAndResetsOnTimeoutCollisionAndRetry() throws {
        var coordinator = GameFeedbackCoordinator()
        let elapsedTimes = [0.0, 3.0, 5.0, 6.0]
        var tiers: [Int] = []
        for (index, elapsedTime) in elapsedTimes.enumerated() {
            let presentation = makePresentation(
                event: .nearMiss(
                    obstacleID: UInt64(index),
                    kind: .barrier,
                    bonus: 100
                ),
                relativeX: 1.2,
                elapsedTime: elapsedTime
            )
            tiers.append(try XCTUnwrap(coordinator.feedback(for: [presentation]).first).chainTier)
        }
        XCTAssertEqual(tiers, [1, 2, 3, 3])

        let timedOut = makePresentation(
            event: .nearMiss(obstacleID: 10, kind: .barrier, bonus: 100),
            relativeX: 1.2,
            elapsedTime: 9.000_001
        )
        XCTAssertEqual(coordinator.feedback(for: [timedOut]).first?.chainTier, 1)

        let collision = makePresentation(
            event: .collision(obstacleID: 11, kind: .barrier),
            relativeX: 0,
            elapsedTime: 9.1
        )
        XCTAssertEqual(coordinator.feedback(for: [collision]).first?.chainTier, 0)
        let afterCollision = makePresentation(
            event: .nearMiss(obstacleID: 12, kind: .barrier, bonus: 100),
            relativeX: 1.2,
            elapsedTime: 9.2
        )
        XCTAssertEqual(coordinator.feedback(for: [afterCollision]).first?.chainTier, 1)

        coordinator.reset()
        XCTAssertEqual(coordinator.feedback(for: [timedOut]).first?.chainTier, 1)
    }

    func testInjectedMonotonicClockLimitsOnlyNearMissHapticsAt150Milliseconds() throws {
        var now: TimeInterval = 10
        var coordinator = GameFeedbackCoordinator(monotonicClock: { now })

        let first = try XCTUnwrap(
            coordinator.feedback(for: [
                GameEvent.nearMiss(obstacleID: 1, kind: .barrier, bonus: 100)
            ]).first
        )
        now += 0.149
        let limited = try XCTUnwrap(
            coordinator.feedback(for: [
                GameEvent.nearMiss(obstacleID: 2, kind: .barrier, bonus: 100)
            ]).first
        )
        now += 0.001
        let boundary = try XCTUnwrap(
            coordinator.feedback(for: [
                GameEvent.nearMiss(obstacleID: 3, kind: .barrier, bonus: 100)
            ]).first
        )

        XCTAssertTrue(first.isHapticEligible)
        XCTAssertFalse(limited.isHapticEligible)
        XCTAssertTrue(boundary.isHapticEligible)
        XCTAssertTrue(coordinator.hapticEligibility(for: .collision))
        XCTAssertTrue(coordinator.hapticEligibility(for: .go))

        coordinator.reset()
        let afterRetry = try XCTUnwrap(
            coordinator.feedback(for: [
                GameEvent.nearMiss(obstacleID: 1, kind: .barrier, bonus: 100)
            ]).first
        )
        XCTAssertTrue(afterRetry.isHapticEligible)
    }

    func testMissingObstacleContextDegradesWithoutChangingRawEventOrSnapshotScore() throws {
        let rawEvent = GameEvent.nearMiss(obstacleID: 99, kind: .barrier, bonus: 100)
        let snapshot = GameSimulation(seed: 7).snapshot
        let presentation = GameEventPresentation(
            event: rawEvent,
            snapshot: snapshot,
            configuration: .init()
        )
        var coordinator = GameFeedbackCoordinator()

        let feedback = try XCTUnwrap(coordinator.feedback(for: [presentation]).first)

        XCTAssertEqual(presentation.event, rawEvent)
        XCTAssertNil(presentation.spatialContext)
        XCTAssertEqual(feedback.nearMissGrade, .standard)
        XCTAssertEqual(feedback.watchKind, .nearMiss)
        XCTAssertEqual(presentation.snapshot, snapshot)
        XCTAssertEqual(presentation.snapshot.score, snapshot.score)
    }

    private func makePresentation(
        event: GameEvent,
        relativeX: Double,
        playerWidth: Double = 1,
        obstacleWidth: Double = 1,
        nearMissMargin: Double = 0.4,
        elapsedTime: TimeInterval
    ) -> GameEventPresentation {
        let obstacleID = switch event {
        case let .nearMiss(obstacleID, _, _), let .collision(obstacleID, _):
            obstacleID
        }
        var configuration = GameSimulation.Configuration()
        configuration.playerWidth = playerWidth
        configuration.nearMissMargin = nearMissMargin
        let obstacle = ObstacleSnapshot(
            id: obstacleID,
            rowID: obstacleID,
            kind: .barrier,
            laneIndex: 1,
            x: relativeX,
            distance: 0,
            width: obstacleWidth,
            length: 1,
            closingSpeed: 0,
            didAwardNearMiss: false
        )
        let snapshot = GameSnapshot(
            phase: .running,
            playerX: 0,
            playerWidth: playerWidth,
            playerLength: 1.8,
            roadHalfWidth: 3,
            laneWidth: 2,
            obstacles: [obstacle],
            score: 100,
            speed: 12,
            elapsedTime: elapsedTime,
            distance: 0,
            spawnInterval: 2
        )
        return GameEventPresentation(
            event: event,
            snapshot: snapshot,
            configuration: configuration
        )
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

        XCTAssertEqual(
            player.feedback,
            [
                GameFeedback(
                    eventID: eventID,
                    kind: .nearMiss(bonus: 100),
                    obstacleID: 3,
                    spatialContext: nil,
                    nearMissGrade: .standard,
                    chainTier: 1,
                    isHapticEligible: true
                )
            ]
        )
        XCTAssertEqual(
            watch.packets.filter { $0.kind == .nearMiss },
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
        XCTAssertEqual(controller.feedbackDeliveryFailures, 2)
        XCTAssertEqual(watch.packets.filter { $0.kind == .collision }.count, 1)
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
        XCTAssertEqual(watch.packets.filter { $0.kind == .collision }.count, 1)
        XCTAssertTrue(controller.scene.presentedFeedback.isEmpty)

        controller.receive(snapshot: controller.scene.currentSnapshot, events: [event])

        XCTAssertEqual(player.feedback.count, 2)
        XCTAssertEqual(watch.packets.filter { $0.kind == .collision }.count, 2)
        XCTAssertNotEqual(player.feedback[0].eventID, player.feedback[1].eventID)
    }

    func testNearMissLimiterSuppressesPhoneAndWatchOnlyWhileCollisionBypasses() {
        let clock = FeedbackTestClock(now: 20)
        let player = RecordingPhoneFeedbackPlayer()
        let watch = RecordingWatchFeedbackSender()
        let controller = GameSessionController(
            seed: 2,
            feedbackPlayer: player,
            watchFeedbackSender: watch,
            currentTime: { clock.now }
        )
        let snapshot = controller.scene.currentSnapshot

        controller.receive(
            snapshot: snapshot,
            events: [.nearMiss(obstacleID: 1, kind: .barrier, bonus: 100)]
        )
        clock.now += 0.1
        controller.receive(
            snapshot: snapshot,
            events: [.nearMiss(obstacleID: 2, kind: .barrier, bonus: 100)]
        )
        controller.receive(
            snapshot: snapshot,
            events: [.collision(obstacleID: 3, kind: .trafficCar)]
        )

        XCTAssertEqual(controller.scene.presentedFeedback.count, 3)
        XCTAssertEqual(player.feedback.map(\.kind), [.nearMiss(bonus: 100), .collision])
        XCTAssertEqual(
            watch.packets.map(\.kind).filter { $0 == .nearMiss || $0 == .collision },
            [.nearMiss, .collision]
        )
    }

    func testReduceMotionSuppressesWorldShakeButKeepsCollisionPresentationAndDelivery() async throws {
        let collisionSleeper = FeedbackManualDurationSleeper()
        let player = RecordingPhoneFeedbackPlayer()
        let watch = RecordingWatchFeedbackSender()
        let controller = GameSessionController(
            seed: 3,
            feedbackPlayer: player,
            watchFeedbackSender: watch,
            countdownSleeper: {},
            collisionSleeper: { try await collisionSleeper.sleep(for: $0) }
        )
        controller.scene.didMove(to: SKView(frame: CGRect(origin: .zero, size: controller.scene.size)))
        controller.scene.setReduceMotionEnabled(true)
        let running = controller.scene.currentSnapshot

        controller.receive(
            snapshot: running,
            events: [.nearMiss(obstacleID: 2, kind: .trafficCar, bonus: 100)]
        )
        let crashed = GameSnapshot(
            phase: .crashed,
            playerX: running.playerX,
            playerWidth: running.playerWidth,
            playerLength: running.playerLength,
            roadHalfWidth: running.roadHalfWidth,
            laneWidth: running.laneWidth,
            obstacles: running.obstacles,
            score: 140,
            speed: running.speed,
            elapsedTime: running.elapsedTime,
            distance: running.distance,
            spawnInterval: running.spawnInterval
        )
        controller.receive(
            snapshot: crashed,
            events: [.collision(obstacleID: 4, kind: .barrier)]
        )

        let world = try XCTUnwrap(controller.scene.childNode(withName: "//feedback.world"))
        let flash = try XCTUnwrap(controller.scene.childNode(withName: "//feedback.flash"))
        let impact = try XCTUnwrap(controller.scene.childNode(withName: "//feedback.impact"))
        let scorePop = try XCTUnwrap(controller.scene.childNode(withName: "//feedback.scorePop"))

        XCTAssertTrue(controller.scene.reduceMotionEnabled)
        XCTAssertNil(world.action(forKey: "feedbackMotion"))
        XCTAssertEqual(world.position, .zero)
        XCTAssertNotNil(flash.action(forKey: "feedbackFlash"))
        XCTAssertGreaterThan(flash.alpha, 0)
        XCTAssertEqual(impact.children.count, 18)
        XCTAssertFalse(scorePop.children.isEmpty)
        XCTAssertEqual(
            scorePop.children.compactMap { ($0 as? SKLabelNode)?.text }.first,
            "NEAR MISS +100"
        )
        XCTAssertEqual(controller.scene.presentedFeedback.count, 2)
        XCTAssertEqual(player.feedback.count, 2)
        XCTAssertEqual(
            watch.packets.map(\.kind).filter { $0 == .nearMiss || $0 == .collision },
            [.nearMiss, .collision]
        )
        XCTAssertFalse(controller.scene.isPaused, "Initial result must allow SpriteKit actions to run")
        XCTAssertNotNil(result(from: controller.presentationPhase))
        XCTAssertEqual(controller.presentationPhase, .collision(result(from: controller.presentationPhase)!))
        await waitUntil { collisionSleeper.pendingCount == 1 }
        collisionSleeper.resumeNext()
        await waitUntil {
            if case .result = controller.presentationPhase { true } else { false }
        }
        XCTAssertTrue(controller.scene.isPaused)
    }

    private func result(from phase: RunPresentationPhase) -> RunResult? {
        switch phase {
        case let .collision(result), let .result(result):
            return result
        case .countdown, .racing:
            return nil
        }
    }

    private func waitUntil(_ predicate: @MainActor () -> Bool) async {
        for _ in 0..<1_000 {
            if predicate() { return }
            await Task.yield()
        }
        XCTFail("Condition did not become true")
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

@MainActor
private final class FeedbackTestClock {
    var now: TimeInterval

    init(now: TimeInterval) {
        self.now = now
    }
}

@MainActor
private final class FeedbackManualDurationSleeper {
    private var continuations: [CheckedContinuation<Void, Never>] = []

    var pendingCount: Int {
        continuations.count
    }

    func sleep(for _: TimeInterval) async throws {
        await withCheckedContinuation { continuation in
            continuations.append(continuation)
        }
    }

    func resumeNext() {
        precondition(!continuations.isEmpty)
        continuations.removeFirst().resume()
    }
}

private final class FeedbackIDSequence {
    private var value: UInt64 = 0

    func next() -> UUID {
        value += 1
        return UUID(uuidString: String(format: "00000000-0000-0000-0000-%012llu", value))!
    }
}
