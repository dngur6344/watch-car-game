#!/usr/bin/env swift

import CoreGraphics
import CryptoKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

private let toolVersion = "1.0.0"
private let outputDimension = 1024
private let quadrantDimension = 512
private let sourceCropOrigin = 27
private let sourceCropDimension = 1200
private let edgeBlendPixels = 36

private enum BuildError: Error, CustomStringConvertible {
    case usage
    case unreadableManifest(URL)
    case invalidManifest(String)
    case unreadableImage(URL)
    case sourceHashMismatch(filename: String, expected: String, actual: String)
    case sourceDimensionMismatch(filename: String, expected: String, actual: String)
    case contextCreation
    case imageCreation
    case destinationCreation(URL)
    case destinationFinalize(URL)
    case missingOutput(URL)
    case outputMismatch(String)

    var description: String {
        switch self {
        case .usage:
            return "usage: build_racing_environment_pbr_maps.swift [build|validate] <source-directory> <output-directory> <manifest.json>"
        case let .unreadableManifest(url):
            return "unable to decode environment manifest: \(url.path)"
        case let .invalidManifest(reason):
            return "invalid environment manifest: \(reason)"
        case let .unreadableImage(url):
            return "unable to read image: \(url.path)"
        case let .sourceHashMismatch(filename, expected, actual):
            return "source SHA-256 mismatch for \(filename): expected \(expected), got \(actual)"
        case let .sourceDimensionMismatch(filename, expected, actual):
            return "source dimension mismatch for \(filename): expected \(expected), got \(actual)"
        case .contextCreation:
            return "unable to create RGBA bitmap context"
        case .imageCreation:
            return "unable to create output CGImage"
        case let .destinationCreation(url):
            return "unable to create PNG destination: \(url.path)"
        case let .destinationFinalize(url):
            return "unable to finalize PNG destination: \(url.path)"
        case let .missingOutput(url):
            return "missing generated PBR map: \(url.path)"
        case let .outputMismatch(reason):
            return "generated PBR map contract mismatch: \(reason)"
        }
    }
}

private struct EnvironmentManifest: Decodable {
    struct Script: Decodable {
        let path: String
        let version: String
    }

    struct Authoring: Decodable {
        let scripts: [Script]
    }

    struct TextureContract: Decodable {
        let width: Int
        let height: Int
        let bitsPerComponent: Int
        let channels: String
        let atlasQuadrantSize: Int
        let expectedBaseLevelDecodedBytesPerTexture: Int
        let expectedBaseLevelDecodedBytesPerTrack: Int
        let expectedBaseLevelDecodedBytesAllTracks: Int
    }

    struct Source: Decodable {
        let trackID: String
        let assetSlug: String
        let filename: String
        let sha256: String
        let width: Int
        let height: Int
    }

    struct Texture: Decodable {
        let filename: String
        let channelRole: String
        let colorEncoding: String
        let realityKitSemantic: String
        let pixelFormat: String
        let width: Int
        let height: Int
        let expectedBaseLevelDecodedBytes: Int
        let derivedSHA256: String?
        let hashStatus: String
    }

    struct Quadrant: Decodable {
        let name: String
        let x: Int
        let y: Int
        let width: Int
        let height: Int
        let content: String
    }

    struct GeometryTier: Decodable {
        let rootName: String
        let tier: String
        let role: String
        let requiredLODRoots: [String]
        let materialSlots: [String]
        let sourceUSDA: String
        let runtimeUSDZ: String
        let sourceUSDASHA256: String?
        let runtimeUSDZSHA256: String?
        let hashStatus: String
    }

    struct Geometry: Decodable {
        let base: GeometryTier
        let enhanced: GeometryTier
    }

    struct Track: Decodable {
        let id: String
        let assetSlug: String
        let sourceFilename: String
        let variantEntityNames: [String]
        let heroEntityName: String
        let roadClearanceHalfWidth: Double
        let heroRoadApertureWidth: Double
        let geometry: Geometry
        let atlasQuadrants: [Quadrant]
        let textures: [Texture]
    }

    let schemaVersion: Int
    let revision: Int
    let license: String
    let hashAlgorithm: String
    let authoring: Authoring
    let textureContract: TextureContract
    let sources: [Source]
    let tracks: [Track]
}

private struct SourceSpec {
    let trackID: String
    let slug: String
    let filename: String
    let sha256: String
    let baseRoot: String
    let enhancedRoot: String
    let variants: [String]
    let hero: String
}

private enum TextureRole: String, CaseIterable {
    case baseColor
    case normal
    case roughness

    var filenameSuffix: String {
        switch self {
        case .baseColor: "terrain_basecolor.png"
        case .normal: "terrain_normal.png"
        case .roughness: "terrain_roughness.png"
        }
    }

    var manifestChannelRole: String {
        switch self {
        case .baseColor: "baseColor"
        case .normal: "tangentSpaceNormal"
        case .roughness: "roughnessScalarReplicatedRGBA"
        }
    }

    var colorEncoding: String {
        self == .baseColor ? "sRGB" : "linear-sRGB"
    }

    var semantic: String {
        switch self {
        case .baseColor: ".color"
        case .normal: ".normal"
        case .roughness: ".scalar"
        }
    }
}

private let sourceSpecs = [
    SourceSpec(
        trackID: "coastal",
        slug: "ocean",
        filename: "ocean_terrain_source.png",
        sha256: "fc62fba112a901ae41adfa497bbce2d889f1a32b432487074bfe650f65d42416",
        baseRoot: "OceanEnvironmentBase",
        enhancedRoot: "OceanEnvironmentEnhanced",
        variants: ["Coastal_ShorelineRock", "Coastal_PalmGrove", "Coastal_CliffOutcrop", "Coastal_SeaStack"],
        hero: "Coastal_CliffCove_Hero"
    ),
    SourceSpec(
        trackID: "alpine",
        slug: "alpine",
        filename: "alpine_terrain_source.png",
        sha256: "735c36b4ab5f958fcb7afc691c9303ceb8086bf138bfde9ed34d58b4d628fba7",
        baseRoot: "AlpineEnvironmentBase",
        enhancedRoot: "AlpineEnvironmentEnhanced",
        variants: ["Alpine_RockOutcrop", "Alpine_PineGrove", "Alpine_ForestBelt", "Alpine_SnowRidge"],
        hero: "Alpine_TunnelPeak_Hero"
    ),
    SourceSpec(
        trackID: "desert",
        slug: "desert",
        filename: "desert_terrain_source.png",
        sha256: "062c6cc3a963d7c161947af2ed913fd450e007af469fecf177432694792bab54",
        baseRoot: "DesertEnvironmentBase",
        enhancedRoot: "DesertEnvironmentEnhanced",
        variants: ["Desert_CactusCluster", "Desert_BoulderCluster", "Desert_CanyonWall", "Desert_Mesa"],
        hero: "Desert_StoneArch_Hero"
    ),
]

private struct Pixel {
    var red: Float
    var green: Float
    var blue: Float
    var alpha: Float

    static func mix(_ first: Pixel, _ second: Pixel, amount: Float) -> Pixel {
        let inverse = 1 - amount
        return Pixel(
            red: first.red * inverse + second.red * amount,
            green: first.green * inverse + second.green * amount,
            blue: first.blue * inverse + second.blue * amount,
            alpha: first.alpha * inverse + second.alpha * amount
        )
    }
}

private struct Raster {
    let width: Int
    let height: Int
    var pixels: [UInt8]

    init(width: Int, height: Int) {
        self.width = width
        self.height = height
        pixels = [UInt8](repeating: 0, count: width * height * 4)
    }

    init(contentsOf url: URL) throws {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw BuildError.unreadableImage(url)
        }
        width = image.width
        height = image.height
        pixels = [UInt8](repeating: 0, count: width * height * 4)
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                  data: &pixels,
                  width: width,
                  height: height,
                  bitsPerComponent: 8,
                  bytesPerRow: width * 4,
                  space: colorSpace,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else {
            throw BuildError.contextCreation
        }
        context.interpolationQuality = .none
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    }

    func pixel(x: Int, y: Int) -> Pixel {
        let clampedX = min(max(x, 0), width - 1)
        let clampedY = min(max(y, 0), height - 1)
        let offset = (clampedY * width + clampedX) * 4
        return Pixel(
            red: Float(pixels[offset]) / 255,
            green: Float(pixels[offset + 1]) / 255,
            blue: Float(pixels[offset + 2]) / 255,
            alpha: Float(pixels[offset + 3]) / 255
        )
    }

    func bilinearPixel(x: Float, y: Float) -> Pixel {
        let lowerX = Int(floor(x))
        let lowerY = Int(floor(y))
        let fractionX = x - Float(lowerX)
        let fractionY = y - Float(lowerY)
        let top = Pixel.mix(
            pixel(x: lowerX, y: lowerY),
            pixel(x: lowerX + 1, y: lowerY),
            amount: fractionX
        )
        let bottom = Pixel.mix(
            pixel(x: lowerX, y: lowerY + 1),
            pixel(x: lowerX + 1, y: lowerY + 1),
            amount: fractionX
        )
        return Pixel.mix(top, bottom, amount: fractionY)
    }

    func luminance(x: Int, y: Int, quadrantX: Int, quadrantY: Int) -> Float {
        let localX = (x % quadrantDimension + quadrantDimension) % quadrantDimension
        let localY = (y % quadrantDimension + quadrantDimension) % quadrantDimension
        let globalX = quadrantX * quadrantDimension + localX
        let globalY = quadrantY * quadrantDimension + localY
        let offset = (globalY * width + globalX) * 4
        return (
            Float(pixels[offset]) * 0.2126
                + Float(pixels[offset + 1]) * 0.7152
                + Float(pixels[offset + 2]) * 0.0722
        ) / 255
    }

    mutating func setPixel(x: Int, y: Int, _ pixel: Pixel) {
        let offset = (y * width + x) * 4
        pixels[offset] = byte(pixel.red)
        pixels[offset + 1] = byte(pixel.green)
        pixels[offset + 2] = byte(pixel.blue)
        pixels[offset + 3] = byte(pixel.alpha)
    }

    func writePNG(to url: URL, linear: Bool) throws {
        let colorSpaceName = linear ? CGColorSpace.linearSRGB : CGColorSpace.sRGB
        guard let colorSpace = CGColorSpace(name: colorSpaceName),
              let provider = CGDataProvider(data: Data(pixels) as CFData),
              let image = CGImage(
                  width: width,
                  height: height,
                  bitsPerComponent: 8,
                  bitsPerPixel: 32,
                  bytesPerRow: width * 4,
                  space: colorSpace,
                  bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                  provider: provider,
                  decode: nil,
                  shouldInterpolate: true,
                  intent: .defaultIntent
              ) else {
            throw BuildError.imageCreation
        }
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else {
            throw BuildError.destinationCreation(url)
        }
        let profileName = linear ? "Linear sRGB" : "sRGB IEC61966-2.1"
        CGImageDestinationAddImage(destination, image, [
            kCGImagePropertyColorModel: kCGImagePropertyColorModelRGB,
            kCGImagePropertyProfileName: profileName,
        ] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw BuildError.destinationFinalize(url)
        }
    }
}

private func byte(_ value: Float) -> UInt8 {
    UInt8(clamping: Int((min(max(value, 0), 1) * 255).rounded()))
}

private func wrapUnit(_ value: Float) -> Float {
    value - floor(value)
}

private func sourcePixel(
    source: Raster,
    u: Float,
    v: Float,
    scale: Float,
    offsetX: Float,
    offsetY: Float
) -> Pixel {
    let wrappedU = wrapUnit(u * scale + offsetX)
    let wrappedV = wrapUnit(v * scale + offsetY)
    let x = Float(sourceCropOrigin) + wrappedU * Float(sourceCropDimension - 1)
    let y = Float(sourceCropOrigin) + wrappedV * Float(sourceCropDimension - 1)
    return source.bilinearPixel(x: x, y: y)
}

private func edgeWeight(_ unit: Float) -> Float {
    let normalizedBlend = Float(edgeBlendPixels) / Float(quadrantDimension - 1)
    let distance = min(unit, 1 - unit)
    guard distance < normalizedBlend else { return 0 }
    return 0.5 * (1 - distance / normalizedBlend)
}

private func edgeWrappedPixel(
    source: Raster,
    u: Float,
    v: Float,
    scale: Float,
    offsetX: Float,
    offsetY: Float
) -> Pixel {
    var result = sourcePixel(
        source: source,
        u: u,
        v: v,
        scale: scale,
        offsetX: offsetX,
        offsetY: offsetY
    )
    let horizontalWeight = edgeWeight(u)
    if horizontalWeight > 0 {
        let opposite = sourcePixel(
            source: source,
            u: 1 - u,
            v: v,
            scale: scale,
            offsetX: offsetX,
            offsetY: offsetY
        )
        result = Pixel.mix(result, opposite, amount: horizontalWeight)
    }
    let verticalWeight = edgeWeight(v)
    if verticalWeight > 0 {
        let opposite = sourcePixel(
            source: source,
            u: u,
            v: 1 - v,
            scale: scale,
            offsetX: offsetX,
            offsetY: offsetY
        )
        result = Pixel.mix(result, opposite, amount: verticalWeight)
    }
    return result
}

private func smoothstep(_ lower: Float, _ upper: Float, _ value: Float) -> Float {
    let normalized = min(max((value - lower) / (upper - lower), 0), 1)
    return normalized * normalized * (3 - 2 * normalized)
}

private func tint(
    _ source: Pixel,
    slug: String,
    quadrant: Int,
    u: Float,
    v: Float
) -> Pixel {
    var result = source
    let macro = Float(sin(Double((u * 1.7 + v * 1.1) * 2 * .pi))) * 0.025
    let secondary = quadrant == 1
    let transition = quadrant == 2
    let decal = quadrant == 3

    switch slug {
    case "ocean":
        result.red = result.red * (secondary ? 0.91 : 1.02) + 0.018 + macro
        result.green = result.green * (secondary ? 0.95 : 1.00) + 0.012 + macro * 0.7
        result.blue = result.blue * (secondary ? 1.02 : 0.94) + macro * 0.35
        if transition {
            let damp = smoothstep(0.35, 0.78, v + Float(sin(Double(u * 7))) * 0.09)
            result = Pixel.mix(result, Pixel(red: 0.16, green: 0.23, blue: 0.22, alpha: 1), amount: damp * 0.38)
        } else if decal {
            let grass = smoothstep(0.74, 0.91, Float(sin(Double((u * 13 + v * 5) * .pi))) * 0.5 + 0.5)
            result = Pixel.mix(result, Pixel(red: 0.20, green: 0.34, blue: 0.20, alpha: 1), amount: grass * 0.58)
        }
    case "alpine":
        result.red = result.red * (secondary ? 0.86 : 0.93) + macro * 0.35
        result.green = result.green * (secondary ? 0.91 : 0.96) + macro * 0.45
        result.blue = result.blue * (secondary ? 1.00 : 1.02) + 0.012 + macro
        if transition {
            let grass = smoothstep(0.42, 0.73, u + Float(sin(Double(v * 8))) * 0.08)
            result = Pixel.mix(result, Pixel(red: 0.10, green: 0.25, blue: 0.16, alpha: 1), amount: grass * 0.46)
        } else if decal {
            let snow = smoothstep(0.82, 0.96, Float(sin(Double((u * 9 - v * 11) * .pi))) * 0.5 + 0.5)
            result = Pixel.mix(result, Pixel(red: 0.82, green: 0.86, blue: 0.85, alpha: 1), amount: snow * 0.72)
        }
    default:
        result.red = result.red * (secondary ? 1.04 : 1.02) + 0.012 + macro
        result.green = result.green * (secondary ? 0.88 : 0.94) + macro * 0.55
        result.blue = result.blue * (secondary ? 0.78 : 0.84) + macro * 0.25
        if transition {
            let clay = smoothstep(0.36, 0.75, u + Float(sin(Double(v * 6))) * 0.12)
            result = Pixel.mix(result, Pixel(red: 0.54, green: 0.25, blue: 0.10, alpha: 1), amount: clay * 0.42)
        } else if decal {
            let diagonal = abs(wrapUnit(u * 4.1 + v * 3.7) - 0.5)
            let cross = abs(wrapUnit(u * 2.3 - v * 5.2) - 0.5)
            let crack = 1 - smoothstep(0.015, 0.060, min(diagonal, cross))
            result = Pixel.mix(result, Pixel(red: 0.19, green: 0.09, blue: 0.04, alpha: 1), amount: crack * 0.68)
        }
    }
    result.alpha = 1
    return result
}

private func buildBaseColor(source: Raster, slug: String) -> Raster {
    var output = Raster(width: outputDimension, height: outputDimension)
    let transforms: [(scale: Float, x: Float, y: Float)] = [
        (1.0, 0.00, 0.00),
        (1.0, 0.37, 0.19),
        (1.0, 0.13, 0.53),
        (2.0, 0.29, 0.41),
    ]
    for quadrant in 0..<4 {
        let originX = (quadrant % 2) * quadrantDimension
        let originY = (quadrant / 2) * quadrantDimension
        let transform = transforms[quadrant]
        for y in 0..<quadrantDimension {
            let v = Float(y) / Float(quadrantDimension - 1)
            for x in 0..<quadrantDimension {
                let u = Float(x) / Float(quadrantDimension - 1)
                let sampled = edgeWrappedPixel(
                    source: source,
                    u: u,
                    v: v,
                    scale: transform.scale,
                    offsetX: transform.x,
                    offsetY: transform.y
                )
                output.setPixel(
                    x: originX + x,
                    y: originY + y,
                    tint(sampled, slug: slug, quadrant: quadrant, u: u, v: v)
                )
            }
        }
    }
    return output
}

private func buildDataMaps(baseColor: Raster, slug: String) -> (normal: Raster, roughness: Raster) {
    var normal = Raster(width: outputDimension, height: outputDimension)
    var roughness = Raster(width: outputDimension, height: outputDimension)
    let roughnessBase: Float
    switch slug {
    case "ocean": roughnessBase = 0.80
    case "alpine": roughnessBase = 0.86
    default: roughnessBase = 0.88
    }

    for quadrantY in 0..<2 {
        for quadrantX in 0..<2 {
            let quadrant = quadrantY * 2 + quadrantX
            for localY in 0..<quadrantDimension {
                for localX in 0..<quadrantDimension {
                    let left = baseColor.luminance(x: localX - 1, y: localY, quadrantX: quadrantX, quadrantY: quadrantY)
                    let right = baseColor.luminance(x: localX + 1, y: localY, quadrantX: quadrantX, quadrantY: quadrantY)
                    let up = baseColor.luminance(x: localX, y: localY - 1, quadrantX: quadrantX, quadrantY: quadrantY)
                    let down = baseColor.luminance(x: localX, y: localY + 1, quadrantX: quadrantX, quadrantY: quadrantY)
                    let center = baseColor.luminance(x: localX, y: localY, quadrantX: quadrantX, quadrantY: quadrantY)
                    let strength: Float = quadrant == 3 ? 5.4 : (quadrant == 2 ? 4.5 : 3.8)
                    let dx = (right - left) * strength
                    let dy = (down - up) * strength
                    let inverseLength = 1 / sqrt(dx * dx + dy * dy + 1)
                    let x = quadrantX * quadrantDimension + localX
                    let y = quadrantY * quadrantDimension + localY
                    normal.setPixel(
                        x: x,
                        y: y,
                        Pixel(
                            red: (-dx * inverseLength) * 0.5 + 0.5,
                            green: (-dy * inverseLength) * 0.5 + 0.5,
                            blue: inverseLength * 0.5 + 0.5,
                            alpha: 1
                        )
                    )

                    let contrast = min(abs(right - left) + abs(down - up), 0.32)
                    let quadrantOffset: Float = quadrant == 2 ? -0.06 : (quadrant == 3 ? -0.03 : 0)
                    let value = min(max(roughnessBase + (1 - center) * 0.10 + contrast * 0.24 + quadrantOffset, 0.62), 0.97)
                    roughness.setPixel(
                        x: x,
                        y: y,
                        Pixel(red: value, green: value, blue: value, alpha: 1)
                    )
                }
            }
        }
    }
    return (normal, roughness)
}

private func sha256(of url: URL) throws -> String {
    let data = try Data(contentsOf: url)
    return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
}

private func decodedManifest(at url: URL) throws -> EnvironmentManifest {
    do {
        return try JSONDecoder().decode(EnvironmentManifest.self, from: Data(contentsOf: url))
    } catch {
        throw BuildError.unreadableManifest(url)
    }
}

private func validateManifest(_ manifest: EnvironmentManifest) throws {
    guard manifest.schemaVersion == 1, manifest.revision == 1 else {
        throw BuildError.invalidManifest("schemaVersion and revision must both be 1")
    }
    guard manifest.license == "project-original", manifest.hashAlgorithm == "SHA-256" else {
        throw BuildError.invalidManifest("license/hash algorithm contract mismatch")
    }
    let requiredScripts = [
        "Scripts/build_racing_environment_usd.swift": "1.1.0",
        "Scripts/build_racing_environment_pbr_maps.swift": toolVersion,
    ]
    let scripts = Dictionary(uniqueKeysWithValues: manifest.authoring.scripts.map { ($0.path, $0.version) })
    guard scripts == requiredScripts else {
        throw BuildError.invalidManifest("authoring script path/version mismatch")
    }
    let contract = manifest.textureContract
    guard contract.width == outputDimension,
          contract.height == outputDimension,
          contract.bitsPerComponent == 8,
          contract.channels == "RGBA",
          contract.atlasQuadrantSize == quadrantDimension,
          contract.expectedBaseLevelDecodedBytesPerTexture == 4_194_304,
          contract.expectedBaseLevelDecodedBytesPerTrack == 12_582_912,
          contract.expectedBaseLevelDecodedBytesAllTracks == 37_748_736 else {
        throw BuildError.invalidManifest("texture dimensions, format, or decoded-byte budget mismatch")
    }
    guard manifest.sources.count == sourceSpecs.count, manifest.tracks.count == sourceSpecs.count else {
        throw BuildError.invalidManifest("exactly three sources and tracks are required")
    }

    let expectedQuadrants: [(String, Int, Int)] = [
        ("terrainPrimary", 0, 0),
        ("terrainSecondary", 512, 0),
        ("transition", 0, 512),
        ("decal", 512, 512),
    ]
    for spec in sourceSpecs {
        guard let source = manifest.sources.first(where: { $0.assetSlug == spec.slug }),
              source.trackID == spec.trackID,
              source.filename == spec.filename,
              source.sha256 == spec.sha256,
              source.width == 1254,
              source.height == 1254 else {
            throw BuildError.invalidManifest("fixed source contract mismatch for \(spec.slug)")
        }
        guard let track = manifest.tracks.first(where: { $0.assetSlug == spec.slug }),
              track.id == spec.trackID,
              track.sourceFilename == spec.filename,
              track.variantEntityNames == spec.variants,
              track.heroEntityName == spec.hero,
              track.roadClearanceHalfWidth == 6,
              track.heroRoadApertureWidth == 14 else {
            throw BuildError.invalidManifest("track/source link mismatch for \(spec.slug)")
        }
        let expectedLODNames = ["ForegroundLOD", "MidgroundLOD", "FarLOD", "Hero"]
        let expectedMaterialSlots = ["Terrain", "Rock", "Vegetation", "Accent"]
        guard track.geometry.base.rootName == spec.baseRoot,
              track.geometry.base.tier == "base",
              track.geometry.base.role == "racing-environment-pack",
              track.geometry.base.requiredLODRoots == expectedLODNames,
              track.geometry.base.materialSlots == expectedMaterialSlots,
              track.geometry.base.sourceUSDA == "\(spec.slug)_environment_base.usda",
              track.geometry.base.runtimeUSDZ == "\(spec.slug)_environment_base.usdz",
              track.geometry.enhanced.rootName == spec.enhancedRoot,
              track.geometry.enhanced.tier == "enhanced",
              track.geometry.enhanced.role == "racing-environment-pack",
              track.geometry.enhanced.requiredLODRoots == expectedLODNames,
              track.geometry.enhanced.materialSlots == expectedMaterialSlots,
              track.geometry.enhanced.sourceUSDA == "\(spec.slug)_environment_enhanced.usda",
              track.geometry.enhanced.runtimeUSDZ == "\(spec.slug)_environment_enhanced.usdz" else {
            throw BuildError.invalidManifest("geometry output names mismatch for \(spec.slug)")
        }
        let geometryHashes = [
            track.geometry.base.sourceUSDASHA256,
            track.geometry.base.runtimeUSDZSHA256,
            track.geometry.enhanced.sourceUSDASHA256,
            track.geometry.enhanced.runtimeUSDZSHA256,
        ]
        for hash in geometryHashes.compactMap({ $0 }) where
            hash.range(of: "^[0-9a-f]{64}$", options: .regularExpression) == nil {
            throw BuildError.invalidManifest("geometry SHA-256 must be null or 64 lowercase hex characters for \(spec.slug)")
        }
        let geometryHashPairs = [
            (track.geometry.base.sourceUSDASHA256, track.geometry.base.runtimeUSDZSHA256, track.geometry.base.hashStatus),
            (track.geometry.enhanced.sourceUSDASHA256, track.geometry.enhanced.runtimeUSDZSHA256, track.geometry.enhanced.hashStatus),
        ]
        for hashes in geometryHashPairs {
            let validPending = hashes.0 == nil && hashes.1 == nil && hashes.2 == "pending-generation"
            let validFinal = hashes.0 != nil && hashes.1 != nil && hashes.2 == "verified"
            guard validPending || validFinal else {
                throw BuildError.invalidManifest("geometry hashes/status must be entirely pending or verified for \(spec.slug)")
            }
        }
        guard track.atlasQuadrants.count == expectedQuadrants.count else {
            throw BuildError.invalidManifest("atlas must declare four quadrants for \(spec.slug)")
        }
        for expected in expectedQuadrants {
            guard let quadrant = track.atlasQuadrants.first(where: { $0.name == expected.0 }),
                  quadrant.x == expected.1,
                  quadrant.y == expected.2,
                  quadrant.width == quadrantDimension,
                  quadrant.height == quadrantDimension,
                  !quadrant.content.isEmpty else {
                throw BuildError.invalidManifest("atlas quadrant mismatch for \(spec.slug)/\(expected.0)")
            }
        }
        guard track.textures.count == TextureRole.allCases.count else {
            throw BuildError.invalidManifest("exactly three PBR textures are required for \(spec.slug)")
        }
        for role in TextureRole.allCases {
            let filename = "\(spec.slug)_\(role.filenameSuffix)"
            guard let texture = track.textures.first(where: { $0.filename == filename }) else {
                throw BuildError.invalidManifest("missing texture \(filename)")
            }
            guard texture.channelRole == role.manifestChannelRole else {
                throw BuildError.invalidManifest("channel role mismatch for \(filename)")
            }
            guard texture.colorEncoding == role.colorEncoding else {
                throw BuildError.invalidManifest("color encoding mismatch for \(filename): expected \(role.colorEncoding)")
            }
            guard texture.realityKitSemantic == role.semantic else {
                throw BuildError.invalidManifest("RealityKit semantic mismatch for \(filename): expected \(role.semantic)")
            }
            guard texture.pixelFormat == "RGBA8",
                  texture.width == outputDimension,
                  texture.height == outputDimension,
                  texture.expectedBaseLevelDecodedBytes == 4_194_304 else {
                throw BuildError.invalidManifest("pixel format, dimension, or decoded-byte mismatch for \(filename)")
            }
            if let hash = texture.derivedSHA256,
               hash.range(of: "^[0-9a-f]{64}$", options: .regularExpression) == nil {
                throw BuildError.invalidManifest("derived SHA-256 must be null or 64 lowercase hex characters for \(filename)")
            }
            let validPending = texture.derivedSHA256 == nil && texture.hashStatus == "pending-generation"
            let validFinal = texture.derivedSHA256 != nil && texture.hashStatus == "verified"
            guard validPending || validFinal else {
                throw BuildError.invalidManifest("derived SHA-256/status must be pending or verified for \(filename)")
            }
        }
    }
}

private func validateSources(in sourceDirectory: URL, manifest: EnvironmentManifest) throws {
    for spec in sourceSpecs {
        let sourceURL = sourceDirectory.appendingPathComponent(spec.filename)
        guard FileManager.default.fileExists(atPath: sourceURL.path) else {
            throw BuildError.unreadableImage(sourceURL)
        }
        let actualHash = try sha256(of: sourceURL)
        guard actualHash == spec.sha256 else {
            throw BuildError.sourceHashMismatch(
                filename: spec.filename,
                expected: spec.sha256,
                actual: actualHash
            )
        }
        let image = try image(at: sourceURL)
        guard image.width == 1254, image.height == 1254 else {
            throw BuildError.sourceDimensionMismatch(
                filename: spec.filename,
                expected: "1254x1254",
                actual: "\(image.width)x\(image.height)"
            )
        }
        guard manifest.sources.contains(where: { $0.assetSlug == spec.slug && $0.sha256 == actualHash }) else {
            throw BuildError.invalidManifest("source SHA link mismatch for \(spec.filename)")
        }
    }
}

private func image(at url: URL) throws -> CGImage {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
        throw BuildError.unreadableImage(url)
    }
    return image
}

private func colorSpaceMatches(_ image: CGImage, linear: Bool) -> Bool {
    guard let actual = image.colorSpace,
          let expected = CGColorSpace(name: linear ? CGColorSpace.linearSRGB : CGColorSpace.sRGB) else {
        return false
    }
    if CFEqual(actual, expected) {
        return true
    }
    guard let actualICC = actual.copyICCData(),
          let expectedICC = expected.copyICCData() else {
        return false
    }
    return actualICC == expectedICC
}

private func validateOutputs(
    in outputDirectory: URL,
    manifest: EnvironmentManifest
) throws {
    for spec in sourceSpecs {
        guard let track = manifest.tracks.first(where: { $0.assetSlug == spec.slug }) else {
            throw BuildError.invalidManifest("missing track \(spec.slug)")
        }
        for role in TextureRole.allCases {
            let filename = "\(spec.slug)_\(role.filenameSuffix)"
            let url = outputDirectory.appendingPathComponent(filename)
            guard FileManager.default.fileExists(atPath: url.path) else {
                throw BuildError.missingOutput(url)
            }
            let outputImage = try image(at: url)
            guard outputImage.width == outputDimension, outputImage.height == outputDimension else {
                throw BuildError.outputMismatch("\(filename) must be 1024x1024")
            }
            guard outputImage.bitsPerComponent == 8, outputImage.bitsPerPixel == 32 else {
                throw BuildError.outputMismatch("\(filename) must be 8-bit RGBA")
            }
            guard colorSpaceMatches(outputImage, linear: role != .baseColor) else {
                throw BuildError.outputMismatch("\(filename) embedded color encoding is not \(role.colorEncoding)")
            }
            guard let texture = track.textures.first(where: { $0.filename == filename }) else {
                throw BuildError.invalidManifest("missing texture declaration for \(filename)")
            }
            if let expectedHash = texture.derivedSHA256 {
                let actualHash = try sha256(of: url)
                guard expectedHash == actualHash else {
                    throw BuildError.outputMismatch("derived SHA-256 mismatch for \(filename)")
                }
            }

            let raster = try Raster(contentsOf: url)
            for pixelOffset in stride(from: 0, to: raster.pixels.count, by: 4) {
                guard raster.pixels[pixelOffset + 3] == 255 else {
                    throw BuildError.outputMismatch("\(filename) alpha must be 255")
                }
                if role == .roughness {
                    let red = raster.pixels[pixelOffset]
                    guard raster.pixels[pixelOffset + 1] == red,
                          raster.pixels[pixelOffset + 2] == red else {
                        throw BuildError.outputMismatch("\(filename) must replicate roughness to RGB")
                    }
                }
            }
            print("validated \(url.path)")
        }
    }
}

private func build(
    sourceDirectory: URL,
    outputDirectory: URL,
    manifest: EnvironmentManifest
) throws {
    try FileManager.default.createDirectory(
        at: outputDirectory,
        withIntermediateDirectories: true
    )
    for spec in sourceSpecs {
        let sourceURL = sourceDirectory.appendingPathComponent(spec.filename)
        let source = try Raster(contentsOf: sourceURL)
        let baseColor = buildBaseColor(source: source, slug: spec.slug)
        let maps = buildDataMaps(baseColor: baseColor, slug: spec.slug)
        let outputs: [(TextureRole, Raster)] = [
            (.baseColor, baseColor),
            (.normal, maps.normal),
            (.roughness, maps.roughness),
        ]
        for output in outputs {
            let url = outputDirectory.appendingPathComponent("\(spec.slug)_\(output.0.filenameSuffix)")
            try output.1.writePNG(to: url, linear: output.0 != .baseColor)
            print("wrote \(url.path)")
        }
    }
    try validateOutputs(in: outputDirectory, manifest: manifest)
}

do {
    let arguments = Array(CommandLine.arguments.dropFirst())
    let mode: String
    let paths: ArraySlice<String>
    if arguments.count == 3 {
        mode = "build"
        paths = arguments[0...2]
    } else if arguments.count == 4, ["build", "validate"].contains(arguments[0]) {
        mode = arguments[0]
        paths = arguments[1...3]
    } else {
        throw BuildError.usage
    }

    let sourceDirectory = URL(fileURLWithPath: paths[paths.startIndex], isDirectory: true)
    let outputDirectory = URL(fileURLWithPath: paths[paths.index(after: paths.startIndex)], isDirectory: true)
    let manifestURL = URL(fileURLWithPath: paths[paths.index(paths.startIndex, offsetBy: 2)])
    let manifest = try decodedManifest(at: manifestURL)
    try validateManifest(manifest)
    try validateSources(in: sourceDirectory, manifest: manifest)
    if mode == "build" {
        try build(
            sourceDirectory: sourceDirectory,
            outputDirectory: outputDirectory,
            manifest: manifest
        )
    } else {
        try validateOutputs(in: outputDirectory, manifest: manifest)
    }
} catch {
    fputs("error: \(error)\n", stderr)
    exit(1)
}
