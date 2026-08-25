import Foundation

protocol VehicleSelectionStoring {
    /// Loads the committed selection. Invalid or missing data is replaced with the catalog default.
    func load() -> VehicleSelection

    /// Persists a committed selection. Draft changes must not call this method.
    func save(_ selection: VehicleSelection)
}

final class UserDefaultsVehicleSelectionStore: VehicleSelectionStoring {
    static let currentSchemaVersion = 1
    static let storageKey = "com.woohyuk.WatchCarRacer.vehicleSelection"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> VehicleSelection {
        guard let data = defaults.data(forKey: Self.storageKey),
              let payload = try? JSONDecoder().decode(Payload.self, from: data),
              payload.schemaVersion == Self.currentSchemaVersion,
              VehicleCatalog.resolve(payload.selection) != nil else {
            return restoreDefault()
        }
        return payload.selection
    }

    func save(_ selection: VehicleSelection) {
        guard VehicleCatalog.resolve(selection) != nil else { return }
        let payload = Payload(
            schemaVersion: Self.currentSchemaVersion,
            selection: selection
        )
        guard let data = try? JSONEncoder().encode(payload) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }

    private func restoreDefault() -> VehicleSelection {
        let selection = VehicleCatalog.defaultSelection
        save(selection)
        return selection
    }
}

private struct Payload: Codable {
    let schemaVersion: Int
    let selection: VehicleSelection
}
