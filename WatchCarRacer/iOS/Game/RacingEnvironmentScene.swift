import RealityKit
import UIKit

struct RacingEnvironmentSceneHazeContract: Equatable, Sendable {
    let layer: RacingEnvironmentDistanceLayer
    let coefficient: Float
    let tint: SIMD3<Float>
    let opacity: Float
}

struct RacingEnvironmentScenePlacementSnapshot: Equatable, Sendable {
    let layer: RacingEnvironmentDistanceLayer
    let slotIndex: Int
    let logicalSegmentIndex: Int
    let assetName: String
    let distance: Float
    let lateralOffset: Float
    let footprintRadius: Float
    let scale: Float
    let yaw: Float
    let tint: Float

    var propEdgeOffset: Float {
        abs(lateralOffset) - footprintRadius
    }
}

struct RacingEnvironmentParallaxBandSnapshot: Equatable, Sendable {
    let layer: RacingEnvironmentDistanceLayer
    let slotIndex: Int
    let bandIndex: Int
    let distance: Float
    let travelMultiplier: Float
    let opacity: Float
    let logicalSegmentIndex: Int
    let identity: ObjectIdentifier
}

struct RacingEnvironmentSceneSnapshot: Equatable, Sendable {
    let track: RacingTrack
    let tier: RacingEnvironmentQualityTier
    let diagnostic: RacingEnvironmentResourceDiagnostic
    let hierarchyNames: [String]
    let haze: [RacingEnvironmentSceneHazeContract]
    let placements: [RacingEnvironmentScenePlacementSnapshot]
    let heroAnchor: SIMD3<Float>
    let heroAnchorDistance: Float
    let minimumRoadApertureWidth: Float
    let entityCount: Int
    let materialCount: Int
    let modelMaterialAssignmentCount: Int
    let contactShadowCount: Int
    let activeContactShadowCount: Int
    let preallocatedPropSlotCount: Int
    let activePropSlotCount: Int
    let preallocatedRenderPartCount: Int
    let propSlotIdentities: [ObjectIdentifier]
    let renderPartIdentities: [ObjectIdentifier]
    let detailedLODSlotCount: Int
    let parallaxBandCounts: [RacingEnvironmentDistanceLayer: Int]
    let parallaxBands: [RacingEnvironmentParallaxBandSnapshot]
    let atlasQuadrantCount: Int
    let terrainUsesBaseColor: Bool
    let terrainUsesNormal: Bool
    let terrainUsesRoughness: Bool
    let terrainExtendsPastHorizon: Bool
    let appliesPBRToShoulders: Bool
    let collisionComponentCount: Int
    let inputTargetComponentCount: Int
    let containsPrimitiveFallback: Bool
    let weatherState: WeatherPresentationState
    let precreatedWeatherMaterialSetCount: Int
    let precreatedWeatherParticleCapacity: Int
    let activeWeatherParticleCount: Int
    let weatherEffectEntityIdentities: [ObjectIdentifier]
    let puddleCueCount: Int
    let enabledPuddleCueCount: Int
    let wetSurfaceTargetCount: Int
}

@MainActor
struct RacingEnvironmentSceneAssembly {
    let root: Entity
    let snapshot: RacingEnvironmentSceneSnapshot
}

private struct RacingEnvironmentSceneMetadataComponent: Component {
    let track: RacingTrack
    var tier: RacingEnvironmentQualityTier
    let diagnostic: RacingEnvironmentResourceDiagnostic
    let materialCount: Int
    let heroAnchorDistance: Float
    let minimumRoadApertureWidth: Float
    let atlasQuadrantCount: Int
    let terrainUsesBaseColor: Bool
    let terrainUsesNormal: Bool
    let terrainUsesRoughness: Bool
    let terrainExtendsPastHorizon: Bool
    let appliesPBRToShoulders: Bool
}

private struct RacingEnvironmentScenePlacementComponent: Component {
    var layer: RacingEnvironmentDistanceLayer
    var slotIndex: Int
    var logicalSegmentIndex: Int
    var assetName: String
    var distance: Float
    var lateralOffset: Float
    var footprintRadius: Float
    var scale: Float
    var yaw: Float
    var tint: Float
}

private struct RacingEnvironmentHeroAnchorComponent: Component {
    let track: RacingTrack
    let distance: Float
}

private struct RacingEnvironmentHazeComponent: Component {
    let layer: RacingEnvironmentDistanceLayer
    let coefficient: Float
    let tint: SIMD3<Float>
    let opacity: Float
}

private struct RacingEnvironmentContactShadowComponent: Component {
    let track: RacingTrack
    var distance: Float
    var lateralOffset: Float
}

private enum RacingEnvironmentTerrainSurfaceKind: Equatable, Sendable {
    case terrain
    case transitionDecal
    case shoulder
}

private struct RacingEnvironmentTerrainSurfaceComponent: Component {
    let kind: RacingEnvironmentTerrainSurfaceKind
    let usesBaseColor: Bool
    let usesNormal: Bool
    let usesRoughness: Bool
}

@MainActor
enum RacingEnvironmentScene {
    static let rootName = "racing.environment.authored"
    static let foregroundRootName = "foreground"
    static let midgroundRootName = "midground"
    static let farRootName = "far"
    static let heroRootName = "hero"
    static let weatherRootName = "weather"
    static let terrainRootName = "terrain"
    static let decalRootName = "decal"
    static let contactShadowRootName = "contact-shadow"

    static let hierarchyNames = [
        foregroundRootName,
        midgroundRootName,
        farRootName,
        heroRootName,
        weatherRootName,
        terrainRootName,
        decalRootName,
        contactShadowRootName,
    ]

    private static func directChild(named name: String, in parent: Entity) -> Entity? {
        parent.children.first { $0.name == name }
    }

    enum AssemblyError: Error, Equatable {
        case resourcesAreFallback
        case textureSetIncomplete
        case assetMissing(String)
        case budgetExceeded
    }

    private enum TemplateSource: Hashable {
        case base
        case enhanced
    }

    private struct TemplateKey: Hashable {
        let source: TemplateSource
        let layer: RacingEnvironmentDistanceLayer
        let assetName: String
    }

    private struct RenderTemplatePart {
        let dryModel: ModelComponent
        let wetModel: ModelComponent
        let transform: Transform
    }

    private struct RenderTemplate {
        let parts: [RenderTemplatePart]
    }

    private final class RenderBankRuntime {
        let source: TemplateSource
        let entity: Entity
        let renderParts: [Entity]

        init(source: TemplateSource, entity: Entity, renderParts: [Entity]) {
            self.source = source
            self.entity = entity
            self.renderParts = renderParts
        }
    }

    private final class PropBandRuntime {
        let contract: RacingEnvironmentParallaxBandContract
        let entity: Entity
        let renderBanks: [RenderBankRuntime]
        var logicalSegmentIndex = Int.min
        var variantIndex = -1
        var placement: RacingEnvironmentClusterPlacement?
        var distance: Float = 0
        var opacity: Float = 0
        var usesWetMaterials = false

        init(
            contract: RacingEnvironmentParallaxBandContract,
            entity: Entity,
            renderBanks: [RenderBankRuntime]
        ) {
            self.contract = contract
            self.entity = entity
            self.renderBanks = renderBanks
        }
    }

    private final class PropSlotRuntime {
        let layer: RacingEnvironmentDistanceLayer
        let slotIndex: Int
        let slotCount: Int
        let entity: Entity
        let bands: [PropBandRuntime]
        let contactShadow: Entity?
        var nearLODState: RacingEnvironmentNearLODState = .standard

        init(
            layer: RacingEnvironmentDistanceLayer,
            slotIndex: Int,
            slotCount: Int,
            entity: Entity,
            bands: [PropBandRuntime],
            contactShadow: Entity?
        ) {
            self.layer = layer
            self.slotIndex = slotIndex
            self.slotCount = slotCount
            self.entity = entity
            self.bands = bands
            self.contactShadow = contactShadow
        }
    }

    private final class PropPoolRuntime {
        let track: RacingTrack
        var tier: RacingEnvironmentQualityTier
        let profile: RacingEnvironmentProfile
        let templates: [TemplateKey: RenderTemplate]
        let hazeOpacities: [RacingEnvironmentDistanceLayer: Float]
        let slots: [PropSlotRuntime]
        var weatherState: WeatherPresentationState

        init(
            track: RacingTrack,
            tier: RacingEnvironmentQualityTier,
            profile: RacingEnvironmentProfile,
            templates: [TemplateKey: RenderTemplate],
            hazeOpacities: [RacingEnvironmentDistanceLayer: Float],
            slots: [PropSlotRuntime],
            weatherState: WeatherPresentationState
        ) {
            self.track = track
            self.tier = tier
            self.profile = profile
            self.templates = templates
            self.hazeOpacities = hazeOpacities
            self.slots = slots
            self.weatherState = weatherState
        }
    }

    private struct PropPoolRuntimeComponent: Component {
        let runtime: PropPoolRuntime
    }

    private final class WeatherSurfaceRuntime {
        let entity: Entity
        let dryModel: ModelComponent
        let wetModel: ModelComponent

        init(entity: Entity, dryModel: ModelComponent, wetModel: ModelComponent) {
            self.entity = entity
            self.dryModel = dryModel
            self.wetModel = wetModel
        }
    }

    private final class WeatherEffectRuntime {
        let entity: Entity
        let basePosition: SIMD3<Float>

        init(entity: Entity, basePosition: SIMD3<Float>) {
            self.entity = entity
            self.basePosition = basePosition
        }
    }

    private final class WeatherRuntime {
        let rainParticles: [WeatherEffectRuntime]
        let dustSprayParticles: [WeatherEffectRuntime]
        let hazeCues: [WeatherEffectRuntime]
        let puddleCues: [WeatherEffectRuntime]
        let lightningCue: WeatherEffectRuntime
        let materialSetCount: Int
        let particleCapacity: Int
        var surfaces: [WeatherSurfaceRuntime]
        var state: WeatherPresentationState
        var usesWetMaterialsApplied: Bool?

        init(
            rainParticles: [WeatherEffectRuntime],
            dustSprayParticles: [WeatherEffectRuntime],
            hazeCues: [WeatherEffectRuntime],
            puddleCues: [WeatherEffectRuntime],
            lightningCue: WeatherEffectRuntime,
            materialSetCount: Int,
            particleCapacity: Int,
            surfaces: [WeatherSurfaceRuntime],
            state: WeatherPresentationState
        ) {
            self.rainParticles = rainParticles
            self.dustSprayParticles = dustSprayParticles
            self.hazeCues = hazeCues
            self.puddleCues = puddleCues
            self.lightningCue = lightningCue
            self.materialSetCount = materialSetCount
            self.particleCapacity = particleCapacity
            self.surfaces = surfaces
            self.state = state
        }

        var effectEntities: [Entity] {
            rainParticles.map(\.entity)
                + dustSprayParticles.map(\.entity)
                + hazeCues.map(\.entity)
                + puddleCues.map(\.entity)
                + [lightningCue.entity]
        }
    }

    private struct WeatherRuntimeComponent: Component {
        let runtime: WeatherRuntime
    }

    static func hazeContracts(for track: RacingTrack) -> [RacingEnvironmentSceneHazeContract] {
        let tints: [SIMD3<Float>] = switch track {
        case .coastal:
            [SIMD3(1.00, 0.98, 0.94), SIMD3(0.86, 0.91, 0.92), SIMD3(0.72, 0.82, 0.86)]
        case .alpine:
            [SIMD3(0.98, 1.00, 0.98), SIMD3(0.82, 0.89, 0.88), SIMD3(0.72, 0.80, 0.84)]
        case .desert:
            [SIMD3(1.00, 0.96, 0.89), SIMD3(0.92, 0.82, 0.69), SIMD3(0.80, 0.69, 0.59)]
        }
        return zip(
            RacingEnvironmentDistanceLayer.allCases,
            zip([Float(0.08), 0.23, 0.42], zip(tints, [Float(0.98), 0.94, 0.88]))
        ).map { layer, values in
            RacingEnvironmentSceneHazeContract(
                layer: layer,
                coefficient: values.0,
                tint: values.1.0,
                opacity: values.1.1
            )
        }
    }

    static func heroAnchor(track: RacingTrack, travel: Double) -> SIMD3<Float> {
        let profile = RacingEnvironmentCatalog.profile(for: track)
        let safeTravel: Double
        if travel.isFinite {
            safeTravel = min(max(travel, 0), 1_000_000_000)
        } else {
            safeTravel = 0
        }
        return RacingWorldLayout.trackPlacement(
            distance: profile.hero.anchorDistance,
            travel: safeTravel,
            track: track
        ).position
    }

    static func assemble(
        resources: RacingEnvironmentResources,
        travel: Double
    ) throws -> RacingEnvironmentSceneAssembly {
        try assemble(
            resources: resources,
            travel: travel,
            weatherState: RacingEnvironmentWeather.presentationState(
                track: resources.track,
                weather: .clear,
                travel: travel,
                tier: resources.effectiveTier,
                accessibilityPolicy: RacingEnvironmentWeather.standardAccessibilityPolicy()
            )
        )
    }

    static func assemble(
        resources: RacingEnvironmentResources,
        travel: Double,
        weatherState: WeatherPresentationState
    ) throws -> RacingEnvironmentSceneAssembly {
        guard resources.diagnostic.isAuthored else {
            throw AssemblyError.resourcesAreFallback
        }
        guard let baseColorTexture = resources.baseColorTexture,
              let normalTexture = resources.normalTexture,
              let roughnessTexture = resources.roughnessTexture else {
            throw AssemblyError.textureSetIncomplete
        }

        let profile = RacingEnvironmentCatalog.profile(for: resources.track)
        let budget = profile.qualityBudgets.budget(for: resources.effectiveTier)
        let root = Entity()
        root.name = rootName

        var layerRoots: [RacingEnvironmentDistanceLayer: Entity] = [:]
        for haze in hazeContracts(for: resources.track) {
            let layerRoot = Entity()
            layerRoot.name = rootName(for: haze.layer)
            layerRoot.components.set(
                RacingEnvironmentHazeComponent(
                    layer: haze.layer,
                    coefficient: haze.coefficient,
                    tint: haze.tint,
                    opacity: haze.opacity
                )
            )
            layerRoot.components.set(OpacityComponent(opacity: haze.opacity))
            layerRoots[haze.layer] = layerRoot
            root.addChild(layerRoot)
        }

        let heroRoot = Entity()
        heroRoot.name = heroRootName
        heroRoot.components.set(
            RacingEnvironmentHeroAnchorComponent(
                track: resources.track,
                distance: profile.hero.anchorDistance
            )
        )
        if let farHaze = hazeContracts(for: resources.track).last {
            heroRoot.components.set(OpacityComponent(opacity: farHaze.opacity))
        }
        root.addChild(heroRoot)

        let weatherRoot = Entity()
        weatherRoot.name = weatherRootName
        root.addChild(weatherRoot)

        let terrainMaterial = makeTerrainMaterial(
            track: resources.track,
            baseColor: baseColorTexture,
            normal: normalTexture,
            roughness: roughnessTexture
        )
        let terrainRoot = makeTerrainRoot(material: terrainMaterial)
        root.addChild(terrainRoot)

        let decalRoot = makeDecalRoot(
            track: resources.track,
            baseColor: baseColorTexture,
            normal: normalTexture,
            roughness: roughnessTexture
        )
        root.addChild(decalRoot)

        let contactShadowRoot = Entity()
        contactShadowRoot.name = contactShadowRootName
        root.addChild(contactShadowRoot)

        let templates = try makeTemplateRegistry(
            resources: resources,
            profile: profile
        )
        let propPool = try makePropPool(
            resources: resources,
            profile: profile,
            layerRoots: layerRoots,
            contactShadowRoot: contactShadowRoot,
            templates: templates,
            weatherState: weatherState
        )
        root.components.set(PropPoolRuntimeComponent(runtime: propPool))

        let heroSource = resources.enhancedEntity ?? resources.baseEntity
        guard let hero = heroSource.findEntity(named: profile.hero.assetName) else {
            throw AssemblyError.assetMissing(profile.hero.assetName)
        }
        let heroClone = hero.clone(recursive: true)
        removeInteractionComponents(from: heroClone)
        if let farHaze = hazeContracts(for: resources.track).last {
            applyAtmosphericTint(to: heroClone, contract: farHaze)
        }
        heroRoot.addChild(heroClone)

        let weatherRuntime = makeWeatherRuntime(
            root: root,
            weatherRoot: weatherRoot,
            track: resources.track,
            budget: budget,
            state: weatherState
        )
        root.components.set(WeatherRuntimeComponent(runtime: weatherRuntime))

        let materialCount = (resources.effectiveTier == .enhanced ? 14 : 10)
            + weatherRuntime.materialSetCount
        root.components.set(
            RacingEnvironmentSceneMetadataComponent(
                track: resources.track,
                tier: resources.effectiveTier,
                diagnostic: resources.diagnostic,
                materialCount: materialCount,
                heroAnchorDistance: profile.hero.anchorDistance,
                minimumRoadApertureWidth: profile.hero.minimumRoadApertureWidth,
                atlasQuadrantCount: 4,
                terrainUsesBaseColor: true,
                terrainUsesNormal: true,
                terrainUsesRoughness: true,
                terrainExtendsPastHorizon: true,
                appliesPBRToShoulders: true
            )
        )
        updateTransforms(in: root, travel: travel, weatherState: weatherState)
        removeInteractionComponents(from: root)

        let snapshot = try snapshot(of: root)
        guard snapshot.entityCount <= budget.maximumEntityCount,
              snapshot.materialCount <= budget.maximumMaterialCount,
              snapshot.contactShadowCount <= budget.maximumContactShadowCount,
              snapshot.collisionComponentCount == 0,
              snapshot.inputTargetComponentCount == 0 else {
            throw AssemblyError.budgetExceeded
        }
        return RacingEnvironmentSceneAssembly(root: root, snapshot: snapshot)
    }

    @discardableResult
    static func install(
        in world: Entity,
        resources: RacingEnvironmentResources,
        travel: Double
    ) -> Bool {
        install(
            in: world,
            resources: resources,
            travel: travel,
            weatherState: RacingEnvironmentWeather.presentationState(
                track: resources.track,
                weather: .clear,
                travel: travel,
                tier: resources.effectiveTier,
                accessibilityPolicy: RacingEnvironmentWeather.standardAccessibilityPolicy()
            )
        )
    }

    @discardableResult
    static func install(
        in world: Entity,
        resources: RacingEnvironmentResources,
        travel: Double,
        weatherState: WeatherPresentationState
    ) -> Bool {
        guard resources.diagnostic.isAuthored else { return false }
        if let existing = directChild(named: rootName, in: world) {
            updateTransforms(in: existing, travel: travel, weatherState: weatherState)
            return true
        }

        guard let assembly = try? assemble(
            resources: resources,
            travel: travel,
            weatherState: weatherState
        ) else {
            return false
        }

        guard let baseColorTexture = resources.baseColorTexture,
              let normalTexture = resources.normalTexture,
              let roughnessTexture = resources.roughnessTexture else {
            return false
        }
        world.addChild(assembly.root)
        applyTerrainMaterialToShoulders(
            in: world,
            material: makeTerrainMaterial(
                track: resources.track,
                baseColor: baseColorTexture,
                normal: normalTexture,
                roughness: roughnessTexture
            ),
            weatherRuntime: assembly.root.components[WeatherRuntimeComponent.self]?.runtime
        )
        updateTransforms(in: assembly.root, travel: travel, weatherState: weatherState)
        disableLegacyEnvironment(in: world)
        return true
    }

    static func update(in world: Entity, travel: Double) {
        guard let root = directChild(named: rootName, in: world) else { return }
        let metadata = root.components[RacingEnvironmentSceneMetadataComponent.self]
        let track = metadata?.track ?? .coastal
        let tier = metadata?.tier ?? .baseline
        updateTransforms(
            in: root,
            travel: travel,
            weatherState: RacingEnvironmentWeather.presentationState(
                track: track,
                weather: .clear,
                travel: travel,
                tier: tier,
                accessibilityPolicy: RacingEnvironmentWeather.standardAccessibilityPolicy()
            )
        )
    }

    static func update(
        in world: Entity,
        travel: Double,
        weatherState: WeatherPresentationState
    ) {
        guard let root = directChild(named: rootName, in: world) else { return }
        updateTransforms(in: root, travel: travel, weatherState: weatherState)
    }

    @discardableResult
    static func applyQualityTier(
        _ tier: RacingEnvironmentQualityTier,
        in world: Entity,
        travel: Double,
        weatherState: WeatherPresentationState
    ) -> Bool {
        guard let root = directChild(named: rootName, in: world),
              var metadata = root.components[RacingEnvironmentSceneMetadataComponent.self],
              let propPool = root.components[PropPoolRuntimeComponent.self]?.runtime else {
            return false
        }
        if metadata.tier == tier {
            updateTransforms(in: root, travel: travel, weatherState: weatherState)
            return true
        }
        guard metadata.tier == .enhanced, tier == .baseline else {
            return false
        }

        metadata.tier = .baseline
        root.components.set(metadata)
        propPool.tier = .baseline
        for slot in propPool.slots {
            slot.nearLODState = .standard
            for band in slot.bands {
                band.logicalSegmentIndex = .min
                band.variantIndex = -1
            }
        }
        updateTransforms(in: root, travel: travel, weatherState: weatherState)
        return true
    }

    static func snapshot(of root: Entity) throws -> RacingEnvironmentSceneSnapshot {
        guard root.name == rootName,
              let metadata = root.components[RacingEnvironmentSceneMetadataComponent.self],
              let hero = root.children.first(where: { $0.name == heroRootName }) else {
            throw AssemblyError.assetMissing(rootName)
        }
        let entities = descendants(including: root)
        let haze = RacingEnvironmentDistanceLayer.allCases.compactMap { layer in
            root.children
                .first(where: { $0.name == rootName(for: layer) })?
                .components[RacingEnvironmentHazeComponent.self]
        }.map {
            RacingEnvironmentSceneHazeContract(
                layer: $0.layer,
                coefficient: $0.coefficient,
                tint: $0.tint,
                opacity: $0.opacity
            )
        }
        let placements = entities.compactMap {
            $0.components[RacingEnvironmentScenePlacementComponent.self]
        }.map {
            RacingEnvironmentScenePlacementSnapshot(
                layer: $0.layer,
                slotIndex: $0.slotIndex,
                logicalSegmentIndex: $0.logicalSegmentIndex,
                assetName: $0.assetName,
                distance: $0.distance,
                lateralOffset: $0.lateralOffset,
                footprintRadius: $0.footprintRadius,
                scale: $0.scale,
                yaw: $0.yaw,
                tint: $0.tint
            )
        }
        let propPool = root.components[PropPoolRuntimeComponent.self]?.runtime
        let contactShadows = root.children
            .first(where: { $0.name == contactShadowRootName })
            .map { Array($0.children) } ?? []
        let propSlotIdentities = propPool?.slots.map {
            ObjectIdentifier($0.entity)
        } ?? []
        let renderPartIdentities = propPool?.slots.flatMap { slot in
            slot.bands.flatMap { band in
                band.renderBanks.flatMap { bank in
                    bank.renderParts.map(ObjectIdentifier.init)
                }
            }
        } ?? []
        let parallaxBandCounts = Dictionary(
            uniqueKeysWithValues: RacingEnvironmentDistanceLayer.allCases.map { layer in
                (
                    layer,
                    propPool?.slots
                        .filter { $0.layer == layer }
                        .first?.bands.count ?? 0
                )
            }
        )
        let parallaxBands = propPool?.slots.flatMap { slot in
            slot.bands.map { band in
                RacingEnvironmentParallaxBandSnapshot(
                    layer: slot.layer,
                    slotIndex: slot.slotIndex,
                    bandIndex: band.contract.bandIndex,
                    distance: band.distance,
                    travelMultiplier: band.contract.travelMultiplier,
                    opacity: band.opacity,
                    logicalSegmentIndex: band.logicalSegmentIndex,
                    identity: ObjectIdentifier(band.entity)
                )
            }
        } ?? []
        let modelMaterialAssignmentCount = entities.reduce(into: 0) { count, entity in
            count += entity.components[ModelComponent.self]?.materials.count ?? 0
        }
        guard let weatherRuntime = root.components[WeatherRuntimeComponent.self]?.runtime else {
            throw AssemblyError.assetMissing(weatherRootName)
        }
        return RacingEnvironmentSceneSnapshot(
            track: metadata.track,
            tier: metadata.tier,
            diagnostic: metadata.diagnostic,
            hierarchyNames: root.children.map(\.name),
            haze: haze,
            placements: placements,
            heroAnchor: hero.position,
            heroAnchorDistance: metadata.heroAnchorDistance,
            minimumRoadApertureWidth: metadata.minimumRoadApertureWidth,
            entityCount: entities.count,
            materialCount: metadata.materialCount,
            modelMaterialAssignmentCount: modelMaterialAssignmentCount,
            contactShadowCount: root.children
                .first(where: { $0.name == contactShadowRootName })?
                .children.count ?? 0,
            activeContactShadowCount: contactShadows.filter(\.isEnabled).count,
            preallocatedPropSlotCount: propSlotIdentities.count,
            activePropSlotCount: propPool?.slots.filter { $0.entity.isEnabled }.count ?? 0,
            preallocatedRenderPartCount: renderPartIdentities.count,
            propSlotIdentities: propSlotIdentities,
            renderPartIdentities: renderPartIdentities,
            detailedLODSlotCount: propPool?.slots.filter {
                $0.entity.isEnabled && $0.nearLODState == .detailed
            }.count ?? 0,
            parallaxBandCounts: parallaxBandCounts,
            parallaxBands: parallaxBands,
            atlasQuadrantCount: metadata.atlasQuadrantCount,
            terrainUsesBaseColor: metadata.terrainUsesBaseColor,
            terrainUsesNormal: metadata.terrainUsesNormal,
            terrainUsesRoughness: metadata.terrainUsesRoughness,
            terrainExtendsPastHorizon: metadata.terrainExtendsPastHorizon,
            appliesPBRToShoulders: metadata.appliesPBRToShoulders,
            collisionComponentCount: entities.filter {
                $0.components.has(CollisionComponent.self)
            }.count,
            inputTargetComponentCount: entities.filter {
                $0.components.has(InputTargetComponent.self)
            }.count,
            containsPrimitiveFallback: entities.contains(where: isLegacyPrimitive),
            weatherState: weatherRuntime.state,
            precreatedWeatherMaterialSetCount: weatherRuntime.materialSetCount,
            precreatedWeatherParticleCapacity: weatherRuntime.particleCapacity,
            activeWeatherParticleCount: weatherRuntime.state.weatherParticleCount,
            weatherEffectEntityIdentities: weatherRuntime.effectEntities.map(
                ObjectIdentifier.init
            ),
            puddleCueCount: weatherRuntime.puddleCues.count,
            enabledPuddleCueCount: weatherRuntime.puddleCues.filter {
                $0.entity.isEnabled
            }.count,
            wetSurfaceTargetCount: weatherRuntime.state.usesWetMaterials
                ? weatherRuntime.surfaces.count
                : 0
        )
    }

    static func isPBRShoulder(_ entity: Entity) -> Bool {
        guard let contract = entity.components[RacingEnvironmentTerrainSurfaceComponent.self] else {
            return false
        }
        return contract.kind == .shoulder
            && contract.usesBaseColor
            && contract.usesNormal
            && contract.usesRoughness
    }

    private static func rootName(for layer: RacingEnvironmentDistanceLayer) -> String {
        switch layer {
        case .foreground: foregroundRootName
        case .midground: midgroundRootName
        case .far: farRootName
        }
    }

    private static func makeTemplateRegistry(
        resources: RacingEnvironmentResources,
        profile: RacingEnvironmentProfile
    ) throws -> [TemplateKey: RenderTemplate] {
        var registry: [TemplateKey: RenderTemplate] = [:]
        let sources: [(TemplateSource, Entity)] = if let enhanced = resources.enhancedEntity {
            [(.base, resources.baseEntity), (.enhanced, enhanced)]
        } else {
            [(.base, resources.baseEntity)]
        }

        for layer in RacingEnvironmentDistanceLayer.allCases {
            let haze = hazeContracts(for: resources.track)[layer.index]
            for (sourceKind, source) in sources {
                for variant in profile.variants {
                    guard let entity = source.findEntity(named: variant.assetName) else {
                        throw AssemblyError.assetMissing(variant.assetName)
                    }
                    let parts = flattenedRenderParts(from: entity, haze: haze)
                    guard !parts.isEmpty else {
                        throw AssemblyError.assetMissing(variant.assetName)
                    }
                    registry[
                        TemplateKey(
                            source: sourceKind,
                            layer: layer,
                            assetName: variant.assetName
                        )
                    ] = RenderTemplate(parts: parts)
                }
            }
        }
        return registry
    }

    private static func makePropPool(
        resources: RacingEnvironmentResources,
        profile: RacingEnvironmentProfile,
        layerRoots: [RacingEnvironmentDistanceLayer: Entity],
        contactShadowRoot: Entity,
        templates: [TemplateKey: RenderTemplate],
        weatherState: WeatherPresentationState
    ) throws -> PropPoolRuntime {
        let density = profile.qualityBudgets
            .budget(for: resources.effectiveTier)
            .clusterDensity
        let shadowMesh = MeshResource.generatePlane(width: 1, depth: 1)
        let shadowMaterial = UnlitMaterial(
            color: UIColor(red: 0.035, green: 0.045, blue: 0.04, alpha: 0.24)
        )
        var slots: [PropSlotRuntime] = []

        for layer in RacingEnvironmentDistanceLayer.allCases {
            guard let layerRoot = layerRoots[layer] else {
                throw AssemblyError.assetMissing(rootName(for: layer))
            }
            let slotCount = density.clusterCount(for: layer)
            for slotIndex in 0..<slotCount {
                let slotEntity = Entity()
                slotEntity.name = "prop-slot.\(layer.rawValue).\(slotIndex)"
                let placeholder = profile.variants[0]
                slotEntity.components.set(
                    RacingEnvironmentScenePlacementComponent(
                        layer: layer,
                        slotIndex: slotIndex,
                        logicalSegmentIndex: 0,
                        assetName: placeholder.assetName,
                        distance: profile.layerContract(for: layer)?.visibleDistanceRange.lowerBound
                            ?? 0,
                        lateralOffset: profile.roadClearance.minimumPropEdgeOffset
                            + placeholder.footprintRadius,
                        footprintRadius: placeholder.footprintRadius,
                        scale: 1,
                        yaw: 0,
                        tint: 0
                    )
                )

                var bands: [PropBandRuntime] = []
                for contract in RacingEnvironmentLayout.parallaxBands(for: layer) {
                    let bandEntity = Entity()
                    bandEntity.name = "prop-band.\(layer.rawValue).\(contract.bandIndex)"
                    bandEntity.components.set(OpacityComponent(opacity: 0))
                    slotEntity.addChild(bandEntity)

                    let sources: [TemplateSource]
                    if resources.effectiveTier == .enhanced {
                        sources = layer == .foreground ? [.base, .enhanced] : [.enhanced]
                    } else {
                        sources = [.base]
                    }
                    let banks = try sources.map { source in
                        try makeRenderBank(
                            source: source,
                            layer: layer,
                            profile: profile,
                            templates: templates,
                            parent: bandEntity
                        )
                    }
                    bands.append(
                        PropBandRuntime(
                            contract: contract,
                            entity: bandEntity,
                            renderBanks: banks
                        )
                    )
                }

                let contactShadow: Entity?
                if layer == .foreground {
                    let shadow = makeContactShadow(
                        index: slotIndex,
                        track: resources.track,
                        mesh: shadowMesh,
                        material: shadowMaterial
                    )
                    contactShadowRoot.addChild(shadow)
                    contactShadow = shadow
                } else {
                    contactShadow = nil
                }
                layerRoot.addChild(slotEntity)
                slots.append(
                    PropSlotRuntime(
                        layer: layer,
                        slotIndex: slotIndex,
                        slotCount: slotCount,
                        entity: slotEntity,
                        bands: bands,
                        contactShadow: contactShadow
                    )
                )
            }
        }

        return PropPoolRuntime(
            track: resources.track,
            tier: resources.effectiveTier,
            profile: profile,
            templates: templates,
            hazeOpacities: Dictionary(
                uniqueKeysWithValues: hazeContracts(for: resources.track).map {
                    ($0.layer, $0.opacity)
                }
            ),
            slots: slots,
            weatherState: weatherState
        )
    }

    private static func makeRenderBank(
        source: TemplateSource,
        layer: RacingEnvironmentDistanceLayer,
        profile: RacingEnvironmentProfile,
        templates: [TemplateKey: RenderTemplate],
        parent: Entity
    ) throws -> RenderBankRuntime {
        let available = try profile.variants.map { variant -> RenderTemplate in
            guard let template = templates[
                TemplateKey(
                    source: source,
                    layer: layer,
                    assetName: variant.assetName
                )
            ] else {
                throw AssemblyError.assetMissing(variant.assetName)
            }
            return template
        }
        guard let initial = available.first,
              let initialPart = initial.parts.first,
              let capacity = available.map(\.parts.count).max() else {
            throw AssemblyError.assetMissing(rootName(for: layer))
        }

        let bankEntity = Entity()
        bankEntity.name = source == .base ? "lod.standard" : "lod.detailed"
        bankEntity.components.set(OpacityComponent(opacity: source == .base ? 1 : 0))
        parent.addChild(bankEntity)
        var renderParts: [Entity] = []
        for index in 0..<capacity {
            let part = Entity()
            part.name = "render-part.\(index)"
            let templatePart = initial.parts.indices.contains(index)
                ? initial.parts[index]
                : initialPart
            part.components.set(templatePart.dryModel)
            part.transform = templatePart.transform
            part.isEnabled = initial.parts.indices.contains(index)
            bankEntity.addChild(part)
            renderParts.append(part)
        }
        return RenderBankRuntime(
            source: source,
            entity: bankEntity,
            renderParts: renderParts
        )
    }

    private static func flattenedRenderParts(
        from root: Entity,
        haze: RacingEnvironmentSceneHazeContract
    ) -> [RenderTemplatePart] {
        var result: [RenderTemplatePart] = []

        func visit(_ entity: Entity, parentMatrix: simd_float4x4) {
            let matrix = parentMatrix * entity.transform.matrix
            if let model = entity.components[ModelComponent.self] {
                let dryModel = atmosphericallyTinted(model, contract: haze)
                result.append(
                    RenderTemplatePart(
                        dryModel: dryModel,
                        wetModel: wetModel(from: dryModel),
                        transform: Transform(matrix: matrix)
                    )
                )
            }
            for child in entity.children {
                visit(child, parentMatrix: matrix)
            }
        }

        visit(root, parentMatrix: matrix_identity_float4x4)
        return result
    }

    private static func atmosphericallyTinted(
        _ source: ModelComponent,
        contract: RacingEnvironmentSceneHazeContract
    ) -> ModelComponent {
        var model = source
        model.materials = source.materials.map { material in
            guard var pbr = material as? PhysicallyBasedMaterial else { return material }
            var red: CGFloat = 1
            var green: CGFloat = 1
            var blue: CGFloat = 1
            var alpha: CGFloat = 1
            pbr.baseColor.tint.getRed(
                &red,
                green: &green,
                blue: &blue,
                alpha: &alpha
            )
            pbr.baseColor.tint = UIColor(
                red: red * CGFloat(contract.tint.x),
                green: green * CGFloat(contract.tint.y),
                blue: blue * CGFloat(contract.tint.z),
                alpha: alpha
            )
            pbr.roughness.scale = min(
                1,
                pbr.roughness.scale + contract.coefficient * 0.12
            )
            return pbr
        }
        return model
    }

    private static func makeTerrainRoot(material: PhysicallyBasedMaterial) -> Entity {
        let root = Entity()
        root.name = terrainRootName
        let surface = ModelEntity(
            mesh: .generatePlane(width: 180, depth: 600),
            materials: [material]
        )
        surface.name = "continuous-pbr-terrain"
        surface.position = SIMD3(0, -0.24, -210)
        surface.components.set(
            RacingEnvironmentTerrainSurfaceComponent(
                kind: .terrain,
                usesBaseColor: true,
                usesNormal: true,
                usesRoughness: true
            )
        )
        root.addChild(surface)
        return root
    }

    private static func makeDecalRoot(
        track: RacingTrack,
        baseColor: TextureResource,
        normal: TextureResource,
        roughness: TextureResource
    ) -> Entity {
        let root = Entity()
        root.name = decalRootName
        let placements: [(SIMD3<Float>, SIMD2<Float>)] = [
            (SIMD3(-8.2, -0.075, -22), SIMD2(0, 0)),
            (SIMD3(8.4, -0.075, -66), SIMD2(0.5, 0)),
            (SIMD3(-9.0, -0.075, -124), SIMD2(0, 0.5)),
            (SIMD3(9.2, -0.075, -190), SIMD2(0.5, 0.5)),
        ]
        for (index, placement) in placements.enumerated() {
            var material = makeTerrainMaterial(
                track: track,
                baseColor: baseColor,
                normal: normal,
                roughness: roughness
            )
            material.textureCoordinateTransform = .init(
                offset: placement.1,
                scale: SIMD2(repeating: 0.5)
            )
            let decal = ModelEntity(
                mesh: .generatePlane(width: 5.5, depth: 34),
                materials: [material]
            )
            decal.name = "atlas-quadrant-\(index)"
            decal.position = placement.0
            decal.components.set(
                RacingEnvironmentTerrainSurfaceComponent(
                    kind: .transitionDecal,
                    usesBaseColor: true,
                    usesNormal: true,
                    usesRoughness: true
                )
            )
            root.addChild(decal)
        }
        return root
    }

    private static func makeTerrainMaterial(
        track: RacingTrack,
        baseColor: TextureResource,
        normal: TextureResource,
        roughness: TextureResource
    ) -> PhysicallyBasedMaterial {
        let tint: UIColor = switch track {
        case .coastal: UIColor(red: 0.55, green: 0.68, blue: 0.62, alpha: 1)
        case .alpine: UIColor(red: 0.60, green: 0.68, blue: 0.64, alpha: 1)
        case .desert: UIColor(red: 0.78, green: 0.56, blue: 0.36, alpha: 1)
        }
        var material = PhysicallyBasedMaterial()
        material.baseColor = .init(
            tint: tint,
            texture: PhysicallyBasedMaterial.Texture(baseColor)
        )
        material.normal = .init(texture: PhysicallyBasedMaterial.Texture(normal))
        material.roughness = .init(
            scale: 0.92,
            texture: PhysicallyBasedMaterial.Texture(roughness)
        )
        material.metallic = .init(scale: 0)
        material.specular = .init(scale: 0.42)
        material.textureCoordinateTransform = .init(scale: SIMD2(18, 60))
        return material
    }

    private static func makeContactShadow(
        index: Int,
        track: RacingTrack,
        mesh: MeshResource,
        material: UnlitMaterial
    ) -> Entity {
        let shadow = ModelEntity(
            mesh: mesh,
            materials: [material]
        )
        shadow.name = "contact-shadow.\(index)"
        shadow.components.set(OpacityComponent(opacity: 0))
        shadow.components.set(
            RacingEnvironmentContactShadowComponent(
                track: track,
                distance: 0,
                lateralOffset: 0
            )
        )
        return shadow
    }

    private static func makeWeatherRuntime(
        root: Entity,
        weatherRoot: Entity,
        track: RacingTrack,
        budget: RacingEnvironmentStaticQualityBudget,
        state: WeatherPresentationState
    ) -> WeatherRuntime {
        let cueMaterial = UnlitMaterial(color: .white)
        var puddleMaterial = PhysicallyBasedMaterial()
        puddleMaterial.baseColor = .init(
            tint: UIColor(red: 0.16, green: 0.22, blue: 0.25, alpha: 1)
        )
        puddleMaterial.metallic = .init(scale: 0.04)
        puddleMaterial.roughness = .init(scale: 0.18)
        puddleMaterial.clearcoat = .init(scale: 0.72)
        puddleMaterial.clearcoatRoughness = .init(scale: 0.08)

        let maximumParticleCount = max(budget.maximumWeatherParticleCount, 0)
        let rainCueCount = 1
        let dustSprayCueCount = 1
        let rainMesh = MeshResource.generateBox(size: SIMD3(0.018, 0.30, 0.012))
        let dustMesh = MeshResource.generateBox(size: SIMD3(0.18, 0.035, 0.11))
        let hazeMesh = MeshResource.generateBox(size: SIMD3(32, 4.6, 0.02))
        let puddleMesh = MeshResource.generatePlane(width: 2.2, depth: 5.8)
        let lightningMesh = MeshResource.generateBox(size: SIMD3(16, 7, 0.015))

        let rainParticles = (0..<rainCueCount).map { index in
            let row = Float(index / 12)
            let column = Float(index % 12)
            let basePosition = SIMD3<Float>(
                -7.8 + column * 1.42,
                0.8 + Float(index % 7) * 0.67,
                -5.5 - row * 4.1
            )
            let entity = ModelEntity(mesh: rainMesh, materials: [cueMaterial])
            entity.name = "weather.rain.\(index)"
            entity.position = basePosition
            entity.orientation = simd_quatf(angle: 0.16, axis: SIMD3(0, 0, 1))
            entity.components.set(OpacityComponent(opacity: 0))
            entity.isEnabled = false
            weatherRoot.addChild(entity)
            return WeatherEffectRuntime(entity: entity, basePosition: basePosition)
        }
        let dustSprayParticles = (0..<dustSprayCueCount).map { index in
            let column = Float(index % 10)
            let row = Float(index / 10)
            let side: Float = index.isMultiple(of: 2) ? -1 : 1
            let basePosition = SIMD3<Float>(
                side * (3.7 + column * 0.28),
                0.12 + Float(index % 4) * 0.08,
                -7.5 - row * 7.2 - column * 1.4
            )
            let entity = ModelEntity(mesh: dustMesh, materials: [cueMaterial])
            entity.name = "weather.\(track == .desert ? "dust" : "spray").\(index)"
            entity.position = basePosition
            entity.components.set(OpacityComponent(opacity: 0))
            entity.isEnabled = false
            weatherRoot.addChild(entity)
            return WeatherEffectRuntime(entity: entity, basePosition: basePosition)
        }
        let hazeCues = [RacingEnvironmentDistanceLayer.far].map { layer in
            let basePosition = SIMD3<Float>(0, 3.3, -134)
            let entity = ModelEntity(mesh: hazeMesh, materials: [cueMaterial])
            entity.name = "weather.haze.\(layer.rawValue)"
            entity.position = basePosition
            entity.components.set(OpacityComponent(opacity: 0))
            entity.isEnabled = false
            weatherRoot.addChild(entity)
            return WeatherEffectRuntime(entity: entity, basePosition: basePosition)
        }
        let puddlePositions = [
            SIMD3<Float>(-4.55, -0.065, -18),
            SIMD3<Float>(4.65, -0.065, -49),
        ]
        let puddleCues = puddlePositions.enumerated().map { index, basePosition in
            let entity = ModelEntity(mesh: puddleMesh, materials: [puddleMaterial])
            entity.name = "weather.puddle.\(index)"
            entity.position = basePosition
            entity.components.set(OpacityComponent(opacity: 0))
            entity.isEnabled = false
            weatherRoot.addChild(entity)
            return WeatherEffectRuntime(entity: entity, basePosition: basePosition)
        }
        let lightningPosition = SIMD3<Float>(0, 4.8, -116)
        let lightningEntity = ModelEntity(
            mesh: lightningMesh,
            materials: [cueMaterial]
        )
        lightningEntity.name = "weather.lightning"
        lightningEntity.position = lightningPosition
        lightningEntity.components.set(OpacityComponent(opacity: 0))
        lightningEntity.isEnabled = false
        weatherRoot.addChild(lightningEntity)

        let surfaceRoots = [terrainRootName, decalRootName, heroRootName].compactMap { name in
            root.children.first { $0.name == name }
        }
        let surfaces = surfaceRoots.flatMap { surfaceRoot in
            descendants(including: surfaceRoot).compactMap(weatherSurfaceRuntime)
        }
        return WeatherRuntime(
            rainParticles: rainParticles,
            dustSprayParticles: dustSprayParticles,
            hazeCues: hazeCues,
            puddleCues: puddleCues,
            lightningCue: WeatherEffectRuntime(
                entity: lightningEntity,
                basePosition: lightningPosition
            ),
            materialSetCount: 2,
            particleCapacity: maximumParticleCount,
            surfaces: surfaces,
            state: state
        )
    }

    private static func weatherSurfaceRuntime(_ entity: Entity) -> WeatherSurfaceRuntime? {
        guard let dryModel = entity.components[ModelComponent.self],
              dryModel.materials.contains(where: { $0 is PhysicallyBasedMaterial }) else {
            return nil
        }
        return WeatherSurfaceRuntime(
            entity: entity,
            dryModel: dryModel,
            wetModel: wetModel(from: dryModel)
        )
    }

    private static func wetModel(from source: ModelComponent) -> ModelComponent {
        var model = source
        model.materials = source.materials.map { material in
            guard var pbr = material as? PhysicallyBasedMaterial else { return material }
            var red: CGFloat = 1
            var green: CGFloat = 1
            var blue: CGFloat = 1
            var alpha: CGFloat = 1
            pbr.baseColor.tint.getRed(
                &red,
                green: &green,
                blue: &blue,
                alpha: &alpha
            )
            pbr.baseColor.tint = UIColor(
                red: red * 0.78,
                green: green * 0.82,
                blue: blue * 0.86,
                alpha: alpha
            )
            pbr.roughness.scale = min(pbr.roughness.scale, 0.32)
            pbr.clearcoat = .init(scale: 0.52)
            pbr.clearcoatRoughness = .init(scale: 0.09)
            return pbr
        }
        return model
    }

    private static func updateTransforms(in root: Entity, travel _: Double,
                                         weatherState: WeatherPresentationState) {
        guard root.components.has(RacingEnvironmentSceneMetadataComponent.self) else {
            return
        }
        let safeTravel = weatherState.sanitizedTravel
        if let propPool = root.components[PropPoolRuntimeComponent.self]?.runtime {
            propPool.weatherState = weatherState
            updatePropPool(propPool, travel: safeTravel)
        }
        if let heroEntity = root.children.first(where: { $0.name == heroRootName }),
           let hero = heroEntity.components[RacingEnvironmentHeroAnchorComponent.self] {
            let trackPlacement = RacingWorldLayout.trackPlacement(
                distance: hero.distance,
                travel: safeTravel,
                track: hero.track
            )
            heroEntity.position = trackPlacement.position
            heroEntity.orientation = trackPlacement.orientation
        }
        applyWeatherState(weatherState, to: root)
    }

    private static func applyWeatherState(
        _ state: WeatherPresentationState,
        to root: Entity
    ) {
        guard let runtime = root.components[WeatherRuntimeComponent.self]?.runtime else {
            return
        }
        let wetMaterialSetChanged = runtime.usesWetMaterialsApplied != state.usesWetMaterials
        runtime.state = state
        if wetMaterialSetChanged {
            for surface in runtime.surfaces {
                surface.entity.components.set(
                    state.usesWetMaterials ? surface.wetModel : surface.dryModel
                )
            }
            runtime.usesWetMaterialsApplied = state.usesWetMaterials
        }
        for layer in RacingEnvironmentDistanceLayer.allCases {
            guard let layerRoot = root.children.first(where: {
                $0.name == rootName(for: layer)
            }) else { continue }
            setOpacity(state.visibility.value(for: layer), on: layerRoot)
        }
        if let hero = root.children.first(where: { $0.name == heroRootName }) {
            let baseOpacity = hazeContracts(for: state.track)[2].opacity
            setOpacity(baseOpacity * state.visibility.far, on: hero)
        }

        for (index, particle) in runtime.rainParticles.enumerated() {
            let isActive = index < state.rainParticleCount
            particle.entity.position = particle.basePosition + state.rainTranslation
            setOpacity(isActive ? state.rainWorldOpacity : 0, on: particle.entity)
            particle.entity.isEnabled = isActive
        }
        for (index, particle) in runtime.dustSprayParticles.enumerated() {
            let isActive = index < state.dustSprayParticleCount
            particle.entity.position = particle.basePosition + state.dustSprayTranslation
            setOpacity(isActive ? state.dustSprayOpacity : 0, on: particle.entity)
            particle.entity.isEnabled = isActive
        }
        for cue in runtime.hazeCues {
            let opacity = min(max(1 - state.visibility.far, 0), 1) * 0.24
            cue.entity.position = cue.basePosition + state.movingWorldHazeTranslation
            setOpacity(opacity, on: cue.entity)
            cue.entity.isEnabled = opacity > 0.001
        }
        for cue in runtime.puddleCues {
            cue.entity.position = cue.basePosition
            setOpacity(state.puddleOpacity, on: cue.entity)
            cue.entity.isEnabled = state.puddlesEnabled && state.puddleOpacity > 0.001
        }
        let lightning = runtime.lightningCue
        lightning.entity.position = lightning.basePosition + state.lightningTranslation
        lightning.entity.scale = SIMD3(repeating: state.lightningScale)
        setOpacity(state.lightningOpacity, on: lightning.entity)
        lightning.entity.isEnabled = state.lightningOpacity > 0.001
    }

    private static func updatePropPool(
        _ runtime: PropPoolRuntime,
        travel: Double
    ) {
        for slot in runtime.slots {
            let activeSlotCount = runtime.profile.qualityBudgets
                .budget(for: runtime.tier)
                .clusterDensity
                .clusterCount(for: slot.layer)
            guard slot.slotIndex < activeSlotCount else {
                slot.entity.isEnabled = false
                slot.contactShadow?.isEnabled = false
                continue
            }
            slot.entity.isEnabled = true
            guard let primaryBand = slot.bands.first,
                  let primaryState = RacingEnvironmentLayout.propSlotState(
                    layer: slot.layer,
                    bandIndex: primaryBand.contract.bandIndex,
                    slotIndex: slot.slotIndex,
                    slotCount: activeSlotCount,
                    travel: travel
                  ) else { continue }
            if runtime.tier == .enhanced, slot.layer == .foreground {
                slot.nearLODState = RacingEnvironmentLayout.nearLODContract.nextState(
                    current: slot.nearLODState,
                    distance: primaryState.distance
                )
            }

            var primaryPlacement: RacingEnvironmentClusterPlacement?
            var primaryOpacity: Float = 0
            for band in slot.bands {
                guard let state = RacingEnvironmentLayout.propSlotState(
                    layer: slot.layer,
                    bandIndex: band.contract.bandIndex,
                    slotIndex: slot.slotIndex,
                    slotCount: activeSlotCount,
                    travel: travel
                ) else { continue }
                let placement: RacingEnvironmentClusterPlacement
                if band.logicalSegmentIndex == state.logicalSegmentIndex,
                   let cachedPlacement = band.placement {
                    placement = cachedPlacement
                } else {
                    let roleSalt = UInt64(band.contract.bandIndex + 1)
                        &* 0xC6BC_2796_92B5_C323
                    guard let generatedPlacement = RacingEnvironmentLayout.clusterPlacement(
                        profile: runtime.profile,
                        seed: RacingEnvironmentLayout.sceneSeed,
                        logicalSegmentIndex: state.logicalSegmentIndex,
                        qualityTier: runtime.tier,
                        layer: slot.layer,
                        slotIndex: slot.slotIndex,
                        roleSalt: roleSalt
                    ) else { continue }
                    placement = generatedPlacement
                }

                if band.logicalSegmentIndex != state.logicalSegmentIndex
                    || band.variantIndex != placement.variantIndex
                    || band.usesWetMaterials != runtime.weatherState.usesWetMaterials {
                    configure(
                        band: band,
                        placement: placement,
                        runtime: runtime
                    )
                    band.logicalSegmentIndex = state.logicalSegmentIndex
                    band.variantIndex = placement.variantIndex
                    band.placement = placement
                    band.usesWetMaterials = runtime.weatherState.usesWetMaterials
                }

                let trackPlacement = RacingWorldLayout.trackPlacement(
                    distance: state.distance,
                    travel: travel,
                    track: runtime.track
                )
                band.entity.position = trackPlacement.position
                    + trackPlacement.orientation.act(
                        SIMD3(
                            placement.lateralOffset,
                            0,
                            -placement.longitudinalOffset
                        )
                    )
                band.entity.orientation = trackPlacement.orientation
                    * simd_quatf(angle: placement.yaw, axis: SIMD3(0, 1, 0))
                    * vegetationSwayOrientation(
                        assetName: placement.variantAssetName,
                        sway: runtime.weatherState.vegetationSwayRadians,
                        slotIndex: slot.slotIndex
                    )
                band.entity.scale = SIMD3(
                    repeating: placement.scale * (1 + Float(band.contract.bandIndex) * 0.06)
                )
                let hazeOpacity = runtime.hazeOpacities[slot.layer] ?? 1
                let tintOpacity = min(max(1 + placement.tint, 0.86), 1.08)
                let bandOpacity = min(
                    hazeOpacity
                        * band.contract.opacityMultiplier
                        * state.edgeOpacity
                        * tintOpacity,
                    1
                )
                band.distance = state.distance
                band.opacity = bandOpacity
                setOpacity(bandOpacity, on: band.entity)
                band.entity.isEnabled = bandOpacity > 0.001
                updateLODVisibility(
                    in: band,
                    tier: runtime.tier,
                    distance: state.distance,
                    nearLODState: slot.nearLODState
                )

                if band.contract.bandIndex == 0 {
                    primaryPlacement = placement
                    primaryOpacity = bandOpacity
                    slot.entity.components.set(
                        RacingEnvironmentScenePlacementComponent(
                            layer: slot.layer,
                            slotIndex: slot.slotIndex,
                            logicalSegmentIndex: state.logicalSegmentIndex,
                            assetName: placement.variantAssetName,
                            distance: state.distance,
                            lateralOffset: placement.lateralOffset,
                            footprintRadius: placement.footprintRadius,
                            scale: placement.scale,
                            yaw: placement.yaw,
                            tint: placement.tint
                        )
                    )
                }
            }

            if let shadow = slot.contactShadow,
               let placement = primaryPlacement {
                let component = shadow.components[RacingEnvironmentContactShadowComponent.self]
                let trackPlacement = RacingWorldLayout.trackPlacement(
                    distance: primaryState.distance,
                    travel: travel,
                    track: component?.track ?? runtime.track
                )
                shadow.position = trackPlacement.position + trackPlacement.orientation.act(
                    SIMD3(
                        placement.lateralOffset,
                        -0.035,
                        -placement.longitudinalOffset
                    )
                )
                shadow.orientation = trackPlacement.orientation
                shadow.scale = SIMD3(
                    max(placement.footprintRadius * 2.1, 1.4),
                    1,
                    max(placement.footprintRadius * 1.35, 1)
                )
                shadow.components.set(
                    RacingEnvironmentContactShadowComponent(
                        track: component?.track ?? runtime.track,
                        distance: primaryState.distance,
                        lateralOffset: placement.lateralOffset
                    )
                )
                setOpacity(primaryOpacity, on: shadow)
                shadow.isEnabled = primaryOpacity > 0.001
            }
        }
    }

    private static func configure(
        band: PropBandRuntime,
        placement: RacingEnvironmentClusterPlacement,
        runtime: PropPoolRuntime
    ) {
        band.entity.name = placement.variantAssetName
        for bank in band.renderBanks {
            let templateSource: TemplateSource = runtime.tier == .baseline
                ? .base
                : bank.source
            guard let template = runtime.templates[
                TemplateKey(
                    source: templateSource,
                    layer: placement.layer,
                    assetName: placement.variantAssetName
                )
            ], let fallback = template.parts.first else {
                continue
            }
            for (index, part) in bank.renderParts.enumerated() {
                let isActive = template.parts.indices.contains(index)
                let templatePart = isActive ? template.parts[index] : fallback
                part.components.set(
                    runtime.weatherState.usesWetMaterials
                        ? templatePart.wetModel
                        : templatePart.dryModel
                )
                part.transform = templatePart.transform
                part.isEnabled = isActive
            }
        }
    }

    private static func updateLODVisibility(
        in band: PropBandRuntime,
        tier: RacingEnvironmentQualityTier,
        distance: Float,
        nearLODState: RacingEnvironmentNearLODState
    ) {
        guard tier == .enhanced else {
            let baselineBank = band.renderBanks.first(where: { $0.source == .base })
                ?? band.renderBanks.first
            for bank in band.renderBanks {
                let usesBank = baselineBank.map { bank === $0 } ?? false
                setOpacity(usesBank ? 1 : 0, on: bank.entity)
                bank.entity.isEnabled = usesBank
            }
            return
        }
        guard band.contract.layer == .foreground,
              band.renderBanks.count == 2 else {
            let hasEnhancedBank = band.renderBanks.contains { $0.source == .enhanced }
            for bank in band.renderBanks {
                let usesBank = hasEnhancedBank
                    ? bank.source == .enhanced
                    : bank.source == .base
                setOpacity(usesBank ? 1 : 0, on: bank.entity)
                bank.entity.isEnabled = usesBank
            }
            return
        }

        let transitionBlend = RacingEnvironmentLayout.nearLODContract.detailedBlend(
            distance: distance
        )
        let detailed = switch nearLODState {
        case .standard:
            transitionBlend * transitionBlend
        case .detailed:
            sqrt(transitionBlend)
        }
        for bank in band.renderBanks {
            let opacity = bank.source == .enhanced ? detailed : 1 - detailed
            setOpacity(opacity, on: bank.entity)
            bank.entity.isEnabled = opacity > 0.001
        }
    }

    private static func vegetationSwayOrientation(
        assetName: String,
        sway: Float,
        slotIndex: Int
    ) -> simd_quatf {
        let isVegetation = ["Palm", "Pine", "Forest", "Cactus", "Grass"]
            .contains { assetName.contains($0) }
        guard isVegetation, sway != 0 else { return simd_quatf() }
        let direction: Float = slotIndex.isMultiple(of: 2) ? 1 : -1
        return simd_quatf(
            angle: sway * direction,
            axis: SIMD3(0, 0, 1)
        )
    }

    private static func setOpacity(_ value: Float, on entity: Entity) {
        guard var component = entity.components[OpacityComponent.self] else { return }
        let opacity = min(max(value, 0), 1)
        guard component.opacity != opacity else { return }
        component.opacity = opacity
        entity.components.set(component)
    }

    private static func sanitizedTravel(_ travel: Double) -> Double {
        guard travel.isFinite else { return 0 }
        return min(max(travel, 0), 1_000_000_000)
    }

    private static func applyTerrainMaterialToShoulders(
        in world: Entity,
        material: PhysicallyBasedMaterial,
        weatherRuntime: WeatherRuntime?
    ) {
        for entity in descendants(including: world) where entity.name == "shoulder" {
            guard var model = entity.components[ModelComponent.self] else { continue }
            model.materials = [material]
            entity.components.set(model)
            entity.components.set(
                RacingEnvironmentTerrainSurfaceComponent(
                    kind: .shoulder,
                    usesBaseColor: true,
                    usesNormal: true,
                    usesRoughness: true
                )
            )
            if let surface = weatherSurfaceRuntime(entity) {
                weatherRuntime?.surfaces.append(surface)
                entity.components.set(
                    weatherRuntime?.state.usesWetMaterials == true
                        ? surface.wetModel
                        : surface.dryModel
                )
            }
        }
    }

    private static func disableLegacyEnvironment(in world: Entity) {
        world.children.first(where: { $0.name == "racing.environment" })?.isEnabled = false
        for entity in descendants(including: world) where isLegacyNaturalProp(entity) {
            entity.isEnabled = false
        }
    }

    private static func isLegacyNaturalProp(_ entity: Entity) -> Bool {
        ["racing.palm", "racing.pine", "racing.cactus", "racing.rockCluster"]
            .contains(entity.name)
    }

    private static func isLegacyPrimitive(_ entity: Entity) -> Bool {
        entity.name == "ground"
            || entity.name.hasPrefix("racing.mountain.")
            || isLegacyNaturalProp(entity)
    }

    private static func removeInteractionComponents(from entity: Entity) {
        entity.components.remove(CollisionComponent.self)
        entity.components.remove(InputTargetComponent.self)
        for child in entity.children {
            removeInteractionComponents(from: child)
        }
    }

    private static func applyAtmosphericTint(
        to entity: Entity,
        contract: RacingEnvironmentSceneHazeContract
    ) {
        if var model = entity.components[ModelComponent.self] {
            model.materials = model.materials.map { material in
                guard var pbr = material as? PhysicallyBasedMaterial else { return material }
                var red: CGFloat = 1
                var green: CGFloat = 1
                var blue: CGFloat = 1
                var alpha: CGFloat = 1
                pbr.baseColor.tint.getRed(
                    &red,
                    green: &green,
                    blue: &blue,
                    alpha: &alpha
                )
                pbr.baseColor.tint = UIColor(
                    red: red * CGFloat(contract.tint.x),
                    green: green * CGFloat(contract.tint.y),
                    blue: blue * CGFloat(contract.tint.z),
                    alpha: alpha
                )
                pbr.roughness.scale = min(
                    1,
                    pbr.roughness.scale + contract.coefficient * 0.12
                )
                return pbr
            }
            entity.components.set(model)
        }
        for child in entity.children {
            applyAtmosphericTint(to: child, contract: contract)
        }
    }

    private static func descendants(including root: Entity) -> [Entity] {
        var result: [Entity] = [root]
        for child in root.children {
            result.append(contentsOf: descendants(including: child))
        }
        return result
    }
}

private extension RacingEnvironmentDistanceLayer {
    var index: Int {
        switch self {
        case .foreground: 0
        case .midground: 1
        case .far: 2
        }
    }
}
