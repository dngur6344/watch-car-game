import Foundation
import WatchKit

@MainActor
protocol WatchHapticPlaying: AnyObject {
    func play(_ kind: WatchFeedbackKind)
}

@MainActor
final class WatchHapticPlayer: WatchHapticPlaying {
    func play(_ kind: WatchFeedbackKind) {
        WKInterfaceDevice.current().play(Self.hapticType(for: kind))
    }

    static func hapticType(for kind: WatchFeedbackKind) -> WKHapticType {
        switch kind {
        case .countdownTick:
            .click
        case .go:
            .start
        case .nearMiss:
            .click
        case .nearMissStrong:
            .directionUp
        case .collision:
            .failure
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
