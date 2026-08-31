import CryptoKit
import Foundation
import RealityKit

enum RacingEnvironmentTextureSemantic: String, CaseIterable, Sendable {
    case color = ".color"
    case normal = ".normal"
    case scalar = ".scalar"

    var realityKitSemantic: TextureResource.Semantic {
        switch self {
        case .color: .color
        case .normal: .normal
        case .scalar: .scalar
        }
    }
}

enum RacingEnvironmentMipmapPolicy: String, Sendable {
    case allocateAndGenerateAll
}

struct RacingEnvironmentTextureAssetContract: Equatable, Sendable {
    let filename: String
    let channelRole: String
    let colorEncoding: String
    let semantic: RacingEnvironmentTextureSemantic
    let mipmapPolicy: RacingEnvironmentMipmapPolicy
}

struct RacingEnvironmentGeometryAssetContract: Equatable, Sendable {
    let filename: String
    let rootName: String
}

struct RacingEnvironmentTrackAssetContract: Equatable, Sendable {
    let track: RacingTrack
    let assetSlug: String
    let base: RacingEnvironmentGeometryAssetContract
    let enhanced: RacingEnvironmentGeometryAssetContract
    let textures: [RacingEnvironmentTextureAssetContract]
}

enum RacingEnvironmentAssetContract {
    static let manifestFilename = "RacingEnvironmentAssetManifest.json"

    static func mapping(for track: RacingTrack) -> RacingEnvironmentTrackAssetContract {
        let assetSlug: String
        let rootPrefix: String
        switch track {
        case .coastal:
            assetSlug = "ocean"
            rootPrefix = "Ocean"
        case .alpine:
            assetSlug = "alpine"
            rootPrefix = "Alpine"
        case .desert:
            assetSlug = "desert"
            rootPrefix = "Desert"
        }

        return RacingEnvironmentTrackAssetContract(
            track: track,
            assetSlug: assetSlug,
            base: RacingEnvironmentGeometryAssetContract(
                filename: "\(assetSlug)_environment_base.usdz",
                rootName: "\(rootPrefix)EnvironmentBase"
            ),
            enhanced: RacingEnvironmentGeometryAssetContract(
                filename: "\(assetSlug)_environment_enhanced.usdz",
                rootName: "\(rootPrefix)EnvironmentEnhanced"
            ),
            textures: [
                RacingEnvironmentTextureAssetContract(
                    filename: "\(assetSlug)_terrain_basecolor.png",
                    channelRole: "baseColor",
                    colorEncoding: "sRGB",
                    semantic: .color,
                    mipmapPolicy: .allocateAndGenerateAll
                ),
                RacingEnvironmentTextureAssetContract(
                    filename: "\(assetSlug)_terrain_normal.png",
                    channelRole: "tangentSpaceNormal",
                    colorEncoding: "linear-sRGB",
                    semantic: .normal,
                    mipmapPolicy: .allocateAndGenerateAll
                ),
                RacingEnvironmentTextureAssetContract(
                    filename: "\(assetSlug)_terrain_roughness.png",
                    channelRole: "roughnessScalarReplicatedRGBA",
                    colorEncoding: "linear-sRGB",
                    semantic: .scalar,
                    mipmapPolicy: .allocateAndGenerateAll
                ),
            ]
        )
    }
}

enum RacingEnvironmentResourceFallbackReason: Equatable, Sendable {
    case manifestUnavailable
    case manifestInvalid
    case assetMissing(String)
    case assetIntegrityFailed(String)
    case assetDecodeFailed(String)
}

enum RacingEnvironmentResourceDiagnostic: Equatable, Sendable {
    case authored
    case fallback(RacingEnvironmentResourceFallbackReason)

    var isAuthored: Bool {
        self == .authored
    }
}

struct RacingEnvironmentResources: Sendable {
    let track: RacingTrack
    let requestedTier: RacingEnvironmentQualityTier
    let effectiveTier: RacingEnvironmentQualityTier
    let baseEntity: Entity
    let enhancedEntity: Entity?
    let baseColorTexture: TextureResource?
    let normalTexture: TextureResource?
    let roughnessTexture: TextureResource?
    let diagnostic: RacingEnvironmentResourceDiagnostic

    fileprivate func projected(for requestedTier: RacingEnvironmentQualityTier) -> Self {
        guard diagnostic.isAuthored else {
            return Self(
                track: track,
                requestedTier: requestedTier,
                effectiveTier: .baseline,
                baseEntity: baseEntity,
                enhancedEntity: nil,
                baseColorTexture: baseColorTexture,
                normalTexture: normalTexture,
                roughnessTexture: roughnessTexture,
                diagnostic: diagnostic
            )
        }

        let usesEnhanced = requestedTier == .enhanced && enhancedEntity != nil
        return Self(
            track: track,
            requestedTier: requestedTier,
            effectiveTier: usesEnhanced ? .enhanced : .baseline,
            baseEntity: baseEntity,
            enhancedEntity: usesEnhanced ? enhancedEntity : nil,
            baseColorTexture: baseColorTexture,
            normalTexture: normalTexture,
            roughnessTexture: roughnessTexture,
            diagnostic: diagnostic
        )
    }
}

struct RacingEnvironmentResourcesComponent: Component {
    let resources: RacingEnvironmentResources
}

struct RacingEnvironmentAssetSource: Sendable {
    let manifestData: @Sendable () throws -> Data
    let resourceURL: @Sendable (String) -> URL?

    static func bundled(_ bundle: Bundle = .main) -> Self {
        Self(
            manifestData: {
                guard let url = bundle.url(
                    forResource: RacingEnvironmentAssetContract.manifestFilename
                        .replacingOccurrences(of: ".json", with: ""),
                    withExtension: "json"
                ) else {
                    throw RacingEnvironmentAssetLoadError.manifestUnavailable
                }
                return try Data(contentsOf: url)
            },
            resourceURL: { filename in
                let file = URL(fileURLWithPath: filename)
                return bundle.url(
                    forResource: file.deletingPathExtension().lastPathComponent,
                    withExtension: file.pathExtension
                )
            }
        )
    }
}

struct RacingEnvironmentAssetLibraryDiagnostics: Equatable, Sendable {
    let cachedTrackCount: Int
    let cachedTrack: RacingTrack?
    let cachedTier: RacingEnvironmentQualityTier?
    let decodeOperationCount: Int
    let decodedAssetCounts: [String: Int]
}

actor RacingEnvironmentAssetLibrary {
    static let shared = RacingEnvironmentAssetLibrary()

    private struct InFlight {
        let id: UUID
        let track: RacingTrack
        let tier: RacingEnvironmentQualityTier
        let task: Task<RacingEnvironmentLoadResult, Never>
    }

    private let source: RacingEnvironmentAssetSource
    private var cache: RacingEnvironmentResources?
    private var inFlight: InFlight?
    private var decodeOperationCount = 0
    private var decodedAssetCounts: [String: Int] = [:]

    init(source: RacingEnvironmentAssetSource = .bundled()) {
        self.source = source
    }

    func resources(
        for track: RacingTrack,
        tier requestedTier: RacingEnvironmentQualityTier
    ) async -> RacingEnvironmentResources {
        if var cached = cache, cached.track == track {
            if requestedTier == .baseline || cached.effectiveTier == .enhanced
                || !cached.diagnostic.isAuthored {
                cached = cached.projected(for: requestedTier)
                cache = cached
                return cached
            }
        } else if cache?.track != track {
            cache = nil
        }

        if let inFlight,
           inFlight.track == track,
           inFlight.tier == requestedTier {
            let result = await inFlight.task.value
            finish(result, operationID: inFlight.id)
            return result.resources
        }

        inFlight?.task.cancel()
        let operationID = UUID()
        let source = source
        let cachedBaseline = cache?.track == track ? cache : nil
        let task = Task {
            if requestedTier == .enhanced,
               let cachedBaseline,
               cachedBaseline.diagnostic.isAuthored {
                return await Self.augment(cachedBaseline, source: source)
            }
            return await Self.load(track: track, tier: requestedTier, source: source)
        }
        inFlight = InFlight(
            id: operationID,
            track: track,
            tier: requestedTier,
            task: task
        )
        decodeOperationCount += 1

        let result = await task.value
        finish(result, operationID: operationID)
        return result.resources
    }

    private func finish(_ result: RacingEnvironmentLoadResult, operationID: UUID) {
        guard inFlight?.id == operationID else { return }
        cache = result.resources
        inFlight = nil
        for filename in result.decodedAssetNames {
            decodedAssetCounts[filename, default: 0] += 1
        }
    }

    func diagnostics() -> RacingEnvironmentAssetLibraryDiagnostics {
        RacingEnvironmentAssetLibraryDiagnostics(
            cachedTrackCount: cache == nil ? 0 : 1,
            cachedTrack: cache?.track,
            cachedTier: cache?.effectiveTier,
            decodeOperationCount: decodeOperationCount,
            decodedAssetCounts: decodedAssetCounts
        )
    }

    private static func load(
        track: RacingTrack,
        tier: RacingEnvironmentQualityTier,
        source: RacingEnvironmentAssetSource
    ) async -> RacingEnvironmentLoadResult {
        do {
            let selection = try validatedSelection(track: track, tier: tier, source: source)
            guard let baseURL = selection.baseURL else {
                throw RacingEnvironmentAssetLoadError.manifestInvalid
            }
            async let baseEntity = loadEntity(
                at: baseURL,
                filename: selection.mapping.base.filename
            )
            async let baseColorTexture = loadTexture(
                selection.textureURLs[.color],
                contract: try selection.textureContract(.color)
            )
            async let normalTexture = loadTexture(
                selection.textureURLs[.normal],
                contract: try selection.textureContract(.normal)
            )
            async let roughnessTexture = loadTexture(
                selection.textureURLs[.scalar],
                contract: try selection.textureContract(.scalar)
            )

            let enhancedEntity: Entity?
            if let enhancedURL = selection.enhancedURL {
                enhancedEntity = try await loadEntity(
                    at: enhancedURL,
                    filename: selection.mapping.enhanced.filename
                )
            } else {
                enhancedEntity = nil
            }

            let loaded = try await (
                baseEntity,
                baseColorTexture,
                normalTexture,
                roughnessTexture
            )
            var decodedAssetNames = [
                selection.mapping.base.filename,
                try selection.textureContract(.color).filename,
                try selection.textureContract(.normal).filename,
                try selection.textureContract(.scalar).filename,
            ]
            if enhancedEntity != nil {
                decodedAssetNames.append(selection.mapping.enhanced.filename)
            }
            return RacingEnvironmentLoadResult(
                resources: RacingEnvironmentResources(
                    track: track,
                    requestedTier: tier,
                    effectiveTier: enhancedEntity == nil ? .baseline : .enhanced,
                    baseEntity: loaded.0,
                    enhancedEntity: enhancedEntity,
                    baseColorTexture: loaded.1,
                    normalTexture: loaded.2,
                    roughnessTexture: loaded.3,
                    diagnostic: .authored
                ),
                decodedAssetNames: decodedAssetNames
            )
        } catch {
            return await fallback(track: track, requestedTier: tier, error: error)
        }
    }

    private static func augment(
        _ baseline: RacingEnvironmentResources,
        source: RacingEnvironmentAssetSource
    ) async -> RacingEnvironmentLoadResult {
        do {
            let selection = try validatedSelection(
                track: baseline.track,
                tier: .enhanced,
                source: source,
                validatesBaseAndTextures: false
            )
            guard let enhancedURL = selection.enhancedURL else {
                throw RacingEnvironmentAssetLoadError.manifestInvalid
            }
            let entity = try await loadEntity(
                at: enhancedURL,
                filename: selection.mapping.enhanced.filename
            )
            return RacingEnvironmentLoadResult(
                resources: RacingEnvironmentResources(
                    track: baseline.track,
                    requestedTier: .enhanced,
                    effectiveTier: .enhanced,
                    baseEntity: baseline.baseEntity,
                    enhancedEntity: entity,
                    baseColorTexture: baseline.baseColorTexture,
                    normalTexture: baseline.normalTexture,
                    roughnessTexture: baseline.roughnessTexture,
                    diagnostic: .authored
                ),
                decodedAssetNames: [selection.mapping.enhanced.filename]
            )
        } catch {
            return RacingEnvironmentLoadResult(
                resources: RacingEnvironmentResources(
                    track: baseline.track,
                    requestedTier: .enhanced,
                    effectiveTier: .baseline,
                    baseEntity: baseline.baseEntity,
                    enhancedEntity: nil,
                    baseColorTexture: baseline.baseColorTexture,
                    normalTexture: baseline.normalTexture,
                    roughnessTexture: baseline.roughnessTexture,
                    diagnostic: .fallback(fallbackReason(for: error))
                ),
                decodedAssetNames: []
            )
        }
    }

    private static func loadEntity(at url: URL, filename: String) async throws -> Entity {
        do {
            return try await Entity(
                contentsOf: url,
                withName: "racing.environment.\(filename)"
            )
        } catch {
            throw RacingEnvironmentAssetLoadError.assetDecodeFailed(filename)
        }
    }

    private static func loadTexture(
        _ url: URL?,
        contract: RacingEnvironmentTextureAssetContract
    ) async throws -> TextureResource {
        guard let url else {
            throw RacingEnvironmentAssetLoadError.assetMissing(contract.filename)
        }
        do {
            return try await TextureResource(
                contentsOf: url,
                withName: "racing.environment.\(contract.filename)",
                options: TextureResource.CreateOptions(
                    semantic: contract.semantic.realityKitSemantic,
                    mipmapsMode: .allocateAndGenerateAll
                )
            )
        } catch {
            throw RacingEnvironmentAssetLoadError.assetDecodeFailed(contract.filename)
        }
    }

    private static func validatedSelection(
        track: RacingTrack,
        tier: RacingEnvironmentQualityTier,
        source: RacingEnvironmentAssetSource,
        validatesBaseAndTextures: Bool = true
    ) throws -> RacingEnvironmentValidatedSelection {
        let manifestData: Data
        do {
            manifestData = try source.manifestData()
        } catch {
            throw RacingEnvironmentAssetLoadError.manifestUnavailable
        }

        let manifest: RacingEnvironmentRuntimeManifest
        do {
            manifest = try JSONDecoder().decode(
                RacingEnvironmentRuntimeManifest.self,
                from: manifestData
            )
        } catch {
            throw RacingEnvironmentAssetLoadError.manifestInvalid
        }
        try validate(manifest)

        let mapping = RacingEnvironmentAssetContract.mapping(for: track)
        guard let manifestTrack = manifest.tracks.first(where: { $0.id == track.rawValue }) else {
            throw RacingEnvironmentAssetLoadError.manifestInvalid
        }

        let baseURL: URL?
        var textureURLs: [RacingEnvironmentTextureSemantic: URL] = [:]
        if validatesBaseAndTextures {
            baseURL = try validatedURL(
                filename: mapping.base.filename,
                expectedHash: manifestTrack.geometry.base.runtimeUSDZSHA256,
                source: source
            )
            for textureContract in mapping.textures {
                guard let texture = manifestTrack.textures.first(where: {
                    $0.filename == textureContract.filename
                }) else {
                    throw RacingEnvironmentAssetLoadError.manifestInvalid
                }
                textureURLs[textureContract.semantic] = try validatedURL(
                    filename: textureContract.filename,
                    expectedHash: texture.derivedSHA256,
                    source: source
                )
            }
        } else {
            baseURL = nil
        }

        let enhancedURL: URL?
        if tier == .enhanced {
            enhancedURL = try validatedURL(
                filename: mapping.enhanced.filename,
                expectedHash: manifestTrack.geometry.enhanced.runtimeUSDZSHA256,
                source: source
            )
        } else {
            enhancedURL = nil
        }

        return RacingEnvironmentValidatedSelection(
            mapping: mapping,
            baseURL: baseURL,
            enhancedURL: enhancedURL,
            textureURLs: textureURLs
        )
    }

    private static func validate(_ manifest: RacingEnvironmentRuntimeManifest) throws {
        guard manifest.schemaVersion == 1,
              manifest.revision == 1,
              manifest.license == "project-original",
              manifest.hashAlgorithm == "SHA-256",
              manifest.textureContract.width == 1_024,
              manifest.textureContract.height == 1_024,
              manifest.textureContract.bitsPerComponent == 8,
              manifest.textureContract.channels == "RGBA",
              manifest.textureContract.mipmapPolicy ==
                RacingEnvironmentMipmapPolicy.allocateAndGenerateAll.rawValue,
              manifest.textureContract.runtimeGenerationAllowed == false,
              manifest.tracks.count == RacingTrack.allCases.count else {
            throw RacingEnvironmentAssetLoadError.manifestInvalid
        }

        for track in RacingTrack.allCases {
            let mapping = RacingEnvironmentAssetContract.mapping(for: track)
            guard manifest.tracks.filter({ $0.id == track.rawValue }).count == 1,
                  let entry = manifest.tracks.first(where: { $0.id == track.rawValue }),
                  entry.assetSlug == mapping.assetSlug else {
                throw RacingEnvironmentAssetLoadError.manifestInvalid
            }
            try validate(entry.geometry.base, against: mapping.base, tier: "base")
            try validate(entry.geometry.enhanced, against: mapping.enhanced, tier: "enhanced")
            guard entry.textures.count == mapping.textures.count else {
                throw RacingEnvironmentAssetLoadError.manifestInvalid
            }
            for expected in mapping.textures {
                guard let texture = entry.textures.first(where: {
                    $0.filename == expected.filename
                }),
                      texture.channelRole == expected.channelRole,
                      texture.colorEncoding == expected.colorEncoding,
                      texture.realityKitSemantic == expected.semantic.rawValue,
                      texture.pixelFormat == "RGBA8",
                      texture.width == 1_024,
                      texture.height == 1_024,
                      texture.expectedBaseLevelDecodedBytes == 4_194_304,
                      texture.hashStatus == "verified",
                      isSHA256(texture.derivedSHA256) else {
                    throw RacingEnvironmentAssetLoadError.manifestInvalid
                }
            }
        }
    }

    private static func validate(
        _ pack: RacingEnvironmentRuntimeManifest.Pack,
        against expected: RacingEnvironmentGeometryAssetContract,
        tier: String
    ) throws {
        guard pack.rootName == expected.rootName,
              pack.tier == tier,
              pack.role == "racing-environment-pack",
              pack.runtimeUSDZ == expected.filename,
              pack.hashStatus == "verified",
              isSHA256(pack.runtimeUSDZSHA256) else {
            throw RacingEnvironmentAssetLoadError.manifestInvalid
        }
    }

    private static func validatedURL(
        filename: String,
        expectedHash: String,
        source: RacingEnvironmentAssetSource
    ) throws -> URL {
        guard let url = source.resourceURL(filename) else {
            throw RacingEnvironmentAssetLoadError.assetMissing(filename)
        }
        guard url.lastPathComponent == filename else {
            throw RacingEnvironmentAssetLoadError.assetIntegrityFailed(filename)
        }
        // Xcode converts bundled PNGs to CgBI, so their encoded bytes intentionally differ
        // from the committed derived SHA. Their manifest SHA/status/semantic are validated
        // above and RealityKit validates the runtime payload while decoding.
        guard url.pathExtension.lowercased() != "png" else {
            return url
        }
        let actualHash: String
        do {
            actualHash = SHA256.hash(data: try Data(contentsOf: url))
                .map { String(format: "%02x", $0) }
                .joined()
        } catch {
            throw RacingEnvironmentAssetLoadError.assetMissing(filename)
        }
        guard actualHash == expectedHash else {
            throw RacingEnvironmentAssetLoadError.assetIntegrityFailed(filename)
        }
        return url
    }

    private static func isSHA256(_ value: String) -> Bool {
        value.count == 64 && value.allSatisfy { $0.isHexDigit && !$0.isUppercase }
    }

    private static func fallback(
        track: RacingTrack,
        requestedTier: RacingEnvironmentQualityTier,
        error: Error
    ) async -> RacingEnvironmentLoadResult {
        let entity = await MainActor.run {
            let entity = Entity()
            entity.name = "racing.environment.fallback.\(track.rawValue)"
            return entity
        }
        return RacingEnvironmentLoadResult(
            resources: RacingEnvironmentResources(
                track: track,
                requestedTier: requestedTier,
                effectiveTier: .baseline,
                baseEntity: entity,
                enhancedEntity: nil,
                baseColorTexture: nil,
                normalTexture: nil,
                roughnessTexture: nil,
                diagnostic: .fallback(fallbackReason(for: error))
            ),
            decodedAssetNames: []
        )
    }

    private static func fallbackReason(
        for error: Error
    ) -> RacingEnvironmentResourceFallbackReason {
        guard let error = error as? RacingEnvironmentAssetLoadError else {
            return .manifestInvalid
        }
        return switch error {
        case .manifestUnavailable: .manifestUnavailable
        case .manifestInvalid: .manifestInvalid
        case let .assetMissing(filename): .assetMissing(filename)
        case let .assetIntegrityFailed(filename): .assetIntegrityFailed(filename)
        case let .assetDecodeFailed(filename): .assetDecodeFailed(filename)
        }
    }
}

private struct RacingEnvironmentLoadResult: Sendable {
    let resources: RacingEnvironmentResources
    let decodedAssetNames: [String]
}

private struct RacingEnvironmentValidatedSelection: Sendable {
    let mapping: RacingEnvironmentTrackAssetContract
    let baseURL: URL?
    let enhancedURL: URL?
    let textureURLs: [RacingEnvironmentTextureSemantic: URL]

    func textureContract(
        _ semantic: RacingEnvironmentTextureSemantic
    ) throws -> RacingEnvironmentTextureAssetContract {
        guard let contract = mapping.textures.first(where: { $0.semantic == semantic }) else {
            throw RacingEnvironmentAssetLoadError.manifestInvalid
        }
        return contract
    }
}

private enum RacingEnvironmentAssetLoadError: Error {
    case manifestUnavailable
    case manifestInvalid
    case assetMissing(String)
    case assetIntegrityFailed(String)
    case assetDecodeFailed(String)
}

private struct RacingEnvironmentRuntimeManifest: Decodable {
    struct TextureContract: Decodable {
        let width: Int
        let height: Int
        let bitsPerComponent: Int
        let channels: String
        let mipmapPolicy: String
        let runtimeGenerationAllowed: Bool
    }

    struct Pack: Decodable {
        let rootName: String
        let tier: String
        let role: String
        let runtimeUSDZ: String
        let runtimeUSDZSHA256: String
        let hashStatus: String
    }

    struct Geometry: Decodable {
        let base: Pack
        let enhanced: Pack
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

    struct Track: Decodable {
        let id: String
        let assetSlug: String
        let geometry: Geometry
        let textures: [Texture]
    }

    let schemaVersion: Int
    let revision: Int
    let license: String
    let hashAlgorithm: String
    let textureContract: TextureContract
    let tracks: [Track]
}
