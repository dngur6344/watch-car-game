import Foundation

enum GamePhase: Equatable, Sendable {
    case running
    case crashed
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
}

enum GameEvent: Equatable, Sendable {
    case collision(obstacleID: UInt64, kind: ObstacleKind)
    case nearMiss(obstacleID: UInt64, kind: ObstacleKind, bonus: Int)
}

struct GameSimulation: Sendable {
    struct Configuration: Equatable, Sendable {
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

    init(seed: UInt64, configuration: Configuration = Configuration()) {
        self.configuration = configuration
        timeUntilNextSpawn = configuration.firstSpawnDelay
        generator = SeededGenerator(seed: seed)
    }

    var snapshot: GameSnapshot {
        GameSnapshot(
            phase: phase,
            playerX: playerX,
            playerWidth: configuration.playerWidth,
            playerLength: configuration.playerLength,
            roadHalfWidth: roadHalfWidth,
            laneWidth: configuration.laneWidth,
            obstacles: obstacles.map(\.snapshot),
            score: Int(distance.rounded(.down)) + bonusScore,
            speed: currentSpeed,
            elapsedTime: elapsedTime,
            distance: distance,
            spawnInterval: currentSpawnInterval
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
    }

    mutating func step(dt: TimeInterval, steering: Double) -> [GameEvent] {
        guard phase == .running, dt.isFinite, dt > 0 else {
            return []
        }

        let maximumDeltaTime = max(configuration.maximumDeltaTime, .leastNonzeroMagnitude)
        let deltaTime = min(dt, maximumDeltaTime)
        let steeringValue = steering.isFinite ? min(max(steering, -1), 1) : 0
        let playerLimit = max(0, roadHalfWidth - configuration.playerWidth / 2)
        playerX = min(
            max(playerX + steeringValue * configuration.playerLateralSpeed * deltaTime, -playerLimit),
            playerLimit
        )

        elapsedTime += deltaTime
        distance += currentSpeed * deltaTime

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
        configuration.laneWidth * 1.5
    }

    private var difficultyProgress: Double {
        let duration = max(configuration.difficultyRampDuration, .leastNonzeroMagnitude)
        return min(max(elapsedTime / duration, 0), 1)
    }

    private var currentSpeed: Double {
        min(
            configuration.initialSpeed
                + (configuration.maximumSpeed - configuration.initialSpeed) * difficultyProgress,
            configuration.maximumSpeed
        )
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
        let laneIndex = Int(generator.next() % 3)
        let kind: ObstacleKind = generator.next() & 1 == 0 ? .barrier : .trafficCar
        let dimensions = switch kind {
        case .barrier: (width: 1.7, length: 1.0)
        case .trafficCar: (width: 1.2, length: 2.2)
        }
        let x = (Double(laneIndex) - 1) * configuration.laneWidth
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
}
