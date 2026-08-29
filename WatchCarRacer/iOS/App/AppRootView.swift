import SwiftUI

struct AppRootView: View {
    let flow: AppFlowController
    let watchSession: PhoneWatchSession
    let presentationAssetLibrary: PresentationAssetLibrary
    let scenePhase: ScenePhase
    @State private var driveIntent: HubDriveIntentController

    init(
        flow: AppFlowController,
        watchSession: PhoneWatchSession,
        presentationAssetLibrary: PresentationAssetLibrary,
        scenePhase: ScenePhase
    ) {
        self.flow = flow
        self.watchSession = watchSession
        self.presentationAssetLibrary = presentationAssetLibrary
        self.scenePhase = scenePhase
        _driveIntent = State(
            initialValue: HubDriveIntentController { controlRoute in
                flow.drive(controlRoute: controlRoute)
            }
        )
    }

    var body: some View {
        Group {
            switch flow.route {
            case .hub:
                MainHubView(
                    flow: flow,
                    watchSession: watchSession,
                    presentationAssetLibrary: presentationAssetLibrary,
                    driveIntent: driveIntent
                )
            case .maintenance:
                VehicleMaintenanceView(
                    flow: flow,
                    presentationAssetLibrary: presentationAssetLibrary
                )
            case .playing:
                if let gameSession = flow.gameSession {
                    GameRootView(
                        gameSession: gameSession,
                        watchSession: watchSession,
                        onRetry: flow.retry,
                        onMainHub: flow.returnToHub
                    )
                } else {
                    MainHubView(
                        flow: flow,
                        watchSession: watchSession,
                        presentationAssetLibrary: presentationAssetLibrary,
                        driveIntent: driveIntent
                    )
                }
            }
        }
        .task {
            await flow.prepareAssets()
        }
        .onChange(of: scenePhase, initial: true) { _, newPhase in
            flow.handleLifecycle(sessionLifecyclePhase(for: newPhase))
        }
    }

    private func sessionLifecyclePhase(for scenePhase: ScenePhase) -> GameSessionLifecyclePhase {
        switch scenePhase {
        case .active:
            return .active
        case .inactive:
            return .inactive
        case .background:
            return .background
        @unknown default:
            return .inactive
        }
    }
}
