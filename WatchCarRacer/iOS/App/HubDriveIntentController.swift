import Observation

@MainActor
@Observable
final class HubDriveIntentController {
    typealias DriveStarter = @MainActor (SessionControlRoute) -> Bool

    private(set) var isReadinessSheetPresented = false
    private(set) var hasPendingDriveIntent = false
    private(set) var hasStartedDrive = false
    private(set) var driveTransitionTrigger = 0

    @ObservationIgnored private let startDrive: DriveStarter

    init(startDrive: @escaping DriveStarter) {
        self.startDrive = startDrive
    }

    var canRequestDrive: Bool {
        !hasPendingDriveIntent && !hasStartedDrive
    }

    func beginHubVisit() {
        guard !hasPendingDriveIntent else { return }
        hasStartedDrive = false
    }

    func requestDrive(
        readiness: WatchReadinessStatus,
        presentationIsReady: Bool = true
    ) {
        guard canRequestDrive, presentationIsReady else { return }

        if readiness.isReady {
            completeDrive(using: .adaptiveWatchPreferred)
        } else {
            hasPendingDriveIntent = true
            isReadinessSheetPresented = true
        }
    }

    func cancelPendingDrive() {
        hasPendingDriveIntent = false
        isReadinessSheetPresented = false
    }

    func readinessSheetDidDismiss() {
        cancelPendingDrive()
    }

    func continueWithTouch() {
        guard hasPendingDriveIntent else { return }

        hasPendingDriveIntent = false
        isReadinessSheetPresented = false
        completeDrive(using: .touchOnly)
    }

    private func completeDrive(using route: SessionControlRoute) {
        hasStartedDrive = startDrive(route)
        if hasStartedDrive {
            driveTransitionTrigger &+= 1
        }
    }
}
