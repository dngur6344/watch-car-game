import Foundation
import Observation
import UIKit

enum RunPresentationPhase: Equatable, Sendable {
    case countdown(Int)
    case racing
    case collision(RunResult)
    case result(RunResult)
}

enum GameSessionLifecyclePhase: Equatable, Sendable {
    case active
    case inactive
    case background
}

struct RacingFeedbackPresentationDiagnostics: Equatable, Sendable {
    static let cueCapacity = 1

    let activeCueCount: Int
    let consumedEventCount: Int
    let sourceEventCount: Int
    let duplicateEventCount: Int

    var isBounded: Bool {
        activeCueCount <= Self.cueCapacity
            && consumedEventCount == sourceEventCount
            && duplicateEventCount == 0
    }
}

@MainActor
@Observable
final class GameSessionController {
    typealias CountdownSleeper = @MainActor @Sendable () async throws -> Void
    typealias DurationSleeper = @MainActor @Sendable (TimeInterval) async throws -> Void
    typealias ResultRecorder = @MainActor (Int) -> RunResult

    private(set) var score = 0
    private(set) var speed = 0
    private(set) var phase: GamePhase = .running
    private(set) var renderSnapshot: GameSnapshot
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
    private(set) var startCuePresentation: StartCuePresentation?
    private(set) var nearMissFeedbackPresentation: GameFeedback?
    private(set) var environmentQualityTier: RacingEnvironmentQualityTier
    private(set) var environmentQualityRunID: UInt64 = 0
    private(set) var adaptiveEnvironmentQualityState: RacingEnvironmentAdaptiveQualityState
#if DEBUG
    private(set) var framesPerSecond: Double?
    private(set) var averageFramesPerSecond: Double?
    private(set) var minimumFramesPerSecond: Double?
    private(set) var frameRateSampleCount = 0
    private(set) var frameRateSamples: [Double] = []
    private(set) var frameRateSamplePhases: [RunPresentationPhase] = []
    private(set) var maximumConsecutiveFrameRateSamplesBelow50 = 0
    private(set) var firstObstacleFrameRateSample: Double?

    var sensoryAcceptanceAudioDirectorIdentity: ObjectIdentifier? {
        audioDirector.map(ObjectIdentifier.init)
    }
#endif

    let runSeed: UInt64
    let appearance: VehicleAppearance
    let assetLibrary: GameAssetLibrary
    let controlRoute: SessionControlRoute
    let scene: GameScene

    @ObservationIgnored private let watchInput: (any WatchSteeringReadingProviding)?
    @ObservationIgnored private let feedbackPlayer: (any PhoneFeedbackPlaying)?
    @ObservationIgnored private let watchFeedbackSender: (any WatchFeedbackSending)?
    @ObservationIgnored private let audioDirector: GameAudioDirector?
    @ObservationIgnored private let currentTime: @MainActor () -> TimeInterval
    @ObservationIgnored private let isHapticsEnabled: @MainActor () -> Bool
    @ObservationIgnored private let countdownSleeper: CountdownSleeper
    @ObservationIgnored private let presentationSleeper: DurationSleeper
    @ObservationIgnored private let collisionSleeper: DurationSleeper
    @ObservationIgnored private let resultRecorder: ResultRecorder
    @ObservationIgnored private let makeStartCueEventID: @MainActor () -> UUID
    @ObservationIgnored private let gameLoopDriver: GameLoopDriver
    @ObservationIgnored private let initialEnvironmentQualityTier: @MainActor () -> RacingEnvironmentQualityTier
    @ObservationIgnored private let adaptiveQualityNotificationCenter: NotificationCenter
    @ObservationIgnored private let adaptiveQualityProcessInfo: ProcessInfo
    @ObservationIgnored private var adaptiveQualityObservers: [NSObjectProtocol] = []
    @ObservationIgnored private var inputRouter = SteeringInputRouter()
    @ObservationIgnored private var feedbackCoordinator: GameFeedbackCoordinator
    @ObservationIgnored private var fallbackBannerExpiration: TimeInterval?
    @ObservationIgnored private var lastFallbackReason: WatchSteeringAvailability?
    @ObservationIgnored private var lifecyclePhase: GameSessionLifecyclePhase = .active
    @ObservationIgnored private var countdownGeneration: UInt64 = 0
    @ObservationIgnored private var countdownTask: Task<Void, Never>?
    @ObservationIgnored private var startCueGeneration: UInt64 = 0
    @ObservationIgnored private var startCueTask: Task<Void, Never>?
    @ObservationIgnored private var nearMissFeedbackGeneration: UInt64 = 0
    @ObservationIgnored private var nearMissFeedbackTask: Task<Void, Never>?
    @ObservationIgnored private var presentedNearMissFeedbackIDs: Set<UUID> = []
    @ObservationIgnored private var duplicateNearMissFeedbackCount = 0
    @ObservationIgnored private var collisionGeneration: UInt64 = 0
    @ObservationIgnored private var collisionTask: Task<Void, Never>?
    @ObservationIgnored private var didRecordResult = false
    @ObservationIgnored private var isStopped = false
    @ObservationIgnored private var isGameLoopRequested = false
    @ObservationIgnored private let audioInitialSpeed: Double
    @ObservationIgnored private let audioMaximumSpeed: Double
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
        audioDirector: GameAudioDirector? = nil,
        makeFeedbackEventID: @escaping () -> UUID = UUID.init,
        isHapticsEnabled: @escaping @MainActor () -> Bool = { true },
        currentTime: @escaping @MainActor () -> TimeInterval = {
            ProcessInfo.processInfo.systemUptime
        },
        makeStartCueEventID: @escaping @MainActor () -> UUID = UUID.init,
        countdownSleeper: @escaping CountdownSleeper = {
            try await Task.sleep(for: .seconds(1))
        },
        presentationSleeper: @escaping DurationSleeper = { duration in
            try await Task.sleep(for: .seconds(duration))
        },
        collisionSleeper: @escaping DurationSleeper = { duration in
            try await Task.sleep(for: .seconds(duration))
        },
        initialEnvironmentQualityTier: @escaping @MainActor () -> RacingEnvironmentQualityTier = {
            RacingEnvironmentQualityProductionAdapter.initialTier()
        },
        adaptiveQualityNotificationCenter: NotificationCenter = .default,
        adaptiveQualityProcessInfo: ProcessInfo = .processInfo,
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
        renderSnapshot = scene.currentSnapshot
        gameLoopDriver = GameLoopDriver(scene: scene)
        self.watchInput = watchInput
        self.audioDirector = audioDirector
        audioInitialSpeed = configuration.initialSpeed
        audioMaximumSpeed = configuration.maximumSpeed
        let inferredWatchFeedbackSender = watchInput as? any WatchFeedbackSending
        self.feedbackPlayer = feedbackPlayer
            ?? (inferredWatchFeedbackSender == nil ? nil : PhoneFeedbackPlayer())
        self.watchFeedbackSender = watchFeedbackSender ?? inferredWatchFeedbackSender
        feedbackCoordinator = GameFeedbackCoordinator(
            makeEventID: makeFeedbackEventID,
            monotonicClock: currentTime
        )
        self.isHapticsEnabled = isHapticsEnabled
        self.currentTime = currentTime
        self.makeStartCueEventID = makeStartCueEventID
        self.countdownSleeper = countdownSleeper
        self.presentationSleeper = presentationSleeper
        self.collisionSleeper = collisionSleeper
        self.initialEnvironmentQualityTier = initialEnvironmentQualityTier
        self.adaptiveQualityNotificationCenter = adaptiveQualityNotificationCenter
        self.adaptiveQualityProcessInfo = adaptiveQualityProcessInfo
        self.resultRecorder = resultRecorder
        let initialTier = initialEnvironmentQualityTier()
        environmentQualityTier = initialTier
        adaptiveEnvironmentQualityState = RacingEnvironmentAdaptiveQualityState(
            initialTier: initialTier
        )

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
        scene.frameHandler = { [weak self] snapshot, presentationEvents in
            self?.receive(snapshot: snapshot, presentationEvents: presentationEvents)
        }
        scene.frameRateHandler = { [weak self] framesPerSecond in
            self?.receiveFrameRate(framesPerSecond)
        }
        installAdaptiveQualityObservers()
        receive(snapshot: scene.currentSnapshot, events: [])
        scene.isPaused = true
        audioDirector?.beginAttempt()
        beginCountdown()
    }

    convenience init(
        seed: UInt64 = 0,
        configuration: GameSimulation.Configuration = .init(),
        controlRoute: SessionControlRoute = .adaptiveWatchPreferred,
        watchInput: (any WatchSteeringReadingProviding)? = nil,
        feedbackPlayer: (any PhoneFeedbackPlaying)? = nil,
        watchFeedbackSender: (any WatchFeedbackSending)? = nil,
        audioDirector: GameAudioDirector? = nil,
        makeFeedbackEventID: @escaping () -> UUID = UUID.init,
        isHapticsEnabled: @escaping @MainActor () -> Bool = { true },
        currentTime: @escaping @MainActor () -> TimeInterval = {
            ProcessInfo.processInfo.systemUptime
        },
        makeStartCueEventID: @escaping @MainActor () -> UUID = UUID.init,
        countdownSleeper: @escaping CountdownSleeper = {
            try await Task.sleep(for: .seconds(1))
        },
        presentationSleeper: @escaping DurationSleeper = { duration in
            try await Task.sleep(for: .seconds(duration))
        },
        collisionSleeper: @escaping DurationSleeper = { duration in
            try await Task.sleep(for: .seconds(duration))
        },
        initialEnvironmentQualityTier: @escaping @MainActor () -> RacingEnvironmentQualityTier = {
            RacingEnvironmentQualityProductionAdapter.initialTier()
        },
        adaptiveQualityNotificationCenter: NotificationCenter = .default,
        adaptiveQualityProcessInfo: ProcessInfo = .processInfo,
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
                audioDirector: audioDirector,
                makeFeedbackEventID: makeFeedbackEventID,
                isHapticsEnabled: isHapticsEnabled,
                currentTime: currentTime,
                makeStartCueEventID: makeStartCueEventID,
                countdownSleeper: countdownSleeper,
                presentationSleeper: presentationSleeper,
                collisionSleeper: collisionSleeper,
                initialEnvironmentQualityTier: initialEnvironmentQualityTier,
                adaptiveQualityNotificationCenter: adaptiveQualityNotificationCenter,
                adaptiveQualityProcessInfo: adaptiveQualityProcessInfo,
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
        invalidateStartCue()
        invalidateCollision()
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
        resetNearMissFeedbackPresentation()
        didRecordResult = false
        resetAdaptiveEnvironmentQualityForNewRun()
        audioDirector?.beginAttempt()
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

    var hasActiveStartCueTask: Bool {
        startCueTask != nil
    }

    var racingFeedbackPresentationDiagnostics: RacingFeedbackPresentationDiagnostics {
        RacingFeedbackPresentationDiagnostics(
            activeCueCount: nearMissFeedbackPresentation == nil ? 0 : 1,
            consumedEventCount: presentedNearMissFeedbackIDs.count,
            sourceEventCount: scene.presentedFeedback.count {
                if case .nearMiss = $0.kind { return true }
                return false
            },
            duplicateEventCount: duplicateNearMissFeedbackCount
        )
    }

    var hasActiveCollisionTask: Bool {
        collisionTask != nil
    }

    func handleLifecycle(_ newPhase: GameSessionLifecyclePhase) {
        guard !isStopped, lifecyclePhase != newPhase else { return }
        lifecyclePhase = newPhase

        switch newPhase {
        case .inactive, .background:
            gameLoopDriver.stop()
            invalidateCountdown()
            invalidateStartCue()
            invalidateNearMissFeedbackPresentation()
            touchSteering.reset()
            if case let .collision(result) = presentationPhase {
                promoteCollisionToResult(result)
            } else {
                scene.isPaused = true
            }
            audioDirector?.handleLifecycle(newPhase)
        case .active:
            if isGameLoopRequested {
                gameLoopDriver.start()
            }
            switch presentationPhase {
            case .countdown, .racing:
                beginCountdown()
            case let .collision(result):
                promoteCollisionToResult(result)
            case .result:
                scene.isPaused = true
                audioDirector?.transition(to: .result)
            }
            audioDirector?.handleLifecycle(.active)
        }
    }

    func stop() {
        guard !isStopped else { return }
        isStopped = true
        isGameLoopRequested = false
        gameLoopDriver.stop()
        invalidateCountdown()
        invalidateStartCue()
        invalidateNearMissFeedbackPresentation()
        invalidateCollision()
        touchSteering.reset()
        scene.isPaused = true
        scene.stopPresentation()
        removeAdaptiveQualityObservers()
    }

    func startGameLoop() {
        guard !isStopped else { return }
        isGameLoopRequested = true
        if lifecyclePhase == .active {
            gameLoopDriver.start()
        }
    }

    func stopGameLoop() {
        isGameLoopRequested = false
        gameLoopDriver.stop()
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
        receive(
            snapshot: snapshot,
            presentationEvents: events.map { event in
                GameEventPresentation(
                    event: event,
                    snapshot: snapshot,
                    configuration: scene.configuration
                )
            }
        )
    }

    func receive(
        snapshot: GameSnapshot,
        presentationEvents: [GameEventPresentation]
    ) {
        if renderSnapshot != snapshot {
            renderSnapshot = snapshot
        }
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
        if let event = presentationEvents.last?.event {
            lastEvent = event
        }
        let feedbackEvents = feedbackCoordinator.feedback(for: presentationEvents)
        var collisionResult: RunResult?
        if wasRunning, snapshot.phase == .crashed, !didRecordResult {
            didRecordResult = true
            let result = resultRecorder(snapshot.score)
            collisionResult = result
            invalidateCountdown()
            invalidateStartCue()
            presentationPhase = .collision(result)
            scene.isPaused = false
            audioDirector?.transition(to: .impact)
        }

        for feedback in feedbackEvents {
            switch feedback.kind {
            case .nearMiss:
                presentNearMissFeedback(feedback)
                audioDirector?.play(
                    .nearMiss,
                    eventID: feedback.eventID,
                    rate: feedback.nearMissGrade == .strong ? 1.08 : 0.96,
                    pan: feedback.spatialContext?.side.audioPan ?? 0,
                    gain: nearMissAudioGain(for: feedback)
                )
            case .collision:
                invalidateNearMissFeedbackPresentation()
                audioDirector?.transition(to: .impact)
                let closeness = feedback.spatialContext?.closeness ?? 0
                audioDirector?.play(
                    .collision,
                    eventID: feedback.eventID,
                    rate: 0.95 + closeness * 0.05,
                    pan: feedback.spatialContext?.side.audioPan ?? 0,
                    gain: 0.75 + closeness * 0.25
                )
            }
            scene.present(feedback)
            if feedback.isHapticEligible, isHapticsEnabled() {
                feedbackPlayer?.play(feedback)
                do {
                    try watchFeedbackSender?.sendFeedback(
                        WatchFeedbackPacket(eventID: feedback.eventID, kind: feedback.watchKind)
                    )
                } catch {
                    feedbackDeliveryFailures += 1
                }
            }
        }

        if presentationPhase == .racing {
            audioDirector?.update(
                speed: snapshot.speed,
                initialSpeed: audioInitialSpeed,
                maximumSpeed: audioMaximumSpeed,
                steering: steeringSnapshot.value,
                timestamp: snapshot.elapsedTime
            )
        }

        if let collisionResult {
            beginCollisionTransition(result: collisionResult)
        }
    }

    private func nearMissAudioGain(for feedback: GameFeedback) -> Double {
        let closeness = feedback.spatialContext?.closeness ?? 0
        let gradeBoost = feedback.nearMissGrade == .strong ? 0.08 : 0
        let chainBoost = Double(max(feedback.chainTier - 1, 0)) * 0.04
        return min(0.55 + closeness * 0.29 + gradeBoost + chainBoost, 1)
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
        invalidateStartCue()
        invalidateCollision()
        presentationPhase = .countdown(3)
        scene.isPaused = true
        audioDirector?.transition(to: .countdown)
        guard lifecyclePhase == .active, !isStopped else { return }

        emitStartCue(.three)

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
        emitStartCue(value == 2 ? .two : .one)
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
        adaptiveEnvironmentQualityState.beginRacing(at: currentTime())
        audioDirector?.transition(to: .racing)
        scene.isPaused = false
        emitStartCue(.go)
    }

    private func invalidateCountdown() {
        countdownGeneration &+= 1
        countdownTask?.cancel()
        countdownTask = nil
    }

    private func emitStartCue(_ kind: StartCueKind) {
        invalidateStartCue()
        guard !isStopped, lifecyclePhase == .active else { return }

        let cue = StartCuePresentation(
            id: makeStartCueEventID(),
            kind: kind,
            emittedAt: currentTime()
        )
        startCuePresentation = cue
#if DEBUG
        SG6AcceptanceProbe.recordStartCueEmitted(cue)
#endif
        audioDirector?.play(cue.audioCue, eventID: cue.id, rate: cue.audioRate)
        if isHapticsEnabled() {
#if DEBUG
            SG6AcceptanceProbe.recordStartCueHapticFanout(cue)
#endif
            feedbackPlayer?.playStartCue(cue)
            do {
                try watchFeedbackSender?.sendFeedback(
                    WatchFeedbackPacket(eventID: cue.id, kind: cue.watchKind)
                )
            } catch {
                feedbackDeliveryFailures += 1
            }
        }
    }

    func startCueDidBecomeVisible(id: UUID) {
        guard !isStopped,
              lifecyclePhase == .active,
              startCueTask == nil,
              let cue = startCuePresentation,
              cue.id == id else {
            return
        }

        let generation = startCueGeneration
        let sleeper = presentationSleeper
        startCueTask = Task { [weak self] in
            do {
                try await sleeper(cue.visibleDuration)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            self?.removeStartCue(id: cue.id, generation: generation)
        }
    }

    private func removeStartCue(id: UUID, generation: UInt64) {
        guard !isStopped,
              startCueGeneration == generation,
              startCuePresentation?.id == id else {
            return
        }
        startCueTask = nil
        startCuePresentation = nil
    }

    private func invalidateStartCue() {
        startCueGeneration &+= 1
        startCueTask?.cancel()
        startCueTask = nil
        startCuePresentation = nil
    }

    private func presentNearMissFeedback(_ feedback: GameFeedback) {
        guard presentedNearMissFeedbackIDs.insert(feedback.eventID).inserted else {
            duplicateNearMissFeedbackCount += 1
            return
        }
        invalidateNearMissFeedbackPresentation()
        nearMissFeedbackPresentation = feedback
        let generation = nearMissFeedbackGeneration
        nearMissFeedbackTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(680))
            guard !Task.isCancelled else { return }
            self?.removeNearMissFeedbackPresentation(
                id: feedback.eventID,
                generation: generation
            )
        }
    }

    private func removeNearMissFeedbackPresentation(id: UUID, generation: UInt64) {
        guard nearMissFeedbackGeneration == generation,
              nearMissFeedbackPresentation?.eventID == id else {
            return
        }
        nearMissFeedbackTask = nil
        nearMissFeedbackPresentation = nil
    }

    private func invalidateNearMissFeedbackPresentation() {
        nearMissFeedbackGeneration &+= 1
        nearMissFeedbackTask?.cancel()
        nearMissFeedbackTask = nil
        nearMissFeedbackPresentation = nil
    }

    private func resetNearMissFeedbackPresentation() {
        invalidateNearMissFeedbackPresentation()
        presentedNearMissFeedbackIDs.removeAll(keepingCapacity: true)
        duplicateNearMissFeedbackCount = 0
    }

    private func beginCollisionTransition(result: RunResult) {
        invalidateCollision()
        guard !isStopped,
              lifecyclePhase == .active,
              case let .collision(currentResult) = presentationPhase,
              currentResult == result else {
            return
        }

        let generation = collisionGeneration
        let sleeper = collisionSleeper
        collisionTask = Task { [weak self] in
            do {
                try await sleeper(GameScene.collisionTotalDuration)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            self?.finishCollision(result: result, generation: generation)
        }
    }

    private func finishCollision(result: RunResult, generation: UInt64) {
        guard !isStopped,
              lifecyclePhase == .active,
              collisionGeneration == generation,
              case let .collision(currentResult) = presentationPhase,
              currentResult == result else {
            return
        }
        collisionTask = nil
        scene.finishCollisionPresentation()
        scene.isPaused = true
        presentationPhase = .result(result)
        audioDirector?.transition(to: .result)
    }

    private func promoteCollisionToResult(_ result: RunResult) {
        invalidateCollision()
        scene.finishCollisionPresentation()
        scene.isPaused = true
        presentationPhase = .result(result)
        audioDirector?.transition(to: .result)
    }

    private func invalidateCollision() {
        collisionGeneration &+= 1
        collisionTask?.cancel()
        collisionTask = nil
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

    private func receiveFrameRate(_ value: Double) {
        guard presentationPhase == .racing, value.isFinite, value > 0 else {
            return
        }
        applyAdaptiveQualityTransition(
            adaptiveEnvironmentQualityState.receiveFrameRateSample(
                value,
                at: currentTime()
            )
        )
#if DEBUG
        recordFrameRateDiagnostic(value)
#endif
    }

    func receiveEnvironmentFrameRateSample(_ value: Double, at timestamp: TimeInterval) {
        guard presentationPhase == .racing else { return }
        applyAdaptiveQualityTransition(
            adaptiveEnvironmentQualityState.receiveFrameRateSample(value, at: timestamp)
        )
    }

    func receiveEnvironmentThermalState(
        _ state: RacingEnvironmentThermalState,
        at timestamp: TimeInterval? = nil
    ) {
        applyAdaptiveQualityTransition(
            adaptiveEnvironmentQualityState.receiveThermalState(state, at: timestamp)
        )
    }

    func receiveEnvironmentMemoryWarning(at timestamp: TimeInterval? = nil) {
        applyAdaptiveQualityTransition(
            adaptiveEnvironmentQualityState.receiveMemoryWarning(at: timestamp)
        )
    }

    private func resetAdaptiveEnvironmentQualityForNewRun() {
        let tier = initialEnvironmentQualityTier()
        adaptiveEnvironmentQualityState.reset(initialTier: tier)
        environmentQualityTier = tier
        environmentQualityRunID &+= 1
    }

    var adaptiveQualityObserverCount: Int {
        adaptiveQualityObservers.count
    }

    private func applyAdaptiveQualityTransition(
        _ transition: RacingEnvironmentQualityTransition?
    ) {
        guard let transition else { return }
        environmentQualityTier = transition.toTier
        RacingEnvironmentQualityTransitionLogger.log(transition)
    }

    private func installAdaptiveQualityObservers() {
        let thermalObserver = adaptiveQualityNotificationCenter.addObserver(
            forName: ProcessInfo.thermalStateDidChangeNotification,
            object: adaptiveQualityProcessInfo,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.receiveEnvironmentThermalState(
                    RacingEnvironmentQualityProductionAdapter.thermalState(
                        self.adaptiveQualityProcessInfo.thermalState
                    ),
                    at: self.currentTime()
                )
            }
        }
        let memoryObserver = adaptiveQualityNotificationCenter.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.receiveEnvironmentMemoryWarning(at: self.currentTime())
            }
        }
        adaptiveQualityObservers = [thermalObserver, memoryObserver]
    }

    private func removeAdaptiveQualityObservers() {
        for observer in adaptiveQualityObservers {
            adaptiveQualityNotificationCenter.removeObserver(observer)
        }
        adaptiveQualityObservers.removeAll()
    }

#if DEBUG
    private func recordFrameRateDiagnostic(_ value: Double) {
        framesPerSecond = value
        frameRateSampleCount += 1
        frameRateSum += value
        frameRateSamples.append(value)
        frameRateSamplePhases.append(presentationPhase)
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
