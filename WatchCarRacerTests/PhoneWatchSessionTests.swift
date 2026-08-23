import XCTest
@testable import WatchCarRacer

final class PhoneWatchSessionTests: XCTestCase {
    func testReceiverTracksSequenceGapsAndActiveInterarrivalP95() throws {
        let streamID = UUID(uuidString: "ABABABAB-1111-2222-3333-444444444444")!
        var receiver = PhoneSteeringReceiver()

        try receiver.receive(data: packet(streamID: streamID, sequence: 1).encodedData(), at: 10.00)
        try receiver.receive(data: packet(streamID: streamID, sequence: 2).encodedData(), at: 10.03)
        try receiver.receive(data: packet(streamID: streamID, sequence: 5).encodedData(), at: 10.07)
        try receiver.receive(data: packet(streamID: streamID, sequence: 6).encodedData(), at: 10.15)

        XCTAssertEqual(receiver.sequenceGaps, 2)
        XCTAssertEqual(try XCTUnwrap(receiver.interarrivalP95), 0.08, accuracy: 0.000_001)
    }

    func testReceiverBecomesStaleAfterFreshnessThreshold() throws {
        var receiver = PhoneSteeringReceiver()
        try receiver.receive(data: packet(sequence: 1, value: 0.75).encodedData(), at: 20)

        XCTAssertFalse(receiver.isStale(at: 20.25))
        XCTAssertTrue(receiver.isStale(at: 20.251))
        XCTAssertEqual(receiver.receivedSteering, 0.75)
    }

    func testReceiverAcceptsNewStreamButRejectsRetiredStream() throws {
        let first = UUID(uuidString: "AAAAAAAA-1111-2222-3333-444444444444")!
        let second = UUID(uuidString: "BBBBBBBB-1111-2222-3333-444444444444")!
        var receiver = PhoneSteeringReceiver()

        try receiver.receive(data: packet(streamID: first, sequence: 1).encodedData(), at: 1)
        try receiver.receive(data: packet(streamID: second, sequence: 1).encodedData(), at: 2)

        XCTAssertThrowsError(
            try receiver.receive(data: packet(streamID: first, sequence: 2).encodedData(), at: 3)
        ) { error in
            XCTAssertEqual(error as? PhoneSteeringReceiverError, .retiredStream(first))
        }
    }

    func testMalformedPacketIsRejectedWithoutChangingLastValidValue() throws {
        var receiver = PhoneSteeringReceiver()
        try receiver.receive(data: packet(sequence: 1, value: -0.4).encodedData(), at: 1)

        XCTAssertThrowsError(try receiver.receive(data: Data("not-json".utf8), at: 2))
        XCTAssertEqual(receiver.receivedSteering, -0.4)
        XCTAssertEqual(receiver.lastSequence, 1)
    }

    func testRoutingReadingRequiresActiveSessionReachabilityAndFreshActivePacket() throws {
        var receiver = PhoneSteeringReceiver()
        try receiver.receive(data: packet(sequence: 1, value: -0.45).encodedData(), at: 30)

        XCTAssertEqual(
            receiver.routingReading(isSessionActive: false, isReachable: true, at: 30).availability,
            .sessionInactive
        )
        XCTAssertEqual(
            receiver.routingReading(isSessionActive: true, isReachable: false, at: 30).availability,
            .unreachable
        )

        let active = receiver.routingReading(isSessionActive: true, isReachable: true, at: 30.25)
        XCTAssertEqual(active.availability, .active)
        XCTAssertEqual(active.value, -0.45)

        let stale = receiver.routingReading(isSessionActive: true, isReachable: true, at: 30.251)
        XCTAssertEqual(stale.availability, .stale)
        XCTAssertEqual(stale.value, 0)
    }

    func testNonActivePacketsNeverExposeSteeringToRouter() throws {
        let streamID = UUID(uuidString: "CDCDCDCD-1111-2222-3333-444444444444")!
        var receiver = PhoneSteeringReceiver()

        let needsCalibration = SteeringPacket(
            streamID: streamID,
            sequence: 1,
            state: .needsCalibration,
            value: 0.8
        )
        try receiver.receive(data: needsCalibration.encodedData(), at: 1)
        let calibrationReading = receiver.routingReading(
            isSessionActive: true,
            isReachable: true,
            at: 1
        )
        XCTAssertEqual(calibrationReading.availability, .needsCalibration)
        XCTAssertEqual(calibrationReading.value, 0)

        let motionUnavailable = SteeringPacket(
            streamID: streamID,
            sequence: 2,
            state: .motionUnavailable,
            value: -0.8
        )
        try receiver.receive(data: motionUnavailable.encodedData(), at: 2)
        let unavailableReading = receiver.routingReading(
            isSessionActive: true,
            isReachable: true,
            at: 2
        )
        XCTAssertEqual(unavailableReading.availability, .motionUnavailable)
        XCTAssertEqual(unavailableReading.value, 0)
    }

    private func packet(
        streamID: UUID = UUID(uuidString: "ABABABAB-1111-2222-3333-444444444444")!,
        sequence: UInt64,
        value: Double = 0.25
    ) -> SteeringPacket {
        SteeringPacket(streamID: streamID, sequence: sequence, state: .active, value: value)
    }
}
