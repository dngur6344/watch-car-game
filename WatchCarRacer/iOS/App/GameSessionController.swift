import Foundation
import Observation

@MainActor
@Observable
final class GameSessionController {
    private(set) var score = 0
    private(set) var speed = 0
    private(set) var phase: GamePhase = .running
    private(set) var lastEvent: GameEvent?
    private(set) var touchSteering = TouchSteeringState()
    private(set) var steeringSnapshot = SteeringSnapshot(
        value: 0,
        source: .touch,
        availability: .fallback(.noPacket)
    )
    private(set) var fallbackBannerText: String?
    private(set) var feedbackDeliveryFailures = 0
#if DEBUG
    private(set) var framesPerSecond: Double?
    private(set) var averageFramesPerSecond: Double?
    private(set) var minimumFramesPerSecond: Double?
    private(set) var frameRateSampleCount = 0
#endif

    let runSeed: UInt64
    let scene: GameScene

    @ObservationIgnored private let watchInput: (any WatchSteeringReadingProviding)?
    @ObservationIgnored private let feedbackPlayer: (any PhoneFeedbackPlaying)?
    @ObservationIgnored private let watchFeedbackSender: (any WatchFeedbackSending)?
    @ObservationIgnored private let currentTime: @MainActor () -> TimeInterval
    @ObservationIgnored private var inputRouter = SteeringInputRouter()
    @ObservationIgnored private var feedbackCoordinator: GameFeedbackCoordinator
    @ObservationIgnored private var fallbackBannerExpiration: TimeInterval?
    @ObservationIgnored private var lastFallbackReason: WatchSteeringAvailability?
#if DEBUG
    @ObservationIgnored private var frameRateSum = 0.0
#endif

    init(
        seed: UInt64 = 0,
        configuration: GameSimulation.Configuration = .init(),
        watchInput: (any WatchSteeringReadingProviding)? = nil,
        feedbackPlayer: (any PhoneFeedbackPlaying)? = nil,
        watchFeedbackSender: (any WatchFeedbackSending)? = nil,
        makeFeedbackEventID: @escaping () -> UUID = UUID.init,
        currentTime: @escaping @MainActor () -> TimeInterval = {
            ProcessInfo.processInfo.systemUptime
        }
    ) {
        runSeed = seed
        scene = GameScene(seed: seed, configuration: configuration)
        self.watchInput = watchInput
        let inferredWatchFeedbackSender = watchInput as? any WatchFeedbackSending
        self.feedbackPlayer = feedbackPlayer
            ?? (inferredWatchFeedbackSender == nil ? nil : PhoneFeedbackPlayer())
        self.watchFeedbackSender = watchFeedbackSender ?? inferredWatchFeedbackSender
        feedbackCoordinator = GameFeedbackCoordinator(makeEventID: makeFeedbackEventID)
        self.currentTime = currentTime

        scene.steeringProvider = { [weak self] deltaTime in
            guard let self else {
                return 0
            }
            return self.routedSteering(deltaTime: deltaTime)
        }
        scene.frameHandler = { [weak self] snapshot, events in
            self?.receive(snapshot: snapshot, events: events)
        }
#if DEBUG
        scene.frameRateHandler = { [weak self] framesPerSecond in
            self?.receiveFrameRate(framesPerSecond)
        }
#endif
        receive(snapshot: scene.currentSnapshot, events: [])
    }

    func updateTouch(horizontalPosition: Double, width: Double) {
        touchSteering.updateDrag(horizontalPosition: horizontalPosition, width: width)
    }

    func releaseTouch() {
        touchSteering.endDrag()
    }

    func retry() {
        touchSteering.reset()
        let now = currentTime()
        let watch = watchInput?.routingReading(at: now) ?? .noPacket
        inputRouter.reset(retiring: watch)
        steeringSnapshot = SteeringSnapshot(
            value: 0,
            source: .touch,
            availability: .fallback(
                watch.availability == .active ? .awaitingFreshPacket : watch.availability
            )
        )
        fallbackBannerText = nil
        fallbackBannerExpiration = nil
        lastFallbackReason = nil
        lastEvent = nil
        feedbackDeliveryFailures = 0
        feedbackCoordinator.reset()
        // Retrying the same session intentionally reuses its seed for a reproducible run.
        scene.reset(seed: runSeed)
    }

    var inputSourceDescription: String {
        switch steeringSnapshot.availability {
        case .available:
            return steeringSnapshot.source.rawValue.uppercased()
        case .transitioning:
            return "\(steeringSnapshot.source.rawValue.uppercased()) · TRANSITION"
        case .fallback:
            return "TOUCH · FALLBACK"
        }
    }

    func receive(snapshot: GameSnapshot, events: [GameEvent]) {
        let displayedSpeed = Int((snapshot.speed * 3.6).rounded())
        if score != snapshot.score {
            score = snapshot.score
        }
        if speed != displayedSpeed {
            speed = displayedSpeed
        }
        if phase != snapshot.phase {
            phase = snapshot.phase
        }
        if let event = events.last {
            lastEvent = event
        }
        for feedback in feedbackCoordinator.feedback(for: events) {
            scene.present(feedback)
            feedbackPlayer?.play(feedback)
            do {
                try watchFeedbackSender?.sendFeedback(
                    WatchFeedbackPacket(eventID: feedback.eventID, kind: feedback.kind.watchKind)
                )
            } catch {
                feedbackDeliveryFailures += 1
            }
        }
    }

    private func routedSteering(deltaTime: TimeInterval) -> Double {
        touchSteering.advance(by: deltaTime)
        let now = currentTime()
        let watch = watchInput?.routingReading(at: now) ?? .noPacket
        let snapshot = inputRouter.steeringSnapshot(
            at: now,
            watch: watch,
            touchValue: touchSteering.value,
            isTouchDragging: touchSteering.isDragging
        )
        steeringSnapshot = snapshot
        updateFallbackBanner(for: snapshot, at: now)
        return snapshot.value
    }

    private func updateFallbackBanner(for snapshot: SteeringSnapshot, at now: TimeInterval) {
        guard case let .fallback(reason) = snapshot.availability else {
            fallbackBannerText = nil
            fallbackBannerExpiration = nil
            lastFallbackReason = nil
            return
        }

        if lastFallbackReason != reason {
            lastFallbackReason = reason
            fallbackBannerText = fallbackMessage(for: reason)
            fallbackBannerExpiration = now + 1.5
        } else if let fallbackBannerExpiration, now >= fallbackBannerExpiration {
            fallbackBannerText = nil
            self.fallbackBannerExpiration = nil
        }
    }

    private func fallbackMessage(for reason: WatchSteeringAvailability) -> String {
        switch reason {
        case .sessionInactive:
            return "WATCH INACTIVE · TOUCH CONTROL"
        case .unreachable:
            return "WATCH DISCONNECTED · TOUCH CONTROL"
        case .stale:
            return "WATCH SIGNAL STALE · TOUCH CONTROL"
        case .needsCalibration:
            return "CALIBRATE WATCH · TOUCH CONTROL"
        case .motionUnavailable:
            return "WATCH MOTION UNAVAILABLE · TOUCH CONTROL"
        case .awaitingFreshPacket:
            return "WAITING FOR WATCH · TOUCH CONTROL"
        case .active, .noPacket:
            return "WATCH UNAVAILABLE · TOUCH CONTROL"
        }
    }

#if DEBUG
    private func receiveFrameRate(_ value: Double) {
        guard value.isFinite, value > 0 else {
            return
        }
        framesPerSecond = value
        frameRateSampleCount += 1
        frameRateSum += value
        averageFramesPerSecond = frameRateSum / Double(frameRateSampleCount)
        minimumFramesPerSecond = min(minimumFramesPerSecond ?? value, value)

        let sample = value.formatted(.number.precision(.fractionLength(1)))
        let average = averageFramesPerSecond?.formatted(.number.precision(.fractionLength(1))) ?? "—"
        let minimum = minimumFramesPerSecond?.formatted(.number.precision(.fractionLength(1))) ?? "—"
        print(
            "SG7_FPS sample=\(sample) average=\(average) minimum=\(minimum) "
                + "count=\(frameRateSampleCount) phase=\(phase) score=\(score)"
        )
    }
#endif
}
