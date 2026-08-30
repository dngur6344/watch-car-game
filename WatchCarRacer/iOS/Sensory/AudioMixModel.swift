import Foundation

struct AudioMixSnapshot: Equatable, Sendable {
    static let silent = AudioMixSnapshot(
        idleGain: 0,
        midGain: 0,
        highGain: 0,
        idleRate: 1,
        midRate: 1,
        highRate: 1,
        roadGain: 0,
        windGain: 0,
        tireScrubGain: 0
    )

    let idleGain: Double
    let midGain: Double
    let highGain: Double
    let idleRate: Double
    let midRate: Double
    let highRate: Double
    let roadGain: Double
    let windGain: Double
    let tireScrubGain: Double

    var engineEnergy: Double {
        idleGain * idleGain + midGain * midGain + highGain * highGain
    }

    var allValues: [Double] {
        [
            idleGain,
            midGain,
            highGain,
            idleRate,
            midRate,
            highRate,
            roadGain,
            windGain,
            tireScrubGain,
        ]
    }
}

struct DirectionalAudioMix: Equatable, Sendable {
    let pan: Double
    let leftGain: Double
    let rightGain: Double
}

struct AudioMixModel: Equatable, Sendable {
    static let engineGain = 0.46
    static let steeringDeadZone = 0.12

    private(set) var current = AudioMixSnapshot.silent

    mutating func reset() {
        current = .silent
    }

    mutating func update(
        speed: Double,
        initialSpeed: Double,
        maximumSpeed: Double,
        steering: Double,
        deltaTime: TimeInterval
    ) -> AudioMixSnapshot {
        let target = Self.target(
            speed: speed,
            initialSpeed: initialSpeed,
            maximumSpeed: maximumSpeed,
            steering: steering
        )
        let safeDeltaTime = Self.clampFinite(deltaTime, lower: 0, upper: 0.25, fallback: 0)
        let smoothing = 1 - exp(-8 * safeDeltaTime)

        current = AudioMixSnapshot(
            idleGain: Self.interpolate(current.idleGain, target.idleGain, smoothing),
            midGain: Self.interpolate(current.midGain, target.midGain, smoothing),
            highGain: Self.interpolate(current.highGain, target.highGain, smoothing),
            idleRate: Self.interpolate(current.idleRate, target.idleRate, smoothing),
            midRate: Self.interpolate(current.midRate, target.midRate, smoothing),
            highRate: Self.interpolate(current.highRate, target.highRate, smoothing),
            roadGain: Self.interpolate(current.roadGain, target.roadGain, smoothing),
            windGain: Self.interpolate(current.windGain, target.windGain, smoothing),
            tireScrubGain: Self.interpolate(
                current.tireScrubGain,
                target.tireScrubGain,
                smoothing
            )
        )
        return current
    }

    static func target(
        speed: Double,
        initialSpeed: Double,
        maximumSpeed: Double,
        steering: Double
    ) -> AudioMixSnapshot {
        let lowerSpeed = finiteOrZero(initialSpeed)
        let upperSpeed = max(finiteOrZero(maximumSpeed), lowerSpeed + 0.001)
        let safeSpeed = clampFinite(speed, lower: lowerSpeed, upper: upperSpeed, fallback: lowerSpeed)
        let progress = (safeSpeed - lowerSpeed) / (upperSpeed - lowerSpeed)

        let idleWeight: Double
        let midWeight: Double
        let highWeight: Double
        if progress <= 0.5 {
            let phase = progress * 2 * .pi / 2
            idleWeight = cos(phase)
            midWeight = sin(phase)
            highWeight = 0
        } else {
            let phase = (progress - 0.5) * 2 * .pi / 2
            idleWeight = 0
            midWeight = cos(phase)
            highWeight = sin(phase)
        }

        let safeSteering = abs(clampFinite(steering, lower: -1, upper: 1, fallback: 0))
        let scrubProgress = max(
            0,
            (safeSteering - steeringDeadZone) / (1 - steeringDeadZone)
        )
        let speedContribution = 0.35 + 0.65 * progress

        return AudioMixSnapshot(
            idleGain: clampFinite(idleWeight * engineGain, lower: 0, upper: engineGain, fallback: 0),
            midGain: clampFinite(midWeight * engineGain, lower: 0, upper: engineGain, fallback: 0),
            highGain: clampFinite(highWeight * engineGain, lower: 0, upper: engineGain, fallback: 0),
            idleRate: clampFinite(0.92 + 0.18 * progress, lower: 0.75, upper: 1.35, fallback: 1),
            midRate: clampFinite(0.88 + 0.30 * progress, lower: 0.75, upper: 1.35, fallback: 1),
            highRate: clampFinite(0.90 + 0.38 * progress, lower: 0.75, upper: 1.35, fallback: 1),
            roadGain: clampFinite(0.08 + 0.30 * progress, lower: 0, upper: 0.38, fallback: 0),
            windGain: clampFinite(max(0, (progress - 0.12) / 0.88) * 0.34, lower: 0, upper: 0.34, fallback: 0),
            tireScrubGain: clampFinite(scrubProgress * speedContribution * 0.32, lower: 0, upper: 0.32, fallback: 0)
        )
    }

    static func directionalMix(pan: Double, gain: Double) -> DirectionalAudioMix {
        let safePan = clampFinite(pan, lower: -0.75, upper: 0.75, fallback: 0)
        let safeGain = clampFinite(gain, lower: 0, upper: 1, fallback: 0)
        let normalizedPan = safePan / 0.75
        return DirectionalAudioMix(
            pan: safePan,
            leftGain: safeGain * sqrt((1 - normalizedPan) / 2),
            rightGain: safeGain * sqrt((1 + normalizedPan) / 2)
        )
    }

    private static func finiteOrZero(_ value: Double) -> Double {
        value.isFinite ? value : 0
    }

    private static func interpolate(_ start: Double, _ end: Double, _ progress: Double) -> Double {
        start + (end - start) * progress
    }

    private static func clampFinite(
        _ value: Double,
        lower: Double,
        upper: Double,
        fallback: Double
    ) -> Double {
        guard value.isFinite else { return fallback }
        return min(max(value, lower), upper)
    }
}
