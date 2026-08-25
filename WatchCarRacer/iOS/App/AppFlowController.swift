import Foundation
import Observation

@MainActor
@Observable
final class AppFlowController {
    enum Route: Equatable {
        case garage
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
    typealias GameSessionFactory = @MainActor (
        _ seed: UInt64,
        _ appearance: VehicleAppearance,
        _ assetLibrary: GameAssetLibrary
    ) throws -> GameSessionController

    private(set) var route: Route = .garage
    private(set) var draftSelection: VehicleSelection
    private(set) var assetReadiness: AssetReadiness = .idle
    private(set) var gameSession: GameSessionController?
    private(set) var errorMessage: String?

    let assetLibrary: GameAssetLibrary

    @ObservationIgnored private let selectionStore: any VehicleSelectionStoring
    @ObservationIgnored private let prepareAssetsOperation: AssetPreparation
    @ObservationIgnored private let seedProvider: SeedProvider
    @ObservationIgnored private let gameSessionFactory: GameSessionFactory

    init(
        selectionStore: any VehicleSelectionStoring,
        assetLibrary: GameAssetLibrary,
        watchInput: (any WatchSteeringReadingProviding)? = nil,
        prepareAssets: AssetPreparation? = nil,
        seedProvider: @escaping SeedProvider = {
            UInt64.random(in: UInt64.min...UInt64.max)
        },
        gameSessionFactory: GameSessionFactory? = nil
    ) {
        self.selectionStore = selectionStore
        self.assetLibrary = assetLibrary
        draftSelection = selectionStore.load()
        prepareAssetsOperation = prepareAssets ?? {
            try await assetLibrary.preloadAll()
        }
        self.seedProvider = seedProvider
        self.gameSessionFactory = gameSessionFactory ?? { seed, appearance, library in
            try GameSessionController(
                seed: seed,
                appearance: appearance,
                assetLibrary: library,
                watchInput: watchInput
            )
        }
    }

    var draftAppearance: VehicleAppearance? {
        VehicleCatalog.resolve(draftSelection)
    }

    var canDrive: Bool {
        route == .garage && assetReadiness == .ready && gameSession == nil
    }

    func selectVehicle(_ vehicleID: VehicleID) {
        guard route == .garage else { return }
        draftSelection = VehicleSelection(
            vehicleID: vehicleID,
            colorID: draftSelection.colorID
        )
        clearControllerCreationErrorIfPossible()
    }

    func selectColor(_ colorID: VehicleColorID) {
        guard route == .garage else { return }
        draftSelection = VehicleSelection(
            vehicleID: draftSelection.vehicleID,
            colorID: colorID
        )
        clearControllerCreationErrorIfPossible()
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

    func drive() {
        guard canDrive else { return }
        guard let appearance = draftAppearance else {
            errorMessage = "The selected vehicle is unavailable. Choose another vehicle."
            return
        }

        let seed = seedProvider()
        do {
            let controller = try gameSessionFactory(seed, appearance, assetLibrary)
            selectionStore.save(draftSelection)
            gameSession = controller
            errorMessage = nil
            route = .playing
        } catch {
            errorMessage = "Unable to start the drive. \(error.localizedDescription)"
        }
    }

    func retry() {
        guard route == .playing, let gameSession else { return }
        gameSession.retry()
    }

    func returnToGarage() {
        guard route == .playing else { return }
        gameSession?.scene.isPaused = true
        gameSession = nil
        errorMessage = nil
        route = .garage
    }

    private func clearControllerCreationErrorIfPossible() {
        if assetReadiness == .ready {
            errorMessage = nil
        }
    }
}
