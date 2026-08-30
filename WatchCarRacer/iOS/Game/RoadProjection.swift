import CoreGraphics
import Foundation

struct ProjectedRoadPoint: Equatable {
    let point: CGPoint
    let scale: CGFloat
    let normalizedDepth: CGFloat
}

struct RoadProjection: Equatable {
    static let maximumNormalizedLateral = 1.55

    let screenSize: CGSize
    let roadHalfWidth: Double
    let maximumDistance: Double

    init(
        screenSize: CGSize,
        roadHalfWidth: Double,
        maximumDistance: Double = 52
    ) {
        self.screenSize = CGSize(
            width: max(screenSize.width, 1),
            height: max(screenSize.height, 1)
        )
        self.roadHalfWidth = max(roadHalfWidth, .leastNonzeroMagnitude)
        self.maximumDistance = max(maximumDistance, .leastNonzeroMagnitude)
    }

    var horizonY: CGFloat {
        screenSize.height * 0.70
    }

    func project(lateral: Double, distance: Double) -> ProjectedRoadPoint {
        let normalizedLateral = min(
            max(lateral / roadHalfWidth, -Self.maximumNormalizedLateral),
            Self.maximumNormalizedLateral
        )
        let depth = projectedDepth(for: distance)
        let halfWidth = roadScreenHalfWidth(at: distance)
        let nearY = screenSize.height * 0.14
        let y = nearY + (horizonY - nearY) * depth
        let scale = 1 + (0.16 - 1) * depth

        return ProjectedRoadPoint(
            point: CGPoint(
                x: screenSize.width / 2 + CGFloat(normalizedLateral) * halfWidth,
                y: y
            ),
            scale: scale,
            normalizedDepth: depth
        )
    }

    func roadScreenHalfWidth(at distance: Double) -> CGFloat {
        let depth = projectedDepth(for: distance)
        let nearHalfWidth = screenSize.width / 2
        let horizonHalfWidth = screenSize.width * 0.105
        return nearHalfWidth + (horizonHalfWidth - nearHalfWidth) * depth
    }

    private func projectedDepth(for distance: Double) -> CGFloat {
        let finiteDistance = distance.isFinite ? distance : 0
        let normalized = min(max(finiteDistance / maximumDistance, 0), 1)
        return CGFloat(sqrt(normalized))
    }
}

/// Presentation-only curve layered on top of the deterministic road projection.
/// Gameplay continues to use the same lateral/distance coordinates while every
/// track visual shares one smoothly moving centerline.
struct TrackPerspectiveProjection: Equatable {
    let road: RoadProjection
    let travel: Double
    let maximumCurveOffset: CGFloat

    init(
        road: RoadProjection,
        travel: Double,
        maximumCurveOffset: CGFloat? = nil
    ) {
        self.road = road
        self.travel = travel.isFinite ? travel : 0
        let requested = maximumCurveOffset ?? road.screenSize.width * 0.145
        self.maximumCurveOffset = min(
            max(requested.isFinite ? requested : 0, 0),
            road.screenSize.width * 0.20
        )
    }

    var horizonY: CGFloat {
        road.horizonY
    }

    var maximumDistance: Double {
        road.maximumDistance
    }

    func project(lateral: Double, distance: Double) -> ProjectedRoadPoint {
        let projected = road.project(lateral: lateral, distance: distance)
        return ProjectedRoadPoint(
            point: CGPoint(
                x: projected.point.x + centerOffset(at: distance),
                y: projected.point.y
            ),
            scale: projected.scale,
            normalizedDepth: projected.normalizedDepth
        )
    }

    func centerOffset(at distance: Double) -> CGFloat {
        let safeDistance = min(max(distance.isFinite ? distance : 0, 0), maximumDistance)
        guard safeDistance > 0, maximumCurveOffset > 0 else { return 0 }

        let normalizedDistance = safeDistance / maximumDistance
        let basePhase = travel * 0.017
        let curve = (sin(basePhase + normalizedDistance * 2.05) - sin(basePhase)) * 0.5
        let depth = road.project(lateral: 0, distance: safeDistance).normalizedDepth
        let requested = CGFloat(curve) * maximumCurveOffset * depth
        let availableMargin = max(
            road.screenSize.width / 2 - road.roadScreenHalfWidth(at: safeDistance),
            0
        ) * 0.82
        return min(max(requested, -availableMargin), availableMargin)
    }

    /// Rotation for sprites authored pointing toward the horizon (+Y).
    func heading(at distance: Double, sampleLength: Double = 1.5) -> CGFloat {
        let safeSample = max(sampleLength.isFinite ? sampleLength : 1.5, 0.25)
        let nearDistance = min(max(distance.isFinite ? distance : 0, 0), maximumDistance)
        let farDistance = min(nearDistance + safeSample, maximumDistance)
        guard farDistance > nearDistance else { return 0 }

        let near = project(lateral: 0, distance: nearDistance).point
        let far = project(lateral: 0, distance: farDistance).point
        let angle = -atan2(far.x - near.x, far.y - near.y)
        return min(max(angle.isFinite ? angle : 0, -0.22), 0.22)
    }
}
