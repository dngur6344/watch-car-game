import Foundation
import SpriteKit
import UIKit

struct AssetManifest: Decodable, Sendable {
    struct Asset: Decodable, Equatable, Sendable {
        struct PixelSize: Decodable, Equatable, Sendable {
            let width: Int
            let height: Int
        }

        let name: String
        let file: String
        let family: String
        let atlas: String?
        let pixelSize: PixelSize
        let anchor: NormalizedPivot
        let colorSpace: String
        let bitsPerComponent: Int
        let channels: String
        let alphaMode: String
    }

    let schemaVersion: Int
    let direction: String
    let assets: [Asset]
}

enum GameAssetLibraryError: Error, Equatable, LocalizedError {
    case missingManifest
    case invalidManifest(String)
    case duplicateTextureName(String)
    case missingTexture(String)
    case emptyTexture(String)

    var errorDescription: String? {
        switch self {
        case .missingManifest:
            return "AssetManifest.json is missing from the iOS application bundle."
        case let .invalidManifest(reason):
            return "AssetManifest.json is invalid: \(reason)"
        case let .duplicateTextureName(name):
            return "AssetManifest.json declares the texture name more than once: \(name)."
        case let .missingTexture(name):
            return "Required game texture is missing from the iOS application bundle: \(name)."
        case let .emptyTexture(name):
            return "Required game texture resolved with an empty size: \(name)."
        }
    }
}

@MainActor
final class GameAssetLibrary {
    private static let atlasNames = ["Vehicles", "Obstacles", "Environment"]

    let manifest: AssetManifest

    private let bundle: Bundle
    private let atlases: [String: SKTextureAtlas]
    private let assetsByName: [String: AssetManifest.Asset]
    private var textureCache: [String: SKTexture] = [:]
    private(set) var preloadedAtlasNames: [String] = []

    init(bundle: Bundle = .main) throws {
        self.bundle = bundle
        guard let manifestURL = bundle.url(
            forResource: "AssetManifest",
            withExtension: "json"
        ) else {
            throw GameAssetLibraryError.missingManifest
        }

        do {
            manifest = try JSONDecoder().decode(
                AssetManifest.self,
                from: Data(contentsOf: manifestURL)
            )
        } catch {
            throw GameAssetLibraryError.invalidManifest(error.localizedDescription)
        }

        var index: [String: AssetManifest.Asset] = [:]
        for asset in manifest.assets {
            guard index.updateValue(asset, forKey: asset.name) == nil else {
                throw GameAssetLibraryError.duplicateTextureName(asset.name)
            }
        }
        assetsByName = index
        atlases = Dictionary(
            uniqueKeysWithValues: Self.atlasNames.map {
                ($0, SKTextureAtlas(named: $0))
            }
        )
    }

    func preloadVehicleTextures() async throws {
        try await preload(atlasNames: ["Vehicles"], standaloneNames: [])
    }

    func preloadGameplayTextures() async throws {
        try await preload(
            atlasNames: ["Obstacles", "Environment"],
            standaloneNames: manifest.assets.filter { $0.atlas == nil }.map(\.name)
        )
    }

    func preloadAll() async throws {
        try await preloadVehicleTextures()
        try await preloadGameplayTextures()
    }

    func texture(named name: String) throws -> SKTexture {
        if let cached = textureCache[name] {
            return cached
        }
        guard let asset = assetsByName[name] else {
            throw GameAssetLibraryError.missingTexture(name)
        }

        let texture: SKTexture
        if let atlasName = asset.atlas {
            guard let atlas = atlases[atlasName], atlasContains(atlas, textureName: name) else {
                throw GameAssetLibraryError.missingTexture(name)
            }
            texture = atlas.textureNamed(name)
        } else {
            guard let url = bundle.url(forResource: name, withExtension: "png"),
                  let image = UIImage(contentsOfFile: url.path) else {
                throw GameAssetLibraryError.missingTexture(name)
            }
            texture = SKTexture(image: image)
        }

        guard texture.size().width > 0, texture.size().height > 0 else {
            throw GameAssetLibraryError.emptyTexture(name)
        }
        texture.filteringMode = .linear
        textureCache[name] = texture
        return texture
    }

    var cachedTextureCount: Int {
        textureCache.count
    }

    private func preload(
        atlasNames: [String],
        standaloneNames: [String]
    ) async throws {
        for atlasName in atlasNames {
            guard !preloadedAtlasNames.contains(atlasName) else { continue }
            guard let atlas = atlases[atlasName] else {
                throw GameAssetLibraryError.missingTexture(atlasName)
            }

            await withCheckedContinuation { continuation in
                SKTextureAtlas.preloadTextureAtlases([atlas]) {
                    continuation.resume()
                }
            }

            let textureNames = manifest.assets
                .filter { $0.atlas == atlasName }
                .map(\.name)
            for textureName in textureNames {
                _ = try texture(named: textureName)
            }
            preloadedAtlasNames.append(atlasName)
        }

        for name in standaloneNames {
            _ = try texture(named: name)
        }
    }

    private func atlasContains(_ atlas: SKTextureAtlas, textureName: String) -> Bool {
        atlas.textureNames.contains { candidate in
            candidate == textureName
                || (candidate as NSString).deletingPathExtension == textureName
        }
    }
}
