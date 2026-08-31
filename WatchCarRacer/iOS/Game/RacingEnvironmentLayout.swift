import Foundation

struct TrackTileState: Equatable, Sendable {
    let distance: Float
    let logicalSegmentIndex: Int
}

struct RacingEnvironmentClusterPlacement: Equatable, Sendable {
    let layer: RacingEnvironmentDistanceLayer
    let slotIndex: Int
    let variantIndex: Int
    let variantAssetName: String
    let lateralOffset: Float
    let longitudinalOffset: Float
    let scale: Float
    let yaw: Float
    let tint: Float
    let footprintRadius: Float
}

struct RacingEnvironmentClusterPlan: Equatable, Sendable {
    let track: RacingTrack
    let seed: UInt64
    let logicalSegmentIndex: Int
    let qualityTier: RacingEnvironmentQualityTier
    let placements: [RacingEnvironmentClusterPlacement]
    let checksum: UInt64
}

enum RacingEnvironmentNearLODState: String, Equatable, Sendable {
    case standard
    case detailed
}

struct RacingEnvironmentNearLODContract: Equatable, Sendable {
    let enterDetailedDistance: Float
    let exitDetailedDistance: Float

    func nextState(
        current: RacingEnvironmentNearLODState,
        distance: Float
    ) -> RacingEnvironmentNearLODState {
        let safeDistance = distance.isFinite ? max(distance, 0) : .greatestFiniteMagnitude
        switch current {
        case .standard:
            return safeDistance <= enterDetailedDistance
                ? RacingEnvironmentNearLODState.detailed
                : RacingEnvironmentNearLODState.standard
        case .detailed:
            return safeDistance > exitDetailedDistance
                ? RacingEnvironmentNearLODState.standard
                : RacingEnvironmentNearLODState.detailed
        }
    }

    func detailedBlend(distance: Float) -> Float {
        let safeDistance = distance.isFinite ? max(distance, 0) : .greatestFiniteMagnitude
        let span = max(exitDetailedDistance - enterDetailedDistance, 0.001)
        return min(max((exitDetailedDistance - safeDistance) / span, 0), 1)
    }
}

struct RacingEnvironmentParallaxBandContract: Equatable, Sendable {
    let layer: RacingEnvironmentDistanceLayer
    let bandIndex: Int
    let distanceRange: ClosedRange<Float>
    let travelMultiplier: Float
    let opacityMultiplier: Float
    let edgeFadeDistance: Float
}

struct RacingEnvironmentPropSlotState: Equatable, Sendable {
    let layer: RacingEnvironmentDistanceLayer
    let bandIndex: Int
    let distance: Float
    let logicalSegmentIndex: Int
    let edgeOpacity: Float
}

struct FixedSplitMix64: RandomNumberGenerator, Sendable {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
        return value ^ (value >> 31)
    }

    mutating func nextUnitFloat() -> Float {
        let significand = next() >> 40
        return Float(significand) / Float(1 << 24)
    }

    mutating func nextInt(upperBound: Int) -> Int {
        precondition(upperBound > 0)
        return Int(next() % UInt64(upperBound))
    }
}

enum RacingEnvironmentLayout {
    static let trackTileLength: Float = 12
    static let trackTileCount = 18
    static let minimumTrackTileDistance: Float = -12
    static let sceneSeed: UInt64 = 0x5052_4F50_5F50_4F4F
    static let nearLODContract = RacingEnvironmentNearLODContract(
        enterDetailedDistance: 38,
        exitDetailedDistance: 50
    )
    private static let foregroundParallaxBands = [
        RacingEnvironmentParallaxBandContract(
            layer: .foreground,
            bandIndex: 0,
            distanceRange: 0...55,
            travelMultiplier: 1,
            opacityMultiplier: 1,
            edgeFadeDistance: 5
        ),
    ]
    private static let midgroundParallaxBands = [
        RacingEnvironmentParallaxBandContract(
            layer: .midground,
            bandIndex: 0,
            distanceRange: 45...84,
            travelMultiplier: 0.70,
            opacityMultiplier: 1,
            edgeFadeDistance: 7
        ),
        RacingEnvironmentParallaxBandContract(
            layer: .midground,
            bandIndex: 1,
            distanceRange: 88...130,
            travelMultiplier: 0.48,
            opacityMultiplier: 0.78,
            edgeFadeDistance: 8
        ),
    ]
    private static let farParallaxBands = [
        RacingEnvironmentParallaxBandContract(
            layer: .far,
            bandIndex: 0,
            distanceRange: 110...168,
            travelMultiplier: 0.30,
            opacityMultiplier: 1,
            edgeFadeDistance: 10
        ),
        RacingEnvironmentParallaxBandContract(
            layer: .far,
            bandIndex: 1,
            distanceRange: 174...240,
            travelMultiplier: 0.16,
            opacityMultiplier: 0.72,
            edgeFadeDistance: 12
        ),
    ]

    static func trackTileState(index: Int, travel: Double) -> TrackTileState {
        let safeTravel = travel.isFinite ? max(travel, 0) : 0
        let cycleLength = Double(trackTileLength) * Double(trackTileCount)
        let minimumDistance = Double(minimumTrackTileDistance)
        let completedCycles = floor(safeTravel / cycleLength)
        let normalizedTravel = safeTravel >= cycleLength
            ? safeTravel.truncatingRemainder(dividingBy: cycleLength)
            : safeTravel
        let unwrappedDistance = Double(index - 1) * Double(trackTileLength)
            - normalizedTravel
        let cycle = floor((unwrappedDistance - minimumDistance) / cycleLength)
        let distance = Float(unwrappedDistance - cycle * cycleLength)
        let logicalIndex = Double(index - 1)
            - cycle * Double(trackTileCount)
            + completedCycles * Double(trackTileCount)

        return TrackTileState(
            distance: distance,
            logicalSegmentIndex: clampedInteger(logicalIndex)
        )
    }

    static func clusterPlan(
        track: RacingTrack,
        seed: UInt64,
        logicalSegmentIndex: Int,
        qualityTier: RacingEnvironmentQualityTier = .baseline
    ) -> RacingEnvironmentClusterPlan {
        let profile = RacingEnvironmentCatalog.profile(for: track)
        let budget = profile.qualityBudgets.budget(for: qualityTier)
        var placements: [RacingEnvironmentClusterPlacement] = []

        for layer in RacingEnvironmentDistanceLayer.allCases {
            let clusterCount = budget.clusterDensity.clusterCount(for: layer)
            for clusterIndex in 0..<clusterCount {
                guard let placement = clusterPlacement(
                    track: track,
                    seed: seed,
                    logicalSegmentIndex: logicalSegmentIndex,
                    qualityTier: qualityTier,
                    layer: layer,
                    slotIndex: clusterIndex
                ) else { continue }
                placements.append(placement)
            }
        }

        let checksum = stableChecksum(
            profile: profile,
            seed: seed,
            logicalSegmentIndex: logicalSegmentIndex,
            qualityTier: qualityTier,
            placements: placements
        )
        return RacingEnvironmentClusterPlan(
            track: track,
            seed: seed,
            logicalSegmentIndex: logicalSegmentIndex,
            qualityTier: qualityTier,
            placements: placements,
            checksum: checksum
        )
    }

    static func clusterPlacement(
        track: RacingTrack,
        seed: UInt64,
        logicalSegmentIndex: Int,
        qualityTier: RacingEnvironmentQualityTier,
        layer: RacingEnvironmentDistanceLayer,
        slotIndex: Int,
        roleSalt: UInt64 = 0
    ) -> RacingEnvironmentClusterPlacement? {
        let profile = RacingEnvironmentCatalog.profile(for: track)
        return clusterPlacement(
            profile: profile,
            seed: seed,
            logicalSegmentIndex: logicalSegmentIndex,
            qualityTier: qualityTier,
            layer: layer,
            slotIndex: slotIndex,
            roleSalt: roleSalt
        )
    }

    static func clusterPlacement(
        profile: RacingEnvironmentProfile,
        seed: UInt64,
        logicalSegmentIndex: Int,
        qualityTier: RacingEnvironmentQualityTier,
        layer: RacingEnvironmentDistanceLayer,
        slotIndex: Int,
        roleSalt: UInt64 = 0
    ) -> RacingEnvironmentClusterPlacement? {
        let budget = profile.qualityBudgets.budget(for: qualityTier)
        let slotCount = budget.clusterDensity.clusterCount(for: layer)
        guard slotIndex >= 0,
              slotIndex < slotCount,
              let layerContract = profile.layerContract(for: layer),
              !profile.variants.isEmpty else {
            return nil
        }

        let segmentBits = UInt64(
            bitPattern: Int64(truncatingIfNeeded: logicalSegmentIndex)
        )
        let layerIndex = layer.index
        let layerSalt = 0xA24B_AED4_963E_E407 &* UInt64(layerIndex + 1)
        let slotSalt = 0x9FB2_1C65_1E98_DF25 &* UInt64(slotIndex + 1)
        let fixedRoleSalt = layerSalt ^ slotSalt ^ roleSalt
        let variantIndex = stableVariantIndex(
            profile: profile,
            seed: seed,
            segmentBits: segmentBits,
            layerIndex: layerIndex,
            slotIndex: slotIndex,
            roleSalt: fixedRoleSalt
        )
        let variant = profile.variants[variantIndex]
        var generator = FixedSplitMix64(
            seed: mixed(
                profile.stableSeed
                    ^ seed
                    ^ segmentBits &* 0xD6E8_FEB8_6659_FD93
                    ^ fixedRoleSalt
            )
        )
        let scale = randomValue(in: variant.scaleRange, using: &generator)
        let footprintRadius = variant.footprintRadius * scale
        let roadsideOffset = randomValue(
            in: layerContract.roadsideOffsetRange,
            using: &generator
        )
        let side: Float = generator.next() & 1 == 0 ? -1 : 1
        let mirrorBreak = Float(layerIndex * 4 + slotIndex) * 0.021
        let lateralMagnitude = profile.roadClearance.minimumPropEdgeOffset
            + footprintRadius
            + roadsideOffset
            + mirrorBreak

        return RacingEnvironmentClusterPlacement(
            layer: layer,
            slotIndex: slotIndex,
            variantIndex: variantIndex,
            variantAssetName: variant.assetName,
            lateralOffset: side * lateralMagnitude,
            longitudinalOffset: randomValue(
                in: (-trackTileLength / 2)...(trackTileLength / 2),
                using: &generator
            ),
            scale: scale,
            yaw: randomValue(in: 0...(2 * .pi), using: &generator),
            tint: randomValue(in: -0.08...0.08, using: &generator),
            footprintRadius: footprintRadius
        )
    }

    static func parallaxBands(
        for layer: RacingEnvironmentDistanceLayer
    ) -> [RacingEnvironmentParallaxBandContract] {
        switch layer {
        case .foreground:
            foregroundParallaxBands
        case .midground:
            midgroundParallaxBands
        case .far:
            farParallaxBands
        }
    }

    static func propSlotState(
        layer: RacingEnvironmentDistanceLayer,
        bandIndex: Int,
        slotIndex: Int,
        slotCount: Int,
        travel: Double
    ) -> RacingEnvironmentPropSlotState? {
        guard slotCount > 0,
              slotIndex >= 0,
              slotIndex < slotCount,
              let band = parallaxBand(for: layer, bandIndex: bandIndex) else {
            return nil
        }

        let safeTravel = sanitizedTravel(travel)
        let width = Double(band.distanceRange.upperBound - band.distanceRange.lowerBound)
        let spacing = width / Double(slotCount)
        let initialPhase = (Double(slotIndex) + 0.5) * spacing
        let movingPhase = initialPhase + safeTravel * Double(band.travelMultiplier)
        let cycle = floor(movingPhase / width)
        let wrappedPhase = movingPhase - cycle * width
        let distance = band.distanceRange.upperBound - Float(wrappedPhase)
        let edgeDistance = min(
            distance - band.distanceRange.lowerBound,
            band.distanceRange.upperBound - distance
        )
        let edgeOpacity = min(max(edgeDistance / band.edgeFadeDistance, 0), 1)
        let logicalIndex = cycle * Double(slotCount) + Double(slotIndex)

        return RacingEnvironmentPropSlotState(
            layer: layer,
            bandIndex: bandIndex,
            distance: distance,
            logicalSegmentIndex: clampedInteger(logicalIndex),
            edgeOpacity: edgeOpacity
        )
    }

    private static func parallaxBand(
        for layer: RacingEnvironmentDistanceLayer,
        bandIndex: Int
    ) -> RacingEnvironmentParallaxBandContract? {
        let bands: [RacingEnvironmentParallaxBandContract]
        switch layer {
        case .foreground: bands = foregroundParallaxBands
        case .midground: bands = midgroundParallaxBands
        case .far: bands = farParallaxBands
        }
        guard bands.indices.contains(bandIndex) else { return nil }
        return bands[bandIndex]
    }

    private static func randomValue(
        in range: ClosedRange<Float>,
        using generator: inout FixedSplitMix64
    ) -> Float {
        range.lowerBound + (range.upperBound - range.lowerBound) * generator.nextUnitFloat()
    }

    private static func stableVariantIndex(
        profile: RacingEnvironmentProfile,
        seed: UInt64,
        segmentBits: UInt64,
        layerIndex: Int,
        slotIndex: Int,
        roleSalt: UInt64
    ) -> Int {
        let radix = UInt64(profile.variants.count)
        let seedOffset = mixed(profile.stableSeed ^ seed)
        let ordinal = segmentBits &+ seedOffset
        let digitPosition: Int
        if slotIndex == 0 {
            digitPosition = 0
        } else {
            digitPosition = 1 + layerIndex * 2 + slotIndex - 1
        }
        var digit = radixDigit(ordinal, position: digitPosition, radix: radix)
        if slotIndex == 0, layerIndex > 0 {
            digit &+= radixDigit(ordinal, position: layerIndex + 1, radix: radix)
        }
        let fixedRoleOffset = mixed(
            profile.stableSeed ^ seed ^ roleSalt
        ) % radix
        return Int((digit &+ fixedRoleOffset) % radix)
    }

    private static func radixDigit(
        _ value: UInt64,
        position: Int,
        radix: UInt64
    ) -> UInt64 {
        var divisor: UInt64 = 1
        for _ in 0..<position {
            let (next, overflow) = divisor.multipliedReportingOverflow(by: radix)
            if overflow { return 0 }
            divisor = next
        }
        return value / divisor % radix
    }

    private static func mixed(_ input: UInt64) -> UInt64 {
        var generator = FixedSplitMix64(seed: input)
        return generator.next()
    }

    private static func sanitizedTravel(_ travel: Double) -> Double {
        guard travel.isFinite else { return 0 }
        return min(max(travel, 0), 1_000_000_000)
    }

    private static func clampedInteger(_ value: Double) -> Int {
        if value >= Double(Int.max) {
            return Int.max
        }
        if value <= Double(Int.min) {
            return Int.min
        }
        return Int(value)
    }

    private static func stableChecksum(
        profile: RacingEnvironmentProfile,
        seed: UInt64,
        logicalSegmentIndex: Int,
        qualityTier: RacingEnvironmentQualityTier,
        placements: [RacingEnvironmentClusterPlacement]
    ) -> UInt64 {
        var checksum = StableChecksum64()
        checksum.combine(profile.stableSeed)
        checksum.combine(seed)
        checksum.combine(
            UInt64(bitPattern: Int64(truncatingIfNeeded: logicalSegmentIndex))
        )
        checksum.combine(qualityTier.rawValue)
        checksum.combine(UInt64(placements.count))
        for placement in placements {
            checksum.combine(placement.layer.rawValue)
            checksum.combine(UInt64(placement.slotIndex))
            checksum.combine(UInt64(placement.variantIndex))
            checksum.combine(placement.variantAssetName)
            checksum.combine(UInt64(placement.lateralOffset.bitPattern))
            checksum.combine(UInt64(placement.longitudinalOffset.bitPattern))
            checksum.combine(UInt64(placement.scale.bitPattern))
            checksum.combine(UInt64(placement.yaw.bitPattern))
            checksum.combine(UInt64(placement.tint.bitPattern))
            checksum.combine(UInt64(placement.footprintRadius.bitPattern))
        }
        return checksum.value
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

private struct StableChecksum64 {
    private(set) var value: UInt64 = 0xCBF2_9CE4_8422_2325

    mutating func combine(_ number: UInt64) {
        for shift in stride(from: 0, to: 64, by: 8) {
            combine(byte: UInt8(truncatingIfNeeded: number >> UInt64(shift)))
        }
    }

    mutating func combine(_ string: String) {
        for byte in string.utf8 {
            combine(byte: byte)
        }
        combine(byte: 0)
    }

    private mutating func combine(byte: UInt8) {
        value ^= UInt64(byte)
        value &*= 0x0000_0100_0000_01B3
    }
}
