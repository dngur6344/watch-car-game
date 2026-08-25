#if DEBUG
import Darwin
import Foundation

@MainActor
final class SG6AcceptanceCoordinator {
    private enum Mode: String {
        case fps = "--sg6-fps"
        case memory = "--sg6-memory"
    }

    private let flow: AppFlowController
    private let mode: Mode
    private let startDelay: TimeInterval
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
            do {
                try await Task.sleep(for: .seconds(startDelay))
                print("SG6_ACCEPTANCE_START mode=\(mode.rawValue) delay=\(startDelay)")
                await flow.prepareAssets()
                guard flow.assetReadiness == .ready else {
                    print("SG6_ACCEPTANCE_ERROR mode=\(mode.rawValue) reason=asset_preload_failed")
                    return
                }

                switch mode {
                case .fps:
                    await runFrameRateAcceptance()
                case .memory:
                    await runMemoryAcceptance()
                }
            } catch is CancellationError {
                print("SG6_ACCEPTANCE_ERROR mode=\(mode.rawValue) reason=cancelled")
            } catch {
                print(
                    "SG6_ACCEPTANCE_ERROR mode=\(mode.rawValue) reason=unexpected "
                        + "detail=\(String(reflecting: error))"
                )
            }
        }
    }

    private func runFrameRateAcceptance() async {
        flow.drive()
        guard let controller = flow.gameSession else {
            print("SG6_FPS_SUMMARY pass=false reason=controller_creation_failed")
            return
        }

        let startingSampleIndex = controller.frameRateSamples.count
        let targetSampleCount = 300
        var gameplayRetries = 0
        while controller.frameRateSamples.count - startingSampleIndex < targetSampleCount {
            if controller.phase == .crashed {
                gameplayRetries += 1
                print(
                    "SG6_FPS_GAMEPLAY_COLLISION retry=\(gameplayRetries) "
                        + "sample=\(controller.frameRateSampleCount) score=\(controller.score)"
                )
                controller.retry()
            }
            steerSafely(controller)
            try? await Task.sleep(for: .milliseconds(50))
        }
        if controller.phase == .crashed {
            gameplayRetries += 1
            print(
                "SG6_FPS_GAMEPLAY_COLLISION retry=\(gameplayRetries) "
                    + "sample=\(controller.frameRateSampleCount) score=\(controller.score)"
            )
            controller.retry()
        }
        controller.releaseTouch()

        let samples = Array(
            controller.frameRateSamples
                .dropFirst(startingSampleIndex)
                .prefix(targetSampleCount)
        )
        let average = samples.reduce(0, +) / Double(samples.count)
        let minimum = samples.min() ?? 0
        let maximumConsecutiveBelow50 = Self.maximumConsecutiveSamples(
            below: 50,
            in: samples
        )
        let firstObstacleSample = controller.firstObstacleFrameRateSample
        let passed = samples.count == targetSampleCount
            && average >= 58
            && maximumConsecutiveBelow50 < 2
            && controller.phase == .running

        print(
            "SG6_FPS_SUMMARY pass=\(passed) samples=\(samples.count) "
                + "average=\(formatted(average)) minimum=\(formatted(minimum)) "
                + "maxConsecutiveBelow50=\(maximumConsecutiveBelow50) "
                + "firstObstacleSample=\(formatted(firstObstacleSample)) "
                + "gameplayRetries=\(gameplayRetries) phase=\(controller.phase) "
                + "score=\(controller.score)"
        )
    }

    private func runMemoryAcceptance() async {
        guard await completeCollisionRoute(label: "warmup") else {
            print("SG6_MEMORY_SUMMARY pass=false reason=warmup_failed")
            return
        }

        try? await Task.sleep(for: .seconds(10))
        guard let baseline = residentMemoryBytes() else {
            print("SG6_MEMORY_SUMMARY pass=false reason=baseline_rss_unavailable")
            return
        }
        print("SG6_MEMORY_BASELINE residentBytes=\(baseline) idleSeconds=10")

        var samples: [UInt64] = []
        var releasedControllers = 0
        for cycle in 1...10 {
            guard await completeCollisionRoute(label: "cycle_\(cycle)") else {
                print("SG6_MEMORY_SUMMARY pass=false reason=cycle_failed cycle=\(cycle)")
                return
            }
            if lastRouteControllerWasReleased {
                releasedControllers += 1
            }
            try? await Task.sleep(for: .seconds(5))
            guard let residentBytes = residentMemoryBytes() else {
                print("SG6_MEMORY_SUMMARY pass=false reason=rss_unavailable cycle=\(cycle)")
                return
            }
            samples.append(residentBytes)
            print(
                "SG6_MEMORY_SAMPLE cycle=\(cycle) residentBytes=\(residentBytes) "
                    + "idleSeconds=5 controllerReleased=\(lastRouteControllerWasReleased)"
            )
        }

        try? await Task.sleep(for: .seconds(5))
        guard let finalResidentBytes = residentMemoryBytes() else {
            print("SG6_MEMORY_SUMMARY pass=false reason=final_rss_unavailable")
            return
        }
        let threshold = Double(baseline) * 1.15
        let lastFive = Array(samples.suffix(5))
        let lastFiveStrictlyIncreasing = zip(lastFive, lastFive.dropFirst())
            .allSatisfy { pair in pair.0 < pair.1 }
        let passed = Double(finalResidentBytes) <= threshold
            && !lastFiveStrictlyIncreasing
            && releasedControllers == 10
        let serializedSamples = samples.map(String.init).joined(separator: ",")
        print(
            "SG6_MEMORY_SUMMARY pass=\(passed) baselineBytes=\(baseline) "
                + "samples=\(serializedSamples) finalBytes=\(finalResidentBytes) "
                + "thresholdBytes=\(UInt64(threshold.rounded(.down))) "
                + "lastFiveStrictlyIncreasing=\(lastFiveStrictlyIncreasing) "
                + "releasedControllers=\(releasedControllers)"
        )
    }

    private var lastRouteControllerWasReleased = false

    private func completeCollisionRoute(label: String) async -> Bool {
        flow.drive()
        guard flow.gameSession != nil else {
            print("SG6_MEMORY_ROUTE label=\(label) result=controller_creation_failed")
            return false
        }
        weak let weakController = flow.gameSession
        weak let weakScene = flow.gameSession?.scene
        let controllerID = ObjectIdentifier(flow.gameSession!)
        let collided = await steerIntoCollision(flow.gameSession!, timeout: 15)
        guard collided else {
            flow.gameSession?.releaseTouch()
            print("SG6_MEMORY_ROUTE label=\(label) result=collision_timeout")
            return false
        }

        flow.returnToGarage()
        let releaseDeadline = ProcessInfo.processInfo.systemUptime + 1
        while (weakController != nil || weakScene != nil)
            && ProcessInfo.processInfo.systemUptime < releaseDeadline {
            try? await Task.sleep(for: .milliseconds(10))
        }
        lastRouteControllerWasReleased = weakController == nil && weakScene == nil
        print(
            "SG6_MEMORY_ROUTE label=\(label) result=garage controller=\(controllerID) "
                + "released=\(lastRouteControllerWasReleased)"
        )
        return flow.route == .garage && flow.gameSession == nil
    }

    private func steerIntoCollision(
        _ controller: GameSessionController,
        timeout: TimeInterval
    ) async -> Bool {
        let deadline = ProcessInfo.processInfo.systemUptime + timeout
        while ProcessInfo.processInfo.systemUptime < deadline {
            if controller.phase == .crashed {
                controller.releaseTouch()
                return true
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

    private func formatted(_ value: Double?) -> String {
        guard let value else { return "none" }
        return String(format: "%.3f", locale: Locale(identifier: "en_US_POSIX"), value)
    }
}
#endif
