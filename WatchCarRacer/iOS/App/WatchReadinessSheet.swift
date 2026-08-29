import SwiftUI

struct WatchReadinessSheet: View {
    let status: WatchReadinessStatus
    let onCancel: () -> Void
    let onContinueWithTouch: () -> Void

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.018, green: 0.034, blue: 0.065),
                    Color(red: 0.035, green: 0.12, blue: 0.15),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 18) {
                    Image(systemName: status.symbolName)
                        .font(.system(size: 38, weight: .semibold))
                        .foregroundStyle(status.isReady ? .mint : .orange)
                        .frame(width: 64, height: 64)
                        .background(
                            (status.isReady ? Color.mint : Color.orange).opacity(0.14),
                            in: Circle()
                        )
                        .accessibilityHidden(true)

                    VStack(spacing: 7) {
                        Text("APPLE WATCH STEERING")
                            .font(.caption.bold())
                            .tracking(1.3)
                            .foregroundStyle(.mint)
                        Text(status.displayTitle)
                            .font(.system(.title2, design: .rounded, weight: .black))
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.center)
                        Text(status.guidance)
                            .font(.body)
                            .foregroundStyle(.white.opacity(0.78))
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityLabel("Apple Watch status")
                    .accessibilityValue(status.accessibilityValue)
                    .accessibilityIdentifier("watchReadiness.status")

                    Label(
                        "Calibration is available only in the Watch app.",
                        systemImage: "applewatch.side.right"
                    )
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.86))
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .premiumPanel(reduceTransparency: reduceTransparency)
                    .accessibilityIdentifier("watchReadiness.calibrationGuidance")

                    VStack(spacing: 10) {
                        Button {
                            onContinueWithTouch()
                        } label: {
                            Label("CONTINUE WITH TOUCH", systemImage: "hand.tap.fill")
                                .font(.headline.bold())
                                .frame(maxWidth: .infinity, minHeight: 52)
                        }
                        .buttonStyle(.borderedProminent)
                        .buttonBorderShape(.capsule)
                        .tint(.mint)
                        .foregroundStyle(.black)
                        .accessibilityHint("Save the pending vehicle and start a touch-only drive")
                        .accessibilityIdentifier("watchReadiness.continueTouch")

                        Button("CANCEL") {
                            onCancel()
                        }
                        .font(.headline.bold())
                        .buttonStyle(.bordered)
                        .buttonBorderShape(.capsule)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .accessibilityHint("Close without saving or starting a drive")
                        .accessibilityIdentifier("watchReadiness.cancel")
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 20)
                .frame(maxWidth: 520)
                .frame(maxWidth: .infinity)
            }
        }
        .preferredColorScheme(.dark)
        .presentationDragIndicator(.visible)
    }
}

extension WatchReadinessStatus {
    var displayTitle: String {
        switch self {
        case .activating:
            "CONNECTING"
        case .disconnected:
            "WATCH DISCONNECTED"
        case .awaitingPacket:
            "OPEN WATCH APP"
        case .needsCalibration:
            "CALIBRATION NEEDED"
        case .motionUnavailable:
            "MOTION UNAVAILABLE"
        case .stale:
            "SIGNAL INTERRUPTED"
        case .ready:
            "WATCH READY"
        }
    }

    var symbolName: String {
        switch self {
        case .activating:
            "applewatch.radiowaves.left.and.right"
        case .disconnected:
            "applewatch.slash"
        case .awaitingPacket:
            "applewatch"
        case .needsCalibration:
            "gyroscope"
        case .motionUnavailable:
            "exclamationmark.arrow.trianglehead.2.clockwise.rotate.90"
        case .stale:
            "waveform.slash"
        case .ready:
            "applewatch.radiowaves.left.and.right"
        }
    }

    var accessibilityValue: String {
        "\(displayTitle). \(guidance)"
    }
}
