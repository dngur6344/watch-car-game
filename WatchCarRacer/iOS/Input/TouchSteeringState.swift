import Foundation

struct TouchSteeringState: Equatable, Sendable {
    private(set) var value = 0.0
    private(set) var isDragging = false

    private let returnRate: Double

    init(returnRate: Double = 8) {
        self.returnRate = max(returnRate, 0)
    }

    static func normalized(horizontalPosition: Double, width: Double) -> Double {
        guard horizontalPosition.isFinite, width.isFinite, width > 0 else {
            return 0
        }
        return min(max(horizontalPosition / width * 2 - 1, -1), 1)
    }

    mutating func updateDrag(horizontalPosition: Double, width: Double) {
        isDragging = true
        value = Self.normalized(horizontalPosition: horizontalPosition, width: width)
    }

    mutating func endDrag() {
        isDragging = false
    }

    mutating func advance(by deltaTime: TimeInterval) {
        guard !isDragging, deltaTime.isFinite, deltaTime > 0 else {
            return
        }

        value *= exp(-returnRate * deltaTime)
        if abs(value) < 0.001 {
            value = 0
        }
    }

    mutating func reset() {
        value = 0
        isDragging = false
    }
}
