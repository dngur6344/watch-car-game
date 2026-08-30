#!/usr/bin/env -S xcrun swift

import Foundation

private let sampleRate = 48_000
private let bitDepth = 16
private let authoringVersion = "1.0.0"
private let creationDate = "2026-08-29"
private let licenseDeclaration = "Project-original; all rights held by the Watch Car Racer project owner."
private let sourceDeclaration = "Repository-authored deterministic oscillator, noise, and envelope recipe; no external source material."

private enum Recipe: String {
    case engineIdle = "Layered 55/110/165 Hz motor harmonics, slow amplitude modulation, and low-passed seeded mechanical noise."
    case engineMid = "Layered 90/180/270 Hz motor harmonics, pulse modulation, and seeded mechanical noise."
    case engineHigh = "Layered 140/280/420/700 Hz motor harmonics and bright seeded mechanical noise."
    case road = "Seeded low-passed surface noise layered with 34/68 Hz road rumble."
    case wind = "Seeded broadband air noise shaped by slow gust oscillators and a high-pass component."
    case tireScrub = "Seeded high-pass scrub noise with 620/930 Hz friction resonances."
    case nearMiss = "Fast attack/release seeded air-noise whoosh with a descending tonal edge."
    case collision = "Short seeded transient burst layered with decaying 43/86 Hz impact modes."
    case countdown = "Short 1320/1980 Hz synthesized tick with a seeded attack transient."
    case goBass = "Fast-attack descending 88-to-42 Hz bass hit with second harmonic and seeded transient."
    case hubAmbience = "Stereo 42/84 Hz garage drone, slow shimmer tones, and independent seeded air layers."
    case maintenanceAmbience = "Stereo 48/96 Hz workshop drone, alternating metallic partials, and seeded air layers."
    case vehicleSelect = "Fast 760/1140 Hz confirmation chirp with click transient."
    case colorSelect = "Fast 1040/1560 Hz color chirp with click transient."
    case driveTransition = "Rising synthesized tonal sweep layered with seeded air-noise transition."
}

private struct AssetSpec {
    let role: String
    let channels: Int
    let duration: Double
    let loop: Bool
    let targetPeak: Double
    let seed: UInt64
    let recipe: Recipe

    var filename: String { "\(role).wav" }
    var frameCount: Int { Int(duration * Double(sampleRate)) }
}

private let assets: [AssetSpec] = [
    AssetSpec(role: "engine_idle_loop", channels: 1, duration: 2.0, loop: true, targetPeak: 0.70, seed: 0x1001, recipe: .engineIdle),
    AssetSpec(role: "engine_mid_loop", channels: 1, duration: 2.0, loop: true, targetPeak: 0.72, seed: 0x1002, recipe: .engineMid),
    AssetSpec(role: "engine_high_loop", channels: 1, duration: 2.0, loop: true, targetPeak: 0.70, seed: 0x1003, recipe: .engineHigh),
    AssetSpec(role: "road_loop", channels: 1, duration: 2.0, loop: true, targetPeak: 0.58, seed: 0x1004, recipe: .road),
    AssetSpec(role: "wind_loop", channels: 1, duration: 2.0, loop: true, targetPeak: 0.54, seed: 0x1005, recipe: .wind),
    AssetSpec(role: "tire_scrub_loop", channels: 1, duration: 2.0, loop: true, targetPeak: 0.62, seed: 0x1006, recipe: .tireScrub),
    AssetSpec(role: "near_miss_whoosh", channels: 1, duration: 0.45, loop: false, targetPeak: 0.78, seed: 0x2001, recipe: .nearMiss),
    AssetSpec(role: "collision_impact", channels: 1, duration: 0.60, loop: false, targetPeak: 0.92, seed: 0x2002, recipe: .collision),
    AssetSpec(role: "countdown_tick", channels: 1, duration: 0.18, loop: false, targetPeak: 0.68, seed: 0x2003, recipe: .countdown),
    AssetSpec(role: "go_bass_hit", channels: 1, duration: 0.55, loop: false, targetPeak: 0.88, seed: 0x2004, recipe: .goBass),
    AssetSpec(role: "hub_ambience_loop", channels: 2, duration: 4.0, loop: true, targetPeak: 0.46, seed: 0x3001, recipe: .hubAmbience),
    AssetSpec(role: "maintenance_ambience_loop", channels: 2, duration: 4.0, loop: true, targetPeak: 0.48, seed: 0x3002, recipe: .maintenanceAmbience),
    AssetSpec(role: "vehicle_select", channels: 1, duration: 0.16, loop: false, targetPeak: 0.64, seed: 0x4001, recipe: .vehicleSelect),
    AssetSpec(role: "color_select", channels: 1, duration: 0.14, loop: false, targetPeak: 0.62, seed: 0x4002, recipe: .colorSelect),
    AssetSpec(role: "drive_transition", channels: 1, duration: 0.48, loop: false, targetPeak: 0.76, seed: 0x4003, recipe: .driveTransition),
]

private struct SeededNoise {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed == 0 ? 0x9e3779b97f4a7c15 : seed
    }

    mutating func next() -> Double {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        let normalized = Double(state >> 11) / Double(UInt64(1) << 53)
        return normalized * 2 - 1
    }
}

private func sine(_ frequency: Double, _ time: Double, phase: Double = 0) -> Double {
    sin(2 * Double.pi * frequency * time + phase)
}

private func smoothstep(_ value: Double) -> Double {
    let clamped = min(max(value, 0), 1)
    return clamped * clamped * (3 - 2 * clamped)
}

private func attackRelease(
    time: Double,
    duration: Double,
    attack: Double,
    release: Double
) -> Double {
    let attackGain = smoothstep(time / attack)
    let releaseGain = smoothstep((duration - time) / release)
    return min(attackGain, releaseGain)
}

private func noiseLayers(count: Int, seed: UInt64) -> (raw: [Double], low: [Double]) {
    var generator = SeededNoise(seed: seed)
    var raw = [Double](repeating: 0, count: count)
    var low = [Double](repeating: 0, count: count)
    var previous = 0.0

    for index in 0..<count {
        let value = generator.next()
        previous += 0.035 * (value - previous)
        raw[index] = value
        low[index] = previous
    }
    return (raw, low)
}

private func renderedChannel(for spec: AssetSpec, channel: Int) -> [Double] {
    let count = spec.frameCount
    let channelSeed = spec.seed &+ UInt64(channel) &* 0x9e3779b97f4a7c15
    let noise = noiseLayers(count: count, seed: channelSeed)
    let channelPhase = channel == 0 ? 0.0 : Double.pi * 0.63
    var samples = [Double](repeating: 0, count: count)

    for index in 0..<count {
        let time = Double(index) / Double(sampleRate)
        let progress = time / spec.duration
        let sample: Double

        switch spec.recipe {
        case .engineIdle:
            let pulse = 0.88 + 0.12 * sine(2, time)
            sample = pulse * (
                0.62 * sine(55, time)
                    + 0.26 * sine(110, time, phase: 0.2)
                    + 0.12 * sine(165, time, phase: 0.5)
            ) + 0.14 * noise.low[index]
        case .engineMid:
            let pulse = 0.84 + 0.16 * sine(4, time, phase: 0.3)
            sample = pulse * (
                0.52 * sine(90, time)
                    + 0.29 * sine(180, time, phase: 0.25)
                    + 0.16 * sine(270, time, phase: 0.7)
            ) + 0.12 * noise.raw[index] + 0.10 * noise.low[index]
        case .engineHigh:
            sample = 0.45 * sine(140, time)
                + 0.26 * sine(280, time, phase: 0.2)
                + 0.14 * sine(420, time, phase: 0.6)
                + 0.07 * sine(700, time, phase: 0.9)
                + 0.17 * noise.raw[index]
        case .road:
            sample = 0.58 * noise.low[index]
                + 0.22 * noise.raw[index]
                + 0.22 * sine(34, time)
                + 0.10 * sine(68, time, phase: 0.7)
        case .wind:
            let gust = 0.58 + 0.22 * sine(0.5, time) + 0.12 * sine(1.5, time, phase: 0.8)
            sample = gust * (0.62 * noise.raw[index] + 0.24 * (noise.raw[index] - noise.low[index]))
        case .tireScrub:
            sample = 0.72 * (noise.raw[index] - noise.low[index])
                + 0.16 * sine(620, time, phase: 0.4)
                + 0.09 * sine(930, time)
        case .nearMiss:
            let envelope = attackRelease(time: time, duration: spec.duration, attack: 0.025, release: 0.16)
            sample = envelope * (
                0.76 * (noise.raw[index] - 0.55 * noise.low[index])
                    + 0.18 * sine(960 - 540 * progress, time)
            )
        case .collision:
            let body = exp(-7.2 * progress)
            let transient = exp(-34 * progress)
            sample = body * (0.66 * sine(43, time) + 0.24 * sine(86, time, phase: 0.4))
                + transient * (0.68 * noise.raw[index] + 0.28 * noise.low[index])
        case .countdown:
            let envelope = attackRelease(time: time, duration: spec.duration, attack: 0.003, release: 0.11)
            sample = envelope * (
                0.74 * sine(1320, time)
                    + 0.24 * sine(1980, time, phase: 0.2)
                    + 0.12 * noise.raw[index] * exp(-42 * time)
            )
        case .goBass:
            let frequencyStart = 88.0
            let frequencyEnd = 42.0
            let phase = 2 * Double.pi * (
                frequencyStart * time
                    + 0.5 * (frequencyEnd - frequencyStart) * time * time / spec.duration
            )
            let envelope = attackRelease(time: time, duration: spec.duration, attack: 0.008, release: 0.25)
            sample = envelope * (
                0.78 * sin(phase)
                    + 0.18 * sin(phase * 2 + 0.25)
                    + 0.16 * noise.low[index] * exp(-18 * time)
            )
        case .hubAmbience:
            let shimmer = channel == 0 ? 216.0 : 224.0
            sample = 0.38 * sine(42, time, phase: channelPhase)
                + 0.14 * sine(84, time, phase: 0.4 + channelPhase)
                + 0.08 * sine(shimmer, time, phase: 0.7)
                + 0.13 * noise.low[index]
        case .maintenanceAmbience:
            let metallic = channel == 0 ? 312.0 : 328.0
            sample = 0.34 * sine(48, time, phase: channelPhase)
                + 0.14 * sine(96, time, phase: 0.25 + channelPhase)
                + 0.08 * sine(metallic, time, phase: 0.6)
                + 0.11 * noise.low[index]
        case .vehicleSelect:
            let envelope = attackRelease(time: time, duration: spec.duration, attack: 0.003, release: 0.08)
            sample = envelope * (
                0.72 * sine(760, time)
                    + 0.24 * sine(1140, time, phase: 0.3)
                    + 0.10 * noise.raw[index] * exp(-52 * time)
            )
        case .colorSelect:
            let envelope = attackRelease(time: time, duration: spec.duration, attack: 0.002, release: 0.065)
            sample = envelope * (
                0.68 * sine(1040, time)
                    + 0.26 * sine(1560, time, phase: 0.35)
                    + 0.09 * noise.raw[index] * exp(-58 * time)
            )
        case .driveTransition:
            let frequencyStart = 190.0
            let frequencyEnd = 780.0
            let phase = 2 * Double.pi * (
                frequencyStart * time
                    + 0.5 * (frequencyEnd - frequencyStart) * time * time / spec.duration
            )
            let envelope = attackRelease(time: time, duration: spec.duration, attack: 0.025, release: 0.13)
            sample = envelope * (
                0.56 * sin(phase)
                    + 0.28 * noise.raw[index] * smoothstep(progress)
                    + 0.11 * sine(95, time)
            )
        }

        samples[index] = sample
    }

    if spec.loop {
        makeLoopBoundaryDeterministic(&samples)
    } else if !samples.isEmpty {
        samples[0] = 0
        samples[samples.count - 1] = 0
    }
    return samples
}

private func makeLoopBoundaryDeterministic(_ samples: inout [Double]) {
    let seamFrames = sampleRate / 100
    guard samples.count >= seamFrames * 3 else { return }

    var tile = Array(samples[0..<seamFrames])
    let cyclicBlendFrames = 64
    for index in 0..<cyclicBlendFrames {
        let destination = seamFrames - cyclicBlendFrames + index
        let amount = smoothstep(Double(index + 1) / Double(cyclicBlendFrames + 1))
        tile[destination] = tile[destination] * (1 - amount) + tile[index] * amount
    }

    for index in 0..<seamFrames {
        samples[index] = tile[index]

        let startBlend = smoothstep(Double(index) / Double(seamFrames - 1))
        let startDestination = seamFrames + index
        samples[startDestination] = tile[index] * (1 - startBlend)
            + samples[startDestination] * startBlend

        let endBlend = smoothstep(Double(index) / Double(seamFrames - 1))
        let endTransition = samples.count - seamFrames * 2 + index
        samples[endTransition] = samples[endTransition] * (1 - endBlend)
            + tile[index] * endBlend

        samples[samples.count - seamFrames + index] = tile[index]
    }
}

private func normalizedPCM(for spec: AssetSpec) -> [[Int16]] {
    var channels = (0..<spec.channels).map { renderedChannel(for: spec, channel: $0) }

    for channel in channels.indices {
        let mean = channels[channel].reduce(0, +) / Double(channels[channel].count)
        for index in channels[channel].indices {
            channels[channel][index] -= mean
        }
    }

    let peak = channels.flatMap { $0 }.map(abs).max() ?? 1
    let scale = peak > 0 ? spec.targetPeak / peak : 1
    return channels.map { channel in
        channel.map { sample in
            let normalized = min(max(sample * scale, -0.98), 0.98)
            return Int16((normalized * Double(Int16.max)).rounded())
        }
    }
}

private func appendLittleEndian<T: FixedWidthInteger>(_ value: T, to data: inout Data) {
    var littleEndian = value.littleEndian
    withUnsafeBytes(of: &littleEndian) { data.append(contentsOf: $0) }
}

private func waveData(channels: [[Int16]]) -> Data {
    let channelCount = channels.count
    let frameCount = channels.first?.count ?? 0
    let bytesPerSample = bitDepth / 8
    let dataByteCount = frameCount * channelCount * bytesPerSample
    var data = Data()

    data.append(contentsOf: "RIFF".utf8)
    appendLittleEndian(UInt32(36 + dataByteCount), to: &data)
    data.append(contentsOf: "WAVE".utf8)
    data.append(contentsOf: "fmt ".utf8)
    appendLittleEndian(UInt32(16), to: &data)
    appendLittleEndian(UInt16(1), to: &data)
    appendLittleEndian(UInt16(channelCount), to: &data)
    appendLittleEndian(UInt32(sampleRate), to: &data)
    appendLittleEndian(UInt32(sampleRate * channelCount * bytesPerSample), to: &data)
    appendLittleEndian(UInt16(channelCount * bytesPerSample), to: &data)
    appendLittleEndian(UInt16(bitDepth), to: &data)
    data.append(contentsOf: "data".utf8)
    appendLittleEndian(UInt32(dataByteCount), to: &data)

    for frame in 0..<frameCount {
        for channel in 0..<channelCount {
            appendLittleEndian(UInt16(bitPattern: channels[channel][frame]), to: &data)
        }
    }
    return data
}

private struct SHA256 {
    private static let initial: [UInt32] = [
        0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a,
        0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19,
    ]
    private static let constants: [UInt32] = [
        0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5,
        0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
        0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3,
        0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
        0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc,
        0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
        0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7,
        0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
        0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13,
        0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
        0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3,
        0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
        0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5,
        0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
        0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208,
        0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
    ]

    static func hexDigest(_ data: Data) -> String {
        var bytes = [UInt8](data)
        let bitLength = UInt64(bytes.count) * 8
        bytes.append(0x80)
        while bytes.count % 64 != 56 {
            bytes.append(0)
        }
        for shift in stride(from: 56, through: 0, by: -8) {
            bytes.append(UInt8((bitLength >> UInt64(shift)) & 0xff))
        }

        var hash = initial
        for offset in stride(from: 0, to: bytes.count, by: 64) {
            var words = [UInt32](repeating: 0, count: 64)
            for index in 0..<16 {
                let base = offset + index * 4
                words[index] = UInt32(bytes[base]) << 24
                    | UInt32(bytes[base + 1]) << 16
                    | UInt32(bytes[base + 2]) << 8
                    | UInt32(bytes[base + 3])
            }
            for index in 16..<64 {
                let s0 = rotateRight(words[index - 15], by: 7)
                    ^ rotateRight(words[index - 15], by: 18)
                    ^ (words[index - 15] >> 3)
                let s1 = rotateRight(words[index - 2], by: 17)
                    ^ rotateRight(words[index - 2], by: 19)
                    ^ (words[index - 2] >> 10)
                words[index] = words[index - 16] &+ s0 &+ words[index - 7] &+ s1
            }

            var a = hash[0]
            var b = hash[1]
            var c = hash[2]
            var d = hash[3]
            var e = hash[4]
            var f = hash[5]
            var g = hash[6]
            var h = hash[7]
            for index in 0..<64 {
                let sum1 = rotateRight(e, by: 6) ^ rotateRight(e, by: 11) ^ rotateRight(e, by: 25)
                let choice = (e & f) ^ ((~e) & g)
                let temporary1 = h &+ sum1 &+ choice &+ constants[index] &+ words[index]
                let sum0 = rotateRight(a, by: 2) ^ rotateRight(a, by: 13) ^ rotateRight(a, by: 22)
                let majority = (a & b) ^ (a & c) ^ (b & c)
                let temporary2 = sum0 &+ majority
                h = g
                g = f
                f = e
                e = d &+ temporary1
                d = c
                c = b
                b = a
                a = temporary1 &+ temporary2
            }
            hash[0] &+= a
            hash[1] &+= b
            hash[2] &+= c
            hash[3] &+= d
            hash[4] &+= e
            hash[5] &+= f
            hash[6] &+= g
            hash[7] &+= h
        }
        return hash.map { String(format: "%08x", $0) }.joined()
    }

    private static func rotateRight(_ value: UInt32, by amount: UInt32) -> UInt32 {
        (value >> amount) | (value << (32 - amount))
    }
}

private struct RenderedAsset {
    let spec: AssetSpec
    let sha256: String
}

private func escapedJSON(_ value: String) -> String {
    value
        .replacingOccurrences(of: "\\", with: "\\\\")
        .replacingOccurrences(of: "\"", with: "\\\"")
        .replacingOccurrences(of: "\n", with: "\\n")
}

private func manifestData(for rendered: [RenderedAsset]) -> Data {
    var lines = [
        "{",
        "  \"schemaVersion\": 1,",
        "  \"authoring\": {",
        "    \"tool\": \"Scripts/build_original_audio_assets.swift\",",
        "    \"version\": \"\(authoringVersion)\",",
        "    \"creationDate\": \"\(creationDate)\",",
        "    \"method\": \"Deterministic offline layered oscillator, seeded-noise, and envelope rendering.\"",
        "  },",
        "  \"format\": {",
        "    \"sampleRate\": \(sampleRate),",
        "    \"bitDepth\": \(bitDepth),",
        "    \"encoding\": \"signed-integer-pcm-little-endian\"",
        "  },",
        "  \"assets\": [",
    ]

    for (index, asset) in rendered.enumerated() {
        let suffix = index == rendered.count - 1 ? "" : ","
        lines.append(contentsOf: [
            "    {",
            "      \"role\": \"\(escapedJSON(asset.spec.role))\",",
            "      \"filename\": \"\(escapedJSON(asset.spec.filename))\",",
            "      \"sampleRate\": \(sampleRate),",
            "      \"bitDepth\": \(bitDepth),",
            "      \"channels\": \(asset.spec.channels),",
            "      \"frameCount\": \(asset.spec.frameCount),",
            "      \"durationSeconds\": \(String(format: "%.3f", asset.spec.duration)),",
            "      \"loop\": \(asset.spec.loop),",
            "      \"license\": \"\(escapedJSON(licenseDeclaration))\",",
            "      \"source\": \"\(escapedJSON(sourceDeclaration))\",",
            "      \"recipe\": \"\(escapedJSON(asset.spec.recipe.rawValue))\",",
            "      \"authoringVersion\": \"\(authoringVersion)\",",
            "      \"sha256\": \"\(asset.sha256)\"",
            "    }\(suffix)",
        ])
    }
    lines.append(contentsOf: ["  ]", "}"])
    return Data((lines.joined(separator: "\n") + "\n").utf8)
}

private func outputDirectory() throws -> URL {
    let arguments = Array(CommandLine.arguments.dropFirst())
    if arguments.isEmpty {
        return URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("WatchCarRacer/iOS/Resources/Audio", isDirectory: true)
    }
    guard arguments.count == 2, arguments[0] == "--output" else {
        throw NSError(
            domain: "OriginalAudioAuthoring",
            code: 2,
            userInfo: [NSLocalizedDescriptionKey: "Usage: build_original_audio_assets.swift [--output DIRECTORY]"]
        )
    }
    return URL(fileURLWithPath: arguments[1], isDirectory: true)
}

private func main() throws {
    let destination = try outputDirectory()
    try FileManager.default.createDirectory(
        at: destination,
        withIntermediateDirectories: true
    )

    var rendered = [RenderedAsset]()
    for spec in assets {
        let data = waveData(channels: normalizedPCM(for: spec))
        let sha256 = SHA256.hexDigest(data)
        try data.write(to: destination.appendingPathComponent(spec.filename), options: .atomic)
        rendered.append(RenderedAsset(spec: spec, sha256: sha256))
        print("\(spec.role) \(spec.filename) \(sha256)")
    }

    let manifest = manifestData(for: rendered)
    try manifest.write(
        to: destination.appendingPathComponent("AudioAssetManifest.json"),
        options: .atomic
    )
    print("manifest AudioAssetManifest.json \(SHA256.hexDigest(manifest))")
}

do {
    try main()
} catch {
    FileHandle.standardError.write(Data("error: \(error.localizedDescription)\n".utf8))
    exit(1)
}
