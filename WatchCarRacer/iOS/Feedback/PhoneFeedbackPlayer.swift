import AVFoundation
import Foundation
import UIKit

struct GameFeedback: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case nearMiss(bonus: Int)
        case collision

        var watchKind: WatchFeedbackKind {
            switch self {
            case .nearMiss:
                return .nearMiss
            case .collision:
                return .collision
            }
        }
    }

    let eventID: UUID
    let kind: Kind
}

struct GameFeedbackCoordinator {
    private enum EventKey: Hashable {
        case nearMiss(obstacleID: UInt64, kind: ObstacleKind)
        case collision(obstacleID: UInt64, kind: ObstacleKind)
    }

    private var handledEvents: Set<EventKey> = []
    private let makeEventID: () -> UUID

    init(makeEventID: @escaping () -> UUID = UUID.init) {
        self.makeEventID = makeEventID
    }

    mutating func feedback(for events: [GameEvent]) -> [GameFeedback] {
        events.compactMap { event in
            let key: EventKey
            let kind: GameFeedback.Kind
            switch event {
            case let .nearMiss(obstacleID, obstacleKind, bonus):
                key = .nearMiss(obstacleID: obstacleID, kind: obstacleKind)
                kind = .nearMiss(bonus: bonus)
            case let .collision(obstacleID, obstacleKind):
                key = .collision(obstacleID: obstacleID, kind: obstacleKind)
                kind = .collision
            }

            guard handledEvents.insert(key).inserted else {
                return nil
            }
            return GameFeedback(eventID: makeEventID(), kind: kind)
        }
    }

    mutating func reset() {
        handledEvents.removeAll(keepingCapacity: true)
    }
}

@MainActor
protocol PhoneFeedbackPlaying: AnyObject {
    func play(_ feedback: GameFeedback)
}

enum ProceduralFeedbackAudio {
    enum Cue {
        case nearMiss
        case collision
    }

    static func waveData(for cue: Cue, sampleRate: Int = 22_050) -> Data {
        let duration = cue == .nearMiss ? 0.14 : 0.24
        let sampleCount = Int(duration * Double(sampleRate))
        var randomState: UInt32 = 0xC0FF_EE11
        var samples = [Int16]()
        samples.reserveCapacity(sampleCount)

        for index in 0..<sampleCount {
            let time = Double(index) / Double(sampleRate)
            let remaining = duration - time
            let attack = min(time / 0.008, 1)
            let release = min(remaining / (cue == .nearMiss ? 0.045 : 0.09), 1)
            let envelope = max(0, min(attack, release))

            let value: Double
            switch cue {
            case .nearMiss:
                let progress = time / duration
                let frequency = 720 + 1_080 * progress
                value = sin(2 * .pi * frequency * time) * envelope * 0.48
            case .collision:
                randomState = randomState &* 1_664_525 &+ 1_013_904_223
                let noise = Double(Int32(bitPattern: randomState)) / Double(Int32.max)
                let thump = sin(2 * .pi * 82 * time) + 0.35 * sin(2 * .pi * 147 * time)
                value = (0.55 * thump + 0.30 * noise) * envelope * 0.58
            }

            let clamped = min(max(value, -1), 1)
            samples.append(Int16((clamped * Double(Int16.max)).rounded()))
        }

        return makeWaveData(samples: samples, sampleRate: sampleRate)
    }

    private static func makeWaveData(samples: [Int16], sampleRate: Int) -> Data {
        let dataSize = UInt32(samples.count * MemoryLayout<Int16>.size)
        var data = Data()
        data.reserveCapacity(44 + Int(dataSize))
        data.append(contentsOf: Array("RIFF".utf8))
        append(36 + dataSize, to: &data)
        data.append(contentsOf: Array("WAVE".utf8))
        data.append(contentsOf: Array("fmt ".utf8))
        append(UInt32(16), to: &data)
        append(UInt16(1), to: &data)
        append(UInt16(1), to: &data)
        append(UInt32(sampleRate), to: &data)
        append(UInt32(sampleRate * MemoryLayout<Int16>.size), to: &data)
        append(UInt16(MemoryLayout<Int16>.size), to: &data)
        append(UInt16(16), to: &data)
        data.append(contentsOf: Array("data".utf8))
        append(dataSize, to: &data)
        for sample in samples {
            append(sample, to: &data)
        }
        return data
    }

    private static func append<Value: FixedWidthInteger>(_ value: Value, to data: inout Data) {
        var littleEndian = value.littleEndian
        Swift.withUnsafeBytes(of: &littleEndian) { bytes in
            data.append(contentsOf: bytes)
        }
    }
}

@MainActor
final class PhoneFeedbackPlayer: PhoneFeedbackPlaying {
    private let nearMissHaptic = UIImpactFeedbackGenerator(style: .soft)
    private let collisionHaptic = UINotificationFeedbackGenerator()
    private var nearMissAudio: AVAudioPlayer?
    private var collisionAudio: AVAudioPlayer?

    private(set) var lastError: String?

    init() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
        } catch {
            lastError = error.localizedDescription
        }

        do {
            nearMissAudio = try AVAudioPlayer(
                data: ProceduralFeedbackAudio.waveData(for: .nearMiss)
            )
            collisionAudio = try AVAudioPlayer(
                data: ProceduralFeedbackAudio.waveData(for: .collision)
            )
            nearMissAudio?.prepareToPlay()
            collisionAudio?.prepareToPlay()
        } catch {
            lastError = error.localizedDescription
        }
    }

    func play(_ feedback: GameFeedback) {
        switch feedback.kind {
        case .nearMiss:
            nearMissHaptic.impactOccurred(intensity: 0.55)
            play(nearMissAudio)
        case .collision:
            collisionHaptic.notificationOccurred(.error)
            play(collisionAudio)
        }
    }

    private func play(_ player: AVAudioPlayer?) {
        guard let player else {
            return
        }
        player.currentTime = 0
        if !player.play() {
            lastError = "Procedural feedback audio could not be played."
        }
    }
}
