import SpriteKit

@MainActor
final class GameScene: SKScene {
    typealias SteeringProvider = @MainActor (TimeInterval) -> Double
    typealias FrameHandler = @MainActor (GameSnapshot, [GameEvent]) -> Void
#if DEBUG
    typealias FrameRateHandler = @MainActor (Double) -> Void
#endif

    static let fixedStep: TimeInterval = 1.0 / 60.0
    static let maximumStepsPerFrame = 5
    static let skyAuthoredHorizonFraction: CGFloat = 0.10
#if DEBUG
    static let frameRateReportingInterval: TimeInterval = 1
#endif

    var steeringProvider: SteeringProvider = { _ in 0 }
    var frameHandler: FrameHandler?
#if DEBUG
    var frameRateHandler: FrameRateHandler?
#endif

    private(set) var currentSnapshot: GameSnapshot
    private(set) var reduceMotionEnabled = false
    let appearance: VehicleAppearance
    let assetLibrary: GameAssetLibrary

    private var simulation: GameSimulation
    private let obstacleSpriteFactory: ObstacleSpriteFactory
    private var previousUpdateTime: TimeInterval?
    private var accumulatedTime: TimeInterval = 0
    private var didBuildScene = false
#if DEBUG
    private var frameRateFrameCount = 0
    private var frameRateElapsedTime: TimeInterval = 0
#endif

    private let worldNode = SKNode()
    private let skyNode: SKSpriteNode
    private let roadShadowNode = SKShapeNode()
    private let roadNode = SKShapeNode()
    private let roadDecalContainer = SKNode()
    private let laneContainer = SKNode()
    private let roadsideContainer = SKNode()
    private let obstacleContainer = SKNode()
    private let playerNode: VehicleSpriteNode
    private let impactContainer = SKNode()
    private let scorePopContainer = SKNode()
    private let flashNode = SKShapeNode()
    private let mapTextures: MapTextures
    private var roadDecals: [RoadDecal] = []
    private var laneMarks: [(node: SKSpriteNode, separatorX: Double, index: Int)] = []
    private var roadsideProps: [RoadsideProp] = []
    private var obstacleNodes: [UInt64: SKNode] = [:]
    private var presentedFeedbackIDs: Set<UUID> = []

    private(set) var presentedFeedback: [GameFeedback] = []

    @MainActor
    private struct MapTextures {
        static let skyName = "sky_horizon"
        static let asphaltName = "asphalt"
        static let laneName = "lane_worn"
        static let roadDecalName = "road_decal_chevrons"
        static let roadsideNames = [
            "roadside_light",
            "roadside_palm",
            "roadside_marker",
        ]

        let sky: SKTexture
        let asphalt: SKTexture
        let lane: SKTexture
        let roadDecal: SKTexture
        let roadside: [SKTexture]

        init(assetLibrary: GameAssetLibrary) throws {
            sky = try assetLibrary.texture(named: Self.skyName)
            asphalt = try assetLibrary.texture(named: Self.asphaltName)
            lane = try assetLibrary.texture(named: Self.laneName)
            roadDecal = try assetLibrary.texture(named: Self.roadDecalName)
            roadside = try Self.roadsideNames.map { name in
                try assetLibrary.texture(named: name)
            }
        }
    }

    private struct RoadDecal {
        let node: SKSpriteNode
        let baseDistance: Double
        let lateralFactor: Double
    }

    private struct RoadsideProp {
        let node: SKSpriteNode
        let baseDistance: Double
        let side: Double
        let lateralOffset: Double
        let parallax: Double
    }

    init(
        seed: UInt64,
        configuration: GameSimulation.Configuration = .init(),
        appearance: VehicleAppearance,
        assetLibrary: GameAssetLibrary
    ) throws {
        let simulation = GameSimulation(seed: seed, configuration: configuration)
        let mapTextures = try MapTextures(assetLibrary: assetLibrary)
        self.simulation = simulation
        self.appearance = appearance
        self.assetLibrary = assetLibrary
        self.mapTextures = mapTextures
        skyNode = SKSpriteNode(texture: mapTextures.sky)
        playerNode = try VehicleSpriteNode(
            appearance: appearance,
            assetLibrary: assetLibrary
        )
        obstacleSpriteFactory = try ObstacleSpriteFactory(assetLibrary: assetLibrary)
        currentSnapshot = simulation.snapshot
        super.init(size: CGSize(width: 844, height: 390))
        scaleMode = .resizeFill
        anchorPoint = .zero
    }

    @available(*, unavailable)
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func didMove(to view: SKView) {
        buildSceneIfNeeded()
        updateStaticGeometry()
        render(currentSnapshot)
    }

    override func didChangeSize(_ oldSize: CGSize) {
        super.didChangeSize(oldSize)
        guard didBuildScene else {
            return
        }
        updateStaticGeometry()
        render(currentSnapshot)
    }

    override func update(_ currentTime: TimeInterval) {
        guard currentTime.isFinite else {
            return
        }
        guard !isPaused else {
            previousUpdateTime = nil
            accumulatedTime = 0
            return
        }
        guard let previousUpdateTime else {
            self.previousUpdateTime = currentTime
            render(currentSnapshot)
            frameHandler?(currentSnapshot, [])
            return
        }

        self.previousUpdateTime = currentTime
        let elapsedFrameTime = max(currentTime - previousUpdateTime, 0)
#if DEBUG
        updateFrameRateDiagnostic(elapsedFrameTime: elapsedFrameTime)
#endif
        let frameTime = min(elapsedFrameTime, 0.25)
        let maximumAccumulatedTime = Self.fixedStep * Double(Self.maximumStepsPerFrame)
        accumulatedTime = min(accumulatedTime + frameTime, maximumAccumulatedTime)

        var events: [GameEvent] = []
        var stepCount = 0
        while accumulatedTime >= Self.fixedStep, stepCount < Self.maximumStepsPerFrame {
            let steering = steeringProvider(Self.fixedStep)
            events.append(contentsOf: simulation.step(dt: Self.fixedStep, steering: steering))
            accumulatedTime -= Self.fixedStep
            stepCount += 1
        }

        currentSnapshot = simulation.snapshot
        render(currentSnapshot)
        frameHandler?(currentSnapshot, events)
    }

    func reset(seed: UInt64) {
        simulation.reset(seed: seed)
        currentSnapshot = simulation.snapshot
        previousUpdateTime = nil
        accumulatedTime = 0
#if DEBUG
        frameRateFrameCount = 0
        frameRateElapsedTime = 0
#endif
        presentedFeedbackIDs.removeAll(keepingCapacity: true)
        presentedFeedback.removeAll(keepingCapacity: true)
        worldNode.removeAllActions()
        worldNode.position = .zero
        flashNode.removeAllActions()
        flashNode.alpha = 0
        impactContainer.removeAllChildren()
        scorePopContainer.removeAllChildren()
        obstacleNodes.values.forEach { $0.removeFromParent() }
        obstacleNodes.removeAll(keepingCapacity: true)
        render(currentSnapshot)
        frameHandler?(currentSnapshot, [])
    }

    func setReduceMotionEnabled(_ enabled: Bool) {
        reduceMotionEnabled = enabled
        if enabled {
            worldNode.removeAction(forKey: "feedbackMotion")
            worldNode.position = .zero
        }
    }

#if DEBUG
    private func updateFrameRateDiagnostic(elapsedFrameTime: TimeInterval) {
        guard elapsedFrameTime > 0 else {
            return
        }
        frameRateFrameCount += 1
        frameRateElapsedTime += elapsedFrameTime
        guard frameRateElapsedTime >= Self.frameRateReportingInterval else {
            return
        }

        frameRateHandler?(Double(frameRateFrameCount) / frameRateElapsedTime)
        frameRateFrameCount = 0
        frameRateElapsedTime = 0
    }
#endif

    func present(_ feedback: GameFeedback) {
        guard presentedFeedbackIDs.insert(feedback.eventID).inserted else {
            return
        }
        presentedFeedback.append(feedback)
        guard didBuildScene else {
            return
        }

        switch feedback.kind {
        case let .nearMiss(bonus):
            runNearMissFeedback(bonus: bonus)
        case .collision:
            runCollisionFeedback()
        }
    }

    private func buildSceneIfNeeded() {
        guard !didBuildScene else {
            return
        }
        didBuildScene = true
        backgroundColor = UIColor(red: 0.12, green: 0.10, blue: 0.41, alpha: 1)

        worldNode.zPosition = 0
        worldNode.name = "feedback.world"
        addChild(worldNode)

        skyNode.name = "map.sky.sky_horizon"
        skyNode.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        skyNode.color = .white
        skyNode.colorBlendFactor = 0
        skyNode.zPosition = -3
        worldNode.addChild(skyNode)

        roadShadowNode.fillColor = UIColor(red: 0.01, green: 0.015, blue: 0.04, alpha: 0.72)
        roadShadowNode.strokeColor = .clear
        roadShadowNode.zPosition = -2
        worldNode.addChild(roadShadowNode)

        roadNode.name = "map.road.asphalt"
        roadNode.fillColor = .white
        roadNode.fillTexture = mapTextures.asphalt
        roadNode.strokeColor = UIColor(red: 0.37, green: 0.91, blue: 0.80, alpha: 0.82)
        roadNode.lineWidth = 3
        roadNode.zPosition = 0
        worldNode.addChild(roadNode)

        roadDecalContainer.name = "map.roadDecals"
        roadDecalContainer.zPosition = 1
        worldNode.addChild(roadDecalContainer)
        buildRoadDecals()

        laneContainer.name = "map.lanes"
        laneContainer.zPosition = 2
        worldNode.addChild(laneContainer)
        buildLaneMarks()

        roadsideContainer.name = "map.roadside"
        roadsideContainer.zPosition = 5
        worldNode.addChild(roadsideContainer)
        buildRoadsideProps()

        obstacleContainer.zPosition = 10
        worldNode.addChild(obstacleContainer)

        playerNode.zPosition = 100
        worldNode.addChild(playerNode)

        impactContainer.zPosition = 220
        impactContainer.name = "feedback.impact"
        worldNode.addChild(impactContainer)

        scorePopContainer.zPosition = 520
        scorePopContainer.name = "feedback.scorePop"
        addChild(scorePopContainer)

        flashNode.fillColor = .white
        flashNode.strokeColor = .clear
        flashNode.alpha = 0
        flashNode.zPosition = 500
        flashNode.name = "feedback.flash"
        addChild(flashNode)
    }

    private func updateStaticGeometry() {
        let projection = makeProjection(for: currentSnapshot)

        let skyAspectRatio = mapTextures.sky.size().width / mapTextures.sky.size().height
        let skyWidth = ceil(size.width) + 2
        let skyHeight = skyWidth / skyAspectRatio
        skyNode.size = CGSize(width: skyWidth, height: skyHeight)
        skyNode.position = CGPoint(
            x: size.width / 2,
            y: projection.horizonY
                + (0.5 - Self.skyAuthoredHorizonFraction) * skyHeight
        )

        let shadowOffset = CGPoint(x: 7, y: -5)
        let roadShadowPath = CGMutablePath()
        roadShadowPath.move(to: CGPoint(x: shadowOffset.x, y: shadowOffset.y))
        roadShadowPath.addLine(to: CGPoint(
            x: size.width / 2 - projection.roadScreenHalfWidth(at: projection.maximumDistance)
                + shadowOffset.x,
            y: projection.horizonY + shadowOffset.y
        ))
        roadShadowPath.addLine(to: CGPoint(
            x: size.width / 2 + projection.roadScreenHalfWidth(at: projection.maximumDistance)
                + shadowOffset.x,
            y: projection.horizonY + shadowOffset.y
        ))
        roadShadowPath.addLine(to: CGPoint(
            x: size.width + shadowOffset.x,
            y: shadowOffset.y
        ))
        roadShadowPath.closeSubpath()
        roadShadowNode.path = roadShadowPath

        let roadPath = CGMutablePath()
        roadPath.move(to: CGPoint(x: 0, y: 0))
        roadPath.addLine(to: CGPoint(
            x: size.width / 2 - projection.roadScreenHalfWidth(at: projection.maximumDistance),
            y: projection.horizonY
        ))
        roadPath.addLine(to: CGPoint(
            x: size.width / 2 + projection.roadScreenHalfWidth(at: projection.maximumDistance),
            y: projection.horizonY
        ))
        roadPath.addLine(to: CGPoint(x: size.width, y: 0))
        roadPath.closeSubpath()
        roadNode.path = roadPath

        flashNode.path = CGPath(rect: CGRect(origin: .zero, size: size), transform: nil)
    }

    private func buildRoadDecals() {
        for index in 0..<4 {
            let node = SKSpriteNode(
                texture: mapTextures.roadDecal,
                size: CGSize(width: 38, height: 38)
            )
            node.name = "map.decal.road_decal_chevrons.\(index)"
            node.anchorPoint = CGPoint(x: 0.5, y: 0.5)
            node.color = .white
            node.colorBlendFactor = 0
            node.alpha = 0.42
            roadDecalContainer.addChild(node)
            roadDecals.append(
                RoadDecal(
                    node: node,
                    baseDistance: 12 + Double(index) * 16,
                    lateralFactor: index.isMultiple(of: 2) ? -0.72 : 0.72
                )
            )
        }
    }

    private func buildLaneMarks() {
        let markCount = 12
        for (separatorIndex, separatorX) in [-0.5, 0.5].enumerated() {
            for index in 0..<markCount {
                let node = SKSpriteNode(
                    texture: mapTextures.lane,
                    size: CGSize(width: 5, height: 40)
                )
                node.name = "map.lane.lane_worn.\(separatorIndex).\(index)"
                node.anchorPoint = CGPoint(x: 0.5, y: 0.5)
                node.color = .white
                node.colorBlendFactor = 0
                laneContainer.addChild(node)
                laneMarks.append((node, separatorX, index))
            }
        }
    }

    private func buildRoadsideProps() {
        for index in 0..<24 {
            let style = index % MapTextures.roadsideNames.count
            let node = makeRoadsideProp(style: style, index: index)
            roadsideContainer.addChild(node)
            roadsideProps.append(
                RoadsideProp(
                    node: node,
                    baseDistance: 2.5 + Double(index) * 2.55,
                    side: index.isMultiple(of: 2) ? -1 : 1,
                    lateralOffset: 1.0 + Double(index % 4) * 0.26,
                    parallax: 0.78 + Double(index % 3) * 0.09
                )
            )
        }
    }

    private func makeRoadsideProp(style: Int, index: Int) -> SKSpriteNode {
        let textureName = MapTextures.roadsideNames[style]
        let logicalSizes = [
            CGSize(width: 28, height: 56),
            CGSize(width: 48, height: 64),
            CGSize(width: 48, height: 64),
        ]
        let node = SKSpriteNode(
            texture: mapTextures.roadside[style],
            size: logicalSizes[style]
        )
        node.name = "map.roadside.\(textureName).\(index)"
        node.anchorPoint = CGPoint(x: 0.5, y: 0)
        node.color = .white
        node.colorBlendFactor = 0
        return node
    }

    private func render(_ snapshot: GameSnapshot) {
        guard didBuildScene else {
            return
        }
        let projection = makeProjection(for: snapshot)
        renderRoadDecals(snapshot: snapshot, projection: projection)
        renderLaneMarks(snapshot: snapshot, projection: projection)
        renderRoadsideProps(snapshot: snapshot, projection: projection)

        let playerProjection = projection.project(lateral: snapshot.playerX, distance: 0)
        playerNode.position = playerProjection.point
        playerNode.setScale(playerProjection.scale)

        let visibleIDs = Set(snapshot.obstacles.map(\.id))
        for id in Array(obstacleNodes.keys) where !visibleIDs.contains(id) {
            obstacleNodes[id]?.removeFromParent()
            obstacleNodes[id] = nil
        }

        for obstacle in snapshot.obstacles {
            let node = obstacleNodes[obstacle.id] ?? makeObstacleNode(for: obstacle)
            obstacleNodes[obstacle.id] = node
            if node.parent == nil {
                obstacleContainer.addChild(node)
            }

            let projected = projection.project(lateral: obstacle.x, distance: obstacle.distance)
            node.position = projected.point
            node.setScale(projected.scale)
            node.zPosition = 1 - projected.normalizedDepth
            node.isHidden = obstacle.distance < -3 || obstacle.distance > projection.maximumDistance + 2
        }
    }

    private func renderRoadDecals(snapshot: GameSnapshot, projection: RoadProjection) {
        let cycleLength = projection.maximumDistance + 20
        let travel = snapshot.distance.truncatingRemainder(dividingBy: cycleLength)
        for decal in roadDecals {
            var distance = decal.baseDistance - travel
            while distance < 1.2 {
                distance += cycleLength
            }

            let projected = projection.project(
                lateral: decal.lateralFactor * snapshot.roadHalfWidth,
                distance: distance
            )
            decal.node.position = projected.point
            decal.node.setScale(projected.scale)
            decal.node.zPosition = 1 - projected.normalizedDepth
            decal.node.isHidden = distance > projection.maximumDistance
        }
    }

    private func renderLaneMarks(snapshot: GameSnapshot, projection: RoadProjection) {
        let spacing = 4.5
        let speedRange = max(
            simulation.configuration.maximumSpeed - simulation.configuration.initialSpeed,
            0.001
        )
        let speedProgress = min(
            max((snapshot.speed - simulation.configuration.initialSpeed) / speedRange, 0),
            1
        )
        let markLength = 1.7 + speedProgress * 1.15
        let cycleLength = spacing * 12
        let travel = snapshot.distance.truncatingRemainder(dividingBy: spacing)

        for mark in laneMarks {
            var distance = Double(mark.index) * spacing - travel
            if distance < 0 {
                distance += cycleLength
            }
            let lateral = mark.separatorX * snapshot.laneWidth
            let nearPoint = projection.project(lateral: lateral, distance: distance)
            let farPoint = projection.project(lateral: lateral, distance: distance + markLength)
            let height = max(farPoint.point.y - nearPoint.point.y, 1)

            mark.node.position = CGPoint(
                x: nearPoint.point.x,
                y: nearPoint.point.y + height / 2
            )
            mark.node.xScale = max(nearPoint.scale, 0.2)
            mark.node.yScale = height / 40
            mark.node.alpha = 0.68 + speedProgress * 0.30
            mark.node.isHidden = distance > projection.maximumDistance
        }
    }

    private func renderRoadsideProps(snapshot: GameSnapshot, projection: RoadProjection) {
        let cycleLength = projection.maximumDistance + 10
        for prop in roadsideProps {
            let travel = (snapshot.distance * prop.parallax)
                .truncatingRemainder(dividingBy: cycleLength)
            var distance = prop.baseDistance - travel
            while distance < 1.2 {
                distance += cycleLength
            }

            let lateral = prop.side * (snapshot.roadHalfWidth + prop.lateralOffset)
            let projected = projection.project(lateral: lateral, distance: distance)
            prop.node.position = projected.point
            prop.node.setScale(projected.scale)
            prop.node.zPosition = 1 - projected.normalizedDepth
            prop.node.isHidden = distance > projection.maximumDistance
        }
    }

    private func makeProjection(for snapshot: GameSnapshot) -> RoadProjection {
        RoadProjection(
            screenSize: size,
            roadHalfWidth: snapshot.roadHalfWidth,
            maximumDistance: max(simulation.configuration.spawnDistance + 4, 52)
        )
    }

    private func makeObstacleNode(for obstacle: ObstacleSnapshot) -> SKNode {
        obstacleSpriteFactory.makeNode(for: obstacle)
    }

    private func runNearMissFeedback(bonus: Int) {
        worldNode.removeAction(forKey: "feedbackMotion")
        worldNode.position = .zero
        if !reduceMotionEnabled {
            worldNode.run(
                .sequence([
                    .moveBy(x: -5, y: -2, duration: 0.035),
                    .moveBy(x: 9, y: 3, duration: 0.045),
                    .moveBy(x: -4, y: -1, duration: 0.045)
                ]),
                withKey: "feedbackMotion"
            )
        }

        flashNode.removeAction(forKey: "feedbackFlash")
        flashNode.fillColor = UIColor(red: 0.34, green: 1.0, blue: 0.84, alpha: 1)
        flashNode.alpha = 0.22
        flashNode.run(.fadeOut(withDuration: 0.16), withKey: "feedbackFlash")

        let label = SKLabelNode(fontNamed: "AvenirNext-Heavy")
        label.text = "NEAR MISS +\(bonus)"
        label.fontSize = 22
        label.fontColor = UIColor(red: 1.0, green: 0.86, blue: 0.33, alpha: 1)
        label.position = CGPoint(x: size.width / 2, y: size.height * 0.42)
        label.horizontalAlignmentMode = .center
        label.verticalAlignmentMode = .center
        label.setScale(0.82)
        scorePopContainer.addChild(label)
        label.run(
            .sequence([
                .group([
                    .scale(to: 1.08, duration: 0.10),
                    .moveBy(x: 0, y: 12, duration: 0.10)
                ]),
                .wait(forDuration: 0.34),
                .group([
                    .fadeOut(withDuration: 0.24),
                    .moveBy(x: 0, y: 18, duration: 0.24)
                ]),
                .removeFromParent()
            ])
        )
    }

    private func runCollisionFeedback() {
        worldNode.removeAction(forKey: "feedbackMotion")
        worldNode.position = .zero
        if !reduceMotionEnabled {
            let offsets: [(CGFloat, CGFloat)] = [
                (-12, 5), (8, -8), (15, 10), (-18, -5),
                (14, -9), (-9, 7), (5, -3), (-3, 3)
            ]
            worldNode.run(
                .sequence(offsets.map { .moveBy(x: $0.0, y: $0.1, duration: 0.035) }),
                withKey: "feedbackMotion"
            )
        }

        flashNode.removeAction(forKey: "feedbackFlash")
        flashNode.fillColor = UIColor(red: 1.0, green: 0.29, blue: 0.36, alpha: 1)
        flashNode.alpha = 0.64
        flashNode.run(
            .sequence([
                .fadeAlpha(to: 0.14, duration: 0.08),
                .fadeOut(withDuration: 0.30)
            ]),
            withKey: "feedbackFlash"
        )

        let colors = [
            UIColor(red: 1.0, green: 0.76, blue: 0.25, alpha: 1),
            UIColor(red: 1.0, green: 0.34, blue: 0.42, alpha: 1),
            UIColor(red: 0.48, green: 0.93, blue: 0.84, alpha: 1)
        ]
        for index in 0..<18 {
            let particle = SKShapeNode(
                rectOf: CGSize(width: 5 + index % 3 * 2, height: 5 + (index + 1) % 3 * 2),
                cornerRadius: 1
            )
            particle.fillColor = colors[index % colors.count]
            particle.strokeColor = .clear
            particle.position = playerNode.position
            particle.zRotation = CGFloat(index) * 0.41
            impactContainer.addChild(particle)

            let angle = CGFloat(index) / 18 * 2 * .pi
            let radius = CGFloat(34 + (index % 5) * 11)
            particle.run(
                .sequence([
                    .group([
                        .moveBy(
                            x: cos(angle) * radius,
                            y: sin(angle) * radius + 24,
                            duration: 0.42
                        ),
                        .rotate(byAngle: index.isMultiple(of: 2) ? 2.4 : -2.4, duration: 0.42),
                        .fadeOut(withDuration: 0.42),
                        .scale(to: 0.35, duration: 0.42)
                    ]),
                    .removeFromParent()
                ])
            )
        }
    }

}
