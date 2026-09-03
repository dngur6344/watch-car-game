enum RacingEnvironmentDistanceLayer: String, CaseIterable, Sendable {
    case foreground
    case midground
    case far
}

struct RacingEnvironmentLayerContract: Equatable, Sendable {
    let layer: RacingEnvironmentDistanceLayer
    let visibleDistanceRange: ClosedRange<Float>
    let roadsideOffsetRange: ClosedRange<Float>
}

struct RacingEnvironmentVariantContract: Equatable, Sendable {
    let assetName: String
    let footprintRadius: Float
    let scaleRange: ClosedRange<Float>
}

struct RacingEnvironmentHeroContract: Equatable, Sendable {
    let assetName: String
    let layer: RacingEnvironmentDistanceLayer
    let anchorDistance: Float
    let minimumRoadApertureWidth: Float
}

struct RacingEnvironmentRoadClearance: Equatable, Sendable {
    let corridorHalfWidth: Float
    let shoulderSafetyMargin: Float

    var minimumPropEdgeOffset: Float {
        corridorHalfWidth + shoulderSafetyMargin
    }
}

enum RacingEnvironmentQualityTier: String, CaseIterable, Sendable {
    case baseline
    case enhanced
}

struct RacingEnvironmentLayerDensity: Equatable, Sendable {
    let foreground: Int
    let midground: Int
    let far: Int

    func clusterCount(for layer: RacingEnvironmentDistanceLayer) -> Int {
        switch layer {
        case .foreground: foreground
        case .midground: midground
        case .far: far
        }
    }
}

struct RacingEnvironmentStaticQualityBudget: Equatable, Sendable {
    let tier: RacingEnvironmentQualityTier
    let clusterDensity: RacingEnvironmentLayerDensity
    let maximumEntityCount: Int
    let maximumMaterialCount: Int
    let maximumContactShadowCount: Int
    let maximumWeatherParticleCount: Int
}

struct RacingEnvironmentQualityBudgets: Equatable, Sendable {
    let baseline: RacingEnvironmentStaticQualityBudget
    let enhanced: RacingEnvironmentStaticQualityBudget

    func budget(for tier: RacingEnvironmentQualityTier) -> RacingEnvironmentStaticQualityBudget {
        switch tier {
        case .baseline: baseline
        case .enhanced: enhanced
        }
    }
}

struct RacingEnvironmentProfile: Equatable, Sendable {
    let track: RacingTrack
    let stableSeed: UInt64
    let layers: [RacingEnvironmentLayerContract]
    let variants: [RacingEnvironmentVariantContract]
    let hero: RacingEnvironmentHeroContract
    let roadClearance: RacingEnvironmentRoadClearance
    let qualityBudgets: RacingEnvironmentQualityBudgets

    func layerContract(
        for layer: RacingEnvironmentDistanceLayer
    ) -> RacingEnvironmentLayerContract? {
        layers.first { $0.layer == layer }
    }

    func eligibleVariantIndices(
        for layer: RacingEnvironmentDistanceLayer
    ) -> [Int] {
        switch layer {
        case .foreground:
            variants.indices.filter { variants[$0].footprintRadius <= 2.5 }
        case .midground, .far:
            Array(variants.indices)
        }
    }
}

enum RacingEnvironmentCatalog {
    private static let layers = [
        RacingEnvironmentLayerContract(
            layer: .foreground,
            visibleDistanceRange: 0...55,
            roadsideOffsetRange: 0...8
        ),
        RacingEnvironmentLayerContract(
            layer: .midground,
            visibleDistanceRange: 45...130,
            roadsideOffsetRange: 10...28
        ),
        RacingEnvironmentLayerContract(
            layer: .far,
            visibleDistanceRange: 110...240,
            roadsideOffsetRange: 28...55
        ),
    ]

    private static let roadClearance = RacingEnvironmentRoadClearance(
        corridorHalfWidth: 4.35,
        shoulderSafetyMargin: 2.65
    )

    private static let qualityBudgets = RacingEnvironmentQualityBudgets(
        baseline: RacingEnvironmentStaticQualityBudget(
            tier: .baseline,
            clusterDensity: RacingEnvironmentLayerDensity(
                foreground: 2,
                midground: 1,
                far: 1
            ),
            maximumEntityCount: 180,
            maximumMaterialCount: 12,
            maximumContactShadowCount: 12,
            maximumWeatherParticleCount: 80
        ),
        enhanced: RacingEnvironmentStaticQualityBudget(
            tier: .enhanced,
            clusterDensity: RacingEnvironmentLayerDensity(
                foreground: 3,
                midground: 2,
                far: 2
            ),
            maximumEntityCount: 280,
            maximumMaterialCount: 16,
            maximumContactShadowCount: 20,
            maximumWeatherParticleCount: 140
        )
    )

    static var allProfiles: [RacingEnvironmentProfile] {
        RacingTrack.allCases.map(profile(for:))
    }

    static func profile(for track: RacingTrack) -> RacingEnvironmentProfile {
        switch track {
        case .coastal:
            RacingEnvironmentProfile(
                track: track,
                stableSeed: 0x4F43_4541_4E44_5256,
                layers: layers,
                variants: [
                    RacingEnvironmentVariantContract(
                        assetName: "Coastal_ShorelineRock",
                        footprintRadius: 1.4,
                        scaleRange: 0.82...1.18
                    ),
                    RacingEnvironmentVariantContract(
                        assetName: "Coastal_PalmGrove",
                        footprintRadius: 2.1,
                        scaleRange: 0.88...1.16
                    ),
                    RacingEnvironmentVariantContract(
                        assetName: "Coastal_CliffOutcrop",
                        footprintRadius: 3.8,
                        scaleRange: 0.86...1.22
                    ),
                    RacingEnvironmentVariantContract(
                        assetName: "Coastal_SeaStack",
                        footprintRadius: 3.2,
                        scaleRange: 0.90...1.24
                    ),
                ],
                hero: RacingEnvironmentHeroContract(
                    assetName: "Coastal_CliffCove_Hero",
                    layer: .far,
                    anchorDistance: 210,
                    minimumRoadApertureWidth: 14
                ),
                roadClearance: roadClearance,
                qualityBudgets: qualityBudgets
            )
        case .alpine:
            RacingEnvironmentProfile(
                track: track,
                stableSeed: 0x414C_5049_4E45_5053,
                layers: layers,
                variants: [
                    RacingEnvironmentVariantContract(
                        assetName: "Alpine_RockOutcrop",
                        footprintRadius: 1.8,
                        scaleRange: 0.84...1.20
                    ),
                    RacingEnvironmentVariantContract(
                        assetName: "Alpine_PineGrove",
                        footprintRadius: 2.4,
                        scaleRange: 0.88...1.18
                    ),
                    RacingEnvironmentVariantContract(
                        assetName: "Alpine_ForestBelt",
                        footprintRadius: 4.2,
                        scaleRange: 0.90...1.16
                    ),
                    RacingEnvironmentVariantContract(
                        assetName: "Alpine_SnowRidge",
                        footprintRadius: 4.8,
                        scaleRange: 0.92...1.22
                    ),
                ],
                hero: RacingEnvironmentHeroContract(
                    assetName: "Alpine_TunnelPeak_Hero",
                    layer: .far,
                    anchorDistance: 205,
                    minimumRoadApertureWidth: 14
                ),
                roadClearance: roadClearance,
                qualityBudgets: qualityBudgets
            )
        case .desert:
            RacingEnvironmentProfile(
                track: track,
                stableSeed: 0x4445_5345_5254_4354,
                layers: layers,
                variants: [
                    RacingEnvironmentVariantContract(
                        assetName: "Desert_CactusCluster",
                        footprintRadius: 1.5,
                        scaleRange: 0.84...1.18
                    ),
                    RacingEnvironmentVariantContract(
                        assetName: "Desert_BoulderCluster",
                        footprintRadius: 2.0,
                        scaleRange: 0.82...1.22
                    ),
                    RacingEnvironmentVariantContract(
                        assetName: "Desert_CanyonWall",
                        footprintRadius: 4.4,
                        scaleRange: 0.88...1.20
                    ),
                    RacingEnvironmentVariantContract(
                        assetName: "Desert_Mesa",
                        footprintRadius: 4.8,
                        scaleRange: 0.92...1.24
                    ),
                ],
                hero: RacingEnvironmentHeroContract(
                    assetName: "Desert_StoneArch_Hero",
                    layer: .far,
                    anchorDistance: 215,
                    minimumRoadApertureWidth: 14
                ),
                roadClearance: roadClearance,
                qualityBudgets: qualityBudgets
            )
        }
    }
}
