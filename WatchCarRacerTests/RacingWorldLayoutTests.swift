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

    func testTrackProfilesProduceDistinctCurvesAndElevation() {
        let coastal = RacingWorldLayout.trackPlacement(
            distance: 54,
            travel: 63,
            track: .coastal
        )
        let alpine = RacingWorldLayout.trackPlacement(
            distance: 54,
            travel: 63,
            track: .alpine
        )
        let desert = RacingWorldLayout.trackPlacement(
            distance: 54,
            travel: 63,
            track: .desert
        )

        XCTAssertGreaterThan(simd_distance(coastal.position, alpine.position), 0.5)
        XCTAssertGreaterThan(simd_distance(coastal.position, desert.position), 0.5)
        XCTAssertGreaterThan(simd_distance(alpine.position, desert.position), 0.5)
        XCTAssertEqual(coastal.position.z, alpine.position.z, accuracy: 0.000_1)
        XCTAssertEqual(alpine.position.z, desert.position.z, accuracy: 0.000_1)
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
            Float(1.4) * 0.38 + curve.position.x * 0.62,
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

    func testCinematicSpeedIntensityRespectsAccessibilityAndClampsInput() {
        let calm = RacingWorldLayout.cinematicSpeedIntensity(
            speedProgress: 0,
            effectLevel: .balanced
        )
        let fast = RacingWorldLayout.cinematicSpeedIntensity(
            speedProgress: 1,
            effectLevel: .balanced
        )
        let reduced = RacingWorldLayout.cinematicSpeedIntensity(
            speedProgress: 1,
            effectLevel: .reduced
        )
        let disabled = RacingWorldLayout.cinematicSpeedIntensity(
            speedProgress: 1,
            effectLevel: .off
        )
        let invalid = RacingWorldLayout.cinematicSpeedIntensity(
            speedProgress: .nan,
            effectLevel: .balanced
        )

        XCTAssertEqual(calm, 0)
        XCTAssertEqual(fast, 1, accuracy: 0.000_1)
        XCTAssertGreaterThan(fast, reduced)
        XCTAssertGreaterThan(reduced, 0)
        XCTAssertEqual(disabled, 0)
        XCTAssertEqual(invalid, 0)
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
        XCTAssertGreaterThan(start.intensity, 13_000)
        XCTAssertLessThan(start.intensity, 17_000)
        XCTAssertGreaterThan(start.rimIntensity, 3_000)
        XCTAssertLessThan(start.rimIntensity, 4_500)

        for value in [
            invalid.sourcePosition.x,
            invalid.sourcePosition.y,
            invalid.sourcePosition.z,
            invalid.direction.x,
            invalid.direction.y,
            invalid.direction.z,
            invalid.intensity,
            invalid.rimSourcePosition.x,
            invalid.rimSourcePosition.y,
            invalid.rimSourcePosition.z,
            invalid.rimColor.x,
            invalid.rimColor.y,
            invalid.rimColor.z,
            invalid.rimIntensity,
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

    func testWeatherChangesSunlightAndTrackCatalogIsComplete() {
        XCTAssertEqual(RacingTrack.allCases.count, 3)
        XCTAssertEqual(RacingWeather.allCases.count, 4)

        let clear = RacingSunlightModel.state(
            travel: 120,
            steering: 0,
            environment: RacingEnvironmentSelection(track: .coastal, weather: .clear)
        )
        let rain = RacingSunlightModel.state(
            travel: 120,
            steering: 0,
            environment: RacingEnvironmentSelection(track: .coastal, weather: .rain)
        )
        let storm = RacingSunlightModel.state(
            travel: 120,
            steering: 0,
            environment: RacingEnvironmentSelection(track: .desert, weather: .storm)
        )

        XCTAssertLessThan(rain.intensity, clear.intensity)
        XCTAssertLessThan(storm.intensity, rain.intensity)
        XCTAssertLessThan(rain.glareOpacity, clear.glareOpacity)
        XCTAssertLessThan(storm.glareOpacity, rain.glareOpacity)
        XCTAssertNotEqual(storm.color, clear.color)
    }

    func testRacing3DAssetsMatchAuthoredHashesAndUSDZContract() throws {
        let expectedHashes = [
            "rally_racer.usda": "78d050e14ced0f760bb9c9890ac07bb2a9e73078bc91a92e6304394a93396a7f",
            "rally_racer.usdz": "be6c9cbe491dfb49d2ffb1f9df693801fbabbb2a6bd35bef36af293f85a802c7",
            "gt_racer.usda": "d565b0533610899661397a2cd638ac9cce22988945d2f22adb7bd294a7896ccc",
            "gt_racer.usdz": "a063100e6a9f3c98e14c7d1589a9b8fbbedffe3e9645ca7bd9ec8e8e2c820832",
            "angular_racer.usda": "16387b335acda03874ae4000ede6b87944bfe561a5222ed1a73556fa176d30a3",
            "angular_racer.usdz": "3534290018452fb5ff0c166e35f1b2e6581024bbf64eaa95c5b59240ec8e5ca6",
            "traffic_sedan_3d.usda": "dd6e027c81a15be7c685f37bf908894ddb918cefadbe11ce26198a113a3e4327",
            "traffic_sedan_3d.usdz": "e16125cf69a140ef44593d25028b57983e5d89bb94f5ce9711dcc88cb6f7fb26",
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
            let revision = filename == "track_barrier.usdz" ? 2 : 3
            XCTAssertNotNil(
                package.range(of: Data("productionRevision = \(revision)".utf8)),
                filename
            )
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
            "rally_racer": ["paint_body_shell", "glass_canopy", "wheel_front_left", "paint_spoiler", "rear_light_recess", "tire_sidewall", "rim_outer", "interior_cockpit"],
            "gt_racer": ["paint_body_shell", "glass_canopy", "wheel_rear_right", "paint_ducktail", "rear_light_recess", "tire_sidewall", "rim_outer", "interior_cockpit"],
            "angular_racer": ["paint_body_shell", "glass_canopy", "wheel_front_right", "paint_spoiler", "rear_light_recess", "tire_sidewall", "rim_outer", "interior_cockpit"],
            "traffic_sedan_3d": ["paint_body_shell", "glass_canopy", "wheel_rear_left", "paint_rear_lip", "rear_light_recess", "tire_sidewall", "rim_outer"],
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
