import Foundation

enum RacingEnvironmentStormEffectKind: Equatable, Sendable {
    case spray
    case dust
}

struct RacingEnvironmentLayerVisibilityState: Equatable, Sendable {
    let foreground: Float
    let midground: Float
    let far: Float

    func value(for layer: RacingEnvironmentDistanceLayer) -> Float {
        switch layer {
        case .foreground: foreground
        case .midground: midground
        case .far: far
        }
    }
}

struct RacingWeatherOverlayPresentationState: Equatable, Sendable {
    let darkWashOpacity: Double
    let rainOpacity: Double
    let fogOpacity: Double
    let lightningOpacity: Double
    let rainDropCount: Int
    let rainPhase: Double
}

struct WeatherPresentationState: Equatable, Sendable {
    let track: RacingTrack
    let weather: RacingWeather
    let tier: RacingEnvironmentQualityTier
    let sanitizedTravel: Double
    let phase: Float
    let terrainWetness: Float
    let rockWetness: Float
    let terrainRoughness: Float
    let rockRoughness: Float
    let clearcoat: Float
    let visibility: RacingEnvironmentLayerVisibilityState
    let rainParticleCount: Int
    let dustSprayParticleCount: Int
    let maximumWeatherParticleCount: Int
    let rainWorldOpacity: Float
    let puddlesEnabled: Bool
    let puddleOpacity: Float
    let stormEffectKind: RacingEnvironmentStormEffectKind
    let dustSprayOpacity: Float
    let vegetationSwayRadians: Float
    let rainTranslation: SIMD3<Float>
    let movingWorldHazeTranslation: SIMD3<Float>
    let dustSprayTranslation: SIMD3<Float>
    let lightningOpacity: Float
    let lightningTranslation: SIMD3<Float>
    let lightningScale: Float
    let overlay: RacingWeatherOverlayPresentationState
    let subjectContrastFloor: Float

    var weatherParticleCount: Int {
        rainParticleCount + dustSprayParticleCount
    }

    var usesWetMaterials: Bool {
        weather == .rain || weather == .storm
    }

    var combinedAtmosphericObscuration: Double {
        Double(1 - visibility.far)
            + overlay.fogOpacity
            + overlay.darkWashOpacity
    }

    var allNumericValuesAreFinite: Bool {
        let floatValues = [
            phase,
            terrainWetness,
            rockWetness,
            terrainRoughness,
            rockRoughness,
            clearcoat,
            visibility.foreground,
            visibility.midground,
            visibility.far,
            rainWorldOpacity,
            puddleOpacity,
            dustSprayOpacity,
            vegetationSwayRadians,
            rainTranslation.x,
            rainTranslation.y,
            rainTranslation.z,
            movingWorldHazeTranslation.x,
            movingWorldHazeTranslation.y,
            movingWorldHazeTranslation.z,
            dustSprayTranslation.x,
            dustSprayTranslation.y,
            dustSprayTranslation.z,
            lightningOpacity,
            lightningTranslation.x,
            lightningTranslation.y,
            lightningTranslation.z,
            lightningScale,
            subjectContrastFloor,
        ]
        let doubleValues = [
            sanitizedTravel,
            overlay.darkWashOpacity,
            overlay.rainOpacity,
            overlay.fogOpacity,
            overlay.lightningOpacity,
            overlay.rainPhase,
            combinedAtmosphericObscuration,
        ]
        return floatValues.allSatisfy(\.isFinite)
            && doubleValues.allSatisfy(\.isFinite)
    }
}

enum RacingEnvironmentWeather {
    static let maximumSanitizedTravel = 1_000_000_000.0
    static let maximumCombinedAtmosphericObscuration = 0.80
    static let minimumSubjectContrastFloor: Float = 0.72

    static func presentationState(
        track: RacingTrack,
        weather: RacingWeather,
        travel: Double,
        tier: RacingEnvironmentQualityTier,
        accessibilityPolicy: SensoryAccessibilityPolicy
    ) -> WeatherPresentationState {
        let budget = RacingEnvironmentCatalog.profile(for: track)
            .qualityBudgets
            .budget(for: tier)
        return presentationState(
            track: track,
            weather: weather,
            travel: travel,
            tier: tier,
            budget: budget,
            accessibilityPolicy: accessibilityPolicy
        )
    }

    static func presentationState(
        track: RacingTrack,
        weather: RacingWeather,
        travel: Double,
        tier: RacingEnvironmentQualityTier,
        budget: RacingEnvironmentStaticQualityBudget,
        accessibilityPolicy: SensoryAccessibilityPolicy
    ) -> WeatherPresentationState {
        let safeTravel = sanitizedTravel(travel)
        let trackPhaseOffset: Double = switch track {
        case .coastal: 0.42
        case .alpine: 1.76
        case .desert: 3.18
        }
        let phase = Float(
            (safeTravel * 0.031 + trackPhaseOffset)
                .truncatingRemainder(dividingBy: .pi * 2)
        )
        let reducesMotion = !accessibilityPolicy.allowsFogMotion
        let reducesTransparency = accessibilityPolicy.usesOpaqueFeedback
        let motionIntensity: Float = switch accessibilityPolicy.debris {
        case .balanced: 1
        case .reduced: 0.55
        case .off: 0
        }

        let material: (
            wetness: Float,
            rockWetness: Float,
            terrainRoughness: Float,
            rockRoughness: Float,
            clearcoat: Float
        ) = switch weather {
        case .clear: (0, 0, 0.92, 0.84, 0.04)
        case .rain: (0.70, 0.62, 0.32, 0.38, 0.46)
        case .fog: (0.08, 0.06, 0.92, 0.84, 0.08)
        case .storm: (0.86, 0.78, 0.32, 0.34, 0.58)
        }
        let visibility: RacingEnvironmentLayerVisibilityState = switch weather {
        case .clear:
            RacingEnvironmentLayerVisibilityState(
                foreground: 1,
                midground: 0.96,
                far: 0.90
            )
        case .rain:
            RacingEnvironmentLayerVisibilityState(
                foreground: 0.98,
                midground: 0.90,
                far: 0.76
            )
        case .fog:
            RacingEnvironmentLayerVisibilityState(
                foreground: 0.88,
                midground: 0.62,
                far: 0.34
            )
        case .storm:
            RacingEnvironmentLayerVisibilityState(
                foreground: 0.94,
                midground: 0.78,
                far: 0.58
            )
        }

        let requestedCounts: (rain: Int, dustSpray: Int) = switch (tier, weather) {
        case (_, .clear), (_, .fog): (0, 0)
        case (.baseline, .rain): (48, 0)
        case (.enhanced, .rain): (88, 0)
        case (.baseline, .storm): (56, 20)
        case (.enhanced, .storm): (96, 36)
        }
        let maximumParticleCount = max(budget.maximumWeatherParticleCount, 0)
        let rainParticleCount = min(requestedCounts.rain, maximumParticleCount)
        let dustSprayParticleCount = min(
            requestedCounts.dustSpray,
            maximumParticleCount - rainParticleCount
        )
        let rainWorldOpacity: Float = switch weather {
        case .rain: 0.34
        case .storm: 0.48
        case .clear, .fog: 0
        }
        let puddleOpacity: Float = switch weather {
        case .rain: 0.56
        case .storm: 0.72
        case .clear, .fog: 0
        }
        let dustSprayOpacity: Float = weather == .storm ? 0.34 : 0
        let stormEffectKind: RacingEnvironmentStormEffectKind = track == .desert
            ? .dust
            : .spray
        let swayBase: Float = switch weather {
        case .clear: 0.006
        case .rain: 0.014
        case .fog: 0.004
        case .storm: 0.055
        }
        let vegetationSway = reducesMotion
            ? 0
            : sin(phase * 1.3) * swayBase * motionIntensity
        let rainTranslation = reducesMotion
            ? SIMD3<Float>.zero
            : SIMD3(sin(phase) * 0.10, -abs(cos(phase)) * 0.18, 0)
        let hazeTranslation = reducesMotion
            ? SIMD3<Float>.zero
            : SIMD3(sin(phase * 0.37) * 0.42 * motionIntensity, 0, 0)
        let dustTranslation = reducesMotion || weather != .storm
            ? SIMD3<Float>.zero
            : SIMD3(
                sin(phase * 0.71) * 0.56 * motionIntensity,
                cos(phase * 0.53) * 0.10 * motionIntensity,
                -0.22 * motionIntensity
            )

        let lightningPulse = pow(max(sin(phase * 0.61 - 1.1), 0), 22) * 0.18
        let lightningOpacity: Float
        let lightningTranslation: SIMD3<Float>
        let lightningScale: Float
        if weather != .storm {
            lightningOpacity = 0
            lightningTranslation = .zero
            lightningScale = 1
        } else if reducesMotion {
            lightningOpacity = 0.055
            lightningTranslation = .zero
            lightningScale = 1
        } else {
            lightningOpacity = lightningPulse
            lightningTranslation = SIMD3(sin(phase * 0.23) * 0.18, 0, 0)
            lightningScale = 1 + lightningPulse * 0.08
        }

        let overlayBase: (
            darkWash: Double,
            rain: Double,
            fog: Double
        ) = switch weather {
        case .clear: (0, 0, 0)
        case .rain: (0.10, 0.34, 0)
        case .fog: (0, 0, 0.12)
        case .storm: (0.20, 0.48, 0)
        }
        let transparencyMultiplier = reducesTransparency ? 0.35 : 1.0
        let overlayLightning = Double(lightningOpacity)
            * (reducesTransparency ? 0.45 : 1)
        let overlay = RacingWeatherOverlayPresentationState(
            darkWashOpacity: overlayBase.darkWash * transparencyMultiplier,
            rainOpacity: overlayBase.rain * transparencyMultiplier,
            fogOpacity: overlayBase.fog * transparencyMultiplier,
            lightningOpacity: overlayLightning,
            rainDropCount: rainParticleCount,
            rainPhase: reducesMotion ? 0 : safeTravel * 7.4
        )

        return WeatherPresentationState(
            track: track,
            weather: weather,
            tier: tier,
            sanitizedTravel: safeTravel,
            phase: phase,
            terrainWetness: material.wetness,
            rockWetness: material.rockWetness,
            terrainRoughness: material.terrainRoughness,
            rockRoughness: material.rockRoughness,
            clearcoat: material.clearcoat,
            visibility: visibility,
            rainParticleCount: rainParticleCount,
            dustSprayParticleCount: dustSprayParticleCount,
            maximumWeatherParticleCount: maximumParticleCount,
            rainWorldOpacity: rainWorldOpacity,
            puddlesEnabled: weather == .rain || weather == .storm,
            puddleOpacity: puddleOpacity,
            stormEffectKind: stormEffectKind,
            dustSprayOpacity: dustSprayOpacity,
            vegetationSwayRadians: vegetationSway,
            rainTranslation: rainTranslation,
            movingWorldHazeTranslation: hazeTranslation,
            dustSprayTranslation: dustTranslation,
            lightningOpacity: lightningOpacity,
            lightningTranslation: lightningTranslation,
            lightningScale: lightningScale,
            overlay: overlay,
            subjectContrastFloor: minimumSubjectContrastFloor
        )
    }

    static func standardAccessibilityPolicy() -> SensoryAccessibilityPolicy {
        SensoryAccessibilityPolicy(
            settings: .defaultValue,
            reduceMotion: false,
            reduceTransparency: false
        )
    }

    private static func sanitizedTravel(_ travel: Double) -> Double {
        guard travel.isFinite else { return 0 }
        return min(max(travel, 0), maximumSanitizedTravel)
    }
}
