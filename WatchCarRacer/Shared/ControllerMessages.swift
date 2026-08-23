import Foundation

enum ControllerMessageProtocol {
    static let currentVersion: UInt8 = 1
}

enum ControllerMessageValidationError: Error, Equatable {
    case unsupportedVersion(received: UInt8)
    case nonFiniteSteering
    case steeringOutOfRange(received: Double)
    case nonIncreasingSequence(previous: UInt64, received: UInt64)
}

enum SteeringState: String, Codable, Equatable, Sendable {
    case needsCalibration
    case active
    case motionUnavailable
}

struct SteeringPacket: Codable, Equatable, Sendable {
    let protocolVersion: UInt8
    let streamID: UUID
    let sequence: UInt64
    let state: SteeringState
    let value: Double

    init(
        protocolVersion: UInt8 = ControllerMessageProtocol.currentVersion,
        streamID: UUID,
        sequence: UInt64,
        state: SteeringState,
        value: Double
    ) {
        self.protocolVersion = protocolVersion
        self.streamID = streamID
        self.sequence = sequence
        self.state = state
        self.value = value
    }

    func validate(previousSequence: UInt64? = nil) throws {
        guard protocolVersion == ControllerMessageProtocol.currentVersion else {
            throw ControllerMessageValidationError.unsupportedVersion(received: protocolVersion)
        }
        guard value.isFinite else {
            throw ControllerMessageValidationError.nonFiniteSteering
        }
        guard (-1.0...1.0).contains(value) else {
            throw ControllerMessageValidationError.steeringOutOfRange(received: value)
        }
        if let previousSequence, sequence <= previousSequence {
            throw ControllerMessageValidationError.nonIncreasingSequence(
                previous: previousSequence,
                received: sequence
            )
        }
    }

    func encodedData() throws -> Data {
        try validate()
        return try JSONEncoder().encode(self)
    }

    static func decode(from data: Data, previousSequence: UInt64? = nil) throws -> SteeringPacket {
        let packet = try JSONDecoder().decode(SteeringPacket.self, from: data)
        try packet.validate(previousSequence: previousSequence)
        return packet
    }
}

enum WatchFeedbackKind: String, Codable, Equatable, Sendable {
    case nearMiss
    case collision
}

struct WatchFeedbackPacket: Codable, Equatable, Sendable {
    let protocolVersion: UInt8
    let eventID: UUID
    let kind: WatchFeedbackKind

    init(
        protocolVersion: UInt8 = ControllerMessageProtocol.currentVersion,
        eventID: UUID,
        kind: WatchFeedbackKind
    ) {
        self.protocolVersion = protocolVersion
        self.eventID = eventID
        self.kind = kind
    }

    func validate() throws {
        guard protocolVersion == ControllerMessageProtocol.currentVersion else {
            throw ControllerMessageValidationError.unsupportedVersion(received: protocolVersion)
        }
    }

    func encodedData() throws -> Data {
        try validate()
        return try JSONEncoder().encode(self)
    }

    static func decode(from data: Data) throws -> WatchFeedbackPacket {
        let packet = try JSONDecoder().decode(WatchFeedbackPacket.self, from: data)
        try packet.validate()
        return packet
    }
}
