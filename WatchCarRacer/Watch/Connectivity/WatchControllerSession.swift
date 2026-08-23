import Foundation
import Observation
import WatchConnectivity

@MainActor
@Observable
final class WatchControllerSession: NSObject {
    static let shared = WatchControllerSession()

    private(set) var activationState: WCSessionActivationState = .notActivated
    private(set) var isReachable = false
    private(set) var isAppActive = false
    private(set) var lastSendError: String?
    private(set) var feedbackDecodingFailures = 0
    private(set) var lastFeedbackError: String?

    let motionEngine: MotionSteeringEngine

    @ObservationIgnored private let session: WCSession
    @ObservationIgnored private var streamID = UUID()
    @ObservationIgnored private var sequence: UInt64 = 0
    @ObservationIgnored private var senderTask: Task<Void, Never>?
    @ObservationIgnored private let hapticPlayer: any WatchHapticPlaying
    @ObservationIgnored private var feedbackReceiver = WatchFeedbackReceiver()

#if DEBUG && targetEnvironment(simulator)
    @ObservationIgnored private var hasSyntheticStream = false
#endif

    private override init() {
        motionEngine = MotionSteeringEngine()
        session = WCSession.default
        hapticPlayer = WatchHapticPlayer()
        super.init()
        session.delegate = self
        session.activate()
    }

    var activationDescription: String {
        switch activationState {
        case .notActivated: "Not activated"
        case .inactive: "Inactive"
        case .activated: "Activated"
        @unknown default: "Unknown"
        }
    }

    func setAppActive(_ active: Bool) {
        guard active != isAppActive else {
            return
        }
        isAppActive = active
        if active {
            motionEngine.start()
            startSender()
            sendLatestIfPossible()
        } else {
            stopSender()
            motionEngine.stopAndInvalidateCalibration()
#if DEBUG && targetEnvironment(simulator)
            hasSyntheticStream = false
#endif
        }
    }

    @discardableResult
    func calibrateNeutral() -> Bool {
        guard motionEngine.calibrateNeutral() else {
            return false
        }
        beginNewStream()
        sendLatestIfPossible()
        return true
    }

    private func beginNewStream() {
        streamID = UUID()
        sequence = 0
        lastSendError = nil
    }

    private func startSender() {
        guard senderTask == nil else {
            return
        }
        senderTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(33))
                guard !Task.isCancelled else {
                    return
                }
                self?.sendLatestIfPossible()
            }
        }
    }

    private func stopSender() {
        senderTask?.cancel()
        senderTask = nil
    }

    private func sendLatestIfPossible() {
        guard isAppActive, activationState == .activated, session.isReachable else {
            return
        }

        isReachable = true
        sequence &+= 1
        let state = motionEngine.state
        let packet = SteeringPacket(
            streamID: streamID,
            sequence: sequence,
            state: state,
            value: state == .active ? motionEngine.latestValue : 0
        )

        do {
            let data = try packet.encodedData()
            session.sendMessageData(data, replyHandler: nil) { [weak self] error in
                let message = error.localizedDescription
                Task { @MainActor [weak self] in
                    self?.lastSendError = message
                }
            }
        } catch {
            lastSendError = error.localizedDescription
        }
    }

    private func processFeedback(_ data: Data) {
        do {
            guard let packet = try feedbackReceiver.receive(data) else {
                return
            }
            lastFeedbackError = nil
            hapticPlayer.play(packet.kind)
        } catch {
            feedbackDecodingFailures += 1
            lastFeedbackError = error.localizedDescription
        }
    }

#if DEBUG && targetEnvironment(simulator)
    func setSyntheticSteering(_ value: Double) {
        guard isAppActive else {
            return
        }
        if !hasSyntheticStream {
            beginNewStream()
            hasSyntheticStream = true
        }
        motionEngine.setSyntheticSteering(value)
        sendLatestIfPossible()
    }
#endif
}

extension WatchControllerSession: WCSessionDelegate {
    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: (any Error)?
    ) {
        let reachable = session.isReachable
        let errorMessage = error?.localizedDescription
        Task { @MainActor [weak self] in
            self?.activationState = activationState
            self?.isReachable = reachable
            self?.lastSendError = errorMessage
            self?.sendLatestIfPossible()
        }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        let reachable = session.isReachable
        Task { @MainActor [weak self] in
            self?.isReachable = reachable
            if reachable {
                self?.sendLatestIfPossible()
            }
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessageData messageData: Data) {
        Task { @MainActor [weak self] in
            self?.processFeedback(messageData)
        }
    }
}
