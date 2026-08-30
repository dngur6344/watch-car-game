import SpriteKit

@MainActor
final class GameScene: SKScene {
    typealias SteeringProvider = @MainActor (TimeInterval) -> Double
    typealias FrameHandler = @MainActor (GameSnapshot, [GameEventPresentation]) -> Void
#if DEBUG
    typealias FrameRateHandler = @MainActor (Double) -> Void
#endif

    static let fixedStep: TimeInterval = 1.0 / 60.0
    static let maximumStepsPerFrame = 5
    static let skyAuthoredHorizonFraction: CGFloat = 0.10
    static let maximumEdgeStreakCount = 20
    static let maximumRoadLightCount = 12
    static let maximumFogBandCount = 6
    static let maximumCollisionDebrisCount = 18
    static let maximumScorePopCount = 3
    static let trackCurveSampleCount = 18
    static let trackCurbSegmentCountPerSide = 14
    static let collisionHitStopDuration: TimeInterval = 0.065
    static let collisionRecoilEndTime: TimeInterval = 0.405
    static let collisionSettleEndTime: TimeInterval = 0.500
    static let collisionTotalDuration: TimeInterval = 0.520
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
    private(set) var accessibilityPolicy = SensoryAccessibilityPolicy(
        settings: .defaultValue,
        reduceMotion: false,
        reduceTransparency: false
    )
    let appearance: VehicleAppearance
    let assetLibrary: GameAssetLibrary

    var configuration: GameSimulation.Configuration {
        simulation.configuration
    }

    private var simulation: GameSimulation
    private let obstacleSpriteFactory: ObstacleSpriteFactory
    private var previousUpdateTime: TimeInterval?
    private var accumulatedTime: TimeInterval = 0
    private var routedSteering: Double = 0
    private var didBuildScene = false
#if DEBUG
    private var frameRateFrameCount = 0
    private var frameRateElapsedTime: TimeInterval = 0
#endif

    private let continuousCameraNode = SKNode()
    private let impactCameraNode = SKNode()
    private let worldNode = SKNode()
    private let skyNode: SKSpriteNode
    private let roadShadowNode = SKShapeNode()
    private let roadNode = SKShapeNode()
    private let trackCurbContainer = SKNode()
    private let roadDecalContainer = SKNode()
    private let laneContainer = SKNode()
    private let guardrailContainer = SKNode()
    private let roadsideContainer = SKNode()
    private let fogContainer = SKNode()
    private let roadLightContainer = SKNode()
    private let edgeStreakContainer = SKNode()
    private let obstacleContainer = SKNode()
    private let playerNode: VehicleSpriteNode
    private let impactContainer = SKNode()
    private let scorePopContainer = SKNode()
    private let nearMissEdgeContainer = SKNode()
    private let flashNode = SKShapeNode()
    private let mapTextures: MapTextures
    private var roadDecals: [RoadDecal] = []
    private var laneMarks: [(node: SKSpriteNode, separatorX: Double, index: Int)] = []
    private var trackCurbs: [(node: SKShapeNode, side: Double, index: Int)] = []
    private var guardrails: [(node: SKShapeNode, side: Double)] = []
    private var roadsideProps: [RoadsideProp] = []
    private var fogBands: [SKShapeNode] = []
    private var roadLights: [SKShapeNode] = []
    private var edgeStreaks: [SKShapeNode] = []
    private var collisionDebris: [SKShapeNode] = []
    private var scorePopLabels: [SKLabelNode] = []
    private var nearMissEdgeNodes: [(side: FeedbackSide, node: SKShapeNode)] = []
    private var obstacleNodes: [UInt64: SKNode] = [:]
    private var presentedFeedbackIDs: Set<UUID> = []
    private var nextScorePopIndex = 0
    private var visibleNearMissSide: FeedbackSide?
    private var visibleNearMissGrade: NearMissFeedbackGrade?
    private var collisionImpactSide: FeedbackSide?
    private var collisionImpactObstacleID: UInt64?
    private(set) var isCollisionPresentationActive = false

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

    struct PresentationDiagnostics {
        let bodyRotation: CGFloat
        let paintOffset: CGPoint
        let detailsOffset: CGPoint
        let shadowPosition: CGPoint
        let shadowScale: CGPoint
        let shadowAlpha: CGFloat
        let continuousCameraPosition: CGPoint
        let continuousCameraScale: CGFloat
        let impactCameraPosition: CGPoint
        let impactCameraScale: CGFloat
        let vehicleImpactPosition: CGPoint
        let vehicleImpactRotation: CGFloat
        let obstacleImpactPosition: CGPoint?
        let collisionImpactSide: FeedbackSide?
        let isCollisionPresentationActive: Bool
        let edgeStreakNodeCount: Int
        let activeEdgeStreakCount: Int
        let edgeStreakPositions: [CGPoint]
        let roadLightNodeCount: Int
        let activeRoadLightCount: Int
        let roadLightPositions: [CGPoint]
        let fogBandNodeCount: Int
        let activeFogBandCount: Int
        let fogBandPositions: [CGPoint]
        let debrisNodeCount: Int
        let activeDebrisCount: Int
        let scheduledDebrisCount: Int
        let visibleNearMissSide: FeedbackSide?
        let visibleNearMissGrade: NearMissFeedbackGrade?
        let visibleEdgeLineWidth: CGFloat
        let visibleEdgeAlpha: CGFloat
        let flashAlpha: CGFloat
        let visibleScorePosition: CGPoint?
        let visibleScoreScale: CGFloat?
        let visibleScoreTexts: [String]
        let nodesWithActions: Int
        let unexpectedFeedbackNodeCount: Int
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

        var presentationEvents: [GameEventPresentation] = []
        var stepCount = 0
        while accumulatedTime >= Self.fixedStep, stepCount < Self.maximumStepsPerFrame {
            let steering = steeringProvider(Self.fixedStep)
            routedSteering = steering.isFinite ? min(max(steering, -1), 1) : 0
            let stepEvents = simulation.step(dt: Self.fixedStep, steering: steering)
            let stepSnapshot = simulation.snapshot
            presentationEvents.append(
                contentsOf: stepEvents.map { event in
                    GameEventPresentation(
                        event: event,
                        snapshot: stepSnapshot,
                        configuration: simulation.configuration
                    )
                }
            )
            accumulatedTime -= Self.fixedStep
            stepCount += 1
        }

        currentSnapshot = simulation.snapshot
        render(currentSnapshot)
        frameHandler?(currentSnapshot, presentationEvents)
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
        routedSteering = 0
        resetPresentationState()
        obstacleNodes.values.forEach { $0.removeFromParent() }
        obstacleNodes.removeAll(keepingCapacity: true)
        render(currentSnapshot)
        frameHandler?(currentSnapshot, [])
    }

    func setReduceMotionEnabled(_ enabled: Bool) {
        var settings = SensorySettings.defaultValue
        settings.effectIntensity = accessibilityPolicy.body == .reduced ? .reduced : .balanced
        setAccessibilityPolicy(
            SensoryAccessibilityPolicy(
                settings: settings,
                reduceMotion: enabled,
                reduceTransparency: accessibilityPolicy.usesOpaqueFeedback
            )
        )
    }

    func setAccessibilityPolicy(_ policy: SensoryAccessibilityPolicy) {
        accessibilityPolicy = policy
        reduceMotionEnabled = policy.camera == .off
        if policy.camera == .off {
            impactCameraNode.removeAction(forKey: "feedbackMotion")
            impactCameraNode.position = .zero
            impactCameraNode.zRotation = 0
            impactCameraNode.setScale(1)
            playerNode.impactPresentationNode.removeAllActions()
            playerNode.impactPresentationNode.position = .zero
            playerNode.impactPresentationNode.zRotation = 0
            playerNode.impactPresentationNode.setScale(1)
            resetCollisionObstacleTransform()
        }
        if policy.debris == .off {
            resetCollisionDebris()
        }
        render(currentSnapshot)
    }

    func stopPresentation() {
        resetPresentationState()
    }

    func finishCollisionPresentation() {
        resetCollisionPresentation()
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
            runNearMissFeedback(feedback: feedback, bonus: bonus)
        case .collision:
            runCollisionFeedback(feedback: feedback)
        }
    }

    private func buildSceneIfNeeded() {
        guard !didBuildScene else {
            return
        }
        didBuildScene = true
        backgroundColor = UIColor(red: 0.12, green: 0.10, blue: 0.41, alpha: 1)

        continuousCameraNode.zPosition = 0
        continuousCameraNode.name = "presentation.camera.continuous"
        addChild(continuousCameraNode)

        impactCameraNode.name = "presentation.camera.impact"
        continuousCameraNode.addChild(impactCameraNode)

        worldNode.name = "feedback.world"
        impactCameraNode.addChild(worldNode)

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

        trackCurbContainer.name = "map.trackCurbs"
        trackCurbContainer.zPosition = 0.6
        worldNode.addChild(trackCurbContainer)
        buildTrackCurbs()

        roadDecalContainer.name = "map.roadDecals"
        roadDecalContainer.zPosition = 1
        worldNode.addChild(roadDecalContainer)
        buildRoadDecals()

        laneContainer.name = "map.lanes"
        laneContainer.zPosition = 2
        worldNode.addChild(laneContainer)
        buildLaneMarks()

        fogContainer.name = "presentation.fog"
        fogContainer.zPosition = 3
        worldNode.addChild(fogContainer)
        buildFogBands()

        roadLightContainer.name = "presentation.roadLights"
        roadLightContainer.zPosition = 4
        worldNode.addChild(roadLightContainer)
        buildRoadLights()

        guardrailContainer.name = "map.guardrails"
        guardrailContainer.zPosition = 4.6
        worldNode.addChild(guardrailContainer)
        buildGuardrails()

        roadsideContainer.name = "map.roadside"
        roadsideContainer.zPosition = 5
        worldNode.addChild(roadsideContainer)
        buildRoadsideProps()

        obstacleContainer.zPosition = 10
        worldNode.addChild(obstacleContainer)

        playerNode.name = "vehicle.player"
        playerNode.zPosition = 100
        worldNode.addChild(playerNode)

        edgeStreakContainer.name = "presentation.edgeStreaks"
        edgeStreakContainer.zPosition = 140
        worldNode.addChild(edgeStreakContainer)
        buildEdgeStreaks()

        impactContainer.zPosition = 220
        impactContainer.name = "feedback.impact"
        worldNode.addChild(impactContainer)
        buildCollisionDebris()

        scorePopContainer.zPosition = 520
        scorePopContainer.name = "feedback.scorePop"
        addChild(scorePopContainer)
        buildScorePopLabels()

        nearMissEdgeContainer.zPosition = 510
        nearMissEdgeContainer.name = "feedback.nearMissEdge"
        addChild(nearMissEdgeContainer)
        buildNearMissEdgeNodes()

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
        let skyWidth = ceil(size.width * 1.24) + 2
        let skyHeight = skyWidth / skyAspectRatio
        skyNode.size = CGSize(width: skyWidth, height: skyHeight)
        skyNode.position = CGPoint(
            x: size.width / 2,
            y: projection.horizonY
                + (0.5 - Self.skyAuthoredHorizonFraction) * skyHeight
        )

        renderTrackGeometry(
            snapshot: currentSnapshot,
            projection: makeTrackProjection(for: currentSnapshot, road: projection)
        )

        flashNode.path = CGPath(rect: CGRect(origin: .zero, size: size), transform: nil)

        for (index, band) in fogBands.enumerated() {
            band.xScale = size.width * (0.42 + CGFloat(index % 3) * 0.11)
        }
        for edge in nearMissEdgeNodes {
            switch edge.side {
            case .left:
                edge.node.position = CGPoint(x: 8, y: size.height * 0.52)
            case .center:
                edge.node.position = CGPoint(x: size.width / 2, y: size.height - 12)
            case .right:
                edge.node.position = CGPoint(x: size.width - 8, y: size.height * 0.52)
            }
        }
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

    private func buildTrackCurbs() {
        for side in [-1.0, 1.0] {
            for index in 0..<Self.trackCurbSegmentCountPerSide {
                let node = SKShapeNode(rectOf: CGSize(width: 1, height: 1))
                node.name = "map.trackCurb.\(side < 0 ? "left" : "right").\(index)"
                node.fillColor = index.isMultiple(of: 2)
                    ? UIColor(red: 0.96, green: 0.20, blue: 0.25, alpha: 1)
                    : UIColor(white: 0.96, alpha: 1)
                node.strokeColor = UIColor(white: 1, alpha: 0.24)
                node.lineWidth = 0.7
                trackCurbContainer.addChild(node)
                trackCurbs.append((node, side, index))
            }
        }
    }

    private func buildGuardrails() {
        for side in [-1.0, 1.0] {
            let node = SKShapeNode()
            node.name = "map.guardrail.\(side < 0 ? "left" : "right")"
            node.strokeColor = UIColor(red: 0.66, green: 0.97, blue: 0.91, alpha: 0.82)
            node.lineWidth = 2.2
            node.lineCap = .round
            guardrailContainer.addChild(node)
            guardrails.append((node, side))
        }
    }

    private func buildFogBands() {
        for index in 0..<Self.maximumFogBandCount {
            let node = SKShapeNode(
                rectOf: CGSize(width: 1, height: 14 + CGFloat(index % 3) * 5),
                cornerRadius: 7
            )
            node.name = "presentation.fog.\(index)"
            node.fillColor = UIColor(red: 0.39, green: 0.78, blue: 0.82, alpha: 1)
            node.strokeColor = .clear
            node.alpha = 0
            node.isHidden = true
            fogContainer.addChild(node)
            fogBands.append(node)
        }
    }

    private func buildRoadLights() {
        for index in 0..<Self.maximumRoadLightCount {
            let node = SKShapeNode(circleOfRadius: 3.5 + CGFloat(index % 2))
            node.name = "presentation.roadLight.\(index)"
            node.fillColor = index.isMultiple(of: 2)
                ? UIColor(red: 0.34, green: 1, blue: 0.84, alpha: 1)
                : UIColor(red: 1, green: 0.73, blue: 0.30, alpha: 1)
            node.strokeColor = .white
            node.lineWidth = 0.8
            node.alpha = 0
            node.isHidden = true
            roadLightContainer.addChild(node)
            roadLights.append(node)
        }
    }

    private func buildEdgeStreaks() {
        for index in 0..<Self.maximumEdgeStreakCount {
            let node = SKShapeNode(
                rectOf: CGSize(
                    width: 1.5 + CGFloat(index % 3) * 0.45,
                    height: 19 + CGFloat(index % 4) * 6
                ),
                cornerRadius: 1
            )
            node.name = "presentation.edgeStreak.\(index)"
            node.fillColor = index.isMultiple(of: 2)
                ? UIColor(red: 0.36, green: 0.98, blue: 0.88, alpha: 1)
                : UIColor(red: 1, green: 0.57, blue: 0.31, alpha: 1)
            node.strokeColor = .clear
            node.alpha = 0
            node.isHidden = true
            edgeStreakContainer.addChild(node)
            edgeStreaks.append(node)
        }
    }

    private func buildCollisionDebris() {
        let colors = [
            UIColor(red: 1, green: 0.76, blue: 0.25, alpha: 1),
            UIColor(red: 1, green: 0.34, blue: 0.42, alpha: 1),
            UIColor(red: 0.48, green: 0.93, blue: 0.84, alpha: 1),
        ]
        for index in 0..<Self.maximumCollisionDebrisCount {
            let node = SKShapeNode(
                rectOf: CGSize(
                    width: 5 + CGFloat(index % 3) * 2,
                    height: 5 + CGFloat((index + 1) % 3) * 2
                ),
                cornerRadius: 1
            )
            node.name = "feedback.debris.\(index)"
            node.fillColor = colors[index % colors.count]
            node.strokeColor = .clear
            node.alpha = 0
            node.isHidden = true
            impactContainer.addChild(node)
            collisionDebris.append(node)
        }
    }

    private func buildScorePopLabels() {
        for index in 0..<Self.maximumScorePopCount {
            let label = SKLabelNode(fontNamed: "AvenirNext-Heavy")
            label.name = "feedback.scoreLabel.\(index)"
            label.fontSize = 22
            label.horizontalAlignmentMode = .center
            label.verticalAlignmentMode = .center
            label.alpha = 0
            label.isHidden = true
            scorePopContainer.addChild(label)
            scorePopLabels.append(label)
        }
    }

    private func buildNearMissEdgeNodes() {
        for side in [FeedbackSide.left, .center, .right] {
            let size = switch side {
            case .left, .right:
                CGSize(width: 9, height: 116)
            case .center:
                CGSize(width: 142, height: 9)
            }
            let node = SKShapeNode(rectOf: size, cornerRadius: 4.5)
            node.name = "feedback.nearMissEdge.\(String(describing: side))"
            node.fillColor = .white
            node.strokeColor = .clear
            node.alpha = 0
            node.isHidden = true
            nearMissEdgeContainer.addChild(node)
            nearMissEdgeNodes.append((side, node))
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
        let roadProjection = makeProjection(for: snapshot)
        let projection = makeTrackProjection(for: snapshot, road: roadProjection)
        renderTrackGeometry(snapshot: snapshot, projection: projection)
        renderRoadDecals(snapshot: snapshot, projection: projection)
        renderLaneMarks(snapshot: snapshot, projection: projection)
        renderRoadsideProps(snapshot: snapshot, projection: projection)
        renderPresentation(snapshot: snapshot, projection: projection)

        let playerProjection = projection.project(lateral: snapshot.playerX, distance: 0)
        playerNode.position = playerProjection.point
        playerNode.setScale(playerProjection.scale)
        playerNode.zRotation = projection.heading(at: 0)

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
            node.zRotation = projection.heading(at: obstacle.distance)
            node.zPosition = 1 - projected.normalizedDepth
            node.isHidden = obstacle.distance < -3 || obstacle.distance > projection.maximumDistance + 2
        }
    }

    private func renderTrackGeometry(
        snapshot: GameSnapshot,
        projection: TrackPerspectiveProjection
    ) {
        skyNode.position.x = size.width / 2
            - projection.centerOffset(at: projection.maximumDistance) * 0.18
        let distances = (0...Self.trackCurveSampleCount).map { index in
            projection.maximumDistance * Double(index) / Double(Self.trackCurveSampleCount)
        }
        let leftEdge = distances.map {
            projection.project(lateral: -snapshot.roadHalfWidth, distance: $0).point
        }
        let rightEdge = distances.map {
            projection.project(lateral: snapshot.roadHalfWidth, distance: $0).point
        }

        let roadPath = CGMutablePath()
        if let first = leftEdge.first {
            roadPath.move(to: CGPoint(x: 0, y: 0))
            roadPath.addLine(to: first)
            leftEdge.dropFirst().forEach { roadPath.addLine(to: $0) }
            rightEdge.reversed().forEach { roadPath.addLine(to: $0) }
            roadPath.addLine(to: CGPoint(x: size.width, y: 0))
            roadPath.closeSubpath()
        }
        roadNode.path = roadPath

        let shadowOffset = CGPoint(x: 7, y: -5)
        let shadowPath = CGMutablePath()
        if let first = leftEdge.first {
            shadowPath.move(to: CGPoint(
                x: first.x + shadowOffset.x,
                y: first.y + shadowOffset.y
            ))
            leftEdge.dropFirst().forEach { point in
                shadowPath.addLine(to: CGPoint(
                    x: point.x + shadowOffset.x,
                    y: point.y + shadowOffset.y
                ))
            }
            rightEdge.reversed().forEach { point in
                shadowPath.addLine(to: CGPoint(
                    x: point.x + shadowOffset.x,
                    y: point.y + shadowOffset.y
                ))
            }
            shadowPath.closeSubpath()
        }
        roadShadowNode.path = shadowPath

        let curbDepth = projection.maximumDistance / Double(Self.trackCurbSegmentCountPerSide)
        for curb in trackCurbs {
            let nearDistance = Double(curb.index) * curbDepth
            let farDistance = min(nearDistance + curbDepth, projection.maximumDistance)
            let innerLateral = curb.side * snapshot.roadHalfWidth * 0.965
            let outerLateral = curb.side * (snapshot.roadHalfWidth + 0.24)
            let innerNear = projection.project(
                lateral: innerLateral,
                distance: nearDistance
            ).point
            let innerFar = projection.project(
                lateral: innerLateral,
                distance: farDistance
            ).point
            let outerFar = projection.project(
                lateral: outerLateral,
                distance: farDistance
            ).point
            let outerNear = projection.project(
                lateral: outerLateral,
                distance: nearDistance
            ).point
            let nearCenter = CGPoint(
                x: (innerNear.x + outerNear.x) / 2,
                y: (innerNear.y + outerNear.y) / 2
            )
            let farCenter = CGPoint(
                x: (innerFar.x + outerFar.x) / 2,
                y: (innerFar.y + outerFar.y) / 2
            )
            let deltaX = farCenter.x - nearCenter.x
            let deltaY = farCenter.y - nearCenter.y
            let nearWidth = hypot(outerNear.x - innerNear.x, outerNear.y - innerNear.y)
            let farWidth = hypot(outerFar.x - innerFar.x, outerFar.y - innerFar.y)
            curb.node.position = CGPoint(
                x: (nearCenter.x + farCenter.x) / 2,
                y: (nearCenter.y + farCenter.y) / 2
            )
            curb.node.xScale = max((nearWidth + farWidth) / 2, 0.5)
            curb.node.yScale = max(hypot(deltaX, deltaY), 0.5)
            curb.node.zRotation = -atan2(deltaX, deltaY)
            curb.node.zPosition = 1 - projection.project(
                lateral: innerLateral,
                distance: nearDistance
            ).normalizedDepth
        }

        for guardrail in guardrails {
            let path = CGMutablePath()
            for (index, distance) in distances.enumerated() {
                let point = projection.project(
                    lateral: guardrail.side * (snapshot.roadHalfWidth + 0.62),
                    distance: distance
                ).point
                if index == 0 {
                    path.move(to: point)
                } else {
                    path.addLine(to: point)
                }
            }
            guardrail.node.path = path
        }
    }

    private func renderRoadDecals(
        snapshot: GameSnapshot,
        projection: TrackPerspectiveProjection
    ) {
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
            decal.node.zRotation = projection.heading(at: distance)
            decal.node.zPosition = 1 - projected.normalizedDepth
            decal.node.isHidden = distance > projection.maximumDistance
        }
    }

    private func renderLaneMarks(
        snapshot: GameSnapshot,
        projection: TrackPerspectiveProjection
    ) {
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
            let deltaX = farPoint.point.x - nearPoint.point.x
            let deltaY = farPoint.point.y - nearPoint.point.y
            let length = max(hypot(deltaX, deltaY), 1)

            mark.node.position = CGPoint(
                x: (nearPoint.point.x + farPoint.point.x) / 2,
                y: (nearPoint.point.y + farPoint.point.y) / 2
            )
            mark.node.xScale = max(nearPoint.scale, 0.2)
            mark.node.yScale = length / 40
            mark.node.zRotation = -atan2(deltaX, deltaY)
            mark.node.alpha = 0.68 + speedProgress * 0.30
            mark.node.isHidden = distance > projection.maximumDistance
        }
    }

    private func renderRoadsideProps(
        snapshot: GameSnapshot,
        projection: TrackPerspectiveProjection
    ) {
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

    private func renderPresentation(
        snapshot: GameSnapshot,
        projection: TrackPerspectiveProjection
    ) {
        let speedRange = max(
            simulation.configuration.maximumSpeed - simulation.configuration.initialSpeed,
            0.001
        )
        let speedProgress = min(
            max((snapshot.speed - simulation.configuration.initialSpeed) / speedRange, 0),
            1
        )
        playerNode.applyPresentation(
            speedProgress: speedProgress,
            steering: routedSteering,
            level: accessibilityPolicy.body
        )
        renderContinuousCamera(
            speedProgress: speedProgress,
            steering: routedSteering,
            trackHeading: projection.heading(at: 1.5, sampleLength: 4)
        )
        renderEdgeStreaks(
            distance: snapshot.distance,
            speedProgress: speedProgress
        )
        renderRoadLights(snapshot: snapshot, projection: projection)
        renderFogBands(distance: snapshot.distance, speedProgress: speedProgress)
    }

    private func renderContinuousCamera(
        speedProgress: Double,
        steering: Double,
        trackHeading: CGFloat
    ) {
        let amplitude = effectAmplitude(accessibilityPolicy.camera)
        let clampedSteering = CGFloat(min(max(steering.isFinite ? steering : 0, -1), 1))
        let clampedSpeed = CGFloat(min(max(speedProgress.isFinite ? speedProgress : 0, 0), 1))
        let scale = 1 + clampedSpeed * 0.018 * amplitude
        let translation = CGPoint(
            x: -clampedSteering * clampedSpeed * 3.5 * amplitude,
            y: -clampedSpeed * 2.5 * amplitude
        )
        let center = CGPoint(x: size.width / 2, y: size.height / 2)

        continuousCameraNode.xScale = scale
        continuousCameraNode.yScale = scale
        continuousCameraNode.zRotation = trackHeading * 0.10 * amplitude
        continuousCameraNode.position = CGPoint(
            x: center.x * (1 - scale) + translation.x,
            y: center.y * (1 - scale) + translation.y
        )
    }

    private func renderEdgeStreaks(distance: Double, speedProgress: Double) {
        let activeCount = activeCount(
            for: accessibilityPolicy.streaks,
            maximum: Self.maximumEdgeStreakCount
        )
        let amplitude = effectAmplitude(accessibilityPolicy.streaks)
        let clampedSpeed = CGFloat(min(max(speedProgress, 0), 1))
        let showsStreaks = clampedSpeed >= 0.08 && activeCount > 0

        for (index, node) in edgeStreaks.enumerated() {
            let isActive = showsStreaks && index < activeCount
            node.isHidden = !isActive
            guard isActive else {
                node.alpha = 0
                continue
            }

            let phase = (distance * 0.047 + Double(index) / Double(Self.maximumEdgeStreakCount))
                .truncatingRemainder(dividingBy: 1)
            let isLeft = index.isMultiple(of: 2)
            let edgeInset = CGFloat(14 + (index % 5) * 7)
            node.position = CGPoint(
                x: isLeft ? edgeInset : size.width - edgeInset,
                y: CGFloat(phase) * size.height
            )
            node.xScale = 1
            node.yScale = 1 + clampedSpeed * 1.25 * amplitude
            node.alpha = accessibilityPolicy.usesOpaqueFeedback
                ? 0.78
                : 0.12 + clampedSpeed * 0.34 * max(amplitude, 0.45)
        }
    }

    private func renderRoadLights(
        snapshot: GameSnapshot,
        projection: TrackPerspectiveProjection
    ) {
        let activeCount = activeCount(
            for: accessibilityPolicy.roadLights,
            maximum: Self.maximumRoadLightCount
        )
        let cycleLength = 4 * Double(Self.maximumRoadLightCount)
        let travel = snapshot.distance.truncatingRemainder(dividingBy: cycleLength)

        for (index, node) in roadLights.enumerated() {
            let isActive = index < activeCount
            node.isHidden = !isActive
            guard isActive else {
                node.alpha = 0
                continue
            }

            var distance = 1.6 + Double(index) * 4 - travel
            while distance < 1.2 {
                distance += cycleLength
            }
            let side: Double = index.isMultiple(of: 2) ? -1 : 1
            let projected = projection.project(
                lateral: side * (snapshot.roadHalfWidth + 0.48),
                distance: distance
            )
            node.position = projected.point
            node.setScale(max(projected.scale * 0.82, 0.16))
            node.zPosition = 1 - projected.normalizedDepth
            node.alpha = 0.30 + 0.36 * effectAmplitude(accessibilityPolicy.roadLights)
            node.isHidden = distance > projection.maximumDistance
        }
    }

    private func renderFogBands(distance: Double, speedProgress: Double) {
        let activeCount = activeCount(
            for: accessibilityPolicy.fog,
            maximum: Self.maximumFogBandCount
        )
        let amplitude = effectAmplitude(accessibilityPolicy.fog)
        let travel = accessibilityPolicy.allowsFogMotion ? distance * 0.006 : 0

        for (index, node) in fogBands.enumerated() {
            let isActive = index < activeCount
            node.isHidden = !isActive
            guard isActive else {
                node.alpha = 0
                continue
            }

            let phase = (travel + Double(index) / Double(Self.maximumFogBandCount))
                .truncatingRemainder(dividingBy: 1)
            node.position = CGPoint(
                x: size.width * (0.34 + CGFloat(index % 3) * 0.16),
                y: size.height * (0.24 + CGFloat(phase) * 0.46)
            )
            node.alpha = (0.035 + CGFloat(speedProgress) * 0.032) * max(amplitude, 0.45)
        }
    }

    private func effectAmplitude(
        _ level: SensoryAccessibilityPolicy.DecorativeEffectLevel
    ) -> CGFloat {
        switch level {
        case .balanced:
            1
        case .reduced:
            0.45
        case .off:
            0
        }
    }

    private func activeCount(
        for level: SensoryAccessibilityPolicy.DecorativeEffectLevel,
        maximum: Int
    ) -> Int {
        switch level {
        case .balanced:
            maximum
        case .reduced:
            (maximum + 1) / 2
        case .off:
            0
        }
    }

    private func makeProjection(for snapshot: GameSnapshot) -> RoadProjection {
        RoadProjection(
            screenSize: size,
            roadHalfWidth: snapshot.roadHalfWidth,
            maximumDistance: max(simulation.configuration.spawnDistance + 4, 52)
        )
    }

    private func makeTrackProjection(
        for snapshot: GameSnapshot,
        road: RoadProjection
    ) -> TrackPerspectiveProjection {
        TrackPerspectiveProjection(road: road, travel: snapshot.distance)
    }

    private func makeObstacleNode(for obstacle: ObstacleSnapshot) -> SKNode {
        let root = SKNode()
        root.name = "obstacle.root.\(obstacle.id)"
        let impactPresentation = SKNode()
        impactPresentation.name = "obstacle.presentation.impact"
        impactPresentation.addChild(obstacleSpriteFactory.makeNode(for: obstacle))
        root.addChild(impactPresentation)
        return root
    }

    private func runNearMissFeedback(feedback: GameFeedback, bonus: Int) {
        let side = feedback.spatialContext?.side ?? .center
        let grade = feedback.nearMissGrade ?? .standard
        let amplitude = effectAmplitude(accessibilityPolicy.camera)

        impactCameraNode.removeAction(forKey: "feedbackMotion")
        impactCameraNode.position = .zero
        impactCameraNode.zRotation = 0
        impactCameraNode.setScale(1)
        if amplitude > 0 {
            let direction: CGFloat = switch side {
            case .left:
                -1
            case .center:
                0
            case .right:
                1
            }
            let gradeAmplitude: CGFloat = grade == .strong ? 1.25 : 1
            impactCameraNode.run(
                .sequence([
                    .moveBy(
                        x: direction * 5 * amplitude * gradeAmplitude,
                        y: -2 * amplitude,
                        duration: 0.035
                    ),
                    .moveBy(
                        x: -direction * 8 * amplitude * gradeAmplitude,
                        y: 3 * amplitude,
                        duration: 0.045
                    ),
                    .moveBy(
                        x: direction * 3 * amplitude * gradeAmplitude,
                        y: -amplitude,
                        duration: 0.045
                    ),
                ]),
                withKey: "feedbackMotion"
            )
        }

        flashNode.removeAction(forKey: "feedbackFlash")
        flashNode.fillColor = accessibilityPolicy.usesOpaqueFeedback
            ? UIColor.white
            : UIColor(red: 0.34, green: 1, blue: 0.84, alpha: 1)
        flashNode.alpha = accessibilityPolicy.usesOpaqueFeedback
            ? (grade == .strong ? 0.92 : 0.72)
            : (grade == .strong ? 0.32 : 0.22)
        flashNode.run(.fadeOut(withDuration: 0.16), withKey: "feedbackFlash")

        presentNearMissEdge(side: side, grade: grade)
        presentScorePop(bonus: bonus, grade: grade)
    }

    private func presentNearMissEdge(side: FeedbackSide, grade: NearMissFeedbackGrade) {
        visibleNearMissSide = side
        visibleNearMissGrade = grade
        for edge in nearMissEdgeNodes {
            edge.node.removeAllActions()
            edge.node.isHidden = edge.side != side
            guard edge.side == side else {
                edge.node.alpha = 0
                continue
            }

            let isStrong = grade == .strong
            edge.node.fillColor = accessibilityPolicy.usesOpaqueFeedback
                ? (isStrong ? .white : .yellow)
                : (isStrong
                    ? UIColor(red: 0.40, green: 1, blue: 0.88, alpha: 1)
                    : UIColor(red: 1, green: 0.72, blue: 0.24, alpha: 1))
            edge.node.strokeColor = isStrong ? .white : .clear
            edge.node.lineWidth = isStrong ? 3 : 0
            edge.node.alpha = accessibilityPolicy.usesOpaqueFeedback
                ? (isStrong ? 1 : 0.88)
                : (isStrong ? 0.92 : 0.62)
            edge.node.run(
                .sequence([
                    .wait(forDuration: isStrong ? 0.16 : 0.12),
                    .fadeOut(withDuration: isStrong ? 0.24 : 0.18),
                    .run { [weak node = edge.node] in
                        node?.isHidden = true
                    },
                ]),
                withKey: "edgeCue"
            )
        }
    }

    private func presentScorePop(bonus: Int, grade: NearMissFeedbackGrade) {
        guard !scorePopLabels.isEmpty else { return }
        let label = scorePopLabels[nextScorePopIndex]
        nextScorePopIndex = (nextScorePopIndex + 1) % scorePopLabels.count
        label.removeAllActions()
        label.text = "NEAR MISS +\(bonus)"
        label.fontColor = grade == .strong
            ? UIColor(red: 0.48, green: 1, blue: 0.88, alpha: 1)
            : UIColor(red: 1, green: 0.86, blue: 0.33, alpha: 1)
        label.position = CGPoint(x: size.width / 2, y: size.height * 0.42)
        label.alpha = 1
        label.isHidden = false

        let amplitude = effectAmplitude(accessibilityPolicy.body)
        guard amplitude > 0 else {
            label.setScale(1)
            label.run(
                .sequence([
                    .wait(forDuration: 0.44),
                    .fadeOut(withDuration: 0.24),
                    .run { [weak label] in label?.isHidden = true },
                ])
            )
            return
        }

        label.setScale(1 - 0.18 * amplitude)
        label.run(
            .sequence([
                .group([
                    .scale(to: 1 + 0.08 * amplitude, duration: 0.10),
                    .moveBy(x: 0, y: 12 * amplitude, duration: 0.10),
                ]),
                .wait(forDuration: 0.34),
                .group([
                    .fadeOut(withDuration: 0.24),
                    .moveBy(x: 0, y: 18 * amplitude, duration: 0.24),
                ]),
                .run { [weak label] in label?.isHidden = true },
            ])
        )
    }

    private func runCollisionFeedback(feedback: GameFeedback) {
        resetCollisionPresentation()
        isCollisionPresentationActive = true
        collisionImpactSide = feedback.spatialContext?.side ?? .center
        collisionImpactObstacleID = feedback.obstacleID
        let amplitude = effectAmplitude(accessibilityPolicy.camera)

        flashNode.removeAction(forKey: "feedbackFlash")
        flashNode.fillColor = accessibilityPolicy.usesOpaqueFeedback
            ? .white
            : UIColor(red: 1, green: 0.29, blue: 0.36, alpha: 1)
        flashNode.alpha = accessibilityPolicy.usesOpaqueFeedback ? 1 : 0.64
        flashNode.run(
            .sequence([
                .wait(forDuration: Self.collisionHitStopDuration),
                .fadeAlpha(
                    to: accessibilityPolicy.usesOpaqueFeedback ? 0.30 : 0.14,
                    duration: 0.08
                ),
                .fadeOut(withDuration: 0.30),
            ]),
            withKey: "feedbackFlash"
        )

        guard amplitude > 0 else {
            resetCollisionDebris()
            return
        }

        let awayDirection: CGFloat = switch collisionImpactSide ?? .center {
        case .left:
            1
        case .center:
            0
        case .right:
            -1
        }
        let zoom = 1 + 0.035 * amplitude
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let cameraTarget = CGPoint(
            x: center.x * (1 - zoom) + awayDirection * 22 * amplitude,
            y: center.y * (1 - zoom) - 6 * amplitude
        )
        impactCameraNode.run(
            collisionTransformAction(
                targetPosition: cameraTarget,
                targetScale: zoom,
                targetRotation: 0
            ),
            withKey: "feedbackMotion"
        )

        playerNode.impactPresentationNode.run(
            collisionTransformAction(
                targetPosition: CGPoint(
                    x: awayDirection * 15 * amplitude,
                    y: -8 * amplitude
                ),
                targetScale: 1 - 0.025 * amplitude,
                targetRotation: -awayDirection * 0.085 * amplitude
            ),
            withKey: "collisionRecoil"
        )

        if let obstacleImpactNode = collisionObstacleImpactNode {
            obstacleImpactNode.run(
                collisionTransformAction(
                    targetPosition: CGPoint(
                        x: -awayDirection * 12 * amplitude,
                        y: 10 * amplitude
                    ),
                    targetScale: 1 + 0.025 * amplitude,
                    targetRotation: awayDirection * 0.07 * amplitude
                ),
                withKey: "collisionRecoil"
            )
        }

        presentCollisionDebris()
    }

    private func collisionTransformAction(
        targetPosition: CGPoint,
        targetScale: CGFloat,
        targetRotation: CGFloat
    ) -> SKAction {
        let travelDuration = 0.245 - Self.collisionHitStopDuration
        let holdDuration = Self.collisionRecoilEndTime - 0.245
        let settleDuration = Self.collisionSettleEndTime - Self.collisionRecoilEndTime
        return .sequence([
            .wait(forDuration: Self.collisionHitStopDuration),
            .group([
                .move(to: targetPosition, duration: travelDuration),
                .scale(to: targetScale, duration: travelDuration),
                .rotate(toAngle: targetRotation, duration: travelDuration),
            ]),
            .wait(forDuration: holdDuration),
            .group([
                .move(to: .zero, duration: settleDuration),
                .scale(to: 1, duration: settleDuration),
                .rotate(toAngle: 0, duration: settleDuration),
            ]),
            .wait(forDuration: Self.collisionTotalDuration - Self.collisionSettleEndTime),
        ])
    }

    private func presentCollisionDebris() {
        resetCollisionDebris()
        let activeCount = activeCount(
            for: accessibilityPolicy.debris,
            maximum: Self.maximumCollisionDebrisCount
        )
        let amplitude = effectAmplitude(accessibilityPolicy.debris)
        guard activeCount > 0, amplitude > 0 else { return }

        for (index, particle) in collisionDebris.enumerated() where index < activeCount {
            particle.position = playerNode.position
            particle.zRotation = CGFloat(index) * 0.41
            particle.setScale(1)
            particle.alpha = 1
            particle.isHidden = true

            let angle = CGFloat(index) / CGFloat(Self.maximumCollisionDebrisCount) * 2 * .pi
            let radius = CGFloat(34 + (index % 5) * 11) * amplitude
            particle.run(
                .sequence([
                    .wait(forDuration: Self.collisionHitStopDuration),
                    .run { [weak particle] in particle?.isHidden = false },
                    .group([
                        .moveBy(
                            x: cos(angle) * radius,
                            y: sin(angle) * radius + 24 * amplitude,
                            duration: Self.collisionRecoilEndTime
                                - Self.collisionHitStopDuration
                        ),
                        .rotate(
                            byAngle: (index.isMultiple(of: 2) ? 2.4 : -2.4) * amplitude,
                            duration: Self.collisionRecoilEndTime
                                - Self.collisionHitStopDuration
                        ),
                        .fadeOut(
                            withDuration: Self.collisionRecoilEndTime
                                - Self.collisionHitStopDuration
                        ),
                        .scale(
                            to: 1 - 0.65 * amplitude,
                            duration: Self.collisionRecoilEndTime
                                - Self.collisionHitStopDuration
                        ),
                    ]),
                    .run { [weak particle] in particle?.isHidden = true },
                ])
            )
        }
    }

    private func resetCollisionDebris() {
        for particle in collisionDebris {
            particle.removeAllActions()
            particle.position = .zero
            particle.zRotation = 0
            particle.setScale(1)
            particle.alpha = 0
            particle.isHidden = true
        }
    }

    private var collisionObstacleImpactNode: SKNode? {
        guard let collisionImpactObstacleID else { return nil }
        return obstacleNodes[collisionImpactObstacleID]?
            .childNode(withName: "obstacle.presentation.impact")
    }

    private func resetCollisionObstacleTransform() {
        collisionObstacleImpactNode?.removeAllActions()
        collisionObstacleImpactNode?.position = .zero
        collisionObstacleImpactNode?.zRotation = 0
        collisionObstacleImpactNode?.setScale(1)
    }

    private func resetCollisionPresentation() {
        impactCameraNode.removeAction(forKey: "feedbackMotion")
        impactCameraNode.position = .zero
        impactCameraNode.zRotation = 0
        impactCameraNode.setScale(1)
        playerNode.impactPresentationNode.removeAllActions()
        playerNode.impactPresentationNode.position = .zero
        playerNode.impactPresentationNode.zRotation = 0
        playerNode.impactPresentationNode.setScale(1)
        resetCollisionObstacleTransform()
        resetCollisionDebris()
        flashNode.removeAction(forKey: "feedbackFlash")
        flashNode.alpha = 0
        collisionImpactSide = nil
        collisionImpactObstacleID = nil
        isCollisionPresentationActive = false
    }

    private func resetPresentationState() {
        continuousCameraNode.removeAllActions()
        continuousCameraNode.position = .zero
        continuousCameraNode.zRotation = 0
        continuousCameraNode.setScale(1)
        resetCollisionPresentation()
        worldNode.removeAllActions()
        worldNode.position = .zero
        worldNode.zRotation = 0
        worldNode.setScale(1)
        playerNode.zRotation = 0
        playerNode.resetPresentation()

        flashNode.removeAllActions()
        flashNode.alpha = 0
        for edge in nearMissEdgeNodes {
            edge.node.removeAllActions()
            edge.node.alpha = 0
            edge.node.isHidden = true
        }
        visibleNearMissSide = nil
        visibleNearMissGrade = nil

        for label in scorePopLabels {
            label.removeAllActions()
            label.position = .zero
            label.setScale(1)
            label.alpha = 0
            label.isHidden = true
        }
        nextScorePopIndex = 0
        for node in edgeStreaks + roadLights + fogBands {
            node.removeAllActions()
            node.alpha = 0
            node.isHidden = true
        }
    }

    func renderPresentationForTesting(speed: Double, steering: Double, distance: Double) {
        guard didBuildScene else { return }
        routedSteering = steering.isFinite ? min(max(steering, -1), 1) : 0
        let snapshot = GameSnapshot(
            phase: currentSnapshot.phase,
            playerX: currentSnapshot.playerX,
            playerWidth: currentSnapshot.playerWidth,
            playerLength: currentSnapshot.playerLength,
            roadHalfWidth: currentSnapshot.roadHalfWidth,
            laneWidth: currentSnapshot.laneWidth,
            obstacles: currentSnapshot.obstacles,
            score: currentSnapshot.score,
            speed: speed,
            elapsedTime: currentSnapshot.elapsedTime,
            distance: distance,
            spawnInterval: currentSnapshot.spawnInterval
        )
        let road = makeProjection(for: snapshot)
        renderPresentation(
            snapshot: snapshot,
            projection: makeTrackProjection(for: snapshot, road: road)
        )
    }

    var presentationDiagnostics: PresentationDiagnostics {
        let visibleEdge = nearMissEdgeNodes.first { !$0.node.isHidden }
        let visibleScore = scorePopLabels.first { !$0.isHidden }
        let fixedFeedbackCount = Self.maximumCollisionDebrisCount
            + Self.maximumScorePopCount
            + nearMissEdgeNodes.count
        let actualFeedbackCount = impactContainer.children.count
            + scorePopContainer.children.count
            + nearMissEdgeContainer.children.count
        return PresentationDiagnostics(
            bodyRotation: playerNode.bodyPresentationNode.zRotation,
            paintOffset: playerNode.paintNode.position,
            detailsOffset: playerNode.detailsNode.position,
            shadowPosition: playerNode.shadowNode.position,
            shadowScale: CGPoint(
                x: playerNode.shadowNode.xScale,
                y: playerNode.shadowNode.yScale
            ),
            shadowAlpha: playerNode.shadowNode.alpha,
            continuousCameraPosition: continuousCameraNode.position,
            continuousCameraScale: continuousCameraNode.xScale,
            impactCameraPosition: impactCameraNode.position,
            impactCameraScale: impactCameraNode.xScale,
            vehicleImpactPosition: playerNode.impactPresentationNode.position,
            vehicleImpactRotation: playerNode.impactPresentationNode.zRotation,
            obstacleImpactPosition: collisionObstacleImpactNode?.position,
            collisionImpactSide: collisionImpactSide,
            isCollisionPresentationActive: isCollisionPresentationActive,
            edgeStreakNodeCount: edgeStreaks.count,
            activeEdgeStreakCount: edgeStreaks.count { !$0.isHidden },
            edgeStreakPositions: edgeStreaks.map(\.position),
            roadLightNodeCount: roadLights.count,
            activeRoadLightCount: roadLights.count { !$0.isHidden },
            roadLightPositions: roadLights.map(\.position),
            fogBandNodeCount: fogBands.count,
            activeFogBandCount: fogBands.count { !$0.isHidden },
            fogBandPositions: fogBands.map(\.position),
            debrisNodeCount: collisionDebris.count,
            activeDebrisCount: collisionDebris.count { !$0.isHidden },
            scheduledDebrisCount: collisionDebris.count { $0.hasActions() },
            visibleNearMissSide: visibleNearMissSide,
            visibleNearMissGrade: visibleNearMissGrade,
            visibleEdgeLineWidth: visibleEdge?.node.lineWidth ?? 0,
            visibleEdgeAlpha: visibleEdge?.node.alpha ?? 0,
            flashAlpha: flashNode.alpha,
            visibleScorePosition: visibleScore?.position,
            visibleScoreScale: visibleScore?.xScale,
            visibleScoreTexts: scorePopLabels.compactMap { label in
                label.isHidden ? nil : label.text
            },
            nodesWithActions: descendantCount(from: self) { $0.hasActions() },
            unexpectedFeedbackNodeCount: max(actualFeedbackCount - fixedFeedbackCount, 0)
        )
    }

    private func descendantCount(
        from node: SKNode,
        matching predicate: (SKNode) -> Bool
    ) -> Int {
        (predicate(node) ? 1 : 0)
            + node.children.reduce(0) { partialResult, child in
                partialResult + descendantCount(from: child, matching: predicate)
            }
    }

}
