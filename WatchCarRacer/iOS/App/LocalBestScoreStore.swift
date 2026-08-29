import CoreFoundation
import Foundation

protocol LocalBestScoreStoring {
    func load() -> Int

    @discardableResult
    func record(_ score: Int) -> Int
}

final class LocalBestScoreStore: LocalBestScoreStoring {
    static let storageKey = "com.woohyuk.WatchCarRacer.localBestScore"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> Int {
        guard let storedValue = defaults.object(forKey: Self.storageKey) else {
            return 0
        }
        guard let score = validScore(from: storedValue) else {
            defaults.set(0, forKey: Self.storageKey)
            return 0
        }
        return score
    }

    @discardableResult
    func record(_ score: Int) -> Int {
        let localBest = load()
        guard score > localBest else { return localBest }
        defaults.set(score, forKey: Self.storageKey)
        return score
    }

    private func validScore(from value: Any) -> Int? {
        guard let number = value as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID(),
              let score = Int(number.stringValue),
              score >= 0 else {
            return nil
        }
        return score
    }
}
