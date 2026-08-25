import SwiftUI

struct AppRootView: View {
    let flow: AppFlowController
    let watchSession: PhoneWatchSession

    var body: some View {
        switch flow.route {
        case .garage:
            GarageView(flow: flow)
        case .playing:
            if let gameSession = flow.gameSession {
                GameRootView(
                    gameSession: gameSession,
                    watchSession: watchSession,
                    onRetry: flow.retry,
                    onGarage: flow.returnToGarage
                )
            } else {
                GarageView(flow: flow)
            }
        }
    }
}
