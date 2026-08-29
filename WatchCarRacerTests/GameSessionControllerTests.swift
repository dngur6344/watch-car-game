import XCTest
@testable import WatchCarRacer

@MainActor
final class GameSessionControllerTests: XCTestCase {
    func testSnapshotAndCollisionEventBridgeToHUDStateAndResultPresentation() {
        let controller = GameSessionController(seed: 7)
        let running = GameSimulation(seed: 7).snapshot
        let crashed = snapshot(from: running, phase: .crashed, score: 321, speed: 15)
        let collision = GameEvent.collision(obstacleID: 9, kind: .barrier)

        controller.receive(snapshot: crashed, events: [collision])

        XCTAssertEqual(controller.score, 321)
        XCTAssertEqual(controller.speed, 54)
        XCTAssertEqual(controller.phase, .crashed)
        XCTAssertEqual(controller.lastEvent, collision)
        XCTAssertEqual(
            controller.presentationPhase,
            .result(
                RunResult(
                    score: 321,
                    previousBest: 0,
                    localBest: 321,
                    isNewBest: true
                )
            )
        )
        XCTAssertFalse(controller.scene.isPaused)
    }

    func testRetryReusesSessionSeedAndClearsSceneHUDAndTouch() {
        let controller = GameSessionController(seed: 42)
        let initialSnapshot = GameSimulation(seed: 42).snapshot
        let crashed = snapshot(from: initialSnapshot, phase: .crashed, score: 99, speed: 20)
        controller.updateTouch(horizontalPosition: 200, width: 200)
        controller.receive(
            snapshot: crashed,
            events: [.collision(obstacleID: 1, kind: .trafficCar)]
        )

        controller.retry()

        XCTAssertEqual(controller.runSeed, 42)
        XCTAssertEqual(controller.scene.currentSnapshot, initialSnapshot)
        XCTAssertEqual(controller.score, 0)
        XCTAssertEqual(controller.speed, 43)
        XCTAssertEqual(controller.phase, .running)
        XCTAssertNil(controller.lastEvent)
        XCTAssertEqual(controller.touchSteering.value, 0)
        XCTAssertFalse(controller.touchSteering.isDragging)
        XCTAssertEqual(controller.presentationPhase, .countdown(3))
        XCTAssertTrue(controller.scene.isPaused)
    }

    func testSceneCapsLargeFrameGapToFiveFixedSteps() throws {
        var configuration = GameSimulation.Configuration()
        configuration.spawnDistance = 10_000
        let scene = try makeScene(seed: 1, configuration: configuration)
        var steeringReads = 0
        scene.steeringProvider = { _ in
            steeringReads += 1
            return 0
        }

        scene.update(10)
        scene.update(20)

        XCTAssertEqual(steeringReads, GameScene.maximumStepsPerFrame)
        XCTAssertEqual(
            scene.currentSnapshot.elapsedTime,
            GameScene.fixedStep * Double(GameScene.maximumStepsPerFrame),
            accuracy: 0.000_001
        )
    }

#if DEBUG
    func testSceneReportsRollingFrameRateWithoutChangingSimulationTiming() throws {
        var configuration = GameSimulation.Configuration()
        configuration.spawnDistance = 10_000
        let scene = try makeScene(seed: 1, configuration: configuration)
        var samples: [Double] = []
        scene.frameRateHandler = { samples.append($0) }

        scene.update(0)
        for frame in 1...180 {
            scene.update(Double(frame) / 60)
        }

        XCTAssertEqual(scene.currentSnapshot.elapsedTime, 3, accuracy: 0.000_001)
        XCTAssertGreaterThanOrEqual(samples.count, 2)
        XCTAssertLessThanOrEqual(samples.count, 3)
        XCTAssertTrue(samples.allSatisfy { abs($0 - 60) < 0.000_001 })
    }

    func testControllerTracksOneSecondFrameRateAcceptanceSamples() async {
        let controller = GameSessionController(seed: 1, countdownSleeper: {})
        await waitUntil { controller.presentationPhase == .racing }

        controller.scene.update(0)
        for frame in 1...180 {
            controller.scene.update(Double(frame) / 60)
        }

        XCTAssertEqual(controller.frameRateSamples.count, controller.frameRateSampleCount)
        XCTAssertGreaterThanOrEqual(controller.frameRateSamples.count, 2)
        XCTAssertTrue(controller.frameRateSamples.allSatisfy { abs($0 - 60) < 0.000_001 })
        XCTAssertEqual(controller.maximumConsecutiveFrameRateSamplesBelow50, 0)
        XCTAssertNotNil(controller.firstObstacleFrameRateSample)
    }
#endif

    func testControllerReadsExactlyOneRoutedSnapshotPerFixedSimulationStep() async {
        var configuration = GameSimulation.Configuration()
        configuration.spawnDistance = 10_000
        let watchInput = FakeWatchInput(reading: activeReading(value: 0.7))
        let clock = FakeMonotonicClock(now: 5)
        let controller = GameSessionController(
            seed: 1,
            configuration: configuration,
            watchInput: watchInput,
            currentTime: { clock.now },
            countdownSleeper: {}
        )
        await waitUntil { controller.presentationPhase == .racing }

        controller.scene.update(10)
        controller.scene.update(20)

        XCTAssertEqual(watchInput.readCount, GameScene.maximumStepsPerFrame)
        XCTAssertEqual(controller.steeringSnapshot.source, .watch)
        XCTAssertEqual(controller.steeringSnapshot.value, 0.7)
        XCTAssertGreaterThan(controller.scene.currentSnapshot.playerX, 0)
    }

    func testRetryClearsRoutedValueAndRequiresANewWatchSample() async {
        var configuration = GameSimulation.Configuration()
        configuration.spawnDistance = 10_000
        let watchInput = FakeWatchInput(reading: activeReading(value: -0.8))
        let clock = FakeMonotonicClock(now: 5)
        let controller = GameSessionController(
            seed: 3,
            configuration: configuration,
            watchInput: watchInput,
            currentTime: { clock.now },
            countdownSleeper: {}
        )
        await waitUntil { controller.presentationPhase == .racing }

        controller.scene.update(10)
        controller.scene.update(10.02)
        XCTAssertEqual(controller.steeringSnapshot.source, .watch)
        XCTAssertEqual(controller.steeringSnapshot.value, -0.8)

        controller.retry()

        XCTAssertEqual(controller.steeringSnapshot.source, .touch)
        XCTAssertEqual(controller.steeringSnapshot.value, 0)
        XCTAssertEqual(controller.steeringSnapshot.availability, .fallback(.awaitingFreshPacket))

        await waitUntil { controller.presentationPhase == .racing }

        controller.scene.update(20)
        controller.scene.update(20.02)
        XCTAssertEqual(controller.steeringSnapshot.source, .touch)
        XCTAssertEqual(controller.steeringSnapshot.value, 0)

        watchInput.reading = activeReading(sequence: 2, value: 0.4)
        clock.now += 0.01
        controller.scene.update(20.04)
        XCTAssertEqual(controller.steeringSnapshot.source, .watch)
        XCTAssertEqual(controller.steeringSnapshot.availability, .transitioning)
        XCTAssertEqual(controller.steeringSnapshot.value, 0)
    }

    func testSelectedAppearanceAndSharedAssetLibraryReachSceneAndSurviveRetry() throws {
        let appearance = try XCTUnwrap(
            VehicleCatalog.resolve(VehicleSelection(vehicleID: .angular, colorID: .emberGold))
        )
        let assetLibrary = try GameAssetLibrary()
        let controller = try GameSessionController(
            seed: 912,
            appearance: appearance,
            assetLibrary: assetLibrary
        )

        XCTAssertEqual(controller.appearance, appearance)
        XCTAssertEqual(controller.scene.appearance, appearance)
        XCTAssertTrue(controller.assetLibrary === assetLibrary)
        XCTAssertTrue(controller.scene.assetLibrary === assetLibrary)

        controller.retry()

        XCTAssertEqual(controller.runSeed, 912)
        XCTAssertEqual(controller.appearance, appearance)
        XCTAssertEqual(controller.scene.appearance, appearance)
        XCTAssertTrue(controller.assetLibrary === assetLibrary)
        XCTAssertTrue(controller.scene.assetLibrary === assetLibrary)
        XCTAssertEqual(controller.presentationPhase, .countdown(3))
        XCTAssertTrue(controller.scene.isPaused)
    }

    func testCountdownRunsThreeTwoOneWithFrozenSimulationAndInputThenRaces() async {
        var configuration = GameSimulation.Configuration()
        configuration.spawnDistance = 10_000
        let sleeper = ManualCountdownSleeper()
        let watchInput = FakeWatchInput(reading: activeReading(value: 0.75))
        let controller = GameSessionController(
            seed: 88,
            configuration: configuration,
            watchInput: watchInput,
            countdownSleeper: { try await sleeper.sleep() }
        )
        let initialSnapshot = controller.scene.currentSnapshot

        XCTAssertEqual(controller.presentationPhase, .countdown(3))
        XCTAssertTrue(controller.scene.isPaused)
        XCTAssertTrue(controller.hasActiveCountdownTask)
        XCTAssertFalse(controller.acceptsTouchInput)

        controller.updateTouch(horizontalPosition: 200, width: 200)
        controller.scene.update(0)
        controller.scene.update(10)
        XCTAssertEqual(controller.scene.currentSnapshot, initialSnapshot)
        XCTAssertEqual(controller.score, initialSnapshot.score)
        XCTAssertEqual(controller.touchSteering.value, 0)
        XCTAssertEqual(watchInput.readCount, 0)

        await waitUntil { sleeper.pendingCount == 1 }
        sleeper.resumeNext()
        await waitUntil { controller.presentationPhase == .countdown(2) }
        XCTAssertEqual(controller.scene.currentSnapshot, initialSnapshot)
        XCTAssertEqual(watchInput.readCount, 0)

        await waitUntil { sleeper.pendingCount == 1 }
        sleeper.resumeNext()
        await waitUntil { controller.presentationPhase == .countdown(1) }
        XCTAssertEqual(controller.scene.currentSnapshot, initialSnapshot)
        XCTAssertEqual(watchInput.readCount, 0)

        await waitUntil { sleeper.pendingCount == 1 }
        sleeper.resumeNext()
        await waitUntil { controller.presentationPhase == .racing }

        XCTAssertFalse(controller.scene.isPaused)
        XCTAssertFalse(controller.hasActiveCountdownTask)
        XCTAssertTrue(controller.acceptsTouchInput)
        XCTAssertEqual(controller.scene.currentSnapshot, initialSnapshot)
        XCTAssertEqual(sleeper.sleepCallCount, 3)
    }

    func testTouchOnlyNeverReadsOrPromotesToWatchAndRouteSurvivesRetry() async {
        let watchInput = FakeWatchInput(reading: activeReading(value: 0.9))
        let controller = GameSessionController(
            seed: 4,
            controlRoute: .touchOnly,
            watchInput: watchInput,
            countdownSleeper: {}
        )
        await waitUntil { controller.presentationPhase == .racing }

        controller.updateTouch(horizontalPosition: 900, width: 1_000)
        controller.scene.update(0)
        controller.scene.update(1)

        XCTAssertEqual(controller.controlRoute, .touchOnly)
        XCTAssertEqual(watchInput.readCount, 0)
        XCTAssertEqual(controller.steeringSnapshot.source, .touch)
        XCTAssertEqual(controller.steeringSnapshot.availability, .available)
        XCTAssertGreaterThan(controller.scene.currentSnapshot.playerX, 0)

        watchInput.reading = activeReading(sequence: 2, value: -0.8)
        controller.retry()
        await waitUntil { controller.presentationPhase == .racing }
        controller.scene.update(2)
        controller.scene.update(3)

        XCTAssertEqual(controller.controlRoute, .touchOnly)
        XCTAssertEqual(watchInput.readCount, 0)
        XCTAssertEqual(controller.steeringSnapshot.source, .touch)
    }

    func testAdaptiveRouteKeepsWatchPriorityAndFallbackAcrossRetry() async {
        let watchInput = FakeWatchInput(reading: activeReading(value: 0.6))
        let controller = GameSessionController(
            seed: 5,
            controlRoute: .adaptiveWatchPreferred,
            watchInput: watchInput,
            countdownSleeper: {}
        )
        await waitUntil { controller.presentationPhase == .racing }
        controller.scene.update(0)
        controller.scene.update(1)
        XCTAssertEqual(controller.steeringSnapshot.source, .watch)

        watchInput.reading = WatchSteeringReading(
            value: 0,
            availability: .stale,
            sampleID: activeReading(value: 0.6).sampleID
        )
        controller.retry()
        await waitUntil { controller.presentationPhase == .racing }
        controller.scene.update(2)
        controller.scene.update(3)

        XCTAssertEqual(controller.controlRoute, .adaptiveWatchPreferred)
        XCTAssertEqual(controller.steeringSnapshot.source, .touch)
        XCTAssertEqual(controller.steeringSnapshot.availability, .fallback(.stale))
        XCTAssertGreaterThan(watchInput.readCount, 0)
    }

    func testCountdownAndRacingLifecycleResumeFromThreeWithoutResettingAttempt() async {
        let sleeper = ManualCountdownSleeper()
        let controller = GameSessionController(
            seed: 77,
            countdownSleeper: { try await sleeper.sleep() }
        )

        await waitUntil { sleeper.pendingCount == 1 }
        controller.handleLifecycle(.inactive)
        XCTAssertTrue(controller.scene.isPaused)
        XCTAssertFalse(controller.hasActiveCountdownTask)
        sleeper.resumeNext()
        await Task.yield()
        XCTAssertEqual(controller.presentationPhase, .countdown(3))

        controller.handleLifecycle(.active)
        await completeCountdown(controller, sleeper: sleeper)
        controller.scene.update(0)
        controller.scene.update(1)
        let racingSnapshot = controller.scene.currentSnapshot
        XCTAssertGreaterThan(racingSnapshot.distance, 0)

        controller.handleLifecycle(.background)
        controller.updateTouch(horizontalPosition: 1_000, width: 1_000)
        XCTAssertTrue(controller.scene.isPaused)
        XCTAssertFalse(controller.acceptsTouchInput)
        XCTAssertEqual(controller.scene.currentSnapshot, racingSnapshot)

        controller.handleLifecycle(.active)
        XCTAssertEqual(controller.presentationPhase, .countdown(3))
        XCTAssertEqual(controller.scene.currentSnapshot, racingSnapshot)
        await completeCountdown(controller, sleeper: sleeper)
        XCTAssertEqual(controller.scene.currentSnapshot, racingSnapshot)
    }

    func testResultLifecycleNeverRestartsRacingAndPausesAfterReactivation() async {
        let controller = GameSessionController(seed: 6, countdownSleeper: {})
        await waitUntil { controller.presentationPhase == .racing }
        let crashed = snapshot(
            from: controller.scene.currentSnapshot,
            phase: .crashed,
            score: 42,
            speed: 12
        )
        controller.receive(
            snapshot: crashed,
            events: [.collision(obstacleID: 1, kind: .barrier)]
        )
        let resultPhase = controller.presentationPhase

        XCTAssertFalse(controller.scene.isPaused, "Initial result keeps feedback actions live")
        controller.handleLifecycle(.inactive)
        XCTAssertTrue(controller.scene.isPaused)
        controller.handleLifecycle(.background)
        controller.handleLifecycle(.active)

        XCTAssertEqual(controller.presentationPhase, resultPhase)
        XCTAssertTrue(controller.scene.isPaused)
        XCTAssertFalse(controller.hasActiveCountdownTask)
        XCTAssertFalse(controller.acceptsTouchInput)
    }

    func testStaleCountdownCannotUnpauseAfterRapidRetryStopOrDuplicateActive() async {
        let sleeper = ManualCountdownSleeper()
        let controller = GameSessionController(
            seed: 90,
            countdownSleeper: { try await sleeper.sleep() }
        )
        await waitUntil { sleeper.pendingCount == 1 }

        controller.retry()
        await waitUntil { sleeper.pendingCount == 2 }
        sleeper.resumeNext()
        await Task.yield()
        XCTAssertEqual(controller.presentationPhase, .countdown(3))
        XCTAssertTrue(controller.scene.isPaused)

        controller.handleLifecycle(.inactive)
        sleeper.resumeNext()
        await Task.yield()
        controller.handleLifecycle(.active)
        controller.handleLifecycle(.active)
        await waitUntil { sleeper.pendingCount == 1 }
        XCTAssertEqual(sleeper.sleepCallCount, 3)

        controller.stop()
        sleeper.resumeNext()
        await Task.yield()

        XCTAssertTrue(controller.scene.isPaused)
        XCTAssertFalse(controller.hasActiveCountdownTask)
        XCTAssertNotEqual(controller.presentationPhase, .racing)
    }

    func testCollisionRecordsOneImmutableResultPerAttempt() async {
        var recordedScores: [Int] = []
        let controller = GameSessionController(
            seed: 12,
            countdownSleeper: {},
            resultRecorder: { score in
                recordedScores.append(score)
                return RunResult(
                    score: score,
                    previousBest: 200,
                    localBest: max(200, score),
                    isNewBest: score > 200
                )
            }
        )
        await waitUntil { controller.presentationPhase == .racing }
        let firstCrash = snapshot(
            from: controller.scene.currentSnapshot,
            phase: .crashed,
            score: 250,
            speed: 12
        )
        controller.receive(
            snapshot: firstCrash,
            events: [.collision(obstacleID: 1, kind: .barrier)]
        )
        let firstResult = try? XCTUnwrap(result(from: controller.presentationPhase))

        controller.receive(
            snapshot: snapshot(from: firstCrash, phase: .crashed, score: 999, speed: 0),
            events: [.collision(obstacleID: 1, kind: .barrier)]
        )

        XCTAssertEqual(recordedScores, [250])
        XCTAssertEqual(result(from: controller.presentationPhase), firstResult)
        XCTAssertEqual(firstResult?.score, 250)
        XCTAssertEqual(firstResult?.previousBest, 200)
        XCTAssertEqual(firstResult?.localBest, 250)
        XCTAssertEqual(firstResult?.isNewBest, true)

        controller.retry()
        await waitUntil { controller.presentationPhase == .racing }
        let secondCrash = snapshot(
            from: controller.scene.currentSnapshot,
            phase: .crashed,
            score: 100,
            speed: 12
        )
        controller.receive(
            snapshot: secondCrash,
            events: [.collision(obstacleID: 1, kind: .barrier)]
        )

        XCTAssertEqual(recordedScores, [250, 100])
        XCTAssertEqual(firstResult?.score, 250)
        XCTAssertEqual(result(from: controller.presentationPhase)?.localBest, 200)
        XCTAssertEqual(result(from: controller.presentationPhase)?.isNewBest, false)
    }

    private func completeCountdown(
        _ controller: GameSessionController,
        sleeper: ManualCountdownSleeper
    ) async {
        await waitUntil { sleeper.pendingCount == 1 }
        sleeper.resumeNext()
        await waitUntil { controller.presentationPhase == .countdown(2) }
        await waitUntil { sleeper.pendingCount == 1 }
        sleeper.resumeNext()
        await waitUntil { controller.presentationPhase == .countdown(1) }
        await waitUntil { sleeper.pendingCount == 1 }
        sleeper.resumeNext()
        await waitUntil { controller.presentationPhase == .racing }
    }

    private func waitUntil(
        _ predicate: @MainActor () -> Bool,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        for _ in 0..<1_000 {
            if predicate() {
                return
            }
            await Task.yield()
        }
        XCTFail("Condition did not become true", file: file, line: line)
    }

    private func result(from phase: RunPresentationPhase) -> RunResult? {
        guard case let .result(result) = phase else { return nil }
        return result
    }

    private func snapshot(
        from snapshot: GameSnapshot,
        phase: GamePhase,
        score: Int,
        speed: Double
    ) -> GameSnapshot {
        GameSnapshot(
            phase: phase,
            playerX: snapshot.playerX,
            playerWidth: snapshot.playerWidth,
            playerLength: snapshot.playerLength,
            roadHalfWidth: snapshot.roadHalfWidth,
            laneWidth: snapshot.laneWidth,
            obstacles: snapshot.obstacles,
            score: score,
            speed: speed,
            elapsedTime: snapshot.elapsedTime,
            distance: snapshot.distance,
            spawnInterval: snapshot.spawnInterval
        )
    }

    private func activeReading(
        sequence: UInt64 = 1,
        value: Double
    ) -> WatchSteeringReading {
        WatchSteeringReading(
            value: value,
            availability: .active,
            sampleID: WatchSteeringSampleID(
                streamID: UUID(uuidString: "99999999-8888-7777-6666-555555555555")!,
                sequence: sequence
            )
        )
    }

    private func makeScene(
        seed: UInt64,
        configuration: GameSimulation.Configuration
    ) throws -> GameScene {
        let appearance = try XCTUnwrap(
            VehicleCatalog.resolve(VehicleCatalog.defaultSelection)
        )
        return try GameScene(
            seed: seed,
            configuration: configuration,
            appearance: appearance,
            assetLibrary: GameAssetLibrary()
        )
    }
}

@MainActor
private final class FakeWatchInput: WatchSteeringReadingProviding {
    var reading: WatchSteeringReading
    private(set) var readCount = 0

    init(reading: WatchSteeringReading) {
        self.reading = reading
    }

    func routingReading(at now: TimeInterval) -> WatchSteeringReading {
        readCount += 1
        return reading
    }
}

@MainActor
private final class FakeMonotonicClock {
    var now: TimeInterval

    init(now: TimeInterval) {
        self.now = now
    }
}

@MainActor
private final class ManualCountdownSleeper {
    private var continuations: [CheckedContinuation<Void, Never>] = []
    private(set) var sleepCallCount = 0

    var pendingCount: Int {
        continuations.count
    }

    func sleep() async throws {
        try Task.checkCancellation()
        sleepCallCount += 1
        await withCheckedContinuation { continuation in
            continuations.append(continuation)
        }
        try Task.checkCancellation()
    }

    func resumeNext() {
        precondition(!continuations.isEmpty, "No countdown sleep is pending")
        continuations.removeFirst().resume()
    }
}
