import Foundation
import XCTest
@testable import WatchCarRacer

@MainActor
final class SensorySettingsTests: XCTestCase {
    func testEmptyDefaultsReturnDefaultsAndSelfHeal() throws {
        try withIsolatedDefaults { defaults in
            let store = UserDefaultsSensorySettingsStore(defaults: defaults)

            XCTAssertNil(defaults.object(forKey: UserDefaultsSensorySettingsStore.storageKey))
            XCTAssertEqual(store.load(), .defaultValue)
            assertStoredSettings(.defaultValue, in: defaults)
        }
    }

    func testSettingsPersistAcrossControllerRecreation() throws {
        try withIsolatedDefaults { defaults in
            let store = UserDefaultsSensorySettingsStore(defaults: defaults)
            let firstController = SensorySettingsController(store: store)

            firstController.setSFXEnabled(false)
            firstController.setHapticsEnabled(false)
            firstController.setEffectIntensity(.reduced)

            let recreatedController = SensorySettingsController(
                store: UserDefaultsSensorySettingsStore(defaults: defaults)
            )
            XCTAssertEqual(
                recreatedController.settings,
                SensorySettings(
                    sfxEnabled: false,
                    hapticsEnabled: false,
                    effectIntensity: .reduced
                )
            )
        }
    }

    func testCorruptPayloadReturnsDefaultsAndSelfHeals() throws {
        try withIsolatedDefaults { defaults in
            defaults.set(
                Data("not-json".utf8),
                forKey: UserDefaultsSensorySettingsStore.storageKey
            )
            let store = UserDefaultsSensorySettingsStore(defaults: defaults)

            XCTAssertEqual(store.load(), .defaultValue)
            assertStoredSettings(.defaultValue, in: defaults)
        }
    }

    func testUnknownSchemaVersionReturnsDefaultsAndSelfHeals() throws {
        try withIsolatedDefaults { defaults in
            setPayload(
                version: UserDefaultsSensorySettingsStore.currentSchemaVersion + 1,
                settings: SensorySettings(
                    sfxEnabled: false,
                    hapticsEnabled: false,
                    effectIntensity: .reduced
                ),
                in: defaults
            )
            let store = UserDefaultsSensorySettingsStore(defaults: defaults)

            XCTAssertEqual(store.load(), .defaultValue)
            assertStoredSettings(.defaultValue, in: defaults)
        }
    }

    func testSFXAndHapticsToggleIndependently() {
        let store = RecordingSensorySettingsStore(settings: .defaultValue)
        let controller = SensorySettingsController(store: store)

        controller.setSFXEnabled(false)
        XCTAssertFalse(controller.settings.sfxEnabled)
        XCTAssertTrue(controller.settings.hapticsEnabled)

        controller.setHapticsEnabled(false)
        XCTAssertFalse(controller.settings.sfxEnabled)
        XCTAssertFalse(controller.settings.hapticsEnabled)

        controller.setSFXEnabled(true)
        XCTAssertTrue(controller.settings.sfxEnabled)
        XCTAssertFalse(controller.settings.hapticsEnabled)
        XCTAssertEqual(store.savedSettings.count, 3)
    }

    func testBalancedAndReducedIntensityRoundTrip() throws {
        try withIsolatedDefaults { defaults in
            let store = UserDefaultsSensorySettingsStore(defaults: defaults)

            for intensity in SensoryEffectIntensity.allCases {
                let settings = SensorySettings(
                    sfxEnabled: false,
                    hapticsEnabled: true,
                    effectIntensity: intensity
                )
                store.save(settings)
                XCTAssertEqual(store.load(), settings)
            }
        }
    }

    func testAccessibilityPolicyCoversEveryIntensityAndSystemSettingCombination() {
        typealias Level = SensoryAccessibilityPolicy.DecorativeEffectLevel
        typealias Panel = SensoryAccessibilityPolicy.PanelTreatment
        typealias Static = SensoryAccessibilityPolicy.StaticFeedbackEmphasis

        struct Case {
            let intensity: SensoryEffectIntensity
            let reduceMotion: Bool
            let reduceTransparency: Bool
            let motion: Level
            let roadLights: Level
            let fog: Level
            let panel: Panel
            let staticFeedback: Static
            let allowsFogMotion: Bool
            let usesOpaqueFeedback: Bool
        }

        let cases = [
            Case(
                intensity: .balanced,
                reduceMotion: false,
                reduceTransparency: false,
                motion: .balanced,
                roadLights: .balanced,
                fog: .balanced,
                panel: .translucent,
                staticFeedback: .supplemental,
                allowsFogMotion: true,
                usesOpaqueFeedback: false
            ),
            Case(
                intensity: .balanced,
                reduceMotion: false,
                reduceTransparency: true,
                motion: .balanced,
                roadLights: .off,
                fog: .off,
                panel: .opaque,
                staticFeedback: .supplemental,
                allowsFogMotion: true,
                usesOpaqueFeedback: true
            ),
            Case(
                intensity: .balanced,
                reduceMotion: true,
                reduceTransparency: false,
                motion: .off,
                roadLights: .off,
                fog: .balanced,
                panel: .translucent,
                staticFeedback: .primary,
                allowsFogMotion: false,
                usesOpaqueFeedback: false
            ),
            Case(
                intensity: .balanced,
                reduceMotion: true,
                reduceTransparency: true,
                motion: .off,
                roadLights: .off,
                fog: .off,
                panel: .opaque,
                staticFeedback: .primary,
                allowsFogMotion: false,
                usesOpaqueFeedback: true
            ),
            Case(
                intensity: .reduced,
                reduceMotion: false,
                reduceTransparency: false,
                motion: .reduced,
                roadLights: .reduced,
                fog: .reduced,
                panel: .translucent,
                staticFeedback: .supplemental,
                allowsFogMotion: true,
                usesOpaqueFeedback: false
            ),
            Case(
                intensity: .reduced,
                reduceMotion: false,
                reduceTransparency: true,
                motion: .reduced,
                roadLights: .off,
                fog: .off,
                panel: .opaque,
                staticFeedback: .supplemental,
                allowsFogMotion: true,
                usesOpaqueFeedback: true
            ),
            Case(
                intensity: .reduced,
                reduceMotion: true,
                reduceTransparency: false,
                motion: .off,
                roadLights: .off,
                fog: .reduced,
                panel: .translucent,
                staticFeedback: .primary,
                allowsFogMotion: false,
                usesOpaqueFeedback: false
            ),
            Case(
                intensity: .reduced,
                reduceMotion: true,
                reduceTransparency: true,
                motion: .off,
                roadLights: .off,
                fog: .off,
                panel: .opaque,
                staticFeedback: .primary,
                allowsFogMotion: false,
                usesOpaqueFeedback: true
            ),
        ]

        XCTAssertEqual(cases.count, SensoryEffectIntensity.allCases.count * 2 * 2)
        for testCase in cases {
            var settings = SensorySettings.defaultValue
            settings.effectIntensity = testCase.intensity

            let policy = SensoryAccessibilityPolicy(
                settings: settings,
                reduceMotion: testCase.reduceMotion,
                reduceTransparency: testCase.reduceTransparency
            )

            XCTAssertEqual(policy.camera, testCase.motion)
            XCTAssertEqual(policy.body, testCase.motion)
            XCTAssertEqual(policy.streaks, testCase.motion)
            XCTAssertEqual(policy.roadLights, testCase.roadLights)
            XCTAssertEqual(policy.debris, testCase.motion)
            XCTAssertEqual(policy.fog, testCase.fog)
            XCTAssertEqual(policy.panel, testCase.panel)
            XCTAssertEqual(policy.staticFeedback, testCase.staticFeedback)
            XCTAssertEqual(policy.allowsFogMotion, testCase.allowsFogMotion)
            XCTAssertEqual(policy.usesOpaqueFeedback, testCase.usesOpaqueFeedback)
        }
    }

    func testMicroInteractionStyleUsesOpacityOnlyAndReducedAlphaClamps() {
        let balanced = SensoryMicroInteractionStyle(
            effectIntensity: .balanced,
            reduceMotion: false
        )
        let reduced = SensoryMicroInteractionStyle(
            effectIntensity: .reduced,
            reduceMotion: false
        )
        let reduceMotion = SensoryMicroInteractionStyle(
            effectIntensity: .balanced,
            reduceMotion: true
        )

        XCTAssertTrue(balanced.usesMotion)
        XCTAssertTrue(reduced.usesMotion)
        XCTAssertFalse(reduceMotion.usesMotion)
        XCTAssertLessThan(reduced.materialSweepAlpha, balanced.materialSweepAlpha)
        XCTAssertLessThan(reduced.routeSweepAlpha, balanced.routeSweepAlpha)
        XCTAssertGreaterThan(reduceMotion.materialSweepAlpha, 0)
        XCTAssertGreaterThan(reduceMotion.routeSweepAlpha, 0)
    }

    func testSettingsMutationDoesNotAlterAppRouteSessionOrScore() throws {
        let bestScoreStore = SensoryBestScoreStore(score: 87)
        let flow = AppFlowController(
            selectionStore: SensoryVehicleSelectionStore(),
            localBestScoreStore: bestScoreStore,
            assetLibrary: try GameAssetLibrary()
        )
        let controller = SensorySettingsController(
            store: RecordingSensorySettingsStore(settings: .defaultValue)
        )

        controller.setSFXEnabled(false)
        controller.setHapticsEnabled(false)
        controller.setEffectIntensity(.reduced)

        XCTAssertEqual(flow.route, .hub)
        XCTAssertNil(flow.gameSession)
        XCTAssertEqual(bestScoreStore.load(), 87)
    }

    private func withIsolatedDefaults(
        _ body: (UserDefaults) throws -> Void
    ) throws {
        let suiteName = "SensorySettingsTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        try body(defaults)
    }

    private func setPayload(
        version: Int,
        settings: SensorySettings,
        in defaults: UserDefaults
    ) {
        let payload = StoredSensorySettingsPayload(
            schemaVersion: version,
            settings: settings
        )
        defaults.set(
            try? JSONEncoder().encode(payload),
            forKey: UserDefaultsSensorySettingsStore.storageKey
        )
    }

    private func assertStoredSettings(
        _ expectedSettings: SensorySettings,
        in defaults: UserDefaults,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard let data = defaults.data(
            forKey: UserDefaultsSensorySettingsStore.storageKey
        ) else {
            return XCTFail("Missing self-healed payload", file: file, line: line)
        }
        do {
            let payload = try JSONDecoder().decode(
                StoredSensorySettingsPayload.self,
                from: data
            )
            XCTAssertEqual(
                payload.schemaVersion,
                UserDefaultsSensorySettingsStore.currentSchemaVersion,
                file: file,
                line: line
            )
            XCTAssertEqual(payload.settings, expectedSettings, file: file, line: line)
        } catch {
            XCTFail("Invalid self-healed payload: \(error)", file: file, line: line)
        }
    }
}

private struct StoredSensorySettingsPayload: Codable {
    let schemaVersion: Int
    let settings: SensorySettings
}

private final class RecordingSensorySettingsStore: SensorySettingsStoring {
    private var storedSettings: SensorySettings
    private(set) var savedSettings: [SensorySettings] = []

    init(settings: SensorySettings) {
        storedSettings = settings
    }

    func load() -> SensorySettings {
        storedSettings
    }

    func save(_ settings: SensorySettings) {
        storedSettings = settings
        savedSettings.append(settings)
    }
}

private final class SensoryVehicleSelectionStore: VehicleSelectionStoring {
    func load() -> VehicleSelection {
        VehicleCatalog.defaultSelection
    }

    func save(_ selection: VehicleSelection) {}
}

private final class SensoryBestScoreStore: LocalBestScoreStoring {
    private var score: Int

    init(score: Int) {
        self.score = score
    }

    func load() -> Int {
        score
    }

    func record(_ score: Int) -> Int {
        self.score = max(self.score, score)
        return self.score
    }
}
