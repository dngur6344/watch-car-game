import XCTest
@testable import WatchCarRacer

@MainActor
final class SG8SensoryAcceptanceTests: XCTestCase {
    func testLaunchConfigurationParsesOnlySupportedExplicitValues() {
        let supported = SG8SensoryLaunchConfiguration(
            arguments: [
                "--sg8-effect-intensity", "reduced",
                "--sg8-expect-reduce-motion", "true",
                "--sg8-expect-reduce-transparency", "false",
            ]
        )
        XCTAssertEqual(supported.effectIntensity, .reduced)
        XCTAssertEqual(supported.expectedReduceMotion, true)
        XCTAssertEqual(supported.expectedReduceTransparency, false)

        let unsupported = SG8SensoryLaunchConfiguration(
            arguments: [
                "--sg8-effect-intensity", "unsupported",
                "--sg8-expect-reduce-motion", "1",
            ]
        )
        XCTAssertNil(unsupported.effectIntensity)
        XCTAssertNil(unsupported.expectedReduceMotion)
        XCTAssertNil(unsupported.expectedReduceTransparency)
    }

    func testCueEvaluationAcceptsMeasuredProductionContractOrderAndDurations() {
        let evaluation = SG8SensoryCueEvaluation(
            events: makeEvents(order: [.three, .two, .one, .go])
        )

        XCTAssertTrue(evaluation.pass)
        XCTAssertEqual(evaluation.cueOrder, [.three, .two, .one, .go])
        XCTAssertEqual(evaluation.contractDurationsMilliseconds, [180, 180, 180, 260])
        for (measured, expected) in zip(
            evaluation.visibleDurationsMilliseconds,
            [180.0, 180.0, 180.0, 260.0]
        ) {
            XCTAssertEqual(measured, expected, accuracy: 0.001)
        }
        XCTAssertEqual(evaluation.hapticFanoutCount, 4)
    }

    func testCueEvaluationRejectsWrongOrderAndDuplicateVisibility() {
        var events = makeEvents(order: [.three, .one, .two, .go])
        guard case let .startCueVisible(id, kind) = events[1].kind else {
            return XCTFail("Expected the first cue visibility event")
        }
        events.append(
            SG6AcceptanceProbe.Event(
                sequence: events.count + 1,
                kind: .startCueVisible(id, kind),
                timestamp: 9
            )
        )

        let evaluation = SG8SensoryCueEvaluation(events: events)

        XCTAssertFalse(evaluation.pass)
        XCTAssertEqual(evaluation.cueOrder, [.three, .one, .two, .go])
    }

    func testCueEvaluationRejectsVisibilityOutsideRuntimeTolerance() {
        let events = makeEvents(
            order: [.three, .two, .one, .go],
            extraVisibleMilliseconds: 51
        )

        let evaluation = SG8SensoryCueEvaluation(events: events)

        XCTAssertFalse(evaluation.pass)
        XCTAssertEqual(
            evaluation.visibleDurationsMilliseconds.first ?? 0,
            231,
            accuracy: 0.001
        )
    }

    private func makeEvents(
        order: [StartCueKind],
        extraVisibleMilliseconds: Double = 0
    ) -> [SG6AcceptanceProbe.Event] {
        var events: [SG6AcceptanceProbe.Event] = []
        for (index, kind) in order.enumerated() {
            let timestamp = Double(index)
            let cue = StartCuePresentation(
                id: UUID(),
                kind: kind,
                emittedAt: timestamp
            )
            append(.startCueEmitted(cue), timestamp: timestamp, to: &events)
            append(
                .startCueVisible(cue.id, cue.kind),
                timestamp: timestamp + 0.010,
                to: &events
            )
            append(.startCueHapticFanout(cue.id), timestamp: timestamp + 0.011, to: &events)
            let extra = index == 0 ? extraVisibleMilliseconds / 1_000 : 0
            append(
                .startCueHidden(cue.id, cue.kind),
                timestamp: timestamp + 0.010 + cue.visibleDuration + extra,
                to: &events
            )
        }
        return events
    }

    private func append(
        _ kind: SG6AcceptanceProbe.EventKind,
        timestamp: TimeInterval,
        to events: inout [SG6AcceptanceProbe.Event]
    ) {
        events.append(
            SG6AcceptanceProbe.Event(
                sequence: events.count + 1,
                kind: kind,
                timestamp: timestamp
            )
        )
    }
}
