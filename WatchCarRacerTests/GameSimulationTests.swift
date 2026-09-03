import XCTest
@testable import WatchCarRacer

final class GameSimulationTests: XCTestCase {
    func testSameSeedAndInputsProduceIdenticalSnapshotsAndEvents() {
        var configuration = GameSimulation.Configuration()
        configuration.spawnDistance = 500
        var first = GameSimulation(seed: 42, configuration: configuration)
        var second = GameSimulation(seed: 42, configuration: configuration)

        for frame in 0..<360 {
            let steering = Double((frame % 9) - 4) / 4
            let firstEvents = first.step(dt: 1.0 / 60.0, steering: steering)
            let secondEvents = second.step(dt: 1.0 / 60.0, steering: steering)

            XCTAssertEqual(firstEvents, secondEvents)
            XCTAssertEqual(first.snapshot, second.snapshot)
        }
    }

    func testSpawnRowsBlockExactlyOneValidLane() {
        var configuration = GameSimulation.Configuration()
        configuration.firstSpawnDelay = 0.01
        configuration.initialSpawnInterval = 0.1
        configuration.minimumSpawnInterval = 0.1
        configuration.spawnDistance = 10_000
        var simulation = GameSimulation(seed: 7, configuration: configuration)

        for _ in 0..<180 {
            _ = simulation.step(dt: 1.0 / 60.0, steering: 0)
        }

        let snapshot = simulation.snapshot
        XCTAssertGreaterThan(snapshot.obstacles.count, 20)
        let rows = Dictionary(grouping: snapshot.obstacles, by: \.rowID)
        XCTAssertTrue(rows.values.allSatisfy { $0.count == 1 })
        let laneCenterOffset = (Double(GameSimulation.laneCount) - 1) / 2
        for obstacle in snapshot.obstacles {
            XCTAssertTrue((0..<GameSimulation.laneCount).contains(obstacle.laneIndex))
            XCTAssertEqual(
                obstacle.x,
                (Double(obstacle.laneIndex) - laneCenterOffset) * snapshot.laneWidth
            )
            XCTAssertLessThanOrEqual(abs(obstacle.x) + obstacle.width / 2, snapshot.roadHalfWidth)
            XCTAssertLessThan(obstacle.width, snapshot.laneWidth)
        }
    }

    func testSteeringClampsPlayerAtBothRoadEdges() {
        var configuration = GameSimulation.Configuration()
        configuration.spawnDistance = 10_000
        var simulation = GameSimulation(seed: 1, configuration: configuration)

        for _ in 0..<120 {
            _ = simulation.step(dt: 1.0 / 60.0, steering: 1)
        }
        var snapshot = simulation.snapshot
        XCTAssertEqual(
            snapshot.playerX,
            snapshot.roadHalfWidth - snapshot.playerWidth / 2,
            accuracy: 0.000_001
        )

        for _ in 0..<240 {
            _ = simulation.step(dt: 1.0 / 60.0, steering: -1)
        }
        snapshot = simulation.snapshot
        XCTAssertEqual(
            snapshot.playerX,
            -(snapshot.roadHalfWidth - snapshot.playerWidth / 2),
            accuracy: 0.000_001
        )
    }

    func testDifficultyReachesButNeverExceedsFixedCaps() {
        var configuration = GameSimulation.Configuration()
        configuration.spawnDistance = 1_000_000
        var simulation = GameSimulation(seed: 2, configuration: configuration)

        for _ in 0..<(65 * 60) {
            _ = simulation.step(dt: 1.0 / 60.0, steering: 0)
            XCTAssertLessThanOrEqual(
                simulation.snapshot.speed,
                configuration.maximumSpeed * configuration.boosterSpeedMultiplier
            )
            XCTAssertGreaterThanOrEqual(
                simulation.snapshot.spawnInterval,
                configuration.minimumSpawnInterval
            )
        }

        XCTAssertEqual(simulation.snapshot.speed, configuration.maximumSpeed, accuracy: 0.000_001)
        XCTAssertEqual(
            simulation.snapshot.spawnInterval,
            configuration.minimumSpawnInterval,
            accuracy: 0.000_001
        )
    }

    func testBothObstacleKindsAppearAndHaveDistinctClosingBehavior() throws {
        var configuration = GameSimulation.Configuration()
        configuration.firstSpawnDelay = 0.01
        configuration.initialSpawnInterval = 100
        configuration.minimumSpawnInterval = 100
        configuration.spawnDistance = 100

        var simulations: [ObstacleKind: GameSimulation] = [:]
        for seed in UInt64(0)..<64 where simulations.count < 2 {
            var simulation = GameSimulation(seed: seed, configuration: configuration)
            _ = simulation.step(dt: 0.02, steering: 0)
            let obstacle = try XCTUnwrap(simulation.snapshot.obstacles.first)
            simulations[obstacle.kind] = simulation
        }

        XCTAssertEqual(Set(simulations.keys), [.barrier, .trafficCar])
        var barrierSimulation = try XCTUnwrap(simulations[.barrier])
        var trafficSimulation = try XCTUnwrap(simulations[.trafficCar])
        let barrierStart = try XCTUnwrap(barrierSimulation.snapshot.obstacles.first).distance
        let trafficStart = try XCTUnwrap(trafficSimulation.snapshot.obstacles.first).distance

        _ = barrierSimulation.step(dt: 0.05, steering: 0)
        _ = trafficSimulation.step(dt: 0.05, steering: 0)

        let barrier = try XCTUnwrap(barrierSimulation.snapshot.obstacles.first)
        let traffic = try XCTUnwrap(trafficSimulation.snapshot.obstacles.first)
        XCTAssertGreaterThan(barrier.closingSpeed, traffic.closingSpeed)
        XCTAssertGreaterThan(barrierStart - barrier.distance, trafficStart - traffic.distance)
    }

    func testCollisionEmitsOnceAndRunRemainsCrashed() throws {
        let configuration = isolatedObstacleConfiguration()
        var simulation = GameSimulation(seed: 11, configuration: configuration)
        _ = simulation.step(dt: 0.02, steering: 0)
        let obstacle = try XCTUnwrap(simulation.snapshot.obstacles.first)
        var collisionEvents: [GameEvent] = []

        for _ in 0..<180 where simulation.snapshot.phase == .running {
            let steering = steering(from: simulation.snapshot.playerX, toward: obstacle.x, configuration: configuration)
            collisionEvents += simulation.step(dt: 1.0 / 60.0, steering: steering)
        }

        XCTAssertEqual(
            collisionEvents,
            [.collision(obstacleID: obstacle.id, kind: obstacle.kind)]
        )
        XCTAssertEqual(simulation.snapshot.phase, .crashed)
        let crashedSnapshot = simulation.snapshot
        for _ in 0..<10 {
            XCTAssertTrue(simulation.step(dt: 1.0 / 60.0, steering: 0).isEmpty)
            XCTAssertEqual(simulation.snapshot, crashedSnapshot)
        }
    }

    func testNearMissEmitsAndAwardsBonusOnceWithoutCollision() throws {
        let configuration = isolatedObstacleConfiguration()
        var simulation = GameSimulation(seed: 15, configuration: configuration)
        _ = simulation.step(dt: 0.02, steering: 0)
        let obstacle = try XCTUnwrap(simulation.snapshot.obstacles.first)
        let combinedHalfWidth = (obstacle.width + configuration.playerWidth) / 2
        let targetX = obstacle.x >= 0
            ? obstacle.x - combinedHalfWidth - 0.1
            : obstacle.x + combinedHalfWidth + 0.1
        var events: [GameEvent] = []

        for _ in 0..<240 {
            let steering = steering(from: simulation.snapshot.playerX, toward: targetX, configuration: configuration)
            events += simulation.step(dt: 1.0 / 60.0, steering: steering)
        }

        XCTAssertEqual(
            events,
            [.nearMiss(obstacleID: obstacle.id, kind: obstacle.kind, bonus: configuration.nearMissBonus)]
        )
        XCTAssertEqual(simulation.snapshot.phase, .running)
        XCTAssertEqual(
            simulation.snapshot.score - Int(simulation.snapshot.distance.rounded(.down)),
            configuration.nearMissBonus
        )
    }

    func testScoreDistanceAndResetRestoreInitialDeterministicSequence() {
        var configuration = GameSimulation.Configuration()
        configuration.spawnDistance = 500
        let seed: UInt64 = 99
        var simulation = GameSimulation(seed: seed, configuration: configuration)
        let initial = simulation.snapshot
        var firstRun: [(GameSnapshot, [GameEvent])] = []

        for frame in 0..<240 {
            let events = simulation.step(dt: 1.0 / 60.0, steering: frame.isMultiple(of: 2) ? 0.5 : -0.25)
            firstRun.append((simulation.snapshot, events))
        }

        XCTAssertGreaterThan(simulation.snapshot.distance, 0)
        XCTAssertGreaterThan(simulation.snapshot.score, 0)
        simulation.reset(seed: seed)
        XCTAssertEqual(simulation.snapshot, initial)

        for (frame, expected) in firstRun.enumerated() {
            let events = simulation.step(dt: 1.0 / 60.0, steering: frame.isMultiple(of: 2) ? 0.5 : -0.25)
            XCTAssertEqual(simulation.snapshot, expected.0)
            XCTAssertEqual(events, expected.1)
        }
    }

    func testInvalidDeltaTimeCannotCorruptState() {
        var simulation = GameSimulation(seed: 5)
        let initial = simulation.snapshot

        for deltaTime in [Double.nan, .infinity, -.infinity, 0, -1] {
            XCTAssertTrue(simulation.step(dt: deltaTime, steering: 1).isEmpty)
            XCTAssertEqual(simulation.snapshot, initial)
        }

        XCTAssertTrue(simulation.step(dt: 1.0 / 60.0, steering: .nan).isEmpty)
        XCTAssertTrue(simulation.snapshot.playerX.isFinite)
        XCTAssertTrue(simulation.snapshot.distance.isFinite)
        XCTAssertGreaterThan(simulation.snapshot.distance, 0)
    }

    func testAutomaticBoosterChargesForFiveSecondsAndRunsForThreeSeconds() {
        var configuration = GameSimulation.Configuration()
        configuration.spawnDistance = 1_000_000
        var simulation = GameSimulation(seed: 25, configuration: configuration)
        let step = 1.0 / 60.0

        for _ in 0..<299 {
            _ = simulation.step(dt: step, steering: 0)
        }
        XCTAssertFalse(simulation.snapshot.booster.isActive)
        XCTAssertGreaterThan(simulation.snapshot.booster.chargeProgress, 0.99)

        _ = simulation.step(dt: step, steering: 0)
        XCTAssertTrue(simulation.snapshot.booster.isActive)
        XCTAssertEqual(
            simulation.snapshot.booster.remainingDuration,
            configuration.boosterActiveDuration,
            accuracy: 0.000_001
        )
        let boostedSpeed = simulation.snapshot.speed

        for _ in 0..<180 {
            _ = simulation.step(dt: step, steering: 0)
        }
        XCTAssertFalse(simulation.snapshot.booster.isActive)
        XCTAssertEqual(simulation.snapshot.booster.chargeProgress, 0, accuracy: 0.000_001)
        XCTAssertLessThan(simulation.snapshot.speed, boostedSpeed)
    }

    func testGuardContactResetsBoosterChargeAndCancelsActiveBoost() {
        var configuration = GameSimulation.Configuration()
        configuration.spawnDistance = 1_000_000
        configuration.boosterChargeDuration = 0.25
        configuration.boosterActiveDuration = 3
        var simulation = GameSimulation(seed: 26, configuration: configuration)
        let step = 1.0 / 60.0

        for _ in 0..<15 {
            _ = simulation.step(dt: step, steering: 0)
        }
        XCTAssertTrue(simulation.snapshot.booster.isActive)

        for _ in 0..<60 where simulation.snapshot.booster.isActive {
            _ = simulation.step(dt: step, steering: 1)
        }

        XCTAssertFalse(simulation.snapshot.booster.isActive)
        XCTAssertEqual(simulation.snapshot.booster.chargeProgress, 0, accuracy: 0.000_001)
        XCTAssertEqual(
            simulation.snapshot.playerX,
            simulation.snapshot.roadHalfWidth - simulation.snapshot.playerWidth / 2,
            accuracy: 0.000_001
        )
    }

    func testCPUSprintCapsRivalsAtThreeAndFinishesWithRank() {
        var configuration = GameSimulation.Configuration()
        configuration.mode = .cpuSprint
        configuration.cpuCount = 99
        configuration.sprintDistance = 50
        configuration.boosterChargeDuration = 1_000
        var simulation = GameSimulation(seed: 27, configuration: configuration)

        XCTAssertEqual(simulation.snapshot.gameMode, .cpuSprint)
        XCTAssertEqual(simulation.snapshot.cpuRacers.count, 3)
        XCTAssertEqual(simulation.snapshot.fieldSize, 4)
        XCTAssertTrue(simulation.snapshot.obstacles.isEmpty)
        XCTAssertEqual(Set(simulation.snapshot.cpuRacers.map(\.id)).count, 3)
        XCTAssertTrue(simulation.snapshot.cpuRacers.allSatisfy { $0.distance > 0 })

        for _ in 0..<1_000 where simulation.snapshot.phase == .running {
            XCTAssertTrue(simulation.step(dt: 1.0 / 60.0, steering: 0).isEmpty)
        }

        XCTAssertEqual(simulation.snapshot.phase, .finished)
        XCTAssertEqual(simulation.snapshot.distance, configuration.sprintDistance, accuracy: 0.001)
        XCTAssertTrue((1...4).contains(simulation.snapshot.playerPlace ?? 0))
        XCTAssertEqual(simulation.snapshot.raceDistance, configuration.sprintDistance)
    }

    func testCPUSprintPacingKeepsARivalInContentionAfterRepeatedBoosts() {
        var configuration = GameSimulation.Configuration()
        configuration.mode = .cpuSprint
        configuration.cpuCount = 3
        var simulation = GameSimulation(seed: 28, configuration: configuration)

        for _ in 0..<(20 * 60) {
            _ = simulation.step(dt: 1.0 / 60.0, steering: 0)
        }

        let gaps = simulation.snapshot.cpuRacers.map {
            abs($0.distance - simulation.snapshot.distance)
        }
        let forwardGaps = simulation.snapshot.cpuRacers.map {
            $0.distance - simulation.snapshot.distance
        }
        XCTAssertLessThanOrEqual(gaps.min() ?? .infinity, 12)
        XCTAssertTrue(
            forwardGaps.contains { (0...20).contains($0) },
            "Expected a visible rival ahead; gaps were \(forwardGaps)"
        )
        XCTAssertTrue((1...4).contains(simulation.snapshot.playerPlace ?? 0))
    }

    func testCPUSprintVehicleContactsPreventInterpenetrationAndReducePlayerSpeed() throws {
        var configuration = GameSimulation.Configuration()
        configuration.mode = .cpuSprint
        configuration.cpuCount = 1
        configuration.sprintDistance = 2_000
        configuration.sprintInitialSpeed = 20
        configuration.sprintMaximumSpeed = 20
        configuration.boosterChargeDuration = 1_000
        var simulation = GameSimulation(seed: 29, configuration: configuration)
        let step = 1.0 / 60.0
        var observedContact = false
        var observedSpeedLoss = false

        for _ in 0..<(20 * 60) {
            let snapshot = simulation.snapshot
            let rival = try XCTUnwrap(snapshot.cpuRacers.first)
            let steering = steering(
                from: snapshot.playerX,
                toward: rival.x,
                configuration: configuration
            )
            _ = simulation.step(dt: step, steering: steering)

            let updated = simulation.snapshot
            let updatedRival = try XCTUnwrap(updated.cpuRacers.first)
            let lateralGap = abs(updated.playerX - updatedRival.x)
            let longitudinalGap = abs(updated.distance - updatedRival.distance)
            let overlapsLaterally = lateralGap < updated.playerWidth - 0.000_001
            let overlapsLongitudinally = longitudinalGap < updated.playerLength - 0.000_001

            XCTAssertFalse(
                overlapsLaterally && overlapsLongitudinally,
                "Player and CPU racer interpenetrated at lateral gap \(lateralGap), longitudinal gap \(longitudinalGap)"
            )
            if overlapsLaterally,
               longitudinalGap <= updated.playerLength + 0.000_1 {
                observedContact = true
                observedSpeedLoss = observedSpeedLoss
                    || updated.speed < configuration.sprintInitialSpeed - 0.1
            }
        }

        XCTAssertTrue(observedContact)
        XCTAssertTrue(observedSpeedLoss)
    }

    func testFiveMinuteEquivalentSimulationRoutingAndRetrySoakRemainsValid() {
        let step = 1.0 / 60.0
        let totalFrames = 5 * 60 * 60
        let streamID = UUID(uuidString: "12345678-1234-5678-1234-567812345678")!
        var configuration = GameSimulation.Configuration()
        configuration.firstSpawnDelay = 0.01
        configuration.initialSpawnInterval = 4
        configuration.minimumSpawnInterval = 4
        configuration.spawnDistance = 12
        let seed: UInt64 = 0x5A17
        var simulation = GameSimulation(seed: seed, configuration: configuration)
        var router = SteeringInputRouter()
        var sequence: UInt64 = 0
        var retryCount = 0
        var priorWatchValue = 0.0

        for frame in 0..<totalFrames {
            let time = Double(frame) * step
            let cycleFrame = frame % 720
            let desiredSteering = steeringTowardNearestObstacle(
                in: simulation.snapshot,
                configuration: configuration
            )
            let availability: WatchSteeringAvailability
            switch cycleFrame {
            case 0..<240:
                availability = .active
            case 240..<480:
                availability = .unreachable
            case 480..<600:
                availability = .needsCalibration
            default:
                availability = .active
            }

            let reading: WatchSteeringReading
            if availability == .active {
                sequence += 1
                priorWatchValue = desiredSteering
                reading = WatchSteeringReading(
                    value: desiredSteering,
                    availability: .active,
                    sampleID: WatchSteeringSampleID(streamID: streamID, sequence: sequence)
                )
            } else {
                reading = WatchSteeringReading(
                    value: priorWatchValue,
                    availability: availability,
                    sampleID: WatchSteeringSampleID(streamID: streamID, sequence: sequence)
                )
            }

            let fallbackFrame = cycleFrame >= 240 ? cycleFrame - 240 : -1
            let isTouchDragging = availability != .active && fallbackFrame >= 20
            let touchValue = isTouchDragging ? desiredSteering : 0
            let routed = router.steeringSnapshot(
                at: time,
                watch: reading,
                touchValue: touchValue,
                isTouchDragging: isTouchDragging
            )

            XCTAssertTrue(routed.value.isFinite)
            XCTAssertLessThanOrEqual(abs(routed.value), 1)
            if (9..<20).contains(fallbackFrame) {
                XCTAssertEqual(routed.source, .touch)
                XCTAssertEqual(routed.value, 0, accuracy: 0.000_001)
            }

            let events = simulation.step(dt: step, steering: routed.value)
            let snapshot = simulation.snapshot
            assertValidSoakSnapshot(snapshot, configuration: configuration)

            if snapshot.phase == .crashed {
                XCTAssertTrue(events.contains { event in
                    if case .collision = event {
                        return true
                    }
                    return false
                })
                retryCount += 1
                simulation.reset(seed: seed)
                router.reset(retiring: reading)
                XCTAssertEqual(simulation.snapshot.phase, .running)
                XCTAssertEqual(simulation.snapshot.playerX, 0)

                let afterRetry = router.steeringSnapshot(
                    at: time,
                    watch: reading,
                    touchValue: 0,
                    isTouchDragging: false
                )
                XCTAssertEqual(afterRetry.source, .touch)
                XCTAssertEqual(afterRetry.value, 0)
                XCTAssertNotEqual(afterRetry.availability, .available)
            }
        }

        XCTAssertGreaterThan(retryCount, 5)
    }

    private func isolatedObstacleConfiguration() -> GameSimulation.Configuration {
        var configuration = GameSimulation.Configuration()
        configuration.firstSpawnDelay = 0.01
        configuration.initialSpawnInterval = 100
        configuration.minimumSpawnInterval = 100
        configuration.spawnDistance = 8
        return configuration
    }

    private func steering(
        from currentX: Double,
        toward targetX: Double,
        configuration: GameSimulation.Configuration
    ) -> Double {
        let oneFrameTravel = configuration.playerLateralSpeed / 60
        return min(max((targetX - currentX) / oneFrameTravel, -1), 1)
    }

    private func steeringTowardNearestObstacle(
        in snapshot: GameSnapshot,
        configuration: GameSimulation.Configuration
    ) -> Double {
        guard let obstacle = snapshot.obstacles.min(by: { $0.distance < $1.distance }) else {
            return 0
        }
        return steering(
            from: snapshot.playerX,
            toward: obstacle.x,
            configuration: configuration
        )
    }

    private func assertValidSoakSnapshot(
        _ snapshot: GameSnapshot,
        configuration: GameSimulation.Configuration,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertTrue(snapshot.playerX.isFinite, file: file, line: line)
        XCTAssertTrue(snapshot.speed.isFinite, file: file, line: line)
        XCTAssertTrue(snapshot.elapsedTime.isFinite, file: file, line: line)
        XCTAssertTrue(snapshot.distance.isFinite, file: file, line: line)
        XCTAssertTrue(snapshot.spawnInterval.isFinite, file: file, line: line)
        XCTAssertGreaterThanOrEqual(
            snapshot.playerX,
            -snapshot.roadHalfWidth + snapshot.playerWidth / 2,
            file: file,
            line: line
        )
        XCTAssertLessThanOrEqual(
            snapshot.playerX,
            snapshot.roadHalfWidth - snapshot.playerWidth / 2,
            file: file,
            line: line
        )
        XCTAssertGreaterThanOrEqual(snapshot.speed, configuration.initialSpeed, file: file, line: line)
        XCTAssertLessThanOrEqual(
            snapshot.speed,
            configuration.maximumSpeed * configuration.boosterSpeedMultiplier,
            file: file,
            line: line
        )
        XCTAssertGreaterThanOrEqual(
            snapshot.spawnInterval,
            configuration.minimumSpawnInterval,
            file: file,
            line: line
        )
        XCTAssertGreaterThanOrEqual(snapshot.score, 0, file: file, line: line)
        for obstacle in snapshot.obstacles {
            XCTAssertTrue(obstacle.x.isFinite, file: file, line: line)
            XCTAssertTrue(obstacle.distance.isFinite, file: file, line: line)
            XCTAssertTrue(obstacle.closingSpeed.isFinite, file: file, line: line)
            XCTAssertTrue(
                (0..<GameSimulation.laneCount).contains(obstacle.laneIndex),
                file: file,
                line: line
            )
            XCTAssertLessThanOrEqual(
                abs(obstacle.x) + obstacle.width / 2,
                snapshot.roadHalfWidth,
                file: file,
                line: line
            )
        }
    }
}
