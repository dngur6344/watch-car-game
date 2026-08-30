import XCTest
@testable import WatchCarRacer

@MainActor
final class AppFlowControllerTests: XCTestCase {
    func testColdLaunchAlwaysStartsInHubWithCommittedSelectionAsDraft() throws {
        let saved = VehicleSelection(vehicleID: .gt, colorID: .ultraviolet)
        let store = RecordingSelectionStore(selection: saved)
        let flow = try makeFlow(store: store)

        XCTAssertEqual(flow.route, .hub)
        XCTAssertEqual(flow.committedSelection, saved)
        XCTAssertEqual(flow.draftSelection, saved)
        XCTAssertNil(flow.gameSession)
        XCTAssertEqual(store.loadCount, 1)
        XCTAssertEqual(store.saveCalls, [])
    }

    func testSelectionCanOnlyBeEditedInMaintenance() async throws {
        let saved = VehicleCatalog.defaultSelection
        let store = RecordingSelectionStore(selection: saved)
        let flow = try makeFlow(store: store)

        flow.selectVehicle(.angular)
        flow.selectColor(.solarCoral)
        XCTAssertEqual(flow.draftSelection, saved)

        flow.enterMaintenance()
        flow.selectVehicle(.angular)
        flow.selectColor(.solarCoral)
        let edited = VehicleSelection(vehicleID: .angular, colorID: .solarCoral)
        XCTAssertEqual(flow.draftSelection, edited)

        flow.exitMaintenance()
        await flow.prepareAssets()
        flow.drive()
        flow.selectVehicle(.gt)
        flow.selectColor(.lunarSilver)

        XCTAssertEqual(flow.draftSelection, edited)
        XCTAssertEqual(store.saveCalls, [edited])
    }

    func testSelectionCuesOnlyFollowAcceptedChangedMutations() throws {
        let saved = VehicleCatalog.defaultSelection
        let store = RecordingSelectionStore(selection: saved)
        var cues: [GameAudioCue] = []
        let flow = try makeFlow(
            store: store,
            routeCuePlayer: { cues.append($0) }
        )

        XCTAssertFalse(flow.selectVehicle(.gt))
        XCTAssertFalse(flow.selectColor(.voltCyan))
        flow.enterMaintenance()
        XCTAssertFalse(flow.selectVehicle(saved.vehicleID))
        XCTAssertTrue(flow.selectVehicle(.gt))
        XCTAssertFalse(flow.selectVehicle(.gt))
        XCTAssertFalse(flow.selectColor(saved.colorID))
        XCTAssertTrue(flow.selectColor(.voltCyan))
        XCTAssertFalse(flow.selectColor(.voltCyan))
        flow.exitMaintenance()
        XCTAssertFalse(flow.selectVehicle(.angular))
        XCTAssertFalse(flow.selectColor(.emberGold))

        XCTAssertEqual(cues, [.vehicleSelect, .colorSelect])
        XCTAssertEqual(
            flow.draftSelection,
            VehicleSelection(vehicleID: .gt, colorID: .voltCyan)
        )
    }

    func testMaintenanceBackRetainsDraftInMemoryWithoutSavingAndReentryRestoresIt() throws {
        let store = RecordingSelectionStore(selection: VehicleCatalog.defaultSelection)
        let flow = try makeFlow(store: store)
        let draft = VehicleSelection(vehicleID: .angular, colorID: .solarCoral)

        flow.enterMaintenance()
        flow.selectVehicle(draft.vehicleID)
        flow.selectColor(draft.colorID)
        flow.exitMaintenance()

        XCTAssertEqual(flow.route, .hub)
        XCTAssertEqual(flow.draftSelection, draft)
        XCTAssertEqual(flow.committedSelection, VehicleCatalog.defaultSelection)
        XCTAssertEqual(store.saveCalls, [])

        flow.enterMaintenance()

        XCTAssertEqual(flow.route, .maintenance)
        XCTAssertEqual(flow.draftSelection, draft)
    }

    func testMaintenanceDoneRetainsDraftInMemoryWithoutSaving() throws {
        let saved = VehicleSelection(vehicleID: .rally, colorID: .midnightInk)
        let draft = VehicleSelection(vehicleID: .gt, colorID: .emberGold)
        let store = RecordingSelectionStore(selection: saved)
        let flow = try makeFlow(store: store)

        flow.enterMaintenance()
        flow.selectVehicle(draft.vehicleID)
        flow.selectColor(draft.colorID)
        flow.exitMaintenance()

        XCTAssertEqual(flow.route, .hub)
        XCTAssertEqual(flow.draftSelection, draft)
        XCTAssertEqual(flow.committedSelection, saved)
        XCTAssertEqual(store.saveCalls, [])
    }

    func testRecreatedFlowRestoresCommittedStoreValueInsteadOfUncommittedDraft() throws {
        let committed = VehicleSelection(vehicleID: .gt, colorID: .lunarSilver)
        let store = RecordingSelectionStore(selection: committed)
        let firstFlow = try makeFlow(store: store)

        firstFlow.enterMaintenance()
        firstFlow.selectVehicle(.angular)
        firstFlow.selectColor(.pulseMagenta)
        firstFlow.exitMaintenance()

        let recreatedFlow = try makeFlow(store: store)

        XCTAssertEqual(recreatedFlow.route, .hub)
        XCTAssertEqual(recreatedFlow.committedSelection, committed)
        XCTAssertEqual(recreatedFlow.draftSelection, committed)
        XCTAssertEqual(store.loadCount, 2)
        XCTAssertEqual(store.saveCalls, [])
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
            localBestScoreStore: StubLocalBestScoreStore(),
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

    func testSuccessfulDriveSavesDraftExactlyOnceAndUpdatesCommittedSelection() async throws {
        let selection = VehicleSelection(vehicleID: .angular, colorID: .emberGold)
        let store = RecordingSelectionStore(selection: VehicleCatalog.defaultSelection)
        let assetLibrary = try GameAssetLibrary()
        var factoryCalls = 0
        let flow = AppFlowController(
            selectionStore: store,
            localBestScoreStore: StubLocalBestScoreStore(),
            assetLibrary: assetLibrary,
            prepareAssets: {},
            seedProvider: { 441 },
            gameSessionFactory: { seed, appearance, receivedLibrary, controlRoute in
                factoryCalls += 1
                return try GameSessionController(
                    seed: seed,
                    appearance: appearance,
                    assetLibrary: receivedLibrary,
                    controlRoute: controlRoute
                )
            }
        )
        flow.enterMaintenance()
        flow.selectVehicle(selection.vehicleID)
        flow.selectColor(selection.colorID)
        flow.exitMaintenance()
        await flow.prepareAssets()

        flow.drive()
        let firstController = try XCTUnwrap(flow.gameSession)
        flow.drive()

        XCTAssertEqual(flow.route, .playing)
        XCTAssertEqual(flow.committedSelection, selection)
        XCTAssertEqual(flow.draftSelection, selection)
        XCTAssertEqual(store.saveCalls, [selection])
        XCTAssertEqual(factoryCalls, 1)
        XCTAssertTrue(flow.gameSession === firstController)
        XCTAssertEqual(firstController.runSeed, 441)
        XCTAssertEqual(firstController.controlRoute, .adaptiveWatchPreferred)
        XCTAssertEqual(firstController.appearance, VehicleCatalog.resolve(selection))
        XCTAssertTrue(firstController.assetLibrary === assetLibrary)
        XCTAssertTrue(firstController.scene.assetLibrary === assetLibrary)
    }

    func testRetryKeepsPlayingRouteControllerSceneAppearanceAndSeed() async throws {
        let selection = VehicleSelection(vehicleID: .gt, colorID: .pulseMagenta)
        let store = RecordingSelectionStore(selection: selection)
        let flow = try makeFlow(store: store, seeds: [812])
        await flow.prepareAssets()
        flow.drive()
        let controller = try XCTUnwrap(flow.gameSession)
        let scene = controller.scene

        flow.retry()

        XCTAssertEqual(flow.route, .playing)
        XCTAssertTrue(flow.gameSession === controller)
        XCTAssertTrue(flow.gameSession?.scene === scene)
        XCTAssertEqual(controller.runSeed, 812)
        XCTAssertEqual(controller.appearance, VehicleCatalog.resolve(selection))
        XCTAssertEqual(controller.controlRoute, .adaptiveWatchPreferred)
        XCTAssertEqual(controller.presentationPhase, .countdown(3))
        XCTAssertTrue(controller.scene.isPaused)
    }

    func testHubDropsRunAndNextDriveUsesRetainedDraftAppearanceAndNewSeed() async throws {
        let firstSelection = VehicleSelection(vehicleID: .rally, colorID: .auroraMint)
        let secondSelection = VehicleSelection(vehicleID: .angular, colorID: .voltCyan)
        let store = RecordingSelectionStore(selection: firstSelection)
        let flow = try makeFlow(store: store, seeds: [101, 202])
        await flow.prepareAssets()

        flow.drive()
        let firstController = try XCTUnwrap(flow.gameSession)
        flow.returnToHub()

        XCTAssertEqual(flow.route, .hub)
        XCTAssertNil(flow.gameSession)

        flow.enterMaintenance()
        flow.selectVehicle(secondSelection.vehicleID)
        flow.selectColor(secondSelection.colorID)
        flow.exitMaintenance()
        flow.drive()
        let secondController = try XCTUnwrap(flow.gameSession)

        XCTAssertFalse(firstController === secondController)
        XCTAssertEqual(firstController.runSeed, 101)
        XCTAssertEqual(secondController.runSeed, 202)
        XCTAssertEqual(secondController.appearance, VehicleCatalog.resolve(secondSelection))
        XCTAssertEqual(store.saveCalls, [firstSelection, secondSelection])
    }

    func testReturningToHubReleasesRunControllerAndScene() async throws {
        let store = RecordingSelectionStore(selection: VehicleCatalog.defaultSelection)
        let flow = try makeFlow(store: store)
        await flow.prepareAssets()
        flow.drive()

        weak let controller = flow.gameSession
        weak let scene = flow.gameSession?.scene
        XCTAssertNotNil(controller)
        XCTAssertNotNil(scene)

        flow.returnToHub()

        XCTAssertEqual(flow.route, .hub)
        XCTAssertNil(flow.gameSession)
        XCTAssertNil(controller)
        XCTAssertNil(scene)
    }

    func testFailedAssetPreparationStaysInHubAndSavesZeroTimes() async throws {
        let store = RecordingSelectionStore(selection: VehicleCatalog.defaultSelection)
        var cues: [GameAudioCue] = []
        let flow = try makeFlow(
            store: store,
            prepareAssets: { throw TestFailure.assetLoad },
            routeCuePlayer: { cues.append($0) }
        )

        await flow.prepareAssets()
        flow.drive()

        XCTAssertEqual(flow.route, .hub)
        XCTAssertEqual(flow.assetReadiness, .failed)
        XCTAssertFalse(flow.canDrive)
        XCTAssertNil(flow.gameSession)
        XCTAssertEqual(store.saveCalls, [])
        XCTAssertTrue(cues.isEmpty)
        XCTAssertTrue(flow.errorMessage?.contains("Unable to load garage assets") == true)
        XCTAssertTrue(flow.errorMessage?.contains(TestFailure.assetLoad.localizedDescription) == true)
    }

    func testFailedControllerCreationDoesNotCommitAndSavesZeroTimes() async throws {
        let saved = VehicleSelection(vehicleID: .rally, colorID: .auroraMint)
        let selected = VehicleSelection(vehicleID: .gt, colorID: .lunarSilver)
        let store = RecordingSelectionStore(selection: saved)
        let assetLibrary = try GameAssetLibrary()
        var cues: [GameAudioCue] = []
        let flow = AppFlowController(
            selectionStore: store,
            localBestScoreStore: StubLocalBestScoreStore(),
            assetLibrary: assetLibrary,
            routeCuePlayer: { cues.append($0) },
            prepareAssets: {},
            seedProvider: { 99 },
            gameSessionFactory: { _, _, _, _ in
                throw TestFailure.controllerCreation
            }
        )
        flow.enterMaintenance()
        flow.selectVehicle(selected.vehicleID)
        flow.selectColor(selected.colorID)
        flow.exitMaintenance()
        await flow.prepareAssets()
        cues.removeAll()

        flow.drive()

        XCTAssertEqual(flow.route, .hub)
        XCTAssertEqual(flow.committedSelection, saved)
        XCTAssertEqual(flow.draftSelection, selected)
        XCTAssertNil(flow.gameSession)
        XCTAssertEqual(store.saveCalls, [])
        XCTAssertTrue(cues.isEmpty)
        XCTAssertTrue(flow.errorMessage?.contains("Unable to start the drive") == true)
        XCTAssertTrue(flow.canDrive)
    }

    func testDriveTransitionCueOccursOnceOnlyAfterSuccessfulDrive() async throws {
        let store = RecordingSelectionStore(selection: VehicleCatalog.defaultSelection)
        var cues: [GameAudioCue] = []
        let flow = try makeFlow(
            store: store,
            routeCuePlayer: { cues.append($0) }
        )

        XCTAssertFalse(flow.drive())
        XCTAssertTrue(cues.isEmpty)

        await flow.prepareAssets()
        XCTAssertTrue(flow.drive())
        XCTAssertFalse(flow.drive())

        XCTAssertEqual(cues, [.driveTransition])
    }

    func testReadyDriveIntentStartsOneAdaptiveSessionAndCommitsOnce() async throws {
        let selection = VehicleSelection(vehicleID: .gt, colorID: .voltCyan)
        let store = RecordingSelectionStore(selection: selection)
        let assetLibrary = try GameAssetLibrary()
        var factoryRoutes: [SessionControlRoute] = []
        let flow = AppFlowController(
            selectionStore: store,
            localBestScoreStore: StubLocalBestScoreStore(),
            assetLibrary: assetLibrary,
            prepareAssets: {},
            gameSessionFactory: { seed, appearance, library, controlRoute in
                factoryRoutes.append(controlRoute)
                return try GameSessionController(
                    seed: seed,
                    appearance: appearance,
                    assetLibrary: library,
                    controlRoute: controlRoute
                )
            }
        )
        let intent = HubDriveIntentController { route in
            flow.drive(controlRoute: route)
        }
        await flow.prepareAssets()

        intent.requestDrive(readiness: .ready)
        intent.requestDrive(readiness: .ready)

        XCTAssertEqual(flow.route, .playing)
        XCTAssertEqual(factoryRoutes, [.adaptiveWatchPreferred])
        XCTAssertEqual(store.saveCalls, [selection])
        XCTAssertEqual(flow.gameSession?.controlRoute, .adaptiveWatchPreferred)
    }

    func testNotReadyDriveIntentDefersSessionAndSaveUntilSingleTouchConsume() async throws {
        let selection = VehicleSelection(vehicleID: .angular, colorID: .solarCoral)
        let store = RecordingSelectionStore(selection: selection)
        let assetLibrary = try GameAssetLibrary()
        var factoryRoutes: [SessionControlRoute] = []
        let flow = AppFlowController(
            selectionStore: store,
            localBestScoreStore: StubLocalBestScoreStore(),
            assetLibrary: assetLibrary,
            prepareAssets: {},
            gameSessionFactory: { seed, appearance, library, controlRoute in
                factoryRoutes.append(controlRoute)
                return try GameSessionController(
                    seed: seed,
                    appearance: appearance,
                    assetLibrary: library,
                    controlRoute: controlRoute
                )
            }
        )
        let intent = HubDriveIntentController { route in
            flow.drive(controlRoute: route)
        }
        await flow.prepareAssets()

        intent.requestDrive(readiness: .stale)

        XCTAssertTrue(intent.isReadinessSheetPresented)
        XCTAssertTrue(intent.hasPendingDriveIntent)
        XCTAssertEqual(flow.route, .hub)
        XCTAssertNil(flow.gameSession)
        XCTAssertTrue(factoryRoutes.isEmpty)
        XCTAssertTrue(store.saveCalls.isEmpty)

        intent.continueWithTouch()
        intent.continueWithTouch()

        XCTAssertEqual(flow.route, .playing)
        XCTAssertEqual(factoryRoutes, [.touchOnly])
        XCTAssertEqual(store.saveCalls, [selection])
        XCTAssertEqual(flow.gameSession?.controlRoute, .touchOnly)
    }

    func testCancelAndInteractiveDismissBothClearPendingIntentWithoutStarting() async throws {
        let store = RecordingSelectionStore(selection: VehicleCatalog.defaultSelection)
        let flow = try makeFlow(store: store)
        let intent = HubDriveIntentController { route in
            flow.drive(controlRoute: route)
        }
        await flow.prepareAssets()

        intent.requestDrive(readiness: .disconnected)
        intent.cancelPendingDrive()
        intent.continueWithTouch()

        XCTAssertFalse(intent.hasPendingDriveIntent)
        XCTAssertFalse(intent.isReadinessSheetPresented)
        XCTAssertEqual(flow.route, .hub)
        XCTAssertNil(flow.gameSession)
        XCTAssertTrue(store.saveCalls.isEmpty)

        intent.requestDrive(readiness: .needsCalibration)
        intent.readinessSheetDidDismiss()
        intent.continueWithTouch()

        XCTAssertFalse(intent.hasPendingDriveIntent)
        XCTAssertFalse(intent.isReadinessSheetPresented)
        XCTAssertEqual(flow.route, .hub)
        XCTAssertNil(flow.gameSession)
        XCTAssertTrue(store.saveCalls.isEmpty)
    }

    func testFlowForwardsLifecycleAndStopsCountdownBeforeHubRelease() async throws {
        let store = RecordingSelectionStore(selection: VehicleCatalog.defaultSelection)
        let flow = try makeFlow(store: store)
        flow.handleLifecycle(.background)
        await flow.prepareAssets()
        flow.drive(controlRoute: .touchOnly)
        let controller = try XCTUnwrap(flow.gameSession)

        XCTAssertEqual(flow.lifecyclePhase, .background)
        XCTAssertEqual(controller.presentationPhase, .countdown(3))
        XCTAssertTrue(controller.scene.isPaused)
        XCTAssertFalse(controller.hasActiveCountdownTask)

        flow.handleLifecycle(.active)
        XCTAssertTrue(controller.hasActiveCountdownTask)

        flow.returnToHub()

        XCTAssertEqual(flow.route, .hub)
        XCTAssertNil(flow.gameSession)
        XCTAssertFalse(controller.hasActiveCountdownTask)
        XCTAssertTrue(controller.scene.isPaused)
    }

    func testDefaultSessionRecorderPublishesPreviousBestWithoutLowerScoreWrite() async throws {
        let selectionStore = RecordingSelectionStore(selection: VehicleCatalog.defaultSelection)
        let bestStore = RecordingLocalBestScoreStore(localBest: 500)
        let flow = AppFlowController(
            selectionStore: selectionStore,
            localBestScoreStore: bestStore,
            assetLibrary: try GameAssetLibrary(),
            prepareAssets: {}
        )
        await flow.prepareAssets()
        flow.drive()
        let controller = try XCTUnwrap(flow.gameSession)
        let running = controller.scene.currentSnapshot
        let crashed = GameSnapshot(
            phase: .crashed,
            playerX: running.playerX,
            playerWidth: running.playerWidth,
            playerLength: running.playerLength,
            roadHalfWidth: running.roadHalfWidth,
            laneWidth: running.laneWidth,
            obstacles: running.obstacles,
            score: 120,
            speed: running.speed,
            elapsedTime: running.elapsedTime,
            distance: running.distance,
            spawnInterval: running.spawnInterval
        )

        controller.receive(
            snapshot: crashed,
            events: [.collision(obstacleID: 1, kind: .barrier)]
        )
        controller.receive(
            snapshot: crashed,
            events: [.collision(obstacleID: 1, kind: .barrier)]
        )
        try await Task.sleep(for: .milliseconds(550))

        XCTAssertEqual(bestStore.recordCalls, [120])
        XCTAssertTrue(bestStore.writeCalls.isEmpty)
        guard case let .result(result) = controller.presentationPhase else {
            return XCTFail("Expected result presentation")
        }
        XCTAssertEqual(result.score, 120)
        XCTAssertEqual(result.previousBest, 500)
        XCTAssertEqual(result.localBest, 500)
        XCTAssertFalse(result.isNewBest)
    }

    private func makeFlow(
        store: RecordingSelectionStore,
        prepareAssets: @escaping AppFlowController.AssetPreparation = {},
        routeCuePlayer: AppFlowController.RouteCuePlayer? = nil,
        seeds: [UInt64] = [1]
    ) throws -> AppFlowController {
        let assetLibrary = try GameAssetLibrary()
        var remainingSeeds = seeds
        return AppFlowController(
            selectionStore: store,
            localBestScoreStore: StubLocalBestScoreStore(),
            assetLibrary: assetLibrary,
            routeCuePlayer: routeCuePlayer,
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
    private var selection: VehicleSelection
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
        self.selection = selection
    }
}

private final class StubLocalBestScoreStore: LocalBestScoreStoring {
    func load() -> Int {
        0
    }

    func record(_ score: Int) -> Int {
        max(score, 0)
    }
}

private final class RecordingLocalBestScoreStore: LocalBestScoreStoring {
    private var localBest: Int
    private(set) var recordCalls: [Int] = []
    private(set) var writeCalls: [Int] = []

    init(localBest: Int) {
        self.localBest = localBest
    }

    func load() -> Int {
        localBest
    }

    func record(_ score: Int) -> Int {
        recordCalls.append(score)
        guard score > localBest else { return localBest }
        localBest = score
        writeCalls.append(score)
        return localBest
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
