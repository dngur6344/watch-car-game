#if DEBUG
import Darwin
import Foundation
import OSLog

@MainActor
enum SG6AcceptanceProbe {
    enum EventKind: Equatable {
        case appInitializationComplete
        case hubFirstLayout
        case presentationReady(PresentationRoute)
        case countdownRendered(Int)
        case startCueEmitted(StartCuePresentation)
        case startCueVisible(UUID, StartCueKind)
        case startCueHidden(UUID, StartCueKind)
        case startCueHapticFanout(UUID)
        case accessibilityPolicyApplied(SensoryAccessibilityPolicy)
        case collisionRendered
        case resultRendered
    }

    struct Event {
        let sequence: Int
        let kind: EventKind
        let timestamp: TimeInterval
    }

    private(set) static var appStartTimestamp: TimeInterval?
    private static var events: [Event] = []

    static func activateIfRequested(
        arguments: [String] = ProcessInfo.processInfo.arguments
    ) {
        let isRequested = arguments.contains("--sg6-presentation")
            || arguments.contains("--sg8-sensory")
        guard isRequested, appStartTimestamp == nil else {
            return
        }
        appStartTimestamp = ProcessInfo.processInfo.systemUptime
    }

    static func recordHubFirstLayout() {
        record(.hubFirstLayout)
    }

    static func recordAppInitializationComplete() {
        record(.appInitializationComplete)
    }

    static func recordPresentationReady(route: PresentationRoute) {
        record(.presentationReady(route))
    }

    static func recordCountdownRendered(_ value: Int) {
        record(.countdownRendered(value))
    }

    static func recordStartCueEmitted(_ cue: StartCuePresentation) {
        record(.startCueEmitted(cue))
    }

    static func recordStartCueVisible(_ cue: StartCuePresentation) {
        record(.startCueVisible(cue.id, cue.kind))
    }

    static func recordStartCueHidden(_ cue: StartCuePresentation) {
        record(.startCueHidden(cue.id, cue.kind))
    }

    static func recordStartCueHapticFanout(_ cue: StartCuePresentation) {
        record(.startCueHapticFanout(cue.id))
    }

    static func recordAccessibilityPolicyApplied(_ policy: SensoryAccessibilityPolicy) {
        record(.accessibilityPolicyApplied(policy))
    }

    static func recordCollisionRendered() {
        record(.collisionRendered)
    }

    static func recordResultRendered() {
        record(.resultRendered)
    }

    static func event(matching kind: EventKind, after sequence: Int) -> Event? {
        events.first { $0.sequence > sequence && $0.kind == kind }
    }

    static func events(after sequence: Int) -> [Event] {
        events.filter { $0.sequence > sequence }
    }

    static var latestSequence: Int {
        events.last?.sequence ?? 0
    }

    private static func record(_ kind: EventKind) {
        guard appStartTimestamp != nil else { return }
        events.append(
            Event(
                sequence: events.count + 1,
                kind: kind,
                timestamp: ProcessInfo.processInfo.systemUptime
            )
        )
    }
}

struct SG8SensoryLaunchConfiguration: Equatable {
    let effectIntensity: SensoryEffectIntensity?
    let expectedReduceMotion: Bool?
    let expectedReduceTransparency: Bool?

    init(arguments: [String]) {
        effectIntensity = Self.value(after: "--sg8-effect-intensity", in: arguments)
            .flatMap(SensoryEffectIntensity.init(rawValue:))
        expectedReduceMotion = Self.boolValue(
            after: "--sg8-expect-reduce-motion",
            in: arguments
        )
        expectedReduceTransparency = Self.boolValue(
            after: "--sg8-expect-reduce-transparency",
            in: arguments
        )
    }

    private static func value(after argument: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: argument),
              arguments.indices.contains(index + 1) else {
            return nil
        }
        return arguments[index + 1]
    }

    private static func boolValue(after argument: String, in arguments: [String]) -> Bool? {
        switch value(after: argument, in: arguments) {
        case "true": true
        case "false": false
        default: nil
        }
    }
}

struct SG8SensoryCueEvaluation {
    static let expectedOrder: [StartCueKind] = [.three, .two, .one, .go]
    static let maximumVisibilityTimingErrorMilliseconds = 50.0

    let cueOrder: [StartCueKind]
    let contractDurationsMilliseconds: [Double]
    let visibleDurationsMilliseconds: [Double]
    let hapticFanoutCount: Int
    let pass: Bool

    init(events: [SG6AcceptanceProbe.Event]) {
        let emittedCues = events.compactMap { event -> StartCuePresentation? in
            guard case let .startCueEmitted(cue) = event.kind else { return nil }
            return cue
        }
        let visibleStartEvents = events.filter {
            if case .startCueVisible = $0.kind { return true }
            return false
        }
        let visibleEndEvents = events.filter {
            if case .startCueHidden = $0.kind { return true }
            return false
        }
        let visibleStarts = visibleStartEvents.reduce(
            into: [UUID: SG6AcceptanceProbe.Event]()
        ) {
            result, event in
            guard case let .startCueVisible(id, _) = event.kind, result[id] == nil else {
                return
            }
            result[id] = event
        }
        let visibleEnds = visibleEndEvents.reduce(
            into: [UUID: SG6AcceptanceProbe.Event]()
        ) {
            result, event in
            guard case let .startCueHidden(id, _) = event.kind, result[id] == nil else {
                return
            }
            result[id] = event
        }

        cueOrder = emittedCues.map(\.kind)
        contractDurationsMilliseconds = emittedCues.map { $0.visibleDuration * 1_000 }
        visibleDurationsMilliseconds = emittedCues.compactMap { cue in
            guard let start = visibleStarts[cue.id],
                  let end = visibleEnds[cue.id],
                  case let .startCueVisible(_, visibleKind) = start.kind,
                  case let .startCueHidden(_, hiddenKind) = end.kind,
                  visibleKind == cue.kind,
                  hiddenKind == cue.kind,
                  end.timestamp >= start.timestamp else {
                return nil
            }
            return (end.timestamp - start.timestamp) * 1_000
        }
        let hapticCueIDs = events.compactMap { event -> UUID? in
            guard case let .startCueHapticFanout(id) = event.kind else { return nil }
            return id
        }
        hapticFanoutCount = hapticCueIDs.count

        let expectedContracts = zip(Self.expectedOrder, [180.0, 180.0, 180.0, 260.0])
        let contractMatches = emittedCues.count == Self.expectedOrder.count
            && zip(emittedCues, expectedContracts).allSatisfy { cue, expected in
                cue.kind == expected.0
                    && abs(cue.visibleDuration * 1_000 - expected.1) < 0.001
                    && Self.visualTreatmentMatchesContract(cue)
            }
        let visibilityMatches = visibleDurationsMilliseconds.count == emittedCues.count
            && zip(visibleDurationsMilliseconds, contractDurationsMilliseconds).allSatisfy {
                measured, contract in
                measured > 0
                    && abs(measured - contract)
                        <= Self.maximumVisibilityTimingErrorMilliseconds
            }
        let emittedIDs = emittedCues.map(\.id)
        pass = cueOrder == Self.expectedOrder
            && Set(emittedIDs).count == Self.expectedOrder.count
            && visibleStartEvents.count == Self.expectedOrder.count
            && visibleEndEvents.count == Self.expectedOrder.count
            && visibleStarts.count == Self.expectedOrder.count
            && visibleEnds.count == Self.expectedOrder.count
            && contractMatches
            && visibilityMatches
            && Set(hapticCueIDs).count == hapticCueIDs.count
            && hapticCueIDs.allSatisfy { emittedIDs.contains($0) }
    }

    private static func visualTreatmentMatchesContract(_ cue: StartCuePresentation) -> Bool {
        switch (cue.kind, cue.visualTreatment) {
        case (.three, .ring(.cyan)),
             (.two, .ring(.mint)),
             (.one, .ring(.orange)),
             (.go, .fullScreenSweep(.mintWhite)):
            return true
        default:
            return false
        }
    }
}

@MainActor
final class SG6AcceptanceCoordinator {
    private enum Mode: String {
        case presentation = "--sg6-presentation"
        case fps = "--sg6-fps"
        case memory = "--sg6-memory"
        case sensory = "--sg8-sensory"

        var summaryPrefix: String {
            switch self {
            case .presentation: "SG6_PRESENTATION_SUMMARY"
            case .fps: "SG6_FPS_SUMMARY"
            case .memory: "SG6_MEMORY_SUMMARY"
            case .sensory: "SG8_SENSORY_SUMMARY"
            }
        }
    }

    private let flow: AppFlowController
    private let sensorySettings: SensorySettingsController
    private let sensoryLaunchConfiguration: SG8SensoryLaunchConfiguration
    private let mode: Mode
    private let startDelay: TimeInterval
    private let logger = Logger(
        subsystem: "com.woohyuk.WatchCarRacer",
        category: "SG6Acceptance"
    )
    private var task: Task<Void, Never>?

    private init(
        flow: AppFlowController,
        sensorySettings: SensorySettingsController,
        sensoryLaunchConfiguration: SG8SensoryLaunchConfiguration,
        mode: Mode,
        startDelay: TimeInterval
    ) {
        self.flow = flow
        self.sensorySettings = sensorySettings
        self.sensoryLaunchConfiguration = sensoryLaunchConfiguration
        self.mode = mode
        self.startDelay = startDelay
    }

    static func makeIfRequested(
        flow: AppFlowController,
        sensorySettings: SensorySettingsController,
        arguments: [String] = ProcessInfo.processInfo.arguments
    ) -> SG6AcceptanceCoordinator? {
        guard let argument = arguments.first(where: { Mode(rawValue: $0) != nil }),
              let mode = Mode(rawValue: argument) else {
            return nil
        }
        let coordinator = SG6AcceptanceCoordinator(
            flow: flow,
            sensorySettings: sensorySettings,
            sensoryLaunchConfiguration: SG8SensoryLaunchConfiguration(arguments: arguments),
            mode: mode,
            startDelay: startDelay(in: arguments)
        )
        coordinator.start()
        return coordinator
    }

    private static func startDelay(in arguments: [String]) -> TimeInterval {
        guard let index = arguments.firstIndex(of: "--sg6-start-delay"),
              arguments.indices.contains(index + 1),
              let delay = TimeInterval(arguments[index + 1]),
              delay.isFinite else {
            return 1
        }
        return max(delay, 0)
    }

    private func start() {
        task = Task { [weak self] in
            guard let self else { return }
            if startDelay > 0 {
                do {
                    try await Task.sleep(for: .seconds(startDelay))
                } catch {
                    emitSummary(pass: false, reason: "cancelled_before_start")
                    return
                }
            }

            log("SG6_ACCEPTANCE_START mode=\(mode.rawValue) delay=\(startDelay)")
            let summary: String
            switch mode {
            case .presentation:
                summary = await runPresentationAcceptance()
            case .fps:
                summary = await runFrameRateAcceptance()
            case .memory:
                summary = await runMemoryAcceptance()
            case .sensory:
                summary = await runSensoryAcceptance()
            }
            log(summary)
        }
    }

    private func runPresentationAcceptance() async -> String {
        guard let appStartTimestamp = SG6AcceptanceProbe.appStartTimestamp else {
            return presentationFailure("probe_not_activated")
        }

        var cursor = 0
        guard let appInitialization = await waitForProbeEvent(
            .appInitializationComplete,
            after: cursor,
            timeout: 5
        ) else {
            return presentationFailure("app_initialization_timeout")
        }
        cursor = appInitialization.sequence
        guard let hubLayout = await waitForProbeEvent(
            .hubFirstLayout,
            after: cursor,
            timeout: 5
        ) else {
            return presentationFailure("hub_first_layout_timeout")
        }
        cursor = hubLayout.sequence
        guard let hubColdReady = await waitForProbeEvent(
            .presentationReady(.hub),
            after: 0,
            timeout: 5
        ) else {
            return presentationFailure("hub_cold_ready_timeout")
        }
        cursor = max(cursor, hubColdReady.sequence)

        let hubColdLayoutMilliseconds = milliseconds(hubLayout.timestamp - appStartTimestamp)
        let hubColdReadyMilliseconds = milliseconds(hubColdReady.timestamp - appStartTimestamp)
        let appInitializationMilliseconds = milliseconds(
            appInitialization.timestamp - appStartTimestamp
        )
        var maintenanceMeasurements: [Double] = []
        var hubWarmMeasurements: [Double] = []

        for maintenanceVisit in 0...3 {
            let maintenanceStart = ProcessInfo.processInfo.systemUptime
            flow.enterMaintenance()
            guard flow.route == .maintenance,
                  let maintenanceReady = await waitForProbeEvent(
                    .presentationReady(.maintenance),
                    after: cursor,
                    timeout: 3
                  ) else {
                return presentationFailure("maintenance_ready_timeout_\(maintenanceVisit)")
            }
            cursor = maintenanceReady.sequence
            maintenanceMeasurements.append(
                milliseconds(maintenanceReady.timestamp - maintenanceStart)
            )

            let hubStart = ProcessInfo.processInfo.systemUptime
            flow.exitMaintenance()
            guard flow.route == .hub,
                  let hubReady = await waitForProbeEvent(
                    .presentationReady(.hub),
                    after: cursor,
                    timeout: 3
                  ) else {
                return presentationFailure("hub_warm_ready_timeout_\(maintenanceVisit)")
            }
            cursor = hubReady.sequence
            if hubWarmMeasurements.count < 3 {
                hubWarmMeasurements.append(milliseconds(hubReady.timestamp - hubStart))
            }
        }

        guard maintenanceMeasurements.count == 4,
              hubWarmMeasurements.count == 3 else {
            return presentationFailure("route_measurement_count")
        }
        guard await waitForAssetReadiness(timeout: 15) else {
            return presentationFailure("game_assets_not_ready")
        }

        let driveStart = ProcessInfo.processInfo.systemUptime
        guard flow.drive(controlRoute: .touchOnly), let controller = flow.gameSession else {
            return presentationFailure("drive_not_accepted")
        }
        let driveReturned = ProcessInfo.processInfo.systemUptime
        guard let countdown3 = await waitForProbeEvent(
            .countdownRendered(3),
            after: cursor,
            timeout: 2
        ) else {
            return presentationFailure("countdown_3_render_timeout")
        }
        cursor = countdown3.sequence
        guard let countdown2 = await waitForProbeEvent(
            .countdownRendered(2),
            after: cursor,
            timeout: 2
        ) else {
            return presentationFailure("countdown_2_render_timeout")
        }
        cursor = countdown2.sequence
        guard let countdown1 = await waitForProbeEvent(
            .countdownRendered(1),
            after: cursor,
            timeout: 2
        ) else {
            return presentationFailure("countdown_1_render_timeout")
        }
        guard let racingTimestamp = await waitUntilRacing(controller, timeout: 2) else {
            return presentationFailure("racing_transition_timeout")
        }

        let driveToCountdown3 = milliseconds(countdown3.timestamp - driveStart)
        let driveConstruction = milliseconds(driveReturned - driveStart)
        let gameMount = milliseconds(countdown3.timestamp - driveReturned)
        let countdownIntervals = [
            milliseconds(countdown2.timestamp - countdown3.timestamp),
            milliseconds(countdown1.timestamp - countdown2.timestamp),
            milliseconds(racingTimestamp - countdown1.timestamp),
        ]
        let countdownTotal = milliseconds(racingTimestamp - countdown3.timestamp)
        let maintenanceCold = maintenanceMeasurements[0]
        let maintenanceWarm = Array(maintenanceMeasurements.dropFirst())
        let passed = hubColdLayoutMilliseconds <= 1_500
            && hubColdReadyMilliseconds <= 1_500
            && maintenanceMeasurements.allSatisfy { $0 <= 500 }
            && hubWarmMeasurements.allSatisfy { $0 <= 250 }
            && driveToCountdown3 <= 250
            && countdownIntervals.allSatisfy { (850...1_150).contains($0) }
            && (2_850...3_150).contains(countdownTotal)

        return "SG6_PRESENTATION_SUMMARY pass=\(passed) "
            + "appInitMs=\(formatted(appInitializationMilliseconds)) "
            + "hubColdLayoutMs=\(formatted(hubColdLayoutMilliseconds)) "
            + "hubColdReadyMs=\(formatted(hubColdReadyMilliseconds)) "
            + "maintenanceColdMs=\(formatted(maintenanceCold)) "
            + "maintenanceWarmMs=\(serialized(maintenanceWarm)) "
            + "hubWarmMs=\(serialized(hubWarmMeasurements)) "
            + "driveConstructionMs=\(formatted(driveConstruction)) "
            + "gameMountMs=\(formatted(gameMount)) "
            + "driveCountdown3Ms=\(formatted(driveToCountdown3)) "
            + "countdownIntervalsMs=\(serialized(countdownIntervals)) "
            + "countdownTotalMs=\(formatted(countdownTotal))"
    }

    private func runFrameRateAcceptance() async -> String {
        guard await waitForAssetReadiness(timeout: 15) else {
            return fpsFailure("asset_preload_failed")
        }
        guard flow.drive(controlRoute: .touchOnly), let controller = flow.gameSession else {
            return fpsFailure("controller_creation_failed")
        }
        guard await waitUntilRacing(controller, timeout: 5) != nil else {
            return fpsFailure("initial_countdown_timeout")
        }

        let startingSampleIndex = controller.frameRateSamples.count
        let targetSampleCount = 300
        let acceptanceDeadline = ProcessInfo.processInfo.systemUptime + 450
        var gameplayRetries = 0
        var lastObservedSampleCount = startingSampleIndex
        var lastSampleProgressTimestamp = ProcessInfo.processInfo.systemUptime
        var freezeDetected = false
        var stateLossDetected = false

        while controller.frameRateSamples.count - startingSampleIndex < targetSampleCount,
              ProcessInfo.processInfo.systemUptime < acceptanceDeadline {
            guard flow.route == .playing, flow.gameSession === controller else {
                stateLossDetected = true
                break
            }

            let currentSampleCount = controller.frameRateSamples.count
            if currentSampleCount != lastObservedSampleCount {
                lastObservedSampleCount = currentSampleCount
                lastSampleProgressTimestamp = ProcessInfo.processInfo.systemUptime
            }

            switch controller.presentationPhase {
            case .racing:
                steerSafely(controller)
                if ProcessInfo.processInfo.systemUptime - lastSampleProgressTimestamp > 3 {
                    freezeDetected = true
                }
            case .result:
                gameplayRetries += 1
                log(
                    "SG6_FPS_GAMEPLAY_COLLISION retry=\(gameplayRetries) "
                        + "sample=\(currentSampleCount) score=\(controller.score)"
                )
                controller.retry()
                lastSampleProgressTimestamp = ProcessInfo.processInfo.systemUptime
            case .countdown, .collision:
                // Required retry countdowns intentionally pause GameScene updates and samples.
                lastSampleProgressTimestamp = ProcessInfo.processInfo.systemUptime
            }

            if freezeDetected { break }
            try? await Task.sleep(for: .milliseconds(50))
        }
        controller.releaseTouch()

        let samples = Array(
            controller.frameRateSamples
                .dropFirst(startingSampleIndex)
                .prefix(targetSampleCount)
        )
        let average = samples.isEmpty ? 0 : samples.reduce(0, +) / Double(samples.count)
        let minimum = samples.min() ?? 0
        let maximumConsecutiveBelow50 = Self.maximumConsecutiveSamples(
            below: 50,
            in: samples
        )
        let firstObstacleSample = controller.firstObstacleFrameRateSample
        let firstObstaclePassed = firstObstacleSample.map { $0 >= 50 } ?? false
        let timedOut = samples.count < targetSampleCount
            && ProcessInfo.processInfo.systemUptime >= acceptanceDeadline
        let passed = samples.count == targetSampleCount
            && average >= 58
            && maximumConsecutiveBelow50 < 2
            && firstObstaclePassed
            && !freezeDetected
            && !stateLossDetected
            && !timedOut

        return "SG6_FPS_SUMMARY pass=\(passed) samples=\(samples.count) "
            + "average=\(formatted(average)) minimum=\(formatted(minimum)) "
            + "maxConsecutiveBelow50=\(maximumConsecutiveBelow50) "
            + "firstObstacleSample=\(formatted(firstObstacleSample)) "
            + "firstObstaclePass=\(firstObstaclePassed) freeze=\(freezeDetected) "
            + "stateLoss=\(stateLossDetected) timeout=\(timedOut) "
            + "gameplayRetries=\(gameplayRetries)"
    }

    private func runMemoryAcceptance() async -> String {
        guard await waitForAssetReadiness(timeout: 15) else {
            return memoryFailure("asset_preload_failed")
        }
        guard let warmup = await completeMemoryCycle(label: "warmup"),
              warmup.controllerReleased,
              warmup.sceneReleased else {
            return memoryFailure("warmup_failed")
        }

        var samples: [UInt64] = []
        samples.reserveCapacity(10)
        var releasedControllers = 0
        var releasedScenes = 0

        try? await Task.sleep(for: .seconds(10))
        guard let baseline = stabilizedResidentMemoryBytes() else {
            return memoryFailure("baseline_rss_unavailable")
        }
        log("SG6_MEMORY_BASELINE residentBytes=\(baseline) idleSeconds=10")

        for cycle in 1...10 {
            guard let release = await completeMemoryCycle(label: "cycle_\(cycle)") else {
                return memoryFailure("cycle_failed_\(cycle)")
            }
            if release.controllerReleased { releasedControllers += 1 }
            if release.sceneReleased { releasedScenes += 1 }

            try? await Task.sleep(for: .seconds(1))
            guard let residentBytes = stabilizedResidentMemoryBytes() else {
                return memoryFailure("rss_unavailable_\(cycle)")
            }
            samples.append(residentBytes)
        }

        try? await Task.sleep(for: .seconds(10))
        guard let finalResidentBytes = stabilizedResidentMemoryBytes() else {
            return memoryFailure("final_rss_unavailable")
        }
        let threshold = Double(baseline) * 1.15
        let lastFive = Array((samples + [finalResidentBytes]).suffix(5))
        let lastFiveStrictlyIncreasing = lastFive.count == 5
            && zip(lastFive, lastFive.dropFirst()).allSatisfy { $0.0 < $0.1 }
        let passed = Double(finalResidentBytes) <= threshold
            && !lastFiveStrictlyIncreasing
            && releasedControllers == 10
            && releasedScenes == 10

        return "SG6_MEMORY_SUMMARY pass=\(passed) baselineBytes=\(baseline) "
            + "samples=\(samples.map(String.init).joined(separator: ",")) "
            + "finalBytes=\(finalResidentBytes) "
            + "thresholdBytes=\(UInt64(threshold.rounded(.down))) "
            + "lastFiveStrictlyIncreasing=\(lastFiveStrictlyIncreasing) "
            + "releasedControllers=\(releasedControllers)/10 "
            + "releasedScenes=\(releasedScenes)/10"
    }

    private struct SensoryCueRun {
        let evaluation: SG8SensoryCueEvaluation
        let lastSequence: Int
    }

    @MainActor
    private struct SensoryPoolAudit {
        private(set) var isBounded = true
        private(set) var maximumActiveStreaks = 0
        private(set) var maximumActiveRoadLights = 0
        private(set) var maximumActiveFogBands = 0
        private(set) var maximumScheduledDebris = 0

        mutating func observe(_ diagnostics: GameScene.PresentationDiagnostics) {
            let maximumEdgeStreakCount = GameScene.maximumEdgeStreakCount
            let maximumRoadLightCount = GameScene.maximumRoadLightCount
            let maximumFogBandCount = GameScene.maximumFogBandCount
            let maximumCollisionDebrisCount = GameScene.maximumCollisionDebrisCount
            let observations = [
                diagnostics.edgeStreakNodeCount == maximumEdgeStreakCount,
                diagnostics.activeEdgeStreakCount <= maximumEdgeStreakCount,
                diagnostics.roadLightNodeCount == maximumRoadLightCount,
                diagnostics.activeRoadLightCount <= maximumRoadLightCount,
                diagnostics.fogBandNodeCount == maximumFogBandCount,
                diagnostics.activeFogBandCount <= maximumFogBandCount,
                diagnostics.debrisNodeCount == maximumCollisionDebrisCount,
                diagnostics.activeDebrisCount <= maximumCollisionDebrisCount,
                diagnostics.scheduledDebrisCount <= maximumCollisionDebrisCount,
                diagnostics.unexpectedFeedbackNodeCount == 0,
            ]
            isBounded = isBounded && observations.allSatisfy { $0 }
            maximumActiveStreaks = max(
                maximumActiveStreaks,
                diagnostics.activeEdgeStreakCount
            )
            maximumActiveRoadLights = max(
                maximumActiveRoadLights,
                diagnostics.activeRoadLightCount
            )
            maximumActiveFogBands = max(
                maximumActiveFogBands,
                diagnostics.activeFogBandCount
            )
            maximumScheduledDebris = max(
                maximumScheduledDebris,
                diagnostics.scheduledDebrisCount
            )
        }
    }

    private struct SensoryNearMissAudit {
        var eventSides: [FeedbackSide] = []
        var visibleSides: [FeedbackSide] = []
        var poolAudit: SensoryPoolAudit

        var hasBothSides: Bool {
            eventSides.contains(.left)
                && eventSides.contains(.right)
                && visibleSides.contains(.left)
                && visibleSides.contains(.right)
        }
    }

    private func runSensoryAcceptance() async -> String {
        guard flow.route == .hub, flow.gameSession == nil else {
            return sensoryFailure("invalid_initial_route")
        }
        guard await waitForAssetReadiness(timeout: 15),
              let audioDirector = flow.audioDirector else {
            return sensoryFailure("asset_or_audio_readiness_failed")
        }

        let originalSettings = sensorySettings.settings
        defer {
            sensorySettings.setSFXEnabled(originalSettings.sfxEnabled)
            sensorySettings.setHapticsEnabled(originalSettings.hapticsEnabled)
            sensorySettings.setEffectIntensity(originalSettings.effectIntensity)
        }
        if let requestedIntensity = sensoryLaunchConfiguration.effectIntensity {
            sensorySettings.setEffectIntensity(requestedIntensity)
        }

        var directorIdentities: [ObjectIdentifier] = [audioDirector.identity]
        let backendIdentity = audioDirector.backendDiagnostics.engineIdentity
        var contextChecks: [Bool] = []
        contextChecks.append(await waitForAudioContext(.hub, director: audioDirector))

        sensorySettings.setSFXEnabled(false)
        guard await waitUntil(timeout: 2, condition: { !audioDirector.sfxEnabled }) else {
            return sensoryFailure("sfx_disable_wiring_timeout")
        }
        let disabledPlayCount = audioDirector.metrics.oneShotPlayCount
        audioDirector.play(.vehicleSelect, eventID: UUID())
        let sfxDisabledGatePassed = audioDirector.metrics.oneShotPlayCount == disabledPlayCount

        sensorySettings.setSFXEnabled(true)
        guard await waitUntil(timeout: 2, condition: { audioDirector.sfxEnabled }) else {
            return sensoryFailure("sfx_enable_wiring_timeout")
        }
        let enabledPlayCount = audioDirector.metrics.oneShotPlayCount
        audioDirector.play(.colorSelect, eventID: UUID())
        let sfxEnabledGatePassed = audioDirector.metrics.oneShotPlayCount == enabledPlayCount + 1
        let settingsGatingPassed = sfxDisabledGatePassed && sfxEnabledGatePassed

        let driveIntent = HubDriveIntentController { [flow] controlRoute in
            flow.drive(controlRoute: controlRoute)
        }
        driveIntent.requestDrive(readiness: .ready, presentationIsReady: false)
        let unavailablePresentationPassed = !driveIntent.hasStartedDrive
            && !driveIntent.hasPendingDriveIntent
            && driveIntent.driveTransitionTrigger == 0

        flow.enterMaintenance()
        guard flow.route == .maintenance else {
            return sensoryFailure("maintenance_entry_failed")
        }
        driveIntent.requestDrive(readiness: .ready)
        let failedDrivePassed = !driveIntent.hasStartedDrive
            && driveIntent.driveTransitionTrigger == 0
            && flow.route == .maintenance
        contextChecks.append(await waitForAudioContext(.maintenance, director: audioDirector))
        guard let maintenanceDirectorIdentity = flow.audioDirector?.identity else {
            return sensoryFailure("maintenance_audio_identity_missing")
        }
        directorIdentities.append(maintenanceDirectorIdentity)

        guard let nextVehicle = VehicleID.allCases.first(where: {
            $0 != flow.draftSelection.vehicleID
        }),
        let nextColor = VehicleColorID.allCases.first(where: {
            $0 != flow.draftSelection.colorID
        }) else {
            return sensoryFailure("selection_alternative_missing")
        }
        let vehicleCueStart = audioDirector.metrics.oneShotPlayCount
        let vehicleChanged = flow.selectVehicle(nextVehicle)
        let vehicleCueAfterChange = audioDirector.metrics.oneShotPlayCount
        let vehicleNoOp = !flow.selectVehicle(nextVehicle)
        let vehicleCueAfterNoOp = audioDirector.metrics.oneShotPlayCount
        let colorChanged = flow.selectColor(nextColor)
        let colorCueAfterChange = audioDirector.metrics.oneShotPlayCount
        let colorNoOp = !flow.selectColor(nextColor)
        let colorCueAfterNoOp = audioDirector.metrics.oneShotPlayCount
        let selectionCuePassed = vehicleChanged
            && vehicleNoOp
            && colorChanged
            && colorNoOp
            && vehicleCueAfterChange == vehicleCueStart + 1
            && vehicleCueAfterNoOp == vehicleCueAfterChange
            && colorCueAfterChange == vehicleCueAfterNoOp + 1
            && colorCueAfterNoOp == colorCueAfterChange

        flow.exitMaintenance()
        guard flow.route == .hub else {
            return sensoryFailure("hub_return_failed")
        }
        contextChecks.append(await waitForAudioContext(.hub, director: audioDirector))
        guard let returnedHubDirectorIdentity = flow.audioDirector?.identity else {
            return sensoryFailure("returned_hub_audio_identity_missing")
        }
        directorIdentities.append(returnedHubDirectorIdentity)

        driveIntent.requestDrive(readiness: .disconnected)
        let notReadyPendingPassed = driveIntent.hasPendingDriveIntent
            && driveIntent.isReadinessSheetPresented
            && !driveIntent.hasStartedDrive
        driveIntent.cancelPendingDrive()
        let cancelPassed = !driveIntent.hasPendingDriveIntent
            && !driveIntent.isReadinessSheetPresented
            && !driveIntent.hasStartedDrive

        sensorySettings.setHapticsEnabled(false)
        let firstCueCursor = SG6AcceptanceProbe.latestSequence
        driveIntent.requestDrive(readiness: .stale)
        let continuePendingPassed = driveIntent.hasPendingDriveIntent
            && driveIntent.isReadinessSheetPresented
        driveIntent.continueWithTouch()
        guard driveIntent.hasStartedDrive,
              driveIntent.driveTransitionTrigger == 1,
              flow.route == .playing,
              let controller = flow.gameSession,
              controller.controlRoute == .touchOnly else {
            return sensoryFailure("drive_not_accepted")
        }
        let driveIntentBranchesPassed = unavailablePresentationPassed
            && failedDrivePassed
            && notReadyPendingPassed
            && cancelPassed
            && continuePendingPassed
        guard let sessionDirectorIdentity = controller.sensoryAcceptanceAudioDirectorIdentity else {
            return sensoryFailure("session_audio_identity_missing")
        }
        directorIdentities.append(sessionDirectorIdentity)
        let firstCountdownFPSStart = controller.frameRateSamples.count
        contextChecks.append(await waitForAudioContext(.countdown, director: audioDirector))
        guard await waitUntilRacing(controller, timeout: 5) != nil else {
            return sensoryFailure("first_countdown_timeout")
        }
        let firstCountdownFPSEnd = controller.frameRateSamples.count
        contextChecks.append(await waitForAudioContext(.racing, director: audioDirector))
        guard let firstCueRun = await waitForCueRun(after: firstCueCursor, timeout: 2) else {
            return sensoryFailure("first_visible_cue_timeout")
        }
        guard let accessibilityEvent = await waitForProbeEvent(
            after: firstCueCursor,
            timeout: 2,
            matching: {
                if case .accessibilityPolicyApplied = $0 { return true }
                return false
            }
        ),
        case let .accessibilityPolicyApplied(accessibilityPolicy) = accessibilityEvent.kind else {
            return sensoryFailure("accessibility_policy_timeout")
        }
        let reduceMotion = accessibilityPolicy.camera == .off
        let reduceTransparency = accessibilityPolicy.usesOpaqueFeedback
        let accessibilityExpectationPassed = sensoryLaunchConfiguration.expectedReduceMotion
            .map { $0 == reduceMotion } ?? true
            && (sensoryLaunchConfiguration.expectedReduceTransparency
                .map { $0 == reduceTransparency } ?? true)
            && controller.scene.accessibilityPolicy == accessibilityPolicy
            && sensoryLaunchConfiguration.effectIntensity
                .map { $0 == sensorySettings.settings.effectIntensity } ?? true

        var poolAudit = SensoryPoolAudit()
        poolAudit.observe(controller.scene.presentationDiagnostics)
        guard let nearMissAudit = await steerForNearMissPresentation(
            controller,
            timeout: 35,
            startingWith: poolAudit
        ) else {
            return sensoryFailure("left_right_near_miss_timeout")
        }
        poolAudit = nearMissAudit.poolAudit
        let collisionCursor = firstCueRun.lastSequence
        guard let collisionAudit = await steerUntilCollision(
            controller,
            timeout: 30,
            startingWith: poolAudit
        ) else {
            return sensoryFailure("collision_not_reached")
        }
        poolAudit = collisionAudit
        let collisionFPSStart = controller.frameRateSamples.count
        guard let collisionRendered = await waitForProbeEvent(
            after: collisionCursor,
            timeout: 2,
            matching: { $0 == .collisionRendered }
        ) else {
            return sensoryFailure("collision_render_timeout")
        }
        contextChecks.append(await waitForAudioContext(.impact, director: audioDirector))
        poolAudit.observe(controller.scene.presentationDiagnostics)
        guard let resultRendered = await waitForProbeEvent(
            after: collisionRendered.sequence,
            timeout: 2,
            matching: { $0 == .resultRendered }
        ) else {
            return sensoryFailure("result_render_timeout")
        }
        let collisionFPSEnd = controller.frameRateSamples.count
        let collisionToResultMilliseconds = milliseconds(
            resultRendered.timestamp - collisionRendered.timestamp
        )
        let resultFPSStart = controller.frameRateSamples.count
        contextChecks.append(await waitForAudioContext(.result, director: audioDirector))
        try? await Task.sleep(for: .milliseconds(300))
        let resultFPSEnd = controller.frameRateSamples.count
        let resultDiagnostics = controller.scene.presentationDiagnostics
        poolAudit.observe(resultDiagnostics)
        let resultCleanupPassed = resultDiagnostics.activeDebrisCount == 0
            && resultDiagnostics.scheduledDebrisCount == 0
            && !resultDiagnostics.isCollisionPresentationActive

        sensorySettings.setHapticsEnabled(true)
        let retryCueCursor = SG6AcceptanceProbe.latestSequence
        let retryCountdownFPSStart = controller.frameRateSamples.count
        flow.retry()
        guard let retryDirectorIdentity = controller.sensoryAcceptanceAudioDirectorIdentity else {
            return sensoryFailure("retry_audio_identity_missing")
        }
        directorIdentities.append(retryDirectorIdentity)
        contextChecks.append(await waitForAudioContext(.countdown, director: audioDirector))
        guard await waitUntilRacing(controller, timeout: 5) != nil else {
            return sensoryFailure("retry_countdown_timeout")
        }
        let retryCountdownFPSEnd = controller.frameRateSamples.count
        contextChecks.append(await waitForAudioContext(.racing, director: audioDirector))
        guard let retryCueRun = await waitForCueRun(after: retryCueCursor, timeout: 2) else {
            return sensoryFailure("retry_visible_cue_timeout")
        }
        poolAudit.observe(controller.scene.presentationDiagnostics)

        let lifecycleCueCursor = SG6AcceptanceProbe.latestSequence
        let lifecycleCountdownFPSStart = controller.frameRateSamples.count
        flow.handleLifecycle(.background)
        let backgroundLifecyclePassed = controller.scene.isPaused
            && !controller.hasActiveCountdownTask
            && !controller.hasActiveStartCueTask
            && audioDirector.isSuspended
        try? await Task.sleep(for: .milliseconds(100))
        flow.handleLifecycle(.active)
        contextChecks.append(await waitForAudioContext(.countdown, director: audioDirector))
        guard await waitUntilRacing(controller, timeout: 5) != nil else {
            return sensoryFailure("lifecycle_countdown_timeout")
        }
        let lifecycleCountdownFPSEnd = controller.frameRateSamples.count
        contextChecks.append(await waitForAudioContext(.racing, director: audioDirector))
        guard let lifecycleCueRun = await waitForCueRun(
            after: lifecycleCueCursor,
            timeout: 2
        ) else {
            return sensoryFailure("lifecycle_visible_cue_timeout")
        }
        let foregroundLifecyclePassed = !audioDirector.isSuspended
            && controller.presentationPhase == .racing
            && !controller.scene.isPaused
        poolAudit.observe(controller.scene.presentationDiagnostics)

        let staleEventCursor = SG6AcceptanceProbe.latestSequence
        flow.returnToHub()
        guard flow.route == .hub, flow.gameSession == nil else {
            return sensoryFailure("final_hub_return_failed")
        }
        contextChecks.append(await waitForAudioContext(.hub, director: audioDirector))
        guard let finalHubDirectorIdentity = flow.audioDirector?.identity else {
            return sensoryFailure("final_hub_audio_identity_missing")
        }
        directorIdentities.append(finalHubDirectorIdentity)
        try? await Task.sleep(for: .milliseconds(700))

        let staleCueCount = SG6AcceptanceProbe.events(after: staleEventCursor).count {
            switch $0.kind {
            case .startCueEmitted,
                 .startCueVisible,
                 .startCueHidden,
                 .startCueHapticFanout:
                return true
            default:
                return false
            }
        }
        let stoppedDiagnostics = controller.scene.presentationDiagnostics
        poolAudit.observe(stoppedDiagnostics)
        let staleActionCount = (controller.hasActiveCountdownTask ? 1 : 0)
            + (controller.hasActiveStartCueTask ? 1 : 0)
            + (controller.hasActiveCollisionTask ? 1 : 0)
            + stoppedDiagnostics.nodesWithActions
            + stoppedDiagnostics.activeDebrisCount
            + stoppedDiagnostics.scheduledDebrisCount
        let poolCleanupPassed = resultCleanupPassed
            && stoppedDiagnostics.activeDebrisCount == 0
            && stoppedDiagnostics.scheduledDebrisCount == 0
            && stoppedDiagnostics.nodesWithActions == 0
            && stoppedDiagnostics.visibleScoreTexts.isEmpty

        driveIntent.beginHubVisit()
        driveIntent.requestDrive(readiness: .ready)
        guard driveIntent.hasStartedDrive,
              driveIntent.driveTransitionTrigger == 2,
              flow.route == .playing,
              let adaptiveController = flow.gameSession,
              adaptiveController.controlRoute == .adaptiveWatchPreferred,
              let adaptiveDirectorIdentity = adaptiveController
                .sensoryAcceptanceAudioDirectorIdentity else {
            return sensoryFailure("ready_adaptive_drive_failed")
        }
        directorIdentities.append(adaptiveDirectorIdentity)
        contextChecks.append(await waitForAudioContext(.countdown, director: audioDirector))
        guard await waitUntilRacing(adaptiveController, timeout: 5) != nil else {
            return sensoryFailure("adaptive_countdown_timeout")
        }
        contextChecks.append(await waitForAudioContext(.racing, director: audioDirector))
        flow.returnToHub()
        guard flow.route == .hub,
              flow.gameSession == nil,
              let adaptiveHubDirectorIdentity = flow.audioDirector?.identity else {
            return sensoryFailure("adaptive_hub_return_failed")
        }
        directorIdentities.append(adaptiveHubDirectorIdentity)
        contextChecks.append(await waitForAudioContext(.hub, director: audioDirector))
        let adaptiveCleanupPassed = !adaptiveController.hasActiveCountdownTask
            && !adaptiveController.hasActiveStartCueTask
            && !adaptiveController.hasActiveCollisionTask

        let sampledIntervalCount = (firstCountdownFPSEnd - firstCountdownFPSStart)
            + (collisionFPSEnd - collisionFPSStart)
            + (resultFPSEnd - resultFPSStart)
            + (retryCountdownFPSEnd - retryCountdownFPSStart)
            + (lifecycleCountdownFPSEnd - lifecycleCountdownFPSStart)
        let nonRacingFPSSampleCount = controller.frameRateSamplePhases.count {
            $0 != .racing
        }
        let directorStable = directorIdentities.count == 8
            && directorIdentities.allSatisfy { $0 == directorIdentities[0] }
            && audioDirector.backendDiagnostics.engineIdentity == backendIdentity
        let decodedAudioBytes = audioDirector.assetMetrics.decodedPCMByteCount
        let decodedAudioLimit = 8 * 1_024 * 1_024
        let audioBoundsPassed = audioDirector.backendDiagnostics.longLivedNodeCount <= 16
            && audioDirector.backendDiagnostics.maximumSimultaneousOneShots <= 4
        let collisionTimingPassed = (480.0...600.0).contains(collisionToResultMilliseconds)
        let firstHapticsGatePassed = firstCueRun.evaluation.hapticFanoutCount == 0
        let retryHapticsGatePassed = retryCueRun.evaluation.hapticFanoutCount == 4
        let lifecycleHapticsGatePassed = lifecycleCueRun.evaluation.hapticFanoutCount == 4
        let passed = firstCueRun.evaluation.pass
            && retryCueRun.evaluation.pass
            && lifecycleCueRun.evaluation.pass
            && firstHapticsGatePassed
            && retryHapticsGatePassed
            && lifecycleHapticsGatePassed
            && settingsGatingPassed
            && selectionCuePassed
            && driveIntentBranchesPassed
            && accessibilityExpectationPassed
            && nearMissAudit.hasBothSides
            && backgroundLifecyclePassed
            && foregroundLifecyclePassed
            && collisionTimingPassed
            && nonRacingFPSSampleCount == 0
            && directorStable
            && contextChecks.allSatisfy { $0 }
            && staleCueCount == 0
            && staleActionCount == 0
            && poolAudit.isBounded
            && poolCleanupPassed
            && adaptiveCleanupPassed
            && decodedAudioBytes <= decodedAudioLimit
            && audioBoundsPassed

        return "SG8_SENSORY_SUMMARY pass=\(passed) "
            + "cueOrder=\(serializedCueOrder(firstCueRun.evaluation.cueOrder)) "
            + "retryCueOrder=\(serializedCueOrder(retryCueRun.evaluation.cueOrder)) "
            + "cueCount=\(firstCueRun.evaluation.cueOrder.count) "
            + "retryCueCount=\(retryCueRun.evaluation.cueOrder.count) "
            + "cueContractMs=\(serialized(firstCueRun.evaluation.contractDurationsMilliseconds)) "
            + "cueVisibleMs=\(serialized(firstCueRun.evaluation.visibleDurationsMilliseconds)) "
            + "retryCueVisibleMs=\(serialized(retryCueRun.evaluation.visibleDurationsMilliseconds)) "
            + "lifecycleCueVisibleMs="
            + "\(serialized(lifecycleCueRun.evaluation.visibleDurationsMilliseconds)) "
            + "collisionResultMs=\(formatted(collisionToResultMilliseconds)) "
            + "nonRacingFPSSamples=\(nonRacingFPSSampleCount) "
            + "boundaryIntervalSamples=\(sampledIntervalCount) "
            + "directorCheckpoints=\(directorIdentities.count) directorStable=\(directorStable) "
            + "audioContexts=\(contextChecks.count) contextPass=\(contextChecks.allSatisfy { $0 }) "
            + "sfxGate=\(settingsGatingPassed) selectionCue=\(selectionCuePassed) "
            + "driveBranches=\(driveIntentBranchesPassed) hapticsOffFanout="
            + "\(firstCueRun.evaluation.hapticFanoutCount) hapticsOnFanout="
            + "\(retryCueRun.evaluation.hapticFanoutCount) lifecycleHapticsFanout="
            + "\(lifecycleCueRun.evaluation.hapticFanoutCount) lifecycle="
            + "\(backgroundLifecyclePassed && foregroundLifecyclePassed) "
            + "nearMissSides=\(serializedSides(nearMissAudit.eventSides)) "
            + "nearMissVisualSides=\(serializedSides(nearMissAudit.visibleSides)) "
            + "effectIntensity=\(sensorySettings.settings.effectIntensity.rawValue) "
            + "reduceMotion=\(reduceMotion) reduceTransparency=\(reduceTransparency) "
            + "accessibilityPass=\(accessibilityExpectationPassed) "
            + "adaptiveCleanup=\(adaptiveCleanupPassed) staleCue=\(staleCueCount) "
            + "staleAction=\(staleActionCount) poolsBounded=\(poolAudit.isBounded) "
            + "poolCleanup=\(poolCleanupPassed) maxStreaks=\(poolAudit.maximumActiveStreaks) "
            + "maxRoadLights=\(poolAudit.maximumActiveRoadLights) "
            + "maxFog=\(poolAudit.maximumActiveFogBands) "
            + "maxDebris=\(poolAudit.maximumScheduledDebris) "
            + "decodedAudioBytes=\(decodedAudioBytes) decodedAudioLimit=\(decodedAudioLimit) "
            + "audioNodes=\(audioDirector.backendDiagnostics.longLivedNodeCount) "
            + "audioOneShotsMax=\(audioDirector.backendDiagnostics.maximumSimultaneousOneShots) "
            + "audioBounds=\(audioBoundsPassed)"
    }

    private struct ReleaseResult {
        let controllerReleased: Bool
        let sceneReleased: Bool
    }

    private final class ReleaseProbe {
        weak var controller: GameSessionController?
        weak var scene: GameScene?

        init(controller: GameSessionController) {
            self.controller = controller
            scene = controller.scene
        }
    }

    private func completeMemoryCycle(label: String) async -> ReleaseResult? {
        guard flow.route == .hub, flow.gameSession == nil else {
            log("SG6_MEMORY_ROUTE label=\(label) result=invalid_initial_state")
            return nil
        }

        flow.enterMaintenance()
        guard flow.route == .maintenance else {
            log("SG6_MEMORY_ROUTE label=\(label) result=maintenance_entry_failed")
            return nil
        }
        try? await Task.sleep(for: .milliseconds(250))
        flow.exitMaintenance()
        guard flow.route == .hub else {
            log("SG6_MEMORY_ROUTE label=\(label) result=hub_return_failed")
            return nil
        }
        try? await Task.sleep(for: .milliseconds(250))

        guard flow.drive(controlRoute: .touchOnly),
              let releaseProbe = await exerciseMemorySession(label: label) else {
            log("SG6_MEMORY_ROUTE label=\(label) result=controller_creation_failed")
            return nil
        }

        flow.returnToHub()
        let releaseDeadline = ProcessInfo.processInfo.systemUptime + 2
        while (releaseProbe.controller != nil || releaseProbe.scene != nil),
              ProcessInfo.processInfo.systemUptime < releaseDeadline {
            try? await Task.sleep(for: .milliseconds(10))
        }

        let result = ReleaseResult(
            controllerReleased: releaseProbe.controller == nil,
            sceneReleased: releaseProbe.scene == nil
        )
        guard flow.route == .hub, flow.gameSession == nil else {
            return nil
        }
        return result
    }

    private func exerciseMemorySession(label: String) async -> ReleaseProbe? {
        guard let controller = flow.gameSession else { return nil }
        let releaseProbe = ReleaseProbe(controller: controller)
        guard await waitUntilRacing(controller, timeout: 5) != nil,
              await steerIntoCollision(controller, timeout: 25) else {
            controller.releaseTouch()
            log("SG6_MEMORY_ROUTE label=\(label) result=first_collision_failed")
            return nil
        }

        controller.retry()
        guard await waitUntilRacing(controller, timeout: 5) != nil,
              await steerIntoCollision(controller, timeout: 25) else {
            controller.releaseTouch()
            log("SG6_MEMORY_ROUTE label=\(label) result=retry_collision_failed")
            return nil
        }
        return releaseProbe
    }

    private func waitForAssetReadiness(timeout: TimeInterval) async -> Bool {
        if flow.assetReadiness == .idle {
            await flow.prepareAssets()
        }
        let deadline = ProcessInfo.processInfo.systemUptime + timeout
        while flow.assetReadiness == .loading,
              ProcessInfo.processInfo.systemUptime < deadline {
            try? await Task.sleep(for: .milliseconds(20))
        }
        return flow.assetReadiness == .ready
    }

    private func waitForProbeEvent(
        _ kind: SG6AcceptanceProbe.EventKind,
        after sequence: Int,
        timeout: TimeInterval
    ) async -> SG6AcceptanceProbe.Event? {
        let deadline = ProcessInfo.processInfo.systemUptime + timeout
        while ProcessInfo.processInfo.systemUptime < deadline {
            if let event = SG6AcceptanceProbe.event(matching: kind, after: sequence) {
                return event
            }
            try? await Task.sleep(for: .milliseconds(5))
        }
        return SG6AcceptanceProbe.event(matching: kind, after: sequence)
    }

    private func waitForProbeEvent(
        after sequence: Int,
        timeout: TimeInterval,
        matching predicate: (SG6AcceptanceProbe.EventKind) -> Bool
    ) async -> SG6AcceptanceProbe.Event? {
        let deadline = ProcessInfo.processInfo.systemUptime + timeout
        while ProcessInfo.processInfo.systemUptime < deadline {
            if let event = SG6AcceptanceProbe.events(after: sequence).first(where: {
                predicate($0.kind)
            }) {
                return event
            }
            try? await Task.sleep(for: .milliseconds(5))
        }
        return SG6AcceptanceProbe.events(after: sequence).first(where: {
            predicate($0.kind)
        })
    }

    private func waitForCueRun(
        after sequence: Int,
        timeout: TimeInterval
    ) async -> SensoryCueRun? {
        let deadline = ProcessInfo.processInfo.systemUptime + timeout
        while ProcessInfo.processInfo.systemUptime < deadline {
            let events = SG6AcceptanceProbe.events(after: sequence)
            let evaluation = SG8SensoryCueEvaluation(events: events)
            if evaluation.cueOrder.count >= 4,
               evaluation.visibleDurationsMilliseconds.count >= 4 {
                return SensoryCueRun(
                    evaluation: evaluation,
                    lastSequence: events.last?.sequence ?? sequence
                )
            }
            try? await Task.sleep(for: .milliseconds(5))
        }
        return nil
    }

    private func waitForAudioContext(
        _ context: GameAudioContext,
        director: GameAudioDirector,
        timeout: TimeInterval = 2
    ) async -> Bool {
        await waitUntil(timeout: timeout) {
            director.desiredContext == context
        }
    }

    private func waitUntil(
        timeout: TimeInterval,
        condition: () -> Bool
    ) async -> Bool {
        let deadline = ProcessInfo.processInfo.systemUptime + timeout
        while ProcessInfo.processInfo.systemUptime < deadline {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(5))
        }
        return condition()
    }

    private func waitUntilRacing(
        _ controller: GameSessionController,
        timeout: TimeInterval
    ) async -> TimeInterval? {
        let deadline = ProcessInfo.processInfo.systemUptime + timeout
        while ProcessInfo.processInfo.systemUptime < deadline {
            guard flow.route == .playing, flow.gameSession === controller else {
                return nil
            }
            if controller.presentationPhase == .racing {
                return ProcessInfo.processInfo.systemUptime
            }
            try? await Task.sleep(for: .milliseconds(5))
        }
        return nil
    }

    private func steerIntoCollision(
        _ controller: GameSessionController,
        timeout: TimeInterval
    ) async -> Bool {
        let deadline = ProcessInfo.processInfo.systemUptime + timeout
        while ProcessInfo.processInfo.systemUptime < deadline {
            guard flow.route == .playing, flow.gameSession === controller else {
                return false
            }
            if case .result = controller.presentationPhase {
                controller.releaseTouch()
                return true
            }
            guard controller.presentationPhase == .racing else {
                try? await Task.sleep(for: .milliseconds(20))
                continue
            }
            let snapshot = controller.scene.currentSnapshot
            if let target = snapshot.obstacles
                .filter({ $0.distance >= -1 })
                .min(by: { $0.distance < $1.distance }) {
                steer(controller, toward: target.x, from: snapshot.playerX)
            } else {
                steer(controller, toward: 0, from: snapshot.playerX)
            }
            try? await Task.sleep(for: .milliseconds(50))
        }
        controller.releaseTouch()
        return false
    }

    private func steerUntilCollision(
        _ controller: GameSessionController,
        timeout: TimeInterval,
        startingWith initialAudit: SensoryPoolAudit
    ) async -> SensoryPoolAudit? {
        var audit = initialAudit
        let deadline = ProcessInfo.processInfo.systemUptime + timeout
        while ProcessInfo.processInfo.systemUptime < deadline {
            guard flow.route == .playing, flow.gameSession === controller else {
                return nil
            }
            audit.observe(controller.scene.presentationDiagnostics)
            switch controller.presentationPhase {
            case .collision:
                return audit
            case .result:
                return nil
            case .racing:
                let snapshot = controller.scene.currentSnapshot
                if let target = snapshot.obstacles
                    .filter({ $0.distance >= -1 })
                    .min(by: { $0.distance < $1.distance }) {
                    steer(controller, toward: target.x, from: snapshot.playerX)
                } else {
                    steer(controller, toward: 0, from: snapshot.playerX)
                }
            case .countdown:
                break
            }
            try? await Task.sleep(for: .milliseconds(20))
        }
        return nil
    }

    private func steerForNearMissPresentation(
        _ controller: GameSessionController,
        timeout: TimeInterval,
        startingWith initialAudit: SensoryPoolAudit
    ) async -> SensoryNearMissAudit? {
        var result = SensoryNearMissAudit(poolAudit: initialAudit)
        var feedbackIndex = controller.scene.presentedFeedback.count
        var targetObstacleID: UInt64?
        var targetSide: FeedbackSide?
        let deadline = ProcessInfo.processInfo.systemUptime + timeout

        while ProcessInfo.processInfo.systemUptime < deadline {
            guard flow.route == .playing,
                  flow.gameSession === controller,
                  controller.presentationPhase == .racing else {
                return nil
            }

            let diagnostics = controller.scene.presentationDiagnostics
            result.poolAudit.observe(diagnostics)
            if let side = diagnostics.visibleNearMissSide,
               side == .left || side == .right,
               !result.visibleSides.contains(side) {
                result.visibleSides.append(side)
            }

            let feedback = controller.scene.presentedFeedback
            if feedbackIndex < feedback.count {
                for item in feedback[feedbackIndex...] {
                    guard case .nearMiss = item.kind,
                          let side = item.spatialContext?.side,
                          side == .left || side == .right else {
                        continue
                    }
                    if !result.eventSides.contains(side) {
                        result.eventSides.append(side)
                    }
                    targetObstacleID = nil
                    targetSide = nil
                }
                feedbackIndex = feedback.count
            }
            if result.hasBothSides {
                controller.releaseTouch()
                return result
            }

            let desiredSide: FeedbackSide = result.eventSides.contains(.left) ? .right : .left
            let snapshot = controller.scene.currentSnapshot
            if targetSide != desiredSide
                || snapshot.obstacles.first(where: { $0.id == targetObstacleID }) == nil {
                targetObstacleID = nil
                targetSide = nil
            }

            if let currentTargetID = targetObstacleID,
               let target = snapshot.obstacles.first(where: { $0.id == currentTargetID }),
               snapshot.obstacles.contains(where: {
                   $0.id != target.id
                       && $0.distance > -2
                       && $0.distance < target.distance
               }) {
                self.steerSafely(controller)
                targetObstacleID = nil
                targetSide = nil
                try? await Task.sleep(for: .milliseconds(20))
                continue
            }

            if targetObstacleID == nil {
                let configuration = controller.scene.configuration
                let playerLimit = snapshot.roadHalfWidth - snapshot.playerWidth / 2
                if let candidate = snapshot.obstacles
                    .filter({ $0.distance > -2 })
                    .min(by: { $0.distance < $1.distance }),
                   !candidate.didAwardNearMiss,
                   candidate.distance > 12,
                   abs(
                       nearMissTargetX(
                           obstacle: candidate,
                           side: desiredSide,
                           snapshot: snapshot,
                           margin: configuration.nearMissMargin
                       )
                   ) <= playerLimit {
                    targetObstacleID = candidate.id
                    targetSide = desiredSide
                }
            }

            if let targetObstacleID,
               let targetSide,
               let obstacle = snapshot.obstacles.first(where: { $0.id == targetObstacleID }) {
                steer(
                    controller,
                    toward: nearMissTargetX(
                        obstacle: obstacle,
                        side: targetSide,
                        snapshot: snapshot,
                        margin: controller.scene.configuration.nearMissMargin
                    ),
                    from: snapshot.playerX
                )
            } else {
                steerSafely(controller)
            }
            try? await Task.sleep(for: .milliseconds(20))
        }
        controller.releaseTouch()
        return nil
    }

    private func nearMissTargetX(
        obstacle: ObstacleSnapshot,
        side: FeedbackSide,
        snapshot: GameSnapshot,
        margin: Double
    ) -> Double {
        let separation = (obstacle.width + snapshot.playerWidth) / 2 + margin / 2
        switch side {
        case .left:
            return obstacle.x + separation
        case .right:
            return obstacle.x - separation
        case .center:
            return obstacle.x
        }
    }

    private func steerSafely(_ controller: GameSessionController) {
        let snapshot = controller.scene.currentSnapshot
        let upcoming = snapshot.obstacles.filter { $0.distance > -2 && $0.distance < 24 }
        guard !upcoming.isEmpty else {
            steer(controller, toward: 0, from: snapshot.playerX)
            return
        }
        let targetLaneIndex = [0, 1, 2].max { leftLane, rightLane in
            let leftClearance = upcoming
                .filter { $0.laneIndex == leftLane }
                .map(\.distance)
                .min() ?? .greatestFiniteMagnitude
            let rightClearance = upcoming
                .filter { $0.laneIndex == rightLane }
                .map(\.distance)
                .min() ?? .greatestFiniteMagnitude
            if leftClearance != rightClearance {
                return leftClearance < rightClearance
            }
            let leftX = Double(leftLane - 1) * snapshot.laneWidth
            let rightX = Double(rightLane - 1) * snapshot.laneWidth
            return abs(leftX - snapshot.playerX) > abs(rightX - snapshot.playerX)
        } ?? 1
        steer(
            controller,
            toward: Double(targetLaneIndex - 1) * snapshot.laneWidth,
            from: snapshot.playerX
        )
    }

    private func steer(
        _ controller: GameSessionController,
        toward targetX: Double,
        from currentX: Double
    ) {
        let steering = min(max((targetX - currentX) / 0.8, -1), 1)
        controller.updateTouch(horizontalPosition: (steering + 1) * 500, width: 1_000)
    }

    private func residentMemoryBytes() -> UInt64? {
        var info = mach_task_basic_info_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<mach_task_basic_info_data_t>.size / MemoryLayout<natural_t>.size
        )
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(
                    mach_task_self_,
                    task_flavor_t(MACH_TASK_BASIC_INFO),
                    $0,
                    &count
                )
            }
        }
        guard result == KERN_SUCCESS else {
            return nil
        }
        return UInt64(info.resident_size)
    }

    private func stabilizedResidentMemoryBytes() -> UInt64? {
        _ = malloc_zone_pressure_relief(nil, 0)
        return residentMemoryBytes()
    }

    private static func maximumConsecutiveSamples(
        below threshold: Double,
        in samples: [Double]
    ) -> Int {
        var current = 0
        var maximum = 0
        for sample in samples {
            if sample < threshold {
                current += 1
                maximum = max(maximum, current)
            } else {
                current = 0
            }
        }
        return maximum
    }

    private func emitSummary(pass: Bool, reason: String) {
        log("\(mode.summaryPrefix) pass=\(pass) reason=\(reason)")
    }

    private func presentationFailure(_ reason: String) -> String {
        "SG6_PRESENTATION_SUMMARY pass=false reason=\(reason)"
    }

    private func fpsFailure(_ reason: String) -> String {
        "SG6_FPS_SUMMARY pass=false reason=\(reason)"
    }

    private func memoryFailure(_ reason: String) -> String {
        "SG6_MEMORY_SUMMARY pass=false reason=\(reason)"
    }

    private func sensoryFailure(_ reason: String) -> String {
        "SG8_SENSORY_SUMMARY pass=false reason=\(reason)"
    }

    private func log(_ message: String) {
        logger.notice("\(message, privacy: .public)")
    }

    private func milliseconds(_ seconds: TimeInterval) -> Double {
        seconds * 1_000
    }

    private func serialized(_ values: [Double]) -> String {
        values.map(formatted).joined(separator: ",")
    }

    private func serializedCueOrder(_ values: [StartCueKind]) -> String {
        values.map { value in
            switch value {
            case .three: "3"
            case .two: "2"
            case .one: "1"
            case .go: "GO"
            }
        }.joined(separator: ",")
    }

    private func serializedSides(_ values: [FeedbackSide]) -> String {
        values.map { side in
            switch side {
            case .left: "left"
            case .center: "center"
            case .right: "right"
            }
        }.joined(separator: ",")
    }

    private func formatted(_ value: Double?) -> String {
        guard let value else { return "none" }
        return String(format: "%.3f", locale: Locale(identifier: "en_US_POSIX"), value)
    }
}
#endif
