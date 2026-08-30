import Foundation
import Observation

@MainActor
@Observable
final class AppFlowController {
    enum Route: Equatable {
        case hub
        case maintenance
        case playing
    }

    enum AssetReadiness: Equatable {
        case idle
        case loading
        case ready
        case failed
    }

    typealias AssetPreparation = @MainActor () async throws -> Void
    typealias SeedProvider = @MainActor () -> UInt64
    typealias RouteCuePlayer = @MainActor (GameAudioCue) -> Void
    typealias GameSessionFactory = @MainActor (
        _ seed: UInt64,
        _ appearance: VehicleAppearance,
        _ assetLibrary: GameAssetLibrary,
        _ controlRoute: SessionControlRoute
    ) throws -> GameSessionController

    private(set) var route: Route = .hub
    private(set) var committedSelection: VehicleSelection
    private(set) var draftSelection: VehicleSelection
    private(set) var assetReadiness: AssetReadiness = .idle
    private(set) var gameSession: GameSessionController?
    private(set) var errorMessage: String?
    private(set) var lifecyclePhase: GameSessionLifecyclePhase = .active

    let assetLibrary: GameAssetLibrary
    let localBestScoreStore: any LocalBestScoreStoring
    let audioDirector: GameAudioDirector?

    @ObservationIgnored private let selectionStore: any VehicleSelectionStoring
    @ObservationIgnored private let prepareAssetsOperation: AssetPreparation
    @ObservationIgnored private let seedProvider: SeedProvider
    @ObservationIgnored private let gameSessionFactory: GameSessionFactory
    @ObservationIgnored private let routeCuePlayer: RouteCuePlayer

    init(
        selectionStore: any VehicleSelectionStoring,
        localBestScoreStore: any LocalBestScoreStoring,
        assetLibrary: GameAssetLibrary,
        watchInput: (any WatchSteeringReadingProviding)? = nil,
        audioDirector: GameAudioDirector? = nil,
        feedbackPlayer: (any PhoneFeedbackPlaying)? = nil,
        isHapticsEnabled: @escaping @MainActor () -> Bool = { true },
        routeCuePlayer: RouteCuePlayer? = nil,
        prepareAssets: AssetPreparation? = nil,
        seedProvider: @escaping SeedProvider = {
            UInt64.random(in: UInt64.min...UInt64.max)
        },
        gameSessionFactory: GameSessionFactory? = nil
    ) {
        self.selectionStore = selectionStore
        self.localBestScoreStore = localBestScoreStore
        self.assetLibrary = assetLibrary
        self.audioDirector = audioDirector
        self.routeCuePlayer = routeCuePlayer ?? { cue in
            audioDirector?.play(cue)
        }
        let committedSelection = selectionStore.load()
        self.committedSelection = committedSelection
        draftSelection = committedSelection
        prepareAssetsOperation = prepareAssets ?? {
            try await assetLibrary.preloadAll()
            try audioDirector?.prepareAssets()
        }
        self.seedProvider = seedProvider
        let resultStore = localBestScoreStore
        self.gameSessionFactory = gameSessionFactory ?? { seed, appearance, library, controlRoute in
            try GameSessionController(
                seed: seed,
                appearance: appearance,
                assetLibrary: library,
                controlRoute: controlRoute,
                watchInput: watchInput,
                feedbackPlayer: feedbackPlayer,
                audioDirector: audioDirector,
                isHapticsEnabled: isHapticsEnabled,
                resultRecorder: { score in
                    let previousBest = resultStore.load()
                    let localBest = resultStore.record(score)
                    return RunResult(
                        score: score,
                        previousBest: previousBest,
                        localBest: localBest,
                        isNewBest: score > previousBest && localBest == score
                    )
                }
            )
        }
    }

    var draftAppearance: VehicleAppearance? {
        VehicleCatalog.resolve(draftSelection)
    }

    var canDrive: Bool {
        route == .hub && assetReadiness == .ready && gameSession == nil
    }

    func enterMaintenance() {
        guard route == .hub, gameSession == nil else { return }
        route = .maintenance
    }

    func exitMaintenance() {
        guard route == .maintenance else { return }
        route = .hub
    }

    @discardableResult
    func selectVehicle(_ vehicleID: VehicleID) -> Bool {
        guard route == .maintenance else { return false }
        let selection = VehicleSelection(
            vehicleID: vehicleID,
            colorID: draftSelection.colorID
        )
        guard selection != draftSelection,
              VehicleCatalog.resolve(selection) != nil else {
            return false
        }
        draftSelection = selection
        clearControllerCreationErrorIfPossible()
        routeCuePlayer(.vehicleSelect)
        return true
    }

    @discardableResult
    func selectColor(_ colorID: VehicleColorID) -> Bool {
        guard route == .maintenance else { return false }
        let selection = VehicleSelection(
            vehicleID: draftSelection.vehicleID,
            colorID: colorID
        )
        guard selection != draftSelection,
              VehicleCatalog.resolve(selection) != nil else {
            return false
        }
        draftSelection = selection
        clearControllerCreationErrorIfPossible()
        routeCuePlayer(.colorSelect)
        return true
    }

    func prepareAssets() async {
        guard assetReadiness == .idle else { return }
        assetReadiness = .loading
        errorMessage = nil

        do {
            try await prepareAssetsOperation()
            assetReadiness = .ready
        } catch is CancellationError {
            assetReadiness = .idle
        } catch {
            assetReadiness = .failed
            errorMessage = "Unable to load garage assets. \(error.localizedDescription)"
        }
    }

    func retryAssetPreparation() async {
        guard assetReadiness == .failed else { return }
        assetReadiness = .idle
        await prepareAssets()
    }

    @discardableResult
    func drive(
        controlRoute: SessionControlRoute = .adaptiveWatchPreferred
    ) -> Bool {
        guard canDrive else { return false }
        guard let appearance = draftAppearance else {
            errorMessage = "The selected vehicle is unavailable. Choose another vehicle."
            return false
        }

        let seed = seedProvider()
        do {
            let controller = try gameSessionFactory(
                seed,
                appearance,
                assetLibrary,
                controlRoute
            )
            selectionStore.save(draftSelection)
            committedSelection = draftSelection
            gameSession = controller
            controller.handleLifecycle(lifecyclePhase)
            errorMessage = nil
            route = .playing
            routeCuePlayer(.driveTransition)
            return true
        } catch {
            errorMessage = "Unable to start the drive. \(error.localizedDescription)"
            return false
        }
    }

    func retry() {
        guard route == .playing, let gameSession else { return }
        gameSession.retry()
    }

    func handleLifecycle(_ phase: GameSessionLifecyclePhase) {
        lifecyclePhase = phase
        if let gameSession {
            gameSession.handleLifecycle(phase)
        } else {
            audioDirector?.handleLifecycle(phase)
        }
    }

    func returnToHub() {
        guard route == .playing else { return }
        gameSession?.stop()
        gameSession = nil
        errorMessage = nil
        route = .hub
    }

    private func clearControllerCreationErrorIfPossible() {
        if assetReadiness == .ready {
            errorMessage = nil
        }
    }
}
