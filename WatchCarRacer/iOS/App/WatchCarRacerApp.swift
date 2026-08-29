import SwiftUI

@main
struct WatchCarRacerApp: App {
    @Environment(\.scenePhase) private var scenePhase

    private let watchSession: PhoneWatchSession
    private let selectionStore: UserDefaultsVehicleSelectionStore
    private let localBestScoreStore: LocalBestScoreStore
    private let assetLibrary: GameAssetLibrary
    private let presentationAssetLibrary: PresentationAssetLibrary
    @State private var flow: AppFlowController
#if DEBUG
    private let acceptanceCoordinator: SG6AcceptanceCoordinator?
#endif

    init() {
#if DEBUG
        SG6AcceptanceProbe.activateIfRequested()
#endif
        let watchSession = PhoneWatchSession.shared
        let selectionStore = UserDefaultsVehicleSelectionStore()
        let localBestScoreStore = LocalBestScoreStore()
        let assetLibrary: GameAssetLibrary
        let presentationAssetLibrary: PresentationAssetLibrary
        do {
            assetLibrary = try GameAssetLibrary()
            presentationAssetLibrary = try PresentationAssetLibrary()
        } catch {
            preconditionFailure("Required app assets could not be initialized: \(error)")
        }

        self.watchSession = watchSession
        self.selectionStore = selectionStore
        self.localBestScoreStore = localBestScoreStore
        self.assetLibrary = assetLibrary
        self.presentationAssetLibrary = presentationAssetLibrary
        let flow = AppFlowController(
            selectionStore: selectionStore,
            localBestScoreStore: localBestScoreStore,
            assetLibrary: assetLibrary,
            watchInput: watchSession
        )
        _flow = State(initialValue: flow)
#if DEBUG
        acceptanceCoordinator = SG6AcceptanceCoordinator.makeIfRequested(flow: flow)
        SG6AcceptanceProbe.recordAppInitializationComplete()
#endif
    }

    var body: some Scene {
        WindowGroup {
            AppRootView(
                flow: flow,
                watchSession: watchSession,
                presentationAssetLibrary: presentationAssetLibrary,
                scenePhase: scenePhase
            )
        }
    }
}
