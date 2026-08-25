import XCTest
@testable import WatchCarRacer

@MainActor
final class AppFlowControllerTests: XCTestCase {
    func testColdLaunchAlwaysStartsInGarageWithSavedSelectionAsDraft() throws {
        let saved = VehicleSelection(vehicleID: .gt, colorID: .ultraviolet)
        let store = RecordingSelectionStore(selection: saved)
        let flow = try makeFlow(store: store)

        XCTAssertEqual(flow.route, .garage)
        XCTAssertEqual(flow.draftSelection, saved)
        XCTAssertNil(flow.gameSession)
        XCTAssertEqual(store.loadCount, 1)
        XCTAssertEqual(store.saveCalls, [])
    }

    func testDraftChangesDoNotSaveUntilDrive() throws {
        let store = RecordingSelectionStore(selection: VehicleCatalog.defaultSelection)
        let flow = try makeFlow(store: store)

        flow.selectVehicle(.angular)
        flow.selectColor(.solarCoral)

        XCTAssertEqual(
            flow.draftSelection,
            VehicleSelection(vehicleID: .angular, colorID: .solarCoral)
        )
        XCTAssertEqual(store.saveCalls, [])
        XCTAssertEqual(flow.route, .garage)
    }

    func testLoadingBlocksDriveAndAssetPreparationIsIdempotent() async throws {
        let store = RecordingSelectionStore(selection: VehicleCatalog.defaultSelection)
        var preparationCount = 0
        let preparationStarted = AsyncGate()
        let preparationCanFinish = AsyncGate()
        let flow = try makeFlow(store: store, prepareAssets: {
            preparationCount += 1
            await preparationStarted.open()
            await preparationCanFinish.wait()
        })

        flow.drive()
        XCTAssertNil(flow.gameSession)
        XCTAssertEqual(store.saveCalls, [])

        let firstPreparation = Task { await flow.prepareAssets() }
        await preparationStarted.wait()
        XCTAssertEqual(flow.assetReadiness, .loading)
        XCTAssertFalse(flow.canDrive)

        await flow.prepareAssets()
        await preparationCanFinish.open()
        await firstPreparation.value

        XCTAssertEqual(preparationCount, 1)
        XCTAssertEqual(flow.assetReadiness, .ready)

        await flow.prepareAssets()
        XCTAssertEqual(preparationCount, 1)
    }

    func testDefaultPreparationCachesEveryManifestTexture() async throws {
        let store = RecordingSelectionStore(selection: VehicleCatalog.defaultSelection)
        let assetLibrary = try GameAssetLibrary()
        let flow = AppFlowController(
            selectionStore: store,
            assetLibrary: assetLibrary
        )

        await flow.prepareAssets()

        XCTAssertEqual(flow.assetReadiness, .ready)
        XCTAssertEqual(
            assetLibrary.preloadedAtlasNames,
            ["Vehicles", "Obstacles", "Environment"]
        )
        XCTAssertEqual(assetLibrary.cachedTextureCount, assetLibrary.manifest.assets.count)
        XCTAssertTrue(flow.canDrive)
        XCTAssertNil(flow.errorMessage)
    }

    func testDriveSavesAndCreatesExactlyOnceDespiteRepeatedCalls() async throws {
        let selection = VehicleSelection(vehicleID: .angular, colorID: .emberGold)
        let store = RecordingSelectionStore(selection: VehicleCatalog.defaultSelection)
        let assetLibrary = try GameAssetLibrary()
        var factoryCalls = 0
        let flow = AppFlowController(
            selectionStore: store,
            assetLibrary: assetLibrary,
            prepareAssets: {},
            seedProvider: { 441 },
            gameSessionFactory: { seed, appearance, receivedLibrary in
                factoryCalls += 1
                return try GameSessionController(
                    seed: seed,
                    appearance: appearance,
                    assetLibrary: receivedLibrary
                )
            }
        )
        flow.selectVehicle(selection.vehicleID)
        flow.selectColor(selection.colorID)
        await flow.prepareAssets()

        flow.drive()
        let firstController = try XCTUnwrap(flow.gameSession)
        flow.drive()

        XCTAssertEqual(flow.route, .playing)
        XCTAssertEqual(store.saveCalls, [selection])
        XCTAssertEqual(factoryCalls, 1)
        XCTAssertTrue(flow.gameSession === firstController)
        XCTAssertEqual(firstController.runSeed, 441)
        XCTAssertEqual(firstController.appearance, VehicleCatalog.resolve(selection))
        XCTAssertTrue(firstController.assetLibrary === assetLibrary)
        XCTAssertTrue(firstController.scene.assetLibrary === assetLibrary)
    }

    func testRetryKeepsPlayingRouteControllerAppearanceAndSeed() async throws {
        let selection = VehicleSelection(vehicleID: .gt, colorID: .pulseMagenta)
        let store = RecordingSelectionStore(selection: selection)
        let flow = try makeFlow(store: store, seeds: [812])
        await flow.prepareAssets()
        flow.drive()
        let controller = try XCTUnwrap(flow.gameSession)

        flow.retry()

        XCTAssertEqual(flow.route, .playing)
        XCTAssertTrue(flow.gameSession === controller)
        XCTAssertEqual(controller.runSeed, 812)
        XCTAssertEqual(controller.appearance, VehicleCatalog.resolve(selection))
    }

    func testGarageDropsRunAndNextDriveUsesNewDraftAppearanceAndSeed() async throws {
        let firstSelection = VehicleSelection(vehicleID: .rally, colorID: .auroraMint)
        let secondSelection = VehicleSelection(vehicleID: .angular, colorID: .voltCyan)
        let store = RecordingSelectionStore(selection: firstSelection)
        let flow = try makeFlow(store: store, seeds: [101, 202])
        await flow.prepareAssets()

        flow.drive()
        let firstController = try XCTUnwrap(flow.gameSession)
        flow.returnToGarage()

        XCTAssertEqual(flow.route, .garage)
        XCTAssertNil(flow.gameSession)

        flow.selectVehicle(secondSelection.vehicleID)
        flow.selectColor(secondSelection.colorID)
        flow.drive()
        let secondController = try XCTUnwrap(flow.gameSession)

        XCTAssertFalse(firstController === secondController)
        XCTAssertEqual(firstController.runSeed, 101)
        XCTAssertEqual(secondController.runSeed, 202)
        XCTAssertEqual(secondController.appearance, VehicleCatalog.resolve(secondSelection))
        XCTAssertEqual(store.saveCalls, [firstSelection, secondSelection])
    }

    func testReturningToGarageReleasesRunControllerAndScene() async throws {
        let store = RecordingSelectionStore(selection: VehicleCatalog.defaultSelection)
        let flow = try makeFlow(store: store)
        await flow.prepareAssets()
        flow.drive()

        weak let controller = flow.gameSession
        weak let scene = flow.gameSession?.scene
        XCTAssertNotNil(controller)
        XCTAssertNotNil(scene)

        flow.returnToGarage()

        XCTAssertNil(flow.gameSession)
        XCTAssertNil(controller)
        XCTAssertNil(scene)
    }

    func testFailedAssetPreparationStaysInGarageAndExposesError() async throws {
        let store = RecordingSelectionStore(selection: VehicleCatalog.defaultSelection)
        let flow = try makeFlow(store: store, prepareAssets: {
            throw TestFailure.assetLoad
        })

        await flow.prepareAssets()
        flow.drive()

        XCTAssertEqual(flow.route, .garage)
        XCTAssertEqual(flow.assetReadiness, .failed)
        XCTAssertFalse(flow.canDrive)
        XCTAssertNil(flow.gameSession)
        XCTAssertEqual(store.saveCalls, [])
        XCTAssertTrue(flow.errorMessage?.contains("Unable to load garage assets") == true)
        XCTAssertTrue(flow.errorMessage?.contains(TestFailure.assetLoad.localizedDescription) == true)
    }

    func testFailedControllerCreationDoesNotCommitAndCanBeRetriedOnce() async throws {
        let selected = VehicleSelection(vehicleID: .gt, colorID: .lunarSilver)
        let store = RecordingSelectionStore(selection: selected)
        let assetLibrary = try GameAssetLibrary()
        var attempts = 0
        let flow = AppFlowController(
            selectionStore: store,
            assetLibrary: assetLibrary,
            prepareAssets: {},
            seedProvider: { 99 },
            gameSessionFactory: { seed, appearance, library in
                attempts += 1
                if attempts == 1 {
                    throw TestFailure.controllerCreation
                }
                return try GameSessionController(
                    seed: seed,
                    appearance: appearance,
                    assetLibrary: library
                )
            }
        )
        await flow.prepareAssets()

        flow.drive()

        XCTAssertEqual(flow.route, .garage)
        XCTAssertNil(flow.gameSession)
        XCTAssertEqual(store.saveCalls, [])
        XCTAssertTrue(flow.errorMessage?.contains("Unable to start the drive") == true)
        XCTAssertTrue(flow.canDrive)

        flow.drive()

        XCTAssertEqual(flow.route, .playing)
        XCTAssertNotNil(flow.gameSession)
        XCTAssertEqual(store.saveCalls, [selected])
        XCTAssertEqual(attempts, 2)
        XCTAssertNil(flow.errorMessage)
    }

    private func makeFlow(
        store: RecordingSelectionStore,
        prepareAssets: @escaping AppFlowController.AssetPreparation = {},
        seeds: [UInt64] = [1]
    ) throws -> AppFlowController {
        let assetLibrary = try GameAssetLibrary()
        var remainingSeeds = seeds
        return AppFlowController(
            selectionStore: store,
            assetLibrary: assetLibrary,
            prepareAssets: prepareAssets,
            seedProvider: {
                precondition(!remainingSeeds.isEmpty, "The test did not provide enough seeds.")
                return remainingSeeds.removeFirst()
            }
        )
    }
}

private actor AsyncGate {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        guard !isOpen else { return }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func open() {
        guard !isOpen else { return }
        isOpen = true
        let pendingWaiters = waiters
        waiters.removeAll()
        for waiter in pendingWaiters {
            waiter.resume()
        }
    }
}

private final class RecordingSelectionStore: VehicleSelectionStoring {
    private let selection: VehicleSelection
    private(set) var loadCount = 0
    private(set) var saveCalls: [VehicleSelection] = []

    init(selection: VehicleSelection) {
        self.selection = selection
    }

    func load() -> VehicleSelection {
        loadCount += 1
        return selection
    }

    func save(_ selection: VehicleSelection) {
        saveCalls.append(selection)
    }
}

private enum TestFailure: LocalizedError {
    case assetLoad
    case controllerCreation

    var errorDescription: String? {
        switch self {
        case .assetLoad:
            "Synthetic asset load failure"
        case .controllerCreation:
            "Synthetic controller creation failure"
        }
    }
}
