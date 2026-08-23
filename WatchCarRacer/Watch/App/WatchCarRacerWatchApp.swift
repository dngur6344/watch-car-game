import SwiftUI

@main
struct WatchCarRacerWatchApp: App {
    @State private var controller = WatchControllerSession.shared

    var body: some Scene {
        WindowGroup {
            SteeringControlView(controller: controller)
        }
    }
}
