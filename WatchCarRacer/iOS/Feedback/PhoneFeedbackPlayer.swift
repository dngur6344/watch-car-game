import Foundation
import UIKit

enum FeedbackSide: Equatable, Sendable {
    case left
    case center
    case right

    var audioPan: Double {
        switch self {
        case .left:
            -0.75
        case .center:
            0
        case .right:
            0.75
        }
    }
}

struct FeedbackSpatialContext: Equatable, Sendable {
    let relativeX: Double
    let side: FeedbackSide
    let closeness: Double
}

enum NearMissFeedbackGrade: Equatable, Sendable {
    case standard
    case strong
}

/// A raw simulation event paired with the snapshot from the exact fixed step that emitted it.
/// This is presentation-only; the simulation event and snapshot remain unchanged.
struct GameEventPresentation: Equatable, Sendable {
    let event: GameEvent
    let snapshot: GameSnapshot
    let configuration: GameSimulation.Configuration
    let spatialContext: FeedbackSpatialContext?

    init(
        event: GameEvent,
        snapshot: GameSnapshot,
        configuration: GameSimulation.Configuration
    ) {
        self.event = event
        self.snapshot = snapshot
        self.configuration = configuration
        spatialContext = Self.makeSpatialContext(
            event: event,
            snapshot: snapshot,
            configuration: configuration
        )
    }

    private static func makeSpatialContext(
        event: GameEvent,
        snapshot: GameSnapshot,
        configuration: GameSimulation.Configuration
    ) -> FeedbackSpatialContext? {
        let obstacleID = switch event {
        case let .nearMiss(obstacleID, _, _), let .collision(obstacleID, _):
            obstacleID
        }
        guard let obstacle = snapshot.obstacles.first(where: { $0.id == obstacleID }) else {
            return nil
        }

        let relativeX = obstacle.x - snapshot.playerX
        let playerWidth = snapshot.playerWidth
        let obstacleWidth = obstacle.width
        let nearMissMargin = configuration.nearMissMargin
        guard relativeX.isFinite,
              playerWidth.isFinite,
              obstacleWidth.isFinite,
              nearMissMargin.isFinite,
              playerWidth > 0,
              obstacleWidth > 0,
              nearMissMargin > 0 else {
            return nil
        }

        // The closed center band is 25% of the narrower vehicle width on either side.
        // Values exactly on the boundary are center, keeping classification deterministic.
        let centerBoundary = min(playerWidth, obstacleWidth) * 0.25
        let side: FeedbackSide
        if relativeX < -centerBoundary {
            side = .left
        } else if relativeX > centerBoundary {
            side = .right
        } else {
            side = .center
        }

        // Closeness is 1 at contact/overlap and 0 at the near-miss margin's outer edge.
        let edgeGap = abs(relativeX) - (playerWidth + obstacleWidth) / 2
        let normalizedGap = min(max(edgeGap / nearMissMargin, 0), 1)
        return FeedbackSpatialContext(
            relativeX: relativeX,
            side: side,
            closeness: 1 - normalizedGap
        )
    }
}

struct GameFeedback: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case nearMiss(bonus: Int)
        case collision
    }

    let eventID: UUID
    let kind: Kind
    let obstacleID: UInt64?
    let spatialContext: FeedbackSpatialContext?
    let nearMissGrade: NearMissFeedbackGrade?
    let chainTier: Int
    let isHapticEligible: Bool

    init(eventID: UUID, kind: Kind) {
        self.eventID = eventID
        self.kind = kind
        obstacleID = nil
        spatialContext = nil
        switch kind {
        case .nearMiss:
            nearMissGrade = .standard
            chainTier = 1
        case .collision:
            nearMissGrade = nil
            chainTier = 0
        }
        isHapticEligible = true
    }

    init(
        eventID: UUID,
        kind: Kind,
        obstacleID: UInt64? = nil,
        spatialContext: FeedbackSpatialContext?,
        nearMissGrade: NearMissFeedbackGrade?,
        chainTier: Int,
        isHapticEligible: Bool
    ) {
        self.eventID = eventID
        self.kind = kind
        self.obstacleID = obstacleID
        self.spatialContext = spatialContext
        self.nearMissGrade = nearMissGrade
        self.chainTier = chainTier
        self.isHapticEligible = isHapticEligible
    }

    var watchKind: WatchFeedbackKind {
        switch kind {
        case .nearMiss:
            nearMissGrade == .strong ? .nearMissStrong : .nearMiss
        case .collision:
            .collision
        }
    }
}

enum GameHapticCue: Equatable, Sendable {
    case countdownTick
    case go
    case nearMiss
    case collision
}

@MainActor
struct GameFeedbackCoordinator {
    static let nearMissChainWindow: TimeInterval = 3
    static let maximumChainTier = 3
    static let strongNearMissClosenessBoundary = 0.5
    static let minimumNearMissHapticInterval: TimeInterval = 0.15

    private enum EventKey: Hashable {
        case nearMiss(obstacleID: UInt64, kind: ObstacleKind)
        case collision(obstacleID: UInt64, kind: ObstacleKind)
    }

    private var handledEvents: Set<EventKey> = []
    private var lastNearMissElapsedTime: TimeInterval?
    private var nearMissChainTier = 0
    private var lastNearMissHapticTime: TimeInterval?
    private let makeEventID: () -> UUID
    private let monotonicClock: () -> TimeInterval

    init(
        makeEventID: @escaping () -> UUID = UUID.init,
        monotonicClock: @escaping () -> TimeInterval = {
            ProcessInfo.processInfo.systemUptime
        }
    ) {
        self.makeEventID = makeEventID
        self.monotonicClock = monotonicClock
    }

    mutating func feedback(for events: [GameEventPresentation]) -> [GameFeedback] {
        events.compactMap { presentation in
            makeFeedback(for: presentation.event, presentation: presentation)
        }
    }

    mutating func feedback(for events: [GameEvent]) -> [GameFeedback] {
        events.compactMap { event in
            makeFeedback(for: event, presentation: nil)
        }
    }

    mutating func hapticEligibility(for cue: GameHapticCue) -> Bool {
        guard cue == .nearMiss else {
            return true
        }

        let now = monotonicClock()
        guard now.isFinite else { return false }
        if let lastNearMissHapticTime {
            let interval = now - lastNearMissHapticTime
            guard interval + 0.000_000_1 >= Self.minimumNearMissHapticInterval else {
                return false
            }
        }
        lastNearMissHapticTime = now
        return true
    }

    mutating func reset() {
        handledEvents.removeAll(keepingCapacity: true)
        resetNearMissChain()
        lastNearMissHapticTime = nil
    }

    private mutating func makeFeedback(
        for event: GameEvent,
        presentation: GameEventPresentation?
    ) -> GameFeedback? {
        let key: EventKey
        let kind: GameFeedback.Kind
        switch event {
        case let .nearMiss(obstacleID, obstacleKind, bonus):
            key = .nearMiss(obstacleID: obstacleID, kind: obstacleKind)
            kind = .nearMiss(bonus: bonus)
        case let .collision(obstacleID, obstacleKind):
            key = .collision(obstacleID: obstacleID, kind: obstacleKind)
            kind = .collision
        }

        guard handledEvents.insert(key).inserted else {
            return nil
        }

        switch event {
        case .nearMiss:
            let grade: NearMissFeedbackGrade = if let closeness = presentation?
                .spatialContext?.closeness,
                closeness >= Self.strongNearMissClosenessBoundary {
                .strong
            } else {
                .standard
            }
            return GameFeedback(
                eventID: makeEventID(),
                kind: kind,
                obstacleID: event.obstacleID,
                spatialContext: presentation?.spatialContext,
                nearMissGrade: grade,
                chainTier: advanceNearMissChain(
                    elapsedTime: presentation?.snapshot.elapsedTime
                ),
                isHapticEligible: hapticEligibility(for: .nearMiss)
            )
        case .collision:
            resetNearMissChain()
            return GameFeedback(
                eventID: makeEventID(),
                kind: kind,
                obstacleID: event.obstacleID,
                spatialContext: presentation?.spatialContext,
                nearMissGrade: nil,
                chainTier: 0,
                isHapticEligible: hapticEligibility(for: .collision)
            )
        }
    }

    private mutating func advanceNearMissChain(elapsedTime: TimeInterval?) -> Int {
        guard let elapsedTime, elapsedTime.isFinite else {
            resetNearMissChain()
            nearMissChainTier = 1
            return nearMissChainTier
        }

        if let lastNearMissElapsedTime,
           elapsedTime >= lastNearMissElapsedTime,
           elapsedTime - lastNearMissElapsedTime <= Self.nearMissChainWindow {
            nearMissChainTier = min(nearMissChainTier + 1, Self.maximumChainTier)
        } else {
            nearMissChainTier = 1
        }
        lastNearMissElapsedTime = elapsedTime
        return nearMissChainTier
    }

    private mutating func resetNearMissChain() {
        lastNearMissElapsedTime = nil
        nearMissChainTier = 0
    }
}

private extension GameEvent {
    var obstacleID: UInt64 {
        switch self {
        case let .nearMiss(obstacleID, _, _), let .collision(obstacleID, _):
            obstacleID
        }
    }
}

enum StartCueKind: Equatable, Sendable {
    case three
    case two
    case one
    case go

    var countdownValue: Int? {
        switch self {
        case .three:
            3
        case .two:
            2
        case .one:
            1
        case .go:
            nil
        }
    }
}

enum StartCueAccentColor: Equatable, Sendable {
    case cyan
    case mint
    case orange
    case mintWhite
}

enum StartCueVisualTreatment: Equatable, Sendable {
    case ring(StartCueAccentColor)
    case fullScreenSweep(StartCueAccentColor)
}

enum PhoneImpactStyle: Equatable, Sendable {
    case light
    case rigid
    case heavy
}

struct PhoneImpactCommand: Equatable, Sendable {
    let style: PhoneImpactStyle
    let intensity: Double
}

/// Immutable render-and-feedback contract for one logical start cue.
/// Its ID is shared by audio, phone haptic, Watch haptic, and visual removal.
struct StartCuePresentation: Identifiable, Equatable, Sendable {
    let id: UUID
    let kind: StartCueKind
    let audioCue: GameAudioCue
    let audioRate: Double
    let visualTreatment: StartCueVisualTreatment
    let phoneImpact: PhoneImpactCommand
    let watchKind: WatchFeedbackKind
    let visibleDuration: TimeInterval
    let emittedAt: TimeInterval

    init(id: UUID, kind: StartCueKind, emittedAt: TimeInterval) {
        self.id = id
        self.kind = kind
        self.emittedAt = emittedAt
        switch kind {
        case .three:
            audioCue = .countdownTick
            audioRate = 0.88
            visualTreatment = .ring(.cyan)
            phoneImpact = PhoneImpactCommand(style: .light, intensity: 0.35)
            watchKind = .countdownTick
            visibleDuration = 0.18
        case .two:
            audioCue = .countdownTick
            audioRate = 1
            visualTreatment = .ring(.mint)
            phoneImpact = PhoneImpactCommand(style: .rigid, intensity: 0.55)
            watchKind = .countdownTick
            visibleDuration = 0.18
        case .one:
            audioCue = .countdownTick
            audioRate = 1.12
            visualTreatment = .ring(.orange)
            phoneImpact = PhoneImpactCommand(style: .rigid, intensity: 0.75)
            watchKind = .countdownTick
            visibleDuration = 0.18
        case .go:
            audioCue = .go
            audioRate = 1
            visualTreatment = .fullScreenSweep(.mintWhite)
            phoneImpact = PhoneImpactCommand(style: .heavy, intensity: 0.90)
            watchKind = .go
            visibleDuration = 0.26
        }
    }

    func opacity(for intensity: SensoryEffectIntensity) -> Double {
        intensity == .balanced ? 1 : 0.55
    }
}

@MainActor
protocol PhoneFeedbackPlaying: AnyObject {
    func play(_ feedback: GameFeedback)
    func playStartCue(_ cue: StartCuePresentation)
}

extension PhoneFeedbackPlaying {
    func playStartCue(_ cue: StartCuePresentation) {}
}

@MainActor
final class PhoneFeedbackPlayer: PhoneFeedbackPlaying {
    private let nearMissHaptic = UIImpactFeedbackGenerator(style: .soft)
    private let collisionHaptic = UINotificationFeedbackGenerator()
    private let countdownLightHaptic = UIImpactFeedbackGenerator(style: .light)
    private let countdownRigidHaptic = UIImpactFeedbackGenerator(style: .rigid)
    private let goHaptic = UIImpactFeedbackGenerator(style: .heavy)
    private let isHapticsEnabled: () -> Bool

    init(isHapticsEnabled: @escaping () -> Bool = { true }) {
        self.isHapticsEnabled = isHapticsEnabled
    }

    func play(_ feedback: GameFeedback) {
        guard isHapticsEnabled() else { return }
        switch feedback.kind {
        case .nearMiss:
            let intensity = feedback.nearMissGrade == .strong ? 0.85 : 0.55
            nearMissHaptic.impactOccurred(intensity: intensity)
        case .collision:
            collisionHaptic.notificationOccurred(.error)
        }
    }

    func playStartCue(_ cue: StartCuePresentation) {
        guard isHapticsEnabled() else { return }
        let generator = switch cue.phoneImpact.style {
        case .light:
            countdownLightHaptic
        case .rigid:
            countdownRigidHaptic
        case .heavy:
            goHaptic
        }
        generator.impactOccurred(intensity: cue.phoneImpact.intensity)
    }
}
