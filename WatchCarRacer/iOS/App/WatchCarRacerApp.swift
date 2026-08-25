import SwiftUI

@main
struct WatchCarRacerApp: App {
    private let watchSession: PhoneWatchSession
    private let selectionStore: UserDefaultsVehicleSelectionStore
    private let assetLibrary: GameAssetLibrary
    @State private var flow: AppFlowController
#if DEBUG
    private let acceptanceCoordinator: SG6AcceptanceCoordinator?
#endif

    init() {
        let watchSession = PhoneWatchSession.shared
        let selectionStore = UserDefaultsVehicleSelectionStore()
        let assetLibrary: GameAssetLibrary
        do {
            assetLibrary = try GameAssetLibrary()
        } catch {
            preconditionFailure("Required garage assets could not be initialized: \(error)")
        }

        self.watchSession = watchSession
        self.selectionStore = selectionStore
        self.assetLibrary = assetLibrary
        let flow = AppFlowController(
            selectionStore: selectionStore,
            assetLibrary: assetLibrary,
            watchInput: watchSession
        )
        _flow = State(initialValue: flow)
#if DEBUG
        acceptanceCoordinator = SG6AcceptanceCoordinator.makeIfRequested(flow: flow)
#endif
    }

    var body: some Scene {
        WindowGroup {
            AppRootView(flow: flow, watchSession: watchSession)
        }
    }
}
