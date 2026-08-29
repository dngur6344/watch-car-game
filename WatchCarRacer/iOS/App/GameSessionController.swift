import Foundation
import Observation

enum RunPresentationPhase: Equatable, Sendable {
    case countdown(Int)
    case racing
    case result(RunResult)
}

enum GameSessionLifecyclePhase: Equatable, Sendable {
    case active
    case inactive
    case background
}

@MainActor
@Observable
final class GameSessionController {
    typealias CountdownSleeper = @MainActor @Sendable () async throws -> Void
    typealias ResultRecorder = @MainActor (Int) -> RunResult

    private(set) var score = 0
    private(set) var speed = 0
    private(set) var phase: GamePhase = .running
    private(set) var presentationPhase: RunPresentationPhase = .countdown(3)
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
    private(set) var frameRateSamples: [Double] = []
    private(set) var maximumConsecutiveFrameRateSamplesBelow50 = 0
    private(set) var firstObstacleFrameRateSample: Double?
#endif

    let runSeed: UInt64
    let appearance: VehicleAppearance
    let assetLibrary: GameAssetLibrary
    let controlRoute: SessionControlRoute
    let scene: GameScene

    @ObservationIgnored private let watchInput: (any WatchSteeringReadingProviding)?
    @ObservationIgnored private let feedbackPlayer: (any PhoneFeedbackPlaying)?
    @ObservationIgnored private let watchFeedbackSender: (any WatchFeedbackSending)?
    @ObservationIgnored private let currentTime: @MainActor () -> TimeInterval
    @ObservationIgnored private let countdownSleeper: CountdownSleeper
    @ObservationIgnored private let resultRecorder: ResultRecorder
    @ObservationIgnored private var inputRouter = SteeringInputRouter()
    @ObservationIgnored private var feedbackCoordinator: GameFeedbackCoordinator
    @ObservationIgnored private var fallbackBannerExpiration: TimeInterval?
    @ObservationIgnored private var lastFallbackReason: WatchSteeringAvailability?
    @ObservationIgnored private var lifecyclePhase: GameSessionLifecyclePhase = .active
    @ObservationIgnored private var countdownGeneration: UInt64 = 0
    @ObservationIgnored private var countdownTask: Task<Void, Never>?
    @ObservationIgnored private var didRecordResult = false
    @ObservationIgnored private var isStopped = false
#if DEBUG
    @ObservationIgnored private var frameRateSum = 0.0
    @ObservationIgnored private var consecutiveFrameRateSamplesBelow50 = 0
    @ObservationIgnored private var didObserveFirstObstacle = false
    @ObservationIgnored private var isAwaitingFirstObstacleFrameRateSample = false
#endif

    init(
        seed: UInt64 = 0,
        configuration: GameSimulation.Configuration = .init(),
        appearance: VehicleAppearance,
        assetLibrary: GameAssetLibrary,
        controlRoute: SessionControlRoute = .adaptiveWatchPreferred,
        watchInput: (any WatchSteeringReadingProviding)? = nil,
        feedbackPlayer: (any PhoneFeedbackPlaying)? = nil,
        watchFeedbackSender: (any WatchFeedbackSending)? = nil,
        makeFeedbackEventID: @escaping () -> UUID = UUID.init,
        currentTime: @escaping @MainActor () -> TimeInterval = {
            ProcessInfo.processInfo.systemUptime
        },
        countdownSleeper: @escaping CountdownSleeper = {
            try await Task.sleep(for: .seconds(1))
        },
        resultRecorder: @escaping ResultRecorder = { score in
            RunResult(
                score: score,
                previousBest: 0,
                localBest: max(score, 0),
                isNewBest: score > 0
            )
        }
    ) throws {
        runSeed = seed
        self.appearance = appearance
        self.assetLibrary = assetLibrary
        self.controlRoute = controlRoute
        scene = try GameScene(
            seed: seed,
            configuration: configuration,
            appearance: appearance,
            assetLibrary: assetLibrary
        )
        self.watchInput = watchInput
        let inferredWatchFeedbackSender = watchInput as? any WatchFeedbackSending
        self.feedbackPlayer = feedbackPlayer
            ?? (inferredWatchFeedbackSender == nil ? nil : PhoneFeedbackPlayer())
        self.watchFeedbackSender = watchFeedbackSender ?? inferredWatchFeedbackSender
        feedbackCoordinator = GameFeedbackCoordinator(makeEventID: makeFeedbackEventID)
        self.currentTime = currentTime
        self.countdownSleeper = countdownSleeper
        self.resultRecorder = resultRecorder

        if controlRoute == .touchOnly {
            steeringSnapshot = SteeringSnapshot(
                value: 0,
                source: .touch,
                availability: .available
            )
        }

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
        scene.isPaused = true
        beginCountdown()
    }

    convenience init(
        seed: UInt64 = 0,
        configuration: GameSimulation.Configuration = .init(),
        controlRoute: SessionControlRoute = .adaptiveWatchPreferred,
        watchInput: (any WatchSteeringReadingProviding)? = nil,
        feedbackPlayer: (any PhoneFeedbackPlaying)? = nil,
        watchFeedbackSender: (any WatchFeedbackSending)? = nil,
        makeFeedbackEventID: @escaping () -> UUID = UUID.init,
        currentTime: @escaping @MainActor () -> TimeInterval = {
            ProcessInfo.processInfo.systemUptime
        },
        countdownSleeper: @escaping CountdownSleeper = {
            try await Task.sleep(for: .seconds(1))
        },
        resultRecorder: @escaping ResultRecorder = { score in
            RunResult(
                score: score,
                previousBest: 0,
                localBest: max(score, 0),
                isNewBest: score > 0
            )
        }
    ) {
        guard let appearance = VehicleCatalog.resolve(VehicleCatalog.defaultSelection) else {
            preconditionFailure("The default vehicle appearance is invalid.")
        }

        do {
            let assetLibrary = try GameAssetLibrary()
            try self.init(
                seed: seed,
                configuration: configuration,
                appearance: appearance,
                assetLibrary: assetLibrary,
                controlRoute: controlRoute,
                watchInput: watchInput,
                feedbackPlayer: feedbackPlayer,
                watchFeedbackSender: watchFeedbackSender,
                makeFeedbackEventID: makeFeedbackEventID,
                currentTime: currentTime,
                countdownSleeper: countdownSleeper,
                resultRecorder: resultRecorder
            )
        } catch {
            preconditionFailure("Required game assets could not be loaded: \(error)")
        }
    }

    func updateTouch(horizontalPosition: Double, width: Double) {
        guard acceptsTouchInput else { return }
        touchSteering.updateDrag(horizontalPosition: horizontalPosition, width: width)
    }

    func releaseTouch() {
        guard acceptsTouchInput else { return }
        touchSteering.endDrag()
    }

    func retry() {
        guard !isStopped else { return }
        invalidateCountdown()
        touchSteering.reset()
        switch controlRoute {
        case .adaptiveWatchPreferred:
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
        case .touchOnly:
            inputRouter.reset(retiring: nil)
            steeringSnapshot = SteeringSnapshot(
                value: 0,
                source: .touch,
                availability: .available
            )
        }
        fallbackBannerText = nil
        fallbackBannerExpiration = nil
        lastFallbackReason = nil
        lastEvent = nil
        feedbackDeliveryFailures = 0
        feedbackCoordinator.reset()
        didRecordResult = false
        // Retrying the same session intentionally reuses its seed for a reproducible run.
        scene.isPaused = true
        scene.reset(seed: runSeed)
        presentationPhase = .countdown(3)
        if lifecyclePhase == .active {
            beginCountdown()
        }
    }

    var acceptsTouchInput: Bool {
        !isStopped && lifecyclePhase == .active && presentationPhase == .racing
    }

    var hasActiveCountdownTask: Bool {
        countdownTask != nil
    }

    func handleLifecycle(_ newPhase: GameSessionLifecyclePhase) {
        guard !isStopped, lifecyclePhase != newPhase else { return }
        lifecyclePhase = newPhase

        switch newPhase {
        case .inactive, .background:
            invalidateCountdown()
            touchSteering.reset()
            scene.isPaused = true
        case .active:
            switch presentationPhase {
            case .countdown, .racing:
                beginCountdown()
            case .result:
                scene.isPaused = true
            }
        }
    }

    func stop() {
        guard !isStopped else { return }
        isStopped = true
        invalidateCountdown()
        touchSteering.reset()
        scene.isPaused = true
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
        let wasRunning = phase == .running
#if DEBUG
        if !didObserveFirstObstacle, !snapshot.obstacles.isEmpty {
            didObserveFirstObstacle = true
            isAwaitingFirstObstacleFrameRateSample = true
            print("SG6_FIRST_OBSTACLE observedAtSample=\(frameRateSampleCount)")
        }
#endif
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

        if wasRunning, snapshot.phase == .crashed, !didRecordResult {
            didRecordResult = true
            let result = resultRecorder(snapshot.score)
            presentationPhase = .result(result)
            // The crashed simulation is inert, while the scene remains live long enough for
            // collision flash and particle actions to finish. Lifecycle suspension pauses it.
            scene.isPaused = false
        }
    }

    private func routedSteering(deltaTime: TimeInterval) -> Double {
        guard acceptsTouchInput else { return 0 }
        touchSteering.advance(by: deltaTime)

        if controlRoute == .touchOnly {
            let snapshot = SteeringSnapshot(
                value: touchSteering.value,
                source: .touch,
                availability: .available
            )
            steeringSnapshot = snapshot
            fallbackBannerText = nil
            fallbackBannerExpiration = nil
            lastFallbackReason = nil
            return snapshot.value
        }

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

    private func beginCountdown() {
        invalidateCountdown()
        presentationPhase = .countdown(3)
        scene.isPaused = true
        guard lifecyclePhase == .active, !isStopped else { return }

        let generation = countdownGeneration
        let sleeper = countdownSleeper
        countdownTask = Task { [weak self] in
            for nextValue in [2, 1] {
                do {
                    try await sleeper()
                } catch {
                    return
                }
                guard !Task.isCancelled,
                      self?.advanceCountdown(to: nextValue, generation: generation) == true else {
                    return
                }
            }

            do {
                try await sleeper()
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            self?.finishCountdown(generation: generation)
        }
    }

    private func advanceCountdown(to value: Int, generation: UInt64) -> Bool {
        guard !isStopped,
              lifecyclePhase == .active,
              countdownGeneration == generation,
              case .countdown = presentationPhase else {
            return false
        }
        presentationPhase = .countdown(value)
        return true
    }

    private func finishCountdown(generation: UInt64) {
        guard !isStopped,
              lifecyclePhase == .active,
              countdownGeneration == generation,
              case .countdown = presentationPhase else {
            return
        }
        countdownTask = nil
        presentationPhase = .racing
        scene.isPaused = false
    }

    private func invalidateCountdown() {
        countdownGeneration &+= 1
        countdownTask?.cancel()
        countdownTask = nil
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
        guard presentationPhase == .racing, value.isFinite, value > 0 else {
            return
        }
        framesPerSecond = value
        frameRateSampleCount += 1
        frameRateSum += value
        frameRateSamples.append(value)
        averageFramesPerSecond = frameRateSum / Double(frameRateSampleCount)
        minimumFramesPerSecond = min(minimumFramesPerSecond ?? value, value)
        if value < 50 {
            consecutiveFrameRateSamplesBelow50 += 1
            maximumConsecutiveFrameRateSamplesBelow50 = max(
                maximumConsecutiveFrameRateSamplesBelow50,
                consecutiveFrameRateSamplesBelow50
            )
        } else {
            consecutiveFrameRateSamplesBelow50 = 0
        }
        if isAwaitingFirstObstacleFrameRateSample {
            firstObstacleFrameRateSample = value
            isAwaitingFirstObstacleFrameRateSample = false
        }

        let sample = value.formatted(.number.precision(.fractionLength(1)))
        let average = averageFramesPerSecond?.formatted(.number.precision(.fractionLength(1))) ?? "—"
        let minimum = minimumFramesPerSecond?.formatted(.number.precision(.fractionLength(1))) ?? "—"
        print(
            "SG6_FPS_SAMPLE sample=\(sample) average=\(average) minimum=\(minimum) "
                + "count=\(frameRateSampleCount) consecutiveBelow50="
                + "\(consecutiveFrameRateSamplesBelow50) phase=\(phase) score=\(score)"
        )
    }
#endif
}
