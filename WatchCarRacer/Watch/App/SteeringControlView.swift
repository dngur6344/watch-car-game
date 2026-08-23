import SwiftUI

struct SteeringControlView: View {
    @Environment(\.scenePhase) private var scenePhase

    let controller: WatchControllerSession

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
            Image(systemName: "steeringwheel")
                .font(.title)
            Text("Steering Tracer")
                .font(.headline)

                Text("Rest forearm level, Watch face up.")
                    .font(.caption2)
                    .multilineTextAlignment(.center)

                statusRow("Session", controller.activationDescription)
                statusRow("iPhone", controller.isReachable ? "Reachable" : "Unreachable")
                statusRow("Motion", motionDescription)
                statusRow("Calibration", controller.motionEngine.isCalibrated ? "Calibrated" : "Required")

                Button("Calibrate") {
                    controller.calibrateNeutral()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!controller.motionEngine.isMotionAvailable)
                .accessibilityIdentifier("watch.calibrate")

                Text("After inactivity, return to neutral and recalibrate.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

#if DEBUG && targetEnvironment(simulator)
                HStack(spacing: 5) {
                    syntheticButton("L", value: -1, identifier: "watch.synthetic.left")
                    syntheticButton("C", value: 0, identifier: "watch.synthetic.center")
                    syntheticButton("R", value: 1, identifier: "watch.synthetic.right")
                }
                Text("Simulator synthetic input")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
#endif

                if let lastSendError = controller.lastSendError {
                    Text(lastSendError)
                        .font(.caption2)
                        .foregroundStyle(.orange)
                        .lineLimit(2)
                }
            }
            .padding(.horizontal, 4)
        }
        .onChange(of: scenePhase, initial: true) { _, newPhase in
            controller.setAppActive(newPhase == .active)
        }
    }

    private var motionDescription: String {
#if DEBUG && targetEnvironment(simulator)
        if controller.motionEngine.isUsingSyntheticInput {
            return "Synthetic"
        }
#endif
        if !controller.motionEngine.isMotionAvailable {
            return "Unavailable"
        }
        return controller.motionEngine.isRunning ? "Sampling 50 Hz" : "Stopped"
    }

    private func statusRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
        }
        .font(.caption2)
    }

#if DEBUG && targetEnvironment(simulator)
    private func syntheticButton(_ title: String, value: Double, identifier: String) -> some View {
        Button(title) {
            controller.setSyntheticSteering(value)
        }
        .buttonStyle(.bordered)
        .accessibilityIdentifier(identifier)
    }
#endif
}
