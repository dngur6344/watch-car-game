import CoreMotion
import Foundation
import Observation

struct MotionAttitudeSample: Equatable, Sendable {
    let roll: Double
    let pitch: Double
    let yaw: Double
    let timestamp: TimeInterval
}

struct MotionSteeringProjection: Equatable, Sendable {
    enum Axis: Equatable, Sendable {
        case roll
        case pitch
        case yaw
    }

    var axis: Axis
    var direction: Double

    static let provisionalRightPositiveRoll = MotionSteeringProjection(axis: .roll, direction: 1)

    func angle(from sample: MotionAttitudeSample) -> Double {
        let component = switch axis {
        case .roll: sample.roll
        case .pitch: sample.pitch
        case .yaw: sample.yaw
        }
        return component * direction
    }
}

struct MotionSteeringConfiguration: Equatable, Sendable {
    var projection: MotionSteeringProjection = .provisionalRightPositiveRoll
    var deadZoneRadians: Double = 3 * .pi / 180
    var fullLockRadians: Double = 30 * .pi / 180
    var filterTimeConstant: TimeInterval = 0.05
}

struct MotionSteeringCore: Sendable {
    let configuration: MotionSteeringConfiguration

    private(set) var neutralAngle: Double?
    private(set) var latestSample: MotionAttitudeSample?
    private(set) var filteredValue = 0.0
    private var lastTimestamp: TimeInterval?

    init(configuration: MotionSteeringConfiguration = MotionSteeringConfiguration()) {
        self.configuration = configuration
    }

    var isCalibrated: Bool {
        neutralAngle != nil
    }

    mutating func ingest(_ sample: MotionAttitudeSample) -> Double? {
        let angle = configuration.projection.angle(from: sample)
        guard angle.isFinite, sample.timestamp.isFinite else {
            resetCalibration()
            return nil
        }

        latestSample = sample
        guard let neutralAngle else {
            return nil
        }

        let target = Self.normalizedTarget(
            relativeAngle: Self.wrappedAngle(angle - neutralAngle),
            deadZone: configuration.deadZoneRadians,
            fullLock: configuration.fullLockRadians
        )

        guard let lastTimestamp else {
            filteredValue = target
            self.lastTimestamp = sample.timestamp
            return filteredValue
        }

        let elapsed = max(0, sample.timestamp - lastTimestamp)
        let timeConstant = max(configuration.filterTimeConstant, .leastNonzeroMagnitude)
        let alpha = 1 - exp(-elapsed / timeConstant)
        filteredValue += alpha * (target - filteredValue)
        filteredValue = min(max(filteredValue, -1), 1)
        self.lastTimestamp = sample.timestamp
        return filteredValue
    }

    mutating func calibrateUsingLatestSample() -> Bool {
        guard let latestSample else {
            return false
        }
        let angle = configuration.projection.angle(from: latestSample)
        guard angle.isFinite, latestSample.timestamp.isFinite else {
            resetCalibration()
            return false
        }

        neutralAngle = angle
        filteredValue = 0
        lastTimestamp = latestSample.timestamp
        return true
    }

    mutating func resetCalibration() {
        neutralAngle = nil
        latestSample = nil
        filteredValue = 0
        lastTimestamp = nil
    }

    static func wrappedAngle(_ angle: Double) -> Double {
        guard angle.isFinite else {
            return 0
        }
        var wrapped = angle.truncatingRemainder(dividingBy: 2 * .pi)
        if wrapped > .pi {
            wrapped -= 2 * .pi
        } else if wrapped < -.pi {
            wrapped += 2 * .pi
        }
        return wrapped
    }

    static func normalizedTarget(relativeAngle: Double, deadZone: Double, fullLock: Double) -> Double {
        guard relativeAngle.isFinite, deadZone.isFinite, fullLock.isFinite, fullLock > deadZone else {
            return 0
        }
        let magnitude = abs(relativeAngle)
        guard magnitude > max(0, deadZone) else {
            return 0
        }
        let normalized = min((magnitude - max(0, deadZone)) / (fullLock - max(0, deadZone)), 1)
        return relativeAngle.sign == .minus ? -normalized : normalized
    }
}

@MainActor
protocol MotionSampling: AnyObject {
    var isDeviceMotionAvailable: Bool { get }

    func startDeviceMotionUpdates(
        interval: TimeInterval,
        handler: @escaping @MainActor @Sendable (MotionAttitudeSample) -> Void
    )

    func stopDeviceMotionUpdates()
}

@MainActor
final class CoreMotionSampler: MotionSampling {
    private let manager = CMMotionManager()

    var isDeviceMotionAvailable: Bool {
        manager.isDeviceMotionAvailable
    }

    func startDeviceMotionUpdates(
        interval: TimeInterval,
        handler: @escaping @MainActor @Sendable (MotionAttitudeSample) -> Void
    ) {
        manager.deviceMotionUpdateInterval = interval
        manager.startDeviceMotionUpdates(to: .main) { motion, _ in
            guard let motion else {
                return
            }
            let sample = MotionAttitudeSample(
                roll: motion.attitude.roll,
                pitch: motion.attitude.pitch,
                yaw: motion.attitude.yaw,
                timestamp: motion.timestamp
            )
            Task { @MainActor in
                handler(sample)
            }
        }
    }

    func stopDeviceMotionUpdates() {
        manager.stopDeviceMotionUpdates()
    }
}

@MainActor
@Observable
final class MotionSteeringEngine {
    private(set) var isMotionAvailable = false
    private(set) var isRunning = false
    private(set) var isCalibrated = false
    private(set) var latestValue = 0.0

    @ObservationIgnored private let sampler: any MotionSampling
    @ObservationIgnored private var core: MotionSteeringCore

#if DEBUG && targetEnvironment(simulator)
    private(set) var isUsingSyntheticInput = false
#endif

    init(
        sampler: any MotionSampling = CoreMotionSampler(),
        configuration: MotionSteeringConfiguration = MotionSteeringConfiguration()
    ) {
        self.sampler = sampler
        core = MotionSteeringCore(configuration: configuration)
    }

    var state: SteeringState {
#if DEBUG && targetEnvironment(simulator)
        if isUsingSyntheticInput {
            return .active
        }
#endif
        if !isMotionAvailable {
            return .motionUnavailable
        }
        return isCalibrated ? .active : .needsCalibration
    }

    func start() {
        guard !isRunning else {
            return
        }
        isMotionAvailable = sampler.isDeviceMotionAvailable
        guard isMotionAvailable else {
            return
        }

        isRunning = true
        sampler.startDeviceMotionUpdates(interval: 1.0 / 50.0) { [weak self] sample in
            self?.receive(sample)
        }
    }

    func calibrateNeutral() -> Bool {
        guard isRunning, isMotionAvailable, core.calibrateUsingLatestSample() else {
            return false
        }
        isCalibrated = true
        latestValue = 0
        return true
    }

    func stopAndInvalidateCalibration() {
        sampler.stopDeviceMotionUpdates()
        core.resetCalibration()
        isRunning = false
        isCalibrated = false
        latestValue = 0
#if DEBUG && targetEnvironment(simulator)
        isUsingSyntheticInput = false
#endif
    }

    private func receive(_ sample: MotionAttitudeSample) {
        let value = core.ingest(sample)
        isCalibrated = core.isCalibrated
        if let value {
            latestValue = value
        }
    }

#if DEBUG && targetEnvironment(simulator)
    func setSyntheticSteering(_ value: Double) {
        guard value.isFinite else {
            return
        }
        isUsingSyntheticInput = true
        isCalibrated = true
        latestValue = min(max(value, -1), 1)
    }
#endif
}
