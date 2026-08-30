import Foundation
import Observation

enum SensoryEffectIntensity: String, Codable, CaseIterable {
    case balanced
    case reduced

    var displayName: String {
        switch self {
        case .balanced:
            return "Balanced"
        case .reduced:
            return "Reduced"
        }
    }
}

struct SensorySettings: Codable, Equatable {
    static let defaultValue = SensorySettings(
        sfxEnabled: true,
        hapticsEnabled: true,
        effectIntensity: .balanced
    )

    var sfxEnabled: Bool
    var hapticsEnabled: Bool
    var effectIntensity: SensoryEffectIntensity
}

protocol SensorySettingsStoring {
    func load() -> SensorySettings
    func save(_ settings: SensorySettings)
}

final class UserDefaultsSensorySettingsStore: SensorySettingsStoring {
    static let currentSchemaVersion = 1
    static let storageKey = "com.woohyuk.WatchCarRacer.sensorySettings"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> SensorySettings {
        guard let data = defaults.data(forKey: Self.storageKey),
              let payload = try? JSONDecoder().decode(Payload.self, from: data),
              payload.schemaVersion == Self.currentSchemaVersion else {
            return restoreDefault()
        }
        return payload.settings
    }

    func save(_ settings: SensorySettings) {
        let payload = Payload(
            schemaVersion: Self.currentSchemaVersion,
            settings: settings
        )
        guard let data = try? JSONEncoder().encode(payload) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }

    private func restoreDefault() -> SensorySettings {
        let settings = SensorySettings.defaultValue
        save(settings)
        return settings
    }
}

@MainActor
@Observable
final class SensorySettingsController {
    private(set) var settings: SensorySettings

    @ObservationIgnored private let store: any SensorySettingsStoring

    init(store: any SensorySettingsStoring) {
        self.store = store
        settings = store.load()
    }

    func setSFXEnabled(_ isEnabled: Bool) {
        update { $0.sfxEnabled = isEnabled }
    }

    func setHapticsEnabled(_ isEnabled: Bool) {
        update { $0.hapticsEnabled = isEnabled }
    }

    func setEffectIntensity(_ intensity: SensoryEffectIntensity) {
        update { $0.effectIntensity = intensity }
    }

    private func update(_ mutation: (inout SensorySettings) -> Void) {
        var updatedSettings = settings
        mutation(&updatedSettings)
        guard updatedSettings != settings else { return }
        settings = updatedSettings
        store.save(updatedSettings)
    }
}

private struct Payload: Codable {
    let schemaVersion: Int
    let settings: SensorySettings
}
