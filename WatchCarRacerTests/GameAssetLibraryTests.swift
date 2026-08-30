import CoreGraphics
import ImageIO
import SpriteKit
import XCTest
@testable import WatchCarRacer

@MainActor
final class GameAssetLibraryTests: XCTestCase {
    func testVehicleCatalogLocksExactlyThreeAssetDescriptors() {
        XCTAssertEqual(VehicleID.allCases, [.rally, .gt, .angular])
        XCTAssertEqual(VehicleCatalog.all.map(\.id), [.rally, .gt, .angular])
        XCTAssertEqual(Set(VehicleCatalog.all.flatMap(\.textures.allNames)).count, 9)

        for descriptor in VehicleCatalog.all {
            XCTAssertFalse(descriptor.displayName.isEmpty)
            XCTAssertFalse(descriptor.accessibilityName.isEmpty)
            XCTAssertEqual(descriptor.logicalRenderSize, CGSize(width: 50, height: 75))
            XCTAssertEqual(descriptor.pivot, .collisionCenter)
            XCTAssertTrue(descriptor.textures.shadow.hasSuffix("_shadow"))
            XCTAssertTrue(descriptor.textures.paint.hasSuffix("_paint"))
            XCTAssertTrue(descriptor.textures.details.hasSuffix("_details"))
        }
    }

    func testBundleManifestIsCompleteAndEveryTextureResolves() async throws {
        let library = try GameAssetLibrary()
        XCTAssertEqual(library.manifest.schemaVersion, 1)
        XCTAssertEqual(library.manifest.direction, "+Y")
        XCTAssertEqual(library.manifest.assets.count, 19)
        XCTAssertEqual(Set(library.manifest.assets.map(\.name)), expectedTextureNames)

        try await library.preloadAll()

        XCTAssertEqual(
            library.preloadedAtlasNames,
            ["Vehicles", "Obstacles", "Environment"]
        )

        for asset in library.manifest.assets {
            let texture = try library.texture(named: asset.name)
            XCTAssertGreaterThan(texture.size().width, 0, asset.name)
            XCTAssertGreaterThan(texture.size().height, 0, asset.name)
            XCTAssertEqual(texture.filteringMode, .linear, asset.name)
        }
        XCTAssertEqual(library.cachedTextureCount, 19)
    }

    func testAtlasPreloadIsSerializedByStageAndIdempotent() async throws {
        let library = try GameAssetLibrary()

        try await library.preloadVehicleTextures()

        XCTAssertEqual(library.preloadedAtlasNames, ["Vehicles"])
        XCTAssertEqual(library.cachedTextureCount, 9)

        try await library.preloadGameplayTextures()

        XCTAssertEqual(
            library.preloadedAtlasNames,
            ["Vehicles", "Obstacles", "Environment"]
        )
        XCTAssertEqual(library.cachedTextureCount, 19)

        try await library.preloadAll()

        XCTAssertEqual(
            library.preloadedAtlasNames,
            ["Vehicles", "Obstacles", "Environment"]
        )
        XCTAssertEqual(library.cachedTextureCount, 19)
    }

    func testMissingTextureFailsExplicitly() throws {
        let library = try GameAssetLibrary()

        XCTAssertThrowsError(try library.texture(named: "not_a_real_texture")) { error in
            XCTAssertEqual(
                error as? GameAssetLibraryError,
                .missingTexture("not_a_real_texture")
            )
        }
    }

    func testManifestMatchesEveryProductionPNGAndLockedExportContract() throws {
        let manifest = try sourceManifest()
        let resources = resourcesDirectory
        let declaredFiles = Set(manifest.assets.map(\.file))
        let productionFiles = try Set(
            FileManager.default.subpathsOfDirectory(atPath: resources.path)
                .filter {
                    $0.hasSuffix(".png")
                        && !$0.hasPrefix("Presentation/")
                        && !$0.hasPrefix("Racing3D/")
                }
        )
        XCTAssertEqual(declaredFiles, productionFiles)

        for asset in manifest.assets {
            XCTAssertEqual(asset.colorSpace, "sRGB", asset.file)
            XCTAssertEqual(asset.bitsPerComponent, 8, asset.file)
            XCTAssertEqual(asset.channels, "RGBA", asset.file)
            XCTAssertTrue((0...1).contains(asset.anchor.x), asset.file)
            XCTAssertTrue((0...1).contains(asset.anchor.y), asset.file)

            let url = resources.appendingPathComponent(asset.file)
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
                  let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil)
                    as? [CFString: Any] else {
                return XCTFail("Could not decode \(asset.file)")
            }
            XCTAssertEqual(image.width, asset.pixelSize.width, asset.file)
            XCTAssertEqual(image.height, asset.pixelSize.height, asset.file)
            XCTAssertEqual(image.bitsPerComponent, 8, asset.file)
            XCTAssertEqual(image.bitsPerPixel, 32, asset.file)
            XCTAssertEqual(image.colorSpace?.model, .rgb, asset.file)
            XCTAssertTrue(image.alphaInfo.hasAlpha, asset.file)
            XCTAssertEqual(
                properties[kCGImagePropertyProfileName] as? String,
                "sRGB IEC61966-2.1",
                asset.file
            )
        }
    }

    func testVehicleLayersUseExactCanvasPivotAndWhitePaintMask() throws {
        let manifest = try sourceManifest()
        let vehicleAssets = manifest.assets.filter { $0.family.hasPrefix("vehicle.") }
        XCTAssertEqual(vehicleAssets.count, 9)

        for asset in vehicleAssets {
            XCTAssertEqual(asset.pixelSize, .init(width: 384, height: 576), asset.file)
            XCTAssertEqual(asset.anchor, .collisionCenter, asset.file)
            let image = try decodedRGBAImage(
                at: resourcesDirectory.appendingPathComponent(asset.file)
            )
            XCTAssertTrue(image.hasTransparentBorder, "Clipped alpha in \(asset.file)")
            XCTAssertTrue(image.containsVisiblePixel, "Empty layer in \(asset.file)")

            if asset.family.hasSuffix("paint-mask") {
                XCTAssertTrue(image.visiblePixelsAreWhite, asset.file)
                XCTAssertEqual(asset.alphaMode, "straight-white-mask")
            }
        }
    }

    func testLockedFamilyDimensionsAndAnchors() throws {
        let manifest = try sourceManifest()
        let byName = Dictionary(uniqueKeysWithValues: manifest.assets.map { ($0.name, $0) })

        for name in ["traffic_sedan", "traffic_wagon"] {
            XCTAssertEqual(byName[name]?.pixelSize, .init(width: 320, height: 480))
            XCTAssertEqual(byName[name]?.anchor, .collisionCenter)
        }
        XCTAssertEqual(byName["barrier_modular"]?.pixelSize, .init(width: 512, height: 256))
        XCTAssertEqual(byName["lane_worn"]?.pixelSize, .init(width: 64, height: 256))
        XCTAssertEqual(byName["sky_horizon"]?.pixelSize, .init(width: 2048, height: 1024))
        XCTAssertEqual(byName["asphalt"]?.pixelSize, .init(width: 1024, height: 1024))

        for name in ["roadside_light", "roadside_palm", "roadside_marker"] {
            guard let asset = byName[name] else {
                return XCTFail("Missing \(name)")
            }
            XCTAssertLessThanOrEqual(asset.pixelSize.width, 512)
            XCTAssertLessThanOrEqual(asset.pixelSize.height, 512)
            XCTAssertEqual(asset.anchor, NormalizedPivot(x: 0.5, y: 0))
        }
        XCTAssertEqual(
            byName["road_decal_chevrons"]?.pixelSize,
            .init(width: 256, height: 256)
        )
    }

    private var expectedTextureNames: Set<String> {
        [
            "rally_shadow", "rally_paint", "rally_details",
            "gt_shadow", "gt_paint", "gt_details",
            "angular_shadow", "angular_paint", "angular_details",
            "traffic_sedan", "traffic_wagon", "barrier_modular",
            "lane_worn", "road_decal_chevrons",
            "roadside_light", "roadside_palm", "roadside_marker",
            "sky_horizon", "asphalt",
        ]
    }

    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private var resourcesDirectory: URL {
        repositoryRoot.appendingPathComponent("WatchCarRacer/iOS/Resources")
    }

    private func sourceManifest() throws -> AssetManifest {
        let data = try Data(
            contentsOf: resourcesDirectory.appendingPathComponent("AssetManifest.json")
        )
        return try JSONDecoder().decode(AssetManifest.self, from: data)
    }

    private func decodedRGBAImage(at url: URL) throws -> RGBAImage {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return try RGBAImage(image)
    }
}

private struct RGBAImage {
    let width: Int
    let height: Int
    let bytes: [UInt8]

    init(_ image: CGImage) throws {
        let imageWidth = image.width
        let imageHeight = image.height
        var buffer = [UInt8](repeating: 0, count: imageWidth * imageHeight * 4)
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: &buffer,
                width: imageWidth,
                height: imageHeight,
                bitsPerComponent: 8,
                bytesPerRow: imageWidth * 4,
                space: colorSpace,
                bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue
                    | CGImageAlphaInfo.premultipliedLast.rawValue
              ) else {
            throw CocoaError(.coderInvalidValue)
        }
        context.draw(
            image,
            in: CGRect(x: 0, y: 0, width: imageWidth, height: imageHeight)
        )
        width = imageWidth
        height = imageHeight
        bytes = buffer
    }

    var containsVisiblePixel: Bool {
        stride(from: 3, to: bytes.count, by: 4).contains { bytes[$0] > 0 }
    }

    var hasTransparentBorder: Bool {
        let topAndBottom = (0..<width).allSatisfy { x in
            alpha(x: x, y: 0) == 0 && alpha(x: x, y: height - 1) == 0
        }
        let sides = (0..<height).allSatisfy { y in
            alpha(x: 0, y: y) == 0 && alpha(x: width - 1, y: y) == 0
        }
        return topAndBottom && sides
    }

    var visiblePixelsAreWhite: Bool {
        for offset in stride(from: 0, to: bytes.count, by: 4) {
            let alpha = bytes[offset + 3]
            guard alpha > 0 else { continue }
            if abs(Int(bytes[offset]) - Int(alpha)) > 1
                || abs(Int(bytes[offset + 1]) - Int(alpha)) > 1
                || abs(Int(bytes[offset + 2]) - Int(alpha)) > 1 {
                return false
            }
        }
        return true
    }

    private func alpha(x: Int, y: Int) -> UInt8 {
        bytes[(y * width + x) * 4 + 3]
    }
}

private extension CGImageAlphaInfo {
    var hasAlpha: Bool {
        switch self {
        case .first, .last, .premultipliedFirst, .premultipliedLast, .alphaOnly:
            return true
        case .none, .noneSkipFirst, .noneSkipLast:
            return false
        @unknown default:
            return false
        }
    }
}
