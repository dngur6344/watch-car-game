import RealityKit
import XCTest
@testable import WatchCarRacer

@MainActor
final class RacingEnvironmentSceneTests: XCTestCase {
    func testPBXMembershipKeepsSceneImplementationIOSOnlyAndFocusedTestsTestOnly() throws {
        let project = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "WatchCarRacer.xcodeproj/project.pbxproj"
            ),
            encoding: .utf8
        )
        let gameGroup = try XCTUnwrap(
            projectSection(project, startingWith: "02000000000000000000000E /* Game */ = {")
        )
        let testGroup = try XCTUnwrap(
            projectSection(
                project,
                startingWith: "020000000000000000000008 /* WatchCarRacerTests */ = {"
            )
        )
        let appSources = try XCTUnwrap(
            projectSection(project, startingWith: "050000000000000000000001 /* Sources */ = {")
        )
        let watchSources = try XCTUnwrap(
            projectSection(project, startingWith: "050000000000000000000011 /* Sources */ = {")
        )
        let testSources = try XCTUnwrap(
            projectSection(project, startingWith: "050000000000000000000021 /* Sources */ = {")
        )

        XCTAssertEqual(
            gameGroup.components(separatedBy: "RacingEnvironmentScene.swift").count - 1,
            1
        )
        XCTAssertEqual(
            appSources.components(
                separatedBy: "RacingEnvironmentScene.swift in Sources"
            ).count - 1,
            1
        )
        XCTAssertFalse(watchSources.contains("RacingEnvironmentScene.swift"))
        XCTAssertFalse(testSources.contains("RacingEnvironmentScene.swift in Sources"))

        XCTAssertEqual(
            testGroup.components(separatedBy: "RacingEnvironmentSceneTests.swift").count - 1,
            1
        )
        XCTAssertEqual(
            testSources.components(
                separatedBy: "RacingEnvironmentSceneTests.swift in Sources"
            ).count - 1,
            1
        )
        XCTAssertFalse(appSources.contains("RacingEnvironmentSceneTests.swift"))
        XCTAssertFalse(watchSources.contains("RacingEnvironmentSceneTests.swift"))
    }

    func testRuntimeUpdatePathDoesNotCreateOrReparentEntitiesMeshesOrMaterials() throws {
        let source = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "WatchCarRacer/iOS/Game/RacingEnvironmentScene.swift"
            ),
            encoding: .utf8
        )
        let start = try XCTUnwrap(
            source.range(of: "    private static func updateTransforms(in root: Entity")
        )
        let end = try XCTUnwrap(
            source.range(
                of: "    private static func sanitizedTravel(_ travel: Double)",
                range: start.upperBound..<source.endIndex
            )
        )
        let updatePath = String(source[start.lowerBound..<end.lowerBound])

        for forbidden in [
            "Entity()",
            "ModelEntity(",
            ".clone(",
            ".addChild(",
            ".removeFromParent(",
            "PhysicallyBasedMaterial(",
            "UnlitMaterial(",
            "SimpleMaterial(",
            ".generatePlane(",
            ".generateBox(",
        ] {
            XCTAssertFalse(updatePath.contains(forbidden), forbidden)
        }
    }

    func testHazeAndHeroContractsAreMonotonicFiniteAndContinuousAcrossRecycleSamples() {
        let samples = [0.0, 11.99, 12.01, 215.99, 216.01, 1.0e300]
        for track in RacingTrack.allCases {
            let haze = RacingEnvironmentScene.hazeContracts(for: track)
            XCTAssertEqual(haze.map(\.layer), [.foreground, .midground, .far])
            XCTAssertLessThan(haze[0].coefficient, haze[1].coefficient)
            XCTAssertLessThan(haze[1].coefficient, haze[2].coefficient)
            XCTAssertGreaterThan(haze[0].opacity, haze[1].opacity)
            XCTAssertGreaterThan(haze[1].opacity, haze[2].opacity)
            for channel in 0..<3 {
                XCTAssertGreaterThanOrEqual(haze[0].tint[channel], haze[1].tint[channel])
                XCTAssertGreaterThanOrEqual(haze[1].tint[channel], haze[2].tint[channel])
            }

            let anchors = samples.map {
                RacingEnvironmentScene.heroAnchor(track: track, travel: $0)
            }
            for anchor in anchors {
                XCTAssertTrue(anchor.x.isFinite && anchor.y.isFinite && anchor.z.isFinite)
                XCTAssertTrue(
                    RacingEnvironmentCatalog.profile(for: track)
                        .layerContract(for: .far)!
                        .visibleDistanceRange.contains(-anchor.z)
                )
            }
            XCTAssertLessThan(simd_distance(anchors[1], anchors[2]), 0.1)
            XCTAssertLessThan(simd_distance(anchors[3], anchors[4]), 0.1)
        }
    }

    func testBaselineAndEnhancedAssemblyForEveryTrackMeetHierarchyClearanceAndBudgets() async throws {
        let library = RacingEnvironmentAssetLibrary()

        for track in RacingTrack.allCases {
            for tier in RacingEnvironmentQualityTier.allCases {
                let resources = await library.resources(for: track, tier: tier)
                XCTAssertEqual(resources.diagnostic, .authored, "\(track) \(tier)")
                let assembly = try RacingEnvironmentScene.assemble(
                    resources: resources,
                    travel: 215.99
                )
                let snapshot = assembly.snapshot
                let profile = RacingEnvironmentCatalog.profile(for: track)
                let budget = profile.qualityBudgets.budget(for: tier)
                let expectedDensity = budget.clusterDensity

                XCTAssertEqual(snapshot.track, track)
                XCTAssertEqual(snapshot.tier, tier)
                XCTAssertEqual(snapshot.diagnostic, .authored)
                XCTAssertEqual(snapshot.hierarchyNames, RacingEnvironmentScene.hierarchyNames)
                XCTAssertEqual(snapshot.minimumRoadApertureWidth, 14)
                XCTAssertGreaterThanOrEqual(snapshot.minimumRoadApertureWidth, 14)
                XCTAssertEqual(snapshot.atlasQuadrantCount, 4)
                XCTAssertTrue(snapshot.terrainUsesBaseColor)
                XCTAssertTrue(snapshot.terrainUsesNormal)
                XCTAssertTrue(snapshot.terrainUsesRoughness)
                XCTAssertTrue(snapshot.terrainExtendsPastHorizon)
                XCTAssertTrue(snapshot.appliesPBRToShoulders)
                XCTAssertEqual(snapshot.collisionComponentCount, 0)
                XCTAssertEqual(snapshot.inputTargetComponentCount, 0)
                XCTAssertFalse(snapshot.containsPrimitiveFallback)
                XCTAssertLessThanOrEqual(snapshot.entityCount, budget.maximumEntityCount)
                XCTAssertLessThanOrEqual(snapshot.materialCount, budget.maximumMaterialCount)
                XCTAssertLessThanOrEqual(
                    snapshot.contactShadowCount,
                    budget.maximumContactShadowCount
                )
                let expectedPropSlotCount = RacingEnvironmentDistanceLayer.allCases.reduce(0) {
                    $0 + expectedDensity.clusterCount(for: $1)
                }
                XCTAssertEqual(snapshot.preallocatedPropSlotCount, expectedPropSlotCount)
                XCTAssertEqual(Set(snapshot.propSlotIdentities).count, expectedPropSlotCount)
                XCTAssertGreaterThan(
                    snapshot.preallocatedRenderPartCount,
                    snapshot.preallocatedPropSlotCount
                )
                XCTAssertEqual(
                    Set(snapshot.renderPartIdentities).count,
                    snapshot.preallocatedRenderPartCount
                )
                XCTAssertEqual(snapshot.parallaxBandCounts[.foreground], 1)
                XCTAssertEqual(snapshot.parallaxBandCounts[.midground], 2)
                XCTAssertEqual(snapshot.parallaxBandCounts[.far], 2)
                let terrainSurface = try XCTUnwrap(
                    assembly.root.findEntity(named: "continuous-pbr-terrain")
                )
                let terrainMaterial = try XCTUnwrap(
                    terrainSurface.components[ModelComponent.self]?
                        .materials.first as? PhysicallyBasedMaterial
                )
                XCTAssertNotNil(terrainMaterial.baseColor.texture)
                XCTAssertNotNil(terrainMaterial.normal.texture)
                XCTAssertNotNil(terrainMaterial.roughness.texture)
                let decalRoot = try XCTUnwrap(
                    assembly.root.children.first { $0.name == RacingEnvironmentScene.decalRootName }
                )
                XCTAssertEqual(decalRoot.children.count, 4)
                XCTAssertEqual(
                    Set(decalRoot.children.compactMap {
                        ($0.components[ModelComponent.self]?.materials.first
                            as? PhysicallyBasedMaterial)?.textureCoordinateTransform.offset
                    }),
                    Set([
                        SIMD2<Float>(0, 0),
                        SIMD2<Float>(0.5, 0),
                        SIMD2<Float>(0, 0.5),
                        SIMD2<Float>(0.5, 0.5),
                    ])
                )

                XCTAssertEqual(
                    snapshot.placements.filter { $0.layer == .foreground }.count,
                    expectedDensity.foreground
                )
                XCTAssertEqual(
                    snapshot.placements.filter { $0.layer == .midground }.count,
                    expectedDensity.midground
                )
                XCTAssertEqual(
                    snapshot.placements.filter { $0.layer == .far }.count,
                    expectedDensity.far
                )
                XCTAssertEqual(snapshot.contactShadowCount, expectedDensity.foreground)
                for placement in snapshot.placements {
                    XCTAssertTrue(
                        profile.layerContract(for: placement.layer)!
                            .visibleDistanceRange.contains(placement.distance),
                        "\(track) \(tier) \(placement.assetName)"
                    )
                    XCTAssertGreaterThanOrEqual(
                        placement.propEdgeOffset,
                        profile.roadClearance.minimumPropEdgeOffset,
                        "\(track) \(tier) \(placement.assetName)"
                    )
                    XCTAssertNotNil(
                        assembly.root.findEntity(named: placement.assetName),
                        placement.assetName
                    )
                }
                XCTAssertNotNil(
                    assembly.root.findEntity(named: profile.hero.assetName),
                    profile.hero.assetName
                )
            }
        }
    }

    func testInstallIsAtomicDisablesOnlyLegacyNatureAndAppliesPBRShoulders() async throws {
        let resources = await RacingEnvironmentAssetLibrary().resources(
            for: .coastal,
            tier: .baseline
        )
        XCTAssertEqual(resources.diagnostic, .authored)
        let world = makeLegacyWorld()

        XCTAssertTrue(
            RacingEnvironmentScene.install(in: world, resources: resources, travel: 0)
        )
        XCTAssertNotNil(world.findEntity(named: RacingEnvironmentScene.rootName))
        XCTAssertEqual(world.findEntity(named: "racing.environment")?.isEnabled, false)
        for name in ["racing.palm", "racing.pine", "racing.cactus", "racing.rockCluster"] {
            XCTAssertEqual(world.findEntity(named: name)?.isEnabled, false, name)
        }
        for name in [
            "racing.grandstand",
            "racing.pitBuilding",
            "racing.hotelTower",
            "guardrail",
            "racing.roadsideLight",
            "racing.track.arch",
        ] {
            XCTAssertEqual(world.findEntity(named: name)?.isEnabled, true, name)
        }
        let shoulder = try XCTUnwrap(world.findEntity(named: "shoulder"))
        XCTAssertTrue(RacingEnvironmentScene.isPBRShoulder(shoulder))
        let shoulderMaterial = try XCTUnwrap(
            shoulder.components[ModelComponent.self]?.materials.first
                as? PhysicallyBasedMaterial
        )
        XCTAssertNotNil(shoulderMaterial.baseColor.texture)
        XCTAssertNotNil(shoulderMaterial.normal.texture)
        XCTAssertNotNil(shoulderMaterial.roughness.texture)
    }

    func testFallbackDiagnosticLeavesCompleteLegacyEnvironmentAvailable() async {
        let authored = await RacingEnvironmentAssetLibrary().resources(
            for: .desert,
            tier: .baseline
        )
        let fallback = RacingEnvironmentResources(
            track: authored.track,
            requestedTier: .baseline,
            effectiveTier: .baseline,
            baseEntity: Entity(),
            enhancedEntity: nil,
            baseColorTexture: nil,
            normalTexture: nil,
            roughnessTexture: nil,
            diagnostic: .fallback(.manifestUnavailable)
        )
        let world = makeLegacyWorld()

        XCTAssertFalse(
            RacingEnvironmentScene.install(in: world, resources: fallback, travel: 216.01)
        )
        XCTAssertNil(world.findEntity(named: RacingEnvironmentScene.rootName))
        XCTAssertEqual(world.findEntity(named: "racing.environment")?.isEnabled, true)
        for name in ["racing.palm", "racing.pine", "racing.cactus", "racing.rockCluster"] {
            XCTAssertEqual(world.findEntity(named: name)?.isEnabled, true, name)
        }
        XCTAssertFalse(
            RacingEnvironmentScene.isPBRShoulder(world.findEntity(named: "shoulder")!)
        )

        let incomplete = RacingEnvironmentResources(
            track: authored.track,
            requestedTier: .baseline,
            effectiveTier: .baseline,
            baseEntity: authored.baseEntity,
            enhancedEntity: nil,
            baseColorTexture: authored.baseColorTexture,
            normalTexture: authored.normalTexture,
            roughnessTexture: nil,
            diagnostic: .authored
        )
        let incompleteWorld = makeLegacyWorld()
        XCTAssertFalse(
            RacingEnvironmentScene.install(
                in: incompleteWorld,
                resources: incomplete,
                travel: 0
            )
        )
        XCTAssertNil(incompleteWorld.findEntity(named: RacingEnvironmentScene.rootName))
        XCTAssertEqual(
            incompleteWorld.findEntity(named: "racing.environment")?.isEnabled,
            true
        )
    }

    func testUpdatesChangeOnlyTransformsAndKeepSceneAndMaterialCountsStable() async throws {
        let resources = await RacingEnvironmentAssetLibrary().resources(
            for: .alpine,
            tier: .enhanced
        )
        let assembly = try RacingEnvironmentScene.assemble(resources: resources, travel: 0)
        let world = Entity()
        world.addChild(assembly.root)
        let before = try RacingEnvironmentScene.snapshot(of: assembly.root)
        let childIdentitiesBefore = descendantIdentities(of: assembly.root)

        for travel in [11.99, 12.01, 215.99, 216.01, 50_000.0] {
            RacingEnvironmentScene.update(in: world, travel: travel)
        }
        let after = try RacingEnvironmentScene.snapshot(of: assembly.root)

        XCTAssertEqual(after.entityCount, before.entityCount)
        XCTAssertEqual(after.materialCount, before.materialCount)
        XCTAssertEqual(
            after.modelMaterialAssignmentCount,
            before.modelMaterialAssignmentCount
        )
        XCTAssertEqual(after.contactShadowCount, before.contactShadowCount)
        XCTAssertEqual(after.preallocatedPropSlotCount, before.preallocatedPropSlotCount)
        XCTAssertEqual(after.preallocatedRenderPartCount, before.preallocatedRenderPartCount)
        XCTAssertEqual(after.propSlotIdentities, before.propSlotIdentities)
        XCTAssertEqual(after.renderPartIdentities, before.renderPartIdentities)
        XCTAssertEqual(descendantIdentities(of: assembly.root), childIdentitiesBefore)
        XCTAssertNotEqual(after.placements, before.placements)
        XCTAssertEqual(
            after.heroAnchor,
            RacingEnvironmentScene.heroAnchor(track: .alpine, travel: 50_000)
        )
    }

    func testEnhancedNearLODUsesHysteresisWithPreallocatedCrossFadeBanks() async throws {
        let resources = await RacingEnvironmentAssetLibrary().resources(
            for: .coastal,
            tier: .enhanced
        )
        let assembly = try RacingEnvironmentScene.assemble(resources: resources, travel: 0)
        let world = Entity()
        world.addChild(assembly.root)
        let initial = try RacingEnvironmentScene.snapshot(of: assembly.root)
        XCTAssertEqual(initial.detailedLODSlotCount, 2)

        RacingEnvironmentScene.update(in: world, travel: 8)
        let entered = try RacingEnvironmentScene.snapshot(of: assembly.root)
        XCTAssertEqual(entered.detailedLODSlotCount, 3)

        RacingEnvironmentScene.update(in: world, travel: 6)
        let hysteresisHold = try RacingEnvironmentScene.snapshot(of: assembly.root)
        XCTAssertEqual(hysteresisHold.detailedLODSlotCount, 3)
        XCTAssertEqual(hysteresisHold.propSlotIdentities, initial.propSlotIdentities)
        XCTAssertEqual(hysteresisHold.renderPartIdentities, initial.renderPartIdentities)

        RacingEnvironmentScene.update(in: world, travel: 46)
        let exited = try RacingEnvironmentScene.snapshot(of: assembly.root)
        XCTAssertEqual(exited.detailedLODSlotCount, 2)
        XCTAssertEqual(exited.entityCount, initial.entityCount)
        XCTAssertEqual(exited.modelMaterialAssignmentCount, initial.modelMaterialAssignmentCount)
    }

    func testMidFarDoubleBandsKeepDepthOrderingMotionAndRoadRecycleContinuity() async throws {
        let resources = await RacingEnvironmentAssetLibrary().resources(
            for: .desert,
            tier: .enhanced
        )
        let assembly = try RacingEnvironmentScene.assemble(resources: resources, travel: 0)
        let world = Entity()
        world.addChild(assembly.root)
        let start = try RacingEnvironmentScene.snapshot(of: assembly.root)

        for layer in [
            RacingEnvironmentDistanceLayer.midground,
            RacingEnvironmentDistanceLayer.far,
        ] {
            let slots = Set(start.parallaxBands.filter { $0.layer == layer }.map(\.slotIndex))
            for slotIndex in slots {
                let bands = start.parallaxBands
                    .filter { $0.layer == layer && $0.slotIndex == slotIndex }
                    .sorted { $0.bandIndex < $1.bandIndex }
                XCTAssertEqual(bands.count, 2)
                XCTAssertLessThan(bands[0].distance, bands[1].distance)
                XCTAssertGreaterThan(bands[0].travelMultiplier, bands[1].travelMultiplier)
            }
        }

        RacingEnvironmentScene.update(in: world, travel: 0.5)
        let moved = try RacingEnvironmentScene.snapshot(of: assembly.root)
        let startByIdentity = Dictionary(
            uniqueKeysWithValues: start.parallaxBands.map { ($0.identity, $0) }
        )
        for band in moved.parallaxBands where band.layer != .foreground {
            let prior = try XCTUnwrap(startByIdentity[band.identity])
            XCTAssertGreaterThan(abs(band.distance - prior.distance), 0)
        }

        RacingEnvironmentScene.update(in: world, travel: 215.99)
        let beforeRecycle = try RacingEnvironmentScene.snapshot(of: assembly.root)
        RacingEnvironmentScene.update(in: world, travel: 216.01)
        let afterRecycle = try RacingEnvironmentScene.snapshot(of: assembly.root)
        let beforeByIdentity = Dictionary(
            uniqueKeysWithValues: beforeRecycle.parallaxBands.map { ($0.identity, $0) }
        )
        for band in afterRecycle.parallaxBands where band.layer != .foreground {
            let before = try XCTUnwrap(beforeByIdentity[band.identity])
            XCTAssertLessThan(abs(band.distance - before.distance), 0.05)
        }
        XCTAssertEqual(afterRecycle.propSlotIdentities, beforeRecycle.propSlotIdentities)
        XCTAssertEqual(afterRecycle.renderPartIdentities, beforeRecycle.renderPartIdentities)
        XCTAssertEqual(afterRecycle.entityCount, beforeRecycle.entityCount)
        XCTAssertEqual(
            afterRecycle.modelMaterialAssignmentCount,
            beforeRecycle.modelMaterialAssignmentCount
        )
    }

    private func makeLegacyWorld() -> Entity {
        let world = Entity()
        let environment = Entity()
        environment.name = "racing.environment"
        let ground = Entity()
        ground.name = "ground"
        environment.addChild(ground)
        world.addChild(environment)

        let track = Entity()
        track.name = "racing.track"
        let shoulder = ModelEntity(
            mesh: .generatePlane(width: 2, depth: 12),
            materials: [SimpleMaterial(color: .brown, isMetallic: false)]
        )
        shoulder.name = "shoulder"
        track.addChild(shoulder)
        for name in [
            "racing.palm",
            "racing.pine",
            "racing.cactus",
            "racing.rockCluster",
            "racing.grandstand",
            "racing.pitBuilding",
            "racing.hotelTower",
            "guardrail",
            "racing.roadsideLight",
            "racing.track.arch",
        ] {
            let entity = Entity()
            entity.name = name
            track.addChild(entity)
        }
        world.addChild(track)
        return world
    }

    private func descendantIdentities(of root: Entity) -> [ObjectIdentifier] {
        [ObjectIdentifier(root)] + root.children.flatMap(descendantIdentities)
    }

    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func projectSection(_ project: String, startingWith marker: String) -> String? {
        guard let start = project.range(of: marker)?.lowerBound,
              let end = project[start...].range(of: "\n\t\t};")?.upperBound else {
            return nil
        }
        return String(project[start..<end])
    }
}
