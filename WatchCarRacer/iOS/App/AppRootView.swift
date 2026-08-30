import SwiftUI

struct AppRootView: View {
    let flow: AppFlowController
    let watchSession: PhoneWatchSession
    let presentationAssetLibrary: PresentationAssetLibrary
    let sensorySettings: SensorySettingsController
    let audioDirector: GameAudioDirector
    let scenePhase: ScenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var driveIntent: HubDriveIntentController

    init(
        flow: AppFlowController,
        watchSession: PhoneWatchSession,
        presentationAssetLibrary: PresentationAssetLibrary,
        sensorySettings: SensorySettingsController,
        audioDirector: GameAudioDirector,
        scenePhase: ScenePhase
    ) {
        self.flow = flow
        self.watchSession = watchSession
        self.presentationAssetLibrary = presentationAssetLibrary
        self.sensorySettings = sensorySettings
        self.audioDirector = audioDirector
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
                    driveIntent: driveIntent,
                    sensorySettings: sensorySettings
                )
            case .maintenance:
                VehicleMaintenanceView(
                    flow: flow,
                    presentationAssetLibrary: presentationAssetLibrary,
                    sensorySettings: sensorySettings
                )
            case .playing:
                if let gameSession = flow.gameSession {
                    GameRootView(
                        gameSession: gameSession,
                        watchSession: watchSession,
                        sensorySettings: sensorySettings,
                        environment: flow.environmentSelection,
                        onRetry: flow.retry,
                        onMainHub: flow.returnToHub
                    )
                } else {
                    MainHubView(
                        flow: flow,
                        watchSession: watchSession,
                        presentationAssetLibrary: presentationAssetLibrary,
                        driveIntent: driveIntent,
                        sensorySettings: sensorySettings
                    )
                }
            }
        }
        .overlay {
            if driveIntent.driveTransitionTrigger > 0 {
                DriveRouteSweepView(
                    style: SensoryMicroInteractionStyle(
                        effectIntensity: sensorySettings.settings.effectIntensity,
                        reduceMotion: reduceMotion
                    )
                )
                .id(driveIntent.driveTransitionTrigger)
            }
        }
        .task {
            await flow.prepareAssets()
        }
        .onChange(of: flow.route, initial: true) { _, route in
            if let context = route.routeAudioContext {
                audioDirector.transition(to: context)
            }
        }
        .onChange(of: scenePhase, initial: true) { _, newPhase in
            flow.handleLifecycle(sessionLifecyclePhase(for: newPhase))
        }
        .onChange(of: sensorySettings.settings.sfxEnabled, initial: true) { _, isEnabled in
            audioDirector.setSFXEnabled(isEnabled)
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

extension AppFlowController.Route {
    var routeAudioContext: GameAudioContext? {
        switch self {
        case .hub:
            return .hub
        case .maintenance:
            return .maintenance
        case .playing:
            return nil
        }
    }
}

private struct DriveRouteSweepView: View {
    let style: SensoryMicroInteractionStyle

    @State private var sweepProgress: CGFloat = -0.72
    @State private var opacity = 1.0

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color.mint.opacity(0.04 * style.routeSweepAlpha)

                if style.usesMotion {
                    LinearGradient(
                        colors: [
                            .clear,
                            .mint.opacity(0.34 * style.routeSweepAlpha),
                            .white.opacity(0.78 * style.routeSweepAlpha),
                            .mint.opacity(0.28 * style.routeSweepAlpha),
                            .clear,
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: proxy.size.width * 0.42)
                    .offset(x: sweepProgress * proxy.size.width)
                } else {
                    Color.white.opacity(0.16 * style.routeSweepAlpha)
                }
            }
            .opacity(opacity)
            .onAppear {
                if style.usesMotion {
                    withAnimation(.easeInOut(duration: 0.48)) {
                        sweepProgress = 0.72
                    }
                    withAnimation(.easeOut(duration: 0.18).delay(0.34)) {
                        opacity = 0
                    }
                } else {
                    withAnimation(.easeOut(duration: 0.34)) {
                        opacity = 0
                    }
                }
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
