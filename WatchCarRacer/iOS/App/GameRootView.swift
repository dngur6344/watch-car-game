import SwiftUI

struct GameRootView: View {
    private enum PresentationAccessibilityFocus: Hashable {
        case countdown
        case result
    }

    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @Environment(\.accessibilityReduceTransparency) private var accessibilityReduceTransparency
#if DEBUG
    @Environment(\.sg8AccessibilityAcceptanceOverride)
    private var accessibilityAcceptanceOverride
#endif
    @AccessibilityFocusState private var presentationFocus: PresentationAccessibilityFocus?

    let gameSession: GameSessionController
    let watchSession: PhoneWatchSession
    let sensorySettings: SensorySettingsController
    let environment: RacingEnvironmentSelection
    let onRetry: () -> Void
    let onMainHub: () -> Void

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                RacingWorldView(
                    snapshot: gameSession.renderSnapshot,
                    steering: gameSession.steeringSnapshot.value,
                    lastEvent: gameSession.lastEvent,
                    feedback: gameSession.nearMissFeedbackPresentation,
                    appearance: gameSession.appearance,
                    configuration: gameSession.scene.configuration,
                    environment: environment,
                    qualityTier: gameSession.environmentQualityTier,
                    accessibilityPolicy: sceneAccessibilityPolicy
                )
                .ignoresSafeArea()

                VStack(spacing: 0) {
                    hud
                    Spacer(minLength: 12)
                    touchSurface(height: min(max(proxy.size.height * 0.30, 92), 132))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)

                switch gameSession.presentationPhase {
                case let .countdown(value):
                    countdownOverlay(value: value)
                        .transition(
                            effectiveReduceMotion
                                ? .opacity
                                : .scale(scale: 0.90).combined(with: .opacity)
                        )
                case .racing:
                    Color.clear
                        .frame(width: 1, height: 1)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
#if DEBUG
                        .onAppear {
                            SG6AcceptanceProbe.recordRacingRendered()
                        }
#endif
                case .collision:
                    collisionOverlay
                case let .result(result):
                    resultOverlay(result)
                        .transition(
                            effectiveReduceMotion
                                ? .opacity
                                : .scale(scale: 0.90).combined(with: .opacity)
                        )
                }

                if let cue = gameSession.startCuePresentation, cue.kind == .go {
                    GoStartCueView(
                        cue: cue,
                        opacity: cue.opacity(
                            for: sensorySettings.settings.effectIntensity
                        ),
                        reduceMotion: effectiveReduceMotion,
                        onCueVisible: gameSession.startCueDidBecomeVisible
                    )
                    .id(cue.id)
                    .allowsHitTesting(false)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Go")
                    .accessibilityIdentifier("game.startCue.go")
                }

                if let fallbackBannerText = gameSession.fallbackBannerText {
                    VStack {
                        Text(fallbackBannerText)
                            .font(.system(size: 9, weight: .bold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.88))
                            .padding(.vertical, 4)
                            .padding(.horizontal, 8)
                            .background(.black.opacity(0.68), in: Capsule())
                            .accessibilityIdentifier("game.inputFallback")
                        Spacer()
                    }
                    .padding(.top, 66)
                    .allowsHitTesting(false)
                }
            }
            .animation(
                effectiveReduceMotion ? nil : .easeOut(duration: 0.20),
                value: gameSession.presentationPhase
            )
        }
        .onChange(of: sceneAccessibilityPolicy, initial: true) { _, policy in
            gameSession.scene.setAccessibilityPolicy(policy)
#if DEBUG
            SG6AcceptanceProbe.recordAccessibilityPolicyApplied(policy)
#endif
        }
        .onChange(of: gameSession.presentationPhase, initial: true) { _, phase in
            switch phase {
            case .countdown:
                presentationFocus = .countdown
            case .racing:
                presentationFocus = nil
            case .collision:
                presentationFocus = nil
            case .result:
                presentationFocus = .result
            }
        }
        .background(Color(red: 0.025, green: 0.035, blue: 0.065))
        .preferredColorScheme(.dark)
        .onAppear {
            gameSession.startGameLoop()
        }
        .onDisappear {
            gameSession.stopGameLoop()
        }
    }

    private var sceneAccessibilityPolicy: SensoryAccessibilityPolicy {
        SensoryAccessibilityPolicy(
            settings: sensorySettings.settings,
            reduceMotion: effectiveReduceMotion,
            reduceTransparency: effectiveReduceTransparency
        )
    }

    private var effectiveReduceMotion: Bool {
#if DEBUG
        accessibilityAcceptanceOverride.reduceMotion ?? accessibilityReduceMotion
#else
        accessibilityReduceMotion
#endif
    }

    private var effectiveReduceTransparency: Bool {
#if DEBUG
        accessibilityAcceptanceOverride.reduceTransparency ?? accessibilityReduceTransparency
#else
        accessibilityReduceTransparency
#endif
    }

    private var hud: some View {
        ZStack(alignment: .top) {
            HStack(alignment: .top, spacing: 12) {
                hudMetric(
                    title: primaryMetricTitle,
                    value: primaryMetricValue,
                    unit: nil,
                    systemImage: "flag.checkered"
                )
                .accessibilityIdentifier("game.score")

                Spacer(minLength: 120)

                HStack(alignment: .top, spacing: 7) {
                    hudMetric(
                        title: "SPEED",
                        value: String(gameSession.speed),
                        unit: "KM/H",
                        systemImage: "speedometer"
                    )
                    .accessibilityIdentifier("game.speed")

                    boosterStatus
                }
            }

            VStack(spacing: 3) {
                raceStatusChip

#if DEBUG
                compactDiagnostics
#endif
            }
        }
        .frame(height: 50)
    }

    private var primaryMetricTitle: String {
        gameSession.renderSnapshot.gameMode == .cpuSprint ? "POSITION" : "SCORE"
    }

    private var primaryMetricValue: String {
        let snapshot = gameSession.renderSnapshot
        guard snapshot.gameMode == .cpuSprint else {
            return String(gameSession.score)
        }
        return "\(snapshot.playerPlace ?? 1)/\(snapshot.fieldSize)"
    }

    private var boosterStatus: some View {
        let booster = gameSession.renderSnapshot.booster
        let configuration = gameSession.scene.configuration
        let progress: Double
        let color: Color
        let status: String
        if booster.isActive {
            let duration = max(configuration.boosterActiveDuration, 0.001)
            progress = min(max(booster.remainingDuration / duration, 0), 1)
            color = .orange
            status = booster.remainingDuration.formatted(
                .number.precision(.fractionLength(1))
            )
        } else {
            progress = min(max(booster.chargeProgress, 0), 1)
            color = .mint
            status = "\(Int((progress * 100).rounded()))%"
        }

        return VStack(spacing: 1) {
            ZStack {
                Circle()
                    .stroke(.white.opacity(0.14), lineWidth: 3)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(color, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Image(systemName: "bolt.fill")
                    .font(.system(size: 11, weight: .black))
                    .foregroundStyle(booster.isActive ? .orange : .white.opacity(0.86))
            }
            .frame(width: 27, height: 27)

            Text(booster.isActive ? "BOOST \(status)" : status)
                .font(.system(size: 6.5, weight: .bold, design: .monospaced))
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 6)
        .frame(width: 58, height: 50)
        .background(.black.opacity(0.46), in: RoundedRectangle(cornerRadius: 9))
        .overlay {
            RoundedRectangle(cornerRadius: 9)
                .stroke(color.opacity(booster.isActive ? 0.62 : 0.18), lineWidth: 0.8)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Automatic booster")
        .accessibilityValue(
            booster.isActive
                ? "Active, \(status) seconds remaining"
                : "Charging, \(status)"
        )
        .accessibilityIdentifier("game.booster")
    }

    private func hudMetric(
        title: String,
        value: String,
        unit: String?,
        systemImage: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 8, weight: .bold, design: .rounded))
                .tracking(0.7)
                .foregroundStyle(.white.opacity(0.58))
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(.system(size: 23, weight: .black, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.74)
                    .foregroundStyle(.white)
                if let unit {
                    Text(unit)
                        .font(.system(size: 8, weight: .bold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.62))
                }
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 9)
        .frame(minWidth: 88, alignment: .leading)
        .background(.black.opacity(0.46), in: RoundedRectangle(cornerRadius: 9))
        .overlay {
            RoundedRectangle(cornerRadius: 9)
                .stroke(.white.opacity(0.10), lineWidth: 0.5)
        }
        .accessibilityElement(children: .combine)
    }

    private var raceStatusChip: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(gameSession.presentationPhase == .racing ? .mint : .orange)
                .frame(width: 5, height: 5)
            Text(presentationStatus)
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.90))
                .accessibilityIdentifier("game.phase")
            Rectangle()
                .fill(.white.opacity(0.18))
                .frame(width: 1, height: 9)
            Image(systemName: watchSession.isFallback ? "hand.draw" : "applewatch")
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(.white.opacity(0.62))
            Text(gameSession.inputSourceDescription.uppercased())
                .font(.system(size: 8, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.68))
                .accessibilityIdentifier("game.inputSource")
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 8)
        .background(.black.opacity(0.42), in: Capsule())
        .overlay {
            Capsule().stroke(.white.opacity(0.10), lineWidth: 0.5)
        }
    }

    private func touchSurface(height: CGFloat) -> some View {
        GeometryReader { touchProxy in
            ZStack(alignment: .bottom) {
                Color.clear

                Label("DRAG TO STEER", systemImage: "arrow.left.and.right")
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.66))
                    .padding(.vertical, 4)
                    .padding(.horizontal, 7)
                    .background(.black.opacity(0.34), in: Capsule())
                    .padding(.bottom, 4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .allowsHitTesting(false)
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
        .opacity(gameSession.acceptsTouchInput ? 1 : 0.48)
        .allowsHitTesting(gameSession.acceptsTouchInput)
    }

    private func countdownOverlay(value: Int) -> some View {
        VStack(spacing: 6) {
            Text("GET READY")
                .font(.caption.bold())
                .foregroundStyle(.white.opacity(0.76))
            CountdownNumberView(
                value: value,
                cue: activeCountdownCue(for: value),
                accentOpacity: sensorySettings.settings.effectIntensity == .balanced ? 1 : 0.55,
                reduceMotion: effectiveReduceMotion,
                onCueVisible: gameSession.startCueDidBecomeVisible
            )
            .id(value)
        }
        .padding(.vertical, 20)
        .padding(.horizontal, 42)
        .background(.black.opacity(0.76), in: RoundedRectangle(cornerRadius: 22))
        .overlay {
            RoundedRectangle(cornerRadius: 22)
                .stroke(.white.opacity(0.32), lineWidth: 1)
        }
        .allowsHitTesting(false)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Race countdown")
        .accessibilityValue(String(value))
        .accessibilityAddTraits(.isHeader)
        .accessibilityIdentifier("game.countdown")
        .accessibilityFocused($presentationFocus, equals: .countdown)
    }

    private func activeCountdownCue(for value: Int) -> StartCuePresentation? {
        guard let cue = gameSession.startCuePresentation,
              cue.kind.countdownValue == value else {
            return nil
        }
        return cue
    }

    private var collisionOverlay: some View {
        Text("IMPACT")
            .font(.system(size: 24, weight: .black, design: .rounded))
            .tracking(4)
            .foregroundStyle(.white)
            .padding(.vertical, 9)
            .padding(.horizontal, 18)
            .background(.black.opacity(0.58), in: Capsule())
            .transition(effectiveReduceMotion ? .opacity : .scale.combined(with: .opacity))
            .allowsHitTesting(false)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Impact")
            .accessibilityIdentifier("game.collision")
#if DEBUG
            .onAppear {
                SG6AcceptanceProbe.recordCollisionRendered()
            }
#endif
    }

    private func resultOverlay(_ result: RunResult) -> some View {
        let isSprint = gameSession.renderSnapshot.gameMode == .cpuSprint
        return VStack(spacing: 12) {
            Text(isSprint ? sprintResultTitle : "CRASHED")
                .font(.system(size: 34, weight: .black, design: .rounded))
                .foregroundStyle(.white)
                .accessibilityAddTraits(.isHeader)
                .accessibilityFocused($presentationFocus, equals: .result)

            if !isSprint, result.isNewBest {
                Label("NEW LOCAL BEST", systemImage: "trophy.fill")
                    .font(.caption.bold())
                    .foregroundStyle(.yellow)
                    .accessibilityIdentifier("game.newBest")
            }

            HStack(spacing: 24) {
                if isSprint {
                    resultMetric(
                        title: "POSITION",
                        value: "\(gameSession.renderSnapshot.playerPlace ?? 1) / "
                            + "\(gameSession.renderSnapshot.fieldSize)"
                    )
                    resultMetric(
                        title: "TIME",
                        value: gameSession.renderSnapshot.elapsedTime.formatted(
                            .number.precision(.fractionLength(2))
                        ) + "s"
                    )
                } else {
                    resultMetric(title: "FINAL SCORE", value: String(result.score))
                    resultMetric(title: "LOCAL BEST", value: String(result.localBest))
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Run result")
            .accessibilityValue(resultAccessibilityValue(result))
            .accessibilityIdentifier("game.resultSummary")

            HStack(spacing: 10) {
                Button("RETRY") {
                    onRetry()
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .tint(.orange)
                .font(.headline.bold())
                .controlSize(.large)
                .accessibilityIdentifier("game.retry")

                Button("MAIN HUB") {
                    onMainHub()
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
                .tint(.white)
                .font(.headline.bold())
                .controlSize(.large)
                .accessibilityIdentifier("game.mainHub")
            }
        }
        .padding(.vertical, 24)
        .padding(.horizontal, 40)
        .background(.black.opacity(0.84), in: RoundedRectangle(cornerRadius: 20))
        .overlay {
            RoundedRectangle(cornerRadius: 20)
                .stroke(.orange.opacity(0.8), lineWidth: 2)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("game.result")
#if DEBUG
        .onAppear {
            SG6AcceptanceProbe.recordResultRendered()
        }
#endif
    }

    private var sprintResultTitle: String {
        gameSession.renderSnapshot.playerPlace == 1 ? "VICTORY" : "RACE COMPLETE"
    }

    private func resultMetric(title: String, value: String) -> some View {
        VStack(spacing: 2) {
            Text(title)
                .font(.caption2.bold())
                .foregroundStyle(.white.opacity(0.62))
            Text(value)
                .font(.title3.monospacedDigit().bold())
                .foregroundStyle(.white)
        }
    }

    private func resultAccessibilityValue(_ result: RunResult) -> String {
        if gameSession.renderSnapshot.gameMode == .cpuSprint {
            return "Position \(gameSession.renderSnapshot.playerPlace ?? 1) of "
                + "\(gameSession.renderSnapshot.fieldSize), time "
                + gameSession.renderSnapshot.elapsedTime.formatted(
                    .number.precision(.fractionLength(2))
                ) + " seconds"
        }
        let newBest = result.isNewBest ? ", new local best" : ""
        return "Final score \(result.score), local best \(result.localBest)\(newBest)"
    }

    private var presentationStatus: String {
        switch gameSession.presentationPhase {
        case .countdown:
            return "COUNTDOWN"
        case .racing:
            return "RACING"
        case .collision:
            return "IMPACT"
        case .result:
            return "RESULT"
        }
    }

#if DEBUG
    private var compactDiagnostics: some View {
        HStack(spacing: 4) {
            Text("FPS \(formattedFrameRate(gameSession.framesPerSecond))")
            Circle()
                .fill(watchSession.isFallback ? .orange : .mint)
                .frame(width: 3, height: 3)
            Text(watchSession.isFallback ? "WATCH —" : "WATCH LIVE")
        }
        .font(.system(size: 7, weight: .medium, design: .monospaced))
        .foregroundStyle(.white.opacity(0.52))
        .padding(.vertical, 2)
        .padding(.horizontal, 6)
        .background(.black.opacity(0.28), in: Capsule())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Debug diagnostics")
        .accessibilityValue(
            "\(frameRateDescription), \(watchSession.sourceDescription), "
                + "steering \(watchSession.receivedSteering.formatted(.number.precision(.fractionLength(3))))"
        )
        .accessibilityIdentifier("game.frameRate")
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

private struct CountdownNumberView: View {
    let value: Int
    let cue: StartCuePresentation?
    let accentOpacity: Double
    let reduceMotion: Bool
    let onCueVisible: (UUID) -> Void

    @State private var scale: CGFloat = 0.78
    @State private var ringOpacity = 1.0

    var body: some View {
        ZStack {
            if let cue,
               case let .ring(accentColor) = cue.visualTreatment {
                Circle()
                    .stroke(accentColor.color, lineWidth: 5)
                    .frame(width: 100, height: 100)
                    .scaleEffect(reduceMotion ? 1 : scale)
                    .opacity(ringOpacity * accentOpacity)
                    .accessibilityHidden(true)
                    .onAppear {
                        onCueVisible(cue.id)
#if DEBUG
                        SG6AcceptanceProbe.recordStartCueVisible(cue)
#endif
                    }
#if DEBUG
                    .onDisappear {
                        SG6AcceptanceProbe.recordStartCueHidden(cue)
                    }
#endif
            }

            Text(value, format: .number)
                .font(.system(size: 72, weight: .black, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)
        }
        .frame(width: 108, height: 108)
        .onAppear {
#if DEBUG
            SG6AcceptanceProbe.recordCountdownRendered(value)
#endif
            guard !reduceMotion else { return }
            withAnimation(.easeOut(duration: cue?.visibleDuration ?? 0.18)) {
                scale = 1.12
                ringOpacity = 0.30
            }
        }
    }
}

private struct GoStartCueView: View {
    let cue: StartCuePresentation
    let opacity: Double
    let reduceMotion: Bool
    let onCueVisible: (UUID) -> Void

    @State private var sweepProgress: CGFloat = -1
    @State private var textScale: CGFloat = 0.88

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color.white.opacity(0.12 * opacity)

                if !reduceMotion {
                    LinearGradient(
                        colors: [
                            .clear,
                            StartCueAccentColor.mintWhite.color.opacity(0.88 * opacity),
                            .white.opacity(0.92 * opacity),
                            .clear,
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: proxy.size.width * 0.42)
                    .offset(x: sweepProgress * proxy.size.width)
                }

                Text("GO")
                    .font(.system(size: 86, weight: .black, design: .rounded))
                    .tracking(4)
                    .foregroundStyle(.white)
                    .shadow(color: .mint.opacity(0.85 * opacity), radius: 14)
                    .scaleEffect(reduceMotion ? 1 : textScale)
            }
            .opacity(opacity)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeOut(duration: cue.visibleDuration)) {
                    sweepProgress = 1
                    textScale = 1.08
                }
            }
        }
        .ignoresSafeArea()
        .onAppear {
            onCueVisible(cue.id)
#if DEBUG
            SG6AcceptanceProbe.recordStartCueVisible(cue)
#endif
        }
#if DEBUG
        .onDisappear {
            SG6AcceptanceProbe.recordStartCueHidden(cue)
        }
#endif
    }
}

private extension StartCueAccentColor {
    var color: Color {
        switch self {
        case .cyan:
            .cyan
        case .mint:
            .mint
        case .orange:
            .orange
        case .mintWhite:
            Color(red: 0.72, green: 1, blue: 0.92)
        }
    }
}
