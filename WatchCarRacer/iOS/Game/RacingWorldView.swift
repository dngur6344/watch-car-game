import RealityKit
import SwiftUI
import UIKit

enum RacingTrack: String, CaseIterable, Identifiable, Sendable {
    case coastal
    case alpine
    case desert

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .coastal: "Ocean Drive"
        case .alpine: "Alpine Pass"
        case .desert: "Desert Circuit"
        }
    }

    var detail: String {
        switch self {
        case .coastal: "Fast coastal sweepers and illuminated resort straights"
        case .alpine: "Tighter mountain bends with stronger elevation changes"
        case .desert: "Wide high-speed arcs across an open canyon route"
        }
    }

    var symbolName: String {
        switch self {
        case .coastal: "water.waves"
        case .alpine: "mountain.2.fill"
        case .desert: "sun.max.fill"
        }
    }
}

enum RacingWeather: String, CaseIterable, Identifiable, Sendable {
    case clear
    case rain
    case fog
    case storm

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .clear: "Clear"
        case .rain: "Rain"
        case .fog: "Fog"
        case .storm: "Storm"
        }
    }

    var detail: String {
        switch self {
        case .clear: "High visibility with direct sunlight"
        case .rain: "Wet asphalt, darker reflections and rainfall"
        case .fog: "Soft light with reduced horizon visibility"
        case .storm: "Heavy rain, low sunlight and distant lightning"
        }
    }

    var symbolName: String {
        switch self {
        case .clear: "sun.max.fill"
        case .rain: "cloud.rain.fill"
        case .fog: "cloud.fog.fill"
        case .storm: "cloud.bolt.rain.fill"
        }
    }
}

struct RacingEnvironmentSelection: Equatable, Sendable {
    var track: RacingTrack
    var weather: RacingWeather

    static let `default` = RacingEnvironmentSelection(track: .coastal, weather: .clear)
}

struct RacingWorldLayout {
    struct Placement {
        let position: SIMD3<Float>
        let orientation: simd_quatf
    }

    struct CameraPose {
        let position: SIMD3<Float>
        let target: SIMD3<Float>
        let fieldOfView: Float
        let roll: Float
    }

    struct VehicleDynamicsPose {
        let heave: Float
        let yaw: Float
        let roll: Float
        let pitch: Float
    }

    struct ImpactResponse {
        let recoilDirection: Float
        let recoilDistance: Float
        let lift: Float
        let yaw: Float
        let roll: Float
    }

    struct MountainMassif {
        let x: Float
        let z: Float
        let radius: Float
        let height: Float
    }

    static let trackTileLength = RacingEnvironmentLayout.trackTileLength
    static let trackSurfaceLength: Float = 12.18
    static let trackUnderlayLength: Float = 12.92
    static let trackTileCount = RacingEnvironmentLayout.trackTileCount
    static let mountainClearance: Float = 15
    static let mountainMassifs = [
        MountainMassif(x: -30, z: -126, radius: 13, height: 17),
        MountainMassif(x: 32, z: -132, radius: 14, height: 19),
        MountainMassif(x: -49, z: -158, radius: 18, height: 23),
        MountainMassif(x: 51, z: -164, radius: 19, height: 25),
    ]

    static func trackTileState(index: Int, travel: Double) -> TrackTileState {
        RacingEnvironmentLayout.trackTileState(index: index, travel: travel)
    }

    static func trackTileDistance(index: Int, travel: Double) -> Float {
        trackTileState(index: index, travel: travel).distance
    }

    static func trackPlacement(
        distance: Float,
        travel: Double,
        track: RacingTrack = .coastal
    ) -> Placement {
        let position = trackCenter(distance: distance, travel: travel, track: track)
        let sample: Float = 0.4
        let before = trackCenter(distance: distance - sample, travel: travel, track: track)
        let after = trackCenter(distance: distance + sample, travel: travel, track: track)
        let delta = after - before
        let direction = simd_length_squared(delta) > 0.000_001
            ? simd_normalize(delta)
            : SIMD3<Float>(0, 0, -1)
        let tangent = simd_quatf(from: SIMD3<Float>(0, 0, -1), to: direction)
        let curvature = after.x - position.x * 2 + before.x
        let bank = simd_quatf(
            angle: min(max(-curvature * 0.42, -0.055), 0.055),
            axis: SIMD3<Float>(0, 0, 1)
        )
        return Placement(position: position, orientation: tangent * bank)
    }

    static func obstaclePlacement(
        _ obstacle: ObstacleSnapshot,
        travel: Double,
        track: RacingTrack = .coastal
    ) -> Placement {
        let distance = Float(obstacle.distance.isFinite ? obstacle.distance : 0)
        let trackPlacement = trackPlacement(
            distance: distance,
            travel: travel,
            track: track
        )
        let lateral = Float(obstacle.x.isFinite ? obstacle.x : 0)
        let clearance: Float = obstacle.kind == .barrier ? 0.34 : 0
        let offset = trackPlacement.orientation.act(SIMD3(lateral, clearance, 0))
        return Placement(
            position: trackPlacement.position + offset,
            orientation: trackPlacement.orientation
        )
    }

    static func speedProgress(
        speed: Double,
        initialSpeed: Double,
        maximumSpeed: Double
    ) -> Float {
        let range = max(maximumSpeed - initialSpeed, 0.001)
        let finiteSpeed = speed.isFinite ? speed : initialSpeed
        return Float(min(max((finiteSpeed - initialSpeed) / range, 0), 1))
    }

    static func vehicleVisualScale(vehicleID: VehicleID?) -> Float {
        switch vehicleID {
        case .rally:
            1.04
        case .gt:
            0.90
        case .angular:
            0.99
        case nil:
            1.03
        }
    }

    static func vehicleDynamicsPose(
        steering: Double,
        speedProgress: Float,
        travel: Double
    ) -> VehicleDynamicsPose {
        let safeSteering = Float(min(max(steering.isFinite ? steering : 0, -1), 1))
        let progress = min(max(speedProgress.isFinite ? speedProgress : 0, 0), 1)
        let safeTravel = Float(travel.isFinite ? travel : 0)
        let roadFrequency = safeTravel * 0.34
        let suspensionAmplitude: Float = 0.004 + progress * 0.014
        let lateralLoad = safeSteering * (0.022 + progress * 0.050)

        return VehicleDynamicsPose(
            heave: sin(roadFrequency) * suspensionAmplitude,
            yaw: -safeSteering * (0.078 + progress * 0.048),
            roll: -lateralLoad,
            pitch: cos(roadFrequency * 0.57) * (0.004 + progress * 0.010)
        )
    }

    static func impactResponse(
        playerX: Double,
        obstacleX: Double,
        closingSpeed: Double
    ) -> ImpactResponse {
        let safePlayerX = Float(playerX.isFinite ? playerX : 0)
        let safeObstacleX = Float(obstacleX.isFinite ? obstacleX : 0)
        let direction: Float = safeObstacleX >= safePlayerX ? -1 : 1
        let normalizedSpeed = Float(
            min(max(closingSpeed.isFinite ? closingSpeed / 24 : 0, 0), 1)
        )
        return ImpactResponse(
            recoilDirection: direction,
            recoilDistance: 0.20 + normalizedSpeed * 0.24,
            lift: 0.10 + normalizedSpeed * 0.13,
            yaw: direction * (0.10 + normalizedSpeed * 0.12),
            roll: direction * (0.12 + normalizedSpeed * 0.16)
        )
    }

    static func cameraPose(
        playerX: Double,
        steering: Double,
        speedProgress: Float,
        travel: Double,
        track: RacingTrack = .coastal
    ) -> CameraPose {
        let safePlayerX = Float(playerX.isFinite ? playerX : 0)
        let safeSteering = Float(min(max(steering.isFinite ? steering : 0, -1), 1))
        let progress = min(max(speedProgress.isFinite ? speedProgress : 0, 0), 1)
        let curveFocus = trackPlacement(
            distance: 16,
            travel: travel,
            track: track
        ).position
        let safeTravel = Float(travel.isFinite ? travel : 0)
        let roadPulse = sin(safeTravel * 0.24)
        let highSpeedDrift = sin(safeTravel * 0.91) * progress * 0.018

        return CameraPose(
            position: SIMD3(
                safePlayerX * 0.22 - safeSteering * 0.14 + highSpeedDrift,
                2.36 + progress * 0.12 + roadPulse * (0.018 + progress * 0.020),
                5.32 - progress * 0.52
            ),
            target: SIMD3(
                safePlayerX * 0.38 + curveFocus.x * 0.62,
                0.58 + curveFocus.y * 0.38,
                -9.8 - progress * 3.0
            ),
            fieldOfView: 53 + progress * 12,
            roll: -safeSteering * (0.014 + progress * 0.020)
        )
    }

    static func cinematicSpeedIntensity(
        speedProgress: Float,
        effectLevel: SensoryAccessibilityPolicy.DecorativeEffectLevel
    ) -> Float {
        let progress = min(max(speedProgress.isFinite ? speedProgress : 0, 0), 1)
        let eased = pow(max((progress - 0.12) / 0.88, 0), 1.45)
        return switch effectLevel {
        case .balanced: eased
        case .reduced: eased * 0.45
        case .off: 0
        }
    }

    private static func trackCenter(
        distance: Float,
        travel: Double,
        track: RacingTrack
    ) -> SIMD3<Float> {
        let safeTravel = Float(travel.isFinite ? max(travel, 0) : 0)
        let influence = min(abs(distance) / 28, 1)
        let profile: (
            curveFrequency: Float,
            curveAmplitude: Float,
            elevationFrequency: Float,
            elevationAmplitude: Float,
            phase: Float
        ) = switch track {
        case .coastal: (0.032, 5.2, 0.019, 0.45, 0.8)
        case .alpine: (0.044, 6.8, 0.026, 0.76, 1.35)
        case .desert: (0.022, 4.1, 0.014, 0.30, 0.30)
        }
        let curvePhase = safeTravel * profile.curveFrequency + profile.phase
        let elevationPhase = safeTravel * profile.elevationFrequency + profile.phase
        let x = (
            sin(curvePhase + distance * profile.curveFrequency) - sin(curvePhase)
        ) * profile.curveAmplitude * influence
        let elevationWave = (
            sin(elevationPhase + distance * profile.elevationFrequency) - sin(elevationPhase)
        ) * profile.elevationAmplitude * influence
        let horizonLift = influence * 0.28
        let minimumLift = influence * 0.04
        let y = distance >= 0
            ? max(elevationWave + horizonLift, minimumLift)
            : 0
        return SIMD3(x, y, -distance)
    }
}

struct RacingSunlightModel {
    struct State {
        let sourcePosition: SIMD3<Float>
        let target: SIMD3<Float>
        let color: SIMD3<Float>
        let intensity: Float
        let rimSourcePosition: SIMD3<Float>
        let rimColor: SIMD3<Float>
        let rimIntensity: Float
        let glarePosition: SIMD2<Float>
        let glareOpacity: Float

        var direction: SIMD3<Float> {
            let delta = target - sourcePosition
            guard simd_length_squared(delta) > 0.000_001 else {
                return SIMD3(0, -1, 0)
            }
            return simd_normalize(delta)
        }
    }

    static func state(
        travel: Double,
        steering: Double,
        environment: RacingEnvironmentSelection = .default
    ) -> State {
        let safeTravel = Float(travel.isFinite ? max(travel, 0) : 0)
        let safeSteering = Float(min(max(steering.isFinite ? steering : 0, -1), 1))
        let routePhase = safeTravel * 0.0024
        let horizontalDrift = sin(routePhase)
        let verticalDrift = cos(routePhase * 0.72)
        let trackWarmth: SIMD3<Float> = switch environment.track {
        case .coastal: SIMD3(1, 0.90, 0.75)
        case .alpine: SIMD3(0.90, 0.95, 1)
        case .desert: SIMD3(1, 0.82, 0.60)
        }
        let weatherIntensity: Float = switch environment.weather {
        case .clear: 1
        case .rain: 0.60
        case .fog: 0.44
        case .storm: 0.25
        }
        let glareMultiplier: Float = switch environment.weather {
        case .clear: 1
        case .rain: 0.28
        case .fog: 0.14
        case .storm: 0.06
        }
        let rimColor: SIMD3<Float> = switch environment.track {
        case .coastal: SIMD3(0.36, 0.88, 1)
        case .alpine: SIMD3(0.62, 0.82, 1)
        case .desert: SIMD3(1, 0.42, 0.18)
        }
        let rimWeatherMultiplier: Float = switch environment.weather {
        case .clear: 1
        case .rain: 0.74
        case .fog: 0.54
        case .storm: 0.88
        }

        return State(
            sourcePosition: SIMD3(
                -18.5 + horizontalDrift * 3.2,
                16.8 + verticalDrift * 0.9,
                -25.5 + verticalDrift * 2.4
            ),
            target: SIMD3(0, 0.2, -7.5),
            color: simd_clamp(
                trackWarmth + SIMD3(0, verticalDrift * 0.018, verticalDrift * 0.025),
                .zero,
                SIMD3(repeating: 1)
            ),
            intensity: (15_200 + verticalDrift * 900) * weatherIntensity,
            rimSourcePosition: SIMD3(
                13.5 - horizontalDrift * 2.2,
                8.8 + verticalDrift * 0.5,
                5.8
            ),
            rimColor: rimColor,
            rimIntensity: (3_600 + verticalDrift * 280) * rimWeatherMultiplier,
            glarePosition: SIMD2(
                min(max(0.18 + horizontalDrift * 0.045 - safeSteering * 0.012, 0.10), 0.30),
                min(max(0.17 - verticalDrift * 0.018, 0.12), 0.23)
            ),
            glareOpacity: min(max(0.46 + verticalDrift * 0.055, 0.34), 0.54)
                * glareMultiplier
        )
    }
}

@MainActor
private struct RacingWorldResources {
    let asphaltTexture: TextureResource?
    let asphaltNormalTexture: TextureResource?
    let asphaltRoughnessTexture: TextureResource?
    let environment: EnvironmentResource?
    let vehicleTemplates: [VehicleID: Entity]
    let trafficTemplate: Entity?
    let barrierTemplate: Entity?
    let racingEnvironmentTrack: RacingTrack
    let racingEnvironmentTier: RacingEnvironmentQualityTier

    static func load(
        for selection: RacingEnvironmentSelection,
        tier: RacingEnvironmentQualityTier
    ) async -> RacingWorldResources {
        async let asphaltTexture = loadTexture(
            named: "asphalt",
            semantic: .color
        )
        async let asphaltNormalTexture = loadTexture(
            named: "asphalt_normal",
            semantic: .normal
        )
        async let asphaltRoughnessTexture = loadTexture(
            named: "asphalt_roughness",
            semantic: .scalar
        )

        let environment: EnvironmentResource?
        if let skyImage = UIImage(named: "sky_horizon")?.cgImage {
            environment = try? await EnvironmentResource(
                equirectangular: skyImage,
                withName: "racing.sunset"
            )
        } else {
            environment = nil
        }

        async let rallyTemplate = loadEntity(named: "rally_racer")
        async let gtTemplate = loadFirstEntity(named: ["gt_racer_v5", "gt_racer"])
        async let angularTemplate = loadEntity(named: "angular_racer")
        async let trafficTemplate = loadEntity(named: "traffic_sedan_3d")
        async let barrierTemplate = loadEntity(named: "track_barrier")

        var vehicleTemplates: [VehicleID: Entity] = [:]
        if let rallyTemplate = await rallyTemplate {
            vehicleTemplates[.rally] = rallyTemplate
        }
        if let gtTemplate = await gtTemplate {
            vehicleTemplates[.gt] = gtTemplate
        }
        if let angularTemplate = await angularTemplate {
            vehicleTemplates[.angular] = angularTemplate
        }

        return await RacingWorldResources(
            asphaltTexture: asphaltTexture,
            asphaltNormalTexture: asphaltNormalTexture,
            asphaltRoughnessTexture: asphaltRoughnessTexture,
            environment: environment,
            vehicleTemplates: vehicleTemplates,
            trafficTemplate: trafficTemplate,
            barrierTemplate: barrierTemplate,
            racingEnvironmentTrack: selection.track,
            racingEnvironmentTier: tier
        )
    }

    func loadRacingEnvironment() async -> RacingEnvironmentResources {
        await RacingEnvironmentAssetLibrary.shared.resources(
            for: racingEnvironmentTrack,
            tier: racingEnvironmentTier
        )
    }

    private static func loadEntity(named name: String) async -> Entity? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "usdz") else {
            return nil
        }
        return try? await Entity(contentsOf: url, withName: "racing.\(name)")
    }

    private static func loadFirstEntity(named names: [String]) async -> Entity? {
        for name in names {
            if let entity = await loadEntity(named: name) {
                return entity
            }
        }
        return nil
    }

    private static func loadTexture(
        named name: String,
        semantic: TextureResource.Semantic
    ) async -> TextureResource? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "png") else {
            return nil
        }
        return try? await TextureResource(
            contentsOf: url,
            withName: "racing.\(name)",
            options: TextureResource.CreateOptions(
                semantic: semantic,
                mipmapsMode: .allocateAndGenerateAll
            )
        )
    }
}

struct RacingWorldView: View {
    let snapshot: GameSnapshot
    let steering: Double
    let lastEvent: GameEvent?
    let feedback: GameFeedback?
    let appearance: VehicleAppearance
    let configuration: GameSimulation.Configuration
    let environment: RacingEnvironmentSelection
    let qualityTier: RacingEnvironmentQualityTier
    let accessibilityPolicy: SensoryAccessibilityPolicy

    var body: some View {
        let tier = qualityTier
        let speedProgress = RacingWorldLayout.speedProgress(
            speed: snapshot.speed,
            initialSpeed: configuration.initialSpeed,
            maximumSpeed: configuration.maximumSpeed
        )
        let cinematicIntensity = RacingWorldLayout.cinematicSpeedIntensity(
            speedProgress: speedProgress,
            effectLevel: accessibilityPolicy.streaks
        )
        let weatherState = RacingEnvironmentWeather.presentationState(
            track: environment.track,
            weather: environment.weather,
            travel: snapshot.distance,
            tier: tier,
            accessibilityPolicy: accessibilityPolicy
        )
        ZStack {
            skyBackground

            RealityView { content in
                content.camera = .virtual
                let resources = await RacingWorldResources.load(
                    for: environment,
                    tier: tier
                )
                let world = RacingWorldFactory.makeWorld(
                    snapshot: snapshot,
                    steering: steering,
                    lastEvent: lastEvent,
                    appearance: appearance,
                    configuration: configuration,
                    environment: environment,
                    qualityTier: tier,
                    resources: resources,
                    weatherState: weatherState
                )
                content.add(world)
                Task { @MainActor [weak world] in
                    let racingEnvironment = await resources.loadRacingEnvironment()
                    guard let world else { return }
                    world.components.set(
                        RacingEnvironmentResourcesComponent(resources: racingEnvironment)
                    )
                    RacingEnvironmentScene.install(
                        in: world,
                        resources: racingEnvironment,
                        travel: snapshot.distance,
                        weatherState: weatherState
                    )
                }
            } update: { content in
                guard let world = content.entities.first(where: {
                    $0.name == RacingWorldFactory.worldName
                }) else {
                    return
                }
                RacingWorldFactory.update(
                    world: world,
                    snapshot: snapshot,
                    steering: steering,
                    lastEvent: lastEvent,
                    configuration: configuration,
                    environment: environment,
                    qualityTier: tier,
                    weatherState: weatherState
                )
                RacingEnvironmentScene.applyQualityTier(
                    tier,
                    in: world,
                    travel: snapshot.distance,
                    weatherState: weatherState
                )
            }

            RacingSunGlareOverlay(
                state: RacingSunlightModel.state(
                    travel: snapshot.distance,
                    steering: steering,
                    environment: environment
                ),
                reducesTransparency: accessibilityPolicy.usesOpaqueFeedback
            )

            RacingWeatherOverlay(
                state: weatherState
            )

            RacingSpeedLensOverlay(
                intensity: cinematicIntensity,
                distance: snapshot.distance,
                track: environment.track,
                usesOpaqueTreatment: accessibilityPolicy.usesOpaqueFeedback
            )

            if let collisionEventID {
                RacingImpactLensOverlay(
                    effectLevel: accessibilityPolicy.camera,
                    usesOpaqueTreatment: accessibilityPolicy.usesOpaqueFeedback
                )
                .id(collisionEventID)
            }

            if let nearMissFeedback {
                RacingNearMissOverlay(
                    feedback: nearMissFeedback,
                    accessibilityPolicy: accessibilityPolicy
                )
                .id(nearMissFeedback.eventID)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Three dimensional racing track")
        .accessibilityIdentifier("game.racingWorld3D")
    }

    private var nearMissFeedback: GameFeedback? {
        guard let feedback, case .nearMiss = feedback.kind else {
            return nil
        }
        return feedback
    }

    private var collisionEventID: UInt64? {
        guard snapshot.phase == .crashed,
              case let .collision(obstacleID, _) = lastEvent else {
            return nil
        }
        return obstacleID
    }

    @ViewBuilder
    private var skyBackground: some View {
        if let image = UIImage(named: "sky_horizon") {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .hueRotation(trackSkyHue)
                .saturation(environment.weather == .clear ? 1.08 : 0.82)
                .contrast(environment.weather == .fog ? 0.82 : 1.04)
                .brightness(skyBrightness)
                .overlay(trackSkyTint)
        } else {
            LinearGradient(
                colors: [
                    Color(red: 0.16, green: 0.56, blue: 0.90),
                    Color(red: 0.93, green: 0.49, blue: 0.55),
                    Color(red: 0.08, green: 0.11, blue: 0.20),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }

    private var trackSkyHue: Angle {
        switch environment.track {
        case .coastal: .zero
        case .alpine: .degrees(-18)
        case .desert: .degrees(24)
        }
    }

    private var skyBrightness: Double {
        switch environment.weather {
        case .clear: 0
        case .rain: -0.16
        case .fog: 0.04
        case .storm: -0.30
        }
    }

    private var trackSkyTint: Color {
        let base: Color = switch environment.track {
        case .coastal: .clear
        case .alpine: Color(red: 0.50, green: 0.76, blue: 0.92).opacity(0.10)
        case .desert: Color(red: 1, green: 0.48, blue: 0.18).opacity(0.16)
        }
        return base
    }
}

private struct RacingNearMissOverlay: View {
    let feedback: GameFeedback
    let accessibilityPolicy: SensoryAccessibilityPolicy

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                if let side = feedback.spatialContext?.side, side != .center {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(edgeColor)
                        .frame(width: accessibilityPolicy.usesOpaqueFeedback ? 9 : 6)
                        .padding(.vertical, proxy.size.height * 0.16)
                        .frame(maxWidth: .infinity, alignment: side == .left ? .leading : .trailing)
                        .padding(.horizontal, 8)
                }

                if case let .nearMiss(bonus) = feedback.kind {
                    Text("NEAR MISS +\(bonus)")
                        .font(.system(size: 18, weight: .black, design: .rounded))
                        .foregroundStyle(accessibilityPolicy.usesOpaqueFeedback ? .white : edgeColor)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            accessibilityPolicy.usesOpaqueFeedback
                                ? Color.black
                                : Color.black.opacity(0.46),
                            in: Capsule()
                        )
                        .position(x: proxy.size.width / 2, y: proxy.size.height * 0.42)
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var edgeColor: Color {
        feedback.nearMissGrade == .strong
            ? Color(red: 0.40, green: 1, blue: 0.88)
            : Color(red: 1, green: 0.72, blue: 0.24)
    }
}

private struct RacingWeatherOverlay: View {
    let state: WeatherPresentationState

    var body: some View {
        ZStack {
            switch state.weather {
            case .clear:
                EmptyView()
            case .rain:
                Color(red: 0.05, green: 0.12, blue: 0.20)
                    .opacity(state.overlay.darkWashOpacity)
                rain(
                    opacity: state.overlay.rainOpacity,
                    count: state.overlay.rainDropCount,
                    phase: state.overlay.rainPhase
                )
            case .fog:
                fog(opacity: state.overlay.fogOpacity)
            case .storm:
                Color(red: 0.015, green: 0.035, blue: 0.09)
                    .opacity(state.overlay.darkWashOpacity)
                rain(
                    opacity: state.overlay.rainOpacity,
                    count: state.overlay.rainDropCount,
                    phase: state.overlay.rainPhase
                )
                Color.white.opacity(state.overlay.lightningOpacity)
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func rain(opacity: Double, count: Int, phase: Double) -> some View {
        Canvas { context, size in
            let finitePhase = CGFloat(phase.isFinite ? phase : 0)
            for index in 0..<max(count, 0) {
                let seed = CGFloat(index)
                let x = (seed * 73 + finitePhase * (0.72 + CGFloat(index % 5) * 0.07))
                    .truncatingRemainder(dividingBy: size.width + 80) - 40
                let y = (seed * 47 + finitePhase * 2.1)
                    .truncatingRemainder(dividingBy: size.height + 70) - 35
                var drop = Path()
                drop.move(to: CGPoint(x: x, y: y))
                drop.addLine(
                    to: CGPoint(
                        x: x - 8 - CGFloat(index % 3) * 2,
                        y: y + 24 + CGFloat(index % 4) * 5
                    )
                )
                context.stroke(
                    drop,
                    with: .color(.white.opacity(opacity)),
                    lineWidth: index.isMultiple(of: 4) ? 1.3 : 0.7
                )
            }
        }
    }

    private func fog(opacity: Double) -> some View {
        LinearGradient(
            colors: [
                Color(red: 0.72, green: 0.80, blue: 0.82).opacity(opacity * 0.34),
                Color(red: 0.76, green: 0.82, blue: 0.82).opacity(opacity),
                Color(red: 0.52, green: 0.60, blue: 0.62).opacity(opacity * 0.55),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

}

private struct RacingSpeedLensOverlay: View {
    let intensity: Float
    let distance: Double
    let track: RacingTrack
    let usesOpaqueTreatment: Bool

    var body: some View {
        GeometryReader { proxy in
            let amount = Double(min(max(intensity, 0), 1))
            ZStack {
                RadialGradient(
                    colors: [
                        .clear,
                        .clear,
                        Color.black.opacity(
                            amount * (usesOpaqueTreatment ? 0.16 : 0.25)
                        ),
                    ],
                    center: UnitPoint(x: 0.5, y: 0.47),
                    startRadius: min(proxy.size.width, proxy.size.height) * 0.18,
                    endRadius: max(proxy.size.width, proxy.size.height) * 0.72
                )
                .blendMode(.multiply)

                Canvas { context, size in
                    let center = CGPoint(x: size.width * 0.5, y: size.height * 0.43)
                    let phase = CGFloat(
                        (distance.isFinite ? distance : 0)
                            .truncatingRemainder(dividingBy: 1)
                    )
                    for index in 0..<16 {
                        let side: CGFloat = index.isMultiple(of: 2) ? -1 : 1
                        let lane = CGFloat(index / 2) / 7
                        let edgeX = side < 0
                            ? -size.width * (0.02 + lane * 0.07)
                            : size.width * (1.02 + lane * 0.07)
                        let edgeY = size.height * (0.38 + lane * 0.62)
                        let motion = (phase + lane).truncatingRemainder(dividingBy: 1)
                        let start = CGPoint(
                            x: center.x + (edgeX - center.x) * (0.38 + motion * 0.14),
                            y: center.y + (edgeY - center.y) * (0.38 + motion * 0.14)
                        )
                        let end = CGPoint(
                            x: center.x + (edgeX - center.x) * (0.78 + motion * 0.20),
                            y: center.y + (edgeY - center.y) * (0.78 + motion * 0.20)
                        )
                        var streak = Path()
                        streak.move(to: start)
                        streak.addLine(to: end)
                        context.stroke(
                            streak,
                            with: .color(streakColor.opacity(amount * (0.14 + lane * 0.15))),
                            lineWidth: 0.8 + lane * 1.5
                        )
                    }
                }
                .blendMode(.plusLighter)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var streakColor: Color {
        switch track {
        case .coastal: Color(red: 0.30, green: 0.94, blue: 1)
        case .alpine: Color(red: 0.68, green: 0.84, blue: 1)
        case .desert: Color(red: 1, green: 0.50, blue: 0.18)
        }
    }
}

private struct RacingImpactLensOverlay: View {
    let effectLevel: SensoryAccessibilityPolicy.DecorativeEffectLevel
    let usesOpaqueTreatment: Bool
    @State private var hasExpanded = false

    var body: some View {
        ZStack {
            RadialGradient(
                colors: [
                    Color.white.opacity(hasExpanded ? 0 : 0.32),
                    Color(red: 1, green: 0.42, blue: 0.06)
                        .opacity(hasExpanded ? 0.05 : 0.48),
                    .clear,
                ],
                center: .center,
                startRadius: 0,
                endRadius: hasExpanded ? 280 : 26
            )
            Rectangle()
                .strokeBorder(
                    Color(red: 1, green: 0.48, blue: 0.10)
                        .opacity(hasExpanded ? 0.08 : 0.72),
                    lineWidth: usesOpaqueTreatment ? 8 : 13
                )
        }
        .scaleEffect(effectLevel == .off ? 1 : (hasExpanded ? 1.08 : 0.92))
        .onAppear {
            guard effectLevel != .off else {
                hasExpanded = true
                return
            }
            withAnimation(.easeOut(duration: 0.46)) {
                hasExpanded = true
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct RacingSunGlareOverlay: View {
    let state: RacingSunlightModel.State
    let reducesTransparency: Bool

    var body: some View {
        GeometryReader { proxy in
            let origin = CGPoint(
                x: proxy.size.width * CGFloat(state.glarePosition.x),
                y: proxy.size.height * CGFloat(state.glarePosition.y)
            )

            ZStack {
                Canvas { context, size in
                    for index in 0..<3 {
                        let spread = CGFloat(index) * size.width * 0.055
                        let end = CGPoint(
                            x: size.width * (0.58 + CGFloat(index) * 0.13),
                            y: size.height * (0.72 + CGFloat(index) * 0.08)
                        )
                        var ray = Path()
                        ray.move(to: origin)
                        ray.addLine(to: CGPoint(x: end.x - spread, y: end.y))
                        ray.addLine(to: CGPoint(x: end.x + spread + 28, y: end.y))
                        ray.closeSubpath()
                        context.fill(
                            ray,
                            with: .linearGradient(
                                Gradient(colors: [
                                    Color(red: 1, green: 0.83, blue: 0.56)
                                        .opacity(0.09 - Double(index) * 0.018),
                                    .clear,
                                ]),
                                startPoint: origin,
                                endPoint: end
                            )
                        )
                    }
                }
                .blur(radius: 12)

                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                .white.opacity(0.78),
                                Color(red: 1, green: 0.78, blue: 0.42).opacity(0.28),
                                .clear,
                            ],
                            center: .center,
                            startRadius: 1,
                            endRadius: 70
                        )
                    )
                    .frame(width: 140, height: 140)
                    .position(origin)
                    .blur(radius: 3)

                Circle()
                    .fill(Color(red: 1, green: 0.87, blue: 0.64).opacity(0.12))
                    .frame(width: 18, height: 18)
                    .position(
                        x: origin.x + proxy.size.width * 0.31,
                        y: origin.y + proxy.size.height * 0.34
                    )
                    .blur(radius: 4)
            }
            .blendMode(.plusLighter)
            .opacity(
                reducesTransparency
                    ? Double(state.glareOpacity) * 0.30
                    : Double(state.glareOpacity)
            )
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

@MainActor
private enum RacingWorldFactory {
    static let worldName = "racing.world"

    private static let playerName = "racing.player"
    private static let trackName = "racing.track"
    private static let obstacleRootName = "racing.obstacles"
    private static let speedEffectRootName = "racing.speedEffects"
    private static let wakeEffectRootName = "racing.wakeEffects"
    private static let impactRootName = "racing.impactEffects"
    private static let templateRootName = "racing.templates"
    private static let trafficTemplateName = "racing.template.traffic"
    private static let barrierTemplateName = "racing.template.barrier"
    private static let cameraName = "racing.camera"
    private static let tilePrefix = "racing.track.tile."
    private static let obstaclePrefix = "racing.obstacle."
    private static let speedStreakPrefix = "racing.speedStreak."
    private static let wakeParticlePrefix = "racing.wakeParticle."
    private static let impactSparkPrefix = "racing.impact.spark."
    private static let impactDebrisPrefix = "racing.impact.debris."
    private static let impactCoreName = "racing.impact.core"
    private static let impactFlashName = "racing.impact.flash"

    private static let roadHalfWidth: Float = 3.35
    private static let laneSeparatorX: [Float] = [-1.1, 1.1]

    private final class VehicleAnimationRuntime {
        struct Wheel {
            let entity: Entity
            let isFront: Bool
            let isImported: Bool
        }

        let wheels: [Wheel]
        let exhausts: [Entity]

        init(wheels: [Wheel], exhausts: [Entity]) {
            self.wheels = wheels
            self.exhausts = exhausts
        }
    }

    private struct VehicleAnimationRuntimeComponent: Component {
        let runtime: VehicleAnimationRuntime
    }

    private struct SunShadowQualityComponent: Component {
        var tier: RacingEnvironmentQualityTier
    }

    private static func directChild(named name: String, in parent: Entity) -> Entity? {
        parent.children.first { $0.name == name }
    }

    static func makeWorld(
        snapshot: GameSnapshot,
        steering: Double,
        lastEvent: GameEvent?,
        appearance: VehicleAppearance,
        configuration: GameSimulation.Configuration,
        environment: RacingEnvironmentSelection,
        qualityTier: RacingEnvironmentQualityTier,
        resources: RacingWorldResources,
        weatherState: WeatherPresentationState
    ) -> Entity {
        let world = Entity()
        world.name = worldName

        world.addChild(makeEnvironment(track: environment.track))

        if let environmentResource = resources.environment {
            let imageLight = Entity()
            imageLight.name = "racing.imageLight"
            imageLight.components.set(
                ImageBasedLightComponent(
                    source: .single(environmentResource),
                    intensityExponent: imageLightIntensityExponent(
                        for: environment.weather
                    )
                )
            )
            world.addChild(imageLight)
            world.components.set(
                ImageBasedLightReceiverComponent(imageBasedLight: imageLight)
            )
        }

        let track = Entity()
        track.name = trackName
        for index in 0..<RacingWorldLayout.trackTileCount {
            track.addChild(
                makeTrackTile(
                    index: index,
                    asphaltTexture: resources.asphaltTexture,
                    asphaltNormalTexture: resources.asphaltNormalTexture,
                    asphaltRoughnessTexture: resources.asphaltRoughnessTexture,
                    environment: environment,
                    weatherState: weatherState
                )
            )
        }
        world.addChild(track)

        let player = makeCar(
            name: playerName,
            color: color(from: appearance.color.rgba),
            isPlayer: true,
            vehicleID: appearance.vehicle.id,
            template: resources.vehicleTemplates[appearance.vehicle.id]
        )
        world.addChild(player)

        let templates = Entity()
        templates.name = templateRootName
        templates.isEnabled = false
        if let trafficTemplate = resources.trafficTemplate {
            let traffic = trafficTemplate.clone(recursive: true)
            traffic.name = trafficTemplateName
            templates.addChild(traffic)
        }
        if let barrierTemplate = resources.barrierTemplate {
            let barrier = barrierTemplate.clone(recursive: true)
            barrier.name = barrierTemplateName
            templates.addChild(barrier)
        }
        world.addChild(templates)

        let obstacles = Entity()
        obstacles.name = obstacleRootName
        world.addChild(obstacles)

        world.addChild(makeSpeedEffects())
        world.addChild(makeWakeEffects(environment: environment))
        world.addChild(makeImpactEffects())

        let camera = PerspectiveCamera()
        camera.name = cameraName
        camera.camera.fieldOfViewInDegrees = 55
        camera.position = SIMD3(0, 2.55, 5.4)
        camera.look(
            at: SIMD3(0, 0.68, -8.6),
            from: camera.position,
            relativeTo: world
        )
        world.addChild(camera)

        let sun = DirectionalLight()
        sun.name = "racing.sun"
        let sunlight = RacingSunlightModel.state(
            travel: snapshot.distance,
            steering: steering,
            environment: environment
        )
        sun.light.color = color(from: sunlight.color)
        sun.light.intensity = sunlight.intensity
        applySunShadowQuality(qualityTier, to: sun)
        sun.look(
            at: sunlight.target,
            from: sunlight.sourcePosition,
            relativeTo: world
        )
        world.addChild(sun)

        let rim = DirectionalLight()
        rim.name = "racing.rim"
        rim.light.color = color(from: sunlight.rimColor)
        rim.light.intensity = sunlight.rimIntensity
        rim.look(
            at: SIMD3(0, 0.65, -5.5),
            from: sunlight.rimSourcePosition,
            relativeTo: world
        )
        world.addChild(rim)

        update(
            world: world,
            snapshot: snapshot,
            steering: steering,
            lastEvent: lastEvent,
            configuration: configuration,
            environment: environment,
            qualityTier: qualityTier,
            weatherState: weatherState
        )
        return world
    }

    static func update(
        world: Entity,
        snapshot: GameSnapshot,
        steering: Double,
        lastEvent: GameEvent?,
        configuration: GameSimulation.Configuration,
        environment: RacingEnvironmentSelection,
        qualityTier: RacingEnvironmentQualityTier,
        weatherState: WeatherPresentationState
    ) {
        let speedProgress = RacingWorldLayout.speedProgress(
            speed: snapshot.speed,
            initialSpeed: configuration.initialSpeed,
            maximumSpeed: configuration.maximumSpeed
        )
        updateSunlight(
            in: world,
            snapshot: snapshot,
            steering: steering,
            environment: environment,
            qualityTier: qualityTier
        )
        if let track = directChild(named: trackName, in: world) {
            for index in 0..<RacingWorldLayout.trackTileCount {
                guard let tile = directChild(named: "\(tilePrefix)\(index)", in: track) else {
                    continue
                }
                let tileState = RacingWorldLayout.trackTileState(
                    index: index,
                    travel: snapshot.distance
                )
                let placement = RacingWorldLayout.trackPlacement(
                    distance: tileState.distance,
                    travel: snapshot.distance,
                    track: environment.track
                )
                tile.position = placement.position
                tile.orientation = placement.orientation
            }
        }
        let collisionID: UInt64? = if case let .collision(obstacleID, _) = lastEvent {
            obstacleID
        } else {
            nil
        }
        let impactIsAnimating = collisionID.map {
            hasPresentedImpact(obstacleID: $0, in: world)
        } ?? false

        if snapshot.phase == .running {
            resetImpactEffects(in: world)
        }

        if let player = directChild(named: playerName, in: world), !impactIsAnimating {
            let dynamics = RacingWorldLayout.vehicleDynamicsPose(
                steering: steering,
                speedProgress: speedProgress,
                travel: snapshot.distance
            )
            player.position = SIMD3(Float(snapshot.playerX), dynamics.heave, 0)
            let yaw = simd_quatf(angle: dynamics.yaw, axis: SIMD3(0, 1, 0))
            let roll = simd_quatf(angle: dynamics.roll, axis: SIMD3(0, 0, 1))
            let pitch = simd_quatf(angle: dynamics.pitch, axis: SIMD3(1, 0, 0))
            player.orientation = yaw * roll * pitch
            updateExhaust(on: player, speedProgress: speedProgress, distance: snapshot.distance)
            updateWheels(
                on: player,
                distance: snapshot.distance,
                steering: Float(min(max(steering.isFinite ? steering : 0, -1), 1))
            )
        }

        if let camera = directChild(named: cameraName, in: world) as? PerspectiveCamera {
            let pose = RacingWorldLayout.cameraPose(
                playerX: snapshot.playerX,
                steering: steering,
                speedProgress: speedProgress,
                travel: snapshot.distance,
                track: environment.track
            )
            camera.camera.fieldOfViewInDegrees += (
                pose.fieldOfView - camera.camera.fieldOfViewInDegrees
            ) * 0.14
            let cameraPosition = simd_mix(
                camera.position,
                pose.position,
                SIMD3<Float>(repeating: 0.14)
            )
            camera.look(
                at: pose.target,
                from: cameraPosition,
                relativeTo: world
            )
            camera.orientation *= simd_quatf(
                angle: pose.roll,
                axis: SIMD3<Float>(0, 0, 1)
            )
        }

        updateSpeedEffects(
            in: world,
            snapshot: snapshot,
            speedProgress: speedProgress,
            track: environment.track,
            qualityTier: qualityTier
        )
        updateWakeEffects(
            in: world,
            snapshot: snapshot,
            speedProgress: speedProgress,
            weatherState: weatherState
        )

        guard let obstacleRoot = directChild(named: obstacleRootName, in: world) else {
            return
        }
        let visibleNames = Set(snapshot.obstacles.map { "\(obstaclePrefix)\($0.id)" })
        for child in Array(obstacleRoot.children) where !visibleNames.contains(child.name) {
            child.removeFromParent()
        }

        for obstacle in snapshot.obstacles {
            let name = "\(obstaclePrefix)\(obstacle.id)"
            let entity: Entity
            if let existing = directChild(named: name, in: obstacleRoot) {
                entity = existing
            } else {
                entity = makeObstacle(obstacle, name: name, world: world)
                obstacleRoot.addChild(entity)
            }
            let placement = RacingWorldLayout.obstaclePlacement(
                obstacle,
                travel: snapshot.distance,
                track: environment.track
            )
            entity.position = placement.position
            entity.orientation = placement.orientation
        }

        if snapshot.phase == .crashed,
           case let .collision(obstacleID, obstacleKind) = lastEvent,
           !hasPresentedImpact(obstacleID: obstacleID, in: world),
           let obstacle = snapshot.obstacles.first(where: { $0.id == obstacleID }) {
            presentImpact(
                obstacle: obstacle,
                kind: obstacleKind,
                snapshot: snapshot,
                world: world
            )
        }
    }

    private static func updateSunlight(
        in world: Entity,
        snapshot: GameSnapshot,
        steering: Double,
        environment: RacingEnvironmentSelection,
        qualityTier: RacingEnvironmentQualityTier
    ) {
        guard let sun = directChild(named: "racing.sun", in: world) as? DirectionalLight else {
            return
        }
        let sunlight = RacingSunlightModel.state(
            travel: snapshot.distance,
            steering: steering,
            environment: environment
        )
        sun.light.color = color(from: sunlight.color)
        sun.light.intensity = sunlight.intensity
        applySunShadowQuality(qualityTier, to: sun)
        sun.look(
            at: sunlight.target,
            from: sunlight.sourcePosition,
            relativeTo: world
        )
        if let rim = directChild(named: "racing.rim", in: world) as? DirectionalLight {
            rim.light.color = color(from: sunlight.rimColor)
            rim.light.intensity = sunlight.rimIntensity
            rim.look(
                at: SIMD3(Float(snapshot.playerX), 0.62, -5.5),
                from: sunlight.rimSourcePosition,
                relativeTo: world
            )
        }
    }

    private static func applySunShadowQuality(
        _ tier: RacingEnvironmentQualityTier,
        to sun: DirectionalLight
    ) {
        if sun.components[SunShadowQualityComponent.self]?.tier == tier {
            return
        }
        if tier == .enhanced {
            sun.shadow = DirectionalLightComponent.Shadow(
                shadowProjection: .automatic(maximumDistance: 150),
                depthBias: 1.2
            )
        } else {
            sun.shadow = nil
        }
        sun.components.set(SunShadowQualityComponent(tier: tier))
    }

    private static func makeTrackTile(
        index: Int,
        asphaltTexture: TextureResource?,
        asphaltNormalTexture: TextureResource?,
        asphaltRoughnessTexture: TextureResource?,
        environment: RacingEnvironmentSelection,
        weatherState: WeatherPresentationState
    ) -> Entity {
        let tile = Entity()
        tile.name = "\(tilePrefix)\(index)"
        let wetSurface = weatherState.usesWetMaterials
        let asphaltColor: UIColor = if wetSurface {
            UIColor(red: 0.16, green: 0.19, blue: 0.24, alpha: 1)
        } else {
            switch environment.track {
            case .coastal: UIColor(red: 0.34, green: 0.38, blue: 0.44, alpha: 1)
            case .alpine: UIColor(red: 0.29, green: 0.33, blue: 0.37, alpha: 1)
            case .desert: UIColor(red: 0.38, green: 0.33, blue: 0.29, alpha: 1)
            }
        }
        let shoulderColor: UIColor = switch environment.track {
        case .coastal: UIColor(red: 0.36, green: 0.39, blue: 0.33, alpha: 1)
        case .alpine: UIColor(red: 0.20, green: 0.31, blue: 0.25, alpha: 1)
        case .desert: UIColor(red: 0.52, green: 0.31, blue: 0.17, alpha: 1)
        }
        let asphaltRoughness = weatherState.terrainRoughness

        tile.addChild(
            box(
                name: "asphalt.underlay",
                size: SIMD3(
                    roadHalfWidth * 2 + 0.24,
                    0.10,
                    RacingWorldLayout.trackUnderlayLength
                ),
                position: SIMD3(0, -0.15, 0),
                color: asphaltColor.withAlphaComponent(1),
                metallic: false,
                roughness: 0.94,
                cornerRadius: 0.025
            )
        )

        tile.addChild(
            box(
                name: "asphalt",
                size: SIMD3(
                    roadHalfWidth * 2,
                    0.12,
                    RacingWorldLayout.trackSurfaceLength
                ),
                position: SIMD3(0, -0.09, 0),
                color: asphaltColor,
                metallic: false,
                roughness: asphaltRoughness,
                cornerRadius: 0.04,
                texture: asphaltTexture,
                normalTexture: asphaltNormalTexture,
                roughnessTexture: asphaltRoughnessTexture,
                textureScale: SIMD2(1.3, 3.6)
            )
        )

        for side: Float in [-1, 1] {
            tile.addChild(
                box(
                    name: "shoulder",
                    size: SIMD3(1.9, 0.08, RacingWorldLayout.trackUnderlayLength),
                    position: SIMD3(side * (roadHalfWidth + 1), -0.12, 0),
                    color: shoulderColor,
                    metallic: false,
                    roughness: 1
                )
            )
            tile.addChild(makeGuardrail(side: side))
        }

        for separatorX in laneSeparatorX {
            for dashIndex in 0..<2 {
                tile.addChild(
                    box(
                        name: "lane",
                        size: SIMD3(0.09, 0.025, 2.8),
                        position: SIMD3(
                            separatorX,
                            0,
                            -3 + Float(dashIndex) * 6
                        ),
                        color: .white,
                        metallic: false,
                        roughness: 0.48
                    )
                )
            }
        }

        for reflectorIndex in 0..<4 {
            let localZ = -4.5 + Float(reflectorIndex) * 3
            for side: Float in [-1, 1] {
                tile.addChild(
                    unlitBox(
                        name: "road.reflector",
                        size: SIMD3(0.07, 0.035, 0.18),
                        position: SIMD3(side * 2.96, 0.018, localZ),
                        color: side < 0
                            ? UIColor(red: 0.18, green: 0.88, blue: 1, alpha: 0.92)
                            : UIColor(red: 1, green: 0.40, blue: 0.12, alpha: 0.92),
                        cornerRadius: 0.018
                    )
                )
            }
        }

        for curbIndex in 0..<4 {
            let color = curbIndex.isMultiple(of: 2)
                ? UIColor(red: 0.95, green: 0.13, blue: 0.20, alpha: 1)
                : UIColor.white
            let localZ = -4.5 + Float(curbIndex) * 3
            for side: Float in [-1, 1] {
                tile.addChild(
                    box(
                        name: "curb",
                        size: SIMD3(0.30, 0.10, 3),
                        position: SIMD3(side * (roadHalfWidth + 0.15), 0, localZ),
                        color: color,
                        metallic: false,
                        roughness: 0.55,
                        cornerRadius: 0.025
                    )
                )
            }
        }

        switch environment.track {
        case .coastal:
            if index.isMultiple(of: 2) {
                tile.addChild(makePalm(position: SIMD3(-6.1, 0, -3.2)))
                tile.addChild(makePalm(position: SIMD3(6.4, 0, 3.4)))
            }
            if index % 5 == 2 {
                tile.addChild(makeGrandstand(position: SIMD3(8.6, 0, 0)))
            }
            if index == 4 {
                tile.addChild(makePitBuilding(position: SIMD3(-14.2, 0, 0)))
            }
            if index == 7 {
                tile.addChild(makeHotelTower(position: SIMD3(15.4, 0, 0)))
            }
        case .alpine:
            if index.isMultiple(of: 2) {
                tile.addChild(makePine(position: SIMD3(-6.5, 0, -3.0)))
                tile.addChild(makePine(position: SIMD3(6.9, 0, 3.5)))
            }
            if index % 3 == 1 {
                tile.addChild(makeRockCluster(position: SIMD3(-7.8, 0, 2.4)))
            }
        case .desert:
            if index.isMultiple(of: 3) {
                tile.addChild(makeCactus(position: SIMD3(-6.6, 0, -3.1)))
                tile.addChild(makeCactus(position: SIMD3(7.2, 0, 3.2)))
            }
            if index % 4 == 1 {
                tile.addChild(makeRockCluster(position: SIMD3(-8.1, 0, 2.4)))
            }
        }
        if index.isMultiple(of: 3) {
            tile.addChild(makeRoadsideLight(position: SIMD3(-4.75, 0, 2.8)))
            tile.addChild(makeRoadsideLight(position: SIMD3(4.75, 0, -2.8)))
        }
        if index % 3 == 2 {
            tile.addChild(makeSkidMarks())
        }
        if index == 9 {
            tile.addChild(makeTrackArch(track: environment.track))
        }

        return tile
    }

    private static func makeGuardrail(side: Float) -> Entity {
        let guardrail = Entity()
        guardrail.name = "guardrail"
        guardrail.position.x = side * (roadHalfWidth + 1.12)

        guardrail.addChild(
            box(
                name: "guardrail.backing",
                size: SIMD3(0.10, 0.46, RacingWorldLayout.trackUnderlayLength),
                position: SIMD3(side * 0.035, 0.56, 0),
                color: UIColor(red: 0.22, green: 0.27, blue: 0.29, alpha: 1),
                metallic: true,
                roughness: 0.48,
                cornerRadius: 0.025
            )
        )

        for (index, y): (Int, Float) in [(0, 0.48), (1, 0.70)] {
            guardrail.addChild(
                box(
                    name: "guardrail.wBeam.\(index)",
                    size: SIMD3(0.16, 0.13, RacingWorldLayout.trackUnderlayLength),
                    position: SIMD3(-side * 0.045, y, 0),
                    color: UIColor(red: 0.68, green: 0.76, blue: 0.77, alpha: 1),
                    metallic: true,
                    roughness: 0.27,
                    cornerRadius: 0.045,
                    clearcoat: 0.18,
                    clearcoatRoughness: 0.16
                )
            )
        }

        for postIndex in 0..<5 {
            let localZ = -4.8 + Float(postIndex) * 2.4
            guardrail.addChild(
                box(
                    name: "guardrail.post.\(postIndex)",
                    size: SIMD3(0.14, 0.82, 0.15),
                    position: SIMD3(side * 0.07, 0.27, localZ),
                    color: UIColor(red: 0.40, green: 0.46, blue: 0.47, alpha: 1),
                    metallic: true,
                    roughness: 0.34,
                    cornerRadius: 0.025
                )
            )
            if postIndex.isMultiple(of: 2) {
                guardrail.addChild(
                    unlitBox(
                        name: "guardrail.reflector.\(postIndex)",
                        size: SIMD3(0.025, 0.09, 0.18),
                        position: SIMD3(-side * 0.095, 0.70, localZ),
                        color: side < 0
                            ? UIColor(red: 0.42, green: 0.92, blue: 1, alpha: 0.92)
                            : UIColor(red: 1, green: 0.60, blue: 0.16, alpha: 0.92),
                        cornerRadius: 0.018
                    )
                )
            }
        }
        return guardrail
    }

    private static func makeSpeedEffects() -> Entity {
        let root = Entity()
        root.name = speedEffectRootName
        for index in 0..<18 {
            let color = index.isMultiple(of: 2)
                ? UIColor(red: 0.18, green: 0.94, blue: 1, alpha: 0.82)
                : UIColor(red: 1, green: 0.45, blue: 0.16, alpha: 0.76)
            let streak = unlitBox(
                name: "\(speedStreakPrefix)\(index)",
                size: SIMD3(0.035, 0.025, 2.4),
                position: .zero,
                color: color,
                cornerRadius: 0.012
            )
            streak.isEnabled = false
            root.addChild(streak)
        }
        return root
    }

    private static func makeWakeEffects(
        environment: RacingEnvironmentSelection
    ) -> Entity {
        let root = Entity()
        root.name = wakeEffectRootName
        let color: UIColor = switch (environment.track, environment.weather) {
        case (.desert, .storm):
            UIColor(red: 1, green: 0.42, blue: 0.14, alpha: 0.76)
        case (_, .rain), (_, .storm):
            UIColor(red: 0.68, green: 0.90, blue: 1, alpha: 0.72)
        default:
            UIColor(red: 0.76, green: 0.70, blue: 0.58, alpha: 0.42)
        }
        for index in 0..<12 {
            let particle = ModelEntity(
                mesh: .generateSphere(radius: 0.055 + Float(index % 3) * 0.018),
                materials: [UnlitMaterial(color: color)]
            )
            particle.name = "\(wakeParticlePrefix)\(index)"
            particle.components.set(OpacityComponent(opacity: 0))
            particle.isEnabled = false
            root.addChild(particle)
        }
        return root
    }

    private static func makeImpactEffects() -> Entity {
        let root = Entity()
        root.name = impactRootName

        for index in 0..<18 {
            let spark = unlitBox(
                name: "\(impactSparkPrefix)\(index)",
                size: SIMD3(0.038, 0.038, index.isMultiple(of: 3) ? 1.02 : 0.68),
                position: .zero,
                color: index.isMultiple(of: 4)
                    ? UIColor(red: 1, green: 0.96, blue: 0.72, alpha: 1)
                    : UIColor(red: 1, green: 0.38, blue: 0.035, alpha: 0.96),
                cornerRadius: 0.009
            )
            spark.isEnabled = false
            root.addChild(spark)
        }

        for index in 0..<7 {
            let debris = box(
                name: "\(impactDebrisPrefix)\(index)",
                size: SIMD3(0.07, 0.025, 0.14 + Float(index % 3) * 0.035),
                position: .zero,
                color: index.isMultiple(of: 2)
                    ? UIColor(red: 0.26, green: 0.30, blue: 0.31, alpha: 1)
                    : UIColor(red: 0.68, green: 0.73, blue: 0.72, alpha: 1),
                metallic: true,
                roughness: 0.40,
                cornerRadius: 0.012
            )
            debris.isEnabled = false
            root.addChild(debris)
        }

        let core = ModelEntity(
            mesh: .generateSphere(radius: 0.16),
            materials: [
                UnlitMaterial(
                    color: UIColor(red: 1, green: 0.76, blue: 0.12, alpha: 1)
                ),
            ]
        )
        core.name = impactCoreName
        core.isEnabled = false
        root.addChild(core)

        let flash = PointLight()
        flash.name = impactFlashName
        flash.light.color = UIColor(red: 1, green: 0.48, blue: 0.08, alpha: 1)
        flash.light.intensity = 11_500
        flash.light.attenuationRadius = 7.2
        flash.isEnabled = false
        root.addChild(flash)
        return root
    }

    private static func hasPresentedImpact(obstacleID: UInt64, in world: Entity) -> Bool {
        guard let root = directChild(named: impactRootName, in: world) else { return false }
        return directChild(named: "racing.impact.marker.\(obstacleID)", in: root) != nil
    }

    private static func resetImpactEffects(in world: Entity) {
        guard let root = directChild(named: impactRootName, in: world),
              root.children.contains(where: { $0.name.hasPrefix("racing.impact.marker.") }) else {
            return
        }
        for child in Array(root.children) {
            if child.name.hasPrefix("racing.impact.marker.") {
                child.removeFromParent()
            } else {
                child.isEnabled = false
                child.position = .zero
                child.scale = .one
                child.orientation = simd_quatf()
            }
        }
        root.position = .zero
        root.orientation = simd_quatf()
    }

    private static func presentImpact(
        obstacle: ObstacleSnapshot,
        kind: ObstacleKind,
        snapshot: GameSnapshot,
        world: Entity
    ) {
        guard let root = directChild(named: impactRootName, in: world),
              let player = directChild(named: playerName, in: world),
              let obstacleRoot = directChild(named: obstacleRootName, in: world),
              let obstacleEntity = directChild(
                named: "\(obstaclePrefix)\(obstacle.id)",
                in: obstacleRoot
              ) else {
            return
        }

        let marker = Entity()
        marker.name = "racing.impact.marker.\(obstacle.id)"
        root.addChild(marker)

        let response = RacingWorldLayout.impactResponse(
            playerX: snapshot.playerX,
            obstacleX: obstacle.x,
            closingSpeed: obstacle.closingSpeed
        )
        let impactOrigin = simd_mix(
            player.position(relativeTo: world),
            obstacleEntity.position(relativeTo: world),
            SIMD3<Float>(repeating: 0.52)
        ) + SIMD3<Float>(0, kind == .barrier ? 0.42 : 0.56, 0.12)
        root.position = impactOrigin

        for index in 0..<18 {
            guard let spark = directChild(named: "\(impactSparkPrefix)\(index)", in: root) else {
                continue
            }
            let angle = Float(index) * 2.399_963 + Float(obstacle.id % 7) * 0.31
            let horizontal = 0.56 + Float(index % 4) * 0.12
            var direction = SIMD3<Float>(
                cos(angle) * horizontal + response.recoilDirection * 0.24,
                0.35 + Float(index % 5) * 0.15,
                sin(angle) * horizontal + 0.18
            )
            direction = simd_normalize(direction)
            let travel = 0.82 + Float(index % 6) * 0.18
            spark.isEnabled = true
            spark.position = .zero
            spark.scale = SIMD3(repeating: 0.82 + Float(index % 3) * 0.13)
            spark.orientation = simd_quatf(
                from: SIMD3<Float>(0, 0, 1),
                to: direction
            )
            var target = spark.transform
            target.translation = direction * travel
            target.translation.y -= 0.18 + Float(index % 4) * 0.035
            target.scale = SIMD3(repeating: 0.075)
            spark.move(
                to: target,
                relativeTo: root,
                duration: 0.26 + TimeInterval(index % 5) * 0.025,
                timingFunction: .easeOut
            )
        }

        for index in 0..<7 {
            guard let debris = directChild(named: "\(impactDebrisPrefix)\(index)", in: root) else {
                continue
            }
            let side = index.isMultiple(of: 2) ? response.recoilDirection : -response.recoilDirection
            let direction = SIMD3<Float>(
                side * (0.38 + Float(index) * 0.045),
                0.30 + Float(index % 3) * 0.16,
                0.10 + Float(index % 4) * 0.09
            )
            debris.isEnabled = true
            debris.position = .zero
            debris.scale = .one
            debris.orientation = simd_quatf(
                angle: Float(index) * 0.54,
                axis: simd_normalize(SIMD3<Float>(1, 0.7, 0.4))
            )
            var target = debris.transform
            target.translation = direction
            target.translation.y -= 0.16
            target.rotation = simd_quatf(
                angle: 1.2 + Float(index) * 0.37,
                axis: simd_normalize(SIMD3<Float>(0.4, 1, 0.6))
            ) * target.rotation
            target.scale = SIMD3(repeating: 0.10)
            debris.move(
                to: target,
                relativeTo: root,
                duration: 0.38 + TimeInterval(index % 3) * 0.045,
                timingFunction: .easeOut
            )
        }

        if let core = directChild(named: impactCoreName, in: root) {
            core.isEnabled = true
            core.position = .zero
            core.scale = SIMD3(repeating: 1.35)
            var target = core.transform
            target.scale = SIMD3(repeating: 0.01)
            core.move(
                to: target,
                relativeTo: root,
                duration: 0.16,
                timingFunction: .easeOut
            )
        }

        if let flash = directChild(named: impactFlashName, in: root) {
            flash.isEnabled = true
            Task { @MainActor [weak flash] in
                try? await Task.sleep(for: .milliseconds(85))
                flash?.isEnabled = false
            }
        }

        var playerImpact = player.transform
        playerImpact.translation += SIMD3(
            response.recoilDirection * response.recoilDistance,
            response.lift,
            0.24
        )
        playerImpact.rotation = simd_quatf(
            angle: response.yaw,
            axis: SIMD3(0, 1, 0)
        ) * simd_quatf(
            angle: response.roll,
            axis: SIMD3(0, 0, 1)
        ) * playerImpact.rotation
        player.move(
            to: playerImpact,
            relativeTo: player.parent,
            duration: 0.11,
            timingFunction: .easeOut
        )

        var obstacleImpact = obstacleEntity.transform
        obstacleImpact.translation += SIMD3(
            -response.recoilDirection * (kind == .barrier ? 0.18 : 0.34),
            kind == .barrier ? 0.08 : 0.18,
            -0.28
        )
        obstacleImpact.rotation = simd_quatf(
            angle: -response.roll * (kind == .barrier ? 0.58 : 0.86),
            axis: SIMD3(0, 0, 1)
        ) * obstacleImpact.rotation
        obstacleEntity.move(
            to: obstacleImpact,
            relativeTo: obstacleEntity.parent,
            duration: 0.16,
            timingFunction: .easeOut
        )

        if let camera = directChild(named: cameraName, in: world) {
            var cameraKick = camera.transform
            cameraKick.translation += SIMD3(
                -response.recoilDirection * 0.10,
                0.07,
                0.04
            )
            cameraKick.rotation = simd_quatf(
                angle: -response.recoilDirection * 0.025,
                axis: SIMD3(0, 0, 1)
            ) * cameraKick.rotation
            camera.move(
                to: cameraKick,
                relativeTo: camera.parent,
                duration: 0.055,
                timingFunction: .easeOut
            )
        }

        Task { @MainActor [weak root, weak player] in
            try? await Task.sleep(for: .milliseconds(135))
            guard let root,
                  directChild(named: "racing.impact.marker.\(obstacle.id)", in: root) != nil,
                  let player else {
                return
            }
            var settle = player.transform
            settle.translation.y = 0.035
            settle.translation.z = 0.12
            settle.rotation = simd_quatf(
                angle: response.roll * 0.34,
                axis: SIMD3(0, 0, 1)
            )
            player.move(
                to: settle,
                relativeTo: player.parent,
                duration: 0.34,
                timingFunction: .easeInOut
            )
        }

        Task { @MainActor [weak root] in
            try? await Task.sleep(for: .milliseconds(470))
            guard let root,
                  directChild(named: "racing.impact.marker.\(obstacle.id)", in: root) != nil else {
                return
            }
            for child in Array(root.children)
            where child.name.hasPrefix(impactSparkPrefix)
                || child.name.hasPrefix(impactDebrisPrefix) {
                child.isEnabled = false
            }
        }
    }

    private static func updateSpeedEffects(
        in world: Entity,
        snapshot: GameSnapshot,
        speedProgress: Float,
        track: RacingTrack,
        qualityTier: RacingEnvironmentQualityTier
    ) {
        guard let root = directChild(named: speedEffectRootName, in: world) else {
            return
        }
        let cycle = 92.0
        let activeCount = qualityTier == .enhanced ? 18 : 12
        for index in 0..<18 {
            guard let streak = directChild(named: "\(speedStreakPrefix)\(index)", in: root) else {
                continue
            }
            streak.isEnabled = index < activeCount && speedProgress > 0.16
            var phase = (Double(index) * 8.4 - snapshot.distance * 2.35)
                .truncatingRemainder(dividingBy: cycle)
            if phase < 0 {
                phase += cycle
            }
            let distance = Float(5.5 + phase)
            let placement = RacingWorldLayout.trackPlacement(
                distance: distance,
                travel: snapshot.distance,
                track: track
            )
            let side: Float = index.isMultiple(of: 2) ? -1 : 1
            let lateral = side * (roadHalfWidth + 0.52 + Float(index % 4) * 0.22)
            streak.position = placement.position
                + placement.orientation.act(
                    SIMD3(lateral, 0.10 + Float(index % 3) * 0.09, 0)
                )
            streak.orientation = placement.orientation
            streak.scale = SIMD3(1, 1, 0.68 + speedProgress * 3.8)
        }
    }

    private static func updateWakeEffects(
        in world: Entity,
        snapshot: GameSnapshot,
        speedProgress: Float,
        weatherState: WeatherPresentationState
    ) {
        guard let root = directChild(named: wakeEffectRootName, in: world) else { return }
        let weatherIntensity: Float = switch weatherState.weather {
        case .clear: weatherState.track == .desert ? 0.18 : 0.06
        case .fog: 0.12
        case .rain: 0.72
        case .storm: 1
        }
        let activeIntensity = speedProgress * weatherIntensity
        for index in 0..<12 {
            guard let particle = directChild(
                named: "\(wakeParticlePrefix)\(index)",
                in: root
            ) else {
                continue
            }
            let phase = Float(
                (snapshot.distance * (0.31 + Double(index % 4) * 0.035)
                    + Double(index) * 0.083)
                    .truncatingRemainder(dividingBy: 1)
            )
            let side: Float = index.isMultiple(of: 2) ? -1 : 1
            let opacity = max(0, (1 - phase) * activeIntensity * 0.72)
            particle.isEnabled = opacity > 0.015
            particle.position = SIMD3(
                Float(snapshot.playerX) + side * (0.48 + phase * 0.24),
                0.12 + phase * (0.42 + activeIntensity * 0.28),
                1.15 + phase * (2.1 + activeIntensity * 1.7)
            )
            let scale = 0.72 + phase * (2.2 + activeIntensity)
            particle.scale = SIMD3(scale * 1.15, scale * 0.68, scale * 1.5)
            if var opacityComponent = particle.components[OpacityComponent.self] {
                opacityComponent.opacity = opacity
                particle.components.set(opacityComponent)
            }
        }
    }

    private static func updateExhaust(
        on player: Entity,
        speedProgress: Float,
        distance: Double
    ) {
        guard let runtime = player.components[VehicleAnimationRuntimeComponent.self]?.runtime else {
            return
        }
        let pulse = 0.90 + Float(sin(distance * 0.42)) * 0.10
        for flame in runtime.exhausts {
            flame.isEnabled = speedProgress > 0.08
            flame.scale = SIMD3(
                0.72 + speedProgress * 0.42,
                (0.62 + speedProgress * 1.8) * pulse,
                0.72 + speedProgress * 0.42
            )
        }
    }

    private static func makeTrackArch(track: RacingTrack) -> Entity {
        let arch = Entity()
        arch.name = "racing.track.arch"
        let accents: (UIColor, UIColor, UIColor) = switch track {
        case .coastal:
            (.systemTeal, .systemPink, UIColor(red: 0.72, green: 1, blue: 0.94, alpha: 1))
        case .alpine:
            (UIColor(red: 0.30, green: 0.68, blue: 1, alpha: 1), .white,
             UIColor(red: 0.68, green: 0.86, blue: 1, alpha: 1))
        case .desert:
            (UIColor(red: 1, green: 0.34, blue: 0.10, alpha: 1),
             UIColor(red: 1, green: 0.76, blue: 0.18, alpha: 1),
             UIColor(red: 1, green: 0.90, blue: 0.52, alpha: 1))
        }
        for side: Float in [-1, 1] {
            arch.addChild(
                box(
                    name: "arch.post",
                    size: SIMD3(0.22, 4.2, 0.24),
                    position: SIMD3(side * 4.35, 2.1, 0),
                    color: side < 0 ? accents.0 : accents.1,
                    metallic: true,
                    roughness: 0.28,
                    cornerRadius: 0.06
                )
            )
            let brace = box(
                name: "arch.brace",
                size: SIMD3(0.15, 2.15, 0.18),
                position: SIMD3(side * 3.62, 3.12, 0.04),
                color: accents.2,
                metallic: true,
                roughness: 0.22,
                cornerRadius: 0.04,
                clearcoat: 0.38,
                clearcoatRoughness: 0.12
            )
            brace.orientation = simd_quatf(
                angle: side * 0.60,
                axis: SIMD3(0, 0, 1)
            )
            arch.addChild(brace)
        }
        arch.addChild(
            box(
                name: "arch.beam",
                size: SIMD3(8.9, 0.34, 0.30),
                position: SIMD3(0, 4.12, 0),
                color: accents.2,
                metallic: true,
                roughness: 0.24,
                cornerRadius: 0.07
            )
        )
        arch.addChild(
            unlitBox(
                name: "arch.sign",
                size: SIMD3(2.7, 0.76, 0.10),
                position: SIMD3(0, 3.82, 0.20),
                color: accents.0,
                cornerRadius: 0.08
            )
        )
        return arch
    }

    private static func makeRoadsideLight(position: SIMD3<Float>) -> Entity {
        let light = Entity()
        light.name = "racing.roadsideLight"
        light.position = position

        let pole = ModelEntity(
            mesh: .generateCylinder(height: 3.5, radius: 0.055),
            materials: [metalMaterial(color: UIColor(white: 0.26, alpha: 1))]
        )
        pole.position.y = 1.75
        light.addChild(pole)
        light.addChild(
            box(
                name: "roadsideLight.arm",
                size: SIMD3(0.56, 0.07, 0.07),
                position: SIMD3(position.x < 0 ? 0.23 : -0.23, 3.46, 0),
                color: UIColor(white: 0.28, alpha: 1),
                metallic: true,
                roughness: 0.28,
                cornerRadius: 0.025
            )
        )
        let lampX: Float = position.x < 0 ? 0.48 : -0.48
        light.addChild(
            unlitBox(
                name: "roadsideLight.lamp",
                size: SIMD3(0.26, 0.10, 0.20),
                position: SIMD3(lampX, 3.39, 0),
                color: UIColor(red: 0.55, green: 0.92, blue: 1, alpha: 1),
                cornerRadius: 0.035
            )
        )

        let glow = PointLight()
        glow.light.color = UIColor(red: 0.45, green: 0.83, blue: 1, alpha: 1)
        glow.light.intensity = 520
        glow.light.attenuationRadius = 4.8
        glow.position = SIMD3(lampX, 3.25, 0)
        light.addChild(glow)
        return light
    }

    private static func makeRockCluster(position: SIMD3<Float>) -> Entity {
        let cluster = Entity()
        cluster.name = "racing.rockCluster"
        cluster.position = position
        let colors = [
            UIColor(red: 0.24, green: 0.30, blue: 0.32, alpha: 1),
            UIColor(red: 0.30, green: 0.34, blue: 0.34, alpha: 1),
            UIColor(red: 0.20, green: 0.27, blue: 0.26, alpha: 1),
        ]
        for index in 0..<3 {
            let rock = ModelEntity(
                mesh: .generateSphere(radius: 0.62 + Float(index) * 0.14),
                materials: [
                    pbrMaterial(
                        color: colors[index],
                        metallic: 0,
                        roughness: 0.96
                    ),
                ]
            )
            rock.position = SIMD3(Float(index - 1) * 0.74, 0.30, Float(index % 2) * 0.42)
            rock.scale = SIMD3(1.2, 0.62 + Float(index) * 0.08, 0.88)
            cluster.addChild(rock)
        }
        return cluster
    }

    private static func makeGrandstand(position: SIMD3<Float>) -> Entity {
        let stand = Entity()
        stand.name = "racing.grandstand"
        stand.position = position
        for row in 0..<3 {
            stand.addChild(
                box(
                    name: "grandstand.row",
                    size: SIMD3(4.4, 0.34, 0.82),
                    position: SIMD3(0, 0.28 + Float(row) * 0.42, Float(row) * 0.48),
                    color: UIColor(
                        red: 0.13 + CGFloat(row) * 0.035,
                        green: 0.17,
                        blue: 0.24,
                        alpha: 1
                    ),
                    metallic: true,
                    roughness: 0.46,
                    cornerRadius: 0.035
                )
            )
        }
        for seat in 0..<8 {
            let color = seat.isMultiple(of: 2) ? UIColor.systemTeal : UIColor.systemPink
            stand.addChild(
                unlitBox(
                    name: "grandstand.light",
                    size: SIMD3(0.28, 0.13, 0.06),
                    position: SIMD3(-1.75 + Float(seat) * 0.50, 1.34, 1.04),
                    color: color,
                    cornerRadius: 0.025
                )
            )
        }
        stand.orientation = simd_quatf(angle: -.pi / 2, axis: SIMD3(0, 1, 0))
        return stand
    }

    private static func makePitBuilding(position: SIMD3<Float>) -> Entity {
        let building = Entity()
        building.name = "racing.pitBuilding"
        building.position = position
        building.addChild(
            box(
                name: "pitBuilding.shell",
                size: SIMD3(3.4, 2.3, 6.4),
                position: SIMD3(0, 1.15, 0),
                color: UIColor(red: 0.24, green: 0.32, blue: 0.42, alpha: 1),
                metallic: true,
                roughness: 0.34,
                cornerRadius: 0.18,
                clearcoat: 0.30,
                clearcoatRoughness: 0.16
            )
        )
        for bay in 0..<5 {
            building.addChild(
                box(
                    name: "pitBuilding.glassBay",
                    size: SIMD3(0.05, 1.12, 0.96),
                    position: SIMD3(1.73, 1.20, -2.16 + Float(bay) * 1.08),
                    color: UIColor(red: 0.06, green: 0.42, blue: 0.52, alpha: 1),
                    metallic: true,
                    roughness: 0.10,
                    cornerRadius: 0.04,
                    clearcoat: 0.72,
                    clearcoatRoughness: 0.08
                )
            )
        }
        building.addChild(
            unlitBox(
                name: "pitBuilding.lightRibbon",
                size: SIMD3(0.08, 0.12, 6.1),
                position: SIMD3(1.78, 2.13, 0),
                color: UIColor(red: 0.12, green: 0.92, blue: 1, alpha: 1),
                cornerRadius: 0.03
            )
        )
        building.addChild(
            box(
                name: "pitBuilding.canopy",
                size: SIMD3(1.55, 0.16, 6.9),
                position: SIMD3(1.45, 2.48, 0),
                color: UIColor(red: 0.82, green: 0.90, blue: 0.94, alpha: 1),
                metallic: true,
                roughness: 0.24,
                cornerRadius: 0.08,
                clearcoat: 0.42,
                clearcoatRoughness: 0.12
            )
        )
        return building
    }

    private static func makeHotelTower(position: SIMD3<Float>) -> Entity {
        let tower = Entity()
        tower.name = "racing.hotelTower"
        tower.position = position
        let shellColors = [
            UIColor(red: 0.20, green: 0.25, blue: 0.42, alpha: 1),
            UIColor(red: 0.25, green: 0.20, blue: 0.45, alpha: 1),
            UIColor(red: 0.31, green: 0.19, blue: 0.43, alpha: 1),
        ]
        for section in 0..<3 {
            let height: Float = 3.05 - Float(section) * 0.22
            tower.addChild(
                box(
                    name: "hotelTower.shell.\(section)",
                    size: SIMD3(4.0 - Float(section) * 0.30, height, 5.6),
                    position: SIMD3(
                        Float(section) * 0.18,
                        1.52 + Float(section) * 2.72,
                        Float(section - 1) * 0.24
                    ),
                    color: shellColors[section],
                    metallic: true,
                    roughness: 0.30,
                    cornerRadius: 0.24,
                    clearcoat: 0.34,
                    clearcoatRoughness: 0.14
                )
            )
        }
        for floor in 0..<7 {
            for column in 0..<4 {
                let color = (floor + column).isMultiple(of: 3)
                    ? UIColor(red: 1, green: 0.28, blue: 0.58, alpha: 1)
                    : UIColor(red: 0.18, green: 0.83, blue: 1, alpha: 1)
                tower.addChild(
                    unlitBox(
                        name: "hotelTower.window",
                        size: SIMD3(0.05, 0.42, 0.72),
                        position: SIMD3(
                            -2.04,
                            1.10 + Float(floor) * 1.02,
                            -1.62 + Float(column) * 1.08
                        ),
                        color: color.withAlphaComponent(0.88),
                        cornerRadius: 0.035
                    )
                )
            }
        }
        tower.addChild(
            unlitBox(
                name: "hotelTower.crown",
                size: SIMD3(0.12, 0.18, 4.8),
                position: SIMD3(-2.10, 8.48, 0),
                color: UIColor(red: 0.22, green: 0.94, blue: 1, alpha: 1),
                cornerRadius: 0.05
            )
        )
        for fin in 0..<4 {
            tower.addChild(
                box(
                    name: "hotelTower.fin.\(fin)",
                    size: SIMD3(0.10, 8.2, 0.16),
                    position: SIMD3(-2.12, 4.2, -2.1 + Float(fin) * 1.4),
                    color: UIColor(red: 0.60, green: 0.68, blue: 0.84, alpha: 1),
                    metallic: true,
                    roughness: 0.24,
                    cornerRadius: 0.025
                )
            )
        }
        return tower
    }

    private static func makeSkidMarks() -> Entity {
        let marks = Entity()
        marks.name = "racing.skidMarks"
        for side: Float in [-1, 1] {
            let mark = unlitBox(
                name: "skidMark",
                size: SIMD3(0.095, 0.008, 4.2),
                position: SIMD3(side * 0.38, 0.017, 0.8),
                color: UIColor(white: 0.015, alpha: 0.54),
                cornerRadius: 0.03
            )
            mark.orientation = simd_quatf(angle: side * 0.035, axis: SIMD3(0, 1, 0))
            marks.addChild(mark)
        }
        return marks
    }

    private static func makeEnvironment(track: RacingTrack) -> Entity {
        let environment = Entity()
        environment.name = "racing.environment"
        let groundColor: UIColor = switch track {
        case .coastal: UIColor(red: 0.12, green: 0.29, blue: 0.20, alpha: 1)
        case .alpine: UIColor(red: 0.10, green: 0.23, blue: 0.17, alpha: 1)
        case .desert: UIColor(red: 0.48, green: 0.27, blue: 0.14, alpha: 1)
        }
        environment.addChild(
            box(
                name: "ground",
                size: SIMD3(140, 0.12, 360),
                position: SIMD3(0, -0.20, -150),
                color: groundColor,
                metallic: false,
                roughness: 1
            )
        )

        for (index, massif) in RacingWorldLayout.mountainMassifs.enumerated() {
            environment.addChild(
                makeMountainMassif(massif, index: index, track: track)
            )
        }
        return environment
    }

    private static func makeMountainMassif(
        _ massif: RacingWorldLayout.MountainMassif,
        index: Int,
        track: RacingTrack
    ) -> Entity {
        let root = Entity()
        root.name = "racing.mountain.\(index)"
        root.position = SIMD3(massif.x, 0, massif.z)

        let baseColors: [UIColor] = switch track {
        case .coastal:
            [
                UIColor(red: 0.12, green: 0.29, blue: 0.24, alpha: 1),
                UIColor(red: 0.17, green: 0.36, blue: 0.28, alpha: 1),
                UIColor(red: 0.21, green: 0.41, blue: 0.31, alpha: 1),
            ]
        case .alpine:
            [
                UIColor(red: 0.18, green: 0.25, blue: 0.25, alpha: 1),
                UIColor(red: 0.24, green: 0.32, blue: 0.30, alpha: 1),
                UIColor(red: 0.30, green: 0.37, blue: 0.35, alpha: 1),
            ]
        case .desert:
            [
                UIColor(red: 0.42, green: 0.19, blue: 0.11, alpha: 1),
                UIColor(red: 0.55, green: 0.27, blue: 0.14, alpha: 1),
                UIColor(red: 0.66, green: 0.36, blue: 0.18, alpha: 1),
            ]
        }
        let peakOffsets: [(x: Float, z: Float, radius: Float, height: Float)] = [
            (-0.35, 0.08, 0.72, 0.74),
            (0, -0.10, 0.86, 1),
            (0.37, 0.14, 0.74, 0.82),
        ]

        let foundationHeight = massif.height * 0.42
        let foundation = ModelEntity(
            mesh: .generateSphere(radius: 1),
            materials: [
                pbrMaterial(
                    color: baseColors[index % baseColors.count],
                    metallic: 0,
                    roughness: 0.98
                ),
            ]
        )
        foundation.name = "mountain.foundation"
        foundation.position = SIMD3(0, foundationHeight * 0.50 - 0.18, 0.8)
        foundation.scale = SIMD3(
            massif.radius * 1.05,
            foundationHeight * 0.50,
            massif.radius * 0.88
        )
        root.addChild(foundation)

        for (peakIndex, peak) in peakOffsets.enumerated() {
            let height = massif.height * peak.height
            let radius = massif.radius * peak.radius
            let mountain = ModelEntity(
                mesh: .generateSphere(radius: 1),
                materials: [
                    pbrMaterial(
                        color: baseColors[(index + peakIndex) % baseColors.count],
                        metallic: 0,
                        roughness: 0.96
                    ),
                ]
            )
            mountain.name = "mountain.rock.\(peakIndex)"
            mountain.position = SIMD3(
                peak.x * massif.radius,
                height * 0.50 - 0.12,
                peak.z * massif.radius
            )
            mountain.scale = SIMD3(
                radius,
                height * 0.50,
                radius * (0.78 + Float(peakIndex) * 0.06)
            )
            root.addChild(mountain)

            if track == .alpine, height > 16 {
                let snowHeight = height * 0.23
                let snow = ModelEntity(
                    mesh: .generateSphere(radius: 1),
                    materials: [
                        pbrMaterial(
                            color: UIColor(red: 0.82, green: 0.91, blue: 0.90, alpha: 1),
                            metallic: 0,
                            roughness: 0.88
                        ),
                    ]
                )
                snow.name = "mountain.snow.\(peakIndex)"
                snow.position = SIMD3(
                    peak.x * massif.radius,
                    height - snowHeight * 0.50 - 0.12,
                    peak.z * massif.radius
                )
                snow.scale = SIMD3(
                    radius * 0.30,
                    snowHeight * 0.50,
                    radius * 0.25
                )
                root.addChild(snow)
            }
        }
        return root
    }

    private static func makePalm(position: SIMD3<Float>) -> Entity {
        let palm = Entity()
        palm.name = "racing.palm"
        palm.position = position

        let trunk = ModelEntity(
            mesh: .generateCylinder(height: 3.4, radius: 0.14),
            materials: [
                SimpleMaterial(
                    color: UIColor(red: 0.38, green: 0.22, blue: 0.10, alpha: 1),
                    roughness: 0.92,
                    isMetallic: false
                ),
            ]
        )
        trunk.position.y = 1.7
        palm.addChild(trunk)

        for index in 0..<5 {
            let leaf = box(
                name: "palm.leaf",
                size: SIMD3(0.22, 0.06, 2.0),
                position: SIMD3(0, 3.4, -0.8),
                color: UIColor(red: 0.08, green: 0.55, blue: 0.27, alpha: 1),
                metallic: false,
                roughness: 0.8,
                cornerRadius: 0.05
            )
            leaf.orientation = simd_quatf(
                angle: Float(index) * (.pi * 2 / 5),
                axis: SIMD3(0, 1, 0)
            )
            palm.addChild(leaf)
        }
        return palm
    }

    private static func makePine(position: SIMD3<Float>) -> Entity {
        let pine = Entity()
        pine.name = "racing.pine"
        pine.position = position

        let trunk = ModelEntity(
            mesh: .generateCylinder(height: 2.5, radius: 0.13),
            materials: [
                SimpleMaterial(
                    color: UIColor(red: 0.26, green: 0.15, blue: 0.08, alpha: 1),
                    roughness: 0.96,
                    isMetallic: false
                ),
            ]
        )
        trunk.position.y = 1.25
        pine.addChild(trunk)

        for level in 0..<3 {
            let foliage = ModelEntity(
                mesh: .generateCone(
                    height: 2.1 - Float(level) * 0.28,
                    radius: 1.15 - Float(level) * 0.18
                ),
                materials: [
                    pbrMaterial(
                        color: UIColor(
                            red: 0.06,
                            green: 0.28 + CGFloat(level) * 0.035,
                            blue: 0.19,
                            alpha: 1
                        ),
                        metallic: 0,
                        roughness: 0.92
                    ),
                ]
            )
            foliage.position.y = 2.0 + Float(level) * 0.72
            pine.addChild(foliage)
        }
        return pine
    }

    private static func makeCactus(position: SIMD3<Float>) -> Entity {
        let cactus = Entity()
        cactus.name = "racing.cactus"
        cactus.position = position
        let material = pbrMaterial(
            color: UIColor(red: 0.16, green: 0.42, blue: 0.22, alpha: 1),
            metallic: 0,
            roughness: 0.86
        )

        let trunk = ModelEntity(
            mesh: .generateCylinder(height: 2.8, radius: 0.26),
            materials: [material]
        )
        trunk.position.y = 1.4
        cactus.addChild(trunk)
        for side: Float in [-1, 1] {
            let arm = ModelEntity(
                mesh: .generateCylinder(height: 1.1, radius: 0.18),
                materials: [material]
            )
            arm.position = SIMD3(side * 0.48, 1.55 + (side > 0 ? 0.22 : 0), 0)
            cactus.addChild(arm)
            let branch = ModelEntity(
                mesh: .generateCylinder(height: 0.72, radius: 0.17),
                materials: [material]
            )
            branch.position = SIMD3(side * 0.28, 1.22 + (side > 0 ? 0.22 : 0), 0)
            branch.orientation = simd_quatf(angle: .pi / 2, axis: SIMD3(0, 0, 1))
            cactus.addChild(branch)
        }
        return cactus
    }

    private static func makeObstacle(
        _ obstacle: ObstacleSnapshot,
        name: String,
        world: Entity
    ) -> Entity {
        switch obstacle.kind {
        case .barrier:
            if let template = world.findEntity(named: barrierTemplateName) {
                let root = Entity()
                root.name = name
                let imported = template.clone(recursive: true)
                imported.name = "barrier.importedAsset"
                imported.isEnabled = true
                imported.scale = SIMD3(Float(obstacle.width) / 1.6, 1, 1)
                root.addChild(imported)
                return root
            }
            let root = Entity()
            root.name = name
            let stripeWidth = Float(obstacle.width) / 3
            for index in 0..<3 {
                root.addChild(
                    box(
                        name: "barrier.segment",
                        size: SIMD3(stripeWidth, 0.65, 0.34),
                        position: SIMD3(
                            (Float(index) - 1) * stripeWidth,
                            0,
                            0
                        ),
                        color: index.isMultiple(of: 2) ? .white : .systemOrange,
                        metallic: false,
                        roughness: 0.55,
                        cornerRadius: 0.06
                    )
                )
            }
            return root
        case .trafficCar:
            return makeCar(
                name: name,
                color: obstacle.id.isMultiple(of: 2) ? .systemPink : .systemYellow,
                isPlayer: false,
                template: world.findEntity(named: trafficTemplateName)
            )
        }
    }

    private static func makeCar(
        name: String,
        color: UIColor,
        isPlayer: Bool,
        vehicleID: VehicleID? = nil,
        template: Entity? = nil
    ) -> Entity {
        let car = Entity()
        car.name = name
        let visualScale = RacingWorldLayout.vehicleVisualScale(vehicleID: vehicleID)

        if let template {
            let imported = template.clone(recursive: true)
            imported.name = "car.importedAsset"
            applyVehiclePaint(to: imported, color: color)
            car.addChild(imported)
            if isPlayer {
                addPlayerEffects(to: car)
            }
            addContactShadow(to: car, isPlayer: isPlayer)
            car.scale = SIMD3(repeating: visualScale)
            installVehicleAnimationRuntime(on: car)
            return car
        }

        let bodyMaterialColor = color
        car.addChild(
            box(
                name: "car.body",
                size: SIMD3(1.44, 0.38, 2.75),
                position: SIMD3(0, 0.45, 0),
                color: bodyMaterialColor,
                metallic: true,
                roughness: 0.24,
                cornerRadius: 0.16,
                clearcoat: 0.92,
                clearcoatRoughness: 0.10
            )
        )
        car.addChild(
            box(
                name: "car.cabin",
                size: SIMD3(1.08, 0.44, 1.28),
                position: SIMD3(0, 0.82, -0.10),
                color: UIColor(red: 0.07, green: 0.13, blue: 0.19, alpha: 1),
                metallic: true,
                roughness: 0.18,
                cornerRadius: 0.14,
                clearcoat: 0.72,
                clearcoatRoughness: 0.08
            )
        )
        let hood = box(
            name: "car.hood",
            size: SIMD3(1.25, 0.11, 0.92),
            position: SIMD3(0, 0.66, -0.91),
            color: bodyMaterialColor,
            metallic: true,
            roughness: 0.20,
            cornerRadius: 0.10,
            clearcoat: 0.95,
            clearcoatRoughness: 0.08
        )
        hood.orientation = simd_quatf(angle: -0.055, axis: SIMD3(1, 0, 0))
        car.addChild(hood)
        car.addChild(
            box(
                name: "car.rearBumper",
                size: SIMD3(1.32, 0.16, 0.12),
                position: SIMD3(0, 0.29, 1.39),
                color: UIColor(red: 0.035, green: 0.045, blue: 0.065, alpha: 1),
                metallic: true,
                roughness: 0.26,
                cornerRadius: 0.035,
                clearcoat: 0.42,
                clearcoatRoughness: 0.16
            )
        )
        car.addChild(
            box(
                name: "car.centerStripe",
                size: SIMD3(0.12, 0.012, 2.58),
                position: SIMD3(0, 0.65, 0),
                color: isPlayer ? .white : UIColor(white: 0.16, alpha: 1),
                metallic: true,
                roughness: 0.24,
                cornerRadius: 0.02,
                clearcoat: 0.86,
                clearcoatRoughness: 0.10
            )
        )

        for side: Float in [-1, 1] {
            car.addChild(
                box(
                    name: "car.hoodVent",
                    size: SIMD3(0.26, 0.018, 0.46),
                    position: SIMD3(side * 0.34, 0.735, -0.88),
                    color: UIColor(red: 0.025, green: 0.035, blue: 0.045, alpha: 1),
                    metallic: true,
                    roughness: 0.33,
                    cornerRadius: 0.025
                )
            )
        }

        let spoilerColor = isPlayer ? UIColor.white : bodyMaterialColor
        car.addChild(
            box(
                name: "car.spoiler",
                size: SIMD3(1.36, 0.08, 0.22),
                position: SIMD3(0, 0.82, 1.17),
                color: spoilerColor,
                metallic: true,
                roughness: 0.22,
                cornerRadius: 0.035,
                clearcoat: 0.88,
                clearcoatRoughness: 0.10
            )
        )
        for side: Float in [-1, 1] {
            car.addChild(
                box(
                    name: "car.spoilerPost",
                    size: SIMD3(0.07, 0.27, 0.09),
                    position: SIMD3(side * 0.48, 0.68, 1.15),
                    color: UIColor(white: 0.08, alpha: 1),
                    metallic: true,
                    roughness: 0.26,
                    cornerRadius: 0.018
                )
            )
        }

        for side: Float in [-1, 1] {
            car.addChild(
                unlitBox(
                    name: "car.tailLight",
                    size: SIMD3(0.43, 0.10, 0.055),
                    position: SIMD3(side * 0.42, 0.51, 1.39),
                    color: UIColor(red: 1, green: 0.05, blue: 0.09, alpha: 1),
                    cornerRadius: 0.02
                )
            )
            car.addChild(
                box(
                    name: "car.mirror",
                    size: SIMD3(0.20, 0.10, 0.30),
                    position: SIMD3(side * 0.78, 0.72, -0.22),
                    color: bodyMaterialColor,
                    metallic: true,
                    roughness: 0.20,
                    cornerRadius: 0.06,
                    clearcoat: 0.84,
                    clearcoatRoughness: 0.10
                )
            )
        }

        for (sideName, x): (String, Float) in [("left", -0.76), ("right", 0.76)] {
            for (axleName, z): (String, Float) in [("front", -0.84), ("rear", 0.84)] {
                car.addChild(
                    makeWheel(
                        name: "car.wheel.\(axleName).\(sideName)",
                        position: SIMD3(x, 0.28, z)
                    )
                )
            }
        }

        let diffuser = Entity()
        diffuser.name = "car.diffuser"
        for x: Float in [-0.43, -0.14, 0.14, 0.43] {
            let fin = box(
                name: "car.diffuserFin",
                size: SIMD3(0.045, 0.18, 0.42),
                position: SIMD3(x, 0.23, 1.43),
                color: UIColor(white: 0.025, alpha: 1),
                metallic: true,
                roughness: 0.34,
                cornerRadius: 0.012
            )
            fin.orientation = simd_quatf(angle: -0.10, axis: SIMD3(1, 0, 0))
            diffuser.addChild(fin)
        }
        car.addChild(diffuser)

        if isPlayer {
            addPlayerEffects(to: car)
        }
        addContactShadow(to: car, isPlayer: isPlayer)
        car.scale = SIMD3(repeating: visualScale)
        installVehicleAnimationRuntime(on: car)
        return car
    }

    private static func installVehicleAnimationRuntime(on car: Entity) {
        let wheelNames = [
            ("front", "left"),
            ("front", "right"),
            ("rear", "left"),
            ("rear", "right"),
        ]
        let wheels = wheelNames.compactMap { axleName, side -> VehicleAnimationRuntime.Wheel? in
            let proceduralName = "car.wheel.\(axleName).\(side)"
            let importedName = "wheel_\(axleName)_\(side)"
            guard let wheel = car.findEntity(named: proceduralName)
                ?? car.findEntity(named: importedName) else {
                return nil
            }
            return VehicleAnimationRuntime.Wheel(
                entity: wheel,
                isFront: axleName == "front",
                isImported: wheel.name.hasPrefix("wheel_")
            )
        }
        let exhausts = ["left", "right"].compactMap {
            directChild(named: "racing.exhaust.\($0)", in: car)
        }
        car.components.set(
            VehicleAnimationRuntimeComponent(
                runtime: VehicleAnimationRuntime(wheels: wheels, exhausts: exhausts)
            )
        )
    }

    private static func applyVehiclePaint(to entity: Entity, color: UIColor) {
        if entity.name.hasPrefix("paint_") || entity.name.hasPrefix("mirror_") {
            if let modelEntity = entity as? ModelEntity,
               var model = modelEntity.model {
                model.materials = [
                    pbrMaterial(
                        color: color,
                        metallic: 0.84,
                        roughness: 0.18,
                        clearcoat: 0.96,
                        clearcoatRoughness: 0.08
                    ),
                ]
                modelEntity.model = model
            }
        }
        for child in entity.children {
            applyVehiclePaint(to: child, color: color)
        }
    }

    private static func addPlayerEffects(to car: Entity) {
        for (sideName, x): (String, Float) in [("left", -0.35), ("right", 0.35)] {
            let flame = ModelEntity(
                mesh: .generateCone(height: 0.74, radius: 0.10),
                materials: [
                    UnlitMaterial(
                        color: UIColor(red: 1, green: 0.42, blue: 0.08, alpha: 0.92)
                    ),
                ]
            )
            flame.name = "racing.exhaust.\(sideName)"
            flame.position = SIMD3(x, 0.24, 1.72)
            flame.orientation = simd_quatf(angle: .pi / 2, axis: SIMD3(1, 0, 0))
            flame.isEnabled = false
            car.addChild(flame)
        }
        car.addChild(
            unlitBox(
                name: "car.underglow",
                size: SIMD3(1.18, 0.018, 2.25),
                position: SIMD3(0, 0.11, 0),
                color: UIColor(red: 0.08, green: 0.88, blue: 1, alpha: 0.52),
                cornerRadius: 0.18
            )
        )
    }

    private static func addContactShadow(to car: Entity, isPlayer: Bool) {
        let shadow = Entity()
        shadow.name = "car.contactShadow"
        shadow.addChild(
            unlitBox(
                name: "car.contactShadow.soft",
                size: SIMD3(1.48, 0.006, 2.62),
                position: SIMD3(0, 0.043, 0.04),
                color: UIColor(white: 0.002, alpha: isPlayer ? 0.16 : 0.13),
                cornerRadius: 0.40
            )
        )
        shadow.addChild(
            unlitBox(
                name: "car.contactShadow.core",
                size: SIMD3(1.16, 0.007, 2.22),
                position: SIMD3(0, 0.046, 0.02),
                color: UIColor(white: 0.002, alpha: isPlayer ? 0.24 : 0.20),
                cornerRadius: 0.32
            )
        )
        car.addChild(shadow)
    }

    private static func makeWheel(
        name: String,
        position: SIMD3<Float>
    ) -> Entity {
        let wheel = Entity()
        wheel.name = name
        wheel.position = position
        wheel.orientation = simd_quatf(angle: .pi / 2, axis: SIMD3(0, 0, 1))

        let tire = ModelEntity(
            mesh: .generateCylinder(height: 0.25, radius: 0.29),
            materials: [
                pbrMaterial(
                    color: UIColor(white: 0.018, alpha: 1),
                    metallic: 0,
                    roughness: 0.88
                ),
            ]
        )
        tire.name = "car.tire"
        wheel.addChild(tire)

        let rim = ModelEntity(
            mesh: .generateCylinder(height: 0.265, radius: 0.17),
            materials: [metalMaterial(color: UIColor(white: 0.74, alpha: 1))]
        )
        rim.name = "car.rim"
        wheel.addChild(rim)

        let brakeDisc = ModelEntity(
            mesh: .generateCylinder(height: 0.275, radius: 0.105),
            materials: [metalMaterial(color: UIColor(white: 0.18, alpha: 1))]
        )
        brakeDisc.name = "car.brakeDisc"
        wheel.addChild(brakeDisc)

        let hub = ModelEntity(
            mesh: .generateCylinder(height: 0.285, radius: 0.042),
            materials: [
                pbrMaterial(
                    color: .systemOrange,
                    metallic: 0.55,
                    roughness: 0.22
                ),
            ]
        )
        hub.name = "car.wheelHub"
        wheel.addChild(hub)
        return wheel
    }

    private static func updateWheels(
        on car: Entity,
        distance: Double,
        steering: Float
    ) {
        guard let runtime = car.components[VehicleAnimationRuntimeComponent.self]?.runtime else {
            return
        }
        let finiteDistance = Float(distance.isFinite ? distance : 0)
        let angle = finiteDistance.truncatingRemainder(dividingBy: .pi * 0.58) / 0.29
        let proceduralSpin = simd_quatf(angle: angle, axis: SIMD3(0, 1, 0))
        let importedSpin = simd_quatf(angle: angle, axis: SIMD3(1, 0, 0))
        let axle = simd_quatf(angle: .pi / 2, axis: SIMD3(0, 0, 1))
        for wheel in runtime.wheels {
            let steer = wheel.isFront
                ? simd_quatf(angle: -steering * 0.16, axis: SIMD3(0, 1, 0))
                : simd_quatf()
            wheel.entity.orientation = wheel.isImported
                ? steer * importedSpin
                : steer * axle * proceduralSpin
        }
    }

    private static func box(
        name: String,
        size: SIMD3<Float>,
        position: SIMD3<Float>,
        color: UIColor,
        metallic: Bool,
        roughness: Float,
        cornerRadius: Float = 0,
        clearcoat: Float = 0,
        clearcoatRoughness: Float = 0.18,
        texture: TextureResource? = nil,
        normalTexture: TextureResource? = nil,
        roughnessTexture: TextureResource? = nil,
        textureScale: SIMD2<Float> = SIMD2(repeating: 1)
    ) -> ModelEntity {
        let material = pbrMaterial(
            color: color,
            metallic: metallic ? 1 : 0,
            roughness: roughness,
            clearcoat: clearcoat,
            clearcoatRoughness: clearcoatRoughness,
            texture: texture,
            normalTexture: normalTexture,
            roughnessTexture: roughnessTexture,
            textureScale: textureScale
        )
        let entity = ModelEntity(
            mesh: .generateBox(size: size, cornerRadius: cornerRadius),
            materials: [material]
        )
        entity.name = name
        entity.position = position
        return entity
    }

    private static func pbrMaterial(
        color: UIColor,
        metallic: Float,
        roughness: Float,
        clearcoat: Float = 0,
        clearcoatRoughness: Float = 0.18,
        texture: TextureResource? = nil,
        normalTexture: TextureResource? = nil,
        roughnessTexture: TextureResource? = nil,
        textureScale: SIMD2<Float> = SIMD2(repeating: 1)
    ) -> PhysicallyBasedMaterial {
        var material = PhysicallyBasedMaterial()
        let materialTexture = texture.map(PhysicallyBasedMaterial.Texture.init)
        material.baseColor = .init(tint: color, texture: materialTexture)
        material.metallic = .init(scale: metallic)
        material.roughness = .init(
            scale: roughness,
            texture: roughnessTexture.map(PhysicallyBasedMaterial.Texture.init)
        )
        material.normal = .init(
            texture: normalTexture.map(PhysicallyBasedMaterial.Texture.init)
        )
        material.specular = .init(scale: 0.72)
        material.clearcoat = .init(scale: clearcoat)
        material.clearcoatRoughness = .init(scale: clearcoatRoughness)
        material.textureCoordinateTransform = .init(scale: textureScale)
        return material
    }

    private static func metalMaterial(color: UIColor) -> PhysicallyBasedMaterial {
        pbrMaterial(
            color: color,
            metallic: 0.92,
            roughness: 0.24,
            clearcoat: 0.24,
            clearcoatRoughness: 0.16
        )
    }

    private static func unlitBox(
        name: String,
        size: SIMD3<Float>,
        position: SIMD3<Float>,
        color: UIColor,
        cornerRadius: Float = 0
    ) -> ModelEntity {
        let entity = ModelEntity(
            mesh: .generateBox(size: size, cornerRadius: cornerRadius),
            materials: [UnlitMaterial(color: color)]
        )
        entity.name = name
        entity.position = position
        return entity
    }

    private static func imageLightIntensityExponent(for weather: RacingWeather) -> Float {
        switch weather {
        case .clear: 0.42
        case .rain: 0.18
        case .fog: 0.30
        case .storm: -0.08
        }
    }

    private static func color(from rgba: RGBAComponents) -> UIColor {
        UIColor(
            red: rgba.red,
            green: rgba.green,
            blue: rgba.blue,
            alpha: rgba.alpha
        )
    }

    private static func color(from rgb: SIMD3<Float>) -> UIColor {
        UIColor(
            red: CGFloat(rgb.x),
            green: CGFloat(rgb.y),
            blue: CGFloat(rgb.z),
            alpha: 1
        )
    }
}
