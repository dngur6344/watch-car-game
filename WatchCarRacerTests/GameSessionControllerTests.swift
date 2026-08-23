import XCTest
@testable import WatchCarRacer

@MainActor
final class GameSessionControllerTests: XCTestCase {
    func testSnapshotAndCollisionEventBridgeToHUDState() {
        let controller = GameSessionController(seed: 7)
        let running = GameSimulation(seed: 7).snapshot
        let crashed = snapshot(from: running, phase: .crashed, score: 321, speed: 15)
        let collision = GameEvent.collision(obstacleID: 9, kind: .barrier)

        controller.receive(snapshot: crashed, events: [collision])

        XCTAssertEqual(controller.score, 321)
        XCTAssertEqual(controller.speed, 54)
        XCTAssertEqual(controller.phase, .crashed)
        XCTAssertEqual(controller.lastEvent, collision)
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
    }

    func testSceneCapsLargeFrameGapToFiveFixedSteps() {
        var configuration = GameSimulation.Configuration()
        configuration.spawnDistance = 10_000
        let scene = GameScene(seed: 1, configuration: configuration)
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
    func testSceneReportsRollingFrameRateWithoutChangingSimulationTiming() {
        var configuration = GameSimulation.Configuration()
        configuration.spawnDistance = 10_000
        let scene = GameScene(seed: 1, configuration: configuration)
        var samples: [Double] = []
        scene.frameRateHandler = { samples.append($0) }

        scene.update(0)
        for frame in 1...120 {
            scene.update(Double(frame) / 60)
        }

        XCTAssertEqual(scene.currentSnapshot.elapsedTime, 2, accuracy: 0.000_001)
        XCTAssertGreaterThanOrEqual(samples.count, 3)
        XCTAssertLessThanOrEqual(samples.count, 4)
        XCTAssertTrue(samples.allSatisfy { abs($0 - 60) < 0.000_001 })
    }
#endif

    func testControllerReadsExactlyOneRoutedSnapshotPerFixedSimulationStep() {
        var configuration = GameSimulation.Configuration()
        configuration.spawnDistance = 10_000
        let watchInput = FakeWatchInput(reading: activeReading(value: 0.7))
        let clock = FakeMonotonicClock(now: 5)
        let controller = GameSessionController(
            seed: 1,
            configuration: configuration,
            watchInput: watchInput,
            currentTime: { clock.now }
        )

        controller.scene.update(10)
        controller.scene.update(20)

        XCTAssertEqual(watchInput.readCount, GameScene.maximumStepsPerFrame)
        XCTAssertEqual(controller.steeringSnapshot.source, .watch)
        XCTAssertEqual(controller.steeringSnapshot.value, 0.7)
        XCTAssertGreaterThan(controller.scene.currentSnapshot.playerX, 0)
    }

    func testRetryClearsRoutedValueAndRequiresANewWatchSample() {
        var configuration = GameSimulation.Configuration()
        configuration.spawnDistance = 10_000
        let watchInput = FakeWatchInput(reading: activeReading(value: -0.8))
        let clock = FakeMonotonicClock(now: 5)
        let controller = GameSessionController(
            seed: 3,
            configuration: configuration,
            watchInput: watchInput,
            currentTime: { clock.now }
        )

        controller.scene.update(10)
        controller.scene.update(10.02)
        XCTAssertEqual(controller.steeringSnapshot.source, .watch)
        XCTAssertEqual(controller.steeringSnapshot.value, -0.8)

        controller.retry()

        XCTAssertEqual(controller.steeringSnapshot.source, .touch)
        XCTAssertEqual(controller.steeringSnapshot.value, 0)
        XCTAssertEqual(controller.steeringSnapshot.availability, .fallback(.awaitingFreshPacket))

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
