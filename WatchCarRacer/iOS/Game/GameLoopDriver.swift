import QuartzCore
import UIKit

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
        link.preferredFrameRateRange = Self.preferredFrameRateRange(
            maximumFramesPerSecond: UIScreen.main.maximumFramesPerSecond
        )
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    static func preferredFrameRateRange(
        maximumFramesPerSecond: Int
    ) -> CAFrameRateRange {
        let supportedRate = max(min(maximumFramesPerSecond, 60), 1)
        let requestedRate = Float(supportedRate)
        return CAFrameRateRange(
            minimum: requestedRate,
            maximum: requestedRate,
            preferred: requestedRate
        )
    }

    func stop() {
        displayLink?.invalidate()
        displayLink = nil
    }

    @objc private func tick(_ displayLink: CADisplayLink) {
        scene?.update(displayLink.timestamp)
    }
}
