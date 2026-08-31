import RealityKit
import XCTest
@testable import WatchCarRacer

@MainActor
final class RacingEnvironmentWeatherTests: XCTestCase {
    func testPBXMembershipKeepsWeatherImplementationIOSOnlyAndTestsTestOnly() throws {
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
            gameGroup.components(separatedBy: "RacingEnvironmentWeather.swift").count - 1,
            1
        )
        XCTAssertEqual(
            appSources.components(
                separatedBy: "RacingEnvironmentWeather.swift in Sources"
            ).count - 1,
            1
        )
        XCTAssertFalse(watchSources.contains("RacingEnvironmentWeather.swift"))
        XCTAssertFalse(testSources.contains("RacingEnvironmentWeather.swift in Sources"))

        XCTAssertEqual(
            testGroup.components(
                separatedBy: "RacingEnvironmentWeatherTests.swift"
            ).count - 1,
            1
        )
        XCTAssertEqual(
            testSources.components(
                separatedBy: "RacingEnvironmentWeatherTests.swift in Sources"
            ).count - 1,
            1
        )
        XCTAssertFalse(appSources.contains("RacingEnvironmentWeatherTests.swift"))
        XCTAssertFalse(watchSources.contains("RacingEnvironmentWeatherTests.swift"))
    }

    func testTwelveTrackWeatherCombinationsAreFiniteBoundedAndLegible() {
        for track in RacingTrack.allCases {
            for weather in RacingWeather.allCases {
                let state = makeState(
                    track: track,
                    weather: weather,
                    travel: 987.65,
                    tier: .baseline
                )
                let budget = RacingEnvironmentCatalog.profile(for: track)
                    .qualityBudgets.baseline

                XCTAssertTrue(state.allNumericValuesAreFinite, "\(track) \(weather)")
                XCTAssertEqual(state.track, track)
                XCTAssertEqual(state.weather, weather)
                XCTAssertEqual(state.tier, .baseline)
                XCTAssertTrue((0...1).contains(state.terrainWetness))
                XCTAssertTrue((0...1).contains(state.rockWetness))
                XCTAssertTrue((0...1).contains(state.terrainRoughness))
                XCTAssertTrue((0...1).contains(state.rockRoughness))
                XCTAssertTrue((0...1).contains(state.clearcoat))
                XCTAssertTrue((0...1).contains(state.visibility.foreground))
                XCTAssertTrue((0...1).contains(state.visibility.midground))
                XCTAssertTrue((0...1).contains(state.visibility.far))
                XCTAssertGreaterThanOrEqual(state.subjectContrastFloor, 0.72)
                XCTAssertLessThanOrEqual(
                    state.combinedAtmosphericObscuration,
                    RacingEnvironmentWeather.maximumCombinedAtmosphericObscuration
                )
                XCTAssertLessThanOrEqual(
                    state.weatherParticleCount,
                    budget.maximumWeatherParticleCount
                )
                XCTAssertGreaterThanOrEqual(state.weatherParticleCount, 0)
                XCTAssertLessThanOrEqual(state.lightningScale, 1.02)
                XCTAssertGreaterThanOrEqual(state.lightningScale, 1)

                switch weather {
                case .clear:
                    XCTAssertEqual(state.terrainWetness, 0)
                    XCTAssertEqual(state.weatherParticleCount, 0)
                    XCTAssertFalse(state.puddlesEnabled)
                    XCTAssertGreaterThanOrEqual(state.visibility.far, 0.90)
                case .rain:
                    XCTAssertGreaterThan(state.rainParticleCount, 0)
                    XCTAssertEqual(state.dustSprayParticleCount, 0)
                    XCTAssertTrue(state.puddlesEnabled)
                case .fog:
                    XCTAssertEqual(state.weatherParticleCount, 0)
                    XCTAssertFalse(state.puddlesEnabled)
                    XCTAssertGreaterThan(state.visibility.foreground, state.visibility.midground)
                    XCTAssertGreaterThan(state.visibility.midground, state.visibility.far)
                    XCTAssertLessThanOrEqual(state.overlay.fogOpacity, 0.12)
                case .storm:
                    XCTAssertGreaterThan(state.rainParticleCount, 0)
                    XCTAssertGreaterThan(state.dustSprayParticleCount, 0)
                    XCTAssertTrue(state.puddlesEnabled)
                    XCTAssertEqual(state.stormEffectKind, track == .desert ? .dust : .spray)
                }
            }
        }
    }

    func testWetWeatherIncreasesWetnessAndLowersTerrainAndRockRoughness() {
        for track in RacingTrack.allCases {
            let clear = makeState(track: track, weather: .clear)
            for weather in [RacingWeather.rain, .storm] {
                let wet = makeState(track: track, weather: weather)
                XCTAssertGreaterThan(wet.terrainWetness, clear.terrainWetness)
                XCTAssertGreaterThan(wet.rockWetness, clear.rockWetness)
                XCTAssertLessThan(wet.terrainRoughness, clear.terrainRoughness)
                XCTAssertLessThan(wet.rockRoughness, clear.rockRoughness)
                XCTAssertGreaterThan(wet.clearcoat, clear.clearcoat)
                XCTAssertGreaterThan(wet.puddleOpacity, 0)
            }
        }
    }

    func testStormPhaseIsDeterministicAndInvalidTravelIsSanitized() {
        for track in RacingTrack.allCases {
            let first = makeState(track: track, weather: .storm, travel: 12_345.678)
            let second = makeState(track: track, weather: .storm, travel: 12_345.678)
            XCTAssertEqual(first, second)

            let zero = makeState(track: track, weather: .storm, travel: 0)
            for invalid in [Double.nan, .infinity, -.infinity, -1, -500] {
                XCTAssertEqual(
                    makeState(track: track, weather: .storm, travel: invalid),
                    zero,
                    "\(track) \(invalid)"
                )
            }
            let greatest = makeState(
                track: track,
                weather: .storm,
                travel: .greatestFiniteMagnitude
            )
            XCTAssertEqual(
                greatest.sanitizedTravel,
                RacingEnvironmentWeather.maximumSanitizedTravel
            )
            XCTAssertTrue(greatest.allNumericValuesAreFinite)
        }
    }

    func testBaselineAndEnhancedParticleCountsStayWithinTierBudgets() {
        for track in RacingTrack.allCases {
            let profile = RacingEnvironmentCatalog.profile(for: track)
            for tier in RacingEnvironmentQualityTier.allCases {
                let budget = profile.qualityBudgets.budget(for: tier)
                for weather in RacingWeather.allCases {
                    let state = makeState(
                        track: track,
                        weather: weather,
                        tier: tier
                    )
                    XCTAssertEqual(
                        state.maximumWeatherParticleCount,
                        budget.maximumWeatherParticleCount
                    )
                    XCTAssertLessThanOrEqual(
                        state.weatherParticleCount,
                        budget.maximumWeatherParticleCount
                    )
                }
            }
            XCTAssertGreaterThan(
                makeState(track: track, weather: .rain, tier: .enhanced)
                    .rainParticleCount,
                makeState(track: track, weather: .rain, tier: .baseline)
                    .rainParticleCount
            )
        }
    }

    func testFourAccessibilityCombinationsClampMotionAndTranslucencyIndependently() {
        for reduceMotion in [false, true] {
            let transparent = makeState(
                track: .desert,
                weather: .storm,
                travel: 222.2,
                reduceMotion: reduceMotion,
                reduceTransparency: false
            )
            let opaque = makeState(
                track: .desert,
                weather: .storm,
                travel: 222.2,
                reduceMotion: reduceMotion,
                reduceTransparency: true
            )

            XCTAssertEqual(opaque.visibility, transparent.visibility)
            XCTAssertLessThan(opaque.overlay.darkWashOpacity, transparent.overlay.darkWashOpacity)
            XCTAssertLessThan(opaque.overlay.rainOpacity, transparent.overlay.rainOpacity)
            XCTAssertLessThanOrEqual(
                opaque.overlay.lightningOpacity,
                transparent.overlay.lightningOpacity
            )

            if reduceMotion {
                for state in [transparent, opaque] {
                    XCTAssertEqual(state.vegetationSwayRadians, 0)
                    XCTAssertEqual(state.rainTranslation, .zero)
                    XCTAssertEqual(state.movingWorldHazeTranslation, .zero)
                    XCTAssertEqual(state.dustSprayTranslation, .zero)
                    XCTAssertEqual(state.lightningTranslation, .zero)
                    XCTAssertEqual(state.lightningScale, 1)
                    XCTAssertEqual(state.overlay.rainPhase, 0)
                    XCTAssertEqual(state.lightningOpacity, 0.055)
                }
            } else {
                XCTAssertNotEqual(transparent.movingWorldHazeTranslation, .zero)
                XCTAssertNotEqual(transparent.dustSprayTranslation, .zero)
                XCTAssertNotEqual(transparent.overlay.rainPhase, 0)
            }
        }
    }

    func testScenePrecreatesFiniteEffectsAndWeatherUpdatesKeepAllCountsAndIdentities() async throws {
        for tier in RacingEnvironmentQualityTier.allCases {
            let resources = await RacingEnvironmentAssetLibrary().resources(
                for: .alpine,
                tier: tier
            )
            let clearState = makeState(
                track: .alpine,
                weather: .clear,
                travel: 0,
                tier: tier
            )
            let assembly = try RacingEnvironmentScene.assemble(
                resources: resources,
                travel: 0,
                weatherState: clearState
            )
            let world = Entity()
            world.addChild(assembly.root)
            let before = try RacingEnvironmentScene.snapshot(of: assembly.root)
            let budget = RacingEnvironmentCatalog.profile(for: .alpine)
                .qualityBudgets
                .budget(for: tier)

            XCTAssertEqual(
                before.precreatedWeatherParticleCapacity,
                budget.maximumWeatherParticleCount
            )
            XCTAssertEqual(before.precreatedWeatherMaterialSetCount, 2)
            XCTAssertEqual(before.puddleCueCount, 2)
            XCTAssertEqual(before.enabledPuddleCueCount, 0)
            XCTAssertEqual(before.activeWeatherParticleCount, 0)
            XCTAssertEqual(
                Set(before.weatherEffectEntityIdentities).count,
                before.weatherEffectEntityIdentities.count
            )
            XCTAssertLessThanOrEqual(before.entityCount, budget.maximumEntityCount)
            XCTAssertLessThanOrEqual(before.materialCount, budget.maximumMaterialCount)

            let stormState = makeState(
                track: .alpine,
                weather: .storm,
                travel: 216.01,
                tier: tier
            )
            RacingEnvironmentScene.update(
                in: world,
                travel: stormState.sanitizedTravel,
                weatherState: stormState
            )
            let storm = try RacingEnvironmentScene.snapshot(of: assembly.root)
            XCTAssertEqual(storm.weatherState, stormState)
            XCTAssertEqual(storm.activeWeatherParticleCount, stormState.weatherParticleCount)
            XCTAssertEqual(storm.enabledPuddleCueCount, storm.puddleCueCount)
            XCTAssertGreaterThan(storm.wetSurfaceTargetCount, 0)
            assertStableScene(before, storm)

            let reducedFog = makeState(
                track: .alpine,
                weather: .fog,
                travel: 500,
                tier: tier,
                reduceMotion: true,
                reduceTransparency: true
            )
            RacingEnvironmentScene.update(
                in: world,
                travel: reducedFog.sanitizedTravel,
                weatherState: reducedFog
            )
            let fog = try RacingEnvironmentScene.snapshot(of: assembly.root)
            XCTAssertEqual(fog.enabledPuddleCueCount, 0)
            XCTAssertEqual(fog.activeWeatherParticleCount, 0)
            XCTAssertEqual(fog.wetSurfaceTargetCount, 0)
            XCTAssertGreaterThan(fog.weatherState.visibility.foreground, fog.weatherState.visibility.midground)
            XCTAssertGreaterThan(fog.weatherState.visibility.midground, fog.weatherState.visibility.far)
            assertStableScene(before, fog)
        }
    }

    func testSceneAppliesPrecreatedWetVariantsToTerrainAndNaturalModels() async throws {
        let resources = await RacingEnvironmentAssetLibrary().resources(
            for: .coastal,
            tier: .baseline
        )
        let clearState = makeState(track: .coastal, weather: .clear)
        let assembly = try RacingEnvironmentScene.assemble(
            resources: resources,
            travel: 0,
            weatherState: clearState
        )
        let world = Entity()
        world.addChild(assembly.root)
        let terrain = try XCTUnwrap(
            assembly.root.findEntity(named: "continuous-pbr-terrain")
        )
        let naturalPart = try XCTUnwrap(assembly.root.findEntity(named: "render-part.0"))
        let clearTerrainRoughness = try roughness(of: terrain)
        let clearNaturalRoughness = try roughness(of: naturalPart)

        let rainState = makeState(track: .coastal, weather: .rain, travel: 20)
        RacingEnvironmentScene.update(
            in: world,
            travel: 20,
            weatherState: rainState
        )
        XCTAssertLessThan(try roughness(of: terrain), clearTerrainRoughness)
        XCTAssertLessThan(try roughness(of: naturalPart), clearNaturalRoughness)

        RacingEnvironmentScene.update(
            in: world,
            travel: 21,
            weatherState: makeState(track: .coastal, weather: .clear, travel: 21)
        )
        XCTAssertEqual(try roughness(of: terrain), clearTerrainRoughness)
    }

    func testProductionWiringComputesOneStateAndPassesPolicyFromGameRoot() throws {
        let rootSource = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "WatchCarRacer/iOS/App/GameRootView.swift"
            ),
            encoding: .utf8
        )
        let worldSource = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "WatchCarRacer/iOS/Game/RacingWorldView.swift"
            ),
            encoding: .utf8
        )
        let worldBody = try XCTUnwrap(
            worldSource.range(of: "struct RacingWorldView: View")
        )
        let overlay = try XCTUnwrap(
            worldSource.range(of: "private struct RacingWeatherOverlay: View")
        )
        let productionWiring = String(worldSource[worldBody.lowerBound..<overlay.lowerBound])

        XCTAssertTrue(rootSource.contains("accessibilityPolicy: sceneAccessibilityPolicy"))
        XCTAssertEqual(
            productionWiring.components(
                separatedBy: "RacingEnvironmentWeather.presentationState("
            ).count - 1,
            1
        )
        XCTAssertTrue(productionWiring.contains("RacingWeatherOverlay(\n                state: weatherState"))
        XCTAssertTrue(productionWiring.contains("weatherState: weatherState"))
        XCTAssertFalse(worldSource.contains("RacingWeatherOverlay(\n                weather:"))
    }

    private func assertStableScene(
        _ before: RacingEnvironmentSceneSnapshot,
        _ after: RacingEnvironmentSceneSnapshot,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(after.entityCount, before.entityCount, file: file, line: line)
        XCTAssertEqual(after.materialCount, before.materialCount, file: file, line: line)
        XCTAssertEqual(
            after.modelMaterialAssignmentCount,
            before.modelMaterialAssignmentCount,
            file: file,
            line: line
        )
        XCTAssertEqual(after.contactShadowCount, before.contactShadowCount, file: file, line: line)
        XCTAssertEqual(after.propSlotIdentities, before.propSlotIdentities, file: file, line: line)
        XCTAssertEqual(after.renderPartIdentities, before.renderPartIdentities, file: file, line: line)
        XCTAssertEqual(
            after.weatherEffectEntityIdentities,
            before.weatherEffectEntityIdentities,
            file: file,
            line: line
        )
        XCTAssertEqual(after.collisionComponentCount, 0, file: file, line: line)
        XCTAssertEqual(after.inputTargetComponentCount, 0, file: file, line: line)
    }

    private func roughness(of entity: Entity) throws -> Float {
        let material = try XCTUnwrap(
            entity.components[ModelComponent.self]?.materials.first
                as? PhysicallyBasedMaterial
        )
        return material.roughness.scale
    }

    private func makeState(
        track: RacingTrack,
        weather: RacingWeather,
        travel: Double = 123.45,
        tier: RacingEnvironmentQualityTier = .baseline,
        reduceMotion: Bool = false,
        reduceTransparency: Bool = false
    ) -> WeatherPresentationState {
        RacingEnvironmentWeather.presentationState(
            track: track,
            weather: weather,
            travel: travel,
            tier: tier,
            accessibilityPolicy: SensoryAccessibilityPolicy(
                settings: .defaultValue,
                reduceMotion: reduceMotion,
                reduceTransparency: reduceTransparency
            )
        )
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
