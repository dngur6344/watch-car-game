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
#if DEBUG
    static let frameRateReportingInterval: TimeInterval = 0.5
#endif

    var steeringProvider: SteeringProvider = { _ in 0 }
    var frameHandler: FrameHandler?
#if DEBUG
    var frameRateHandler: FrameRateHandler?
#endif

    private(set) var currentSnapshot: GameSnapshot

    private var simulation: GameSimulation
    private var previousUpdateTime: TimeInterval?
    private var accumulatedTime: TimeInterval = 0
    private var didBuildScene = false
#if DEBUG
    private var frameRateFrameCount = 0
    private var frameRateElapsedTime: TimeInterval = 0
#endif

    private let worldNode = SKNode()
    private let roadShadowNode = SKShapeNode()
    private let roadNode = SKShapeNode()
    private let horizonNode = SKShapeNode()
    private let sunNode = SKShapeNode(circleOfRadius: 42)
    private let laneContainer = SKNode()
    private let roadsideContainer = SKNode()
    private let obstacleContainer = SKNode()
    private let playerNode = SKNode()
    private let impactContainer = SKNode()
    private let scorePopContainer = SKNode()
    private let flashNode = SKShapeNode()
    private var laneMarks: [(node: SKShapeNode, separatorX: Double, index: Int)] = []
    private var roadsideProps: [RoadsideProp] = []
    private var obstacleNodes: [UInt64: SKNode] = [:]
    private var presentedFeedbackIDs: Set<UUID> = []

    private(set) var presentedFeedback: [GameFeedback] = []

    private struct RoadsideProp {
        let node: SKNode
        let baseDistance: Double
        let side: Double
        let lateralOffset: Double
        let parallax: Double
    }

    init(seed: UInt64, configuration: GameSimulation.Configuration = .init()) {
        let simulation = GameSimulation(seed: seed, configuration: configuration)
        self.simulation = simulation
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
        backgroundColor = UIColor(red: 0.035, green: 0.025, blue: 0.09, alpha: 1)

        worldNode.zPosition = 0
        addChild(worldNode)

        sunNode.fillColor = UIColor(red: 0.98, green: 0.39, blue: 0.54, alpha: 0.72)
        sunNode.strokeColor = UIColor(red: 1.0, green: 0.69, blue: 0.37, alpha: 0.82)
        sunNode.lineWidth = 4
        sunNode.zPosition = -3
        worldNode.addChild(sunNode)

        roadShadowNode.fillColor = UIColor(red: 0.01, green: 0.015, blue: 0.04, alpha: 0.72)
        roadShadowNode.strokeColor = .clear
        roadShadowNode.zPosition = -2
        worldNode.addChild(roadShadowNode)

        roadNode.fillColor = UIColor(red: 0.075, green: 0.09, blue: 0.16, alpha: 1)
        roadNode.strokeColor = UIColor(red: 0.37, green: 0.91, blue: 0.80, alpha: 0.82)
        roadNode.lineWidth = 3
        roadNode.zPosition = 0
        worldNode.addChild(roadNode)

        horizonNode.strokeColor = UIColor(red: 0.65, green: 0.48, blue: 0.96, alpha: 0.72)
        horizonNode.lineWidth = 2
        horizonNode.zPosition = 1
        worldNode.addChild(horizonNode)

        laneContainer.zPosition = 2
        worldNode.addChild(laneContainer)
        buildLaneMarks()

        roadsideContainer.zPosition = 5
        worldNode.addChild(roadsideContainer)
        buildRoadsideProps()

        obstacleContainer.zPosition = 10
        worldNode.addChild(obstacleContainer)

        buildPlayerCar()
        playerNode.zPosition = 100
        worldNode.addChild(playerNode)

        impactContainer.zPosition = 220
        worldNode.addChild(impactContainer)

        scorePopContainer.zPosition = 520
        addChild(scorePopContainer)

        flashNode.fillColor = .white
        flashNode.strokeColor = .clear
        flashNode.alpha = 0
        flashNode.zPosition = 500
        addChild(flashNode)
    }

    private func updateStaticGeometry() {
        let projection = makeProjection(for: currentSnapshot)
        sunNode.position = CGPoint(x: size.width * 0.77, y: projection.horizonY + 38)

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

        let horizonPath = CGMutablePath()
        horizonPath.move(to: CGPoint(x: 0, y: projection.horizonY))
        horizonPath.addLine(to: CGPoint(x: size.width, y: projection.horizonY))
        horizonNode.path = horizonPath

        flashNode.path = CGPath(rect: CGRect(origin: .zero, size: size), transform: nil)
    }

    private func buildLaneMarks() {
        let markCount = 12
        for separatorX in [-0.5, 0.5] {
            for index in 0..<markCount {
                let node = SKShapeNode(rectOf: CGSize(width: 5, height: 40), cornerRadius: 2)
                node.fillColor = UIColor(red: 0.96, green: 0.83, blue: 0.34, alpha: 0.84)
                node.strokeColor = .clear
                laneContainer.addChild(node)
                laneMarks.append((node, separatorX, index))
            }
        }
    }

    private func buildRoadsideProps() {
        for index in 0..<24 {
            let node = makeRoadsideProp(style: index % 3)
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

    private func makeRoadsideProp(style: Int) -> SKNode {
        let node = SKNode()
        switch style {
        case 0:
            addBlock(
                to: node,
                size: CGSize(width: 11, height: 38),
                position: CGPoint(x: 4, y: 17),
                color: UIColor.black.withAlphaComponent(0.34),
                cornerRadius: 2
            )
            addBlock(
                to: node,
                size: CGSize(width: 8, height: 36),
                position: CGPoint(x: 0, y: 20),
                color: UIColor(red: 0.31, green: 0.83, blue: 0.78, alpha: 1),
                cornerRadius: 2
            )
            addBlock(
                to: node,
                size: CGSize(width: 20, height: 12),
                position: CGPoint(x: 0, y: 42),
                color: UIColor(red: 0.98, green: 0.38, blue: 0.53, alpha: 1),
                cornerRadius: 3
            )
        case 1:
            addBlock(
                to: node,
                size: CGSize(width: 34, height: 34),
                position: CGPoint(x: 5, y: 19),
                color: UIColor.black.withAlphaComponent(0.30),
                cornerRadius: 5,
                rotation: .pi / 4
            )
            addBlock(
                to: node,
                size: CGSize(width: 30, height: 30),
                position: CGPoint(x: 0, y: 24),
                color: UIColor(red: 0.55, green: 0.35, blue: 0.91, alpha: 1),
                cornerRadius: 4,
                rotation: .pi / 4
            )
            addBlock(
                to: node,
                size: CGSize(width: 9, height: 22),
                position: CGPoint(x: 0, y: 2),
                color: UIColor(red: 0.25, green: 0.17, blue: 0.34, alpha: 1),
                cornerRadius: 2
            )
        default:
            addBlock(
                to: node,
                size: CGSize(width: 46, height: 10),
                position: CGPoint(x: 5, y: 5),
                color: UIColor.black.withAlphaComponent(0.32),
                cornerRadius: 3
            )
            addBlock(
                to: node,
                size: CGSize(width: 42, height: 8),
                position: CGPoint(x: 0, y: 9),
                color: UIColor(red: 0.97, green: 0.70, blue: 0.24, alpha: 1),
                cornerRadius: 2
            )
            addBlock(
                to: node,
                size: CGSize(width: 8, height: 30),
                position: CGPoint(x: -15, y: 25),
                color: UIColor(red: 0.93, green: 0.31, blue: 0.44, alpha: 1),
                cornerRadius: 2
            )
            addBlock(
                to: node,
                size: CGSize(width: 8, height: 30),
                position: CGPoint(x: 15, y: 25),
                color: UIColor(red: 0.93, green: 0.31, blue: 0.44, alpha: 1),
                cornerRadius: 2
            )
        }
        return node
    }

    private func buildPlayerCar() {
        addBlock(
            to: playerNode,
            size: CGSize(width: 50, height: 72),
            position: CGPoint(x: 6, y: -5),
            color: UIColor.black.withAlphaComponent(0.45),
            cornerRadius: 8
        )
        addBlock(
            to: playerNode,
            size: CGSize(width: 44, height: 70),
            position: .zero,
            color: UIColor(red: 0.20, green: 0.88, blue: 0.74, alpha: 1),
            cornerRadius: 7
        )
        addBlock(
            to: playerNode,
            size: CGSize(width: 36, height: 18),
            position: CGPoint(x: 0, y: -25),
            color: UIColor(red: 0.11, green: 0.55, blue: 0.57, alpha: 1),
            cornerRadius: 5
        )
        addBlock(
            to: playerNode,
            size: CGSize(width: 32, height: 30),
            position: CGPoint(x: 0, y: 10),
            color: UIColor(red: 0.12, green: 0.20, blue: 0.38, alpha: 1),
            cornerRadius: 5
        )
        addBlock(
            to: playerNode,
            size: CGSize(width: 7, height: 56),
            position: CGPoint(x: 0, y: -1),
            color: UIColor(red: 0.98, green: 0.72, blue: 0.25, alpha: 0.95),
            cornerRadius: 2
        )
        for x in [-14.0, 14.0] {
            addBlock(
                to: playerNode,
                size: CGSize(width: 9, height: 7),
                position: CGPoint(x: x, y: 30),
                color: UIColor(red: 1.0, green: 0.92, blue: 0.60, alpha: 1),
                cornerRadius: 2
            )
        }
        for x in [-24.0, 24.0] {
            for y in [-20.0, 20.0] {
                addBlock(
                    to: playerNode,
                    size: CGSize(width: 8, height: 16),
                    position: CGPoint(x: x, y: y),
                    color: UIColor(white: 0.04, alpha: 1),
                    cornerRadius: 2
                )
            }
        }
    }

    private func render(_ snapshot: GameSnapshot) {
        guard didBuildScene else {
            return
        }
        let projection = makeProjection(for: snapshot)
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
        let node = SKNode()
        switch obstacle.kind {
        case .barrier:
            addBlock(
                to: node,
                size: CGSize(width: 70, height: 31),
                position: CGPoint(x: 6, y: -6),
                color: UIColor.black.withAlphaComponent(0.43),
                cornerRadius: 4
            )
            addBlock(
                to: node,
                size: CGSize(width: 68, height: 30),
                position: .zero,
                color: UIColor(red: 0.97, green: 0.52, blue: 0.22, alpha: 1),
                cornerRadius: 4
            )
            for x in [-25.0, -8.5, 8.5, 25.0] {
                addBlock(
                    to: node,
                    size: CGSize(width: 9, height: 23),
                    position: CGPoint(x: x, y: 1),
                    color: UIColor(red: 1.0, green: 0.86, blue: 0.35, alpha: 1),
                    cornerRadius: 2,
                    rotation: -.pi / 10
                )
            }
            for x in [-24.0, 24.0] {
                addBlock(
                    to: node,
                    size: CGSize(width: 9, height: 14),
                    position: CGPoint(x: x, y: -21),
                    color: UIColor(red: 0.25, green: 0.16, blue: 0.30, alpha: 1),
                    cornerRadius: 2
                )
            }
        case .trafficCar:
            addBlock(
                to: node,
                size: CGSize(width: 54, height: 76),
                position: CGPoint(x: 6, y: -5),
                color: UIColor.black.withAlphaComponent(0.43),
                cornerRadius: 8
            )
            addBlock(
                to: node,
                size: CGSize(width: 48, height: 74),
                position: .zero,
                color: UIColor(red: 0.90, green: 0.28, blue: 0.51, alpha: 1),
                cornerRadius: 7
            )
            addBlock(
                to: node,
                size: CGSize(width: 37, height: 29),
                position: CGPoint(x: 0, y: 11),
                color: UIColor(red: 0.20, green: 0.18, blue: 0.42, alpha: 1),
                cornerRadius: 5
            )
            addBlock(
                to: node,
                size: CGSize(width: 38, height: 9),
                position: CGPoint(x: 0, y: -29),
                color: UIColor(red: 0.58, green: 0.20, blue: 0.42, alpha: 1),
                cornerRadius: 3
            )
            for x in [-15.0, 15.0] {
                addBlock(
                    to: node,
                    size: CGSize(width: 9, height: 7),
                    position: CGPoint(x: x, y: -33),
                    color: UIColor(red: 1.0, green: 0.58, blue: 0.30, alpha: 1),
                    cornerRadius: 2
                )
            }
            for x in [-27.0, 27.0] {
                for y in [-21.0, 21.0] {
                    addBlock(
                        to: node,
                        size: CGSize(width: 8, height: 16),
                        position: CGPoint(x: x, y: y),
                        color: UIColor(red: 0.035, green: 0.025, blue: 0.075, alpha: 1),
                        cornerRadius: 2
                    )
                }
            }
        }
        return node
    }

    private func runNearMissFeedback(bonus: Int) {
        worldNode.removeAction(forKey: "feedbackMotion")
        worldNode.position = .zero
        worldNode.run(
            .sequence([
                .moveBy(x: -5, y: -2, duration: 0.035),
                .moveBy(x: 9, y: 3, duration: 0.045),
                .moveBy(x: -4, y: -1, duration: 0.045)
            ]),
            withKey: "feedbackMotion"
        )

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
        let offsets: [(CGFloat, CGFloat)] = [
            (-12, 5), (8, -8), (15, 10), (-18, -5),
            (14, -9), (-9, 7), (5, -3), (-3, 3)
        ]
        worldNode.run(
            .sequence(offsets.map { .moveBy(x: $0.0, y: $0.1, duration: 0.035) }),
            withKey: "feedbackMotion"
        )

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

    private func addBlock(
        to parent: SKNode,
        size: CGSize,
        position: CGPoint,
        color: UIColor,
        cornerRadius: CGFloat,
        rotation: CGFloat = 0
    ) {
        let block = SKShapeNode(rectOf: size, cornerRadius: cornerRadius)
        block.position = position
        block.zRotation = rotation
        block.fillColor = color
        block.strokeColor = .clear
        parent.addChild(block)
    }
}
