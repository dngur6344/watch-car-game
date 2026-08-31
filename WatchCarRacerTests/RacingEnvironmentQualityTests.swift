import Foundation
import RealityKit
import XCTest
@testable import WatchCarRacer

@MainActor
final class RacingEnvironmentQualityTests: XCTestCase {
    func testGameLoopRequestsExact60HzWhenSupportedWithoutExceedingDisplayCapability() {
        let sixtyHertz = GameLoopDriver.preferredFrameRateRange(maximumFramesPerSecond: 60)
        XCTAssertEqual(sixtyHertz.minimum, 60)
        XCTAssertEqual(sixtyHertz.maximum, 60)
        XCTAssertEqual(sixtyHertz.preferred, 60)

        let promotion = GameLoopDriver.preferredFrameRateRange(maximumFramesPerSecond: 120)
        XCTAssertEqual(promotion.minimum, 60)
        XCTAssertEqual(promotion.maximum, 60)
        XCTAssertEqual(promotion.preferred, 60)

        let lowerRateDisplay = GameLoopDriver.preferredFrameRateRange(
            maximumFramesPerSecond: 30
        )
        XCTAssertEqual(lowerRateDisplay.minimum, 30)
        XCTAssertEqual(lowerRateDisplay.maximum, 30)
        XCTAssertEqual(lowerRateDisplay.preferred, 30)
    }

    private let fourGiB: UInt64 = 4 * 1_024 * 1_024 * 1_024
    private let sixGiB: UInt64 = 6 * 1_024 * 1_024 * 1_024
    private let eightGiB: UInt64 = 8 * 1_024 * 1_024 * 1_024

    func testAutomaticSelectorUsesMemoryPowerThermalAndExecutionEnvironmentTable() {
        for memory in [fourGiB, sixGiB] {
            XCTAssertEqual(automaticTier(memory: memory), .baseline)
        }
        XCTAssertEqual(automaticTier(memory: eightGiB, thermal: .nominal), .enhanced)
        XCTAssertEqual(automaticTier(memory: eightGiB, thermal: .fair), .enhanced)
        XCTAssertEqual(
            automaticTier(memory: eightGiB, lowPowerMode: true, thermal: .nominal),
            .baseline
        )

        for thermalState in RacingEnvironmentThermalState.allCases {
            let expected: RacingEnvironmentQualityTier = switch thermalState {
            case .nominal, .fair: .enhanced
            case .serious, .critical, .unknown: .baseline
            }
            XCTAssertEqual(
                automaticTier(memory: eightGiB, thermal: thermalState),
                expected,
                "thermal=\(thermalState)"
            )
        }

        for environment in [
            RacingEnvironmentExecutionEnvironment.simulator,
            .unknown,
        ] {
            XCTAssertEqual(
                automaticTier(
                    memory: eightGiB,
                    thermal: .nominal,
                    environment: environment
                ),
                .baseline
            )
        }
    }

    func testDebugForceReleaseAndInvalidArgumentContracts() {
        let prefix = RacingEnvironmentInitialQualitySelector.forceArgumentPrefix
        let restrictedInput = qualityInput(
            memory: fourGiB,
            lowPowerMode: true,
            thermal: .critical,
            environment: .simulator,
            configuration: .debug,
            arguments: ["\(prefix)enhanced"]
        )
        XCTAssertEqual(RacingEnvironmentInitialQualitySelector.tier(for: restrictedInput), .enhanced)

        let capableInput = qualityInput(
            memory: eightGiB,
            thermal: .nominal,
            configuration: .debug,
            arguments: ["\(prefix)baseline"]
        )
        XCTAssertEqual(RacingEnvironmentInitialQualitySelector.tier(for: capableInput), .baseline)

        let releaseInput = qualityInput(
            memory: fourGiB,
            thermal: .critical,
            environment: .simulator,
            configuration: .release,
            arguments: ["\(prefix)enhanced"]
        )
        XCTAssertEqual(RacingEnvironmentInitialQualitySelector.tier(for: releaseInput), .baseline)

        let invalidInput = qualityInput(
            memory: eightGiB,
            thermal: .nominal,
            configuration: .debug,
            arguments: ["\(prefix)ultra"]
        )
        XCTAssertEqual(RacingEnvironmentInitialQualitySelector.tier(for: invalidInput), .enhanced)
        XCTAssertEqual(RacingEnvironmentQualityProductionAdapter.initialTier(), .baseline)
    }

    func testAdaptiveWarmUpCadenceThresholdRecoveryAndExactTransitionEvidence() {
        var state = RacingEnvironmentAdaptiveQualityState(initialTier: .enhanced)
        state.beginRacing(at: 10)

        XCTAssertNil(state.receiveFrameRateSample(49, at: 14.99))
        XCTAssertEqual(state.acceptedFrameRateSampleCount, 0)
        XCTAssertNil(state.receiveFrameRateSample(49, at: 15))
        XCTAssertEqual(state.acceptedFrameRateSampleCount, 1)
        XCTAssertEqual(state.consecutiveLowFrameRateSampleCount, 1)
        XCTAssertNil(state.receiveFrameRateSample(49, at: 15.99))
        XCTAssertEqual(state.acceptedFrameRateSampleCount, 1)

        XCTAssertNil(state.receiveFrameRateSample(50, at: 16))
        XCTAssertEqual(state.consecutiveLowFrameRateSampleCount, 0)
        XCTAssertNil(state.receiveFrameRateSample(49, at: 17))
        XCTAssertNil(state.receiveFrameRateSample(51, at: 18))
        XCTAssertEqual(state.consecutiveLowFrameRateSampleCount, 0)
        XCTAssertNil(state.receiveFrameRateSample(49, at: 19))
        XCTAssertNil(state.receiveFrameRateSample(49, at: 20))
        let transition = state.receiveFrameRateSample(49, at: 21)

        XCTAssertEqual(
            transition,
            RacingEnvironmentQualityTransition(
                fromTier: .enhanced,
                toTier: .baseline,
                reason: .sustainedLowFrameRate,
                acceptedFrameRateSampleCount: 7,
                consecutiveLowFrameRateSampleCount: 3,
                lastAcceptedAverageFramesPerSecond: 49,
                timestamp: 21
            )
        )
        XCTAssertEqual(state.effectiveTier, .baseline)
    }

    func testAdaptiveImmediateSignalsBaselineStabilityAndInvalidInputs() {
        var thermal = RacingEnvironmentAdaptiveQualityState(initialTier: .enhanced)
        thermal.beginRacing(at: 100)
        XCTAssertNil(thermal.receiveThermalState(.nominal, at: 100.1))
        XCTAssertNil(thermal.receiveThermalState(.fair, at: 100.2))
        let serious = thermal.receiveThermalState(.serious, at: 100.3)
        XCTAssertEqual(serious?.reason, .thermalSerious)
        XCTAssertEqual(serious?.acceptedFrameRateSampleCount, 0)
        XCTAssertEqual(serious?.consecutiveLowFrameRateSampleCount, 0)

        var critical = RacingEnvironmentAdaptiveQualityState(initialTier: .enhanced)
        XCTAssertEqual(
            critical.receiveThermalState(.critical, at: 0.25)?.reason,
            .thermalCritical
        )

        var memory = RacingEnvironmentAdaptiveQualityState(initialTier: .enhanced)
        memory.beginRacing(at: 8)
        XCTAssertEqual(memory.receiveMemoryWarning(at: 8.1)?.reason, .memoryWarning)

        var invalid = RacingEnvironmentAdaptiveQualityState(initialTier: .enhanced)
        invalid.beginRacing(at: 0)
        for (fps, timestamp) in [
            (Double.nan, 5.0),
            (Double.infinity, 5.0),
            (0.0, 5.0),
            (-1.0, 5.0),
            (49.0, Double.nan),
            (49.0, Double.infinity),
        ] {
            XCTAssertNil(invalid.receiveFrameRateSample(fps, at: timestamp))
        }
        XCTAssertNil(invalid.receiveFrameRateSample(49, at: 5))
        XCTAssertNil(invalid.receiveFrameRateSample(49, at: 5))
        XCTAssertNil(invalid.receiveFrameRateSample(49, at: 4))
        XCTAssertNil(invalid.receiveThermalState(.serious, at: .nan))
        XCTAssertNil(invalid.receiveMemoryWarning(at: 4))
        XCTAssertEqual(invalid.effectiveTier, .enhanced)
        XCTAssertEqual(invalid.acceptedFrameRateSampleCount, 1)

        var baseline = RacingEnvironmentAdaptiveQualityState(initialTier: .baseline)
        baseline.beginRacing(at: 0)
        XCTAssertNil(baseline.receiveFrameRateSample(1, at: 5))
        XCTAssertNil(baseline.receiveThermalState(.critical, at: 6))
        XCTAssertNil(baseline.receiveMemoryWarning(at: 7))
        XCTAssertEqual(baseline.effectiveTier, .baseline)
        XCTAssertNil(baseline.transition)
    }

    func testAdaptiveStateIsOneWayWithinRunAndResetStartsANewRun() {
        var state = RacingEnvironmentAdaptiveQualityState(initialTier: .enhanced)
        state.beginRacing(at: 0)
        XCTAssertEqual(state.receiveMemoryWarning(at: 1)?.reason, .memoryWarning)
        XCTAssertNil(state.receiveFrameRateSample(60, at: 6))
        XCTAssertNil(state.receiveThermalState(.critical, at: 7))
        XCTAssertNil(state.receiveMemoryWarning(at: 8))
        XCTAssertEqual(state.effectiveTier, .baseline)

        state.reset(initialTier: .enhanced)
        XCTAssertEqual(state.initialTier, .enhanced)
        XCTAssertEqual(state.effectiveTier, .enhanced)
        XCTAssertNil(state.racingStartedAt)
        XCTAssertNil(state.transition)
        XCTAssertEqual(state.acceptedFrameRateSampleCount, 0)
        XCTAssertEqual(state.consecutiveLowFrameRateSampleCount, 0)
        XCTAssertNil(state.lastAcceptedAverageFramesPerSecond)
    }

    func testGameSessionProductionHandoffNotificationLifecycleAndNewRunReset() async {
        let center = NotificationCenter()
        let controller = GameSessionController(
            seed: 88,
            currentTime: { 100 },
            countdownSleeper: {},
            initialEnvironmentQualityTier: { .enhanced },
            adaptiveQualityNotificationCenter: center
        )
        await waitUntil { controller.presentationPhase == .racing }

        XCTAssertEqual(controller.environmentQualityTier, .enhanced)
        XCTAssertEqual(controller.adaptiveQualityObserverCount, 2)
        controller.receiveEnvironmentFrameRateSample(49, at: 104.99)
        XCTAssertEqual(controller.environmentQualityTier, .enhanced)
        controller.receiveEnvironmentFrameRateSample(49, at: 105)
        controller.receiveEnvironmentFrameRateSample(49, at: 106)
        controller.receiveEnvironmentFrameRateSample(49, at: 107)
        XCTAssertEqual(controller.environmentQualityTier, .baseline)
        XCTAssertEqual(controller.adaptiveEnvironmentQualityState.transition?.reason, .sustainedLowFrameRate)

        let firstRunID = controller.environmentQualityRunID
        controller.retry()
        XCTAssertEqual(controller.environmentQualityTier, .enhanced)
        XCTAssertEqual(controller.environmentQualityRunID, firstRunID + 1)
        await waitUntil { controller.presentationPhase == .racing }
        center.post(name: UIApplication.didReceiveMemoryWarningNotification, object: nil)
        XCTAssertEqual(controller.environmentQualityTier, .baseline)
        XCTAssertEqual(controller.adaptiveEnvironmentQualityState.transition?.reason, .memoryWarning)

        controller.stop()
        XCTAssertEqual(controller.adaptiveQualityObserverCount, 0)
    }

#if DEBUG
    func testRacingEnvironmentAcceptanceArgumentsAreExplicitAndFailClosed() throws {
        let arguments = [
            "--sg8-racing-environment",
            "--sg8-track", "desert",
            "--sg8-weather", "storm",
            "--sg8-tier", "enhanced",
            "--sg8-vehicle", "gt",
            "--sg8-duration", "300",
            "--sg8-route-cycles", "10",
            "--sg8-trigger-memory-warning",
            "--sg8-enforce-performance",
            "--sg8-require-racing-screenshot",
        ]
        let configuration = try XCTUnwrap(
            SG8RacingEnvironmentLaunchConfiguration(arguments: arguments)
        )
        XCTAssertEqual(configuration.track, .desert)
        XCTAssertEqual(configuration.weather, .storm)
        XCTAssertEqual(configuration.tier, .enhanced)
        XCTAssertEqual(configuration.vehicle, .gt)
        XCTAssertEqual(configuration.duration, 300)
        XCTAssertEqual(configuration.routeCycles, 10)
        XCTAssertTrue(configuration.triggersMemoryWarning)
        XCTAssertTrue(configuration.enforcesPerformance)
        XCTAssertTrue(configuration.requiresRacingScreenshot)

        func replacingValue(after flag: String, with value: String) -> [String] {
            var result = arguments
            let index = result.firstIndex(of: flag)!
            result[index + 1] = value
            return result
        }

        for invalidArguments in [
            Array(arguments.prefix(10)),
            replacingValue(after: "--sg8-duration", with: "4.99"),
            replacingValue(after: "--sg8-duration", with: "nan"),
            replacingValue(after: "--sg8-route-cycles", with: "11"),
            replacingValue(after: "--sg8-track", with: "unknown"),
            replacingValue(after: "--sg8-vehicle", with: "unknown"),
        ] {
            XCTAssertNil(
                SG8RacingEnvironmentLaunchConfiguration(arguments: invalidArguments)
            )
        }
    }
#endif

    func testSceneDowngradeIsAtomicUsesBaselineDensityAndKeepsOneTrackCache() async throws {
        let library = RacingEnvironmentAssetLibrary()
        let resources = await library.resources(for: .desert, tier: .enhanced)
        let enhancedWeather = RacingEnvironmentWeather.presentationState(
            track: .desert,
            weather: .storm,
            travel: 40,
            tier: .enhanced,
            accessibilityPolicy: RacingEnvironmentWeather.standardAccessibilityPolicy()
        )
        let assembly = try RacingEnvironmentScene.assemble(
            resources: resources,
            travel: 40,
            weatherState: enhancedWeather
        )
        let world = Entity()
        world.addChild(assembly.root)
        let before = try RacingEnvironmentScene.snapshot(of: assembly.root)
        let baselineWeather = RacingEnvironmentWeather.presentationState(
            track: .desert,
            weather: .storm,
            travel: 40,
            tier: .baseline,
            accessibilityPolicy: RacingEnvironmentWeather.standardAccessibilityPolicy()
        )

        XCTAssertTrue(
            RacingEnvironmentScene.applyQualityTier(
                .baseline,
                in: world,
                travel: 40,
                weatherState: baselineWeather
            )
        )
        let after = try RacingEnvironmentScene.snapshot(of: assembly.root)
        let baselineDensity = RacingEnvironmentCatalog.profile(for: .desert)
            .qualityBudgets.baseline.clusterDensity
        let expectedActiveSlots = RacingEnvironmentDistanceLayer.allCases.reduce(0) {
            $0 + baselineDensity.clusterCount(for: $1)
        }

        XCTAssertEqual(before.tier, .enhanced)
        XCTAssertEqual(after.tier, .baseline)
        XCTAssertEqual(after.hierarchyNames, before.hierarchyNames)
        XCTAssertEqual(after.entityCount, before.entityCount)
        XCTAssertEqual(after.materialCount, before.materialCount)
        XCTAssertEqual(after.modelMaterialAssignmentCount, before.modelMaterialAssignmentCount)
        XCTAssertEqual(after.propSlotIdentities, before.propSlotIdentities)
        XCTAssertEqual(after.renderPartIdentities, before.renderPartIdentities)
        XCTAssertEqual(after.preallocatedPropSlotCount, before.preallocatedPropSlotCount)
        XCTAssertEqual(after.activePropSlotCount, expectedActiveSlots)
        XCTAssertEqual(after.activeContactShadowCount, baselineDensity.foreground)
        XCTAssertEqual(after.detailedLODSlotCount, 0)
        XCTAssertEqual(after.weatherState.tier, .baseline)
        XCTAssertLessThan(after.activeWeatherParticleCount, before.activeWeatherParticleCount)
        XCTAssertLessThanOrEqual(
            after.activeWeatherParticleCount,
            RacingEnvironmentCatalog.profile(for: .desert)
                .qualityBudgets.baseline.maximumWeatherParticleCount
        )
        XCTAssertEqual(after.collisionComponentCount, 0)
        XCTAssertEqual(after.inputTargetComponentCount, 0)
        XCTAssertFalse(
            RacingEnvironmentScene.applyQualityTier(
                .enhanced,
                in: world,
                travel: 41,
                weatherState: enhancedWeather
            )
        )
        XCTAssertEqual(try RacingEnvironmentScene.snapshot(of: assembly.root).tier, .baseline)

        let diagnostics = await library.diagnostics()
        XCTAssertEqual(diagnostics.cachedTrackCount, 1)
        XCTAssertEqual(diagnostics.cachedTrack, .desert)
    }

    func testManifestMappingsDefineEveryTrackTierAndExactTextureLoadContract() {
        let expected: [RacingTrack: (String, String, String)] = [
            .coastal: (
                "ocean",
                "ocean_environment_base.usdz",
                "ocean_environment_enhanced.usdz"
            ),
            .alpine: (
                "alpine",
                "alpine_environment_base.usdz",
                "alpine_environment_enhanced.usdz"
            ),
            .desert: (
                "desert",
                "desert_environment_base.usdz",
                "desert_environment_enhanced.usdz"
            ),
        ]

        for track in RacingTrack.allCases {
            let mapping = RacingEnvironmentAssetContract.mapping(for: track)
            let expectedMapping = expected[track]!
            XCTAssertEqual(mapping.track, track)
            XCTAssertEqual(mapping.assetSlug, expectedMapping.0)
            XCTAssertEqual(mapping.base.filename, expectedMapping.1)
            XCTAssertEqual(mapping.enhanced.filename, expectedMapping.2)
            XCTAssertEqual(mapping.textures.map(\.semantic), [.color, .normal, .scalar])
            XCTAssertEqual(
                mapping.textures.map(\.mipmapPolicy),
                [.allocateAndGenerateAll, .allocateAndGenerateAll, .allocateAndGenerateAll]
            )
            XCTAssertEqual(
                mapping.textures.map(\.channelRole),
                ["baseColor", "tangentSpaceNormal", "roughnessScalarReplicatedRGBA"]
            )
            XCTAssertEqual(
                mapping.textures.map(\.colorEncoding),
                ["sRGB", "linear-sRGB", "linear-sRGB"]
            )
        }
    }

    func testForcedBaselineAndEnhancedLoadsForEveryBundledTrack() async {
        let library = RacingEnvironmentAssetLibrary()

        for track in RacingTrack.allCases {
            let baseline = await library.resources(for: track, tier: forcedTier(.baseline))
            assertAuthored(baseline, track: track, tier: .baseline)

            let enhanced = await library.resources(for: track, tier: forcedTier(.enhanced))
            assertAuthored(enhanced, track: track, tier: .enhanced)

            let diagnostics = await library.diagnostics()
            XCTAssertLessThanOrEqual(diagnostics.cachedTrackCount, 1)
            XCTAssertEqual(diagnostics.cachedTrack, track)
        }

        let diagnostics = await library.diagnostics()
        XCTAssertEqual(diagnostics.decodeOperationCount, RacingTrack.allCases.count * 2)
        for track in RacingTrack.allCases {
            let mapping = RacingEnvironmentAssetContract.mapping(for: track)
            for filename in [mapping.base.filename, mapping.enhanced.filename]
                + mapping.textures.map(\.filename) {
                XCTAssertEqual(diagnostics.decodedAssetCounts[filename], 1, filename)
            }
        }
    }

    func testInvalidManifestAndMissingAssetReturnSafeFallbacks() async throws {
        let invalidManifestLibrary = RacingEnvironmentAssetLibrary(
            source: RacingEnvironmentAssetSource(
                manifestData: { Data("{}".utf8) },
                resourceURL: { _ in nil }
            )
        )
        let invalidManifest = await invalidManifestLibrary.resources(
            for: .coastal,
            tier: .enhanced
        )
        assertFallback(invalidManifest, requestedTier: .enhanced)
        XCTAssertEqual(invalidManifest.diagnostic, .fallback(.manifestInvalid))

        let bundle = Bundle.main
        let manifestData = try bundledManifestData(bundle)
        let manifest = try XCTUnwrap(String(data: manifestData, encoding: .utf8))
        for invalidManifest in [
            manifest.replacingOccurrences(
                of: #""realityKitSemantic": ".color""#,
                with: #""realityKitSemantic": ".scalar""#
            ),
            manifest.replacingOccurrences(
                of: #""hashStatus": "verified""#,
                with: #""hashStatus": "pending""#
            ),
        ] {
            let library = RacingEnvironmentAssetLibrary(
                source: RacingEnvironmentAssetSource(
                    manifestData: { Data(invalidManifest.utf8) },
                    resourceURL: { filename in
                        let file = URL(fileURLWithPath: filename)
                        return bundle.url(
                            forResource: file.deletingPathExtension().lastPathComponent,
                            withExtension: file.pathExtension
                        )
                    }
                )
            )
            let resources = await library.resources(for: .coastal, tier: .baseline)
            XCTAssertEqual(resources.diagnostic, .fallback(.manifestInvalid))
        }

        let missingFilename = RacingEnvironmentAssetContract.mapping(for: .alpine).base.filename
        let missingAssetLibrary = RacingEnvironmentAssetLibrary(
            source: RacingEnvironmentAssetSource(
                manifestData: { manifestData },
                resourceURL: { filename in
                    guard filename != missingFilename else { return nil }
                    let file = URL(fileURLWithPath: filename)
                    return bundle.url(
                        forResource: file.deletingPathExtension().lastPathComponent,
                        withExtension: file.pathExtension
                    )
                }
            )
        )
        let missingAsset = await missingAssetLibrary.resources(for: .alpine, tier: .baseline)
        assertFallback(missingAsset, requestedTier: .baseline)
        XCTAssertEqual(missingAsset.diagnostic, .fallback(.assetMissing(missingFilename)))
    }

    func testSimultaneousIdenticalRequestsCoalesceToOneDecodeOperation() async {
        let library = RacingEnvironmentAssetLibrary()
        let diagnostics = await withTaskGroup(
            of: RacingEnvironmentResourceDiagnostic.self,
            returning: [RacingEnvironmentResourceDiagnostic].self
        ) { group in
            for _ in 0..<12 {
                group.addTask {
                    await library.resources(for: .coastal, tier: .baseline).diagnostic
                }
            }
            var values: [RacingEnvironmentResourceDiagnostic] = []
            for await value in group {
                values.append(value)
            }
            return values
        }
        XCTAssertEqual(diagnostics, Array(repeating: .authored, count: 12))

        let cache = await library.diagnostics()
        XCTAssertEqual(cache.decodeOperationCount, 1)
        XCTAssertEqual(cache.cachedTrackCount, 1)
        XCTAssertEqual(cache.cachedTrack, .coastal)
        let mapping = RacingEnvironmentAssetContract.mapping(for: .coastal)
        let expectedDecodedAssets = Set(
            [mapping.base.filename] + mapping.textures.map(\.filename)
        )
        XCTAssertEqual(Set(cache.decodedAssetCounts.keys), expectedDecodedAssets)
        XCTAssertNil(cache.decodedAssetCounts[mapping.enhanced.filename])
        for filename in [mapping.base.filename] + mapping.textures.map(\.filename) {
            XCTAssertEqual(cache.decodedAssetCounts[filename], 1, filename)
        }
    }

    func testTrackSwitchingEvictsToOneTrackAndBaselineAugmentsWithoutBaseReload() async {
        let library = RacingEnvironmentAssetLibrary()

        _ = await library.resources(for: .coastal, tier: .baseline)
        _ = await library.resources(for: .coastal, tier: .enhanced)
        let coastal = RacingEnvironmentAssetContract.mapping(for: .coastal)
        var diagnostics = await library.diagnostics()
        XCTAssertEqual(diagnostics.cachedTrack, .coastal)
        XCTAssertEqual(diagnostics.cachedTrackCount, 1)
        XCTAssertEqual(diagnostics.decodedAssetCounts[coastal.base.filename], 1)
        XCTAssertEqual(diagnostics.decodedAssetCounts[coastal.enhanced.filename], 1)
        for texture in coastal.textures {
            XCTAssertEqual(diagnostics.decodedAssetCounts[texture.filename], 1)
        }

        _ = await library.resources(for: .alpine, tier: .baseline)
        diagnostics = await library.diagnostics()
        XCTAssertEqual(diagnostics.cachedTrack, .alpine)
        XCTAssertLessThanOrEqual(diagnostics.cachedTrackCount, 1)

        _ = await library.resources(for: .desert, tier: .baseline)
        diagnostics = await library.diagnostics()
        XCTAssertEqual(diagnostics.cachedTrack, .desert)
        XCTAssertLessThanOrEqual(diagnostics.cachedTrackCount, 1)
    }

    func testSlowManifestIOYieldsMainActorAndDoesNotDeadlock() async {
        let manifestStarted = expectation(description: "manifest work started")
        let mainActorAdvanced = expectation(description: "main actor advanced")
        let library = RacingEnvironmentAssetLibrary(
            source: RacingEnvironmentAssetSource(
                manifestData: {
                    manifestStarted.fulfill()
                    Thread.sleep(forTimeInterval: 0.25)
                    return Data("{}".utf8)
                },
                resourceURL: { _ in nil }
            )
        )

        let load = Task {
            await library.resources(for: .desert, tier: .baseline)
        }
        await fulfillment(of: [manifestStarted], timeout: 1)
        Task { @MainActor in
            mainActorAdvanced.fulfill()
        }
        await fulfillment(of: [mainActorAdvanced], timeout: 0.1)
        let resources = await load.value
        XCTAssertFalse(resources.diagnostic.isAuthored)
    }

    func testPBXMembershipKeepsImplementationIOSOnlyAndTestsTestOnly() throws {
        let project = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "WatchCarRacer.xcodeproj/project.pbxproj"
            ),
            encoding: .utf8
        )
        let iosSources = try XCTUnwrap(
            projectSection(project, startingWith: "050000000000000000000001 /* Sources */ = {")
        )
        let watchSources = try XCTUnwrap(
            projectSection(project, startingWith: "050000000000000000000011 /* Sources */ = {")
        )
        let testSources = try XCTUnwrap(
            projectSection(project, startingWith: "050000000000000000000021 /* Sources */ = {")
        )

        for filename in [
            "RacingEnvironmentAssetLibrary.swift",
            "RacingEnvironmentQuality.swift",
        ] {
            XCTAssertEqual(
                iosSources.components(separatedBy: "\(filename) in Sources").count - 1,
                1,
                filename
            )
            XCTAssertFalse(watchSources.contains(filename), filename)
            XCTAssertFalse(testSources.contains(filename), filename)
        }
        XCTAssertEqual(
            testSources.components(
                separatedBy: "RacingEnvironmentQualityTests.swift in Sources"
            ).count - 1,
            1
        )
        XCTAssertFalse(iosSources.contains("RacingEnvironmentQualityTests.swift"))
        XCTAssertFalse(watchSources.contains("RacingEnvironmentQualityTests.swift"))
    }

    private func automaticTier(
        memory: UInt64,
        lowPowerMode: Bool = false,
        thermal: RacingEnvironmentThermalState = .nominal,
        environment: RacingEnvironmentExecutionEnvironment = .physicalDevice
    ) -> RacingEnvironmentQualityTier {
        RacingEnvironmentInitialQualitySelector.tier(
            for: qualityInput(
                memory: memory,
                lowPowerMode: lowPowerMode,
                thermal: thermal,
                environment: environment,
                configuration: .release
            )
        )
    }

    private func qualityInput(
        memory: UInt64,
        lowPowerMode: Bool = false,
        thermal: RacingEnvironmentThermalState,
        environment: RacingEnvironmentExecutionEnvironment = .physicalDevice,
        configuration: RacingEnvironmentBuildConfiguration,
        arguments: [String] = []
    ) -> RacingEnvironmentQualityInput {
        RacingEnvironmentQualityInput(
            physicalMemory: memory,
            isLowPowerModeEnabled: lowPowerMode,
            thermalState: thermal,
            executionEnvironment: environment,
            buildConfiguration: configuration,
            launchArguments: arguments
        )
    }

    private func forcedTier(
        _ tier: RacingEnvironmentQualityTier
    ) -> RacingEnvironmentQualityTier {
        RacingEnvironmentInitialQualitySelector.tier(
            for: qualityInput(
                memory: fourGiB,
                lowPowerMode: true,
                thermal: .critical,
                environment: .simulator,
                configuration: .debug,
                arguments: [
                    "\(RacingEnvironmentInitialQualitySelector.forceArgumentPrefix)\(tier.rawValue)"
                ]
            )
        )
    }

    private func assertAuthored(
        _ resources: RacingEnvironmentResources,
        track: RacingTrack,
        tier: RacingEnvironmentQualityTier,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let mapping = RacingEnvironmentAssetContract.mapping(for: track)
        XCTAssertEqual(resources.track, track, file: file, line: line)
        XCTAssertEqual(resources.requestedTier, tier, file: file, line: line)
        XCTAssertEqual(resources.effectiveTier, tier, file: file, line: line)
        XCTAssertEqual(resources.diagnostic, .authored, file: file, line: line)
        XCTAssertNotNil(
            resources.baseEntity.findEntity(named: mapping.base.rootName),
            file: file,
            line: line
        )
        if tier == .enhanced {
            XCTAssertNotNil(
                resources.enhancedEntity?.findEntity(named: mapping.enhanced.rootName),
                file: file,
                line: line
            )
        } else {
            XCTAssertNil(resources.enhancedEntity, file: file, line: line)
        }
        XCTAssertNotNil(resources.baseColorTexture, file: file, line: line)
        XCTAssertNotNil(resources.normalTexture, file: file, line: line)
        XCTAssertNotNil(resources.roughnessTexture, file: file, line: line)
    }

    private func assertFallback(
        _ resources: RacingEnvironmentResources,
        requestedTier: RacingEnvironmentQualityTier,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(resources.requestedTier, requestedTier, file: file, line: line)
        XCTAssertEqual(resources.effectiveTier, .baseline, file: file, line: line)
        XCTAssertFalse(resources.diagnostic.isAuthored, file: file, line: line)
        XCTAssertTrue(resources.baseEntity.name.hasPrefix("racing.environment.fallback."))
        XCTAssertNil(resources.enhancedEntity, file: file, line: line)
        XCTAssertNil(resources.baseColorTexture, file: file, line: line)
        XCTAssertNil(resources.normalTexture, file: file, line: line)
        XCTAssertNil(resources.roughnessTexture, file: file, line: line)
    }

    private func bundledManifestData(_ bundle: Bundle) throws -> Data {
        let url = try XCTUnwrap(
            bundle.url(forResource: "RacingEnvironmentAssetManifest", withExtension: "json")
        )
        return try Data(contentsOf: url)
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

    private func waitUntil(
        timeout: TimeInterval = 1,
        condition: @escaping @MainActor () -> Bool
    ) async {
        let deadline = ProcessInfo.processInfo.systemUptime + timeout
        while !condition(), ProcessInfo.processInfo.systemUptime < deadline {
            await Task.yield()
        }
        XCTAssertTrue(condition())
    }
}
