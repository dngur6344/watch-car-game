import Foundation
import XCTest
@testable import WatchCarRacer

final class RacingEnvironmentLayoutTests: XCTestCase {
    func testCatalogDefinesStableProductionContractsForEveryTrack() {
        XCTAssertEqual(RacingEnvironmentCatalog.allProfiles.count, RacingTrack.allCases.count)

        let expectedSeeds: [UInt64] = [
            0x4F43_4541_4E44_5256,
            0x414C_5049_4E45_5053,
            0x4445_5345_5254_4354,
        ]
        XCTAssertEqual(
            RacingEnvironmentCatalog.allProfiles.map(\.stableSeed),
            expectedSeeds
        )

        for profile in RacingEnvironmentCatalog.allProfiles {
            XCTAssertEqual(profile.layers.map(\.layer), RacingEnvironmentDistanceLayer.allCases)
            XCTAssertEqual(profile.layers[0].visibleDistanceRange, 0...55)
            XCTAssertEqual(profile.layers[1].visibleDistanceRange, 45...130)
            XCTAssertEqual(profile.layers[2].visibleDistanceRange, 110...240)
            XCTAssertGreaterThanOrEqual(profile.variants.count, 2)
            XCTAssertEqual(profile.hero.layer, .far)
            XCTAssertGreaterThanOrEqual(
                profile.hero.minimumRoadApertureWidth,
                profile.roadClearance.minimumPropEdgeOffset * 2
            )

            let baseline = profile.qualityBudgets.baseline
            let enhanced = profile.qualityBudgets.enhanced
            XCTAssertEqual(baseline.tier, .baseline)
            XCTAssertEqual(enhanced.tier, .enhanced)
            XCTAssertGreaterThanOrEqual(
                enhanced.clusterDensity.foreground,
                baseline.clusterDensity.foreground
            )
            XCTAssertGreaterThanOrEqual(enhanced.maximumEntityCount, baseline.maximumEntityCount)
            XCTAssertGreaterThanOrEqual(
                enhanced.maximumContactShadowCount,
                baseline.maximumContactShadowCount
            )
            XCTAssertGreaterThanOrEqual(
                enhanced.maximumWeatherParticleCount,
                baseline.maximumWeatherParticleCount
            )
        }
    }

    func testSameInputsProduceIdenticalPlanAndChecksum() {
        for track in RacingTrack.allCases {
            let first = RacingEnvironmentLayout.clusterPlan(
                track: track,
                seed: 0x1234_5678_9ABC_DEF0,
                logicalSegmentIndex: 42
            )
            let second = RacingEnvironmentLayout.clusterPlan(
                track: track,
                seed: 0x1234_5678_9ABC_DEF0,
                logicalSegmentIndex: 42
            )

            XCTAssertEqual(first, second)
            XCTAssertEqual(first.checksum, second.checksum)
        }
    }

    func testDifferentSeedsProduceDifferentPlansAndChecksums() {
        for track in RacingTrack.allCases {
            let first = RacingEnvironmentLayout.clusterPlan(
                track: track,
                seed: 11,
                logicalSegmentIndex: 42
            )
            let second = RacingEnvironmentLayout.clusterPlan(
                track: track,
                seed: 12,
                logicalSegmentIndex: 42
            )

            XCTAssertNotEqual(first.placements, second.placements)
            XCTAssertNotEqual(first.checksum, second.checksum)
        }
    }

    func testInvalidAndNegativeTravelUseZeroTravelState() {
        for index in 0..<RacingWorldLayout.trackTileCount {
            let zero = RacingWorldLayout.trackTileState(index: index, travel: 0)
            for invalidTravel in [Double.nan, .infinity, -.infinity, -0.01, -500] {
                XCTAssertEqual(
                    RacingWorldLayout.trackTileState(index: index, travel: invalidTravel),
                    zero,
                    "index=\(index), travel=\(invalidTravel)"
                )
            }
        }
    }

    func testGreatestFiniteTravelKeepsFiniteRecycledDistancesAndSpacing() {
        let states = (0..<RacingWorldLayout.trackTileCount).map {
            RacingWorldLayout.trackTileState(
                index: $0,
                travel: Double.greatestFiniteMagnitude
            )
        }

        for (index, state) in states.enumerated() {
            XCTAssertTrue(state.distance.isFinite, "index=\(index)")
            XCTAssertGreaterThanOrEqual(state.distance, -12, "index=\(index)")
            XCTAssertLessThan(state.distance, 204, "index=\(index)")
            XCTAssertEqual(
                RacingWorldLayout.trackTileDistance(
                    index: index,
                    travel: Double.greatestFiniteMagnitude
                ),
                state.distance
            )
        }

        let sortedDistances = states.map(\.distance).sorted()
        for index in 1..<sortedDistances.count {
            XCTAssertEqual(
                sortedDistances[index] - sortedDistances[index - 1],
                RacingWorldLayout.trackTileLength,
                accuracy: 0.001
            )
        }
    }

    func testRecycleAdvancesStableLogicalSegmentIndexByPoolSize() {
        XCTAssertEqual(
            RacingWorldLayout.trackTileState(index: 0, travel: 0),
            TrackTileState(distance: -12, logicalSegmentIndex: -1)
        )
        XCTAssertEqual(
            RacingWorldLayout.trackTileState(index: 0, travel: 0.01).logicalSegmentIndex,
            17
        )
        XCTAssertEqual(
            RacingWorldLayout.trackTileState(index: 1, travel: 11.99).logicalSegmentIndex,
            0
        )
        XCTAssertEqual(
            RacingWorldLayout.trackTileState(index: 1, travel: 12.01).logicalSegmentIndex,
            18
        )

        for index in 0..<RacingWorldLayout.trackTileCount {
            let before = RacingWorldLayout.trackTileState(index: index, travel: 36.5)
            let after = RacingWorldLayout.trackTileState(
                index: index,
                travel: 36.5 + Double(
                    RacingWorldLayout.trackTileLength * Float(RacingWorldLayout.trackTileCount)
                )
            )
            XCTAssertEqual(
                after.logicalSegmentIndex,
                before.logicalSegmentIndex + RacingWorldLayout.trackTileCount
            )
            XCTAssertEqual(after.distance, before.distance, accuracy: 0.000_1)
        }
    }

    func testAdjacentLogicalSegmentsNeverUseAnIdenticalCompletePlan() {
        for track in RacingTrack.allCases {
            for segment in -32..<64 {
                let current = RacingEnvironmentLayout.clusterPlan(
                    track: track,
                    seed: 2026,
                    logicalSegmentIndex: segment
                )
                let next = RacingEnvironmentLayout.clusterPlan(
                    track: track,
                    seed: 2026,
                    logicalSegmentIndex: segment + 1
                )

                XCTAssertNotEqual(current.placements, next.placements)
                XCTAssertNotEqual(current.checksum, next.checksum)
            }
        }
    }

    func testClusterFootprintsStayOutsideRoadCorridor() {
        for profile in RacingEnvironmentCatalog.allProfiles {
            for tier in RacingEnvironmentQualityTier.allCases {
                for segment in -8...32 {
                    let plan = RacingEnvironmentLayout.clusterPlan(
                        track: profile.track,
                        seed: 88,
                        logicalSegmentIndex: segment,
                        qualityTier: tier
                    )
                    for placement in plan.placements {
                        XCTAssertGreaterThanOrEqual(
                            abs(placement.lateralOffset) - placement.footprintRadius,
                            profile.roadClearance.minimumPropEdgeOffset,
                            "\(profile.track) \(tier) segment=\(segment)"
                        )
                    }
                }
            }
        }
    }

    func test256LogicalSegmentsHaveStableCoverageSeedVariationAndNoShortTupleCycle() {
        let firstSeed: UInt64 = 0x1234_5678_9ABC_DEF0
        let secondSeed: UInt64 = 0x0FED_CBA9_8765_4321

        for profile in RacingEnvironmentCatalog.allProfiles {
            for tier in RacingEnvironmentQualityTier.allCases {
                let first = (0..<256).map { segment in
                    RacingEnvironmentLayout.clusterPlan(
                        track: profile.track,
                        seed: firstSeed,
                        logicalSegmentIndex: segment,
                        qualityTier: tier
                    )
                }
                let repeated = (0..<256).map { segment in
                    RacingEnvironmentLayout.clusterPlan(
                        track: profile.track,
                        seed: firstSeed,
                        logicalSegmentIndex: segment,
                        qualityTier: tier
                    )
                }
                let reseeded = (0..<256).map { segment in
                    RacingEnvironmentLayout.clusterPlan(
                        track: profile.track,
                        seed: secondSeed,
                        logicalSegmentIndex: segment,
                        qualityTier: tier
                    )
                }

                XCTAssertEqual(first, repeated, "\(profile.track) \(tier)")
                XCTAssertGreaterThan(
                    zip(first, reseeded).filter { $0 != $1 }.count,
                    240,
                    "\(profile.track) \(tier)"
                )
                let expectedDensity = profile.qualityBudgets
                    .budget(for: tier)
                    .clusterDensity
                let expectedCount = RacingEnvironmentDistanceLayer.allCases.reduce(0) {
                    $0 + expectedDensity.clusterCount(for: $1)
                }
                XCTAssertTrue(first.allSatisfy { $0.placements.count == expectedCount })

                let variantTuples = first.map {
                    $0.placements.map(\.variantAssetName).joined(separator: "|")
                }
                XCTAssertEqual(
                    Set(variantTuples).count,
                    256,
                    "short variant tuple cycle: \(profile.track) \(tier)"
                )
                for layer in RacingEnvironmentDistanceLayer.allCases {
                    let coverage = Set(first.flatMap { plan in
                        plan.placements
                            .filter { $0.layer == layer }
                            .map(\.variantAssetName)
                    })
                    XCTAssertEqual(
                        coverage,
                        Set(profile.variants.map(\.assetName)),
                        "\(profile.track) \(tier) \(layer)"
                    )
                    for segment in 1..<first.count {
                        let previousPrimary = first[segment - 1].placements.first {
                            $0.layer == layer && $0.slotIndex == 0
                        }
                        let currentPrimary = first[segment].placements.first {
                            $0.layer == layer && $0.slotIndex == 0
                        }
                        XCTAssertNotEqual(
                            previousPrimary?.variantAssetName,
                            currentPrimary?.variantAssetName,
                            "\(profile.track) \(tier) \(layer) segment=\(segment)"
                        )
                    }
                }

                for plan in first {
                    for leftIndex in plan.placements.indices {
                        for rightIndex in plan.placements.indices where rightIndex > leftIndex {
                            let left = plan.placements[leftIndex]
                            let right = plan.placements[rightIndex]
                            let isObviousMirror = left.variantAssetName == right.variantAssetName
                                && left.lateralOffset.sign != right.lateralOffset.sign
                                && abs(abs(left.lateralOffset) - abs(right.lateralOffset)) < 0.001
                                && abs(left.longitudinalOffset + right.longitudinalOffset) < 0.001
                            XCTAssertFalse(isObviousMirror, "\(profile.track) \(tier)")
                        }
                    }
                }
            }
        }
    }

    func testExtremeLogicalSegmentsKeepEveryPlacementFiniteAndClear() {
        for profile in RacingEnvironmentCatalog.allProfiles {
            for tier in RacingEnvironmentQualityTier.allCases {
                for segment in [Int.min, Int.min + 1, -1, 0, Int.max - 1, Int.max] {
                    let plan = RacingEnvironmentLayout.clusterPlan(
                        track: profile.track,
                        seed: .max,
                        logicalSegmentIndex: segment,
                        qualityTier: tier
                    )
                    for placement in plan.placements {
                        XCTAssertTrue(placement.lateralOffset.isFinite)
                        XCTAssertTrue(placement.longitudinalOffset.isFinite)
                        XCTAssertTrue(placement.scale.isFinite)
                        XCTAssertTrue(placement.yaw.isFinite)
                        XCTAssertTrue(placement.tint.isFinite)
                        XCTAssertGreaterThanOrEqual(
                            abs(placement.lateralOffset) - placement.footprintRadius,
                            profile.roadClearance.minimumPropEdgeOffset
                        )
                    }
                }
            }
        }
    }

    func testNearLODHysteresisAndBlendTransitionTable() {
        let contract = RacingEnvironmentLayout.nearLODContract
        XCTAssertLessThan(contract.enterDetailedDistance, contract.exitDetailedDistance)

        XCTAssertEqual(contract.nextState(current: .standard, distance: 50), .standard)
        XCTAssertEqual(contract.nextState(current: .standard, distance: 42), .standard)
        XCTAssertEqual(contract.nextState(current: .standard, distance: 38), .detailed)
        XCTAssertEqual(contract.nextState(current: .detailed, distance: 42), .detailed)
        XCTAssertEqual(contract.nextState(current: .detailed, distance: 50), .detailed)
        XCTAssertEqual(contract.nextState(current: .detailed, distance: 50.01), .standard)
        XCTAssertEqual(contract.nextState(current: .detailed, distance: .nan), .standard)

        var state = RacingEnvironmentNearLODState.standard
        for distance: Float in [37.9, 42, 37.8, 43, 49.9] {
            state = contract.nextState(current: state, distance: distance)
            XCTAssertEqual(state, .detailed, "distance=\(distance)")
        }
        XCTAssertEqual(contract.detailedBlend(distance: 38), 1, accuracy: 0.000_1)
        XCTAssertEqual(contract.detailedBlend(distance: 44), 0.5, accuracy: 0.000_1)
        XCTAssertEqual(contract.detailedBlend(distance: 50), 0, accuracy: 0.000_1)
    }

    func testMidAndFarUseOrderedContinuousDoubleBandParallax() throws {
        XCTAssertEqual(RacingEnvironmentLayout.parallaxBands(for: .foreground).count, 1)
        for layer in [
            RacingEnvironmentDistanceLayer.midground,
            RacingEnvironmentDistanceLayer.far,
        ] {
            let contracts = RacingEnvironmentLayout.parallaxBands(for: layer)
            XCTAssertEqual(contracts.count, 2)
            XCTAssertLessThan(
                contracts[0].distanceRange.upperBound,
                contracts[1].distanceRange.lowerBound
            )
            XCTAssertGreaterThan(contracts[0].travelMultiplier, contracts[1].travelMultiplier)

            let innerStart = try XCTUnwrap(
                RacingEnvironmentLayout.propSlotState(
                    layer: layer,
                    bandIndex: 0,
                    slotIndex: 0,
                    slotCount: 1,
                    travel: 0
                )
            )
            let innerMoved = try XCTUnwrap(
                RacingEnvironmentLayout.propSlotState(
                    layer: layer,
                    bandIndex: 0,
                    slotIndex: 0,
                    slotCount: 1,
                    travel: 1
                )
            )
            let outerStart = try XCTUnwrap(
                RacingEnvironmentLayout.propSlotState(
                    layer: layer,
                    bandIndex: 1,
                    slotIndex: 0,
                    slotCount: 1,
                    travel: 0
                )
            )
            let outerMoved = try XCTUnwrap(
                RacingEnvironmentLayout.propSlotState(
                    layer: layer,
                    bandIndex: 1,
                    slotIndex: 0,
                    slotCount: 1,
                    travel: 1
                )
            )
            XCTAssertLessThan(innerStart.distance, outerStart.distance)
            XCTAssertGreaterThan(
                abs(innerMoved.distance - innerStart.distance),
                abs(outerMoved.distance - outerStart.distance)
            )

            for boundary in [11.99, 12.01, 215.99, 216.01] {
                for contract in contracts {
                    let state = try XCTUnwrap(
                        RacingEnvironmentLayout.propSlotState(
                            layer: layer,
                            bandIndex: contract.bandIndex,
                            slotIndex: 0,
                            slotCount: 1,
                            travel: boundary
                        )
                    )
                    XCTAssertTrue(contract.distanceRange.contains(state.distance))
                    XCTAssertTrue(state.distance.isFinite)
                    XCTAssertTrue(state.edgeOpacity.isFinite)
                }
            }
            for contract in contracts {
                let width = Double(
                    contract.distanceRange.upperBound - contract.distanceRange.lowerBound
                )
                let wrapTravel = (width / 2) / Double(contract.travelMultiplier)
                let before = try XCTUnwrap(
                    RacingEnvironmentLayout.propSlotState(
                        layer: layer,
                        bandIndex: contract.bandIndex,
                        slotIndex: 0,
                        slotCount: 1,
                        travel: wrapTravel - 0.001
                    )
                )
                let after = try XCTUnwrap(
                    RacingEnvironmentLayout.propSlotState(
                        layer: layer,
                        bandIndex: contract.bandIndex,
                        slotIndex: 0,
                        slotCount: 1,
                        travel: wrapTravel + 0.001
                    )
                )
                XCTAssertLessThan(before.edgeOpacity, 0.001)
                XCTAssertLessThan(after.edgeOpacity, 0.001)
                XCTAssertEqual(
                    after.logicalSegmentIndex,
                    before.logicalSegmentIndex + 1
                )
            }
        }

        for layer in RacingEnvironmentDistanceLayer.allCases {
            for band in RacingEnvironmentLayout.parallaxBands(for: layer) {
                let extreme = try XCTUnwrap(
                    RacingEnvironmentLayout.propSlotState(
                        layer: layer,
                        bandIndex: band.bandIndex,
                        slotIndex: 0,
                        slotCount: 1,
                        travel: Double.greatestFiniteMagnitude
                    )
                )
                XCTAssertTrue(extreme.distance.isFinite)
                XCTAssertTrue(band.distanceRange.contains(extreme.distance))
            }
        }
    }

    func testTileStateKeepsExactLegacyDistancesAndSpacing() {
        XCTAssertEqual(RacingWorldLayout.trackTileLength, 12)
        XCTAssertEqual(RacingWorldLayout.trackTileCount, 18)

        let expectedAtStart = stride(from: Float(-12), through: 192, by: 12).map { $0 }
        let actualAtStart = (0..<RacingWorldLayout.trackTileCount).map {
            RacingWorldLayout.trackTileState(index: $0, travel: 0).distance
        }
        XCTAssertEqual(actualAtStart, expectedAtStart)
        XCTAssertEqual(
            RacingWorldLayout.trackTileState(index: 0, travel: 0.01).distance,
            203.99,
            accuracy: 0.000_1
        )
        XCTAssertEqual(
            RacingWorldLayout.trackTileState(index: 1, travel: 11.99).distance,
            -11.99,
            accuracy: 0.000_1
        )
        XCTAssertEqual(
            RacingWorldLayout.trackTileState(index: 1, travel: 12.01).distance,
            203.99,
            accuracy: 0.000_1
        )

        for travel in [0.0, 0.01, 11.99, 12.01, 147.25, 216.01] {
            let distances = (0..<RacingWorldLayout.trackTileCount).map {
                RacingWorldLayout.trackTileState(index: $0, travel: travel).distance
            }.sorted()
            for index in 1..<distances.count {
                XCTAssertEqual(distances[index] - distances[index - 1], 12, accuracy: 0.000_1)
            }
            for index in 0..<RacingWorldLayout.trackTileCount {
                XCTAssertEqual(
                    RacingWorldLayout.trackTileDistance(index: index, travel: travel),
                    RacingWorldLayout.trackTileState(index: index, travel: travel).distance
                )
            }
        }
    }

    func testEnvironmentSourcesHaveProductionAndTestTargetMembership() throws {
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
        let testSources = try XCTUnwrap(
            projectSection(project, startingWith: "050000000000000000000021 /* Sources */ = {")
        )

        for filename in [
            "RacingEnvironmentCatalog.swift",
            "RacingEnvironmentLayout.swift",
        ] {
            XCTAssertTrue(gameGroup.contains("/* \(filename) */"), filename)
            XCTAssertTrue(appSources.contains("/* \(filename) in Sources */"), filename)
            XCTAssertFalse(testSources.contains("/* \(filename) in Sources */"), filename)
        }
        XCTAssertTrue(testGroup.contains("/* RacingEnvironmentLayoutTests.swift */"))
        XCTAssertTrue(testSources.contains("/* RacingEnvironmentLayoutTests.swift in Sources */"))
        XCTAssertFalse(appSources.contains("/* RacingEnvironmentLayoutTests.swift in Sources */"))
        XCTAssertFalse(
            try String(
                contentsOf: repositoryRoot.appendingPathComponent(
                    "WatchCarRacer/iOS/Game/RacingEnvironmentLayout.swift"
                ),
                encoding: .utf8
            ).contains("hashValue")
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
