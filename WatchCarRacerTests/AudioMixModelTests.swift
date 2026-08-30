import XCTest
@testable import WatchCarRacer

final class AudioMixModelTests: XCTestCase {
    func testInitialMidAndMaximumSpeedSelectExpectedEngineLayers() {
        let cases: [(speed: Double, gains: [Double])] = [
            (12, [AudioMixModel.engineGain, 0, 0]),
            (18, [0, AudioMixModel.engineGain, 0]),
            (24, [0, 0, AudioMixModel.engineGain]),
        ]

        for testCase in cases {
            let mix = AudioMixModel.target(
                speed: testCase.speed,
                initialSpeed: 12,
                maximumSpeed: 24,
                steering: 0
            )
            XCTAssertEqual(mix.idleGain, testCase.gains[0], accuracy: 0.000_001)
            XCTAssertEqual(mix.midGain, testCase.gains[1], accuracy: 0.000_001)
            XCTAssertEqual(mix.highGain, testCase.gains[2], accuracy: 0.000_001)
        }
    }

    func testEngineCrossfadeHasConstantEnergyAcrossSpeedRange() {
        for speed in stride(from: 12.0, through: 24.0, by: 0.25) {
            let mix = AudioMixModel.target(
                speed: speed,
                initialSpeed: 12,
                maximumSpeed: 24,
                steering: 0
            )
            XCTAssertEqual(
                mix.engineEnergy,
                AudioMixModel.engineGain * AudioMixModel.engineGain,
                accuracy: 0.000_001,
                "speed=\(speed)"
            )
        }
    }

    func testAllValuesStayFiniteAndBoundedForInvalidAndExtremeInputs() {
        for value in [
            -Double.infinity,
            -1_000,
            0,
            1_000,
            Double.infinity,
            Double.nan,
        ] {
            let mix = AudioMixModel.target(
                speed: value,
                initialSpeed: value,
                maximumSpeed: value,
                steering: value
            )
            XCTAssertTrue(mix.allValues.allSatisfy(\.isFinite))
            XCTAssertTrue([mix.idleGain, mix.midGain, mix.highGain].allSatisfy {
                (0...AudioMixModel.engineGain).contains($0)
            })
            XCTAssertTrue([mix.idleRate, mix.midRate, mix.highRate].allSatisfy {
                (0.75...1.35).contains($0)
            })
            XCTAssertTrue((0...0.38).contains(mix.roadGain))
            XCTAssertTrue((0...0.34).contains(mix.windGain))
            XCTAssertTrue((0...0.32).contains(mix.tireScrubGain))
        }
    }

    func testRoadAndWindGainsAreMonotonic() {
        let mixes = stride(from: 12.0, through: 24.0, by: 0.5).map {
            AudioMixModel.target(
                speed: $0,
                initialSpeed: 12,
                maximumSpeed: 24,
                steering: 0
            )
        }

        for pair in zip(mixes, mixes.dropFirst()) {
            XCTAssertLessThanOrEqual(pair.0.roadGain, pair.1.roadGain)
            XCTAssertLessThanOrEqual(pair.0.windGain, pair.1.windGain)
        }
        XCTAssertGreaterThan(mixes.last!.roadGain, mixes.first!.roadGain)
        XCTAssertGreaterThan(mixes.last!.windGain, mixes.first!.windGain)
    }

    func testTireScrubHasSymmetricDeadZoneAndSmoothResponse() {
        let insideLeft = AudioMixModel.target(
            speed: 24,
            initialSpeed: 12,
            maximumSpeed: 24,
            steering: -AudioMixModel.steeringDeadZone
        )
        let insideRight = AudioMixModel.target(
            speed: 24,
            initialSpeed: 12,
            maximumSpeed: 24,
            steering: AudioMixModel.steeringDeadZone
        )
        let outsideLeft = AudioMixModel.target(
            speed: 24,
            initialSpeed: 12,
            maximumSpeed: 24,
            steering: -0.8
        )
        let outsideRight = AudioMixModel.target(
            speed: 24,
            initialSpeed: 12,
            maximumSpeed: 24,
            steering: 0.8
        )
        XCTAssertEqual(insideLeft.tireScrubGain, 0)
        XCTAssertEqual(insideRight.tireScrubGain, 0)
        XCTAssertEqual(outsideLeft.tireScrubGain, outsideRight.tireScrubGain, accuracy: 0.000_001)
        XCTAssertGreaterThan(outsideLeft.tireScrubGain, 0)

        var model = AudioMixModel()
        let first = model.update(
            speed: 24,
            initialSpeed: 12,
            maximumSpeed: 24,
            steering: 1,
            deltaTime: 1 / 30
        )
        let second = model.update(
            speed: 24,
            initialSpeed: 12,
            maximumSpeed: 24,
            steering: 1,
            deltaTime: 1 / 30
        )
        XCTAssertGreaterThan(first.tireScrubGain, 0)
        XCTAssertLessThan(first.tireScrubGain, 0.32)
        XCTAssertGreaterThan(second.tireScrubGain, first.tireScrubGain)
        XCTAssertLessThan(second.tireScrubGain, 0.32)
    }

    func testDirectionalMixClampsPanAndPreservesEqualPowerGain() {
        for pan in [-Double.infinity, -2, -0.75, 0, 0.75, 2, Double.nan] {
            let mix = AudioMixModel.directionalMix(pan: pan, gain: 0.8)
            XCTAssertTrue(mix.pan.isFinite)
            XCTAssertTrue((-0.75...0.75).contains(mix.pan))
            XCTAssertEqual(
                mix.leftGain * mix.leftGain + mix.rightGain * mix.rightGain,
                0.8 * 0.8,
                accuracy: 0.000_001
            )
        }
    }
}
