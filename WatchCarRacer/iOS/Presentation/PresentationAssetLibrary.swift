import Foundation
import UIKit

struct PresentationAssetManifest: Decodable, Sendable {
    struct Asset: Decodable, Equatable, Sendable {
        struct PixelSize: Decodable, Equatable, Sendable {
            let width: Int
            let height: Int
        }

        enum Kind: String, Decodable, Sendable {
            case background
            case paintMask = "paint-mask"
            case detailsShadow = "details-shadow"
        }

        let name: String
        let file: String
        let family: String
        let kind: Kind
        let route: String?
        let vehicleID: String?
        let pixelSize: PixelSize
        let pivot: NormalizedPivot
        let colorSpace: String
        let bitsPerComponent: Int
        let channels: String
        let alphaMode: String
    }

    let schemaVersion: Int
    let assets: [Asset]
}

enum PresentationRoute: String, Equatable, Sendable {
    case hub
    case maintenance
}

struct PresentationHeroPair {
    let paint: UIImage
    let detailsShadow: UIImage
}

struct PresentationRouteAssets {
    let background: UIImage
    let hero: PresentationHeroPair
}

enum PresentationAssetLibraryError: Error, Equatable, LocalizedError {
    case missingManifest
    case invalidManifest(String)
    case duplicateAssetName(String)
    case missingAsset(String)
    case invalidVehicle(String)

    var errorDescription: String? {
        switch self {
        case .missingManifest:
            return "PresentationAssetManifest.json is missing from the iOS application bundle."
        case let .invalidManifest(reason):
            return "PresentationAssetManifest.json is invalid: \(reason)"
        case let .duplicateAssetName(name):
            return "PresentationAssetManifest.json declares \(name) more than once."
        case let .missingAsset(name):
            return "Presentation asset \(name) is missing or could not be decoded."
        case let .invalidVehicle(vehicle):
            return "Presentation assets are not defined for vehicle \(vehicle)."
        }
    }
}

@MainActor
protocol PresentationAssetImageDecoding {
    func decodeImage(at url: URL) -> UIImage?
}

@MainActor
struct BundlePresentationAssetImageDecoder: PresentationAssetImageDecoding {
    func decodeImage(at url: URL) -> UIImage? {
        UIImage(contentsOfFile: url.path)
    }
}

@MainActor
protocol PresentationAssetImageCaching: AnyObject {
    var cachedAssetNames: [String] { get }

    func image(named name: String) -> UIImage?
    func store(_ image: UIImage, named name: String)
}

@MainActor
final class PresentationAssetImageCache: PresentationAssetImageCaching {
    private var imagesByName: [String: UIImage] = [:]

    var cachedAssetNames: [String] {
        imagesByName.keys.sorted()
    }

    func image(named name: String) -> UIImage? {
        imagesByName[name]
    }

    func store(_ image: UIImage, named name: String) {
        imagesByName[name] = image
    }
}

@MainActor
final class PresentationAssetLibrary {
    let manifest: PresentationAssetManifest

    private let bundle: Bundle
    private let decoder: any PresentationAssetImageDecoding
    private let cache: any PresentationAssetImageCaching
    private let assetsByName: [String: PresentationAssetManifest.Asset]

    init(
        bundle: Bundle = .main,
        decoder: any PresentationAssetImageDecoding = BundlePresentationAssetImageDecoder(),
        cache: any PresentationAssetImageCaching = PresentationAssetImageCache()
    ) throws {
        self.bundle = bundle
        self.decoder = decoder
        self.cache = cache

        guard let manifestURL = bundle.url(
            forResource: "PresentationAssetManifest",
            withExtension: "json"
        ) else {
            throw PresentationAssetLibraryError.missingManifest
        }

        do {
            manifest = try JSONDecoder().decode(
                PresentationAssetManifest.self,
                from: Data(contentsOf: manifestURL)
            )
        } catch {
            throw PresentationAssetLibraryError.invalidManifest(error.localizedDescription)
        }

        var index: [String: PresentationAssetManifest.Asset] = [:]
        for asset in manifest.assets {
            guard index.updateValue(asset, forKey: asset.name) == nil else {
                throw PresentationAssetLibraryError.duplicateAssetName(asset.name)
            }
        }
        assetsByName = index
    }

    func load(
        route: PresentationRoute,
        vehicleID: VehicleID
    ) throws -> PresentationRouteAssets {
        let vehiclePrefix = vehicleID.rawValue
        guard assetsByName["\(vehiclePrefix)_hero_paint"] != nil,
              assetsByName["\(vehiclePrefix)_hero_details_shadow"] != nil else {
            throw PresentationAssetLibraryError.invalidVehicle(vehiclePrefix)
        }

        let backgroundName: String
        switch route {
        case .hub:
            backgroundName = "hub_expressway_portal"
        case .maintenance:
            backgroundName = "maintenance_pit_lane"
        }

        return PresentationRouteAssets(
            background: try image(named: backgroundName),
            hero: PresentationHeroPair(
                paint: try image(named: "\(vehiclePrefix)_hero_paint"),
                detailsShadow: try image(named: "\(vehiclePrefix)_hero_details_shadow")
            )
        )
    }

    var cachedAssetNames: [String] {
        cache.cachedAssetNames
    }

    private func image(named name: String) throws -> UIImage {
        if let cached = cache.image(named: name) {
            return cached
        }
        guard assetsByName[name] != nil,
              let url = bundle.url(forResource: name, withExtension: "png"),
              let image = decoder.decodeImage(at: url),
              image.size.width > 0,
              image.size.height > 0 else {
            throw PresentationAssetLibraryError.missingAsset(name)
        }
        cache.store(image, named: name)
        return image
    }
}

@MainActor
enum PresentationVehicleCompositor {
    static func image(hero: PresentationHeroPair, tint: UIColor) -> UIImage {
        let size = hero.paint.size
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        format.preferredRange = .standard

        return UIGraphicsImageRenderer(size: size, format: format).image { rendererContext in
            let bounds = CGRect(origin: .zero, size: size)
            hero.paint.draw(in: bounds)
            rendererContext.cgContext.setBlendMode(.sourceIn)
            tint.setFill()
            rendererContext.cgContext.fill(bounds)
            rendererContext.cgContext.setBlendMode(.normal)
            hero.detailsShadow.draw(in: bounds)
        }
    }
}
