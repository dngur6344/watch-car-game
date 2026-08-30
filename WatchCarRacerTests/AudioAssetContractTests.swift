import CryptoKit
import Foundation
import XCTest

final class AudioAssetContractTests: XCTestCase {
    func testManifestDefinesExactlyOnceAllStableRoleContractsAndProvenance() throws {
        let manifest = try sourceManifest()
        let provenance = try String(
            contentsOf: repositoryRoot.appendingPathComponent("docs/assets/provenance.md"),
            encoding: .utf8
        )

        XCTAssertEqual(manifest.schemaVersion, 1)
        XCTAssertEqual(manifest.authoring.tool, "Scripts/build_original_audio_assets.swift")
        XCTAssertEqual(manifest.authoring.version, "1.0.0")
        XCTAssertEqual(manifest.authoring.creationDate, "2026-08-29")
        XCTAssertEqual(manifest.format.sampleRate, 48_000)
        XCTAssertEqual(manifest.format.bitDepth, 16)
        XCTAssertEqual(manifest.format.encoding, "signed-integer-pcm-little-endian")
        XCTAssertEqual(manifest.assets.count, expectedContracts.count)
        XCTAssertEqual(Set(manifest.assets.map(\.role)), Set(expectedContracts.keys))
        XCTAssertEqual(Set(manifest.assets.map(\.filename)).count, expectedContracts.count)

        for asset in manifest.assets {
            let contract = try XCTUnwrap(expectedContracts[asset.role], asset.role)
            XCTAssertEqual(asset.filename, "\(asset.role).wav", asset.role)
            XCTAssertEqual(asset.sampleRate, 48_000, asset.role)
            XCTAssertEqual(asset.bitDepth, 16, asset.role)
            XCTAssertEqual(asset.channels, contract.channels, asset.role)
            XCTAssertEqual(asset.loop, contract.loop, asset.role)
            XCTAssertTrue(contract.duration.contains(asset.durationSeconds), asset.role)
            XCTAssertEqual(
                asset.frameCount,
                Int(asset.durationSeconds * Double(asset.sampleRate)),
                asset.role
            )
            XCTAssertFalse(asset.license.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            XCTAssertFalse(asset.source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            XCTAssertFalse(asset.recipe.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            XCTAssertEqual(asset.authoringVersion, manifest.authoring.version)

            let url = audioDirectory.appendingPathComponent(asset.filename)
            let data = try Data(contentsOf: url)
            XCTAssertFalse(data.isEmpty, asset.filename)
            let actualSHA = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            XCTAssertEqual(asset.sha256, actualSHA, asset.filename)
            XCTAssertTrue(provenance.contains("`Audio/\(asset.filename)`"), asset.filename)
            XCTAssertTrue(provenance.contains("`\(actualSHA)`"), asset.filename)
        }
    }

    func testEveryWaveIs48kSigned16BitPCMAndMeetsLevelAndSizeContracts() throws {
        let manifest = try sourceManifest()
        var totalDecodedPCMBytes = 0

        for asset in manifest.assets {
            let fixture = try WAVFixture(
                data: Data(contentsOf: audioDirectory.appendingPathComponent(asset.filename))
            )
            XCTAssertEqual(fixture.audioFormat, 1, asset.filename)
            XCTAssertEqual(fixture.sampleRate, 48_000, asset.filename)
            XCTAssertEqual(fixture.bitDepth, 16, asset.filename)
            XCTAssertEqual(fixture.channels, asset.channels, asset.filename)
            XCTAssertEqual(fixture.frameCount, asset.frameCount, asset.filename)
            XCTAssertEqual(
                fixture.duration,
                asset.durationSeconds,
                accuracy: 1 / Double(fixture.sampleRate),
                asset.filename
            )
            XCTAssertFalse(fixture.samples.isEmpty, asset.filename)
            XCTAssertTrue((0.05...0.98).contains(fixture.normalizedPeak), asset.filename)
            for dcOffset in fixture.absoluteDCOffsets {
                XCTAssertLessThanOrEqual(dcOffset, 0.01, asset.filename)
            }
            totalDecodedPCMBytes += fixture.decodedPCMByteCount
        }

        XCTAssertLessThanOrEqual(totalDecodedPCMBytes, 8 * 1_024 * 1_024)
    }

    func testEveryLoopMeetsTenMillisecondSeamContract() throws {
        let manifest = try sourceManifest()
        let loops = manifest.assets.filter(\.loop)
        XCTAssertEqual(loops.count, 8)

        for asset in loops {
            let fixture = try WAVFixture(
                data: Data(contentsOf: audioDirectory.appendingPathComponent(asset.filename))
            )
            for channel in 0..<fixture.channels {
                let metrics = fixture.seamMetrics(channel: channel, frames: fixture.sampleRate / 100)
                XCTAssertLessThanOrEqual(metrics.meanAbsoluteDifference, 0.08, asset.filename)
                XCTAssertLessThanOrEqual(metrics.rmsDifference, 0.05, asset.filename)
            }
        }
    }

    func testAudioResourcesAreRegisteredOnlyInIOSAndResolveFromBuiltHostBundle() throws {
        let manifest = try sourceManifest()
        let project = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "WatchCarRacer.xcodeproj/project.pbxproj"
            ),
            encoding: .utf8
        )
        let iosResources = try XCTUnwrap(
            project.pbxBlock(startingWith: "050000000000000000000003 /* Resources */ = {")
        )
        let watchResources = try XCTUnwrap(
            project.pbxBlock(startingWith: "050000000000000000000013 /* Resources */ = {")
        )

        XCTAssertTrue(iosResources.contains("AudioAssetManifest.json in Resources"))
        XCTAssertFalse(watchResources.contains("AudioAssetManifest"))
        XCTAssertNotNil(Bundle.main.url(forResource: "AudioAssetManifest", withExtension: "json"))

        for asset in manifest.assets {
            XCTAssertTrue(iosResources.contains("\(asset.filename) in Resources"), asset.filename)
            XCTAssertFalse(watchResources.contains(asset.filename), asset.filename)
            XCTAssertNotNil(
                Bundle.main.url(
                    forResource: URL(fileURLWithPath: asset.filename).deletingPathExtension().lastPathComponent,
                    withExtension: "wav"
                ),
                asset.filename
            )
        }
    }

    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private var audioDirectory: URL {
        repositoryRoot.appendingPathComponent("WatchCarRacer/iOS/Resources/Audio")
    }

    private func sourceManifest() throws -> AudioManifestFixture {
        let data = try Data(
            contentsOf: audioDirectory.appendingPathComponent("AudioAssetManifest.json")
        )
        return try JSONDecoder().decode(AudioManifestFixture.self, from: data)
    }

    private var expectedContracts: [String: AudioRoleContract] {
        [
            "engine_idle_loop": .init(channels: 1, duration: 1.0...4.0, loop: true),
            "engine_mid_loop": .init(channels: 1, duration: 1.0...4.0, loop: true),
            "engine_high_loop": .init(channels: 1, duration: 1.0...4.0, loop: true),
            "road_loop": .init(channels: 1, duration: 1.0...4.0, loop: true),
            "wind_loop": .init(channels: 1, duration: 1.0...4.0, loop: true),
            "tire_scrub_loop": .init(channels: 1, duration: 1.0...4.0, loop: true),
            "near_miss_whoosh": .init(channels: 1, duration: 0.08...1.0, loop: false),
            "collision_impact": .init(channels: 1, duration: 0.10...1.0, loop: false),
            "countdown_tick": .init(channels: 1, duration: 0.05...0.35, loop: false),
            "go_bass_hit": .init(channels: 1, duration: 0.10...0.80, loop: false),
            "hub_ambience_loop": .init(channels: 2, duration: 2.0...8.0, loop: true),
            "maintenance_ambience_loop": .init(channels: 2, duration: 2.0...8.0, loop: true),
            "vehicle_select": .init(channels: 1, duration: 0.03...0.50, loop: false),
            "color_select": .init(channels: 1, duration: 0.03...0.50, loop: false),
            "drive_transition": .init(channels: 1, duration: 0.10...0.80, loop: false),
        ]
    }
}

private struct AudioRoleContract {
    let channels: Int
    let duration: ClosedRange<Double>
    let loop: Bool
}

private struct AudioManifestFixture: Decodable {
    struct Authoring: Decodable {
        let tool: String
        let version: String
        let creationDate: String
        let method: String
    }

    struct Format: Decodable {
        let sampleRate: Int
        let bitDepth: Int
        let encoding: String
    }

    struct Asset: Decodable {
        let role: String
        let filename: String
        let sampleRate: Int
        let bitDepth: Int
        let channels: Int
        let frameCount: Int
        let durationSeconds: Double
        let loop: Bool
        let license: String
        let source: String
        let recipe: String
        let authoringVersion: String
        let sha256: String
    }

    let schemaVersion: Int
    let authoring: Authoring
    let format: Format
    let assets: [Asset]
}

private struct WAVFixture {
    let audioFormat: Int
    let channels: Int
    let sampleRate: Int
    let bitDepth: Int
    let samples: [Int16]
    let decodedPCMByteCount: Int

    init(data: Data) throws {
        let bytes = [UInt8](data)
        guard bytes.count >= 44,
              String(bytes: bytes[0..<4], encoding: .ascii) == "RIFF",
              String(bytes: bytes[8..<12], encoding: .ascii) == "WAVE" else {
            throw CocoaError(.fileReadCorruptFile)
        }

        var parsedAudioFormat: Int?
        var parsedChannels: Int?
        var parsedSampleRate: Int?
        var parsedBitDepth: Int?
        var pcmRange: Range<Int>?
        var offset = 12

        while offset + 8 <= bytes.count {
            let chunkID = String(bytes: bytes[offset..<(offset + 4)], encoding: .ascii)
            let chunkSize = Int(Self.uint32(bytes, offset + 4))
            let payloadStart = offset + 8
            let payloadEnd = payloadStart + chunkSize
            guard payloadEnd <= bytes.count else {
                throw CocoaError(.fileReadCorruptFile)
            }
            if chunkID == "fmt ", chunkSize >= 16 {
                parsedAudioFormat = Int(Self.uint16(bytes, payloadStart))
                parsedChannels = Int(Self.uint16(bytes, payloadStart + 2))
                parsedSampleRate = Int(Self.uint32(bytes, payloadStart + 4))
                parsedBitDepth = Int(Self.uint16(bytes, payloadStart + 14))
            } else if chunkID == "data" {
                pcmRange = payloadStart..<payloadEnd
            }
            offset = payloadEnd + chunkSize % 2
        }

        guard let parsedAudioFormat,
              let parsedChannels,
              let parsedSampleRate,
              let parsedBitDepth,
              parsedAudioFormat == 1,
              parsedChannels > 0,
              parsedBitDepth == 16,
              let pcmRange,
              pcmRange.count % 2 == 0 else {
            throw CocoaError(.fileReadCorruptFile)
        }

        var decoded = [Int16]()
        decoded.reserveCapacity(pcmRange.count / 2)
        for index in stride(from: pcmRange.lowerBound, to: pcmRange.upperBound, by: 2) {
            decoded.append(Int16(bitPattern: Self.uint16(bytes, index)))
        }
        guard decoded.count % parsedChannels == 0 else {
            throw CocoaError(.fileReadCorruptFile)
        }

        audioFormat = parsedAudioFormat
        channels = parsedChannels
        sampleRate = parsedSampleRate
        bitDepth = parsedBitDepth
        samples = decoded
        decodedPCMByteCount = pcmRange.count
    }

    var frameCount: Int { samples.count / channels }
    var duration: Double { Double(frameCount) / Double(sampleRate) }

    var normalizedPeak: Double {
        (samples.map { abs(Double($0)) }.max() ?? 0) / 32_768
    }

    var absoluteDCOffsets: [Double] {
        (0..<channels).map { channel in
            let values = stride(from: channel, to: samples.count, by: channels).map {
                Double(samples[$0]) / 32_768
            }
            return abs(values.reduce(0, +) / Double(values.count))
        }
    }

    func seamMetrics(channel: Int, frames: Int) -> (
        meanAbsoluteDifference: Double,
        rmsDifference: Double
    ) {
        let start = (0..<frames).map { frame in
            Double(samples[frame * channels + channel]) / 32_768
        }
        let end = ((frameCount - frames)..<frameCount).map { frame in
            Double(samples[frame * channels + channel]) / 32_768
        }
        let differences = zip(start, end).map(-)
        let meanAbsolute = differences.map(abs).reduce(0, +) / Double(frames)
        let rms = sqrt(differences.map { $0 * $0 }.reduce(0, +) / Double(frames))
        return (meanAbsolute, rms)
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

private extension String {
    func pbxBlock(startingWith marker: String) -> String? {
        guard let start = range(of: marker)?.lowerBound,
              let end = self[start...].range(of: "\n\t\t};")?.upperBound else {
            return nil
        }
        return String(self[start..<end])
    }
}
