import SpriteKit
import XCTest
@testable import WatchCarRacer

@MainActor
final class GameSessionControllerTests: XCTestCase {
    func testSnapshotAndCollisionEventBridgeToHUDStateAndDelayedResultPresentation() async {
        let collisionSleeper = ManualDurationSleeper()
        let controller = GameSessionController(
            seed: 7,
            collisionSleeper: { try await collisionSleeper.sleep(for: $0) }
        )
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
            .collision(
                RunResult(
                    score: 321,
                    previousBest: 0,
                    localBest: 321,
                    isNewBest: true
                )
            )
        )
        XCTAssertFalse(controller.scene.isPaused)
        XCTAssertFalse(controller.acceptsTouchInput)

        await waitUntil { collisionSleeper.pendingCount == 1 }
        XCTAssertEqual(collisionSleeper.pendingDurations, [0.52])
        collisionSleeper.resumeNext()
        await waitUntil {
            if case .result = controller.presentationPhase { true } else { false }
        }
        XCTAssertTrue(controller.scene.isPaused)
    }

    func testCPUSprintFinishTransitionsDirectlyToResultWithoutCollisionDelay() {
        var configuration = GameSimulation.Configuration()
        configuration.mode = .cpuSprint
        configuration.cpuCount = 2
        let result = RunResult(
            score: 1_000,
            previousBest: 500,
            localBest: 500,
            isNewBest: false
        )
        var recordedScores: [Int] = []
        let collisionSleeper = ManualDurationSleeper()
        let controller = GameSessionController(
            seed: 8,
            configuration: configuration,
            collisionSleeper: { try await collisionSleeper.sleep(for: $0) },
            resultRecorder: { score in
                recordedScores.append(score)
                return result
            }
        )
        let running = controller.renderSnapshot
        let finished = GameSnapshot(
            phase: .finished,
            playerX: running.playerX,
            playerWidth: running.playerWidth,
            playerLength: running.playerLength,
            roadHalfWidth: running.roadHalfWidth,
            laneWidth: running.laneWidth,
            obstacles: running.obstacles,
            score: 1_000,
            speed: running.speed,
            elapsedTime: 42,
            distance: 1_000,
            spawnInterval: running.spawnInterval,
            gameMode: .cpuSprint,
            booster: running.booster,
            cpuRacers: running.cpuRacers,
            playerPlace: 2,
            fieldSize: 3,
            raceDistance: 1_000
        )

        controller.receive(snapshot: finished, events: [])

        XCTAssertEqual(controller.phase, .finished)
        XCTAssertEqual(controller.presentationPhase, .result(result))
        XCTAssertEqual(controller.renderSnapshot.playerPlace, 2)
        XCTAssertEqual(recordedScores, [1_000])
        XCTAssertTrue(controller.scene.isPaused)
        XCTAssertFalse(controller.acceptsTouchInput)
        XCTAssertEqual(collisionSleeper.pendingCount, 0)
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

    func testCatchUpEventKeepsFirstSubstepDirectionAndClosenessInsteadOfFinalSnapshot() throws {
        var configuration = GameSimulation.Configuration()
        configuration.playerLateralSpeed = 60
        configuration.initialSpeed = 12
        configuration.maximumSpeed = 12
        configuration.trafficCarSpeed = 6
        configuration.firstSpawnDelay = 0.01
        configuration.initialSpawnInterval = 100
        configuration.minimumSpawnInterval = 100
        configuration.spawnDistance = -1.95
        let scene = try makeScene(seed: 1, configuration: configuration)
        var steeringReadCount = 0
        scene.steeringProvider = { _ in
            defer { steeringReadCount += 1 }
            switch steeringReadCount {
            case 0:
                return 0.8
            case 1:
                return 0
            default:
                return 1
            }
        }
        var capturedPresentations: [GameEventPresentation] = []
        scene.frameHandler = { _, presentations in
            if !presentations.isEmpty {
                capturedPresentations = presentations
            }
        }

        scene.update(0)
        scene.update(GameScene.fixedStep * 1.1)
        scene.update(GameScene.fixedStep * 6.1)

        let presentation = try XCTUnwrap(capturedPresentations.first)
        let context = try XCTUnwrap(presentation.spatialContext)
        XCTAssertEqual(capturedPresentations.count, 1)
        XCTAssertEqual(
            presentation.event,
            .nearMiss(obstacleID: 0, kind: .trafficCar, bonus: 100)
        )
        XCTAssertEqual(steeringReadCount, 6)
        XCTAssertEqual(presentation.snapshot.playerX, 0.8, accuracy: 0.000_001)
        XCTAssertEqual(context.side, .right)
        XCTAssertEqual(context.closeness, 4.0 / 7.0, accuracy: 0.000_001)
        XCTAssertEqual(presentation.snapshot.score, 100)

        XCTAssertEqual(scene.currentSnapshot.playerX, 2.55, accuracy: 0.000_001)
        XCTAssertEqual(scene.currentSnapshot.score, 101)
        let finalSnapshotContext = try XCTUnwrap(
            GameEventPresentation(
                event: presentation.event,
                snapshot: scene.currentSnapshot,
                configuration: configuration
            ).spatialContext
        )
        XCTAssertEqual(finalSnapshotContext.side, .left)
        XCTAssertEqual(finalSnapshotContext.closeness, 1, accuracy: 0.000_001)
        XCTAssertNotEqual(context.side, finalSnapshotContext.side)
        XCTAssertNotEqual(context.closeness, finalSnapshotContext.closeness)
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
        XCTAssertTrue(controller.frameRateSamplePhases.allSatisfy { $0 == .racing })
        XCTAssertEqual(controller.frameRateSamplePhases.count, controller.frameRateSamples.count)
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
        let controller = GameSessionController(
            seed: 6,
            countdownSleeper: {},
            collisionSleeper: { _ in }
        )
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
        await waitUntil {
            if case .result = controller.presentationPhase { true } else { false }
        }
        let resultPhase = controller.presentationPhase

        XCTAssertTrue(controller.scene.isPaused)
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
            collisionSleeper: { _ in },
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
        await waitUntil {
            if case .result = controller.presentationPhase { true } else { false }
        }
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
        await waitUntil {
            if case .result = controller.presentationPhase { true } else { false }
        }

        XCTAssertEqual(recordedScores, [250, 100])
        XCTAssertEqual(firstResult?.score, 250)
        XCTAssertEqual(result(from: controller.presentationPhase)?.localBest, 200)
        XCTAssertEqual(result(from: controller.presentationPhase)?.isNewBest, false)
    }

    func testStartRitualEmitsExactCueContractAcrossThreeSecondsAndRemovesTokens() async {
        let countdownSleeper = ManualCountdownSleeper()
        let visibilitySleeper = ManualDurationSleeper()
        let clock = FakeMonotonicClock(now: 40)
        let phone = StartCueRecordingPhoneFeedbackPlayer()
        let watch = StartCueRecordingWatchFeedbackSender()
        let ids = StartCueIDSequence()
        let controller = GameSessionController(
            seed: 301,
            feedbackPlayer: phone,
            watchFeedbackSender: watch,
            currentTime: { clock.now },
            makeStartCueEventID: { ids.next() },
            countdownSleeper: { try await countdownSleeper.sleep() },
            presentationSleeper: { try await visibilitySleeper.sleep(for: $0) }
        )
        let initialSnapshot = controller.scene.currentSnapshot

        await assertVisibleCue(
            .three,
            controller: controller,
            sleeper: visibilitySleeper,
            duration: 0.18
        )
        await waitUntil { countdownSleeper.pendingCount == 1 }
        clock.now += 1
        countdownSleeper.resumeNext()
        await waitUntil { controller.presentationPhase == .countdown(2) }
        await assertVisibleCue(
            .two,
            controller: controller,
            sleeper: visibilitySleeper,
            duration: 0.18
        )
        await waitUntil { countdownSleeper.pendingCount == 1 }
        clock.now += 1
        countdownSleeper.resumeNext()
        await waitUntil { controller.presentationPhase == .countdown(1) }
        await assertVisibleCue(
            .one,
            controller: controller,
            sleeper: visibilitySleeper,
            duration: 0.18
        )
        await waitUntil { countdownSleeper.pendingCount == 1 }
        clock.now += 1
        countdownSleeper.resumeNext()
        await waitUntil { controller.presentationPhase == .racing }

        XCTAssertFalse(controller.scene.isPaused)
        XCTAssertTrue(controller.acceptsTouchInput)
        XCTAssertEqual(controller.scene.currentSnapshot, initialSnapshot)
        await assertVisibleCue(
            .go,
            controller: controller,
            sleeper: visibilitySleeper,
            duration: 0.26
        )

        XCTAssertEqual(phone.startCues.map(\.kind), [.three, .two, .one, .go])
        XCTAssertEqual(phone.startCues.map(\.audioRate), [0.88, 1, 1.12, 1])
        XCTAssertEqual(
            phone.startCues.map(\.visualTreatment),
            [.ring(.cyan), .ring(.mint), .ring(.orange), .fullScreenSweep(.mintWhite)]
        )
        XCTAssertEqual(
            phone.startCues.map(\.phoneImpact),
            [
                PhoneImpactCommand(style: .light, intensity: 0.35),
                PhoneImpactCommand(style: .rigid, intensity: 0.55),
                PhoneImpactCommand(style: .rigid, intensity: 0.75),
                PhoneImpactCommand(style: .heavy, intensity: 0.90),
            ]
        )
        XCTAssertEqual(phone.startCues.map(\.emittedAt), [40, 41, 42, 43])
        XCTAssertEqual(
            zip(phone.startCues.map(\.emittedAt), phone.startCues.dropFirst().map(\.emittedAt))
                .map { $1 - $0 },
            [1, 1, 1]
        )
        XCTAssertEqual(phone.startCues.last!.emittedAt - phone.startCues.first!.emittedAt, 3)
        XCTAssertEqual(Set(phone.startCues.map(\.id)).count, 4)
        XCTAssertEqual(watch.packets.map(\.eventID), phone.startCues.map(\.id))
        XCTAssertEqual(watch.packets.map(\.kind), [.countdownTick, .countdownTick, .countdownTick, .go])
        XCTAssertEqual(phone.startCues[0].opacity(for: .balanced), 1)
        XCTAssertEqual(phone.startCues[0].opacity(for: .reduced), 0.55)
    }

    func testInitialRetryAndForegroundReentryEachEmitAFreshCompleteRitual() async {
        let phone = StartCueRecordingPhoneFeedbackPlayer()
        let controller = GameSessionController(
            seed: 305,
            feedbackPlayer: phone,
            countdownSleeper: {},
            presentationSleeper: { _ in }
        )

        await waitUntil { phone.startCues.count == 4 }
        XCTAssertEqual(phone.startCues.map(\.kind), [.three, .two, .one, .go])

        controller.retry()
        await waitUntil { phone.startCues.count == 8 }
        XCTAssertEqual(
            Array(phone.startCues[4..<8]).map(\.kind),
            [.three, .two, .one, .go]
        )

        controller.handleLifecycle(.background)
        controller.handleLifecycle(.active)
        await waitUntil { phone.startCues.count == 12 }
        XCTAssertEqual(
            Array(phone.startCues[8..<12]).map(\.kind),
            [.three, .two, .one, .go]
        )
    }

    func testStaleCueRemovalCannotRemoveNewerCue() async {
        let countdownSleeper = ManualCountdownSleeper()
        let visibilitySleeper = ManualDurationSleeper()
        let controller = GameSessionController(
            seed: 302,
            countdownSleeper: { try await countdownSleeper.sleep() },
            presentationSleeper: { try await visibilitySleeper.sleep(for: $0) }
        )

        await waitUntil { controller.startCuePresentation?.kind == .three }
        let firstID = controller.startCuePresentation?.id
        controller.startCueDidBecomeVisible(id: firstID!)
        await waitUntil { visibilitySleeper.pendingCount == 1 }
        await waitUntil { countdownSleeper.pendingCount == 1 }
        countdownSleeper.resumeNext()
        await waitUntil { controller.presentationPhase == .countdown(2) }
        let secondID = controller.startCuePresentation?.id

        controller.startCueDidBecomeVisible(id: firstID!)
        await Task.yield()
        XCTAssertEqual(visibilitySleeper.pendingCount, 1)
        XCTAssertEqual(controller.startCuePresentation?.id, secondID)

        controller.startCueDidBecomeVisible(id: secondID!)
        await waitUntil { visibilitySleeper.pendingCount == 2 }

        visibilitySleeper.resumeNext()
        await Task.yield()
        XCTAssertNotEqual(firstID, secondID)
        XCTAssertEqual(controller.startCuePresentation?.id, secondID)

        visibilitySleeper.resumeNext()
        await waitUntil { controller.startCuePresentation == nil }
    }

    func testStartCueVisibilityTimerWaitsForViewMountAndRemovesAtExactContract() async {
        let countdownSleeper = ManualCountdownSleeper()
        let visibilitySleeper = ManualDurationSleeper()
        let controller = GameSessionController(
            seed: 306,
            countdownSleeper: { try await countdownSleeper.sleep() },
            presentationSleeper: { try await visibilitySleeper.sleep(for: $0) }
        )

        await waitUntil { controller.startCuePresentation?.kind == .three }
        let cue = controller.startCuePresentation!
        await Task.yield()
        XCTAssertEqual(visibilitySleeper.pendingCount, 0)
        XCTAssertFalse(controller.hasActiveStartCueTask)

        controller.startCueDidBecomeVisible(id: cue.id)
        await waitUntil { visibilitySleeper.pendingCount == 1 }
        XCTAssertEqual(visibilitySleeper.pendingDurations, [0.18])
        controller.startCueDidBecomeVisible(id: cue.id)
        await Task.yield()
        XCTAssertEqual(visibilitySleeper.pendingCount, 1)

        visibilitySleeper.resumeNext()
        await waitUntil { controller.startCuePresentation == nil }
        XCTAssertFalse(controller.hasActiveStartCueTask)
    }

    func testRetryBackgroundAndStopCancelAcknowledgedCueRemoval() async {
        let countdownSleeper = ManualCountdownSleeper()
        let visibilitySleeper = ManualDurationSleeper()
        let controller = GameSessionController(
            seed: 307,
            countdownSleeper: { try await countdownSleeper.sleep() },
            presentationSleeper: { try await visibilitySleeper.sleep(for: $0) }
        )

        await waitUntil { controller.startCuePresentation?.kind == .three }
        controller.startCueDidBecomeVisible(id: controller.startCuePresentation!.id)
        await waitUntil { visibilitySleeper.pendingCount == 1 }
        controller.retry()
        let retryCueID = controller.startCuePresentation!.id
        visibilitySleeper.resumeNext()
        await Task.yield()
        XCTAssertEqual(controller.startCuePresentation?.id, retryCueID)
        XCTAssertFalse(controller.hasActiveStartCueTask)

        controller.startCueDidBecomeVisible(id: retryCueID)
        await waitUntil { visibilitySleeper.pendingCount == 1 }
        controller.handleLifecycle(.background)
        XCTAssertNil(controller.startCuePresentation)
        XCTAssertFalse(controller.hasActiveStartCueTask)
        visibilitySleeper.resumeNext()
        await Task.yield()
        XCTAssertNil(controller.startCuePresentation)

        controller.handleLifecycle(.active)
        await waitUntil { controller.startCuePresentation?.kind == .three }
        controller.startCueDidBecomeVisible(id: controller.startCuePresentation!.id)
        await waitUntil { visibilitySleeper.pendingCount == 1 }
        controller.stop()
        XCTAssertNil(controller.startCuePresentation)
        XCTAssertFalse(controller.hasActiveStartCueTask)
        visibilitySleeper.resumeNext()
        await Task.yield()
        XCTAssertNil(controller.startCuePresentation)
    }

    func testCollisionRecordsAtZeroThenPromotesAt520MillisecondsAndCleansScene() async throws {
        let collisionSleeper = ManualDurationSleeper()
        var clock: TimeInterval = 0
        var recordedResults: [RunResult] = []
        let controller = GameSessionController(
            seed: 303,
            currentTime: { clock },
            countdownSleeper: {},
            collisionSleeper: { try await collisionSleeper.sleep(for: $0) },
            resultRecorder: { score in
                let result = RunResult(
                    score: score,
                    previousBest: 10,
                    localBest: score,
                    isNewBest: true
                )
                recordedResults.append(result)
                return result
            }
        )
        controller.scene.didMove(
            to: SKView(frame: CGRect(origin: .zero, size: controller.scene.size))
        )
        await waitUntil { controller.presentationPhase == .racing }
        let presentation = collisionPresentation(
            from: controller.scene.currentSnapshot,
            obstacleID: 55,
            sideX: -0.4,
            score: 432
        )

        controller.receive(
            snapshot: presentation.snapshot,
            presentationEvents: [presentation]
        )
        let recorded = try XCTUnwrap(recordedResults.first)

        XCTAssertEqual(recordedResults, [recorded])
        XCTAssertEqual(controller.presentationPhase, .collision(recorded))
        XCTAssertFalse(controller.acceptsTouchInput)
        XCTAssertFalse(controller.scene.isPaused)
        XCTAssertTrue(controller.scene.isCollisionPresentationActive)
        XCTAssertEqual(controller.scene.presentationDiagnostics.collisionImpactSide, .left)
        XCTAssertEqual(controller.scene.presentationDiagnostics.activeDebrisCount, 0)
        XCTAssertLessThanOrEqual(
            controller.scene.presentationDiagnostics.debrisNodeCount,
            24
        )

        controller.receive(
            snapshot: presentation.snapshot,
            presentationEvents: [presentation]
        )
        XCTAssertEqual(recordedResults, [recorded])
        XCTAssertEqual(controller.presentationPhase, .collision(recorded))

        await waitUntil { collisionSleeper.pendingCount == 1 }
        XCTAssertEqual(collisionSleeper.pendingDurations, [0.52])
        clock = 0.479
        XCTAssertEqual(controller.presentationPhase, .collision(recorded))
        XCTAssertFalse(controller.scene.isPaused)

        clock = 0.520
        collisionSleeper.resumeNext()
        await waitUntil { controller.presentationPhase == .result(recorded) }
        XCTAssertEqual(clock, 0.520)
        XCTAssertTrue(controller.scene.isPaused)
        XCTAssertFalse(controller.scene.isCollisionPresentationActive)
        XCTAssertEqual(controller.scene.presentationDiagnostics.activeDebrisCount, 0)
        XCTAssertEqual(controller.scene.presentationDiagnostics.nodesWithActions, 0)
    }

    func testCollisionLifecyclePromotionAndRetryCancelStaleCompletion() async {
        let collisionSleeper = ManualDurationSleeper()
        let controller = GameSessionController(
            seed: 304,
            countdownSleeper: {},
            collisionSleeper: { try await collisionSleeper.sleep(for: $0) }
        )
        await waitUntil { controller.presentationPhase == .racing }
        let crashed = snapshot(
            from: controller.scene.currentSnapshot,
            phase: .crashed,
            score: 77,
            speed: 12
        )
        controller.receive(
            snapshot: crashed,
            events: [.collision(obstacleID: 1, kind: .barrier)]
        )
        await waitUntil { collisionSleeper.pendingCount == 1 }
        guard case let .collision(result) = controller.presentationPhase else {
            return XCTFail("Expected collision phase")
        }

        controller.handleLifecycle(.inactive)
        XCTAssertEqual(controller.presentationPhase, .result(result))
        XCTAssertTrue(controller.scene.isPaused)
        XCTAssertFalse(controller.hasActiveCollisionTask)
        collisionSleeper.resumeNext()
        await Task.yield()
        controller.handleLifecycle(.active)
        XCTAssertEqual(controller.presentationPhase, .result(result))
        XCTAssertFalse(controller.hasActiveCountdownTask)

        controller.retry()
        await waitUntil { controller.presentationPhase == .racing }
        let secondCrash = snapshot(
            from: controller.scene.currentSnapshot,
            phase: .crashed,
            score: 88,
            speed: 12
        )
        controller.receive(
            snapshot: secondCrash,
            events: [.collision(obstacleID: 1, kind: .barrier)]
        )
        await waitUntil { collisionSleeper.pendingCount == 1 }
        controller.retry()
        controller.handleLifecycle(.inactive)
        let retryPhase = controller.presentationPhase
        collisionSleeper.resumeNext()
        await Task.yield()
        XCTAssertEqual(controller.presentationPhase, retryPhase)
        XCTAssertNotEqual(controller.presentationPhase, .result(result))
        XCTAssertTrue(controller.scene.isPaused)
    }

    private func assertVisibleCue(
        _ kind: StartCueKind,
        controller: GameSessionController,
        sleeper: ManualDurationSleeper,
        duration: TimeInterval
    ) async {
        await waitUntil { controller.startCuePresentation?.kind == kind }
        XCTAssertEqual(controller.startCuePresentation?.visibleDuration, duration)
        guard let cueID = controller.startCuePresentation?.id else {
            XCTFail("Expected a visible cue")
            return
        }
        XCTAssertEqual(sleeper.pendingCount, 0)
        controller.startCueDidBecomeVisible(id: cueID)
        await waitUntil { sleeper.pendingCount == 1 }
        XCTAssertEqual(sleeper.pendingDurations, [duration])
        sleeper.resumeNext()
        await waitUntil { controller.startCuePresentation == nil }
        await waitUntil { sleeper.pendingCount == 0 }
        if kind != .go {
            await waitUntil { controller.hasActiveCountdownTask }
        }
    }

    private func collisionPresentation(
        from base: GameSnapshot,
        obstacleID: UInt64,
        sideX: Double,
        score: Int
    ) -> GameEventPresentation {
        var configuration = GameSimulation.Configuration()
        configuration.playerWidth = base.playerWidth
        let obstacle = ObstacleSnapshot(
            id: obstacleID,
            rowID: obstacleID,
            kind: .barrier,
            laneIndex: 1,
            x: sideX,
            distance: 0,
            width: 1.7,
            length: 1,
            closingSpeed: 12,
            didAwardNearMiss: false
        )
        let crashed = GameSnapshot(
            phase: .crashed,
            playerX: 0,
            playerWidth: base.playerWidth,
            playerLength: base.playerLength,
            roadHalfWidth: base.roadHalfWidth,
            laneWidth: base.laneWidth,
            obstacles: [obstacle],
            score: score,
            speed: base.speed,
            elapsedTime: base.elapsedTime,
            distance: base.distance,
            spawnInterval: base.spawnInterval
        )
        return GameEventPresentation(
            event: .collision(obstacleID: obstacleID, kind: .barrier),
            snapshot: crashed,
            configuration: configuration
        )
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
        switch phase {
        case let .collision(result), let .result(result):
            return result
        case .countdown, .racing:
            return nil
        }
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
            spawnInterval: snapshot.spawnInterval,
            gameMode: snapshot.gameMode,
            booster: snapshot.booster,
            cpuRacers: snapshot.cpuRacers,
            playerPlace: snapshot.playerPlace,
            fieldSize: snapshot.fieldSize,
            raceDistance: snapshot.raceDistance
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

@MainActor
private final class ManualDurationSleeper {
    private struct PendingSleep {
        let duration: TimeInterval
        let continuation: CheckedContinuation<Void, Never>
    }

    private var pending: [PendingSleep] = []

    var pendingCount: Int {
        pending.count
    }

    var pendingDurations: [TimeInterval] {
        pending.map(\.duration)
    }

    func sleep(for duration: TimeInterval) async throws {
        await withCheckedContinuation { continuation in
            pending.append(PendingSleep(duration: duration, continuation: continuation))
        }
    }

    func resumeNext() {
        precondition(!pending.isEmpty, "No duration sleep is pending")
        pending.removeFirst().continuation.resume()
    }
}

@MainActor
private final class StartCueRecordingPhoneFeedbackPlayer: PhoneFeedbackPlaying {
    private(set) var feedback: [GameFeedback] = []
    private(set) var startCues: [StartCuePresentation] = []

    func play(_ feedback: GameFeedback) {
        self.feedback.append(feedback)
    }

    func playStartCue(_ cue: StartCuePresentation) {
        startCues.append(cue)
    }
}

@MainActor
private final class StartCueRecordingWatchFeedbackSender: WatchFeedbackSending {
    private(set) var packets: [WatchFeedbackPacket] = []

    func sendFeedback(_ packet: WatchFeedbackPacket) throws {
        packets.append(packet)
    }
}

@MainActor
private final class StartCueIDSequence {
    private var value: UInt64 = 0

    func next() -> UUID {
        value += 1
        return UUID(
            uuidString: String(
                format: "70000000-0000-0000-0000-%012llx",
                value
            )
        )!
    }
}
