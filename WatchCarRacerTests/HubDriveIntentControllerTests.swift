import XCTest
@testable import WatchCarRacer

@MainActor
final class HubDriveIntentControllerTests: XCTestCase {
    func testReadyRequestStartsAdaptiveExactlyOnce() {
        var routes: [SessionControlRoute] = []
        let controller = HubDriveIntentController { route in
            routes.append(route)
            return true
        }

        controller.requestDrive(readiness: .ready)
        controller.requestDrive(readiness: .ready)

        XCTAssertEqual(routes, [.adaptiveWatchPreferred])
        XCTAssertTrue(controller.hasStartedDrive)
        XCTAssertFalse(controller.hasPendingDriveIntent)
        XCTAssertFalse(controller.isReadinessSheetPresented)
        XCTAssertEqual(controller.driveTransitionTrigger, 1)
    }

    func testNotReadyRequestOnlyPresentsPendingSheet() {
        var routes: [SessionControlRoute] = []
        let controller = HubDriveIntentController { route in
            routes.append(route)
            return true
        }

        controller.requestDrive(readiness: .awaitingPacket)
        controller.requestDrive(readiness: .disconnected)

        XCTAssertTrue(routes.isEmpty)
        XCTAssertTrue(controller.hasPendingDriveIntent)
        XCTAssertTrue(controller.isReadinessSheetPresented)
        XCTAssertFalse(controller.hasStartedDrive)
        XCTAssertEqual(controller.driveTransitionTrigger, 0)
    }

    func testCancelAndInteractiveDismissShareIdempotentCancellationContract() {
        var routes: [SessionControlRoute] = []
        let controller = HubDriveIntentController { route in
            routes.append(route)
            return true
        }

        controller.requestDrive(readiness: .stale)
        controller.cancelPendingDrive()
        controller.continueWithTouch()

        XCTAssertTrue(routes.isEmpty)
        XCTAssertFalse(controller.hasPendingDriveIntent)
        XCTAssertFalse(controller.isReadinessSheetPresented)
        XCTAssertEqual(controller.driveTransitionTrigger, 0)

        controller.requestDrive(readiness: .needsCalibration)
        controller.readinessSheetDidDismiss()
        controller.continueWithTouch()

        XCTAssertTrue(routes.isEmpty)
        XCTAssertFalse(controller.hasPendingDriveIntent)
        XCTAssertFalse(controller.isReadinessSheetPresented)
        XCTAssertEqual(controller.driveTransitionTrigger, 0)
    }

    func testContinueWithTouchConsumesPendingIntentExactlyOnce() {
        var routes: [SessionControlRoute] = []
        let controller = HubDriveIntentController { route in
            routes.append(route)
            return true
        }

        controller.requestDrive(readiness: .motionUnavailable)
        controller.continueWithTouch()
        controller.continueWithTouch()
        controller.readinessSheetDidDismiss()
        controller.continueWithTouch()

        XCTAssertEqual(routes, [.touchOnly])
        XCTAssertTrue(controller.hasStartedDrive)
        XCTAssertFalse(controller.hasPendingDriveIntent)
        XCTAssertFalse(controller.isReadinessSheetPresented)
        XCTAssertEqual(controller.driveTransitionTrigger, 1)
    }

    func testFailedStartCanBeRetriedWithoutDuplicatingAnAcceptedStart() {
        var results = [false, true]
        var routes: [SessionControlRoute] = []
        let controller = HubDriveIntentController { route in
            routes.append(route)
            return results.removeFirst()
        }

        controller.requestDrive(readiness: .ready)
        controller.requestDrive(readiness: .ready)
        controller.requestDrive(readiness: .ready)

        XCTAssertEqual(routes, [.adaptiveWatchPreferred, .adaptiveWatchPreferred])
        XCTAssertTrue(controller.hasStartedDrive)
        XCTAssertEqual(controller.driveTransitionTrigger, 1)
    }

    func testPresentationUnavailableRejectsDriveWithoutTransitionFeedback() {
        var routes: [SessionControlRoute] = []
        let controller = HubDriveIntentController { route in
            routes.append(route)
            return true
        }

        controller.requestDrive(readiness: .ready, presentationIsReady: false)

        XCTAssertTrue(routes.isEmpty)
        XCTAssertFalse(controller.hasStartedDrive)
        XCTAssertFalse(controller.hasPendingDriveIntent)
        XCTAssertFalse(controller.isReadinessSheetPresented)
        XCTAssertEqual(controller.driveTransitionTrigger, 0)
    }

    func testMaintenanceDataAndPendingAccessibilitySeamsAreExact() {
        XCTAssertEqual(VehicleMaintenanceView.vehicleOptions.count, 4)
        XCTAssertEqual(VehicleMaintenanceView.colorOptions.count, 8)
        XCTAssertEqual(
            VehicleMaintenanceView.vehicleOptions.map(\.id),
            VehicleID.allCases
        )
        XCTAssertEqual(
            VehicleMaintenanceView.colorOptions.map(\.id),
            VehicleColorID.allCases
        )
        XCTAssertEqual(VehicleCatalog.allSelections.count, 32)
        XCTAssertEqual(VehicleMaintenanceView.pendingText, "Pending until Drive")
        XCTAssertTrue(
            VehicleMaintenanceView.pendingAccessibilityValue.contains("not been saved")
        )
    }
}
