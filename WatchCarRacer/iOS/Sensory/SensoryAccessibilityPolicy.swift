struct SensoryAccessibilityPolicy: Equatable, Sendable {
    enum DecorativeEffectLevel: Equatable, Sendable {
        case balanced
        case reduced
        case off
    }

    enum PanelTreatment: Equatable, Sendable {
        case translucent
        case opaque
    }

    enum StaticFeedbackEmphasis: Equatable, Sendable {
        case supplemental
        case primary
    }

    let camera: DecorativeEffectLevel
    let body: DecorativeEffectLevel
    let streaks: DecorativeEffectLevel
    let roadLights: DecorativeEffectLevel
    let debris: DecorativeEffectLevel
    let fog: DecorativeEffectLevel
    let panel: PanelTreatment
    let staticFeedback: StaticFeedbackEmphasis
    let allowsFogMotion: Bool
    let usesOpaqueFeedback: Bool

    init(
        settings: SensorySettings,
        reduceMotion: Bool,
        reduceTransparency: Bool
    ) {
        let userLevel: DecorativeEffectLevel = switch settings.effectIntensity {
        case .balanced:
            .balanced
        case .reduced:
            .reduced
        }
        let motionLevel: DecorativeEffectLevel = reduceMotion ? .off : userLevel

        camera = motionLevel
        body = motionLevel
        streaks = motionLevel
        roadLights = reduceTransparency || reduceMotion ? .off : userLevel
        debris = motionLevel
        fog = reduceTransparency ? .off : userLevel
        panel = reduceTransparency ? .opaque : .translucent
        staticFeedback = reduceMotion ? .primary : .supplemental
        allowsFogMotion = !reduceMotion
        usesOpaqueFeedback = reduceTransparency
    }
}

struct SensoryMicroInteractionStyle: Equatable, Sendable {
    let usesMotion: Bool
    let materialSweepAlpha: Double
    let routeSweepAlpha: Double

    init(effectIntensity: SensoryEffectIntensity, reduceMotion: Bool) {
        usesMotion = !reduceMotion
        switch effectIntensity {
        case .balanced:
            materialSweepAlpha = 0.68
            routeSweepAlpha = 0.54
        case .reduced:
            materialSweepAlpha = 0.36
            routeSweepAlpha = 0.30
        }
    }
}
