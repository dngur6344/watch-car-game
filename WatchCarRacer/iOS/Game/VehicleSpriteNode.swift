import SpriteKit
import UIKit

@MainActor
final class VehicleSpriteNode: SKNode {
    static let shadowNodeName = "vehicle.shadow"
    static let paintNodeName = "vehicle.paint"
    static let detailsNodeName = "vehicle.details"

    let appearance: VehicleAppearance
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

        addChild(shadowNode)
        addChild(paintNode)
        addChild(detailsNode)
    }

    @available(*, unavailable)
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) is not supported")
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
