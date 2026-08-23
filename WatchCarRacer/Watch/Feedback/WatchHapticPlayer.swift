import Foundation
import WatchKit

@MainActor
protocol WatchHapticPlaying: AnyObject {
    func play(_ kind: WatchFeedbackKind)
}

@MainActor
final class WatchHapticPlayer: WatchHapticPlaying {
    func play(_ kind: WatchFeedbackKind) {
        switch kind {
        case .nearMiss:
            WKInterfaceDevice.current().play(.click)
        case .collision:
            WKInterfaceDevice.current().play(.failure)
        }
    }
}

struct WatchFeedbackReceiver {
    private(set) var handledEventIDs: Set<UUID> = []

    mutating func receive(_ data: Data) throws -> WatchFeedbackPacket? {
        let packet = try WatchFeedbackPacket.decode(from: data)
        guard handledEventIDs.insert(packet.eventID).inserted else {
            return nil
        }
        return packet
    }
}
