import Foundation
import OSLog

enum RacingEnvironmentThermalState: CaseIterable, Equatable, Sendable {
    case nominal
    case fair
    case serious
    case critical
    case unknown
}

enum RacingEnvironmentExecutionEnvironment: Equatable, Sendable {
    case physicalDevice
    case simulator
    case unknown
}

enum RacingEnvironmentBuildConfiguration: Equatable, Sendable {
    case debug
    case release
}

struct RacingEnvironmentQualityInput: Sendable {
    let physicalMemory: UInt64
    let isLowPowerModeEnabled: Bool
    let thermalState: RacingEnvironmentThermalState
    let executionEnvironment: RacingEnvironmentExecutionEnvironment
    let buildConfiguration: RacingEnvironmentBuildConfiguration
    let launchArguments: [String]
}

enum RacingEnvironmentInitialQualitySelector {
    static let forceArgumentPrefix = "--watch-car-racer-environment-quality="
    static let enhancedMemoryThreshold: UInt64 = 8 * 1_024 * 1_024 * 1_024

    static func tier(for input: RacingEnvironmentQualityInput) -> RacingEnvironmentQualityTier {
        if input.buildConfiguration == .debug,
           let forcedValue = input.launchArguments.last(where: {
               $0.hasPrefix(forceArgumentPrefix)
           })?.dropFirst(forceArgumentPrefix.count),
           let forcedTier = RacingEnvironmentQualityTier(rawValue: String(forcedValue)) {
            return forcedTier
        }

        guard input.executionEnvironment == .physicalDevice,
              !input.isLowPowerModeEnabled,
              input.physicalMemory >= enhancedMemoryThreshold else {
            return .baseline
        }

        switch input.thermalState {
        case .nominal, .fair:
            return .enhanced
        case .serious, .critical, .unknown:
            return .baseline
        }
    }
}

enum RacingEnvironmentQualityDowngradeReason: String, Equatable, Sendable {
    case sustainedLowFrameRate = "sustained-low-frame-rate"
    case thermalSerious = "thermal-serious"
    case thermalCritical = "thermal-critical"
    case memoryWarning = "memory-warning"
}

struct RacingEnvironmentQualityTransition: Equatable, Sendable {
    let fromTier: RacingEnvironmentQualityTier
    let toTier: RacingEnvironmentQualityTier
    let reason: RacingEnvironmentQualityDowngradeReason
    let acceptedFrameRateSampleCount: Int
    let consecutiveLowFrameRateSampleCount: Int
    let lastAcceptedAverageFramesPerSecond: Double?
    let timestamp: TimeInterval?
}

struct RacingEnvironmentAdaptiveQualityState: Equatable, Sendable {
    static let racingWarmUpDuration: TimeInterval = 5
    static let frameRateSampleInterval: TimeInterval = 1
    static let frameRateThreshold = 50.0
    static let requiredConsecutiveLowFrameRateSamples = 3

    private(set) var initialTier: RacingEnvironmentQualityTier
    private(set) var effectiveTier: RacingEnvironmentQualityTier
    private(set) var racingStartedAt: TimeInterval?
    private(set) var lastAcceptedFrameRateSampleTimestamp: TimeInterval?
    private(set) var acceptedFrameRateSampleCount = 0
    private(set) var consecutiveLowFrameRateSampleCount = 0
    private(set) var lastAcceptedAverageFramesPerSecond: Double?
    private(set) var transition: RacingEnvironmentQualityTransition?

    init(initialTier: RacingEnvironmentQualityTier) {
        self.initialTier = initialTier
        effectiveTier = initialTier
    }

    mutating func beginRacing(at timestamp: TimeInterval) {
        guard timestamp.isFinite, timestamp >= 0, racingStartedAt == nil else { return }
        racingStartedAt = timestamp
    }

    @discardableResult
    mutating func receiveFrameRateSample(
        _ averageFramesPerSecond: Double,
        at timestamp: TimeInterval
    ) -> RacingEnvironmentQualityTransition? {
        guard effectiveTier == .enhanced,
              transition == nil,
              averageFramesPerSecond.isFinite,
              averageFramesPerSecond > 0,
              timestamp.isFinite,
              timestamp >= 0,
              let racingStartedAt,
              timestamp >= racingStartedAt,
              timestamp - racingStartedAt >= Self.racingWarmUpDuration else {
            return nil
        }
        if let lastAcceptedFrameRateSampleTimestamp {
            guard timestamp > lastAcceptedFrameRateSampleTimestamp,
                  timestamp - lastAcceptedFrameRateSampleTimestamp
                    >= Self.frameRateSampleInterval else {
                return nil
            }
        }

        lastAcceptedFrameRateSampleTimestamp = timestamp
        acceptedFrameRateSampleCount += 1
        lastAcceptedAverageFramesPerSecond = averageFramesPerSecond
        if averageFramesPerSecond < Self.frameRateThreshold {
            consecutiveLowFrameRateSampleCount += 1
        } else {
            consecutiveLowFrameRateSampleCount = 0
        }

        guard consecutiveLowFrameRateSampleCount
                == Self.requiredConsecutiveLowFrameRateSamples else {
            return nil
        }
        return downgrade(reason: .sustainedLowFrameRate, timestamp: timestamp)
    }

    @discardableResult
    mutating func receiveThermalState(
        _ state: RacingEnvironmentThermalState,
        at timestamp: TimeInterval? = nil
    ) -> RacingEnvironmentQualityTransition? {
        switch state {
        case .serious:
            return downgrade(reason: .thermalSerious, timestamp: timestamp)
        case .critical:
            return downgrade(reason: .thermalCritical, timestamp: timestamp)
        case .nominal, .fair, .unknown:
            return nil
        }
    }

    @discardableResult
    mutating func receiveMemoryWarning(
        at timestamp: TimeInterval? = nil
    ) -> RacingEnvironmentQualityTransition? {
        downgrade(reason: .memoryWarning, timestamp: timestamp)
    }

    mutating func reset(initialTier: RacingEnvironmentQualityTier) {
        self = RacingEnvironmentAdaptiveQualityState(initialTier: initialTier)
    }

    private mutating func downgrade(
        reason: RacingEnvironmentQualityDowngradeReason,
        timestamp: TimeInterval?
    ) -> RacingEnvironmentQualityTransition? {
        guard effectiveTier == .enhanced, transition == nil else { return nil }
        if let timestamp {
            guard timestamp.isFinite,
                  timestamp >= 0,
                  lastAcceptedFrameRateSampleTimestamp.map({ timestamp >= $0 }) ?? true else {
                return nil
            }
        }
        let record = RacingEnvironmentQualityTransition(
            fromTier: .enhanced,
            toTier: .baseline,
            reason: reason,
            acceptedFrameRateSampleCount: acceptedFrameRateSampleCount,
            consecutiveLowFrameRateSampleCount: consecutiveLowFrameRateSampleCount,
            lastAcceptedAverageFramesPerSecond: lastAcceptedAverageFramesPerSecond,
            timestamp: timestamp
        )
        effectiveTier = .baseline
        transition = record
        return record
    }
}

enum RacingEnvironmentQualityTransitionLogger {
    private static let logger = Logger(
        subsystem: "com.woohyuk.WatchCarRacer",
        category: "RacingEnvironmentQuality"
    )

    static func log(_ transition: RacingEnvironmentQualityTransition) {
        let lastAverage = transition.lastAcceptedAverageFramesPerSecond.map {
            String(format: "%.3f", locale: Locale(identifier: "en_US_POSIX"), $0)
        } ?? "none"
        logger.notice(
            "RACING_ENVIRONMENT_QUALITY_TRANSITION reason=\(transition.reason.rawValue, privacy: .public) samples=\(transition.acceptedFrameRateSampleCount) consecutiveLowFPS=\(transition.consecutiveLowFrameRateSampleCount) lastAverageFPS=\(lastAverage, privacy: .public) from=\(transition.fromTier.rawValue, privacy: .public) to=\(transition.toTier.rawValue, privacy: .public)"
        )
    }
}

enum RacingEnvironmentQualityProductionAdapter {
    static func initialTier(processInfo: ProcessInfo = .processInfo) -> RacingEnvironmentQualityTier {
        RacingEnvironmentInitialQualitySelector.tier(
            for: RacingEnvironmentQualityInput(
                physicalMemory: processInfo.physicalMemory,
                isLowPowerModeEnabled: processInfo.isLowPowerModeEnabled,
                thermalState: thermalState(processInfo.thermalState),
                executionEnvironment: executionEnvironment,
                buildConfiguration: buildConfiguration,
                launchArguments: processInfo.arguments
            )
        )
    }

    static func thermalState(
        _ state: ProcessInfo.ThermalState
    ) -> RacingEnvironmentThermalState {
        switch state {
        case .nominal: .nominal
        case .fair: .fair
        case .serious: .serious
        case .critical: .critical
        @unknown default: .unknown
        }
    }

    private static var executionEnvironment: RacingEnvironmentExecutionEnvironment {
#if targetEnvironment(simulator)
        .simulator
#elseif os(iOS)
        .physicalDevice
#else
        .unknown
#endif
    }

    private static var buildConfiguration: RacingEnvironmentBuildConfiguration {
#if DEBUG
        .debug
#else
        .release
#endif
    }
}
