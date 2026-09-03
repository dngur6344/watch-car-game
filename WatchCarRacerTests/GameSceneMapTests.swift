import SpriteKit
import XCTest
@testable import WatchCarRacer

@MainActor
final class GameSceneMapTests: XCTestCase {
    private let landscapeSizes = [
        CGSize(width: 932, height: 430),
        CGSize(width: 667, height: 375),
    ]

    func testPrimaryMapArtUsesRequiredPNGTexturesAndStableCounts() throws {
        let library = try GameAssetLibrary()
        let scene = try makeScene(assetLibrary: library)

        let sky = try sprite(named: "map.sky.sky_horizon", in: scene)
        XCTAssertTrue(sky.texture === (try library.texture(named: "sky_horizon")))

        let road = try XCTUnwrap(
            scene.childNode(withName: "//map.road.asphalt") as? SKShapeNode
        )
        XCTAssertTrue(road.fillTexture === (try library.texture(named: "asphalt")))

        let laneContainer = try XCTUnwrap(scene.childNode(withName: "//map.lanes"))
        let lanes = laneContainer.children.compactMap { $0 as? SKSpriteNode }
        XCTAssertEqual(lanes.count, 36)
        XCTAssertEqual(laneContainer.children.count, lanes.count)
        for lane in lanes {
            XCTAssertTrue(lane.texture === (try library.texture(named: "lane_worn")))
            XCTAssertEqual(lane.size.width / lane.xScale, 5, accuracy: 0.000_01)
            XCTAssertEqual(lane.size.height / lane.yScale, 40, accuracy: 0.000_01)
            XCTAssertEqual(lane.anchorPoint, CGPoint(x: 0.5, y: 0.5))
        }

        let roadsideContainer = try XCTUnwrap(
            scene.childNode(withName: "//map.roadside")
        )
        let roadside = roadsideContainer.children.compactMap { $0 as? SKSpriteNode }
        XCTAssertEqual(roadside.count, 24)
        XCTAssertEqual(roadsideContainer.children.count, roadside.count)

        let logicalSizes = [
            "roadside_light": CGSize(width: 28, height: 56),
            "roadside_palm": CGSize(width: 48, height: 64),
            "roadside_marker": CGSize(width: 48, height: 64),
        ]
        for (textureName, logicalSize) in logicalSizes {
            let matching = roadside.filter { $0.name?.contains(".\(textureName).") == true }
            XCTAssertEqual(matching.count, 8, textureName)
            for prop in matching {
                XCTAssertTrue(
                    prop.texture === (try library.texture(named: textureName)),
                    textureName
                )
                XCTAssertEqual(
                    prop.size.width / prop.xScale,
                    logicalSize.width,
                    accuracy: 0.000_01,
                    textureName
                )
                XCTAssertEqual(
                    prop.size.height / prop.yScale,
                    logicalSize.height,
                    accuracy: 0.000_01,
                    textureName
                )
                XCTAssertEqual(prop.anchorPoint, CGPoint(x: 0.5, y: 0), textureName)
            }
        }

        let decalContainer = try XCTUnwrap(
            scene.childNode(withName: "//map.roadDecals")
        )
        let decals = decalContainer.children.compactMap { $0 as? SKSpriteNode }
        XCTAssertEqual(decals.count, 4)
        XCTAssertEqual(decalContainer.children.count, decals.count)
        for decal in decals {
            XCTAssertTrue(
                decal.texture === (try library.texture(named: "road_decal_chevrons"))
            )
        }

        let curbContainer = try XCTUnwrap(scene.childNode(withName: "//map.trackCurbs"))
        let curbs = curbContainer.children.compactMap { $0 as? SKShapeNode }
        XCTAssertEqual(curbs.count, GameScene.trackCurbSegmentCountPerSide * 2)
        XCTAssertTrue(curbs.allSatisfy { $0.path != nil })

        let guardrailContainer = try XCTUnwrap(
            scene.childNode(withName: "//map.guardrails")
        )
        let guardrails = guardrailContainer.children.compactMap { $0 as? SKShapeNode }
        XCTAssertEqual(guardrails.count, 2)
        XCTAssertTrue(guardrails.allSatisfy { $0.path != nil })

        XCTAssertFalse(scene.allDescendants.contains { $0.name == "map.sun" })
        XCTAssertFalse(scene.allDescendants.contains { $0.name == "map.horizon" })
        XCTAssertFalse(laneContainer.children.contains { $0 is SKShapeNode })
        XCTAssertFalse(roadsideContainer.children.contains { $0 is SKShapeNode })
    }

    func testSkyAspectAndAuthoredHorizonAlignWithoutSeamsAtBothLandscapeSizes() throws {
        for size in landscapeSizes {
            let library = try GameAssetLibrary()
            let scene = try makeScene(size: size, assetLibrary: library)
            let sky = try sprite(named: "map.sky.sky_horizon", in: scene)
            let texture = try library.texture(named: "sky_horizon")
            let projection = RoadProjection(
                screenSize: size,
                roadHalfWidth: scene.currentSnapshot.roadHalfWidth,
                maximumDistance: 52
            )

            XCTAssertEqual(
                sky.size.width / sky.size.height,
                texture.size().width / texture.size().height,
                accuracy: 0.000_001
            )
            XCTAssertLessThanOrEqual(sky.frame.minX, 0)
            XCTAssertGreaterThanOrEqual(sky.frame.maxX, size.width)
            XCTAssertGreaterThanOrEqual(sky.frame.maxY, size.height)

            let authoredHorizonY = sky.frame.minY
                + sky.size.height * GameScene.skyAuthoredHorizonFraction
            XCTAssertEqual(authoredHorizonY, projection.horizonY, accuracy: 0.000_01)
        }
    }

    func testAsphaltUsesTheUnchangedProjectedRoadPathBounds() throws {
        for size in landscapeSizes {
            let scene = try makeScene(size: size)
            let road = try XCTUnwrap(
                scene.childNode(withName: "//map.road.asphalt") as? SKShapeNode
            )
            let path = try XCTUnwrap(road.path)
            let projection = RoadProjection(
                screenSize: size,
                roadHalfWidth: scene.currentSnapshot.roadHalfWidth,
                maximumDistance: 52
            )

            XCTAssertEqual(
                path.boundingBox,
                CGRect(x: 0, y: 0, width: size.width, height: projection.horizonY)
            )
        }
    }

    func testLaneAndRoadsideProjectionContractsRemainExactAcrossSnapshots() throws {
        var configuration = GameSimulation.Configuration()
        configuration.firstSpawnDelay = 10_000
        let scene = try makeScene(configuration: configuration)
        scene.update(0)

        for separatorX in [-1.0, 0.0, 1.0] {
            assertProjectedLane(
                index: 3,
                separatorX: separatorX,
                in: scene,
                configuration: configuration
            )
        }
        assertProjectedRoadside(index: 7, in: scene, configuration: configuration)

        for frame in 1...30 {
            scene.update(Double(frame) * GameScene.fixedStep)
        }
        for separatorX in [-1.0, 0.0, 1.0] {
            assertProjectedLane(
                index: 3,
                separatorX: separatorX,
                in: scene,
                configuration: configuration
            )
        }
        assertProjectedRoadside(index: 7, in: scene, configuration: configuration)

        for frame in 31...120 {
            scene.update(Double(frame) * GameScene.fixedStep)
        }
        for separatorX in [-1.0, 0.0, 1.0] {
            assertProjectedLane(
                index: 3,
                separatorX: separatorX,
                in: scene,
                configuration: configuration
            )
        }
        assertProjectedRoadside(index: 7, in: scene, configuration: configuration)
    }

    func testChevronPositionsAreDeterministicAndDoNotDependOnSimulationSeed() throws {
        var configuration = GameSimulation.Configuration()
        configuration.firstSpawnDelay = 10_000
        let first = try makeScene(seed: 1, configuration: configuration)
        let second = try makeScene(seed: 999, configuration: configuration)

        first.update(0)
        second.update(0)
        for frame in 1...90 {
            let time = Double(frame) * GameScene.fixedStep
            first.update(time)
            second.update(time)
        }

        XCTAssertEqual(first.currentSnapshot, second.currentSnapshot)
        for index in 0..<4 {
            let firstNode = try sprite(
                named: "map.decal.road_decal_chevrons.\(index)",
                in: first
            )
            let secondNode = try sprite(
                named: "map.decal.road_decal_chevrons.\(index)",
                in: second
            )
            XCTAssertEqual(firstNode.position.x, secondNode.position.x, accuracy: 0.000_001)
            XCTAssertEqual(firstNode.position.y, secondNode.position.y, accuracy: 0.000_001)
            XCTAssertEqual(firstNode.xScale, secondNode.xScale, accuracy: 0.000_001)
            XCTAssertEqual(firstNode.yScale, secondNode.yScale, accuracy: 0.000_001)
            XCTAssertEqual(firstNode.zPosition, secondNode.zPosition, accuracy: 0.000_001)
            XCTAssertEqual(firstNode.isHidden, secondNode.isHidden)
        }
    }

    private func assertProjectedLane(
        index: Int,
        separatorX: Double,
        in scene: GameScene,
        configuration: GameSimulation.Configuration,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let separators = [-1.0, 0.0, 1.0]
        guard let separatorIndex = separators.firstIndex(of: separatorX) else {
            return XCTFail("Unknown lane separator", file: file, line: line)
        }
        guard let node = scene.childNode(
            withName: "//map.lane.lane_worn.\(separatorIndex).\(index)"
        ) as? SKSpriteNode else {
            return XCTFail("Missing lane sprite", file: file, line: line)
        }
        let snapshot = scene.currentSnapshot
        let roadProjection = RoadProjection(
            screenSize: scene.size,
            roadHalfWidth: snapshot.roadHalfWidth,
            maximumDistance: max(configuration.spawnDistance + 4, 52)
        )
        let projection = TrackPerspectiveProjection(
            road: roadProjection,
            travel: snapshot.distance
        )
        let spacing = 4.5
        let speedRange = max(configuration.maximumSpeed - configuration.initialSpeed, 0.001)
        let speedProgress = min(
            max((snapshot.speed - configuration.initialSpeed) / speedRange, 0),
            1
        )
        let markLength = 1.7 + speedProgress * 1.15
        let travel = snapshot.distance.truncatingRemainder(dividingBy: spacing)
        var distance = Double(index) * spacing - travel
        if distance < 0 {
            distance += spacing * 12
        }
        let lateral = separatorX * snapshot.laneWidth
        let nearPoint = projection.project(lateral: lateral, distance: distance)
        let farPoint = projection.project(lateral: lateral, distance: distance + markLength)
        let deltaX = farPoint.point.x - nearPoint.point.x
        let deltaY = farPoint.point.y - nearPoint.point.y
        let length = max(hypot(deltaX, deltaY), 1)

        XCTAssertEqual(
            node.position.x,
            (nearPoint.point.x + farPoint.point.x) / 2,
            accuracy: 0.000_05,
            file: file,
            line: line
        )
        XCTAssertEqual(
            node.position.y,
            (nearPoint.point.y + farPoint.point.y) / 2,
            accuracy: 0.000_05,
            file: file,
            line: line
        )
        XCTAssertEqual(node.xScale, max(nearPoint.scale, 0.2), accuracy: 0.000_01, file: file, line: line)
        XCTAssertEqual(node.yScale, length / 40, accuracy: 0.000_01, file: file, line: line)
        XCTAssertEqual(
            node.zRotation,
            -atan2(deltaX, deltaY),
            accuracy: 0.000_01,
            file: file,
            line: line
        )
        XCTAssertEqual(
            node.alpha,
            CGFloat(0.68 + speedProgress * 0.30),
            accuracy: 0.000_01,
            file: file,
            line: line
        )
        XCTAssertEqual(node.isHidden, distance > projection.maximumDistance, file: file, line: line)
    }

    private func assertProjectedRoadside(
        index: Int,
        in scene: GameScene,
        configuration: GameSimulation.Configuration,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let textureNames = ["roadside_light", "roadside_palm", "roadside_marker"]
        let textureName = textureNames[index % textureNames.count]
        guard let node = scene.childNode(
            withName: "//map.roadside.\(textureName).\(index)"
        ) as? SKSpriteNode else {
            return XCTFail("Missing roadside sprite", file: file, line: line)
        }
        let snapshot = scene.currentSnapshot
        let roadProjection = RoadProjection(
            screenSize: scene.size,
            roadHalfWidth: snapshot.roadHalfWidth,
            maximumDistance: max(configuration.spawnDistance + 4, 52)
        )
        let projection = TrackPerspectiveProjection(
            road: roadProjection,
            travel: snapshot.distance
        )
        let cycleLength = projection.maximumDistance + 10
        let parallax = 0.78 + Double(index % 3) * 0.09
        let travel = (snapshot.distance * parallax)
            .truncatingRemainder(dividingBy: cycleLength)
        var distance = 2.5 + Double(index) * 2.55 - travel
        while distance < 1.2 {
            distance += cycleLength
        }
        let side: Double = index.isMultiple(of: 2) ? -1 : 1
        let lateralOffset = 1.0 + Double(index % 4) * 0.26
        let projected = projection.project(
            lateral: side * (snapshot.roadHalfWidth + lateralOffset),
            distance: distance
        )

        XCTAssertEqual(node.position.x, projected.point.x, accuracy: 0.000_05, file: file, line: line)
        XCTAssertEqual(node.position.y, projected.point.y, accuracy: 0.000_05, file: file, line: line)
        XCTAssertEqual(node.xScale, projected.scale, accuracy: 0.000_01, file: file, line: line)
        XCTAssertEqual(node.yScale, projected.scale, accuracy: 0.000_01, file: file, line: line)
        XCTAssertEqual(
            node.zPosition,
            1 - projected.normalizedDepth,
            accuracy: 0.000_01,
            file: file,
            line: line
        )
        XCTAssertEqual(node.isHidden, distance > projection.maximumDistance, file: file, line: line)
    }

    private func makeScene(
        seed: UInt64 = 17,
        size: CGSize = CGSize(width: 844, height: 390),
        configuration: GameSimulation.Configuration = .init(),
        assetLibrary: GameAssetLibrary? = nil
    ) throws -> GameScene {
        let library = try assetLibrary ?? GameAssetLibrary()
        let appearance = try XCTUnwrap(
            VehicleCatalog.resolve(VehicleCatalog.defaultSelection)
        )
        let scene = try GameScene(
            seed: seed,
            configuration: configuration,
            appearance: appearance,
            assetLibrary: library
        )
        scene.size = size
        scene.didMove(to: SKView(frame: CGRect(origin: .zero, size: size)))
        return scene
    }

    private func sprite(named name: String, in scene: SKScene) throws -> SKSpriteNode {
        try XCTUnwrap(scene.childNode(withName: "//\(name)") as? SKSpriteNode)
    }
}

private extension SKNode {
    var allDescendants: [SKNode] {
        children + children.flatMap(\.allDescendants)
    }
}
