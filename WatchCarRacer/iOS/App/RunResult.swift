struct RunResult: Equatable, Sendable {
    let score: Int
    let previousBest: Int
    let localBest: Int
    let isNewBest: Bool
}

enum SessionControlRoute: Equatable, Sendable {
    case adaptiveWatchPreferred
    case touchOnly
}
