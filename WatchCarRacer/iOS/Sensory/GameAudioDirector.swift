import AVFoundation
import Foundation

enum GameAudioContext: Equatable, Sendable {
    case hub
    case maintenance
    case countdown
    case racing
    case impact
    case result
}

enum GameAudioCue: Equatable, Sendable {
    case nearMiss
    case collision
    case countdownTick
    case go
    case vehicleSelect
    case colorSelect
    case driveTransition

    var role: AudioAssetRole {
        switch self {
        case .nearMiss:
            return .nearMissWhoosh
        case .collision:
            return .collisionImpact
        case .countdownTick:
            return .countdownTick
        case .go:
            return .goBassHit
        case .vehicleSelect:
            return .vehicleSelect
        case .colorSelect:
            return .colorSelect
        case .driveTransition:
            return .driveTransition
        }
    }
}

struct GameAudioBackendDiagnostics: Equatable, Sendable {
    let engineIdentity: ObjectIdentifier
    let longLivedNodeCount: Int
    let nodeAllocationCount: Int
    let maximumSimultaneousOneShots: Int
}

@MainActor
protocol GameAudioBackend: AnyObject {
    var diagnostics: GameAudioBackendDiagnostics { get }

    func prepare(using assets: any AudioAssetProviding) throws
    func activate() throws
    func transition(to context: GameAudioContext) throws
    func apply(_ mix: AudioMixSnapshot) throws
    func play(role: AudioAssetRole, rate: Double, pan: Double, gain: Double) throws
    func stopAllOutput()
    func suspend() throws
    func rebuild() throws
}

struct GameAudioDirectorMetrics: Equatable, Sendable {
    fileprivate(set) var assetPreparationAttempts = 0
    fileprivate(set) var assetPreparationSuccesses = 0
    fileprivate(set) var snapshotInputCount = 0
    fileprivate(set) var parameterMutationCount = 0
    fileprivate(set) var oneShotRequests = 0
    fileprivate(set) var oneShotPlayCount = 0
    fileprivate(set) var runtimeFailureCount = 0
}

@MainActor
final class GameAudioDirector: NSObject {
    static let maximumBackendUpdateRate = 30.0

    private let assets: any AudioAssetProviding
    private let backend: any GameAudioBackend
    private let notificationCenter: NotificationCenter
    private var mixModel = AudioMixModel()
    private var latestMix = AudioMixSnapshot.silent
    private var lastMutationTimestamp: TimeInterval?
    private var handledCueIDs: Set<UUID> = []
    private var lifecyclePhase: GameSessionLifecyclePhase = .active
    private var isInterrupted = false
    private var backendIsPrepared = false
    private var observesNotifications = false

    private(set) var desiredContext: GameAudioContext = .hub
    private(set) var sfxEnabled = true
    private(set) var metrics = GameAudioDirectorMetrics()
    private(set) var lastRuntimeError: String?

    var identity: ObjectIdentifier {
        ObjectIdentifier(self)
    }

    var backendDiagnostics: GameAudioBackendDiagnostics {
        backend.diagnostics
    }

    var assetMetrics: AudioAssetLibraryMetrics {
        assets.metrics
    }

    var isSuspended: Bool {
        lifecyclePhase != .active || isInterrupted
    }

    init(
        assetLibrary: any AudioAssetProviding,
        backend: (any GameAudioBackend)? = nil,
        notificationCenter: NotificationCenter = .default,
        observeNotifications: Bool = true
    ) {
        assets = assetLibrary
        self.backend = backend ?? AVFoundationGameAudioBackend()
        self.notificationCenter = notificationCenter
        super.init()
        if observeNotifications {
            registerForNotifications()
        }
    }

    deinit {
        if observesNotifications {
            notificationCenter.removeObserver(self)
        }
    }

    func prepareAssets() throws {
        metrics.assetPreparationAttempts += 1
        try assets.prepare()
        metrics.assetPreparationSuccesses += 1
        restoreDesiredOutput(rebuild: false)
    }

    func setSFXEnabled(_ isEnabled: Bool) {
        guard sfxEnabled != isEnabled else { return }
        sfxEnabled = isEnabled
        if isEnabled {
            restoreDesiredOutput(rebuild: false)
        } else {
            backend.stopAllOutput()
        }
    }

    func beginAttempt() {
        handledCueIDs.removeAll(keepingCapacity: true)
        mixModel.reset()
        latestMix = .silent
        lastMutationTimestamp = nil
    }

    func transition(to context: GameAudioContext) {
        let changed = desiredContext != context
        desiredContext = context
        if context != .racing {
            lastMutationTimestamp = nil
        }
        guard changed, canProduceOutput else { return }
        performRuntimeOperation {
            try ensureBackendPrepared()
            try backend.activate()
            try backend.transition(to: context)
            if context == .racing {
                try backend.apply(latestMix)
            }
        }
    }

    func update(
        speed: Double,
        initialSpeed: Double,
        maximumSpeed: Double,
        steering: Double,
        timestamp: TimeInterval
    ) {
        metrics.snapshotInputCount += 1
        guard desiredContext == .racing,
              timestamp.isFinite else {
            return
        }

        if let lastMutationTimestamp,
           timestamp >= lastMutationTimestamp,
           timestamp - lastMutationTimestamp + 0.000_000_1
            < 1 / Self.maximumBackendUpdateRate {
            return
        }
        let deltaTime: TimeInterval
        if let lastMutationTimestamp, timestamp >= lastMutationTimestamp {
            deltaTime = timestamp - lastMutationTimestamp
        } else {
            deltaTime = 1 / Self.maximumBackendUpdateRate
        }
        self.lastMutationTimestamp = timestamp
        latestMix = mixModel.update(
            speed: speed,
            initialSpeed: initialSpeed,
            maximumSpeed: maximumSpeed,
            steering: steering,
            deltaTime: deltaTime
        )

        guard canProduceOutput else { return }
        performRuntimeOperation {
            try ensureBackendPrepared()
            try backend.apply(latestMix)
            metrics.parameterMutationCount += 1
        }
    }

    func play(
        _ cue: GameAudioCue,
        eventID: UUID? = nil,
        rate: Double = 1,
        pan: Double = 0,
        gain: Double = 1
    ) {
        metrics.oneShotRequests += 1
        if let eventID, !handledCueIDs.insert(eventID).inserted {
            return
        }
        guard canProduceOutput else { return }

        let safeRate = Self.clampFinite(rate, lower: 0.75, upper: 1.35, fallback: 1)
        let directional = AudioMixModel.directionalMix(pan: pan, gain: gain)
        let outputGain = min(
            sqrt(
                directional.leftGain * directional.leftGain
                    + directional.rightGain * directional.rightGain
            ),
            1
        )
        performRuntimeOperation {
            try ensureBackendPrepared()
            try backend.play(
                role: cue.role,
                rate: safeRate,
                pan: directional.pan,
                gain: outputGain
            )
            metrics.oneShotPlayCount += 1
        }
    }

    func handleLifecycle(_ phase: GameSessionLifecyclePhase) {
        guard lifecyclePhase != phase else { return }
        let wasSuspended = isSuspended
        lifecyclePhase = phase
        switch phase {
        case .inactive, .background:
            guard !wasSuspended else { return }
            performRuntimeOperation {
                try backend.suspend()
            }
        case .active:
            guard !isInterrupted else { return }
            restoreDesiredOutput(rebuild: false)
        }
    }

    func handleInterruptionBegan() {
        guard !isInterrupted else { return }
        let wasSuspended = isSuspended
        isInterrupted = true
        guard !wasSuspended else { return }
        performRuntimeOperation {
            try backend.suspend()
        }
    }

    func handleInterruptionEnded(shouldResume: Bool) {
        guard isInterrupted else { return }
        isInterrupted = false
        guard shouldResume else { return }
        guard lifecyclePhase == .active else { return }
        restoreDesiredOutput(rebuild: true)
    }

    func handleRouteChange() {
        guard canProduceOutput else { return }
        restoreDesiredOutput(rebuild: true)
    }

    func handleMediaServicesReset() {
        backendIsPrepared = false
        guard canProduceOutput else { return }
        restoreDesiredOutput(rebuild: true)
    }

    private var canProduceOutput: Bool {
        assets.isPrepared && sfxEnabled && !isSuspended
    }

    private func restoreDesiredOutput(rebuild: Bool) {
        guard canProduceOutput else { return }
        performRuntimeOperation {
            try ensureBackendPrepared()
            if rebuild {
                try backend.rebuild()
            }
            try backend.activate()
            try backend.transition(to: desiredContext)
            if desiredContext == .racing {
                try backend.apply(latestMix)
            }
        }
    }

    private func ensureBackendPrepared() throws {
        guard !backendIsPrepared else { return }
        try backend.prepare(using: assets)
        backendIsPrepared = true
    }

    private func performRuntimeOperation(_ operation: () throws -> Void) {
        do {
            try operation()
            lastRuntimeError = nil
        } catch {
            metrics.runtimeFailureCount += 1
            lastRuntimeError = error.localizedDescription
        }
    }

    private func registerForNotifications() {
        observesNotifications = true
        notificationCenter.addObserver(
            self,
            selector: #selector(audioSessionInterrupted(_:)),
            name: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance()
        )
        notificationCenter.addObserver(
            self,
            selector: #selector(audioRouteChanged(_:)),
            name: AVAudioSession.routeChangeNotification,
            object: AVAudioSession.sharedInstance()
        )
        notificationCenter.addObserver(
            self,
            selector: #selector(mediaServicesWereReset(_:)),
            name: AVAudioSession.mediaServicesWereResetNotification,
            object: AVAudioSession.sharedInstance()
        )
    }

    @objc
    private func audioSessionInterrupted(_ notification: Notification) {
        guard let rawType = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: rawType) else {
            return
        }
        switch type {
        case .began:
            handleInterruptionBegan()
        case .ended:
            let rawOptions = notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            handleInterruptionEnded(
                shouldResume: AVAudioSession.InterruptionOptions(rawValue: rawOptions)
                    .contains(.shouldResume)
            )
        @unknown default:
            handleInterruptionBegan()
        }
    }

    @objc
    private func audioRouteChanged(_ notification: Notification) {
        handleRouteChange()
    }

    @objc
    private func mediaServicesWereReset(_ notification: Notification) {
        handleMediaServicesReset()
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

@MainActor
private final class AVFoundationGameAudioBackend: GameAudioBackend {
    private static let engineRoles: [AudioAssetRole] = [
        .engineIdleLoop,
        .engineMidLoop,
        .engineHighLoop,
    ]
    private static let environmentRoles: [AudioAssetRole] = [
        .roadLoop,
        .windLoop,
        .tireScrubLoop,
    ]
    private static let oneShotPoolSize = 2

    private let engine = AVAudioEngine()
    private let enginePlayers = AVFoundationGameAudioBackend.engineRoles.map {
        _ in AVAudioPlayerNode()
    }
    private let engineRates = AVFoundationGameAudioBackend.engineRoles.map {
        _ in AVAudioUnitVarispeed()
    }
    private let environmentPlayers = AVFoundationGameAudioBackend.environmentRoles.map {
        _ in AVAudioPlayerNode()
    }
    private let ambiencePlayer = AVAudioPlayerNode()
    private let oneShotPlayers = (0..<oneShotPoolSize).map { _ in AVAudioPlayerNode() }
    private let oneShotRates = (0..<oneShotPoolSize).map { _ in AVAudioUnitVarispeed() }
    private let audioSession = AVAudioSession.sharedInstance()
    private var buffers: [AudioAssetRole: AVAudioPCMBuffer] = [:]
    private var graphIsBuilt = false
    private var nextOneShotIndex = 0
    private var maximumSimultaneousOneShots = 0

    var diagnostics: GameAudioBackendDiagnostics {
        let allocatedNodeCount = enginePlayers.count
            + engineRates.count
            + environmentPlayers.count
            + 1
            + oneShotPlayers.count
            + oneShotRates.count
        return GameAudioBackendDiagnostics(
            engineIdentity: ObjectIdentifier(engine),
            longLivedNodeCount: allocatedNodeCount + 2,
            nodeAllocationCount: allocatedNodeCount,
            maximumSimultaneousOneShots: maximumSimultaneousOneShots
        )
    }

    func prepare(using assets: any AudioAssetProviding) throws {
        guard buffers.isEmpty else { return }
        buffers = try Dictionary(
            uniqueKeysWithValues: AudioAssetRole.allCases.map { role in
                (role, try assets.buffer(for: role))
            }
        )
        buildGraphIfNeeded()
    }

    func activate() throws {
        try audioSession.setCategory(.ambient, mode: .default, options: [.mixWithOthers])
        try audioSession.setActive(true)
        if !engine.isRunning {
            engine.prepare()
            try engine.start()
        }
    }

    func transition(to context: GameAudioContext) throws {
        stopLoopPlayers()
        switch context {
        case .hub:
            try scheduleLoop(role: .hubAmbienceLoop, on: ambiencePlayer, volume: 0.20)
        case .maintenance:
            try scheduleLoop(
                role: .maintenanceAmbienceLoop,
                on: ambiencePlayer,
                volume: 0.22
            )
        case .racing:
            for (index, role) in Self.engineRoles.enumerated() {
                try scheduleLoop(role: role, on: enginePlayers[index], volume: 0)
            }
            for (index, role) in Self.environmentRoles.enumerated() {
                try scheduleLoop(role: role, on: environmentPlayers[index], volume: 0)
            }
        case .countdown, .impact, .result:
            break
        }
    }

    func apply(_ mix: AudioMixSnapshot) throws {
        let engineGains = [mix.idleGain, mix.midGain, mix.highGain]
        let engineRateValues = [mix.idleRate, mix.midRate, mix.highRate]
        for index in enginePlayers.indices {
            enginePlayers[index].volume = Float(engineGains[index])
            engineRates[index].rate = Float(engineRateValues[index])
        }
        let environmentGains = [mix.roadGain, mix.windGain, mix.tireScrubGain]
        for index in environmentPlayers.indices {
            environmentPlayers[index].volume = Float(environmentGains[index])
        }
    }

    func play(role: AudioAssetRole, rate: Double, pan: Double, gain: Double) throws {
        guard let buffer = buffers[role] else {
            throw AudioAssetLibraryError.decodeFailure(role.rawValue)
        }
        let availableIndex = oneShotPlayers.firstIndex { !$0.isPlaying }
            ?? nextOneShotIndex
        nextOneShotIndex = (availableIndex + 1) % oneShotPlayers.count
        let player = oneShotPlayers[availableIndex]
        player.stop()
        oneShotRates[availableIndex].rate = Float(rate)
        player.pan = Float(pan)
        player.volume = Float(gain)
        player.scheduleBuffer(buffer)
        player.play()
        maximumSimultaneousOneShots = max(
            maximumSimultaneousOneShots,
            oneShotPlayers.filter(\.isPlaying).count
        )
    }

    func stopAllOutput() {
        stopLoopPlayers()
        oneShotPlayers.forEach { $0.stop() }
    }

    func suspend() throws {
        stopAllOutput()
        engine.pause()
        try audioSession.setActive(false, options: [.notifyOthersOnDeactivation])
    }

    func rebuild() throws {
        stopAllOutput()
        engine.stop()
        engine.reset()
        buildGraphIfNeeded()
    }

    private func buildGraphIfNeeded() {
        guard !graphIsBuilt else { return }
        for index in enginePlayers.indices {
            engine.attach(enginePlayers[index])
            engine.attach(engineRates[index])
            engine.connect(
                enginePlayers[index],
                to: engineRates[index],
                format: buffers[Self.engineRoles[index]]?.format
            )
            engine.connect(engineRates[index], to: engine.mainMixerNode, format: nil)
        }
        for (index, player) in environmentPlayers.enumerated() {
            engine.attach(player)
            engine.connect(
                player,
                to: engine.mainMixerNode,
                format: buffers[Self.environmentRoles[index]]?.format
            )
        }
        engine.attach(ambiencePlayer)
        engine.connect(
            ambiencePlayer,
            to: engine.mainMixerNode,
            format: buffers[.hubAmbienceLoop]?.format
        )
        for index in oneShotPlayers.indices {
            let player = oneShotPlayers[index]
            let rate = oneShotRates[index]
            engine.attach(player)
            engine.attach(rate)
            engine.connect(
                player,
                to: rate,
                format: buffers[.nearMissWhoosh]?.format
            )
            engine.connect(rate, to: engine.mainMixerNode, format: nil)
        }
        graphIsBuilt = true
    }

    private func scheduleLoop(
        role: AudioAssetRole,
        on player: AVAudioPlayerNode,
        volume: Float
    ) throws {
        guard let buffer = buffers[role] else {
            throw AudioAssetLibraryError.decodeFailure(role.rawValue)
        }
        player.volume = volume
        player.scheduleBuffer(buffer, at: nil, options: [.loops])
        player.play()
    }

    private func stopLoopPlayers() {
        enginePlayers.forEach { $0.stop() }
        environmentPlayers.forEach { $0.stop() }
        ambiencePlayer.stop()
    }
}
