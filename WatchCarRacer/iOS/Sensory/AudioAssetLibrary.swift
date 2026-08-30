import AVFoundation
import CryptoKit
import Foundation

enum AudioAssetRole: String, CaseIterable, Codable, Sendable {
    case engineIdleLoop = "engine_idle_loop"
    case engineMidLoop = "engine_mid_loop"
    case engineHighLoop = "engine_high_loop"
    case roadLoop = "road_loop"
    case windLoop = "wind_loop"
    case tireScrubLoop = "tire_scrub_loop"
    case nearMissWhoosh = "near_miss_whoosh"
    case collisionImpact = "collision_impact"
    case countdownTick = "countdown_tick"
    case goBassHit = "go_bass_hit"
    case hubAmbienceLoop = "hub_ambience_loop"
    case maintenanceAmbienceLoop = "maintenance_ambience_loop"
    case vehicleSelect = "vehicle_select"
    case colorSelect = "color_select"
    case driveTransition = "drive_transition"
}

struct AudioAssetManifest: Decodable, Sendable {
    struct Format: Decodable, Sendable {
        let sampleRate: Int
        let bitDepth: Int
        let encoding: String
    }

    struct Asset: Decodable, Sendable {
        let role: AudioAssetRole
        let filename: String
        let sampleRate: Int
        let bitDepth: Int
        let channels: Int
        let frameCount: Int
        let durationSeconds: Double
        let loop: Bool
        let sha256: String
    }

    let schemaVersion: Int
    let format: Format
    let assets: [Asset]
}

enum AudioAssetLibraryError: Error, Equatable, LocalizedError {
    case missingManifest
    case invalidManifest(String)
    case duplicateRole(String)
    case roleSetMismatch
    case missingFile(String)
    case hashMismatch(String)
    case formatMismatch(String)
    case decodeFailure(String)

    var errorDescription: String? {
        switch self {
        case .missingManifest:
            return "AudioAssetManifest.json is missing from the iOS application bundle."
        case let .invalidManifest(reason):
            return "AudioAssetManifest.json is invalid: \(reason)"
        case let .duplicateRole(role):
            return "AudioAssetManifest.json declares \(role) more than once."
        case .roleSetMismatch:
            return "AudioAssetManifest.json does not contain the complete required role set."
        case let .missingFile(filename):
            return "Required audio asset is missing: \(filename)."
        case let .hashMismatch(filename):
            return "Required audio asset has an unexpected SHA-256: \(filename)."
        case let .formatMismatch(filename):
            return "Required audio asset has an unexpected PCM format: \(filename)."
        case let .decodeFailure(filename):
            return "Required audio asset could not be decoded: \(filename)."
        }
    }
}

struct AudioAssetLibraryMetrics: Equatable, Sendable {
    fileprivate(set) var manifestReadCount = 0
    fileprivate(set) var fileReadCount = 0
    fileprivate(set) var decodeCount = 0
    fileprivate(set) var bufferAllocationCount = 0
    fileprivate(set) var decodedPCMByteCount = 0
}

@MainActor
protocol AudioAssetProviding: AnyObject {
    var isPrepared: Bool { get }
    var metrics: AudioAssetLibraryMetrics { get }

    func prepare() throws
    func buffer(for role: AudioAssetRole) throws -> AVAudioPCMBuffer
}

@MainActor
final class AudioAssetLibrary: AudioAssetProviding {
    private let manifestURLProvider: () -> URL?
    private let assetURLProvider: (String) -> URL?
    private var buffers: [AudioAssetRole: AVAudioPCMBuffer] = [:]

    private(set) var manifest: AudioAssetManifest?
    private(set) var metrics = AudioAssetLibraryMetrics()

    var isPrepared: Bool {
        buffers.count == AudioAssetRole.allCases.count
    }

    init(bundle: Bundle = .main) {
        manifestURLProvider = {
            bundle.url(forResource: "AudioAssetManifest", withExtension: "json")
        }
        assetURLProvider = { filename in
            let fileURL = URL(fileURLWithPath: filename)
            return bundle.url(
                forResource: fileURL.deletingPathExtension().lastPathComponent,
                withExtension: fileURL.pathExtension
            )
        }
    }

    init(manifestURL: URL?, assetDirectoryURL: URL) {
        manifestURLProvider = { manifestURL }
        assetURLProvider = { filename in
            let url = assetDirectoryURL.appendingPathComponent(filename)
            return FileManager.default.fileExists(atPath: url.path) ? url : nil
        }
    }

    func prepare() throws {
        guard !isPrepared else { return }
        guard let manifestURL = manifestURLProvider() else {
            throw AudioAssetLibraryError.missingManifest
        }

        let manifestData: Data
        do {
            manifestData = try Data(contentsOf: manifestURL)
            metrics.manifestReadCount += 1
        } catch {
            throw AudioAssetLibraryError.missingManifest
        }

        let decodedManifest: AudioAssetManifest
        do {
            decodedManifest = try JSONDecoder().decode(AudioAssetManifest.self, from: manifestData)
        } catch {
            throw AudioAssetLibraryError.invalidManifest(error.localizedDescription)
        }
        try validateManifest(decodedManifest)

        var preparedBuffers: [AudioAssetRole: AVAudioPCMBuffer] = [:]
        var decodedPCMByteCount = 0
        for asset in decodedManifest.assets {
            guard let fileURL = assetURLProvider(asset.filename) else {
                throw AudioAssetLibraryError.missingFile(asset.filename)
            }

            let fileData: Data
            do {
                fileData = try Data(contentsOf: fileURL)
                metrics.fileReadCount += 1
            } catch {
                throw AudioAssetLibraryError.missingFile(asset.filename)
            }

            let actualHash = SHA256.hash(data: fileData)
                .map { String(format: "%02x", $0) }
                .joined()
            guard actualHash == asset.sha256.lowercased() else {
                throw AudioAssetLibraryError.hashMismatch(asset.filename)
            }

            guard let wave = WaveHeader(data: fileData),
                  wave.encoding == 1,
                  wave.sampleRate == asset.sampleRate,
                  wave.bitDepth == asset.bitDepth,
                  wave.channels == asset.channels,
                  wave.frameCount == asset.frameCount else {
                throw AudioAssetLibraryError.formatMismatch(asset.filename)
            }

            do {
                let file = try AVAudioFile(forReading: fileURL)
                guard file.length == AVAudioFramePosition(asset.frameCount),
                      Int(file.processingFormat.channelCount) == asset.channels else {
                    throw AudioAssetLibraryError.formatMismatch(asset.filename)
                }
                guard let buffer = AVAudioPCMBuffer(
                    pcmFormat: file.processingFormat,
                    frameCapacity: AVAudioFrameCount(asset.frameCount)
                ) else {
                    throw AudioAssetLibraryError.decodeFailure(asset.filename)
                }
                metrics.bufferAllocationCount += 1
                try file.read(into: buffer)
                metrics.decodeCount += 1
                guard buffer.frameLength == AVAudioFrameCount(asset.frameCount) else {
                    throw AudioAssetLibraryError.decodeFailure(asset.filename)
                }
                preparedBuffers[asset.role] = buffer
                decodedPCMByteCount += asset.frameCount * asset.channels * (asset.bitDepth / 8)
            } catch let error as AudioAssetLibraryError {
                throw error
            } catch {
                throw AudioAssetLibraryError.decodeFailure(asset.filename)
            }
        }

        guard decodedPCMByteCount <= 8 * 1_024 * 1_024 else {
            throw AudioAssetLibraryError.invalidManifest("decoded PCM exceeds 8 MiB")
        }
        manifest = decodedManifest
        buffers = preparedBuffers
        metrics.decodedPCMByteCount = decodedPCMByteCount
    }

    func buffer(for role: AudioAssetRole) throws -> AVAudioPCMBuffer {
        guard let buffer = buffers[role] else {
            throw AudioAssetLibraryError.decodeFailure(role.rawValue)
        }
        return buffer
    }

    private func validateManifest(_ manifest: AudioAssetManifest) throws {
        guard manifest.schemaVersion == 1,
              manifest.format.sampleRate == 48_000,
              manifest.format.bitDepth == 16,
              manifest.format.encoding == "signed-integer-pcm-little-endian" else {
            throw AudioAssetLibraryError.invalidManifest("unsupported schema or common format")
        }

        var roles = Set<AudioAssetRole>()
        for asset in manifest.assets {
            guard roles.insert(asset.role).inserted else {
                throw AudioAssetLibraryError.duplicateRole(asset.role.rawValue)
            }
            guard asset.filename == "\(asset.role.rawValue).wav",
                  asset.sampleRate == manifest.format.sampleRate,
                  asset.bitDepth == manifest.format.bitDepth,
                  asset.channels == asset.role.expectedChannels,
                  asset.loop == asset.role.expectedLoop,
                  asset.frameCount > 0,
                  asset.durationSeconds.isFinite,
                  asset.durationSeconds > 0,
                  asset.role.expectedDuration.contains(asset.durationSeconds),
                  abs(
                    asset.durationSeconds
                        - Double(asset.frameCount) / Double(asset.sampleRate)
                  ) <= 1 / Double(asset.sampleRate),
                  asset.sha256.count == 64 else {
                throw AudioAssetLibraryError.invalidManifest("invalid contract for \(asset.role.rawValue)")
            }
        }

        guard roles == Set(AudioAssetRole.allCases) else {
            throw AudioAssetLibraryError.roleSetMismatch
        }
    }
}

private extension AudioAssetRole {
    var expectedChannels: Int {
        switch self {
        case .hubAmbienceLoop, .maintenanceAmbienceLoop:
            return 2
        default:
            return 1
        }
    }

    var expectedLoop: Bool {
        switch self {
        case .engineIdleLoop,
             .engineMidLoop,
             .engineHighLoop,
             .roadLoop,
             .windLoop,
             .tireScrubLoop,
             .hubAmbienceLoop,
             .maintenanceAmbienceLoop:
            return true
        default:
            return false
        }
    }

    var expectedDuration: ClosedRange<Double> {
        switch self {
        case .engineIdleLoop,
             .engineMidLoop,
             .engineHighLoop,
             .roadLoop,
             .windLoop,
             .tireScrubLoop:
            return 1...4
        case .nearMissWhoosh:
            return 0.08...1
        case .collisionImpact:
            return 0.10...1
        case .countdownTick:
            return 0.05...0.35
        case .goBassHit, .driveTransition:
            return 0.10...0.80
        case .hubAmbienceLoop, .maintenanceAmbienceLoop:
            return 2...8
        case .vehicleSelect, .colorSelect:
            return 0.03...0.50
        }
    }
}

private struct WaveHeader {
    let encoding: Int
    let channels: Int
    let sampleRate: Int
    let bitDepth: Int
    let frameCount: Int

    init?(data: Data) {
        let bytes = [UInt8](data)
        guard bytes.count >= 44,
              String(bytes: bytes[0..<4], encoding: .ascii) == "RIFF",
              String(bytes: bytes[8..<12], encoding: .ascii) == "WAVE" else {
            return nil
        }

        var offset = 12
        var format: (encoding: Int, channels: Int, sampleRate: Int, bitDepth: Int)?
        var dataByteCount: Int?
        while offset + 8 <= bytes.count {
            let identifier = String(bytes: bytes[offset..<(offset + 4)], encoding: .ascii)
            let size = Int(Self.uint32(bytes, offset + 4))
            let payload = offset + 8
            guard size >= 0, payload + size <= bytes.count else { return nil }
            if identifier == "fmt ", size >= 16 {
                format = (
                    Int(Self.uint16(bytes, payload)),
                    Int(Self.uint16(bytes, payload + 2)),
                    Int(Self.uint32(bytes, payload + 4)),
                    Int(Self.uint16(bytes, payload + 14))
                )
            } else if identifier == "data" {
                dataByteCount = size
            }
            offset = payload + size + (size % 2)
        }

        guard let format,
              let dataByteCount,
              format.channels > 0,
              format.bitDepth > 0 else {
            return nil
        }
        let bytesPerFrame = format.channels * format.bitDepth / 8
        guard bytesPerFrame > 0, dataByteCount % bytesPerFrame == 0 else { return nil }
        encoding = format.encoding
        channels = format.channels
        sampleRate = format.sampleRate
        bitDepth = format.bitDepth
        frameCount = dataByteCount / bytesPerFrame
    }

    private static func uint16(_ bytes: [UInt8], _ offset: Int) -> UInt16 {
        UInt16(bytes[offset]) | UInt16(bytes[offset + 1]) << 8
    }

    private static func uint32(_ bytes: [UInt8], _ offset: Int) -> UInt32 {
        UInt32(bytes[offset])
            | UInt32(bytes[offset + 1]) << 8
            | UInt32(bytes[offset + 2]) << 16
            | UInt32(bytes[offset + 3]) << 24
    }
}
