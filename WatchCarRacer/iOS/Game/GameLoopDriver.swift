import QuartzCore

@MainActor
final class GameLoopDriver: NSObject {
    private weak var scene: GameScene?
    private var displayLink: CADisplayLink?

    init(scene: GameScene) {
        self.scene = scene
    }

    var isRunning: Bool {
        displayLink != nil
    }

    func start() {
        guard displayLink == nil else { return }
        let link = CADisplayLink(target: self, selector: #selector(tick(_:)))
        link.preferredFrameRateRange = CAFrameRateRange(
            minimum: 50,
            maximum: 60,
            preferred: 60
        )
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    func stop() {
        displayLink?.invalidate()
        displayLink = nil
    }

    @objc private func tick(_ displayLink: CADisplayLink) {
        scene?.update(displayLink.timestamp)
    }
}
