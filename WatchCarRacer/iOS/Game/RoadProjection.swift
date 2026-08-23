import CoreGraphics
import Foundation

struct ProjectedRoadPoint: Equatable {
    let point: CGPoint
    let scale: CGFloat
    let normalizedDepth: CGFloat
}

struct RoadProjection: Equatable {
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
        let normalizedLateral = min(max(lateral / roadHalfWidth, -1), 1)
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
