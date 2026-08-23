import Foundation

enum SteeringInputSource: String, Equatable, Sendable {
    case watch
    case touch
}

enum WatchSteeringAvailability: Equatable, Sendable {
    case active
    case sessionInactive
    case unreachable
    case noPacket
    case stale
    case needsCalibration
    case motionUnavailable
    case awaitingFreshPacket
}

struct WatchSteeringSampleID: Equatable, Hashable, Sendable {
    let streamID: UUID
    let sequence: UInt64
}

struct WatchSteeringReading: Equatable, Sendable {
    let value: Double
    let availability: WatchSteeringAvailability
    let sampleID: WatchSteeringSampleID?

    init(
        value: Double,
        availability: WatchSteeringAvailability,
        sampleID: WatchSteeringSampleID?
    ) {
        self.value = value.isFinite ? min(max(value, -1), 1) : 0
        self.availability = availability
        self.sampleID = sampleID
    }

    static let noPacket = WatchSteeringReading(
        value: 0,
        availability: .noPacket,
        sampleID: nil
    )
}

enum SteeringInputAvailability: Equatable, Sendable {
    case available
    case transitioning
    case fallback(WatchSteeringAvailability)
}

struct SteeringSnapshot: Equatable, Sendable {
    let value: Double
    let source: SteeringInputSource
    let availability: SteeringInputAvailability

    init(
        value: Double,
        source: SteeringInputSource,
        availability: SteeringInputAvailability
    ) {
        self.value = value.isFinite ? min(max(value, -1), 1) : 0
        self.source = source
        self.availability = availability
    }
}

protocol SteeringInputProviding {
    mutating func steeringSnapshot(
        at now: TimeInterval,
        watch: WatchSteeringReading,
        touchValue: Double,
        isTouchDragging: Bool
    ) -> SteeringSnapshot

    mutating func reset(retiring watch: WatchSteeringReading?)
}

@MainActor
protocol WatchSteeringReadingProviding: AnyObject {
    func routingReading(at now: TimeInterval) -> WatchSteeringReading
}

struct SteeringInputRouter: SteeringInputProviding {
    /// Source changes use a short blend while staying below the plan's 150 ms ceiling.
    static let transitionDuration: TimeInterval = 0.125

    private enum Mode: Equatable {
        case undetermined
        case watch
        case touch
        case transitioningToWatch(startTime: TimeInterval, fromValue: Double)
        case fallingBack(
            startTime: TimeInterval,
            fromValue: Double,
            reason: WatchSteeringAvailability
        )
    }

    private var mode: Mode = .undetermined
    private var currentValue = 0.0
    private var lastUpdateTime: TimeInterval?
    private var retiredWatchSampleID: WatchSteeringSampleID?

    mutating func steeringSnapshot(
        at now: TimeInterval,
        watch: WatchSteeringReading,
        touchValue: Double,
        isTouchDragging: Bool
    ) -> SteeringSnapshot {
        let time = monotonicTime(for: now)
        let touch = normalized(touchValue)
        let watchAvailability = effectiveAvailability(for: watch)

        if watch.availability != .active, let sampleID = watch.sampleID {
            retiredWatchSampleID = sampleID
        }

        // A drag is an explicit local takeover, so it responds immediately and remains sticky.
        if isTouchDragging {
            mode = .touch
            currentValue = touch
            return touchSnapshot(value: touch, watchAvailability: watchAvailability)
        }

        switch mode {
        case .undetermined:
            if watchAvailability == .active {
                mode = .watch
                currentValue = watch.value
                return SteeringSnapshot(value: watch.value, source: .watch, availability: .available)
            }
            mode = .touch
            currentValue = touch
            return fallbackSnapshot(value: touch, reason: watchAvailability)

        case .watch:
            if watchAvailability == .active {
                currentValue = watch.value
                return SteeringSnapshot(value: watch.value, source: .watch, availability: .available)
            }
            mode = .fallingBack(
                startTime: time,
                fromValue: currentValue,
                reason: watchAvailability
            )
            return fallbackSnapshot(value: currentValue, reason: watchAvailability)

        case .touch:
            guard watchAvailability == .active else {
                currentValue = touch
                return fallbackSnapshot(value: touch, reason: watchAvailability)
            }
            mode = .transitioningToWatch(startTime: time, fromValue: currentValue)
            return SteeringSnapshot(
                value: currentValue,
                source: .watch,
                availability: .transitioning
            )

        case let .transitioningToWatch(startTime, fromValue):
            guard watchAvailability == .active else {
                mode = .fallingBack(
                    startTime: time,
                    fromValue: currentValue,
                    reason: watchAvailability
                )
                return fallbackSnapshot(value: currentValue, reason: watchAvailability)
            }

            let progress = transitionProgress(from: startTime, to: time)
            currentValue = interpolated(from: fromValue, to: watch.value, progress: progress)
            if progress >= 1 {
                mode = .watch
                currentValue = watch.value
                return SteeringSnapshot(value: watch.value, source: .watch, availability: .available)
            }
            return SteeringSnapshot(
                value: currentValue,
                source: .watch,
                availability: .transitioning
            )

        case let .fallingBack(startTime, fromValue, reason):
            // Finish the loss transition before considering a new Watch sample. This prevents
            // rapid reachability changes from reversing the steering direction mid-blend.
            let progress = transitionProgress(from: startTime, to: time)
            currentValue = interpolated(from: fromValue, to: touch, progress: progress)
            if progress >= 1 {
                mode = .touch
                currentValue = touch
            }
            return fallbackSnapshot(value: currentValue, reason: reason)
        }
    }

    mutating func reset(retiring watch: WatchSteeringReading? = nil) {
        mode = .undetermined
        currentValue = 0
        lastUpdateTime = nil
        retiredWatchSampleID = watch?.sampleID
    }

    private mutating func monotonicTime(for proposedTime: TimeInterval) -> TimeInterval {
        let time: TimeInterval
        if proposedTime.isFinite {
            time = max(proposedTime, lastUpdateTime ?? proposedTime)
        } else {
            time = lastUpdateTime ?? 0
        }
        lastUpdateTime = time
        return time
    }

    private func effectiveAvailability(
        for watch: WatchSteeringReading
    ) -> WatchSteeringAvailability {
        guard watch.availability == .active else {
            return watch.availability
        }
        guard watch.sampleID != retiredWatchSampleID else {
            return .awaitingFreshPacket
        }
        return .active
    }

    private func touchSnapshot(
        value: Double,
        watchAvailability: WatchSteeringAvailability
    ) -> SteeringSnapshot {
        let availability: SteeringInputAvailability = watchAvailability == .active
            ? .available
            : .fallback(watchAvailability)
        return SteeringSnapshot(value: value, source: .touch, availability: availability)
    }

    private func fallbackSnapshot(
        value: Double,
        reason: WatchSteeringAvailability
    ) -> SteeringSnapshot {
        SteeringSnapshot(value: value, source: .touch, availability: .fallback(reason))
    }

    private func transitionProgress(
        from startTime: TimeInterval,
        to currentTime: TimeInterval
    ) -> Double {
        let elapsed = max(currentTime - startTime, 0)
        if elapsed >= Self.transitionDuration
            || Self.transitionDuration - elapsed <= 1e-12 {
            return 1
        }
        return elapsed / Self.transitionDuration
    }

    private func interpolated(from: Double, to: Double, progress: Double) -> Double {
        from + (to - from) * progress
    }

    private func normalized(_ value: Double) -> Double {
        value.isFinite ? min(max(value, -1), 1) : 0
    }
}
