import CoreGraphics
import CryptoKit
import Foundation
import ImageIO
import RealityKit
import XCTest

@MainActor
final class RacingEnvironmentAssetTests: XCTestCase {
    func testManifestProvenanceAndFilesShareVerifiedSHA256SourceChain() throws {
        let manifest = try sourceManifest()
        let provenance = try String(
            contentsOf: repositoryRoot.appendingPathComponent("docs/assets/provenance.md"),
            encoding: .utf8
        )

        XCTAssertEqual(manifest.schemaVersion, 1)
        XCTAssertEqual(manifest.revision, 1)
        XCTAssertEqual(manifest.license, "project-original")
        XCTAssertEqual(manifest.hashAlgorithm, "SHA-256")
        XCTAssertEqual(manifest.sources.count, 3)
        XCTAssertEqual(manifest.tracks.count, 3)
        XCTAssertEqual(Set(manifest.tracks.map(\.id)), ["coastal", "alpine", "desert"])

        for source in manifest.sources {
            let sourceURL = sourceDirectory.appendingPathComponent(source.filename)
            let actualHash = try sha256(of: sourceURL)
            XCTAssertEqual(actualHash, source.sha256, source.filename)
            XCTAssertEqual(source.license, "project-original", source.filename)
            XCTAssertTrue(provenance.contains("`\(source.filename)`"), source.filename)
            XCTAssertTrue(provenance.contains("`\(actualHash)`"), source.filename)
        }

        var geometryCount = 0
        var textureCount = 0
        for track in manifest.tracks {
            let source = try XCTUnwrap(
                manifest.sources.first { $0.filename == track.sourceFilename }
            )
            XCTAssertEqual(source.trackID, track.id)
            XCTAssertEqual(source.assetSlug, track.assetSlug)

            for pack in track.geometry.packs {
                geometryCount += 1
                let sourceURL = environmentDirectory.appendingPathComponent(pack.sourceUSDA)
                let runtimeURL = environmentDirectory.appendingPathComponent(pack.runtimeUSDZ)
                XCTAssertEqual(pack.hashStatus, "verified", pack.sourceUSDA)
                XCTAssertEqual(try sha256(of: sourceURL), pack.sourceUSDASHA256, pack.sourceUSDA)
                XCTAssertEqual(try sha256(of: runtimeURL), pack.runtimeUSDZSHA256, pack.runtimeUSDZ)
                assertProvenance(
                    contains: pack.sourceUSDA,
                    hash: try sha256(of: sourceURL),
                    provenance: provenance
                )
                assertProvenance(
                    contains: pack.runtimeUSDZ,
                    hash: try sha256(of: runtimeURL),
                    provenance: provenance
                )
            }

            for texture in track.textures {
                textureCount += 1
                let url = environmentDirectory.appendingPathComponent(texture.filename)
                XCTAssertEqual(texture.hashStatus, "verified", texture.filename)
                XCTAssertEqual(try sha256(of: url), texture.derivedSHA256, texture.filename)
                assertProvenance(
                    contains: texture.filename,
                    hash: try sha256(of: url),
                    provenance: provenance
                )
            }
        }
        XCTAssertEqual(geometryCount, 6)
        XCTAssertEqual(textureCount, 9)
        XCTAssertFalse(provenance.contains("pending-generation"))
    }

    func testAuthoredPacksExposeRootsVariantsHeroesMetadataAndSaneBounds() throws {
        let manifest = try sourceManifest()

        for track in manifest.tracks {
            XCTAssertEqual(track.variantEntityNames.count, 4, track.assetSlug)
            XCTAssertEqual(track.roadClearanceHalfWidth, 6, track.assetSlug)
            XCTAssertEqual(track.heroRoadApertureWidth, 14, track.assetSlug)
            for pack in track.geometry.packs {
                let sourceURL = environmentDirectory.appendingPathComponent(pack.sourceUSDA)
                let source = try String(contentsOf: sourceURL, encoding: .utf8)
                XCTAssertTrue(source.contains("defaultPrim = \"\(pack.rootName)\""), pack.sourceUSDA)
                XCTAssertTrue(source.contains("string track = \"\(track.id)\""), pack.sourceUSDA)
                XCTAssertTrue(source.contains("string tier = \"\(pack.tier)\""), pack.sourceUSDA)
                XCTAssertTrue(source.contains("string role = \"\(pack.role)\""), pack.sourceUSDA)
                XCTAssertTrue(source.contains("string license = \"project-original\""), pack.sourceUSDA)
                let isBlenderAlpinePack = pack.sourceUSDA == "alpine_environment_enhanced.usda"
                let authoringTool = isBlenderAlpinePack
                    ? "Blender 4.5 LTS + Scripts/build_alpine_environment_blender.py@1.0.0"
                    : "Scripts/build_racing_environment_usd.swift@1.1.0"
                XCTAssertTrue(
                    source.contains("string authoringTool = \"\(authoringTool)\""),
                    pack.sourceUSDA
                )
                XCTAssertTrue(
                    source.contains("int revision = \(isBlenderAlpinePack ? 3 : 2)"),
                    pack.sourceUSDA
                )
                XCTAssertTrue(source.contains("string topology = \"closed-volume\""), pack.sourceUSDA)
                XCTAssertTrue(source.contains("double roadClearanceHalfWidth = 6.00000"), pack.sourceUSDA)
                XCTAssertTrue(source.contains("double roadApertureWidth = 14.00000"), pack.sourceUSDA)

                for name in pack.requiredLODRoots + track.variantEntityNames + [track.heroEntityName] {
                    XCTAssertTrue(source.contains("\"\(name)\""), "\(pack.sourceUSDA): \(name)")
                }
                for material in pack.materialSlots {
                    XCTAssertTrue(source.contains("def Material \"\(material)\""), pack.sourceUSDA)
                }

                let points = try authoredPoints(in: source)
                XCTAssertGreaterThan(points.count, 100, pack.sourceUSDA)
                XCTAssertTrue(points.allSatisfy { $0.x.isFinite && $0.y.isFinite && $0.z.isFinite })
                let minimum = points.reduce(SIMD3<Double>(repeating: .greatestFiniteMagnitude)) {
                    simd_min($0, $1)
                }
                let maximum = points.reduce(SIMD3<Double>(repeating: -.greatestFiniteMagnitude)) {
                    simd_max($0, $1)
                }
                let extents = maximum - minimum
                XCTAssertGreaterThan(extents.x, 14, pack.sourceUSDA)
                XCTAssertGreaterThan(extents.y, 5, pack.sourceUSDA)
                XCTAssertGreaterThan(extents.z, 2, pack.sourceUSDA)
                XCTAssertLessThan(maximum.x, 100, pack.sourceUSDA)
                XCTAssertLessThan(maximum.y, 100, pack.sourceUSDA)
                XCTAssertLessThan(maximum.z, 100, pack.sourceUSDA)
                XCTAssertGreaterThan(minimum.x, -100, pack.sourceUSDA)
                XCTAssertGreaterThan(minimum.y, -10, pack.sourceUSDA)
                XCTAssertGreaterThan(minimum.z, -100, pack.sourceUSDA)
            }
        }
    }

    func testUSDZPackagesAreStoredDeterministicSourceAssociations() throws {
        let manifest = try sourceManifest()

        for track in manifest.tracks {
            for pack in track.geometry.packs {
                let sourceData = try Data(
                    contentsOf: environmentDirectory.appendingPathComponent(pack.sourceUSDA)
                )
                let packageData = try Data(
                    contentsOf: environmentDirectory.appendingPathComponent(pack.runtimeUSDZ)
                )
                XCTAssertEqual(Array(packageData.prefix(2)), [0x50, 0x4B], pack.runtimeUSDZ)
                XCTAssertLessThan(packageData.count, 256 * 1_024, pack.runtimeUSDZ)
                XCTAssertNotNil(packageData.range(of: Data(pack.sourceUSDA.utf8)), pack.runtimeUSDZ)
                XCTAssertNotNil(packageData.range(of: sourceData), pack.runtimeUSDZ)
                XCTAssertNotNil(
                    packageData.range(of: Data("defaultPrim = \"\(pack.rootName)\"".utf8)),
                    pack.runtimeUSDZ
                )
            }
        }
    }

    func testEveryRuntimeTextureMatchesEncodingSemanticAndRGBAContract() async throws {
        let manifest = try sourceManifest()

        for track in manifest.tracks {
            for texture in track.textures {
                let url = environmentDirectory.appendingPathComponent(texture.filename)
                guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                      let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
                    return XCTFail("Could not decode \(texture.filename)")
                }

                XCTAssertEqual(texture.pixelFormat, "RGBA8", texture.filename)
                XCTAssertEqual(image.width, 1_024, texture.filename)
                XCTAssertEqual(image.height, 1_024, texture.filename)
                XCTAssertEqual(image.bitsPerComponent, 8, texture.filename)
                XCTAssertEqual(image.bitsPerPixel, 32, texture.filename)
                XCTAssertTrue(image.alphaInfo.environmentHasAlpha, texture.filename)

                let semantic: TextureResource.Semantic
                switch texture.channelRole {
                case "baseColor":
                    XCTAssertEqual(texture.colorEncoding, "sRGB", texture.filename)
                    XCTAssertEqual(texture.realityKitSemantic, ".color", texture.filename)
                    XCTAssertTrue(colorSpaceMatches(image, name: CGColorSpace.sRGB), texture.filename)
                    semantic = .color
                case "tangentSpaceNormal":
                    XCTAssertEqual(texture.colorEncoding, "linear-sRGB", texture.filename)
                    XCTAssertEqual(texture.realityKitSemantic, ".normal", texture.filename)
                    XCTAssertTrue(colorSpaceMatches(image, name: CGColorSpace.linearSRGB), texture.filename)
                    semantic = .normal
                case "roughnessScalarReplicatedRGBA":
                    XCTAssertEqual(texture.colorEncoding, "linear-sRGB", texture.filename)
                    XCTAssertEqual(texture.realityKitSemantic, ".scalar", texture.filename)
                    XCTAssertTrue(colorSpaceMatches(image, name: CGColorSpace.linearSRGB), texture.filename)
                    XCTAssertTrue(try decodedRGBA(image).hasReplicatedRGB, texture.filename)
                    semantic = .scalar
                default:
                    return XCTFail("Unexpected channel role \(texture.channelRole)")
                }

                _ = try await TextureResource(
                    contentsOf: url,
                    withName: "asset-test.\(texture.filename)",
                    options: TextureResource.CreateOptions(
                        semantic: semantic,
                        mipmapsMode: .allocateAndGenerateAll
                    )
                )
            }
        }
    }

    func testTexturePayloadIsExactlyTwelveMiBPerTrackAndThirtySixMiBOverall() throws {
        let manifest = try sourceManifest()
        XCTAssertEqual(manifest.textureContract.width, 1_024)
        XCTAssertEqual(manifest.textureContract.height, 1_024)
        XCTAssertEqual(manifest.textureContract.bitsPerComponent, 8)
        XCTAssertEqual(manifest.textureContract.channels, "RGBA")
        XCTAssertEqual(manifest.textureContract.expectedBaseLevelDecodedBytesPerTexture, 4_194_304)
        XCTAssertEqual(manifest.textureContract.expectedBaseLevelDecodedBytesPerTrack, 12_582_912)
        XCTAssertEqual(manifest.textureContract.expectedBaseLevelDecodedBytesAllTracks, 37_748_736)

        var total = 0
        for track in manifest.tracks {
            XCTAssertEqual(track.textures.count, 3, track.assetSlug)
            let trackBytes = track.textures.reduce(0) {
                $0 + $1.expectedBaseLevelDecodedBytes
            }
            XCTAssertEqual(trackBytes, 12_582_912, track.assetSlug)
            total += trackBytes
        }
        XCTAssertEqual(total, 37_748_736)
    }

    func testResourcesAreIOSOnlyResolveByBasenameAndSourcesStayUnbundled() throws {
        let manifest = try sourceManifest()
        let project = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "WatchCarRacer.xcodeproj/project.pbxproj"
            ),
            encoding: .utf8
        )
        let iosResources = try XCTUnwrap(
            projectSection(project, startingWith: "050000000000000000000003 /* Resources */ = {")
        )
        let watchResources = try XCTUnwrap(
            projectSection(project, startingWith: "050000000000000000000013 /* Resources */ = {")
        )
        let testSources = try XCTUnwrap(
            projectSection(project, startingWith: "050000000000000000000021 /* Sources */ = {")
        )

        let runtimeFiles = ["RacingEnvironmentAssetManifest.json"]
            + manifest.tracks.flatMap { $0.geometry.packs.map(\.runtimeUSDZ) }
            + manifest.tracks.flatMap { $0.textures.map(\.filename) }
        XCTAssertEqual(runtimeFiles.count, 16)
        for filename in runtimeFiles {
            XCTAssertEqual(
                iosResources.components(separatedBy: "\(filename) in Resources").count - 1,
                1,
                filename
            )
            XCTAssertFalse(watchResources.contains(filename), filename)
            let file = URL(fileURLWithPath: filename)
            XCTAssertNotNil(
                Bundle.main.url(
                    forResource: file.deletingPathExtension().lastPathComponent,
                    withExtension: file.pathExtension
                ),
                filename
            )
        }
        XCTAssertTrue(testSources.contains("RacingEnvironmentAssetTests.swift in Sources"))

        for sourceUSDA in manifest.tracks.flatMap({ $0.geometry.packs.map(\.sourceUSDA) }) {
            XCTAssertFalse(iosResources.contains(sourceUSDA), sourceUSDA)
            let source = URL(fileURLWithPath: sourceUSDA)
            XCTAssertNil(
                Bundle.main.url(
                    forResource: source.deletingPathExtension().lastPathComponent,
                    withExtension: source.pathExtension
                ),
                sourceUSDA
            )
        }
        for source in manifest.sources {
            XCTAssertFalse(iosResources.contains(source.filename), source.filename)
            let file = URL(fileURLWithPath: source.filename)
            XCTAssertNil(
                Bundle.main.url(
                    forResource: file.deletingPathExtension().lastPathComponent,
                    withExtension: file.pathExtension
                ),
                source.filename
            )
        }
        XCTAssertFalse(watchResources.contains("RacingEnvironmentAssetManifest"))
    }

    func testEveryUSDZLoadsAndExposesRequiredRuntimeNames() async throws {
        let manifest = try sourceManifest()

        for track in manifest.tracks {
            for pack in track.geometry.packs {
                let resource = URL(fileURLWithPath: pack.runtimeUSDZ)
                    .deletingPathExtension().lastPathComponent
                let url = try XCTUnwrap(
                    Bundle.main.url(forResource: resource, withExtension: "usdz"),
                    pack.runtimeUSDZ
                )
                let entity = try await Entity(contentsOf: url, withName: "asset-test.\(resource)")
                XCTAssertNotNil(entity.findEntity(named: pack.rootName), pack.runtimeUSDZ)
                for name in pack.requiredLODRoots + track.variantEntityNames + [track.heroEntityName] {
                    XCTAssertNotNil(entity.findEntity(named: name), "\(pack.runtimeUSDZ): \(name)")
                }
            }
        }
    }

    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private var environmentDirectory: URL {
        repositoryRoot.appendingPathComponent(
            "WatchCarRacer/iOS/Resources/RacingEnvironment3D"
        )
    }

    private var sourceDirectory: URL {
        repositoryRoot.appendingPathComponent("docs/assets/sources/racing-environment")
    }

    private func sourceManifest() throws -> RacingEnvironmentAssetManifest {
        let data = try Data(
            contentsOf: environmentDirectory.appendingPathComponent(
                "RacingEnvironmentAssetManifest.json"
            )
        )
        return try JSONDecoder().decode(RacingEnvironmentAssetManifest.self, from: data)
    }

    private func sha256(of url: URL) throws -> String {
        SHA256.hash(data: try Data(contentsOf: url))
            .map { String(format: "%02x", $0) }
            .joined()
    }

    private func assertProvenance(
        contains filename: String,
        hash: String,
        provenance: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertTrue(
            provenance.contains("`RacingEnvironment3D/\(filename)`"),
            filename,
            file: file,
            line: line
        )
        XCTAssertTrue(provenance.contains("`\(hash)`"), filename, file: file, line: line)
    }

    private func authoredPoints(in source: String) throws -> [SIMD3<Double>] {
        let meshExpression = try NSRegularExpression(
            pattern: #"point3f\[\] points = \[([^\]]+)\]"#,
            options: [.dotMatchesLineSeparators]
        )
        let tupleExpression = try NSRegularExpression(
            pattern: #"\((-?[0-9]+\.[0-9]+), (-?[0-9]+\.[0-9]+), (-?[0-9]+\.[0-9]+)\)"#
        )
        let range = NSRange(source.startIndex..., in: source)
        var points: [SIMD3<Double>] = []
        for meshMatch in meshExpression.matches(in: source, range: range) {
            guard let meshRange = Range(meshMatch.range(at: 1), in: source) else { continue }
            let mesh = String(source[meshRange])
            let tupleRange = NSRange(mesh.startIndex..., in: mesh)
            for match in tupleExpression.matches(in: mesh, range: tupleRange) {
                var values: [Double] = []
                for index in 1...3 {
                    guard let valueRange = Range(match.range(at: index), in: mesh) else {
                        continue
                    }
                    if let value = Double(mesh[valueRange]) {
                        values.append(value)
                    }
                }
                if values.count == 3 {
                    points.append(SIMD3(values[0], values[1], values[2]))
                }
            }
        }
        return points
    }

    private func colorSpaceMatches(_ image: CGImage, name: CFString) -> Bool {
        guard let actual = image.colorSpace,
              let expected = CGColorSpace(name: name) else {
            return false
        }
        if CFEqual(actual, expected) {
            return true
        }
        return actual.copyICCData() == expected.copyICCData()
    }

    private func decodedRGBA(_ image: CGImage) throws -> EnvironmentRGBAFixture {
        try EnvironmentRGBAFixture(image)
    }

    private func projectSection(_ project: String, startingWith marker: String) -> String? {
        guard let start = project.range(of: marker)?.lowerBound,
              let end = project[start...].range(of: "\n\t\t};")?.upperBound else {
            return nil
        }
        return String(project[start..<end])
    }
}

private struct RacingEnvironmentAssetManifest: Decodable {
    struct TextureContract: Decodable {
        let width: Int
        let height: Int
        let bitsPerComponent: Int
        let channels: String
        let expectedBaseLevelDecodedBytesPerTexture: Int
        let expectedBaseLevelDecodedBytesPerTrack: Int
        let expectedBaseLevelDecodedBytesAllTracks: Int
    }

    struct Source: Decodable {
        let trackID: String
        let assetSlug: String
        let filename: String
        let license: String
        let sha256: String
    }

    struct Track: Decodable {
        struct Geometry: Decodable {
            struct Pack: Decodable {
                let rootName: String
                let tier: String
                let role: String
                let requiredLODRoots: [String]
                let materialSlots: [String]
                let sourceUSDA: String
                let runtimeUSDZ: String
                let sourceUSDASHA256: String
                let runtimeUSDZSHA256: String
                let hashStatus: String
            }

            let base: Pack
            let enhanced: Pack

            var packs: [Pack] { [base, enhanced] }
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
            let derivedSHA256: String
            let hashStatus: String
        }

        let id: String
        let assetSlug: String
        let sourceFilename: String
        let variantEntityNames: [String]
        let heroEntityName: String
        let roadClearanceHalfWidth: Double
        let heroRoadApertureWidth: Double
        let geometry: Geometry
        let textures: [Texture]
    }

    let schemaVersion: Int
    let revision: Int
    let license: String
    let hashAlgorithm: String
    let textureContract: TextureContract
    let sources: [Source]
    let tracks: [Track]
}

private struct EnvironmentRGBAFixture {
    let bytes: [UInt8]

    init(_ image: CGImage) throws {
        var rgba = [UInt8](repeating: 0, count: image.width * image.height * 4)
        guard let colorSpace = CGColorSpace(name: CGColorSpace.linearSRGB),
              let context = CGContext(
                data: &rgba,
                width: image.width,
                height: image.height,
                bitsPerComponent: 8,
                bytesPerRow: image.width * 4,
                space: colorSpace,
                bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue
                    | CGImageAlphaInfo.premultipliedLast.rawValue
              ) else {
            throw CocoaError(.coderInvalidValue)
        }
        context.interpolationQuality = .none
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        bytes = rgba
    }

    var hasReplicatedRGB: Bool {
        for offset in stride(from: 0, to: bytes.count, by: 4) {
            if bytes[offset] != bytes[offset + 1] || bytes[offset] != bytes[offset + 2] {
                return false
            }
        }
        return true
    }
}

private extension CGImageAlphaInfo {
    var environmentHasAlpha: Bool {
        switch self {
        case .first, .last, .premultipliedFirst, .premultipliedLast, .alphaOnly:
            true
        case .none, .noneSkipFirst, .noneSkipLast:
            false
        @unknown default:
            false
        }
    }
}
