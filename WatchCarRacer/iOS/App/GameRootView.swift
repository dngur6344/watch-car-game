import SpriteKit
import SwiftUI

struct GameRootView: View {
    let gameSession: GameSessionController
    let watchSession: PhoneWatchSession

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                SpriteView(
                    scene: gameSession.scene,
                    preferredFramesPerSecond: 60,
                    options: [.ignoresSiblingOrder]
                )
                .ignoresSafeArea()

                VStack(spacing: 0) {
                    hud
                    Spacer(minLength: 12)
                    touchSurface(height: min(max(proxy.size.height * 0.30, 92), 132))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)

                if gameSession.phase == .crashed {
                    crashOverlay
                        .transition(.scale(scale: 0.90).combined(with: .opacity))
                }

                if let fallbackBannerText = gameSession.fallbackBannerText {
                    VStack {
                        Text(fallbackBannerText)
                            .font(.caption2.bold())
                            .foregroundStyle(.white.opacity(0.88))
                            .padding(.vertical, 6)
                            .padding(.horizontal, 11)
                            .background(.black.opacity(0.68), in: Capsule())
                            .accessibilityIdentifier("game.inputFallback")
                        Spacer()
                    }
                    .padding(.top, 110)
                    .allowsHitTesting(false)
                }
            }
            .animation(.easeOut(duration: 0.20), value: gameSession.phase)
        }
        .background(Color(red: 0.025, green: 0.035, blue: 0.065))
        .preferredColorScheme(.dark)
    }

    private var hud: some View {
        HStack(alignment: .top, spacing: 12) {
            hudCard(title: "SCORE", value: String(gameSession.score))
                .accessibilityIdentifier("game.score")

            Spacer(minLength: 8)

#if DEBUG
            diagnostics
#endif

            hudCard(title: "SPEED", value: "\(gameSession.speed) km/h")

            VStack(alignment: .trailing, spacing: 3) {
                Text(gameSession.phase == .running ? "RUNNING" : "CRASHED")
                    .font(.caption.bold())
                    .foregroundStyle(gameSession.phase == .running ? .mint : .orange)
                    .accessibilityIdentifier("game.phase")
                Text("INPUT · \(gameSession.inputSourceDescription)")
                    .font(.caption2.monospaced())
                    .foregroundStyle(.white.opacity(0.72))
                    .accessibilityIdentifier("game.inputSource")
            }
            .padding(.vertical, 9)
            .padding(.horizontal, 11)
            .background(.black.opacity(0.56), in: RoundedRectangle(cornerRadius: 10))
        }
    }

    private func hudCard(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
                .font(.caption2.bold())
                .foregroundStyle(.white.opacity(0.62))
            Text(value)
                .font(.headline.monospacedDigit().bold())
                .foregroundStyle(.white)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 11)
        .background(.black.opacity(0.56), in: RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .combine)
    }

    private func touchSurface(height: CGFloat) -> some View {
        GeometryReader { touchProxy in
            ZStack(alignment: .top) {
                RoundedRectangle(cornerRadius: 14)
                    .fill(.white.opacity(0.055))
                RoundedRectangle(cornerRadius: 14)
                    .stroke(.white.opacity(0.18), lineWidth: 1)

                Label("DRAG LEFT / RIGHT · RELEASE TO CENTER", systemImage: "arrow.left.and.right")
                    .font(.caption2.bold())
                    .foregroundStyle(.white.opacity(0.70))
                    .padding(.top, 10)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .local)
                    .onChanged { value in
                        gameSession.updateTouch(
                            horizontalPosition: value.location.x,
                            width: touchProxy.size.width
                        )
                    }
                    .onEnded { _ in
                        gameSession.releaseTouch()
                    }
            )
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Touch steering surface")
            .accessibilityHint("Drag horizontally to steer and release to return to center")
            .accessibilityIdentifier("game.touchSurface")
            .accessibilityAddTraits(.allowsDirectInteraction)
        }
        .frame(height: height)
        .allowsHitTesting(gameSession.phase == .running)
    }

    private var crashOverlay: some View {
        VStack(spacing: 12) {
            Text("CRASHED")
                .font(.system(size: 34, weight: .black, design: .rounded))
                .foregroundStyle(.white)
            Text("Score \(gameSession.score)")
                .font(.headline.monospacedDigit())
                .foregroundStyle(.white.opacity(0.82))
            Button("RETRY") {
                gameSession.retry()
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .tint(.orange)
            .font(.headline.bold())
            .controlSize(.large)
            .accessibilityIdentifier("game.retry")
        }
        .padding(.vertical, 24)
        .padding(.horizontal, 40)
        .background(.black.opacity(0.84), in: RoundedRectangle(cornerRadius: 20))
        .overlay {
            RoundedRectangle(cornerRadius: 20)
                .stroke(.orange.opacity(0.8), lineWidth: 2)
        }
    }

#if DEBUG
    private var diagnostics: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 5) {
                Text("WATCH DIAGNOSTICS")
                    .font(.caption2.bold())
                Spacer(minLength: 4)
                Text(watchSession.sourceDescription)
                    .foregroundStyle(watchSession.isFallback ? .orange : .mint)
            }

            steeringTracer

            Text(
                "\(watchSession.packetStateDescription) · \(watchSession.activationDescription) · "
                    + "reach \(watchSession.isReachable ? "Y" : "N")"
            )
            Text(
                "age \(formattedMilliseconds(watchSession.packetAgeMilliseconds)) · "
                    + "gap \(watchSession.sequenceGaps) · p95 "
                    + formattedMilliseconds(watchSession.interarrivalP95Milliseconds)
            )
            Text(
                "value \(watchSession.receivedSteering.formatted(.number.precision(.fractionLength(3)))) · "
                    + "decode \(watchSession.decodingFailures)"
            )
            .accessibilityIdentifier("phone.received.value")
            Text(frameRateDescription)
                .accessibilityIdentifier("game.frameRate")
        }
        .font(.system(size: 8, design: .monospaced))
        .foregroundStyle(.white.opacity(0.78))
        .padding(7)
        .frame(maxWidth: 235)
        .background(.black.opacity(0.58), in: RoundedRectangle(cornerRadius: 9))
    }

    private var steeringTracer: some View {
        GeometryReader { proxy in
            let markerTravel = max(0, proxy.size.width - 10)
            ZStack {
                Capsule()
                    .fill(.white.opacity(0.18))
                    .frame(height: 3)
                Rectangle()
                    .fill(.white.opacity(0.30))
                    .frame(width: 1, height: 10)
                Circle()
                    .fill(watchSession.isFallback ? .orange : .mint)
                    .frame(width: 10, height: 10)
                    .offset(x: watchSession.effectiveSteering * markerTravel / 2)
            }
            .frame(maxHeight: .infinity)
        }
        .frame(height: 11)
        .accessibilityIdentifier("phone.steering.value")
    }

    private func formattedMilliseconds(_ value: Double?) -> String {
        guard let value else {
            return "—"
        }
        return "\(value.formatted(.number.precision(.fractionLength(1))))ms"
    }

    private var frameRateDescription: String {
        let current = formattedFrameRate(gameSession.framesPerSecond)
        let average = formattedFrameRate(gameSession.averageFramesPerSecond)
        let minimum = formattedFrameRate(gameSession.minimumFramesPerSecond)
        return "FPS \(current) · avg \(average) · min \(minimum)"
    }

    private func formattedFrameRate(_ value: Double?) -> String {
        guard let value else {
            return "—"
        }
        return value.formatted(.number.precision(.fractionLength(1)))
    }
#endif
}
