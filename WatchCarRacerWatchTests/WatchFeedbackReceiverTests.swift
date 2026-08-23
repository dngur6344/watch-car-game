import XCTest
@testable import WatchCarRacerWatchApp

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

    func testDistinctEventsPreserveDistinctFeedbackKinds() throws {
        let nearMiss = WatchFeedbackPacket(
            eventID: UUID(uuidString: "AAAAAAAA-2222-3333-4444-555555555555")!,
            kind: .nearMiss
        )
        let collision = WatchFeedbackPacket(
            eventID: UUID(uuidString: "BBBBBBBB-2222-3333-4444-555555555555")!,
            kind: .collision
        )
        var receiver = WatchFeedbackReceiver()

        XCTAssertEqual(try receiver.receive(nearMiss.encodedData())?.kind, .nearMiss)
        XCTAssertEqual(try receiver.receive(collision.encodedData())?.kind, .collision)
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
}
