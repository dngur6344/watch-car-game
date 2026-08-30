import SpriteKit
import XCTest
@testable import WatchCarRacer

@MainActor
final class VehicleSpriteNodeTests: XCTestCase {
    func testAllTwentyFourAppearancesUseExpectedLayersAndTintOnlyPaintMask() throws {
        let assetLibrary = try GameAssetLibrary()

        for selection in VehicleCatalog.allSelections {
            let appearance = try XCTUnwrap(VehicleCatalog.resolve(selection))
            let node = try VehicleSpriteNode(
                appearance: appearance,
                assetLibrary: assetLibrary
            )
            let textures = appearance.vehicle.textures
            let expectedShadow = try assetLibrary.texture(named: textures.shadow)
            let expectedPaint = try assetLibrary.texture(named: textures.paint)
            let expectedDetails = try assetLibrary.texture(named: textures.details)

            XCTAssertEqual(node.appearance, appearance)
            XCTAssertEqual(node.children.count, 1)
            XCTAssertTrue(node.children.first === node.impactPresentationNode)
            XCTAssertEqual(node.impactPresentationNode.children.count, 2)
            XCTAssertTrue(node.shadowNode.parent === node.impactPresentationNode)
            XCTAssertTrue(node.bodyPresentationNode.parent === node.impactPresentationNode)
            XCTAssertEqual(node.bodyPresentationNode.children.count, 2)
            XCTAssertTrue(node.paintNode.parent === node.bodyPresentationNode)
            XCTAssertTrue(node.detailsNode.parent === node.bodyPresentationNode)
            XCTAssertTrue(node.shadowNode.texture === expectedShadow)
            XCTAssertTrue(node.paintNode.texture === expectedPaint)
            XCTAssertTrue(node.detailsNode.texture === expectedDetails)
            XCTAssertEqual(node.shadowNode.name, VehicleSpriteNode.shadowNodeName)
            XCTAssertEqual(node.paintNode.name, VehicleSpriteNode.paintNodeName)
            XCTAssertEqual(node.detailsNode.name, VehicleSpriteNode.detailsNodeName)

            for layer in [node.shadowNode, node.paintNode, node.detailsNode] {
                XCTAssertEqual(layer.size, appearance.vehicle.logicalRenderSize)
                XCTAssertEqual(
                    layer.anchorPoint,
                    CGPoint(
                        x: CGFloat(appearance.vehicle.pivot.x),
                        y: CGFloat(appearance.vehicle.pivot.y)
                    )
                )
                XCTAssertEqual(layer.position, .zero)
            }

            XCTAssertEqual(node.shadowNode.colorBlendFactor, 0)
            XCTAssertEqual(node.detailsNode.colorBlendFactor, 0)
            XCTAssertEqual(node.paintNode.colorBlendFactor, 1)
            assertPaintColor(node.paintNode.color, equals: appearance.color.rgba)
        }
    }

    func testPresentationSeparatesBodyDetailsShadowAndImpactTransforms() throws {
        let library = try GameAssetLibrary()
        let appearance = try XCTUnwrap(
            VehicleCatalog.resolve(VehicleCatalog.defaultSelection)
        )
        let node = try VehicleSpriteNode(appearance: appearance, assetLibrary: library)

        node.applyPresentation(speedProgress: 1, steering: 1, level: .balanced)

        XCTAssertEqual(
            node.bodyPresentationNode.zRotation,
            -VehicleSpriteNode.maximumBodyRoll,
            accuracy: 0.000_001
        )
        XCTAssertEqual(
            node.paintNode.position.x,
            VehicleSpriteNode.maximumPaintOffset,
            accuracy: 0.000_001
        )
        XCTAssertEqual(
            node.detailsNode.position.x,
            VehicleSpriteNode.maximumDetailsOffset,
            accuracy: 0.000_001
        )
        XCTAssertEqual(node.shadowNode.position.x, -3, accuracy: 0.000_001)
        XCTAssertEqual(node.shadowNode.position.y, -3.2, accuracy: 0.000_001)
        XCTAssertEqual(node.shadowNode.xScale, 0.915, accuracy: 0.000_001)
        XCTAssertEqual(node.shadowNode.yScale, 0.835, accuracy: 0.000_001)
        XCTAssertEqual(node.shadowNode.alpha, 0.80, accuracy: 0.000_001)
        XCTAssertEqual(node.impactPresentationNode.position, .zero)
        XCTAssertEqual(node.impactPresentationNode.zRotation, 0)

        node.applyPresentation(speedProgress: 1, steering: -1, level: .reduced)
        XCTAssertEqual(
            node.bodyPresentationNode.zRotation,
            VehicleSpriteNode.maximumBodyRoll * VehicleSpriteNode.reducedTransformMultiplier,
            accuracy: 0.000_001
        )
        XCTAssertEqual(
            node.detailsNode.position.x,
            -VehicleSpriteNode.maximumDetailsOffset
                * VehicleSpriteNode.reducedTransformMultiplier,
            accuracy: 0.000_001
        )

        node.applyPresentation(speedProgress: 1, steering: 1, level: .off)
        XCTAssertEqual(node.bodyPresentationNode.zRotation, 0, accuracy: 0.000_001)
        XCTAssertEqual(node.paintNode.position, .zero)
        XCTAssertEqual(node.detailsNode.position, .zero)
        XCTAssertEqual(node.shadowNode.position, .zero)
        XCTAssertEqual(node.shadowNode.xScale, 1, accuracy: 0.000_001)
        XCTAssertEqual(node.shadowNode.yScale, 1, accuracy: 0.000_001)
        XCTAssertGreaterThan(node.shadowNode.alpha, 0.58, "Opacity-only speed response remains")
    }

    func testTrafficVariantIsStableByObstacleIDAndBarrierUsesAuthoredTexture() throws {
        let assetLibrary = try GameAssetLibrary()
        let factory = try ObstacleSpriteFactory(assetLibrary: assetLibrary)

        for id in UInt64(0)...UInt64(7) {
            let expectedName = id.isMultiple(of: 2) ? "traffic_sedan" : "traffic_wagon"
            let obstacle = makeObstacle(id: id, kind: .trafficCar)
            let node = factory.makeNode(for: obstacle)
            let expectedTexture = try assetLibrary.texture(named: expectedName)

            XCTAssertEqual(
                ObstacleSpriteFactory.textureName(for: .trafficCar, obstacleID: id),
                expectedName
            )
            XCTAssertEqual(node.name, "obstacle.\(expectedName)")
            XCTAssertTrue(node.texture === expectedTexture)
            XCTAssertEqual(node.colorBlendFactor, 0)
            XCTAssertEqual(node.anchorPoint, CGPoint(x: 0.5, y: 0.5))
        }

        let barrier = factory.makeNode(for: makeObstacle(id: 77, kind: .barrier))
        let expectedBarrier = try assetLibrary.texture(
            named: ObstacleSpriteFactory.barrierTextureName
        )
        XCTAssertEqual(
            ObstacleSpriteFactory.textureName(for: .barrier, obstacleID: 77),
            ObstacleSpriteFactory.barrierTextureName
        )
        XCTAssertEqual(barrier.name, "obstacle.barrier_modular")
        XCTAssertTrue(barrier.texture === expectedBarrier)
        XCTAssertEqual(barrier.colorBlendFactor, 0)
        XCTAssertEqual(barrier.anchorPoint, CGPoint(x: 0.5, y: 0.5))
    }

    private func assertPaintColor(
        _ actual: UIColor,
        equals expected: RGBAComponents,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        XCTAssertTrue(
            actual.getRed(&red, green: &green, blue: &blue, alpha: &alpha),
            file: file,
            line: line
        )
        XCTAssertEqual(Double(red), expected.red, accuracy: 0.000_001, file: file, line: line)
        XCTAssertEqual(Double(green), expected.green, accuracy: 0.000_001, file: file, line: line)
        XCTAssertEqual(Double(blue), expected.blue, accuracy: 0.000_001, file: file, line: line)
        XCTAssertEqual(Double(alpha), expected.alpha, accuracy: 0.000_001, file: file, line: line)
    }

    private func makeObstacle(id: UInt64, kind: ObstacleKind) -> ObstacleSnapshot {
        ObstacleSnapshot(
            id: id,
            rowID: id,
            kind: kind,
            laneIndex: 1,
            x: 0,
            distance: 20,
            width: kind == .barrier ? 1.7 : 1.2,
            length: kind == .barrier ? 1.0 : 2.2,
            closingSpeed: 12,
            didAwardNearMiss: false
        )
    }
}
