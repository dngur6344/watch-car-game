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
        guard arguments.contains("--sg6-presentation"), appStartTimestamp == nil else {
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

    static func event(matching kind: EventKind, after sequence: Int) -> Event? {
        events.first { $0.sequence > sequence && $0.kind == kind }
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

@MainActor
final class SG6AcceptanceCoordinator {
    private enum Mode: String {
        case presentation = "--sg6-presentation"
        case fps = "--sg6-fps"
        case memory = "--sg6-memory"

        var summaryPrefix: String {
            switch self {
            case .presentation: "SG6_PRESENTATION_SUMMARY"
            case .fps: "SG6_FPS_SUMMARY"
            case .memory: "SG6_MEMORY_SUMMARY"
            }
        }
    }

    private let flow: AppFlowController
    private let mode: Mode
    private let startDelay: TimeInterval
    private let logger = Logger(
        subsystem: "com.woohyuk.WatchCarRacer",
        category: "SG6Acceptance"
    )
    private var task: Task<Void, Never>?

    private init(flow: AppFlowController, mode: Mode, startDelay: TimeInterval) {
        self.flow = flow
        self.mode = mode
        self.startDelay = startDelay
    }

    static func makeIfRequested(
        flow: AppFlowController,
        arguments: [String] = ProcessInfo.processInfo.arguments
    ) -> SG6AcceptanceCoordinator? {
        guard let argument = arguments.first(where: { Mode(rawValue: $0) != nil }),
              let mode = Mode(rawValue: argument) else {
            return nil
        }
        let coordinator = SG6AcceptanceCoordinator(
            flow: flow,
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
            case .countdown:
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

    private func steerSafely(_ controller: GameSessionController) {
        let snapshot = controller.scene.currentSnapshot
        guard let nearest = snapshot.obstacles
            .filter({ $0.distance > -2 && $0.distance < 24 })
            .min(by: { $0.distance < $1.distance }) else {
            steer(controller, toward: 0, from: snapshot.playerX)
            return
        }
        let candidateLaneIndices = [0, 1, 2].filter { $0 != nearest.laneIndex }
        let targetLaneIndex = candidateLaneIndices.min {
            let leftX = Double($0 - 1) * snapshot.laneWidth
            let rightX = Double($1 - 1) * snapshot.laneWidth
            return abs(leftX - snapshot.playerX) < abs(rightX - snapshot.playerX)
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

    private func log(_ message: String) {
        logger.notice("\(message, privacy: .public)")
    }

    private func milliseconds(_ seconds: TimeInterval) -> Double {
        seconds * 1_000
    }

    private func serialized(_ values: [Double]) -> String {
        values.map(formatted).joined(separator: ",")
    }

    private func formatted(_ value: Double?) -> String {
        guard let value else { return "none" }
        return String(format: "%.3f", locale: Locale(identifier: "en_US_POSIX"), value)
    }
}
#endif
