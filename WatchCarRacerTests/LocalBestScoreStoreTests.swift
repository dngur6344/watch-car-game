import Foundation
import XCTest
@testable import WatchCarRacer

final class LocalBestScoreStoreTests: XCTestCase {
    func testAbsentValueReturnsZeroWithoutCreatingStorage() throws {
        try withIsolatedDefaults { defaults, _ in
            let store = LocalBestScoreStore(defaults: defaults)

            XCTAssertNil(defaults.object(forKey: LocalBestScoreStore.storageKey))
            XCTAssertEqual(store.load(), 0)
            XCTAssertNil(defaults.object(forKey: LocalBestScoreStore.storageKey))
            XCTAssertEqual(defaults.setCallCount, 0)
        }
    }

    func testInvalidValueSelfHealsToZero() throws {
        try withIsolatedDefaults { defaults, _ in
            defaults.set("not-an-integer", forKey: LocalBestScoreStore.storageKey)
            let writesBeforeLoad = defaults.setCallCount
            let store = LocalBestScoreStore(defaults: defaults)

            XCTAssertEqual(store.load(), 0)
            XCTAssertEqual(defaults.integer(forKey: LocalBestScoreStore.storageKey), 0)
            XCTAssertEqual(defaults.setCallCount, writesBeforeLoad + 1)
        }
    }

    func testNegativeValueSelfHealsToZero() throws {
        try withIsolatedDefaults { defaults, _ in
            defaults.set(-14, forKey: LocalBestScoreStore.storageKey)
            let writesBeforeLoad = defaults.setCallCount
            let store = LocalBestScoreStore(defaults: defaults)

            XCTAssertEqual(store.load(), 0)
            XCTAssertEqual(defaults.integer(forKey: LocalBestScoreStore.storageKey), 0)
            XCTAssertEqual(defaults.setCallCount, writesBeforeLoad + 1)
        }
    }

    func testOnlyHigherScoresWriteAndReturnTheMonotonicBest() throws {
        try withIsolatedDefaults { defaults, _ in
            let store = LocalBestScoreStore(defaults: defaults)

            XCTAssertEqual(store.record(120), 120)
            XCTAssertEqual(defaults.setCallCount, 1)
            XCTAssertEqual(store.record(120), 120)
            XCTAssertEqual(store.record(80), 120)
            XCTAssertEqual(store.record(-1), 120)
            XCTAssertEqual(defaults.setCallCount, 1)

            XCTAssertEqual(store.record(121), 121)
            XCTAssertEqual(defaults.setCallCount, 2)
            XCTAssertEqual(store.load(), 121)
        }
    }

    func testStoreUsesOneNamespacedVersionlessIntegerKey() throws {
        try withIsolatedDefaults { defaults, suiteName in
            let store = LocalBestScoreStore(defaults: defaults)

            store.record(44)

            let domain = defaults.persistentDomain(forName: suiteName) ?? [:]
            XCTAssertEqual(Set(domain.keys), [LocalBestScoreStore.storageKey])
            XCTAssertEqual(domain[LocalBestScoreStore.storageKey] as? Int, 44)
            XCTAssertTrue(LocalBestScoreStore.storageKey.hasPrefix("com.woohyuk.WatchCarRacer."))
        }
    }

    private func withIsolatedDefaults(
        _ body: (RecordingUserDefaults, String) throws -> Void
    ) throws {
        let suiteName = "LocalBestScoreStoreTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(RecordingUserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        try body(defaults, suiteName)
    }
}

private final class RecordingUserDefaults: UserDefaults {
    private(set) var setCallCount = 0

    override func set(_ value: Any?, forKey defaultName: String) {
        setCallCount += 1
        super.set(value, forKey: defaultName)
    }
}
