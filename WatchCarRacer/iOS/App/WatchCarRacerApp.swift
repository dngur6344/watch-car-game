import SwiftUI

@main
struct WatchCarRacerApp: App {
    @Environment(\.scenePhase) private var scenePhase

    private let watchSession: PhoneWatchSession
    private let selectionStore: UserDefaultsVehicleSelectionStore
    private let localBestScoreStore: LocalBestScoreStore
    private let assetLibrary: GameAssetLibrary
    private let presentationAssetLibrary: PresentationAssetLibrary
    private let audioDirector: GameAudioDirector
    @State private var flow: AppFlowController
    @State private var sensorySettings: SensorySettingsController
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
        let sensorySettings = SensorySettingsController(
            store: UserDefaultsSensorySettingsStore()
        )
        let audioDirector = GameAudioDirector(assetLibrary: AudioAssetLibrary())
        audioDirector.setSFXEnabled(sensorySettings.settings.sfxEnabled)
        self.audioDirector = audioDirector
        let flow = AppFlowController(
            selectionStore: selectionStore,
            localBestScoreStore: localBestScoreStore,
            assetLibrary: assetLibrary,
            watchInput: watchSession,
            audioDirector: audioDirector,
            feedbackPlayer: PhoneFeedbackPlayer(
                isHapticsEnabled: { sensorySettings.settings.hapticsEnabled }
            ),
            isHapticsEnabled: { sensorySettings.settings.hapticsEnabled }
        )
        _flow = State(initialValue: flow)
        _sensorySettings = State(initialValue: sensorySettings)
#if DEBUG
        acceptanceCoordinator = SG6AcceptanceCoordinator.makeIfRequested(
            flow: flow,
            sensorySettings: sensorySettings
        )
        SG6AcceptanceProbe.recordAppInitializationComplete()
#endif
    }

    var body: some Scene {
        WindowGroup {
            AppRootView(
                flow: flow,
                watchSession: watchSession,
                presentationAssetLibrary: presentationAssetLibrary,
                sensorySettings: sensorySettings,
                audioDirector: audioDirector,
                scenePhase: scenePhase
            )
        }
    }
}
