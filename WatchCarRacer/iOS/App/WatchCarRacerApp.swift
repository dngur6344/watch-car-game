import SwiftUI

#if DEBUG
struct SG8AccessibilityAcceptanceOverride: Equatable {
    let reduceMotion: Bool?
    let reduceTransparency: Bool?
}

private struct SG8AccessibilityAcceptanceOverrideKey: EnvironmentKey {
    static let defaultValue = SG8AccessibilityAcceptanceOverride(
        reduceMotion: nil,
        reduceTransparency: nil
    )
}

extension EnvironmentValues {
    var sg8AccessibilityAcceptanceOverride: SG8AccessibilityAcceptanceOverride {
        get { self[SG8AccessibilityAcceptanceOverrideKey.self] }
        set { self[SG8AccessibilityAcceptanceOverrideKey.self] = newValue }
    }
}
#endif

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
    private let acceptanceAccessibilityConfiguration: SG8SensoryLaunchConfiguration
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
#if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        acceptanceAccessibilityConfiguration = SG8SensoryLaunchConfiguration(
            arguments: arguments
        )
        let acceptanceSeed: UInt64? = arguments.contains("--sg8-sensory")
            || arguments.contains("--sg8-racing-environment") ? 0 : nil
#else
        let acceptanceSeed: UInt64? = nil
#endif
        let flow = AppFlowController(
            selectionStore: selectionStore,
            localBestScoreStore: localBestScoreStore,
            assetLibrary: assetLibrary,
            watchInput: watchSession,
            audioDirector: audioDirector,
            feedbackPlayer: PhoneFeedbackPlayer(
                isHapticsEnabled: { sensorySettings.settings.hapticsEnabled }
            ),
            isHapticsEnabled: { sensorySettings.settings.hapticsEnabled },
            seedProvider: {
                acceptanceSeed ?? UInt64.random(in: UInt64.min...UInt64.max)
            }
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
#if DEBUG
            .environment(
                \.sg8AccessibilityAcceptanceOverride,
                SG8AccessibilityAcceptanceOverride(
                    reduceMotion: acceptanceAccessibilityConfiguration.expectedReduceMotion,
                    reduceTransparency: acceptanceAccessibilityConfiguration
                        .expectedReduceTransparency
                )
            )
#endif
        }
    }
}
