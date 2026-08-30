import CryptoKit
import Foundation
import ImageIO
import RealityKit
import XCTest
@testable import WatchCarRacer

final class RacingWorldLayoutTests: XCTestCase {
    func testTrackTilesKeepConstantSpacingWhileTravelAdvances() {
        for travel in [0.0, 0.01, 5.5, 11.99, 12.01, 23.9, 24, 147.25] {
            let positions = (0..<RacingWorldLayout.trackTileCount).map {
                RacingWorldLayout.trackTileDistance(index: $0, travel: travel)
            }.sorted()

            for index in 1..<positions.count {
                XCTAssertEqual(
                    positions[index] - positions[index - 1],
                    RacingWorldLayout.trackTileLength,
                    accuracy: 0.000_1
                )
            }
        }
    }

    func testTrackTilesAdvanceContinuouslyAndOnlyRecycleBehindTheCamera() {
        let before = (0..<RacingWorldLayout.trackTileCount).map {
            RacingWorldLayout.trackTileDistance(index: $0, travel: 11.99)
        }
        let after = (0..<RacingWorldLayout.trackTileCount).map {
            RacingWorldLayout.trackTileDistance(index: $0, travel: 12.01)
        }
        let deltas = zip(before, after).map { $1 - $0 }
        let recycled = deltas.filter { $0 > RacingWorldLayout.trackTileLength }
        let continuous = deltas.filter { $0 <= RacingWorldLayout.trackTileLength }

        XCTAssertEqual(recycled.count, 1)
        XCTAssertEqual(continuous.count, RacingWorldLayout.trackTileCount - 1)
        for delta in continuous {
            XCTAssertEqual(delta, -0.02, accuracy: 0.000_1)
        }
        XCTAssertEqual(
            recycled[0],
            Float(RacingWorldLayout.trackTileCount) * RacingWorldLayout.trackTileLength - 0.02,
            accuracy: 0.000_1
        )
    }

    func testTrackNeverDropsBelowTheEnvironmentGroundAhead() {
        for travel in stride(from: 0.0, through: 240.0, by: 12.5) {
            for distance in stride(from: Float(0), through: Float(204), by: 6) {
                let placement = RacingWorldLayout.trackPlacement(
                    distance: distance,
                    travel: travel
                )
                XCTAssertGreaterThanOrEqual(
                    placement.position.y,
                    0,
                    "travel=\(travel), distance=\(distance)"
                )
            }
        }
    }

    func testTrackSurfacesOverlapAndExtendBeyondTheVisibleHorizon() {
        XCTAssertGreaterThan(
            RacingWorldLayout.trackSurfaceLength,
            RacingWorldLayout.trackTileLength
        )
        XCTAssertGreaterThan(
            RacingWorldLayout.trackUnderlayLength,
            RacingWorldLayout.trackSurfaceLength
        )

        let farthestCenter = RacingWorldLayout.trackTileDistance(
            index: RacingWorldLayout.trackTileCount - 1,
            travel: 0
        )
        XCTAssertGreaterThan(
            farthestCenter + RacingWorldLayout.trackUnderlayLength / 2,
            190
        )
    }

    func testMountainMassifsLeaveTheTrackCorridorOpen() {
        XCTAssertFalse(RacingWorldLayout.mountainMassifs.isEmpty)
        for massif in RacingWorldLayout.mountainMassifs {
            XCTAssertGreaterThanOrEqual(
                abs(massif.x) - massif.radius,
                RacingWorldLayout.mountainClearance
            )
            XCTAssertLessThan(massif.z, -120)
        }
    }

    func testVehicleScalesNormalizeAuthoredBodyLengths() throws {
        let scaledLengths = [
            2.90 * RacingWorldLayout.vehicleVisualScale(vehicleID: .rally),
            3.39 * RacingWorldLayout.vehicleVisualScale(vehicleID: .gt),
            3.06 * RacingWorldLayout.vehicleVisualScale(vehicleID: .angular),
            2.86 * RacingWorldLayout.vehicleVisualScale(vehicleID: nil),
        ]
        let spread = try XCTUnwrap(scaledLengths.max())
            - (try XCTUnwrap(scaledLengths.min()))

        XCTAssertLessThan(spread, 0.13)
    }

    func testVehicleDynamicsIncreaseBodyLoadWithSpeedAndSanitizeInput() {
        let calm = RacingWorldLayout.vehicleDynamicsPose(
            steering: 1,
            speedProgress: 0,
            travel: 12
        )
        let fast = RacingWorldLayout.vehicleDynamicsPose(
            steering: 1,
            speedProgress: 1,
            travel: 12
        )
        let invalid = RacingWorldLayout.vehicleDynamicsPose(
            steering: .nan,
            speedProgress: .infinity,
            travel: .nan
        )

        XCTAssertGreaterThan(abs(fast.roll), abs(calm.roll))
        XCTAssertGreaterThan(abs(fast.yaw), abs(calm.yaw))
        XCTAssertTrue(invalid.heave.isFinite)
        XCTAssertTrue(invalid.yaw.isFinite)
        XCTAssertTrue(invalid.roll.isFinite)
        XCTAssertTrue(invalid.pitch.isFinite)
    }

    func testImpactResponseRecoilsAwayFromObstacleAndScalesWithSpeed() {
        let rightImpact = RacingWorldLayout.impactResponse(
            playerX: 0,
            obstacleX: 1,
            closingSpeed: 24
        )
        let leftImpact = RacingWorldLayout.impactResponse(
            playerX: 0,
            obstacleX: -1,
            closingSpeed: 6
        )

        XCTAssertLessThan(rightImpact.recoilDirection, 0)
        XCTAssertGreaterThan(leftImpact.recoilDirection, 0)
        XCTAssertGreaterThan(rightImpact.recoilDistance, leftImpact.recoilDistance)
        XCTAssertGreaterThan(rightImpact.lift, leftImpact.lift)
    }

    func testObstacleMapsSimulationLateralAndDistanceOntoCurvedTrack() {
        let obstacle = ObstacleSnapshot(
            id: 4,
            rowID: 2,
            kind: .trafficCar,
            laneIndex: 2,
            x: 2,
            distance: 18.5,
            width: 0.9,
            length: 1.8,
            closingSpeed: 6,
            didAwardNearMiss: false
        )

        let track = RacingWorldLayout.trackPlacement(distance: 18.5, travel: 37)
        let obstaclePlacement = RacingWorldLayout.obstaclePlacement(obstacle, travel: 37)
        let localOffset = track.orientation.inverse.act(
            obstaclePlacement.position - track.position
        )

        XCTAssertEqual(localOffset.x, 2, accuracy: 0.000_1)
        XCTAssertEqual(localOffset.y, 0, accuracy: 0.000_1)
        XCTAssertEqual(localOffset.z, 0, accuracy: 0.000_1)
    }

    func testBarrierReceivesGroundClearance() {
        let obstacle = ObstacleSnapshot(
            id: 8,
            rowID: 3,
            kind: .barrier,
            laneIndex: 0,
            x: -2,
            distance: 10,
            width: 1.4,
            length: 0.7,
            closingSpeed: 12,
            didAwardNearMiss: false
        )

        let track = RacingWorldLayout.trackPlacement(distance: 10, travel: 52)
        let barrier = RacingWorldLayout.obstaclePlacement(obstacle, travel: 52)
        let localOffset = track.orientation.inverse.act(barrier.position - track.position)

        XCTAssertEqual(localOffset.x, -2, accuracy: 0.000_1)
        XCTAssertEqual(localOffset.y, 0.34, accuracy: 0.000_1)
        XCTAssertEqual(localOffset.z, 0, accuracy: 0.000_1)
    }

    func testTrackStartsAtPlayerAndDevelopsCurveAndElevationAhead() {
        let origin = RacingWorldLayout.trackPlacement(distance: 0, travel: 63)
        let ahead = RacingWorldLayout.trackPlacement(distance: 54, travel: 63)

        XCTAssertEqual(origin.position, .zero)
        XCTAssertNotEqual(ahead.position.x, 0, accuracy: 0.01)
        XCTAssertNotEqual(ahead.position.y, 0, accuracy: 0.01)
        XCTAssertEqual(ahead.position.z, -54, accuracy: 0.000_1)
    }

    func testSpeedProgressClampsToConfiguredRange() {
        XCTAssertEqual(
            RacingWorldLayout.speedProgress(speed: 4, initialSpeed: 12, maximumSpeed: 24),
            0
        )
        XCTAssertEqual(
            RacingWorldLayout.speedProgress(speed: 18, initialSpeed: 12, maximumSpeed: 24),
            0.5
        )
        XCTAssertEqual(
            RacingWorldLayout.speedProgress(speed: 50, initialSpeed: 12, maximumSpeed: 24),
            1
        )
    }

    func testCameraPoseWidensAndMovesCloserAtSpeed() {
        let calm = RacingWorldLayout.cameraPose(
            playerX: 0,
            steering: 0,
            speedProgress: 0,
            travel: 20
        )
        let fast = RacingWorldLayout.cameraPose(
            playerX: 0,
            steering: 0,
            speedProgress: 1,
            travel: 20
        )

        XCTAssertGreaterThan(fast.fieldOfView, calm.fieldOfView)
        XCTAssertLessThan(fast.position.z, calm.position.z)
        XCTAssertGreaterThan(fast.position.y, calm.position.y)
    }

    func testCameraPoseLooksIntoCurveAndLeansWithSteering() {
        let pose = RacingWorldLayout.cameraPose(
            playerX: 1.4,
            steering: 0.8,
            speedProgress: 0.75,
            travel: 63
        )
        let curve = RacingWorldLayout.trackPlacement(distance: 16, travel: 63)

        XCTAssertEqual(
            pose.target.x,
            Float(1.4) * 0.42 + curve.position.x * 0.56,
            accuracy: 0.000_1
        )
        XCTAssertLessThan(pose.roll, 0)
        XCTAssertTrue(pose.position.x.isFinite)
        XCTAssertTrue(pose.position.y.isFinite)
        XCTAssertTrue(pose.position.z.isFinite)
    }

    func testCameraPoseSanitizesInvalidInput() {
        let pose = RacingWorldLayout.cameraPose(
            playerX: .nan,
            steering: .infinity,
            speedProgress: .nan,
            travel: .nan
        )

        XCTAssertEqual(pose.fieldOfView, 53)
        XCTAssertEqual(pose.roll, 0)
        XCTAssertTrue(pose.target.x.isFinite)
        XCTAssertTrue(pose.target.y.isFinite)
        XCTAssertTrue(pose.target.z.isFinite)
    }

    func testSunlightDirectionMovesSmoothlyAndSanitizesInvalidInput() {
        let start = RacingSunlightModel.state(travel: 0, steering: 0)
        let nextFrame = RacingSunlightModel.state(travel: 0.5, steering: 0)
        let later = RacingSunlightModel.state(travel: 600, steering: 0.7)
        let invalid = RacingSunlightModel.state(travel: .nan, steering: .infinity)

        XCTAssertEqual(simd_length(start.direction), 1, accuracy: 0.000_1)
        XCTAssertLessThan(simd_distance(start.direction, nextFrame.direction), 0.001)
        XCTAssertGreaterThan(simd_distance(start.direction, later.direction), 0.01)
        XCTAssertGreaterThan(start.sourcePosition.y, start.target.y)
        XCTAssertGreaterThan(start.intensity, 16_000)
        XCTAssertLessThan(start.intensity, 21_000)

        for value in [
            invalid.sourcePosition.x,
            invalid.sourcePosition.y,
            invalid.sourcePosition.z,
            invalid.direction.x,
            invalid.direction.y,
            invalid.direction.z,
            invalid.intensity,
            invalid.glarePosition.x,
            invalid.glarePosition.y,
            invalid.glareOpacity,
        ] {
            XCTAssertTrue(value.isFinite)
        }
        XCTAssertTrue((0...1).contains(invalid.glarePosition.x))
        XCTAssertTrue((0...1).contains(invalid.glarePosition.y))
        XCTAssertTrue((0...1).contains(invalid.glareOpacity))
    }

    func testRacing3DAssetsMatchAuthoredHashesAndUSDZContract() throws {
        let expectedHashes = [
            "rally_racer.usda": "94e23ae4da95829c7f086c228a933008f437be2f94cbaf5bbaf058c6b9a51f13",
            "rally_racer.usdz": "753b0ca8836d3d3e0851189620b06afca8eaa1a306c638af458a019b1dba90e3",
            "gt_racer.usda": "2cb6bbdc27dbecd520964342229c4dad8c05f3260162eae3c6d55f965771c970",
            "gt_racer.usdz": "248920909bd2bbbcecf699893ea69faf54186fd7864ef327ddb41541095b73e0",
            "angular_racer.usda": "8de9be3e5949d626c75fde413f1c7fa43c7d49df8a0e0dc38f119fdece950bd6",
            "angular_racer.usdz": "6398420dc8311c92fefc57b8c517f490b0fcc72a6e458c54efe01aa9f7b67248",
            "traffic_sedan_3d.usda": "fa46f51149f3f39ba92859bdc9154a60dad6bb5afe8dbb5ff8c4822ea4c76f03",
            "traffic_sedan_3d.usdz": "1fdb141d516f08efb9dc8f80f32047b4f30467a637397cf876e75546245a008d",
            "track_barrier.usda": "2d5009eea05facd538fbf364a4e1a9c7a7618b70593df60f0b43bc68c3feb68f",
            "track_barrier.usdz": "911fc70d5e295cbd442a721af73d2b3e9a6369772aea24d075120833e36c57ea",
            "asphalt_normal.png": "c978c6d71292bb1bf012bd6e527cf74fe4ba758177fab50ad53f3634b8d9f571",
            "asphalt_roughness.png": "44bbd02430d7f5ca8b3f9f9830689c6203ec7814542e6a8b4a31386667ed8509",
        ]
        let provenance = try String(
            contentsOf: repositoryRoot.appendingPathComponent("docs/assets/provenance.md"),
            encoding: .utf8
        )

        for (filename, expectedHash) in expectedHashes {
            let data = try Data(contentsOf: racing3DDirectory.appendingPathComponent(filename))
            let actualHash = SHA256.hash(data: data)
                .map { String(format: "%02x", $0) }
                .joined()

            XCTAssertEqual(actualHash, expectedHash, filename)
            XCTAssertTrue(provenance.contains("`Racing3D/\(filename)`"), filename)
            XCTAssertTrue(provenance.contains("`\(actualHash)`"), filename)
        }

        let packageContracts = [
            "rally_racer.usdz": (source: "rally_racer.usda", root: "RallyRacer"),
            "gt_racer.usdz": (source: "gt_racer.usda", root: "GTRacer"),
            "angular_racer.usdz": (source: "angular_racer.usda", root: "AngularRacer"),
            "traffic_sedan_3d.usdz": (source: "traffic_sedan_3d.usda", root: "TrafficSedan"),
            "track_barrier.usdz": (source: "track_barrier.usda", root: "TrackBarrier"),
        ]
        var packagedBytes = 0
        for (filename, contract) in packageContracts {
            let package = try Data(
                contentsOf: racing3DDirectory.appendingPathComponent(filename)
            )
            packagedBytes += package.count
            XCTAssertEqual(Array(package.prefix(2)), [0x50, 0x4B], filename)
            XCTAssertLessThan(package.count, 128 * 1_024, filename)
            XCTAssertNotNil(package.range(of: Data(contract.source.utf8)), filename)
            XCTAssertNotNil(
                package.range(of: Data("defaultPrim = \"\(contract.root)\"".utf8)),
                filename
            )
            XCTAssertNotNil(package.range(of: Data("productionRevision = 2".utf8)), filename)
        }
        XCTAssertLessThan(packagedBytes, 512 * 1_024)
    }

    func testAsphaltPBRMapsAreSRGBEightBitRGBA() throws {
        for filename in ["asphalt_normal.png", "asphalt_roughness.png"] {
            let url = racing3DDirectory.appendingPathComponent(filename)
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
                return XCTFail("Could not decode \(filename)")
            }

            XCTAssertEqual(image.width, 1_024, filename)
            XCTAssertEqual(image.height, 1_024, filename)
            XCTAssertEqual(image.bitsPerComponent, 8, filename)
            XCTAssertEqual(image.bitsPerPixel, 32, filename)
            XCTAssertEqual(image.colorSpace?.name, CGColorSpace.sRGB, filename)
            XCTAssertTrue(image.alphaInfo.hasAlphaChannel, filename)
        }
    }

    func testRacing3DResourcesAreIOSOnlyAndResolveFromBuiltBundle() throws {
        let project = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "WatchCarRacer.xcodeproj/project.pbxproj"
            ),
            encoding: .utf8
        )
        let iosResources = try XCTUnwrap(
            projectSection(
                project,
                startingWith: "050000000000000000000003 /* Resources */ = {"
            )
        )
        let watchResources = try XCTUnwrap(
            projectSection(
                project,
                startingWith: "050000000000000000000013 /* Resources */ = {"
            )
        )

        for filename in [
            "rally_racer.usdz", "gt_racer.usdz", "angular_racer.usdz",
            "traffic_sedan_3d.usdz", "track_barrier.usdz",
            "asphalt_normal.png", "asphalt_roughness.png",
        ] {
            XCTAssertTrue(iosResources.contains("\(filename) in Resources"), filename)
            XCTAssertFalse(watchResources.contains(filename), filename)
            let url = URL(fileURLWithPath: filename)
            XCTAssertNotNil(
                Bundle.main.url(
                    forResource: url.deletingPathExtension().lastPathComponent,
                    withExtension: url.pathExtension
                ),
                filename
            )
        }
        XCTAssertFalse(iosResources.contains(".usda in Resources"))
        XCTAssertFalse(iosResources.contains("premium_racer.usdz"))
    }

    @MainActor
    func testEveryProductionUSDZLoadsAndExposesRequiredRuntimeParts() async throws {
        let contracts = [
            "rally_racer": ["paint_body_shell", "glass_canopy", "wheel_front_left", "paint_spoiler"],
            "gt_racer": ["paint_body_shell", "glass_canopy", "wheel_rear_right", "paint_ducktail"],
            "angular_racer": ["paint_body_shell", "glass_canopy", "wheel_front_right", "paint_spoiler"],
            "traffic_sedan_3d": ["paint_body_shell", "glass_canopy", "wheel_rear_left", "paint_rear_lip"],
            "track_barrier": ["dark_base", "panel_0", "reflector_4", "foot_right"],
        ]

        for (resource, requiredNames) in contracts {
            let url = try XCTUnwrap(
                Bundle.main.url(forResource: resource, withExtension: "usdz"),
                resource
            )
            let entity = try await Entity(contentsOf: url)
            for name in requiredNames {
                XCTAssertNotNil(entity.findEntity(named: name), "\(resource): \(name)")
            }
        }
    }

    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private var racing3DDirectory: URL {
        repositoryRoot.appendingPathComponent("WatchCarRacer/iOS/Resources/Racing3D")
    }

    private func projectSection(_ project: String, startingWith marker: String) -> String? {
        guard let start = project.range(of: marker)?.lowerBound,
              let end = project[start...].range(of: "\n\t\t};")?.upperBound else {
            return nil
        }
        return String(project[start..<end])
    }
}

private extension CGImageAlphaInfo {
    var hasAlphaChannel: Bool {
        switch self {
        case .first, .last, .premultipliedFirst, .premultipliedLast, .alphaOnly:
            true
        case .none, .noneSkipFirst, .noneSkipLast:
            false
        @unknown default:
            false
        }
    }
}
