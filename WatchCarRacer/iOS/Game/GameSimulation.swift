import Foundation

enum GamePhase: Equatable, Sendable {
    case running
    case crashed
    case finished
}

enum GameMode: String, CaseIterable, Identifiable, Sendable {
    case survival
    case cpuSprint = "cpu-sprint"

    var id: Self { self }

    var displayName: String {
        switch self {
        case .survival: "SURVIVAL"
        case .cpuSprint: "CPU SPRINT"
        }
    }

    var detail: String {
        switch self {
        case .survival:
            "Dodge traffic and barriers to set the highest score."
        case .cpuSprint:
            "Race up to three CPU rivals over a 1,000 m sprint."
        }
    }
}

struct GameModeSelection: Equatable, Sendable {
    var mode: GameMode
    var cpuCount: Int

    static let `default` = GameModeSelection(mode: .survival, cpuCount: 3)
}

enum BoosterPhase: Equatable, Sendable {
    case charging
    case active
}

struct BoosterSnapshot: Equatable, Sendable {
    let phase: BoosterPhase
    let chargeProgress: Double
    let remainingDuration: TimeInterval

    var isActive: Bool {
        phase == .active
    }

    static let initial = BoosterSnapshot(
        phase: .charging,
        chargeProgress: 0,
        remainingDuration: 5
    )
}

struct CPURacerSnapshot: Equatable, Sendable {
    let id: UInt64
    let vehicleID: VehicleID
    let x: Double
    let distance: Double
    let speed: Double
    let finishPosition: Int?
}

enum ObstacleKind: Equatable, Hashable, Sendable {
    case barrier
    case trafficCar
}

struct ObstacleSnapshot: Equatable, Sendable {
    let id: UInt64
    let rowID: UInt64
    let kind: ObstacleKind
    let laneIndex: Int
    let x: Double
    let distance: Double
    let width: Double
    let length: Double
    let closingSpeed: Double
    let didAwardNearMiss: Bool
}

struct GameSnapshot: Equatable, Sendable {
    let phase: GamePhase
    let playerX: Double
    let playerWidth: Double
    let playerLength: Double
    let roadHalfWidth: Double
    let laneWidth: Double
    let obstacles: [ObstacleSnapshot]
    let score: Int
    let speed: Double
    let elapsedTime: TimeInterval
    let distance: Double
    let spawnInterval: TimeInterval
    let gameMode: GameMode
    let booster: BoosterSnapshot
    let cpuRacers: [CPURacerSnapshot]
    let playerPlace: Int?
    let fieldSize: Int
    let raceDistance: Double?

    init(
        phase: GamePhase,
        playerX: Double,
        playerWidth: Double,
        playerLength: Double,
        roadHalfWidth: Double,
        laneWidth: Double,
        obstacles: [ObstacleSnapshot],
        score: Int,
        speed: Double,
        elapsedTime: TimeInterval,
        distance: Double,
        spawnInterval: TimeInterval,
        gameMode: GameMode = .survival,
        booster: BoosterSnapshot = .initial,
        cpuRacers: [CPURacerSnapshot] = [],
        playerPlace: Int? = nil,
        fieldSize: Int = 1,
        raceDistance: Double? = nil
    ) {
        self.phase = phase
        self.playerX = playerX
        self.playerWidth = playerWidth
        self.playerLength = playerLength
        self.roadHalfWidth = roadHalfWidth
        self.laneWidth = laneWidth
        self.obstacles = obstacles
        self.score = score
        self.speed = speed
        self.elapsedTime = elapsedTime
        self.distance = distance
        self.spawnInterval = spawnInterval
        self.gameMode = gameMode
        self.booster = booster
        self.cpuRacers = cpuRacers
        self.playerPlace = playerPlace
        self.fieldSize = fieldSize
        self.raceDistance = raceDistance
    }
}

enum GameEvent: Equatable, Sendable {
    case collision(obstacleID: UInt64, kind: ObstacleKind)
    case nearMiss(obstacleID: UInt64, kind: ObstacleKind, bonus: Int)
}

struct GameSimulation: Sendable {
    static let laneCount = 4

    struct Configuration: Equatable, Sendable {
        var mode: GameMode = .survival
        var cpuCount = 3
        var laneWidth = 2.0
        var playerWidth = 0.9
        var playerLength = 1.8
        var playerLateralSpeed = 7.0
        var initialSpeed = 12.0
        var maximumSpeed = 24.0
        var trafficCarSpeed = 6.0
        var difficultyRampDuration: TimeInterval = 60
        var initialSpawnInterval: TimeInterval = 2.2
        var minimumSpawnInterval: TimeInterval = 0.9
        var firstSpawnDelay: TimeInterval = 0.75
        var spawnDistance = 48.0
        var nearMissMargin = 0.35
        var nearMissBonus = 100
        var removalDistance = -8.0
        var maximumDeltaTime: TimeInterval = 1.0 / 15.0
        var sprintDistance = 1_000.0
        var sprintInitialSpeed = 20.0
        var sprintMaximumSpeed = 27.0
        var sprintAccelerationDuration: TimeInterval = 12
        var boosterChargeDuration: TimeInterval = 5
        var boosterActiveDuration: TimeInterval = 3
        var boosterSpeedMultiplier = 1.35
        var racerCollisionRecoveryRate = 3.0
    }

    private struct Obstacle: Equatable, Sendable {
        let id: UInt64
        let rowID: UInt64
        let kind: ObstacleKind
        let laneIndex: Int
        let x: Double
        var distance: Double
        let width: Double
        let length: Double
        var closingSpeed: Double
        var didAwardNearMiss = false

        var snapshot: ObstacleSnapshot {
            ObstacleSnapshot(
                id: id,
                rowID: rowID,
                kind: kind,
                laneIndex: laneIndex,
                x: x,
                distance: distance,
                width: width,
                length: length,
                closingSpeed: closingSpeed,
                didAwardNearMiss: didAwardNearMiss
            )
        }
    }

    private struct CPURacer: Equatable, Sendable {
        let id: UInt64
        let vehicleID: VehicleID
        let x: Double
        let paceOffset: Double
        let pacePhase: Double
        var distance: Double
        var speed: Double
        var collisionSpeedPenalty: Double
        var finishedAt: TimeInterval?
    }

    private struct SeededGenerator: Sendable {
        private var state: UInt64

        init(seed: UInt64) {
            state = seed
        }

        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var value = state
            value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
            value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
            return value ^ (value >> 31)
        }
    }

    let configuration: Configuration

    private var phase: GamePhase = .running
    private var playerX = 0.0
    private var elapsedTime: TimeInterval = 0
    private var distance = 0.0
    private var bonusScore = 0
    private var timeUntilNextSpawn: TimeInterval
    private var obstacles: [Obstacle] = []
    private var nextObstacleID: UInt64 = 0
    private var generator: SeededGenerator
    private var boosterChargeDuration: TimeInterval = 0
    private var boosterRemainingDuration: TimeInterval = 0
    private var cpuRacers: [CPURacer]
    private var playerFinishedAt: TimeInterval?
    private var playerCollisionSpeedPenalty = 0.0

    init(seed: UInt64, configuration: Configuration = Configuration()) {
        self.configuration = configuration
        timeUntilNextSpawn = configuration.firstSpawnDelay
        generator = SeededGenerator(seed: seed)
        cpuRacers = Self.makeCPURacers(configuration: configuration)
    }

    var snapshot: GameSnapshot {
        let raceDistance = configuration.mode == .cpuSprint
            ? max(configuration.sprintDistance, 1)
            : nil
        let cpuSnapshots = cpuRacerSnapshots
        return GameSnapshot(
            phase: phase,
            playerX: playerX,
            playerWidth: configuration.playerWidth,
            playerLength: configuration.playerLength,
            roadHalfWidth: roadHalfWidth,
            laneWidth: configuration.laneWidth,
            obstacles: configuration.mode == .survival ? obstacles.map(\.snapshot) : [],
            score: Int(distance.rounded(.down)) + bonusScore,
            speed: currentSpeed,
            elapsedTime: elapsedTime,
            distance: distance,
            spawnInterval: currentSpawnInterval,
            gameMode: configuration.mode,
            booster: boosterSnapshot,
            cpuRacers: cpuSnapshots,
            playerPlace: playerPlace,
            fieldSize: configuration.mode == .cpuSprint ? cpuSnapshots.count + 1 : 1,
            raceDistance: raceDistance
        )
    }

    mutating func reset(seed: UInt64) {
        phase = .running
        playerX = 0
        elapsedTime = 0
        distance = 0
        bonusScore = 0
        timeUntilNextSpawn = configuration.firstSpawnDelay
        obstacles = []
        nextObstacleID = 0
        generator = SeededGenerator(seed: seed)
        boosterChargeDuration = 0
        boosterRemainingDuration = 0
        cpuRacers = Self.makeCPURacers(configuration: configuration)
        playerFinishedAt = nil
        playerCollisionSpeedPenalty = 0
    }

    mutating func step(dt: TimeInterval, steering: Double) -> [GameEvent] {
        guard phase == .running, dt.isFinite, dt > 0 else {
            return []
        }

        let maximumDeltaTime = max(configuration.maximumDeltaTime, .leastNonzeroMagnitude)
        let deltaTime = min(dt, maximumDeltaTime)
        recoverCollisionSpeed(deltaTime: deltaTime)
        let steeringValue = steering.isFinite ? min(max(steering, -1), 1) : 0
        let playerLimit = max(0, roadHalfWidth - configuration.playerWidth / 2)
        let attemptedPlayerX = playerX
            + steeringValue * configuration.playerLateralSpeed * deltaTime
        let contactedGuard = abs(attemptedPlayerX) > playerLimit
        playerX = min(max(attemptedPlayerX, -playerLimit), playerLimit)

        updateBooster(deltaTime: deltaTime, contactedGuard: contactedGuard)

        elapsedTime += deltaTime
        let playerSpeed = currentSpeed
        let updatedPlayerDistance = distance + playerSpeed * deltaTime
        distance = updatedPlayerDistance

        if configuration.mode == .cpuSprint {
            updateCPURacers(deltaTime: deltaTime)
            resolveCPURacerContacts(
                steering: steeringValue,
                playerSpeed: playerSpeed
            )
            if distance >= max(configuration.sprintDistance, 1) {
                let finishDistance = max(configuration.sprintDistance, 1)
                playerFinishedAt = elapsedTime
                    - (distance - finishDistance)
                        / max(playerSpeed, .leastNonzeroMagnitude)
                distance = finishDistance
                phase = .finished
            }
            return []
        }

        for index in obstacles.indices {
            obstacles[index].closingSpeed = closingSpeed(for: obstacles[index].kind)
            obstacles[index].distance -= obstacles[index].closingSpeed * deltaTime
        }

        if let collided = obstacles.first(where: collidesWithPlayer) {
            phase = .crashed
            return [.collision(obstacleID: collided.id, kind: collided.kind)]
        }

        var events: [GameEvent] = []
        for index in obstacles.indices where !obstacles[index].didAwardNearMiss {
            let obstacle = obstacles[index]
            let passedPlayer = obstacle.distance + obstacle.length / 2 < -configuration.playerLength / 2
            let edgeGap = abs(obstacle.x - playerX) - (obstacle.width + configuration.playerWidth) / 2
            if passedPlayer, edgeGap > 0, edgeGap <= configuration.nearMissMargin {
                obstacles[index].didAwardNearMiss = true
                bonusScore += configuration.nearMissBonus
                events.append(
                    .nearMiss(
                        obstacleID: obstacle.id,
                        kind: obstacle.kind,
                        bonus: configuration.nearMissBonus
                    )
                )
            }
        }

        obstacles.removeAll { $0.distance < configuration.removalDistance }

        timeUntilNextSpawn -= deltaTime
        while timeUntilNextSpawn <= 0 {
            spawnObstacle()
            timeUntilNextSpawn += max(currentSpawnInterval, 0.05)
        }

        return events
    }

    private var roadHalfWidth: Double {
        configuration.laneWidth * Double(Self.laneCount) / 2
    }

    private var difficultyProgress: Double {
        let duration = max(configuration.difficultyRampDuration, .leastNonzeroMagnitude)
        return min(max(elapsedTime / duration, 0), 1)
    }

    private var currentSpeed: Double {
        let targetSpeed = boosterRemainingDuration > 0
            ? basePlayerSpeed * max(configuration.boosterSpeedMultiplier, 1)
            : basePlayerSpeed
        return max(targetSpeed - playerCollisionSpeedPenalty, 0)
    }

    private var basePlayerSpeed: Double {
        let baseSpeed: Double
        switch configuration.mode {
        case .survival:
            baseSpeed = min(
                configuration.initialSpeed
                    + (configuration.maximumSpeed - configuration.initialSpeed) * difficultyProgress,
                configuration.maximumSpeed
            )
        case .cpuSprint:
            let duration = max(
                configuration.sprintAccelerationDuration,
                .leastNonzeroMagnitude
            )
            let progress = min(max(elapsedTime / duration, 0), 1)
            baseSpeed = min(
                configuration.sprintInitialSpeed
                    + (configuration.sprintMaximumSpeed - configuration.sprintInitialSpeed)
                        * progress,
                configuration.sprintMaximumSpeed
            )
        }
        return baseSpeed
    }

    private var currentSpawnInterval: TimeInterval {
        max(
            configuration.initialSpawnInterval
                + (configuration.minimumSpawnInterval - configuration.initialSpawnInterval)
                    * difficultyProgress,
            configuration.minimumSpawnInterval
        )
    }

    private func closingSpeed(for kind: ObstacleKind) -> Double {
        switch kind {
        case .barrier:
            currentSpeed
        case .trafficCar:
            max(currentSpeed - configuration.trafficCarSpeed, 0)
        }
    }

    private func collidesWithPlayer(_ obstacle: Obstacle) -> Bool {
        let overlapsLaterally = abs(obstacle.x - playerX)
            <= (obstacle.width + configuration.playerWidth) / 2
        let overlapsLongitudinally = abs(obstacle.distance)
            <= (obstacle.length + configuration.playerLength) / 2
        return overlapsLaterally && overlapsLongitudinally
    }

    private mutating func spawnObstacle() {
        let laneIndex = Int(generator.next() % UInt64(Self.laneCount))
        let kind: ObstacleKind = generator.next() & 1 == 0 ? .barrier : .trafficCar
        let dimensions = switch kind {
        case .barrier: (width: 1.7, length: 1.0)
        case .trafficCar: (width: 1.2, length: 2.2)
        }
        let laneCenterOffset = (Double(Self.laneCount) - 1) / 2
        let x = (Double(laneIndex) - laneCenterOffset) * configuration.laneWidth
        let id = nextObstacleID
        nextObstacleID &+= 1
        obstacles.append(
            Obstacle(
                id: id,
                rowID: id,
                kind: kind,
                laneIndex: laneIndex,
                x: x,
                distance: configuration.spawnDistance,
                width: dimensions.width,
                length: dimensions.length,
                closingSpeed: closingSpeed(for: kind)
            )
        )
    }

    private var boosterSnapshot: BoosterSnapshot {
        let chargeDuration = max(configuration.boosterChargeDuration, .leastNonzeroMagnitude)
        if boosterRemainingDuration > 0 {
            return BoosterSnapshot(
                phase: .active,
                chargeProgress: 1,
                remainingDuration: boosterRemainingDuration
            )
        }
        return BoosterSnapshot(
            phase: .charging,
            chargeProgress: min(max(boosterChargeDuration / chargeDuration, 0), 1),
            remainingDuration: max(chargeDuration - boosterChargeDuration, 0)
        )
    }

    private mutating func updateBooster(
        deltaTime: TimeInterval,
        contactedGuard: Bool
    ) {
        if contactedGuard {
            boosterChargeDuration = 0
            boosterRemainingDuration = 0
            return
        }

        if boosterRemainingDuration > 0 {
            if boosterRemainingDuration <= deltaTime + 1e-9 {
                boosterRemainingDuration = 0
                boosterChargeDuration = 0
            } else {
                boosterRemainingDuration -= deltaTime
            }
            return
        }

        let requiredCharge = max(
            configuration.boosterChargeDuration,
            .leastNonzeroMagnitude
        )
        let updatedCharge = boosterChargeDuration + deltaTime
        boosterChargeDuration = min(updatedCharge, requiredCharge)
        if updatedCharge >= requiredCharge - 1e-9 {
            boosterChargeDuration = requiredCharge
            let activeDuration = max(configuration.boosterActiveDuration, 0)
            boosterRemainingDuration = activeDuration
            if activeDuration == 0 {
                boosterChargeDuration = 0
            }
        }
    }

    private static func makeCPURacers(configuration: Configuration) -> [CPURacer] {
        guard configuration.mode == .cpuSprint else { return [] }
        let count = min(max(configuration.cpuCount, 1), 3)
        let laneOrder = [-1.5, 1.5, -0.5]
        let vehicleOrder: [VehicleID] = [.gt, .angular, .rallyRS]
        let paceOffsets = [-0.4, 1.4, 4.2]
        return (0..<count).map { index in
            let startingDistance = 8.0 - Double(index) * 2.5
            return CPURacer(
                id: UInt64(index),
                vehicleID: vehicleOrder[index],
                x: laneOrder[index] * configuration.laneWidth,
                paceOffset: paceOffsets[index],
                pacePhase: Double(index) * 1.7,
                distance: startingDistance,
                speed: configuration.sprintInitialSpeed + paceOffsets[index],
                collisionSpeedPenalty: 0,
                finishedAt: nil
            )
        }
    }

    private mutating func updateCPURacers(deltaTime: TimeInterval) {
        let finishDistance = max(configuration.sprintDistance, 1)
        for index in cpuRacers.indices where cpuRacers[index].finishedAt == nil {
            let pace = sin(elapsedTime * 0.55 + cpuRacers[index].pacePhase) * 0.42
            let gapBehindPlayer = distance - cpuRacers[index].distance
            let recovery = min(max(gapBehindPlayer * 0.12, -2.8), 4.0)
            let speed = max(
                basePlayerSpeed
                    + cpuRacers[index].paceOffset
                    + pace
                    + recovery
                    - cpuRacers[index].collisionSpeedPenalty,
                0
            )
            cpuRacers[index].speed = speed
            let previousDistance = cpuRacers[index].distance
            let updatedDistance = previousDistance + speed * deltaTime
            cpuRacers[index].distance = min(updatedDistance, finishDistance)
            if updatedDistance >= finishDistance {
                cpuRacers[index].finishedAt = elapsedTime
                    - (updatedDistance - finishDistance)
                        / max(speed, .leastNonzeroMagnitude)
            }
        }
    }

    private mutating func recoverCollisionSpeed(deltaTime: TimeInterval) {
        let recovery = max(configuration.racerCollisionRecoveryRate, 0) * deltaTime
        playerCollisionSpeedPenalty = max(playerCollisionSpeedPenalty - recovery, 0)
        for index in cpuRacers.indices {
            cpuRacers[index].collisionSpeedPenalty = max(
                cpuRacers[index].collisionSpeedPenalty - recovery,
                0
            )
        }
    }

    private mutating func resolveCPURacerContacts(
        steering: Double,
        playerSpeed: Double
    ) {
        let combinedHalfWidth = configuration.playerWidth
        let combinedHalfLength = configuration.playerLength
        let playerLimit = max(0, roadHalfWidth - configuration.playerWidth / 2)
        let separationEpsilon = 0.000_1

        for index in cpuRacers.indices where cpuRacers[index].finishedAt == nil {
            let lateralDelta = playerX - cpuRacers[index].x
            let longitudinalDelta = distance - cpuRacers[index].distance
            let lateralPenetration = combinedHalfWidth - abs(lateralDelta)
            let longitudinalPenetration = combinedHalfLength - abs(longitudinalDelta)
            guard lateralPenetration > 0, longitudinalPenetration > 0 else {
                continue
            }

            if lateralPenetration < longitudinalPenetration {
                let side: Double
                if abs(lateralDelta) > separationEpsilon {
                    side = lateralDelta.sign == .minus ? -1 : 1
                } else if abs(steering) > separationEpsilon {
                    side = steering.sign == .minus ? -1 : 1
                } else {
                    side = cpuRacers[index].id.isMultiple(of: 2) ? 1 : -1
                }
                let resolvedX = min(
                    max(
                        cpuRacers[index].x
                            + side * (combinedHalfWidth + separationEpsilon),
                        -playerLimit
                    ),
                    playerLimit
                )
                if abs(resolvedX - cpuRacers[index].x) >= combinedHalfWidth {
                    playerX = resolvedX
                    let relativeSpeed = abs(playerSpeed - cpuRacers[index].speed)
                    playerCollisionSpeedPenalty = max(
                        playerCollisionSpeedPenalty,
                        1.1 + relativeSpeed * 0.35
                    )
                    continue
                }
            }

            if longitudinalDelta <= 0 {
                distance = cpuRacers[index].distance
                    - combinedHalfLength
                    - separationEpsilon
                let closingSpeed = max(playerSpeed - cpuRacers[index].speed, 0)
                playerCollisionSpeedPenalty = max(
                    playerCollisionSpeedPenalty,
                    1.5 + closingSpeed * 0.72
                )
            } else {
                cpuRacers[index].distance = distance
                    - combinedHalfLength
                    - separationEpsilon
                let closingSpeed = max(cpuRacers[index].speed - playerSpeed, 0)
                cpuRacers[index].collisionSpeedPenalty = max(
                    cpuRacers[index].collisionSpeedPenalty,
                    1.5 + closingSpeed * 0.72
                )
                cpuRacers[index].speed = max(
                    cpuRacers[index].speed - cpuRacers[index].collisionSpeedPenalty,
                    0
                )
            }
        }
    }

    private var cpuRacerSnapshots: [CPURacerSnapshot] {
        let orderedFinishers = cpuRacers
            .filter { $0.finishedAt != nil }
            .sorted {
                if $0.finishedAt == $1.finishedAt { return $0.id < $1.id }
                return ($0.finishedAt ?? .infinity) < ($1.finishedAt ?? .infinity)
            }
        let finishPositions = Dictionary(
            uniqueKeysWithValues: orderedFinishers.enumerated().map { index, racer in
                (racer.id, index + 1)
            }
        )
        return cpuRacers.map { racer in
            let playerOffset: Int
            if let cpuFinishedAt = racer.finishedAt,
               let playerFinishedAt,
               playerFinishedAt <= cpuFinishedAt {
                playerOffset = 1
            } else {
                playerOffset = 0
            }
            return CPURacerSnapshot(
                id: racer.id,
                vehicleID: racer.vehicleID,
                x: racer.x,
                distance: racer.distance,
                speed: racer.speed,
                finishPosition: finishPositions[racer.id].map { $0 + playerOffset }
            )
        }
    }

    private var playerPlace: Int? {
        guard configuration.mode == .cpuSprint else { return nil }
        if let playerFinishedAt {
            return 1 + cpuRacers.count {
                guard let cpuFinishedAt = $0.finishedAt else { return false }
                return cpuFinishedAt <= playerFinishedAt
            }
        }
        return 1 + cpuRacers.count { $0.distance > distance }
    }

}
