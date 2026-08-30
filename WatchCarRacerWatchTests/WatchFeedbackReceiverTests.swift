import XCTest
@testable import WatchCarRacerWatchApp

@MainActor
final class WatchFeedbackReceiverTests: XCTestCase {
    func testDuplicatePacketProducesOnlyOneAcceptedHapticEvent() throws {
        let packet = WatchFeedbackPacket(
            eventID: UUID(uuidString: "11111111-2222-3333-4444-555555555555")!,
            kind: .nearMiss
        )
        let data = try packet.encodedData()
        var receiver = WatchFeedbackReceiver()

        XCTAssertEqual(try receiver.receive(data), packet)
        XCTAssertNil(try receiver.receive(data))
        XCTAssertEqual(receiver.handledEventIDs, [packet.eventID])
    }

    func testDistinctEventsPreserveEveryFeedbackKind() throws {
        let kinds: [WatchFeedbackKind] = [
            .countdownTick,
            .go,
            .nearMiss,
            .nearMissStrong,
            .collision,
        ]
        var receiver = WatchFeedbackReceiver()

        for kind in kinds {
            let packet = WatchFeedbackPacket(eventID: UUID(), kind: kind)
            XCTAssertEqual(try receiver.receive(packet.encodedData())?.kind, kind)
        }
        XCTAssertEqual(receiver.handledEventIDs.count, kinds.count)
    }

    func testRejectedVersionDoesNotConsumeEventID() throws {
        let eventID = UUID(uuidString: "CCCCCCCC-2222-3333-4444-555555555555")!
        let invalid = WatchFeedbackPacket(protocolVersion: 2, eventID: eventID, kind: .collision)
        let valid = WatchFeedbackPacket(eventID: eventID, kind: .collision)
        var receiver = WatchFeedbackReceiver()
        let invalidData = try JSONEncoder().encode(invalid)

        XCTAssertThrowsError(try receiver.receive(invalidData))
        XCTAssertEqual(try receiver.receive(valid.encodedData()), valid)
    }

    func testUnknownAndMalformedFeedbackDoNotConsumeIDOrPoisonReceiver() throws {
        let eventID = UUID(uuidString: "DDDDDDDD-2222-3333-4444-555555555555")!
        let unknown = Data(
            #"{"protocolVersion":1,"eventID":"DDDDDDDD-2222-3333-4444-555555555555","kind":"futureCue"}"#.utf8
        )
        let malformed = Data([0xFF, 0x00, 0x7B])
        var receiver = WatchFeedbackReceiver()

        XCTAssertThrowsError(try receiver.receive(unknown))
        XCTAssertThrowsError(try receiver.receive(malformed))
        XCTAssertTrue(receiver.handledEventIDs.isEmpty)

        let valid = WatchFeedbackPacket(eventID: eventID, kind: .go)
        XCTAssertEqual(try receiver.receive(valid.encodedData()), valid)
    }

    func testWatchHapticMappingPreservesExistingPatternsAndAddsNarrowNewCues() {
        XCTAssertEqual(WatchHapticPlayer.hapticType(for: .countdownTick), .click)
        XCTAssertEqual(WatchHapticPlayer.hapticType(for: .go), .start)
        XCTAssertEqual(WatchHapticPlayer.hapticType(for: .nearMiss), .click)
        XCTAssertEqual(WatchHapticPlayer.hapticType(for: .nearMissStrong), .directionUp)
        XCTAssertEqual(WatchHapticPlayer.hapticType(for: .collision), .failure)
    }
}
