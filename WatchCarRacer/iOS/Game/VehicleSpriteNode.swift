import SpriteKit
import UIKit

@MainActor
final class VehicleSpriteNode: SKNode {
    static let shadowNodeName = "vehicle.shadow"
    static let paintNodeName = "vehicle.paint"
    static let detailsNodeName = "vehicle.details"
    static let impactPresentationNodeName = "vehicle.presentation.impact"
    static let bodyPresentationNodeName = "vehicle.presentation.body"

    static let maximumBodyRoll: CGFloat = 0.065
    static let maximumPaintOffset: CGFloat = 0.75
    static let maximumDetailsOffset: CGFloat = 1.5
    static let maximumShadowOffset: CGFloat = 3
    static let reducedTransformMultiplier: CGFloat = 0.45

    let appearance: VehicleAppearance
    let impactPresentationNode = SKNode()
    let bodyPresentationNode = SKNode()
    let shadowNode: SKSpriteNode
    let paintNode: SKSpriteNode
    let detailsNode: SKSpriteNode

    init(appearance: VehicleAppearance, assetLibrary: GameAssetLibrary) throws {
        self.appearance = appearance

        let descriptor = appearance.vehicle
        shadowNode = SKSpriteNode(
            texture: try assetLibrary.texture(named: descriptor.textures.shadow),
            size: descriptor.logicalRenderSize
        )
        paintNode = SKSpriteNode(
            texture: try assetLibrary.texture(named: descriptor.textures.paint),
            size: descriptor.logicalRenderSize
        )
        detailsNode = SKSpriteNode(
            texture: try assetLibrary.texture(named: descriptor.textures.details),
            size: descriptor.logicalRenderSize
        )

        super.init()

        let anchorPoint = CGPoint(
            x: CGFloat(descriptor.pivot.x),
            y: CGFloat(descriptor.pivot.y)
        )
        shadowNode.anchorPoint = anchorPoint
        paintNode.anchorPoint = anchorPoint
        detailsNode.anchorPoint = anchorPoint

        shadowNode.name = Self.shadowNodeName
        paintNode.name = Self.paintNodeName
        detailsNode.name = Self.detailsNodeName

        shadowNode.zPosition = 0
        paintNode.zPosition = 1
        detailsNode.zPosition = 2

        impactPresentationNode.name = Self.impactPresentationNodeName
        bodyPresentationNode.name = Self.bodyPresentationNodeName

        shadowNode.color = .white
        shadowNode.colorBlendFactor = 0
        paintNode.color = UIColor(
            red: CGFloat(appearance.color.rgba.red),
            green: CGFloat(appearance.color.rgba.green),
            blue: CGFloat(appearance.color.rgba.blue),
            alpha: CGFloat(appearance.color.rgba.alpha)
        )
        paintNode.colorBlendFactor = 1
        detailsNode.color = .white
        detailsNode.colorBlendFactor = 0

        addChild(impactPresentationNode)
        impactPresentationNode.addChild(shadowNode)
        impactPresentationNode.addChild(bodyPresentationNode)
        bodyPresentationNode.addChild(paintNode)
        bodyPresentationNode.addChild(detailsNode)
    }

    @available(*, unavailable)
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func applyPresentation(
        speedProgress: Double,
        steering: Double,
        level: SensoryAccessibilityPolicy.DecorativeEffectLevel
    ) {
        let clampedSpeed = CGFloat(min(max(speedProgress.isFinite ? speedProgress : 0, 0), 1))
        let clampedSteering = CGFloat(min(max(steering.isFinite ? steering : 0, -1), 1))
        let amplitude: CGFloat = switch level {
        case .balanced:
            1
        case .reduced:
            Self.reducedTransformMultiplier
        case .off:
            0
        }

        bodyPresentationNode.zRotation = -clampedSteering * Self.maximumBodyRoll * amplitude
        paintNode.position = CGPoint(
            x: clampedSteering * Self.maximumPaintOffset * amplitude,
            y: 0
        )
        detailsNode.position = CGPoint(
            x: clampedSteering * Self.maximumDetailsOffset * amplitude,
            y: 0
        )

        let steeringMagnitude = abs(clampedSteering)
        shadowNode.position = CGPoint(
            x: -clampedSteering * Self.maximumShadowOffset * amplitude,
            y: -(1.4 + clampedSpeed * 1.8) * amplitude
        )
        shadowNode.xScale = 1 - (clampedSpeed * 0.06 + steeringMagnitude * 0.025) * amplitude
        shadowNode.yScale = 1 - (clampedSpeed * 0.13 + steeringMagnitude * 0.035) * amplitude
        shadowNode.alpha = 0.58 + (clampedSpeed * 0.16 + steeringMagnitude * 0.06) * max(amplitude, 0.45)
    }

    func resetPresentation() {
        impactPresentationNode.removeAllActions()
        impactPresentationNode.position = .zero
        impactPresentationNode.zRotation = 0
        impactPresentationNode.setScale(1)
        applyPresentation(speedProgress: 0, steering: 0, level: .off)
    }
}

@MainActor
struct ObstacleSpriteFactory {
    static let barrierTextureName = "barrier_modular"
    static let trafficTextureNames = ["traffic_sedan", "traffic_wagon"]

    private let textures: [String: SKTexture]

    init(assetLibrary: GameAssetLibrary) throws {
        let requiredNames = [Self.barrierTextureName] + Self.trafficTextureNames
        textures = try Dictionary(
            uniqueKeysWithValues: requiredNames.map { name in
                (name, try assetLibrary.texture(named: name))
            }
        )
    }

    static func textureName(for kind: ObstacleKind, obstacleID: UInt64) -> String {
        switch kind {
        case .barrier:
            barrierTextureName
        case .trafficCar:
            trafficTextureNames[Int(obstacleID % UInt64(trafficTextureNames.count))]
        }
    }

    func makeNode(for obstacle: ObstacleSnapshot) -> SKSpriteNode {
        let textureName = Self.textureName(for: obstacle.kind, obstacleID: obstacle.id)
        guard let texture = textures[textureName] else {
            preconditionFailure("Required obstacle texture was not resolved: \(textureName)")
        }

        let node = SKSpriteNode(texture: texture, size: Self.logicalRenderSize(for: obstacle.kind))
        node.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        node.color = .white
        node.colorBlendFactor = 0
        node.name = "obstacle.\(textureName)"
        return node
    }

    private static func logicalRenderSize(for kind: ObstacleKind) -> CGSize {
        switch kind {
        case .barrier:
            CGSize(width: 75, height: 37.5)
        case .trafficCar:
            CGSize(width: 54, height: 81)
        }
    }
}
