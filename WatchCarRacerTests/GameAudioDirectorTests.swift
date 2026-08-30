import AVFoundation
import Foundation
import XCTest
@testable import WatchCarRacer

@MainActor
final class GameAudioDirectorTests: XCTestCase {
    func testContextSequenceRetryAndCueDeduplicationKeepOneDirectorAndEngineIdentity() throws {
        let assets = RecordingAudioAssets()
        let backend = RecordingAudioBackend()
        let director = makeDirector(assets: assets, backend: backend)
        let directorIdentity = director.identity
        let engineIdentity = director.backendDiagnostics.engineIdentity

        try director.prepareAssets()
        director.transition(to: .maintenance)
        director.transition(to: .countdown)
        director.transition(to: .racing)
        director.transition(to: .impact)
        let eventID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        director.play(.collision, eventID: eventID)
        director.play(.collision, eventID: eventID)
        director.transition(to: .result)

        director.beginAttempt()
        director.transition(to: .countdown)
        director.play(.collision, eventID: eventID)

        XCTAssertEqual(
            backend.transitions,
            [.hub, .maintenance, .countdown, .racing, .impact, .result, .countdown]
        )
        XCTAssertEqual(backend.playedRoles, [.collisionImpact, .collisionImpact])
        XCTAssertEqual(director.metrics.oneShotRequests, 3)
        XCTAssertEqual(director.metrics.oneShotPlayCount, 2)
        XCTAssertEqual(director.identity, directorIdentity)
        XCTAssertEqual(director.backendDiagnostics.engineIdentity, engineIdentity)
        XCTAssertLessThanOrEqual(director.backendDiagnostics.longLivedNodeCount, 16)
    }

    func testRouteContextsAreIdempotentAndPlayingRemainsSessionOwned() throws {
        let assets = RecordingAudioAssets()
        let backend = RecordingAudioBackend()
        let director = makeDirector(assets: assets, backend: backend)
        let engineIdentity = director.backendDiagnostics.engineIdentity
        try director.prepareAssets()

        let routes: [AppFlowController.Route] = [
            .hub, .maintenance, .maintenance, .hub, .hub, .playing,
        ]
        for route in routes {
            if let context = route.routeAudioContext {
                director.transition(to: context)
            }
        }

        XCTAssertEqual(backend.transitions, [.hub, .maintenance, .hub])
        XCTAssertNil(AppFlowController.Route.playing.routeAudioContext)
        XCTAssertEqual(director.desiredContext, .hub)
        XCTAssertEqual(director.backendDiagnostics.engineIdentity, engineIdentity)
        XCTAssertLessThanOrEqual(backend.maximumDuplicateGraphCount, 1)
    }

    func testAcceptedSelectionCuesUseDirectorSFXGate() throws {
        let assets = RecordingAudioAssets()
        let backend = RecordingAudioBackend()
        let director = makeDirector(assets: assets, backend: backend)
        try director.prepareAssets()
        let flow = AppFlowController(
            selectionStore: AudioSelectionStore(),
            localBestScoreStore: AudioBestScoreStore(),
            assetLibrary: try GameAssetLibrary(),
            audioDirector: director,
            prepareAssets: {}
        )
        flow.enterMaintenance()

        XCTAssertTrue(flow.selectVehicle(.gt))
        XCTAssertTrue(flow.selectColor(.voltCyan))
        director.setSFXEnabled(false)
        XCTAssertTrue(flow.selectVehicle(.angular))
        XCTAssertTrue(flow.selectColor(.emberGold))

        XCTAssertEqual(backend.playedRoles, [.vehicleSelect, .colorSelect])
        XCTAssertEqual(director.metrics.oneShotRequests, 4)
        XCTAssertEqual(director.metrics.oneShotPlayCount, 2)
    }

    func testSuspensionInterruptionRouteAndMediaResetResumeOnlyDesiredContext() throws {
        let assets = RecordingAudioAssets()
        let backend = RecordingAudioBackend()
        let director = makeDirector(assets: assets, backend: backend)
        let engineIdentity = director.backendDiagnostics.engineIdentity
        try director.prepareAssets()
        director.transition(to: .racing)

        director.handleLifecycle(.inactive)
        director.transition(to: .result)
        XCTAssertEqual(director.desiredContext, .result)
        XCTAssertEqual(backend.transitions.last, .racing)
        director.handleLifecycle(.background)
        director.handleLifecycle(.active)
        XCTAssertEqual(backend.transitions.last, .result)

        director.handleInterruptionBegan()
        director.transition(to: .maintenance)
        XCTAssertEqual(backend.transitions.last, .result)
        director.handleInterruptionEnded(shouldResume: true)
        XCTAssertEqual(backend.transitions.last, .maintenance)

        director.handleRouteChange()
        XCTAssertEqual(backend.transitions.last, .maintenance)
        director.handleMediaServicesReset()
        XCTAssertEqual(backend.transitions.last, .maintenance)
        XCTAssertEqual(backend.rebuildCount, 3)
        XCTAssertEqual(director.backendDiagnostics.engineIdentity, engineIdentity)
        XCTAssertEqual(Set(backend.transitions.suffix(3)), [.maintenance])
        XCTAssertLessThanOrEqual(backend.maximumDuplicateGraphCount, 1)
    }

    func testNonResumableInterruptionClearsSuspensionWithoutRestartingOutput() throws {
        let assets = RecordingAudioAssets()
        let backend = RecordingAudioBackend()
        let director = makeDirector(assets: assets, backend: backend)
        try director.prepareAssets()
        director.transition(to: .racing)
        let transitionsBeforeInterruptionEnd = backend.transitions

        director.handleInterruptionBegan()
        director.handleInterruptionEnded(shouldResume: false)

        XCTAssertFalse(director.isSuspended)
        XCTAssertEqual(backend.transitions, transitionsBeforeInterruptionEnd)

        director.handleRouteChange()
        XCTAssertEqual(backend.transitions.last, .racing)
    }

    func testSixtyHertzInputProducesAtMostThirtyHertzMutationAndNoUpdateAllocations() throws {
        let assets = RecordingAudioAssets()
        let backend = RecordingAudioBackend()
        let director = makeDirector(assets: assets, backend: backend)
        try director.prepareAssets()
        director.transition(to: .racing)
        let preparationMetrics = assets.metrics
        let nodeAllocations = backend.diagnostics.nodeAllocationCount
        let appliedMixCountBeforeUpdates = backend.appliedMixes.count

        for frame in 0..<60 {
            director.update(
                speed: 12 + 12 * Double(frame) / 59,
                initialSpeed: 12,
                maximumSpeed: 24,
                steering: frame.isMultiple(of: 2) ? -0.7 : 0.7,
                timestamp: Double(frame) / 60
            )
        }

        XCTAssertEqual(director.metrics.snapshotInputCount, 60)
        XCTAssertLessThanOrEqual(director.metrics.parameterMutationCount, 30)
        XCTAssertEqual(
            backend.appliedMixes.count - appliedMixCountBeforeUpdates,
            director.metrics.parameterMutationCount
        )
        XCTAssertEqual(assets.metrics, preparationMetrics)
        XCTAssertEqual(backend.diagnostics.nodeAllocationCount, nodeAllocations)
        XCTAssertEqual(backend.updatePathAllocationCount, 0)
    }

    func testSFXOffStopsAllOutputAndOnRestoresContextWithoutReplayingSuppressedCue() throws {
        let assets = RecordingAudioAssets()
        let backend = RecordingAudioBackend()
        let director = makeDirector(assets: assets, backend: backend)
        try director.prepareAssets()
        director.transition(to: .racing)
        let suppressedID = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!

        director.setSFXEnabled(false)
        director.play(.nearMiss, eventID: suppressedID, pan: 2)
        director.transition(to: .impact)
        XCTAssertTrue(backend.playedRoles.isEmpty)
        XCTAssertEqual(backend.stopCount, 1)

        director.setSFXEnabled(true)
        director.play(.nearMiss, eventID: suppressedID, pan: -2)
        let audibleID = UUID(uuidString: "33333333-3333-3333-3333-333333333333")!
        director.play(.nearMiss, eventID: audibleID, pan: 2)
        director.play(.nearMiss, eventID: audibleID, pan: 2)

        XCTAssertEqual(backend.transitions.last, .impact)
        XCTAssertEqual(backend.playedRoles, [.nearMissWhoosh])
        XCTAssertEqual(backend.playedPans, [0.75])
        XCTAssertEqual(director.metrics.oneShotRequests, 4)
        XCTAssertEqual(director.metrics.oneShotPlayCount, 1)
    }

    func testFeedbackSettingsGateAudioAndBothHapticDestinationsIndependently() throws {
        let sfxOff = try runFeedbackGateCase(sfxEnabled: false, hapticsEnabled: true)
        XCTAssertEqual(sfxOff.audioCount, 0)
        XCTAssertEqual(sfxOff.phoneCount, 1)
        XCTAssertEqual(sfxOff.watchCount, 1)

        let hapticsOff = try runFeedbackGateCase(sfxEnabled: true, hapticsEnabled: false)
        XCTAssertEqual(hapticsOff.audioCount, 1)
        XCTAssertEqual(hapticsOff.phoneCount, 0)
        XCTAssertEqual(hapticsOff.watchCount, 0)

        let bothOn = try runFeedbackGateCase(sfxEnabled: true, hapticsEnabled: true)
        XCTAssertEqual(bothOn.audioCount, 1)
        XCTAssertEqual(bothOn.phoneCount, 1)
        XCTAssertEqual(bothOn.watchCount, 1)
    }

    func testStartCueSettingsGateAudioAndBothHapticDestinationsIndependently() async throws {
        let sfxOff = try await runStartCueGateCase(
            sfxEnabled: false,
            hapticsEnabled: true
        )
        XCTAssertEqual(sfxOff.audioCount, 0)
        XCTAssertEqual(sfxOff.phoneCount, 4)
        XCTAssertEqual(sfxOff.watchCount, 4)

        let hapticsOff = try await runStartCueGateCase(
            sfxEnabled: true,
            hapticsEnabled: false
        )
        XCTAssertEqual(hapticsOff.audioCount, 4)
        XCTAssertEqual(hapticsOff.phoneCount, 0)
        XCTAssertEqual(hapticsOff.watchCount, 0)

        let bothOn = try await runStartCueGateCase(
            sfxEnabled: true,
            hapticsEnabled: true
        )
        XCTAssertEqual(bothOn.audioCount, 4)
        XCTAssertEqual(bothOn.phoneCount, 4)
        XCTAssertEqual(bothOn.watchCount, 4)
        XCTAssertEqual(
            bothOn.audioRoles,
            [.countdownTick, .countdownTick, .countdownTick, .goBassHit]
        )
        XCTAssertEqual(bothOn.audioRates, [0.88, 1, 1.12, 1])
        XCTAssertEqual(
            bothOn.watchKinds,
            [.countdownTick, .countdownTick, .countdownTick, .go]
        )
    }

    func testDirectionalClosenessAndGradeReachBoundedNearMissAndCollisionAudio() throws {
        let assets = RecordingAudioAssets()
        let backend = RecordingAudioBackend()
        let director = makeDirector(assets: assets, backend: backend)
        try director.prepareAssets()
        let controller = GameSessionController(seed: 1, audioDirector: director)

        let nearMiss = makePresentation(
            event: .nearMiss(obstacleID: 1, kind: .trafficCar, bonus: 100),
            relativeX: 1.1,
            nearMissMargin: 0.4,
            elapsedTime: 1
        )
        controller.receive(
            snapshot: nearMiss.snapshot,
            presentationEvents: [nearMiss]
        )

        let collision = makePresentation(
            event: .collision(obstacleID: 2, kind: .barrier),
            relativeX: -0.6,
            nearMissMargin: 0.4,
            elapsedTime: 2
        )
        controller.receive(
            snapshot: collision.snapshot,
            presentationEvents: [collision]
        )

        let gameplayIndices = backend.playedRoles.indices.filter {
            backend.playedRoles[$0] == .nearMissWhoosh
                || backend.playedRoles[$0] == .collisionImpact
        }
        XCTAssertEqual(gameplayIndices.map { backend.playedRoles[$0] }, [.nearMissWhoosh, .collisionImpact])
        XCTAssertEqual(gameplayIndices.map { backend.playedPans[$0] }, [0.75, -0.75])
        XCTAssertEqual(backend.playedRates[gameplayIndices[0]], 1.08, accuracy: 0.000_001)
        XCTAssertEqual(backend.playedGains[gameplayIndices[0]], 0.847_5, accuracy: 0.000_001)
        XCTAssertEqual(backend.playedRates[gameplayIndices[1]], 1, accuracy: 0.000_001)
        XCTAssertEqual(backend.playedGains[gameplayIndices[1]], 1, accuracy: 0.000_001)
    }

    func testOneShotPoolAndLongLivedGraphStayWithinHardBounds() throws {
        let assets = RecordingAudioAssets()
        let backend = RecordingAudioBackend()
        let director = makeDirector(assets: assets, backend: backend)
        try director.prepareAssets()

        for index in 0..<12 {
            director.play(
                .nearMiss,
                eventID: UUID(
                    uuidString: String(
                        format: "00000000-0000-0000-0000-%012d",
                        index + 1
                    )
                )!
            )
        }

        XCTAssertEqual(director.metrics.oneShotPlayCount, 12)
        XCTAssertLessThanOrEqual(director.backendDiagnostics.maximumSimultaneousOneShots, 4)
        XCTAssertLessThanOrEqual(director.backendDiagnostics.longLivedNodeCount, 16)
        XCTAssertEqual(director.backendDiagnostics.nodeAllocationCount, 14)
    }

    func testProductionBackendUsesFixedGraphWithinNodeAndOneShotBounds() throws {
        let library = AudioAssetLibrary(
            manifestURL: audioDirectory.appendingPathComponent("AudioAssetManifest.json"),
            assetDirectoryURL: audioDirectory
        )
        let director = GameAudioDirector(
            assetLibrary: library,
            observeNotifications: false
        )
        let initialDiagnostics = director.backendDiagnostics

        XCTAssertEqual(initialDiagnostics.longLivedNodeCount, 16)
        XCTAssertEqual(initialDiagnostics.nodeAllocationCount, 14)
        try director.prepareAssets()
        for _ in 0..<12 {
            director.play(.nearMiss, eventID: UUID())
        }

        let finalDiagnostics = director.backendDiagnostics
        XCTAssertEqual(finalDiagnostics.engineIdentity, initialDiagnostics.engineIdentity)
        XCTAssertEqual(finalDiagnostics.longLivedNodeCount, 16)
        XCTAssertEqual(finalDiagnostics.nodeAllocationCount, 14)
        XCTAssertLessThanOrEqual(finalDiagnostics.maximumSimultaneousOneShots, 4)
    }

    func testRuntimeBackendFailureIsNonfatalToReadinessAndGameState() async throws {
        let assets = RecordingAudioAssets()
        let backend = RecordingAudioBackend(error: AudioTestError.runtime)
        let director = makeDirector(assets: assets, backend: backend)

        XCTAssertNoThrow(try director.prepareAssets())
        XCTAssertTrue(assets.isPrepared)
        XCTAssertGreaterThan(director.metrics.runtimeFailureCount, 0)

        let controller = GameSessionController(
            seed: 17,
            audioDirector: director,
            countdownSleeper: {}
        )
        await waitUntil { controller.presentationPhase == .racing }
        let base = controller.scene.currentSnapshot
        let running = GameSnapshot(
            phase: .running,
            playerX: base.playerX,
            playerWidth: base.playerWidth,
            playerLength: base.playerLength,
            roadHalfWidth: base.roadHalfWidth,
            laneWidth: base.laneWidth,
            obstacles: base.obstacles,
            score: 88,
            speed: 18,
            elapsedTime: 2,
            distance: base.distance,
            spawnInterval: base.spawnInterval
        )
        controller.receive(
            snapshot: running,
            events: [.nearMiss(obstacleID: 7, kind: .barrier, bonus: 100)]
        )

        XCTAssertEqual(controller.score, 88)
        XCTAssertEqual(controller.speed, 65)
        XCTAssertEqual(controller.phase, .running)
        XCTAssertEqual(controller.presentationPhase, .racing)
        XCTAssertEqual(controller.steeringSnapshot.value, 0)
        XCTAssertGreaterThan(director.metrics.runtimeFailureCount, 1)
    }

    func testPackagedAssetsPrepareOnceWithoutReadsOrDecodesOnDirectorUpdate() throws {
        let library = AudioAssetLibrary(
            manifestURL: audioDirectory.appendingPathComponent("AudioAssetManifest.json"),
            assetDirectoryURL: audioDirectory
        )
        let backend = RecordingAudioBackend()
        let director = makeDirector(assets: library, backend: backend)

        try director.prepareAssets()
        let preparedMetrics = library.metrics
        director.transition(to: .racing)
        for frame in 0..<60 {
            director.update(
                speed: 18,
                initialSpeed: 12,
                maximumSpeed: 24,
                steering: 0.5,
                timestamp: Double(frame) / 60
            )
        }

        XCTAssertEqual(preparedMetrics.fileReadCount, 15)
        XCTAssertEqual(preparedMetrics.decodeCount, 15)
        XCTAssertEqual(preparedMetrics.bufferAllocationCount, 15)
        XCTAssertLessThanOrEqual(preparedMetrics.decodedPCMByteCount, 8 * 1_024 * 1_024)
        XCTAssertEqual(library.metrics, preparedMetrics)
    }

    func testMissingAndHashMismatchedManifestFailAssetReadiness() throws {
        let missing = AudioAssetLibrary(
            manifestURL: nil,
            assetDirectoryURL: audioDirectory
        )
        XCTAssertThrowsError(try missing.prepare()) { error in
            XCTAssertEqual(error as? AudioAssetLibraryError, .missingManifest)
        }

        let original = try String(
            contentsOf: audioDirectory.appendingPathComponent("AudioAssetManifest.json"),
            encoding: .utf8
        )
        let mismatched = original.replacingOccurrences(
            of: "e8d721b1a7d4f45deb0b04425a78119e36ca75cecaf652fd1e0f2e3c3f9e4995",
            with: String(repeating: "0", count: 64)
        )
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: temporaryDirectory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
        let manifestURL = temporaryDirectory.appendingPathComponent("AudioAssetManifest.json")
        try mismatched.write(to: manifestURL, atomically: true, encoding: .utf8)
        let invalid = AudioAssetLibrary(
            manifestURL: manifestURL,
            assetDirectoryURL: audioDirectory
        )

        XCTAssertThrowsError(try invalid.prepare()) { error in
            XCTAssertEqual(
                error as? AudioAssetLibraryError,
                .hashMismatch("engine_idle_loop.wav")
            )
        }
    }

    func testAppFlowFailsReadinessForAudioAssetFailure() async throws {
        let assets = RecordingAudioAssets(prepareError: AudioTestError.asset)
        let backend = RecordingAudioBackend()
        let director = makeDirector(assets: assets, backend: backend)
        let flow = AppFlowController(
            selectionStore: AudioSelectionStore(),
            localBestScoreStore: AudioBestScoreStore(),
            assetLibrary: try GameAssetLibrary(),
            audioDirector: director
        )

        await flow.prepareAssets()

        XCTAssertEqual(flow.assetReadiness, .failed)
        XCTAssertFalse(flow.canDrive)
        XCTAssertNil(flow.gameSession)
        XCTAssertTrue(flow.errorMessage?.contains("Unable to load garage assets") == true)
    }

    func testAppFlowRuntimeAudioFailureStillBecomesReadyAndStartsSession() async throws {
        let assets = RecordingAudioAssets()
        let backend = RecordingAudioBackend(error: AudioTestError.runtime)
        let director = makeDirector(assets: assets, backend: backend)
        let flow = AppFlowController(
            selectionStore: AudioSelectionStore(),
            localBestScoreStore: AudioBestScoreStore(),
            assetLibrary: try GameAssetLibrary(),
            audioDirector: director
        )

        await flow.prepareAssets()
        let started = flow.drive(controlRoute: .touchOnly)

        XCTAssertEqual(flow.assetReadiness, .ready)
        XCTAssertTrue(started)
        XCTAssertEqual(flow.route, .playing)
        XCTAssertNotNil(flow.gameSession)
        XCTAssertGreaterThan(director.metrics.runtimeFailureCount, 0)
    }

    private func makeDirector(
        assets: any AudioAssetProviding,
        backend: RecordingAudioBackend
    ) -> GameAudioDirector {
        GameAudioDirector(
            assetLibrary: assets,
            backend: backend,
            observeNotifications: false
        )
    }

    private func runFeedbackGateCase(
        sfxEnabled: Bool,
        hapticsEnabled: Bool
    ) throws -> (audioCount: Int, phoneCount: Int, watchCount: Int) {
        let assets = RecordingAudioAssets()
        let backend = RecordingAudioBackend()
        let director = makeDirector(assets: assets, backend: backend)
        try director.prepareAssets()
        director.setSFXEnabled(sfxEnabled)
        let phone = AudioRecordingPhoneFeedbackPlayer()
        let watch = AudioRecordingWatchFeedbackSender()
        let controller = GameSessionController(
            seed: 1,
            feedbackPlayer: phone,
            watchFeedbackSender: watch,
            audioDirector: director,
            isHapticsEnabled: { hapticsEnabled }
        )
        let event = GameEvent.nearMiss(obstacleID: 1, kind: .barrier, bonus: 100)

        controller.receive(snapshot: controller.scene.currentSnapshot, events: [event, event])
        controller.receive(snapshot: controller.scene.currentSnapshot, events: [event])

        return (
            backend.playedRoles.count { $0 == .nearMissWhoosh },
            phone.feedback.count,
            watch.packets.count { $0.kind == .nearMiss }
        )
    }

    private func runStartCueGateCase(
        sfxEnabled: Bool,
        hapticsEnabled: Bool
    ) async throws -> (
        audioCount: Int,
        phoneCount: Int,
        watchCount: Int,
        audioRoles: [AudioAssetRole],
        audioRates: [Double],
        watchKinds: [WatchFeedbackKind]
    ) {
        let assets = RecordingAudioAssets()
        let backend = RecordingAudioBackend()
        let director = makeDirector(assets: assets, backend: backend)
        try director.prepareAssets()
        director.setSFXEnabled(sfxEnabled)
        let phone = AudioRecordingPhoneFeedbackPlayer()
        let watch = AudioRecordingWatchFeedbackSender()
        let controller = GameSessionController(
            seed: 2,
            feedbackPlayer: phone,
            watchFeedbackSender: watch,
            audioDirector: director,
            isHapticsEnabled: { hapticsEnabled },
            countdownSleeper: {}
        )
        await waitUntil { controller.presentationPhase == .racing }

        return (
            backend.playedRoles.count,
            phone.startCues.count,
            watch.packets.count,
            backend.playedRoles,
            backend.playedRates,
            watch.packets.map(\.kind)
        )
    }

    private func makePresentation(
        event: GameEvent,
        relativeX: Double,
        nearMissMargin: Double,
        elapsedTime: TimeInterval
    ) -> GameEventPresentation {
        let obstacleID = switch event {
        case let .nearMiss(obstacleID, _, _), let .collision(obstacleID, _):
            obstacleID
        }
        var configuration = GameSimulation.Configuration()
        configuration.playerWidth = 1
        configuration.nearMissMargin = nearMissMargin
        let obstacle = ObstacleSnapshot(
            id: obstacleID,
            rowID: obstacleID,
            kind: .barrier,
            laneIndex: 1,
            x: relativeX,
            distance: 0,
            width: 1,
            length: 1,
            closingSpeed: 0,
            didAwardNearMiss: false
        )
        let snapshot = GameSnapshot(
            phase: .running,
            playerX: 0,
            playerWidth: 1,
            playerLength: 1.8,
            roadHalfWidth: 3,
            laneWidth: 2,
            obstacles: [obstacle],
            score: 100,
            speed: 12,
            elapsedTime: elapsedTime,
            distance: 0,
            spawnInterval: 2
        )
        return GameEventPresentation(
            event: event,
            snapshot: snapshot,
            configuration: configuration
        )
    }

    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private var audioDirectory: URL {
        repositoryRoot.appendingPathComponent("WatchCarRacer/iOS/Resources/Audio")
    }

    private func waitUntil(
        _ predicate: @MainActor () -> Bool,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        for _ in 0..<1_000 {
            if predicate() { return }
            await Task.yield()
        }
        XCTFail("Condition did not become true", file: file, line: line)
    }
}

@MainActor
private final class RecordingAudioAssets: AudioAssetProviding {
    private let prepareError: (any Error)?
    private(set) var isPrepared = false
    private(set) var metrics = AudioAssetLibraryMetrics()

    init(prepareError: (any Error)? = nil) {
        self.prepareError = prepareError
    }

    func prepare() throws {
        if let prepareError { throw prepareError }
        isPrepared = true
    }

    func buffer(for role: AudioAssetRole) throws -> AVAudioPCMBuffer {
        throw AudioAssetLibraryError.decodeFailure(role.rawValue)
    }
}

@MainActor
private final class RecordingAudioBackend: GameAudioBackend {
    private final class IdentityToken {}

    private let identity = IdentityToken()
    private let error: (any Error)?
    private(set) var transitions: [GameAudioContext] = []
    private(set) var appliedMixes: [AudioMixSnapshot] = []
    private(set) var playedRoles: [AudioAssetRole] = []
    private(set) var playedPans: [Double] = []
    private(set) var playedRates: [Double] = []
    private(set) var playedGains: [Double] = []
    private(set) var stopCount = 0
    private(set) var rebuildCount = 0
    private(set) var prepareCount = 0
    private(set) var maximumDuplicateGraphCount = 0
    private(set) var updatePathAllocationCount = 0

    init(error: (any Error)? = nil) {
        self.error = error
    }

    var diagnostics: GameAudioBackendDiagnostics {
        GameAudioBackendDiagnostics(
            engineIdentity: ObjectIdentifier(identity),
            longLivedNodeCount: 16,
            nodeAllocationCount: 14,
            maximumSimultaneousOneShots: min(playedRoles.count, 4)
        )
    }

    func prepare(using assets: any AudioAssetProviding) throws {
        prepareCount += 1
        maximumDuplicateGraphCount = max(maximumDuplicateGraphCount, 1)
        try failIfNeeded()
    }

    func activate() throws {
        try failIfNeeded()
    }

    func transition(to context: GameAudioContext) throws {
        try failIfNeeded()
        transitions.append(context)
    }

    func apply(_ mix: AudioMixSnapshot) throws {
        try failIfNeeded()
        appliedMixes.append(mix)
    }

    func play(role: AudioAssetRole, rate: Double, pan: Double, gain: Double) throws {
        try failIfNeeded()
        playedRoles.append(role)
        playedPans.append(pan)
        playedRates.append(rate)
        playedGains.append(gain)
    }

    func stopAllOutput() {
        stopCount += 1
    }

    func suspend() throws {
        try failIfNeeded()
    }

    func rebuild() throws {
        try failIfNeeded()
        rebuildCount += 1
    }

    private func failIfNeeded() throws {
        if let error { throw error }
    }
}

@MainActor
private final class AudioRecordingPhoneFeedbackPlayer: PhoneFeedbackPlaying {
    private(set) var feedback: [GameFeedback] = []
    private(set) var startCues: [StartCuePresentation] = []

    func play(_ feedback: GameFeedback) {
        self.feedback.append(feedback)
    }

    func playStartCue(_ cue: StartCuePresentation) {
        startCues.append(cue)
    }
}

@MainActor
private final class AudioRecordingWatchFeedbackSender: WatchFeedbackSending {
    private(set) var packets: [WatchFeedbackPacket] = []

    func sendFeedback(_ packet: WatchFeedbackPacket) throws {
        packets.append(packet)
    }
}

private enum AudioTestError: Error {
    case asset
    case runtime
}

private final class AudioSelectionStore: VehicleSelectionStoring {
    func load() -> VehicleSelection {
        VehicleCatalog.defaultSelection
    }

    func save(_ selection: VehicleSelection) {}
}

private final class AudioBestScoreStore: LocalBestScoreStoring {
    func load() -> Int { 0 }

    func record(_ score: Int) -> Int { max(score, 0) }
}
