import Foundation
import Observation
import WatchConnectivity

@MainActor
protocol WatchFeedbackSending: AnyObject {
    func sendFeedback(_ packet: WatchFeedbackPacket) throws
}

enum PhoneSteeringReceiverError: Error, Equatable {
    case invalidStream
    case retiredStream(UUID)
}

enum WatchReadinessStatus: Equatable, Sendable {
    case activating
    case disconnected
    case awaitingPacket
    case needsCalibration
    case motionUnavailable
    case stale
    case ready

    var isReady: Bool {
        self == .ready
    }

    var guidance: String {
        switch self {
        case .activating:
            "Connecting to Apple Watch. Touch controls are available."
        case .disconnected:
            "Apple Watch is disconnected. Touch controls are available."
        case .awaitingPacket:
            "Open the Watch app to start steering, or use touch controls."
        case .needsCalibration:
            "Calibrate steering in the Watch app, or use touch controls."
        case .motionUnavailable:
            "Watch motion steering is unavailable. Use touch controls."
        case .stale:
            "Watch input was interrupted. Touch controls are active."
        case .ready:
            "Apple Watch steering is ready."
        }
    }

    init(availability: WatchSteeringAvailability) {
        switch availability {
        case .active:
            self = .ready
        case .sessionInactive:
            self = .activating
        case .unreachable:
            self = .disconnected
        case .noPacket, .awaitingFreshPacket:
            self = .awaitingPacket
        case .needsCalibration:
            self = .needsCalibration
        case .motionUnavailable:
            self = .motionUnavailable
        case .stale:
            self = .stale
        }
    }
}

struct PhoneSteeringReceiver {
    static let freshnessThreshold: TimeInterval = 0.25
    static let maximumInterarrivalSamples = 240
    static let zeroStreamID = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!

    private(set) var packetState: SteeringState?
    private(set) var receivedSteering = 0.0
    private(set) var currentStreamID: UUID?
    private(set) var lastSequence: UInt64?
    private(set) var lastReceiptTime: TimeInterval?
    private(set) var sequenceGaps: UInt64 = 0
    private(set) var interarrivalSamples: [TimeInterval] = []

    private var seenStreams: Set<UUID> = []
    private var lastActiveReceiptTime: TimeInterval?

    mutating func receive(data: Data, at receiptTime: TimeInterval) throws {
        guard receiptTime.isFinite else {
            return
        }

        let packet = try SteeringPacket.decode(from: data)
        guard packet.streamID != Self.zeroStreamID else {
            throw PhoneSteeringReceiverError.invalidStream
        }

        if packet.streamID == currentStreamID {
            try packet.validate(previousSequence: lastSequence)
            if let lastSequence, packet.sequence - lastSequence > 1 {
                sequenceGaps += packet.sequence - lastSequence - 1
            }
        } else {
            guard !seenStreams.contains(packet.streamID) else {
                throw PhoneSteeringReceiverError.retiredStream(packet.streamID)
            }
            currentStreamID = packet.streamID
            lastSequence = nil
            seenStreams.insert(packet.streamID)
        }

        if packet.state == .active {
            if let lastActiveReceiptTime {
                interarrivalSamples.append(max(0, receiptTime - lastActiveReceiptTime))
                if interarrivalSamples.count > Self.maximumInterarrivalSamples {
                    interarrivalSamples.removeFirst(interarrivalSamples.count - Self.maximumInterarrivalSamples)
                }
            }
            lastActiveReceiptTime = receiptTime
        } else {
            lastActiveReceiptTime = nil
        }

        packetState = packet.state
        receivedSteering = packet.state == .active ? packet.value : 0
        lastSequence = packet.sequence
        lastReceiptTime = receiptTime
    }

    func packetAge(at now: TimeInterval) -> TimeInterval? {
        guard let lastReceiptTime else {
            return nil
        }
        return max(0, now - lastReceiptTime)
    }

    func isStale(at now: TimeInterval) -> Bool {
        guard packetState == .active, let age = packetAge(at: now) else {
            return true
        }
        return age > Self.freshnessThreshold
    }

    func routingReading(
        isSessionActive: Bool,
        isReachable: Bool,
        at now: TimeInterval
    ) -> WatchSteeringReading {
        let sampleID: WatchSteeringSampleID?
        if let currentStreamID, let lastSequence {
            sampleID = WatchSteeringSampleID(streamID: currentStreamID, sequence: lastSequence)
        } else {
            sampleID = nil
        }

        let availability: WatchSteeringAvailability
        if !isSessionActive {
            availability = .sessionInactive
        } else if !isReachable {
            availability = .unreachable
        } else {
            switch packetState {
            case .active:
                availability = isStale(at: now) ? .stale : .active
            case .needsCalibration:
                availability = .needsCalibration
            case .motionUnavailable:
                availability = .motionUnavailable
            case nil:
                availability = .noPacket
            }
        }

        return WatchSteeringReading(
            value: availability == .active ? receivedSteering : 0,
            availability: availability,
            sampleID: sampleID
        )
    }

    func readinessStatus(
        activationState: WCSessionActivationState,
        isReachable: Bool,
        at now: TimeInterval
    ) -> WatchReadinessStatus {
        WatchReadinessStatus(
            availability: routingReading(
                isSessionActive: activationState == .activated,
                isReachable: isReachable,
                at: now
            ).availability
        )
    }

    var interarrivalP95: TimeInterval? {
        guard !interarrivalSamples.isEmpty else {
            return nil
        }
        let sorted = interarrivalSamples.sorted()
        let index = max(0, Int(ceil(Double(sorted.count) * 0.95)) - 1)
        return sorted[index]
    }
}

@MainActor
@Observable
final class PhoneWatchSession: NSObject {
    static let shared = PhoneWatchSession()

    private(set) var activationState: WCSessionActivationState = .notActivated
    private(set) var isReachable = false
    private(set) var receivedSteering = 0.0
    private(set) var packetState: SteeringState?
    private(set) var packetAgeMilliseconds: Double?
    private(set) var sequenceGaps: UInt64 = 0
    private(set) var interarrivalP95Milliseconds: Double?
    private(set) var decodingFailures = 0
    private(set) var isStale = true
    private(set) var currentStreamID: UUID?
    private(set) var lastSequence: UInt64?
    private(set) var activationError: String?
    private(set) var watchFeedbackSendFailures = 0
    private(set) var lastWatchFeedbackError: String?
    private(set) var readinessStatus: WatchReadinessStatus = .activating

    @ObservationIgnored private let session: WCSession
    @ObservationIgnored private var receiver = PhoneSteeringReceiver()
    @ObservationIgnored private var ageTask: Task<Void, Never>?

    private override init() {
        session = WCSession.default
        super.init()
        session.delegate = self
        session.activate()
        startAgeUpdates()
    }

    var activationDescription: String {
        switch activationState {
        case .notActivated: "Not activated"
        case .inactive: "Inactive"
        case .activated: "Activated"
        @unknown default: "Unknown"
        }
    }

    var effectiveSteering: Double {
        isFallback ? 0 : receivedSteering
    }

    var isFallback: Bool {
        !isReachable || isStale || packetState != .active
    }

    var sourceDescription: String {
        isFallback ? "Neutral fallback" : "Watch"
    }

    var packetStateDescription: String {
        packetState?.rawValue ?? "No packet"
    }

    func routingReading(at now: TimeInterval) -> WatchSteeringReading {
        receiver.routingReading(
            isSessionActive: activationState == .activated,
            isReachable: isReachable,
            at: now
        )
    }

    func readinessStatus(at now: TimeInterval) -> WatchReadinessStatus {
        receiver.readinessStatus(
            activationState: activationState,
            isReachable: isReachable,
            at: now
        )
    }

    func sendFeedback(_ packet: WatchFeedbackPacket) throws {
        guard activationState == .activated, session.isReachable else {
            return
        }

        let data = try packet.encodedData()
        lastWatchFeedbackError = nil
        session.sendMessageData(data, replyHandler: nil) { [weak self] error in
            let message = error.localizedDescription
            Task { @MainActor [weak self] in
                self?.watchFeedbackSendFailures += 1
                self?.lastWatchFeedbackError = message
            }
        }
    }

    private func startAgeUpdates() {
        ageTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(50))
                guard !Task.isCancelled, let self else {
                    return
                }
                self.refreshAge(now: ProcessInfo.processInfo.systemUptime)
            }
        }
    }

    private func process(_ data: Data, receiptTime: TimeInterval) {
        do {
            try receiver.receive(data: data, at: receiptTime)
            receivedSteering = receiver.receivedSteering
            packetState = receiver.packetState
            sequenceGaps = receiver.sequenceGaps
            interarrivalP95Milliseconds = receiver.interarrivalP95.map { $0 * 1_000 }
            currentStreamID = receiver.currentStreamID
            lastSequence = receiver.lastSequence
            refreshAge(now: receiptTime)
        } catch {
            decodingFailures += 1
        }
    }

    private func refreshAge(now: TimeInterval) {
        packetAgeMilliseconds = receiver.packetAge(at: now).map { $0 * 1_000 }
        isStale = receiver.isStale(at: now)
        refreshReadiness(now: now)
    }

    private func refreshReadiness(now: TimeInterval) {
        let updatedStatus = readinessStatus(at: now)
        guard updatedStatus != readinessStatus else {
            return
        }
        readinessStatus = updatedStatus
    }
}

extension PhoneWatchSession: WatchSteeringReadingProviding {}
extension PhoneWatchSession: WatchFeedbackSending {}

extension PhoneWatchSession: WCSessionDelegate {
    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: (any Error)?
    ) {
        let reachable = session.isReachable
        let errorMessage = error?.localizedDescription
        Task { @MainActor [weak self] in
            guard let self else {
                return
            }
            self.activationState = activationState
            self.isReachable = reachable
            self.activationError = errorMessage
            self.refreshReadiness(now: ProcessInfo.processInfo.systemUptime)
        }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {
        Task { @MainActor [weak self] in
            guard let self else {
                return
            }
            self.activationState = .inactive
            self.isReachable = false
            self.refreshReadiness(now: ProcessInfo.processInfo.systemUptime)
        }
    }

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        Task { @MainActor [weak self] in
            guard let self else {
                return
            }
            self.activationState = .notActivated
            self.isReachable = false
            self.refreshReadiness(now: ProcessInfo.processInfo.systemUptime)
            self.session.activate()
        }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        let reachable = session.isReachable
        Task { @MainActor [weak self] in
            guard let self else {
                return
            }
            self.isReachable = reachable
            self.refreshReadiness(now: ProcessInfo.processInfo.systemUptime)
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessageData messageData: Data) {
        let receiptTime = ProcessInfo.processInfo.systemUptime
        Task { @MainActor [weak self] in
            self?.process(messageData, receiptTime: receiptTime)
        }
    }
}
