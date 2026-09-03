import CoreGraphics
import CryptoKit
import ImageIO
import UIKit
import XCTest
@testable import WatchCarRacer

@MainActor
final class PresentationAssetTests: XCTestCase {
    func testPresentationManifestIsCompleteAndGameplayManifestStaysIsolated() throws {
        let presentation = try sourcePresentationManifest()
        let gameplay = try sourceGameplayManifest()

        XCTAssertEqual(presentation.schemaVersion, 1)
        XCTAssertEqual(presentation.assets.count, 10)
        XCTAssertEqual(Set(presentation.assets.map(\.name)), expectedNames)
        XCTAssertEqual(gameplay.assets.count, 19)
        XCTAssertFalse(
            gameplay.assets.contains {
                $0.file.hasPrefix("Presentation/") || expectedNames.contains($0.name)
            }
        )
    }

    func testEveryPresentationPNGMatchesExportContract() throws {
        let manifest = try sourcePresentationManifest()

        for asset in manifest.assets {
            XCTAssertEqual(asset.colorSpace, "sRGB", asset.file)
            XCTAssertEqual(asset.bitsPerComponent, 8, asset.file)
            XCTAssertEqual(asset.channels, "RGBA", asset.file)
            XCTAssertLessThanOrEqual(asset.pixelSize.width, 2_048, asset.file)
            XCTAssertLessThanOrEqual(asset.pixelSize.height, 2_048, asset.file)
            XCTAssertEqual(asset.pivot, NormalizedPivot(x: 0.5, y: 0.5), asset.file)

            let url = resourcesDirectory.appendingPathComponent(asset.file)
            XCTAssertTrue(FileManager.default.fileExists(atPath: url.path), asset.file)
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
            XCTAssertTrue(image.alphaInfo.presentationHasAlpha, asset.file)
            XCTAssertEqual(
                properties[kCGImagePropertyProfileName] as? String,
                "sRGB IEC61966-2.1",
                asset.file
            )

            let rgba = try RGBAFixture(image)
            XCTAssertTrue(rgba.containsVisiblePixel, asset.file)
            if asset.kind == .background {
                XCTAssertTrue(rgba.isFullyOpaque, asset.file)
                XCTAssertEqual(asset.alphaMode, "opaque-rgba", asset.file)
            } else {
                XCTAssertTrue(rgba.hasTransparentBorder, asset.file)
            }
        }
    }

    func testHeroPairsHaveMatchingCanvasWhitePaintAndComplementaryDetails() throws {
        let manifest = try sourcePresentationManifest()
        let byName = Dictionary(uniqueKeysWithValues: manifest.assets.map { ($0.name, $0) })

        for vehicle in VehicleID.allCases {
            let prefix = vehicle.rawValue
            let paintAsset = try XCTUnwrap(byName["\(prefix)_hero_paint"])
            let detailsAsset = try XCTUnwrap(byName["\(prefix)_hero_details_shadow"])
            XCTAssertEqual(paintAsset.kind, .paintMask)
            XCTAssertEqual(detailsAsset.kind, .detailsShadow)
            XCTAssertEqual(paintAsset.vehicleID, prefix)
            XCTAssertEqual(detailsAsset.vehicleID, prefix)
            XCTAssertEqual(paintAsset.pixelSize, .init(width: 1024, height: 1024))
            XCTAssertEqual(detailsAsset.pixelSize, paintAsset.pixelSize)
            XCTAssertEqual(paintAsset.alphaMode, "straight-white-mask")
            XCTAssertEqual(detailsAsset.alphaMode, "straight")

            let paint = try decodedFixture(for: paintAsset)
            let details = try decodedFixture(for: detailsAsset)
            XCTAssertTrue(paint.visiblePixelsAreWhite, paintAsset.file)
            XCTAssertTrue(details.containsVisiblePixel, detailsAsset.file)
            XCTAssertTrue(paint.hasTransparentBorder, paintAsset.file)
            XCTAssertTrue(details.hasTransparentBorder, detailsAsset.file)
            XCTAssertTrue(paint.isAlphaDisjoint(with: details), prefix)
            XCTAssertNotNil(paint.firstOpaquePixel(disjointFrom: details), prefix)
            XCTAssertNotNil(details.firstOpaquePixel(disjointFrom: paint), prefix)
        }
    }

    func testGameplayPreloadDecodesZeroPresentationAssets() async throws {
        let decoder = PresentationDecoderSpy()
        _ = try PresentationAssetLibrary(decoder: decoder)
        let gameplayOnlyLibrary = try GameAssetLibrary()

        try await gameplayOnlyLibrary.preloadGameplayTextures()

        XCTAssertTrue(decoder.decodedFilenames.isEmpty)
        XCTAssertEqual(gameplayOnlyLibrary.cachedTextureCount, 10)

        let allLibrary = try GameAssetLibrary()

        try await allLibrary.preloadAll()

        XCTAssertTrue(decoder.decodedFilenames.isEmpty)
        XCTAssertEqual(allLibrary.manifest.assets.count, 19)
        XCTAssertEqual(allLibrary.cachedTextureCount, 19)
    }

    func testRouteAndCurrentVehicleLoadingIsLazyCachedAndInjectable() throws {
        let decoder = PresentationDecoderSpy()
        let cache = PresentationAssetImageCache()
        let library = try PresentationAssetLibrary(decoder: decoder, cache: cache)

        XCTAssertTrue(cache.cachedAssetNames.isEmpty)

        _ = try library.load(route: .hub, vehicleID: .rally)
        XCTAssertEqual(
            decoder.decodedFilenames,
            [
                "hub_expressway_portal.png",
                "rally_hero_paint.png",
                "rally_hero_details_shadow.png",
            ]
        )
        XCTAssertEqual(
            Set(cache.cachedAssetNames),
            [
                "hub_expressway_portal",
                "rally_hero_paint",
                "rally_hero_details_shadow",
            ]
        )

        _ = try library.load(route: .hub, vehicleID: .rally)
        XCTAssertEqual(decoder.decodedFilenames.count, 3)

        _ = try library.load(route: .maintenance, vehicleID: .rally)
        XCTAssertEqual(decoder.decodedFilenames.count, 4)
        XCTAssertEqual(decoder.decodedFilenames.last, "maintenance_pit_lane.png")

        _ = try library.load(route: .maintenance, vehicleID: .gt)
        XCTAssertEqual(decoder.decodedFilenames.count, 6)
        XCTAssertEqual(
            Set(library.cachedAssetNames),
            [
                "hub_expressway_portal", "maintenance_pit_lane",
                "rally_hero_paint", "rally_hero_details_shadow",
                "gt_hero_paint", "gt_hero_details_shadow",
            ]
        )

        _ = try library.load(route: .hub, vehicleID: .angular)
        XCTAssertEqual(decoder.decodedFilenames.count, 8)

        _ = try library.load(route: .hub, vehicleID: .rallyRS)
        XCTAssertEqual(decoder.decodedFilenames.count, 10)
        XCTAssertEqual(Set(decoder.decodedFilenames), expectedFilenames)

        let independentDecoder = PresentationDecoderSpy()
        let independentCache = PresentationAssetImageCache()
        let independentLibrary = try PresentationAssetLibrary(
            decoder: independentDecoder,
            cache: independentCache
        )
        XCTAssertTrue(independentCache.cachedAssetNames.isEmpty)

        _ = try independentLibrary.load(route: .hub, vehicleID: .rally)

        XCTAssertEqual(independentDecoder.decodedFilenames.count, 3)
        XCTAssertEqual(independentCache.cachedAssetNames.count, 3)
    }

    func testAllThirtyTwoCompositionsTintOnlyPaintPixels() throws {
        for vehicle in VehicleID.allCases {
            let paint = try sourceUIImage(named: "\(vehicle.rawValue)_hero_paint")
            let details = try sourceUIImage(named: "\(vehicle.rawValue)_hero_details_shadow")
            let paintFixture = try RGBAFixture(try XCTUnwrap(paint.cgImage))
            let detailsFixture = try RGBAFixture(try XCTUnwrap(details.cgImage))
            let paintPixel = try XCTUnwrap(
                paintFixture.firstOpaquePixel(disjointFrom: detailsFixture)
            )
            let detailsPixel = try XCTUnwrap(
                detailsFixture.firstOpaquePixel(disjointFrom: paintFixture)
            )
            let expectedDetail = detailsFixture.pixel(at: detailsPixel)
            var paintedColors = Set<[UInt8]>()

            for color in VehicleCatalog.colors {
                let rgba = color.rgba
                let composite = PresentationVehicleCompositor.image(
                    hero: PresentationHeroPair(paint: paint, detailsShadow: details),
                    tint: UIColor(
                        red: rgba.red,
                        green: rgba.green,
                        blue: rgba.blue,
                        alpha: rgba.alpha
                    )
                )
                let fixture = try RGBAFixture(try XCTUnwrap(composite.cgImage))
                let painted = fixture.pixel(at: paintPixel)
                let fixedDetail = fixture.pixel(at: detailsPixel)
                paintedColors.insert(Array(painted.prefix(3)))
                XCTAssertEqual(fixedDetail, expectedDetail, "\(vehicle.rawValue) \(color.id)")
                XCTAssertTrue(
                    fixture.hasTransparentBorder,
                    "Composite canvas must remain transparent for \(vehicle.rawValue) \(color.id)"
                )
            }

            XCTAssertEqual(paintedColors.count, 8, vehicle.rawValue)
        }
        XCTAssertEqual(VehicleCatalog.allSelections.count, 32)
    }

    func testPresentationResourcesAreRegisteredOnlyInIOSResourcePhase() throws {
        let project = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "WatchCarRacer.xcodeproj/project.pbxproj"
            ),
            encoding: .utf8
        )
        let iosResources = try XCTUnwrap(
            project.block(startingWith: "050000000000000000000003 /* Resources */ = {")
        )
        let watchResources = try XCTUnwrap(
            project.block(startingWith: "050000000000000000000013 /* Resources */ = {")
        )

        XCTAssertTrue(iosResources.contains("PresentationAssetManifest.json in Resources"))
        for filename in expectedFilenames {
            XCTAssertTrue(iosResources.contains("\(filename) in Resources"), filename)
            XCTAssertFalse(watchResources.contains(filename), filename)
        }
        XCTAssertFalse(watchResources.contains("PresentationAssetManifest"))
    }

    func testProvenanceContainsActualSHA256ForEveryPresentationAsset() throws {
        let provenance = try String(
            contentsOf: repositoryRoot.appendingPathComponent("docs/assets/provenance.md"),
            encoding: .utf8
        )
        let manifest = try sourcePresentationManifest()

        for asset in manifest.assets {
            let data = try Data(contentsOf: resourcesDirectory.appendingPathComponent(asset.file))
            let sha = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            XCTAssertTrue(provenance.contains("`\(asset.file)`"), asset.file)
            XCTAssertTrue(provenance.contains("`\(sha)`"), asset.file)
        }
    }

    private var expectedNames: Set<String> {
        [
            "hub_expressway_portal", "maintenance_pit_lane",
            "rally_hero_paint", "rally_hero_details_shadow",
            "gt_hero_paint", "gt_hero_details_shadow",
            "angular_hero_paint", "angular_hero_details_shadow",
            "rally-rs_hero_paint", "rally-rs_hero_details_shadow",
        ]
    }

    private var expectedFilenames: Set<String> {
        Set(expectedNames.map { "\($0).png" })
    }

    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private var resourcesDirectory: URL {
        repositoryRoot.appendingPathComponent("WatchCarRacer/iOS/Resources")
    }

    private func sourcePresentationManifest() throws -> PresentationAssetManifest {
        let data = try Data(
            contentsOf: resourcesDirectory.appendingPathComponent(
                "PresentationAssetManifest.json"
            )
        )
        return try JSONDecoder().decode(PresentationAssetManifest.self, from: data)
    }

    private func sourceGameplayManifest() throws -> AssetManifest {
        let data = try Data(
            contentsOf: resourcesDirectory.appendingPathComponent("AssetManifest.json")
        )
        return try JSONDecoder().decode(AssetManifest.self, from: data)
    }

    private func decodedFixture(
        for asset: PresentationAssetManifest.Asset
    ) throws -> RGBAFixture {
        guard let source = CGImageSourceCreateWithURL(
            resourcesDirectory.appendingPathComponent(asset.file) as CFURL,
            nil
        ), let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return try RGBAFixture(image)
    }

    private func sourceUIImage(named name: String) throws -> UIImage {
        let url = resourcesDirectory.appendingPathComponent("Presentation/\(name).png")
        return try XCTUnwrap(UIImage(contentsOfFile: url.path))
    }
}

@MainActor
private final class PresentationDecoderSpy: PresentationAssetImageDecoding {
    private(set) var decodedFilenames: [String] = []

    func decodeImage(at url: URL) -> UIImage? {
        decodedFilenames.append(url.lastPathComponent)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(
            size: CGSize(width: 1, height: 1),
            format: format
        ).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
        }
    }
}

private struct RGBAFixture {
    let width: Int
    let height: Int
    let bytes: [UInt8]

    init(_ image: CGImage) throws {
        width = image.width
        height = image.height
        var buffer = [UInt8](repeating: 0, count: width * height * 4)
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: &buffer,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: colorSpace,
                bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue
                    | CGImageAlphaInfo.premultipliedLast.rawValue
              ) else {
            throw CocoaError(.coderInvalidValue)
        }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        bytes = buffer
    }

    var containsVisiblePixel: Bool {
        stride(from: 3, to: bytes.count, by: 4).contains { bytes[$0] > 0 }
    }

    var isFullyOpaque: Bool {
        stride(from: 3, to: bytes.count, by: 4).allSatisfy { bytes[$0] == 255 }
    }

    var hasTransparentBorder: Bool {
        let horizontal = (0..<width).allSatisfy { x in
            alpha(x: x, y: 0) == 0 && alpha(x: x, y: height - 1) == 0
        }
        let vertical = (0..<height).allSatisfy { y in
            alpha(x: 0, y: y) == 0 && alpha(x: width - 1, y: y) == 0
        }
        return horizontal && vertical
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

    func isAlphaDisjoint(with other: RGBAFixture) -> Bool {
        guard width == other.width, height == other.height else { return false }
        return stride(from: 3, to: bytes.count, by: 4).allSatisfy {
            bytes[$0] == 0 || other.bytes[$0] == 0
        }
    }

    func firstOpaquePixel(disjointFrom other: RGBAFixture) -> Int? {
        guard width == other.width, height == other.height else { return nil }
        for pixel in 0..<(width * height) {
            let alphaOffset = pixel * 4 + 3
            if bytes[alphaOffset] == 255 && other.bytes[alphaOffset] == 0 {
                return pixel
            }
        }
        return nil
    }

    func pixel(at index: Int) -> [UInt8] {
        let offset = index * 4
        return Array(bytes[offset..<(offset + 4)])
    }

    private func alpha(x: Int, y: Int) -> UInt8 {
        bytes[(y * width + x) * 4 + 3]
    }
}

private extension CGImageAlphaInfo {
    var presentationHasAlpha: Bool {
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

private extension String {
    func block(startingWith marker: String) -> String? {
        guard let start = range(of: marker)?.lowerBound,
              let end = self[start...].range(of: "\n\t\t};")?.upperBound else {
            return nil
        }
        return String(self[start..<end])
    }
}
