import SpriteKit
import XCTest
@testable import WatchCarRacer

@MainActor
final class GameScenePresentationTests: XCTestCase {
    private let sceneSize = CGSize(width: 844, height: 390)

    func testSpeedAndSteeringDriveSeparatedVehicleShadowAndCenteredCameraTransforms() throws {
        let scene = try makeScene()
        scene.setAccessibilityPolicy(makePolicy())
        scene.renderPresentationForTesting(
            speed: scene.configuration.maximumSpeed,
            steering: 1,
            distance: 120
        )

        let diagnostics = scene.presentationDiagnostics
        XCTAssertEqual(
            diagnostics.bodyRotation,
            -VehicleSpriteNode.maximumBodyRoll,
            accuracy: 0.000_001
        )
        XCTAssertEqual(
            diagnostics.paintOffset.x,
            VehicleSpriteNode.maximumPaintOffset,
            accuracy: 0.000_001
        )
        XCTAssertEqual(
            diagnostics.detailsOffset.x,
            VehicleSpriteNode.maximumDetailsOffset,
            accuracy: 0.000_001
        )
        XCTAssertEqual(diagnostics.shadowPosition.x, -3, accuracy: 0.000_001)
        XCTAssertEqual(diagnostics.shadowPosition.y, -3.2, accuracy: 0.000_001)
        XCTAssertEqual(diagnostics.shadowScale.x, 0.915, accuracy: 0.000_001)
        XCTAssertEqual(diagnostics.shadowScale.y, 0.835, accuracy: 0.000_001)
        XCTAssertEqual(diagnostics.shadowAlpha, 0.80, accuracy: 0.000_001)

        let center = CGPoint(x: sceneSize.width / 2, y: sceneSize.height / 2)
        XCTAssertEqual(diagnostics.continuousCameraScale, 1.018, accuracy: 0.000_001)
        XCTAssertEqual(
            center.x * diagnostics.continuousCameraScale
                + diagnostics.continuousCameraPosition.x,
            center.x - 3.5,
            accuracy: 0.000_01
        )
        XCTAssertEqual(
            center.y * diagnostics.continuousCameraScale
                + diagnostics.continuousCameraPosition.y,
            center.y - 2.5,
            accuracy: 0.000_01
        )
        XCTAssertEqual(diagnostics.impactCameraPosition, .zero)

        let continuous = try XCTUnwrap(
            scene.childNode(withName: "//presentation.camera.continuous")
        )
        let impact = try XCTUnwrap(
            scene.childNode(withName: "//presentation.camera.impact")
        )
        scene.present(makeNearMiss(side: .right, grade: .strong, id: 1))
        XCTAssertNotNil(impact.action(forKey: "feedbackMotion"))
        XCTAssertNil(continuous.action(forKey: "feedbackMotion"))

        scene.renderPresentationForTesting(
            speed: scene.configuration.maximumSpeed,
            steering: -1,
            distance: 121
        )
        XCTAssertNotNil(
            impact.action(forKey: "feedbackMotion"),
            "Final/crashed frame rendering must not overwrite impact presentation"
        )
        XCTAssertEqual(
            scene.presentationDiagnostics.bodyRotation,
            VehicleSpriteNode.maximumBodyRoll,
            accuracy: 0.000_001
        )
    }

    func testDirectionalNearMissEdgeAndGradeRemainDistinctWithRawBonusText() throws {
        let cases: [(FeedbackSide, NearMissFeedbackGrade, UInt64)] = [
            (.left, .standard, 1),
            (.center, .strong, 2),
            (.right, .standard, 3),
        ]

        var standardAlpha: CGFloat?
        var strongAlpha: CGFloat?
        for (side, grade, id) in cases {
            let scene = try makeScene()
            scene.present(makeNearMiss(side: side, grade: grade, id: id))
            let diagnostics = scene.presentationDiagnostics

            XCTAssertEqual(diagnostics.visibleNearMissSide, side)
            XCTAssertEqual(diagnostics.visibleNearMissGrade, grade)
            XCTAssertEqual(diagnostics.visibleScoreTexts, ["NEAR MISS +100"])
            if grade == .strong {
                XCTAssertEqual(diagnostics.visibleEdgeLineWidth, 3, accuracy: 0.000_001)
                strongAlpha = diagnostics.visibleEdgeAlpha
            } else {
                XCTAssertEqual(diagnostics.visibleEdgeLineWidth, 0, accuracy: 0.000_001)
                standardAlpha = diagnostics.visibleEdgeAlpha
            }
        }

        XCTAssertGreaterThan(try XCTUnwrap(strongAlpha), try XCTUnwrap(standardAlpha))
    }

    func testAccessibilityPolicyTableControlsTransformsPoolsOpacityAndStaticSubstitutes() throws {
        struct Case {
            let intensity: SensoryEffectIntensity
            let reduceMotion: Bool
            let reduceTransparency: Bool
            let transformMultiplier: CGFloat
            let streaks: Int
            let roadLights: Int
            let fog: Int
            let debris: Int
            let scoreScale: CGFloat
            let minimumEdgeAlpha: CGFloat
        }

        let cases = [
            Case(
                intensity: .balanced,
                reduceMotion: false,
                reduceTransparency: false,
                transformMultiplier: 1,
                streaks: 20,
                roadLights: 12,
                fog: 6,
                debris: 18,
                scoreScale: 0.82,
                minimumEdgeAlpha: 0.62
            ),
            Case(
                intensity: .reduced,
                reduceMotion: false,
                reduceTransparency: false,
                transformMultiplier: 0.45,
                streaks: 10,
                roadLights: 6,
                fog: 3,
                debris: 9,
                scoreScale: 0.919,
                minimumEdgeAlpha: 0.62
            ),
            Case(
                intensity: .balanced,
                reduceMotion: true,
                reduceTransparency: false,
                transformMultiplier: 0,
                streaks: 0,
                roadLights: 0,
                fog: 6,
                debris: 0,
                scoreScale: 1,
                minimumEdgeAlpha: 0.62
            ),
            Case(
                intensity: .balanced,
                reduceMotion: false,
                reduceTransparency: true,
                transformMultiplier: 1,
                streaks: 20,
                roadLights: 0,
                fog: 0,
                debris: 18,
                scoreScale: 0.82,
                minimumEdgeAlpha: 0.87
            ),
            Case(
                intensity: .balanced,
                reduceMotion: true,
                reduceTransparency: true,
                transformMultiplier: 0,
                streaks: 0,
                roadLights: 0,
                fog: 0,
                debris: 0,
                scoreScale: 1,
                minimumEdgeAlpha: 0.87
            ),
        ]

        for (index, testCase) in cases.enumerated() {
            let scene = try makeScene()
            let policy = makePolicy(
                intensity: testCase.intensity,
                reduceMotion: testCase.reduceMotion,
                reduceTransparency: testCase.reduceTransparency
            )
            scene.setAccessibilityPolicy(policy)
            scene.renderPresentationForTesting(
                speed: scene.configuration.maximumSpeed,
                steering: 1,
                distance: 100
            )
            let movingFogPositions = scene.presentationDiagnostics.fogBandPositions
            scene.renderPresentationForTesting(
                speed: scene.configuration.maximumSpeed,
                steering: 1,
                distance: 180
            )
            var diagnostics = scene.presentationDiagnostics

            XCTAssertEqual(
                diagnostics.bodyRotation,
                -VehicleSpriteNode.maximumBodyRoll * testCase.transformMultiplier,
                accuracy: 0.000_001,
                "case \(index)"
            )
            XCTAssertEqual(
                diagnostics.continuousCameraScale,
                1 + 0.018 * testCase.transformMultiplier,
                accuracy: 0.000_001,
                "case \(index)"
            )
            XCTAssertEqual(diagnostics.activeEdgeStreakCount, testCase.streaks, "case \(index)")
            XCTAssertEqual(diagnostics.activeRoadLightCount, testCase.roadLights, "case \(index)")
            XCTAssertEqual(diagnostics.activeFogBandCount, testCase.fog, "case \(index)")
            if testCase.reduceMotion, !testCase.reduceTransparency {
                XCTAssertEqual(
                    diagnostics.fogBandPositions,
                    movingFogPositions,
                    "Reduce Motion fog must remain static"
                )
            }

            scene.present(makeNearMiss(side: .left, grade: .standard, id: UInt64(index + 10)))
            diagnostics = scene.presentationDiagnostics
            XCTAssertEqual(
                try XCTUnwrap(diagnostics.visibleScoreScale),
                testCase.scoreScale,
                accuracy: 0.000_001
            )
            XCTAssertGreaterThanOrEqual(
                diagnostics.visibleEdgeAlpha,
                testCase.minimumEdgeAlpha,
                "case \(index)"
            )
            XCTAssertEqual(diagnostics.visibleScoreTexts, ["NEAR MISS +100"])

            scene.present(makeCollision(id: UInt64(index + 100)))
            diagnostics = scene.presentationDiagnostics
            XCTAssertEqual(diagnostics.activeDebrisCount, 0, "case \(index)")
            XCTAssertEqual(diagnostics.scheduledDebrisCount, testCase.debris, "case \(index)")
            XCTAssertGreaterThan(diagnostics.flashAlpha, 0, "Static collision flash remains")
        }
    }

    func testSixThousandFramesAndFeedbackRetryCyclesStayWithinFixedBoundsAndCleanUp() throws {
        var configuration = GameSimulation.Configuration()
        configuration.firstSpawnDelay = 10_000
        configuration.difficultyRampDuration = 2
        let first = try makeScene(seed: 909, configuration: configuration)
        let second = try makeScene(seed: 909, configuration: configuration)
        first.steeringProvider = { frame in sin(frame * 91) }
        second.steeringProvider = { frame in sin(frame * 91) }

        first.update(0)
        second.update(0)
        for frame in 1...6_000 {
            let time = Double(frame) * GameScene.fixedStep
            first.update(time)
            second.update(time)
            if frame.isMultiple(of: 300) {
                assertFixedBounds(first.presentationDiagnostics)
                assertFixedBounds(second.presentationDiagnostics)
            }
        }

        XCTAssertEqual(first.currentSnapshot, second.currentSnapshot)
        XCTAssertEqual(
            first.presentationDiagnostics.edgeStreakPositions,
            second.presentationDiagnostics.edgeStreakPositions
        )
        XCTAssertEqual(
            first.presentationDiagnostics.roadLightPositions,
            second.presentationDiagnostics.roadLightPositions
        )
        XCTAssertEqual(
            first.presentationDiagnostics.fogBandPositions,
            second.presentationDiagnostics.fogBandPositions
        )

        for index in 0..<100 {
            first.present(
                makeNearMiss(
                    side: index % 3 == 0 ? .left : (index % 3 == 1 ? .center : .right),
                    grade: index.isMultiple(of: 2) ? .standard : .strong,
                    id: UInt64(1_000 + index)
                )
            )
            assertFixedBounds(first.presentationDiagnostics)
        }
        XCTAssertEqual(first.presentationDiagnostics.unexpectedFeedbackNodeCount, 0)

        for cycle in 0..<10 {
            first.present(makeCollision(id: UInt64(2_000 + cycle)))
            XCTAssertLessThanOrEqual(
                first.presentationDiagnostics.scheduledDebrisCount,
                GameScene.maximumCollisionDebrisCount
            )
            first.reset(seed: UInt64(909 + cycle))
            let diagnostics = first.presentationDiagnostics
            assertFixedBounds(diagnostics)
            XCTAssertEqual(diagnostics.activeDebrisCount, 0)
            XCTAssertEqual(diagnostics.scheduledDebrisCount, 0)
            XCTAssertEqual(diagnostics.nodesWithActions, 0)
            XCTAssertEqual(diagnostics.unexpectedFeedbackNodeCount, 0)
            XCTAssertTrue(diagnostics.visibleScoreTexts.isEmpty)
        }

        first.present(makeNearMiss(side: .right, grade: .strong, id: 9_001))
        first.present(makeCollision(id: 9_002))
        XCTAssertGreaterThan(first.presentationDiagnostics.nodesWithActions, 0)
        first.stopPresentation()
        let stopped = first.presentationDiagnostics
        XCTAssertEqual(stopped.nodesWithActions, 0)
        XCTAssertEqual(stopped.activeDebrisCount, 0)
        XCTAssertEqual(stopped.unexpectedFeedbackNodeCount, 0)
        XCTAssertTrue(stopped.visibleScoreTexts.isEmpty)
    }

    func testCollisionActionsEncodeHitStopRecoilSettleAndCleanupTimeline() throws {
        let scene = try makeScene()
        scene.present(makeCollision(id: 8_001, side: .left))

        let impactCamera = try XCTUnwrap(
            scene.childNode(withName: "//presentation.camera.impact")
        )
        let vehicleImpact = try XCTUnwrap(
            scene.childNode(withName: "//\(VehicleSpriteNode.impactPresentationNodeName)")
        )
        let diagnostics = scene.presentationDiagnostics

        XCTAssertEqual(GameScene.collisionHitStopDuration, 0.065, accuracy: 0.000_001)
        XCTAssertEqual(GameScene.collisionRecoilEndTime, 0.405, accuracy: 0.000_001)
        XCTAssertEqual(GameScene.collisionSettleEndTime, 0.500, accuracy: 0.000_001)
        XCTAssertEqual(GameScene.collisionTotalDuration, 0.520, accuracy: 0.000_001)
        XCTAssertEqual(
            try XCTUnwrap(impactCamera.action(forKey: "feedbackMotion")).duration,
            GameScene.collisionTotalDuration,
            accuracy: 0.000_001
        )
        XCTAssertEqual(
            try XCTUnwrap(vehicleImpact.action(forKey: "collisionRecoil")).duration,
            GameScene.collisionTotalDuration,
            accuracy: 0.000_001
        )
        XCTAssertEqual(diagnostics.collisionImpactSide, .left)
        XCTAssertTrue(diagnostics.isCollisionPresentationActive)
        XCTAssertEqual(diagnostics.impactCameraPosition, .zero)
        XCTAssertEqual(diagnostics.impactCameraScale, 1, accuracy: 0.000_001)
        XCTAssertEqual(diagnostics.vehicleImpactPosition, .zero)
        XCTAssertEqual(diagnostics.vehicleImpactRotation, 0, accuracy: 0.000_001)
        XCTAssertEqual(diagnostics.activeDebrisCount, 0)
        XCTAssertEqual(
            diagnostics.scheduledDebrisCount,
            GameScene.maximumCollisionDebrisCount
        )

        scene.finishCollisionPresentation()
        let cleaned = scene.presentationDiagnostics
        XCTAssertFalse(cleaned.isCollisionPresentationActive)
        XCTAssertEqual(cleaned.impactCameraPosition, .zero)
        XCTAssertEqual(cleaned.impactCameraScale, 1, accuracy: 0.000_001)
        XCTAssertEqual(cleaned.vehicleImpactPosition, .zero)
        XCTAssertEqual(cleaned.vehicleImpactRotation, 0, accuracy: 0.000_001)
        XCTAssertEqual(cleaned.activeDebrisCount, 0)
        XCTAssertEqual(cleaned.scheduledDebrisCount, 0)
    }

    func testReduceMotionCollisionKeepsStaticImpactWithoutTransformsOrDebris() throws {
        let scene = try makeScene()
        scene.setAccessibilityPolicy(makePolicy(reduceMotion: true))
        scene.present(makeCollision(id: 8_002, side: .right))

        let impactCamera = try XCTUnwrap(
            scene.childNode(withName: "//presentation.camera.impact")
        )
        let vehicleImpact = try XCTUnwrap(
            scene.childNode(withName: "//\(VehicleSpriteNode.impactPresentationNodeName)")
        )
        let diagnostics = scene.presentationDiagnostics

        XCTAssertTrue(diagnostics.isCollisionPresentationActive)
        XCTAssertEqual(diagnostics.collisionImpactSide, .right)
        XCTAssertNil(impactCamera.action(forKey: "feedbackMotion"))
        XCTAssertNil(vehicleImpact.action(forKey: "collisionRecoil"))
        XCTAssertEqual(diagnostics.impactCameraPosition, .zero)
        XCTAssertEqual(diagnostics.impactCameraScale, 1, accuracy: 0.000_001)
        XCTAssertEqual(diagnostics.vehicleImpactPosition, .zero)
        XCTAssertEqual(diagnostics.vehicleImpactRotation, 0, accuracy: 0.000_001)
        XCTAssertEqual(diagnostics.activeDebrisCount, 0)
        XCTAssertEqual(diagnostics.scheduledDebrisCount, 0)
        XCTAssertGreaterThan(diagnostics.flashAlpha, 0)
    }

    private func assertFixedBounds(
        _ diagnostics: GameScene.PresentationDiagnostics,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(
            diagnostics.edgeStreakNodeCount,
            GameScene.maximumEdgeStreakCount,
            file: file,
            line: line
        )
        XCTAssertLessThanOrEqual(
            diagnostics.activeEdgeStreakCount,
            GameScene.maximumEdgeStreakCount,
            file: file,
            line: line
        )
        XCTAssertEqual(
            diagnostics.roadLightNodeCount,
            GameScene.maximumRoadLightCount,
            file: file,
            line: line
        )
        XCTAssertLessThanOrEqual(
            diagnostics.activeRoadLightCount,
            GameScene.maximumRoadLightCount,
            file: file,
            line: line
        )
        XCTAssertEqual(
            diagnostics.fogBandNodeCount,
            GameScene.maximumFogBandCount,
            file: file,
            line: line
        )
        XCTAssertLessThanOrEqual(
            diagnostics.activeFogBandCount,
            GameScene.maximumFogBandCount,
            file: file,
            line: line
        )
        XCTAssertEqual(
            diagnostics.debrisNodeCount,
            GameScene.maximumCollisionDebrisCount,
            file: file,
            line: line
        )
        XCTAssertLessThanOrEqual(
            diagnostics.activeDebrisCount,
            GameScene.maximumCollisionDebrisCount,
            file: file,
            line: line
        )
        XCTAssertLessThanOrEqual(
            diagnostics.scheduledDebrisCount,
            GameScene.maximumCollisionDebrisCount,
            file: file,
            line: line
        )
    }

    private func makeScene(
        seed: UInt64 = 17,
        configuration: GameSimulation.Configuration = .init()
    ) throws -> GameScene {
        let library = try GameAssetLibrary()
        let appearance = try XCTUnwrap(
            VehicleCatalog.resolve(VehicleCatalog.defaultSelection)
        )
        let scene = try GameScene(
            seed: seed,
            configuration: configuration,
            appearance: appearance,
            assetLibrary: library
        )
        scene.size = sceneSize
        scene.didMove(to: SKView(frame: CGRect(origin: .zero, size: sceneSize)))
        return scene
    }

    private func makePolicy(
        intensity: SensoryEffectIntensity = .balanced,
        reduceMotion: Bool = false,
        reduceTransparency: Bool = false
    ) -> SensoryAccessibilityPolicy {
        SensoryAccessibilityPolicy(
            settings: SensorySettings(
                sfxEnabled: true,
                hapticsEnabled: true,
                effectIntensity: intensity
            ),
            reduceMotion: reduceMotion,
            reduceTransparency: reduceTransparency
        )
    }

    private func makeNearMiss(
        side: FeedbackSide,
        grade: NearMissFeedbackGrade,
        id: UInt64
    ) -> GameFeedback {
        GameFeedback(
            eventID: deterministicUUID(id),
            kind: .nearMiss(bonus: 100),
            spatialContext: FeedbackSpatialContext(
                relativeX: side == .left ? -1 : (side == .right ? 1 : 0),
                side: side,
                closeness: grade == .strong ? 0.8 : 0.3
            ),
            nearMissGrade: grade,
            chainTier: 1,
            isHapticEligible: true
        )
    }

    private func makeCollision(
        id: UInt64,
        side: FeedbackSide = .right
    ) -> GameFeedback {
        GameFeedback(
            eventID: deterministicUUID(id),
            kind: .collision,
            obstacleID: id,
            spatialContext: FeedbackSpatialContext(
                relativeX: side == .left ? -1 : (side == .right ? 1 : 0),
                side: side,
                closeness: 1
            ),
            nearMissGrade: nil,
            chainTier: 0,
            isHapticEligible: true
        )
    }

    private func deterministicUUID(_ value: UInt64) -> UUID {
        let suffix = String(format: "%012llx", value)
        return UUID(uuidString: "00000000-0000-0000-0000-\(suffix)")!
    }
}
