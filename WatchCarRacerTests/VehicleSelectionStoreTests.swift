import Foundation
import XCTest
@testable import WatchCarRacer

final class VehicleSelectionStoreTests: XCTestCase {
    func testSaveAndLoadRoundTripUsesOneNamespacedKey() throws {
        try withIsolatedDefaults { defaults, suiteName in
            let store = UserDefaultsVehicleSelectionStore(defaults: defaults)
            let selection = VehicleSelection(vehicleID: .gt, colorID: .pulseMagenta)

            store.save(selection)

            XCTAssertEqual(store.load(), selection)
            XCTAssertEqual(
                Set((defaults.persistentDomain(forName: suiteName) ?? [:]).keys),
                [UserDefaultsVehicleSelectionStore.storageKey]
            )
        }
    }

    func testAbsentDataReturnsDefaultAndSelfHeals() throws {
        try withIsolatedDefaults { defaults, _ in
            let store = UserDefaultsVehicleSelectionStore(defaults: defaults)

            XCTAssertNil(defaults.object(forKey: UserDefaultsVehicleSelectionStore.storageKey))
            XCTAssertEqual(store.load(), VehicleCatalog.defaultSelection)
            assertCurrentDefaultPayload(in: defaults)
        }
    }

    func testCorruptJSONReturnsDefaultAndSelfHeals() throws {
        try withIsolatedDefaults { defaults, _ in
            defaults.set(
                Data("not-json".utf8),
                forKey: UserDefaultsVehicleSelectionStore.storageKey
            )
            let store = UserDefaultsVehicleSelectionStore(defaults: defaults)

            XCTAssertEqual(store.load(), VehicleCatalog.defaultSelection)
            assertCurrentDefaultPayload(in: defaults)
        }
    }

    func testUnknownVehicleIDReturnsDefaultAndSelfHeals() throws {
        try withIsolatedDefaults { defaults, _ in
            setPayload(
                version: UserDefaultsVehicleSelectionStore.currentSchemaVersion,
                vehicleID: "prototype",
                colorID: VehicleColorID.auroraMint.rawValue,
                in: defaults
            )
            let store = UserDefaultsVehicleSelectionStore(defaults: defaults)

            XCTAssertEqual(store.load(), VehicleCatalog.defaultSelection)
            assertCurrentDefaultPayload(in: defaults)
        }
    }

    func testUnknownColorIDReturnsDefaultAndSelfHeals() throws {
        try withIsolatedDefaults { defaults, _ in
            setPayload(
                version: UserDefaultsVehicleSelectionStore.currentSchemaVersion,
                vehicleID: VehicleID.rally.rawValue,
                colorID: "custom-picker-color",
                in: defaults
            )
            let store = UserDefaultsVehicleSelectionStore(defaults: defaults)

            XCTAssertEqual(store.load(), VehicleCatalog.defaultSelection)
            assertCurrentDefaultPayload(in: defaults)
        }
    }

    func testUnsupportedFutureSchemaReturnsDefaultAndSelfHeals() throws {
        try withIsolatedDefaults { defaults, _ in
            setPayload(
                version: UserDefaultsVehicleSelectionStore.currentSchemaVersion + 1,
                vehicleID: VehicleID.angular.rawValue,
                colorID: VehicleColorID.ultraviolet.rawValue,
                in: defaults
            )
            let store = UserDefaultsVehicleSelectionStore(defaults: defaults)

            XCTAssertEqual(store.load(), VehicleCatalog.defaultSelection)
            assertCurrentDefaultPayload(in: defaults)
        }
    }

    private func withIsolatedDefaults(
        _ body: (UserDefaults, String) throws -> Void
    ) throws {
        let suiteName = "VehicleSelectionStoreTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        try body(defaults, suiteName)
    }

    private func setPayload(
        version: Int,
        vehicleID: String,
        colorID: String,
        in defaults: UserDefaults
    ) {
        let json = """
        {
          "schemaVersion": \(version),
          "selection": {
            "vehicleID": "\(vehicleID)",
            "colorID": "\(colorID)"
          }
        }
        """
        defaults.set(
            Data(json.utf8),
            forKey: UserDefaultsVehicleSelectionStore.storageKey
        )
    }

    private func assertCurrentDefaultPayload(
        in defaults: UserDefaults,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard let data = defaults.data(
            forKey: UserDefaultsVehicleSelectionStore.storageKey
        ) else {
            return XCTFail("Missing self-healed payload", file: file, line: line)
        }
        do {
            let payload = try JSONDecoder().decode(StoredPayload.self, from: data)
            XCTAssertEqual(
                payload.schemaVersion,
                UserDefaultsVehicleSelectionStore.currentSchemaVersion,
                file: file,
                line: line
            )
            XCTAssertEqual(
                payload.selection,
                VehicleCatalog.defaultSelection,
                file: file,
                line: line
            )
        } catch {
            XCTFail("Invalid self-healed payload: \(error)", file: file, line: line)
        }
    }
}

private struct StoredPayload: Codable {
    let schemaVersion: Int
    let selection: VehicleSelection
}
