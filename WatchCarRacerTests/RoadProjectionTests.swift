import CoreGraphics
import XCTest
@testable import WatchCarRacer

final class RoadProjectionTests: XCTestCase {
    private let landscapeSizes = [
        CGSize(width: 932, height: 430),
        CGSize(width: 667, height: 375),
    ]

    func testGreaterWorldDistanceMovesMonotonicallyTowardHorizon() {
        for size in landscapeSizes {
            let projection = RoadProjection(screenSize: size, roadHalfWidth: 3, maximumDistance: 48)
            let points = [0.0, 6, 18, 32, 48].map {
                projection.project(lateral: 0, distance: $0)
            }

            for pair in zip(points, points.dropFirst()) {
                XCTAssertLessThan(pair.0.point.y, pair.1.point.y)
                XCTAssertLessThan(pair.0.normalizedDepth, pair.1.normalizedDepth)
            }
            XCTAssertEqual(points.last!.point.y, projection.horizonY, accuracy: 0.000_001)
        }
    }

    func testLeftAndRightProjectionAreSymmetricAroundScreenCenter() {
        for size in landscapeSizes {
            let projection = RoadProjection(screenSize: size, roadHalfWidth: 3, maximumDistance: 48)
            for distance in [0.0, 12, 30, 48] {
                let left = projection.project(lateral: -1.75, distance: distance)
                let right = projection.project(lateral: 1.75, distance: distance)

                XCTAssertEqual(left.point.y, right.point.y, accuracy: 0.000_001)
                XCTAssertEqual(left.scale, right.scale, accuracy: 0.000_001)
                XCTAssertEqual(left.point.x + right.point.x, size.width, accuracy: 0.000_001)
            }
        }
    }

    func testNearObjectsAreLargerThanFarObjects() {
        for size in landscapeSizes {
            let projection = RoadProjection(screenSize: size, roadHalfWidth: 3, maximumDistance: 48)
            let near = projection.project(lateral: 0, distance: 0)
            let middle = projection.project(lateral: 0, distance: 24)
            let far = projection.project(lateral: 0, distance: 48)

            XCTAssertGreaterThan(near.scale, middle.scale)
            XCTAssertGreaterThan(middle.scale, far.scale)
            XCTAssertEqual(near.scale, 1, accuracy: 0.000_001)
            XCTAssertEqual(far.scale, 0.16, accuracy: 0.000_001)
        }
    }

    func testRoadBoundariesRemainInsideScreenAtRepresentativeDepths() {
        for size in landscapeSizes {
            let projection = RoadProjection(screenSize: size, roadHalfWidth: 3, maximumDistance: 48)
            for distance in [0.0, 4, 12, 24, 48] {
                let left = projection.project(lateral: -3, distance: distance).point
                let right = projection.project(lateral: 3, distance: distance).point

                XCTAssertGreaterThanOrEqual(left.x, 0)
                XCTAssertLessThanOrEqual(right.x, size.width)
                XCTAssertGreaterThanOrEqual(left.y, 0)
                XCTAssertLessThanOrEqual(right.y, size.height)
                XCTAssertLessThan(left.x, right.x)
            }

            XCTAssertEqual(projection.project(lateral: -3, distance: 0).point.x, 0, accuracy: 0.000_001)
            XCTAssertEqual(
                projection.project(lateral: 3, distance: 0).point.x,
                size.width,
                accuracy: 0.000_001
            )
        }
    }

    func testRoadsideProjectionCanExtendBeyondTrackEdgeWithoutAffectingRoadBounds() {
        let projection = RoadProjection(
            screenSize: landscapeSizes[0],
            roadHalfWidth: 3,
            maximumDistance: 48
        )
        let edge = projection.project(lateral: 3, distance: 12)
        let roadside = projection.project(lateral: 4.2, distance: 12)

        XCTAssertGreaterThan(roadside.point.x, edge.point.x)
        XCTAssertEqual(roadside.point.y, edge.point.y, accuracy: 0.000_001)
        XCTAssertEqual(roadside.scale, edge.scale, accuracy: 0.000_001)
    }

    func testTrackPerspectiveBendsSharedCenterlineWhileKeepingRoadEdgesVisible() {
        for size in landscapeSizes {
            let road = RoadProjection(
                screenSize: size,
                roadHalfWidth: 3,
                maximumDistance: 48
            )
            let track = TrackPerspectiveProjection(road: road, travel: 0)

            XCTAssertEqual(track.centerOffset(at: 0), 0, accuracy: 0.000_001)
            XCTAssertNotEqual(track.centerOffset(at: 48), 0, accuracy: 0.000_001)

            for distance in [0.0, 6, 18, 32, 48] {
                let left = track.project(lateral: -3, distance: distance).point
                let center = track.project(lateral: 0, distance: distance).point
                let right = track.project(lateral: 3, distance: distance).point
                XCTAssertGreaterThanOrEqual(left.x, 0)
                XCTAssertLessThanOrEqual(right.x, size.width)
                XCTAssertLessThan(left.x, center.x)
                XCTAssertLessThan(center.x, right.x)
            }
        }
    }

    func testTrackHeadingIsFiniteBoundedAndChangesAsTrackAdvances() {
        let road = RoadProjection(
            screenSize: landscapeSizes[0],
            roadHalfWidth: 3,
            maximumDistance: 52
        )
        let first = TrackPerspectiveProjection(road: road, travel: 0)
        let later = TrackPerspectiveProjection(road: road, travel: 180)
        let firstHeading = first.heading(at: 4, sampleLength: 5)
        let laterHeading = later.heading(at: 4, sampleLength: 5)

        XCTAssertTrue(firstHeading.isFinite)
        XCTAssertTrue(laterHeading.isFinite)
        XCTAssertLessThanOrEqual(abs(firstHeading), 0.22)
        XCTAssertLessThanOrEqual(abs(laterHeading), 0.22)
        XCTAssertNotEqual(firstHeading, laterHeading, accuracy: 0.000_001)
    }
}
