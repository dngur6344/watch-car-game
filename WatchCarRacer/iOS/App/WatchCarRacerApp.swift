import SwiftUI

@main
struct WatchCarRacerApp: App {
    @State private var watchSession: PhoneWatchSession
    @State private var gameSession: GameSessionController

    init() {
        let watchSession = PhoneWatchSession.shared
        _watchSession = State(initialValue: watchSession)
        _gameSession = State(initialValue: GameSessionController(watchInput: watchSession))
    }

    var body: some Scene {
        WindowGroup {
            GameRootView(gameSession: gameSession, watchSession: watchSession)
        }
    }
}
