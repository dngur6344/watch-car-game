import XCTest
@testable import WatchCarRacer

final class ControllerMessagesTests: XCTestCase {
    func testSteeringPacketRoundTrip() throws {
        let packet = SteeringPacket(
            streamID: UUID(uuidString: "11111111-2222-3333-4444-555555555555")!,
            sequence: 42,
            state: .active,
            value: -0.375
        )

        XCTAssertEqual(try SteeringPacket.decode(from: packet.encodedData()), packet)
    }

    func testWatchFeedbackPacketRoundTrip() throws {
        let packet = WatchFeedbackPacket(
            eventID: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!,
            kind: .nearMiss
        )

        XCTAssertEqual(try WatchFeedbackPacket.decode(from: packet.encodedData()), packet)
    }

    func testUnsupportedWatchFeedbackVersionIsRejected() {
        let packet = WatchFeedbackPacket(
            protocolVersion: 2,
            eventID: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!,
            kind: .collision
        )

        XCTAssertThrowsError(try packet.encodedData()) { error in
            XCTAssertEqual(
                error as? ControllerMessageValidationError,
                .unsupportedVersion(received: 2)
            )
        }
    }

    func testUnsupportedVersionIsRejected() {
        let packet = makeSteeringPacket(protocolVersion: 2)

        XCTAssertThrowsError(try packet.validate()) { error in
            XCTAssertEqual(
                error as? ControllerMessageValidationError,
                .unsupportedVersion(received: 2)
            )
        }
    }

    func testNonFiniteSteeringValuesAreRejected() {
        for value in [Double.nan, Double.infinity, -Double.infinity] {
            XCTAssertThrowsError(try makeSteeringPacket(value: value).validate()) { error in
                XCTAssertEqual(error as? ControllerMessageValidationError, .nonFiniteSteering)
            }
        }
    }

    func testOutOfRangeSteeringValuesAreRejected() {
        for value in [-1.000_001, 1.000_001] {
            XCTAssertThrowsError(try makeSteeringPacket(value: value).validate()) { error in
                XCTAssertEqual(
                    error as? ControllerMessageValidationError,
                    .steeringOutOfRange(received: value)
                )
            }
        }
    }

    func testNonIncreasingSequenceIsRejected() {
        let packet = makeSteeringPacket(sequence: 10)

        for previousSequence in [10, 11] {
            XCTAssertThrowsError(try packet.validate(previousSequence: UInt64(previousSequence))) { error in
                XCTAssertEqual(
                    error as? ControllerMessageValidationError,
                    .nonIncreasingSequence(previous: UInt64(previousSequence), received: 10)
                )
            }
        }
    }

    private func makeSteeringPacket(
        protocolVersion: UInt8 = ControllerMessageProtocol.currentVersion,
        sequence: UInt64 = 1,
        value: Double = 0
    ) -> SteeringPacket {
        SteeringPacket(
            protocolVersion: protocolVersion,
            streamID: UUID(uuidString: "11111111-2222-3333-4444-555555555555")!,
            sequence: sequence,
            state: .active,
            value: value
        )
    }
}
