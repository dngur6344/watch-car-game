import SwiftUI

struct MainHubView: View {
    let flow: AppFlowController
    let watchSession: PhoneWatchSession
    let presentationAssetLibrary: PresentationAssetLibrary
    let driveIntent: HubDriveIntentController
    let sensorySettings: SensorySettingsController

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var presentationStatus: PresentationLoadStatus = .idle
    @State private var presentationReloadRequest = 0
    @State private var isSensorySettingsPresented = false
    @State private var isEnvironmentPickerPresented = false
    @State private var isGameModePickerPresented = false

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                if let appearance = flow.draftAppearance {
                    VehiclePresentationView(
                        route: .hub,
                        appearance: appearance,
                        assetLibrary: presentationAssetLibrary,
                        reloadRequest: presentationReloadRequest,
                        loadStatus: $presentationStatus
                    )
                }

                LinearGradient(
                    colors: [.black.opacity(0.58), .clear, .black.opacity(0.42)],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .ignoresSafeArea()
                .accessibilityHidden(true)

                ScrollView {
                    hubContent(width: proxy.size.width)
                        .frame(
                            minHeight: max(0, proxy.size.height - 32),
                            alignment: .top
                        )
                        .padding(.horizontal, 20)
                        .padding(.vertical, 16)
                }
                .scrollIndicators(.hidden)
            }
#if DEBUG
            .onAppear {
                SG6AcceptanceProbe.recordHubFirstLayout()
            }
#endif
        }
        .preferredColorScheme(.dark)
        .onAppear {
            driveIntent.beginHubVisit()
        }
        .sheet(
            isPresented: Binding(
                get: { driveIntent.isReadinessSheetPresented },
                set: { isPresented in
                    if !isPresented {
                        driveIntent.cancelPendingDrive()
                    }
                }
            ),
            onDismiss: {
                driveIntent.readinessSheetDidDismiss()
            }
        ) {
            WatchReadinessSheet(
                status: watchSession.readinessStatus,
                onCancel: driveIntent.cancelPendingDrive,
                onContinueWithTouch: driveIntent.continueWithTouch
            )
        }
        .sheet(isPresented: $isSensorySettingsPresented) {
            SensorySettingsView(controller: sensorySettings)
        }
        .sheet(isPresented: $isEnvironmentPickerPresented) {
            RacingEnvironmentPickerView(flow: flow)
        }
        .sheet(isPresented: $isGameModePickerPresented) {
            GameModePickerView(flow: flow)
        }
    }

    @ViewBuilder
    private func hubContent(width: CGFloat) -> some View {
        if dynamicTypeSize.isAccessibilitySize {
            accessibilityHubContent
        } else if width >= 620 {
            HStack(alignment: .top, spacing: 18) {
                overview
                    .frame(maxWidth: 310, alignment: .leading)
                Spacer(minLength: 40)
                actionRail()
                    .frame(maxWidth: 390)
            }
        } else {
            VStack(alignment: .leading, spacing: 16) {
                overview
                actionRail()
            }
        }
    }

    private var accessibilityHubContent: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("NIGHTSHIFT")
                .font(.system(size: 24, weight: .black, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1)
                .accessibilityAddTraits(.isHeader)

            if let appearance = flow.draftAppearance {
                HStack(spacing: 8) {
                    Image(systemName: "car.side.fill")
                        .font(.headline)
                        .foregroundStyle(.mint)
                        .frame(width: 36, height: 36)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(appearance.vehicle.displayName)
                            .font(.headline.bold())
                        Text(appearance.color.displayName)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.78))
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .premiumPanel(reduceTransparency: reduceTransparency)
                .dynamicTypeSize(DynamicTypeSize.xSmall...DynamicTypeSize.large)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Selected vehicle")
                .accessibilityValue(
                    "\(appearance.vehicle.displayName), \(appearance.color.displayName)"
                )
                .accessibilityIdentifier("hub.currentSelection")
            }

            actionRail(compact: true)
                .dynamicTypeSize(DynamicTypeSize.xSmall...DynamicTypeSize.xLarge)
        }
    }

    private var overview: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text("EXPRESSWAY PORTAL")
                    .font(.caption.bold())
                    .tracking(1.6)
                    .foregroundStyle(.mint)
                Text("NIGHTSHIFT")
                    .font(.system(.largeTitle, design: .rounded, weight: .black))
                    .foregroundStyle(.white)
                Text("Road clear. Machine ready.")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.76))
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)

            if let appearance = flow.draftAppearance {
                VStack(alignment: .leading, spacing: 7) {
                    Label("CURRENT MACHINE", systemImage: "car.side.fill")
                        .font(.caption.bold())
                        .foregroundStyle(.mint)
                    Text(appearance.vehicle.displayName)
                        .font(.title3.bold())
                        .foregroundStyle(.white)
                    HStack(spacing: 8) {
                        Circle()
                            .fill(appearance.color.swiftUIColor)
                            .frame(width: 18, height: 18)
                            .overlay {
                                Circle().stroke(.white, lineWidth: 2)
                            }
                            .accessibilityHidden(true)
                        Text(appearance.color.displayName)
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.88))
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .premiumPanel(reduceTransparency: reduceTransparency)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Selected vehicle")
                .accessibilityValue(
                    "\(appearance.vehicle.displayName), \(appearance.color.displayName)"
                )
                .accessibilityIdentifier("hub.currentSelection")
            }
        }
    }

    private func actionRail(compact: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: compact ? 8 : 12) {
            localBestCard(compact: compact)
            watchStatusCard(compact: compact)
            gameModeButton(compact: compact)
            environmentButton(compact: compact)

            Button {
                flow.enterMaintenance()
            } label: {
                Label("VEHICLE MAINTENANCE", systemImage: "wrench.and.screwdriver.fill")
                    .font(compact ? .subheadline.bold() : .headline.bold())
                    .frame(maxWidth: .infinity, minHeight: compact ? 44 : 50)
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.capsule)
            .accessibilityHint("Edit vehicle appearance. Changes remain pending until Drive.")
            .accessibilityIdentifier("hub.maintenance")

            Button {
                isSensorySettingsPresented = true
            } label: {
                Label("SENSORY SETTINGS", systemImage: "slider.horizontal.3")
                    .font(compact ? .subheadline.bold() : .headline.bold())
                    .frame(maxWidth: .infinity, minHeight: compact ? 44 : 50)
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.capsule)
            .accessibilityLabel("Sensory settings")
            .accessibilityValue(sensorySettingsAccessibilityValue)
            .accessibilityHint("Adjust sound effects, haptics, and visual effect intensity.")
            .accessibilityIdentifier("hub.sensorySettings")

            assetStatus

            Button {
                driveIntent.requestDrive(
                    readiness: watchSession.readinessStatus,
                    presentationIsReady: presentationStatus == .ready
                )
            } label: {
                Label("DRIVE", systemImage: "steeringwheel")
                    .font(compact ? .headline.bold() : .title3.bold())
                    .frame(maxWidth: .infinity, minHeight: compact ? 44 : 52)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .tint(.mint)
            .foregroundStyle(.black)
            .disabled(!canAttemptDrive)
            .accessibilityHint(driveAccessibilityHint)
            .accessibilityIdentifier("hub.drive")
        }
        .padding(compact ? 10 : 16)
        .premiumPanel(reduceTransparency: reduceTransparency)
    }

    private func localBestCard(compact: Bool) -> some View {
        HStack(spacing: compact ? 8 : 12) {
            Image(systemName: "trophy.fill")
                .font(compact ? .headline : .title2)
                .foregroundStyle(.yellow)
                .frame(width: compact ? 36 : 44, height: compact ? 36 : 44)
                .background(.yellow.opacity(0.12), in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text("LOCAL BEST")
                    .font(.caption.bold())
                    .foregroundStyle(.white.opacity(0.68))
                Text(flow.localBestScoreStore.load(), format: .number)
                    .font(.title2.monospacedDigit().bold())
                    .foregroundStyle(.white)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Local best")
        .accessibilityValue("\(flow.localBestScoreStore.load()) points")
        .accessibilityIdentifier("hub.localBest")
    }

    private func watchStatusCard(compact: Bool) -> some View {
        let status = watchSession.readinessStatus
        return HStack(alignment: .top, spacing: compact ? 8 : 12) {
            Image(systemName: status.symbolName)
                .font(compact ? .headline : .title2)
                .foregroundStyle(status.isReady ? .mint : .orange)
                .frame(width: compact ? 36 : 44, height: compact ? 36 : 44)
                .background(
                    (status.isReady ? Color.mint : Color.orange).opacity(0.12),
                    in: Circle()
                )
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(status.displayTitle)
                    .font(.headline.bold())
                    .foregroundStyle(.white)
                Text(status.guidance)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.74))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Apple Watch status")
        .accessibilityValue(status.accessibilityValue)
        .accessibilityIdentifier("hub.watchStatus")
    }

    private func environmentButton(compact: Bool) -> some View {
        Button {
            isEnvironmentPickerPresented = true
        } label: {
            HStack(spacing: compact ? 8 : 12) {
                Image(systemName: flow.environmentSelection.track.symbolName)
                    .font(compact ? .headline : .title2)
                    .foregroundStyle(.cyan)
                    .frame(width: compact ? 36 : 44, height: compact ? 36 : 44)
                    .background(.cyan.opacity(0.12), in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text("TRACK & WEATHER")
                        .font(.caption.bold())
                        .foregroundStyle(.white.opacity(0.64))
                    Text(
                        "\(flow.environmentSelection.track.displayName) · "
                            + flow.environmentSelection.weather.displayName
                    )
                    .font(.subheadline.bold())
                    .foregroundStyle(.white)
                }
                Spacer(minLength: 0)
                Image(systemName: flow.environmentSelection.weather.symbolName)
                    .font(.headline)
                    .foregroundStyle(.white.opacity(0.72))
                Image(systemName: "chevron.right")
                    .font(.caption.bold())
                    .foregroundStyle(.white.opacity(0.46))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Track and weather")
        .accessibilityValue(
            "\(flow.environmentSelection.track.displayName), "
                + flow.environmentSelection.weather.displayName
        )
        .accessibilityHint("Choose the racing track and weather conditions")
        .accessibilityIdentifier("hub.environment")
    }

    private func gameModeButton(compact: Bool) -> some View {
        let selection = flow.gameModeSelection
        return Button {
            isGameModePickerPresented = true
        } label: {
            HStack(spacing: compact ? 8 : 12) {
                Image(systemName: selection.mode == .survival ? "shield.checkered" : "person.3.fill")
                    .font(compact ? .headline : .title2)
                    .foregroundStyle(.orange)
                    .frame(width: compact ? 36 : 44, height: compact ? 36 : 44)
                    .background(.orange.opacity(0.12), in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text("GAME MODE")
                        .font(.caption.bold())
                        .foregroundStyle(.white.opacity(0.64))
                    Text(gameModeSummary(selection))
                        .font(.subheadline.bold())
                        .foregroundStyle(.white)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption.bold())
                    .foregroundStyle(.white.opacity(0.46))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Game mode")
        .accessibilityValue(gameModeSummary(selection))
        .accessibilityHint("Choose survival or a CPU sprint and set the rival count")
        .accessibilityIdentifier("hub.gameMode")
    }

    private func gameModeSummary(_ selection: GameModeSelection) -> String {
        switch selection.mode {
        case .survival:
            selection.mode.displayName
        case .cpuSprint:
            "\(selection.mode.displayName) · \(selection.cpuCount) CPU"
        }
    }

    @ViewBuilder
    private var assetStatus: some View {
        if let errorMessage = flow.errorMessage {
            VStack(alignment: .leading, spacing: 8) {
                errorLabel(errorMessage)
                if flow.assetReadiness == .failed {
                    Button("RETRY GAME ASSETS") {
                        Task {
                            await flow.retryAssetPreparation()
                        }
                    }
                    .buttonStyle(.bordered)
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("hub.retryGameAssets")
                }
            }
        }

        if case let .failed(message) = presentationStatus {
            VStack(alignment: .leading, spacing: 8) {
                errorLabel("Unable to load presentation assets. \(message)")
                Button("RETRY PRESENTATION") {
                    presentationReloadRequest += 1
                }
                .buttonStyle(.bordered)
                .frame(minHeight: 44)
                .accessibilityIdentifier("hub.retryPresentation")
            }
        } else if flow.assetReadiness == .loading || presentationStatus == .loading {
            Label("PREPARING EXPRESSWAY", systemImage: "arrow.trianglehead.2.clockwise.rotate.90")
                .font(.caption.bold())
                .foregroundStyle(.white.opacity(0.74))
                .accessibilityIdentifier("hub.loading")
        }
    }

    private func errorLabel(_ message: String) -> some View {
        Label(message, systemImage: "exclamationmark.triangle.fill")
            .font(.callout)
            .foregroundStyle(.orange)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var canAttemptDrive: Bool {
        flow.canDrive
            && presentationStatus == .ready
            && driveIntent.canRequestDrive
    }

    private var driveAccessibilityHint: String {
        guard flow.assetReadiness == .ready, presentationStatus == .ready else {
            return "Available after game and presentation assets finish loading"
        }
        if watchSession.readinessStatus.isReady {
            return "Save this vehicle and start with Apple Watch preferred controls"
        }
        return "Review Apple Watch readiness before saving or starting"
    }

    private var sensorySettingsAccessibilityValue: String {
        let settings = sensorySettings.settings
        return "Sound effects \(settings.sfxEnabled ? "on" : "off"), "
            + "haptics \(settings.hapticsEnabled ? "on" : "off"), "
            + "effects \(settings.effectIntensity.displayName)"
    }
}

private struct GameModePickerView: View {
    let flow: AppFlowController

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Choose an endless score run or a 1,000 m race against CPU rivals.")
                        .font(.callout)
                        .foregroundStyle(.white.opacity(0.70))

                    ForEach(GameMode.allCases) { mode in
                        modeButton(mode)
                    }

                    if flow.gameModeSelection.mode == .cpuSprint {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("CPU RIVALS")
                                .font(.caption.bold())
                                .tracking(1.2)
                                .foregroundStyle(.orange)
                            Picker(
                                "CPU rivals",
                                selection: Binding(
                                    get: { flow.gameModeSelection.cpuCount },
                                    set: { flow.selectCPUCount($0) }
                                )
                            ) {
                                ForEach(1...3, id: \.self) { count in
                                    Text("\(count) CPU").tag(count)
                                }
                            }
                            .pickerStyle(.segmented)
                            .accessibilityIdentifier("gameMode.cpuCount")

                            Text("PLAYER + \(flow.gameModeSelection.cpuCount) CPU · "
                                + "\(flow.gameModeSelection.cpuCount + 1) CARS TOTAL")
                                .font(.caption.monospaced().bold())
                                .foregroundStyle(.white.opacity(0.68))
                        }
                        .padding(14)
                        .background(
                            Color.orange.opacity(0.10),
                            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                        )
                    }

                    Label(
                        "Stay off the side guards for 5 seconds to trigger a 3-second auto boost.",
                        systemImage: "bolt.fill"
                    )
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.mint)
                    .padding(12)
                    .background(.mint.opacity(0.09), in: RoundedRectangle(cornerRadius: 12))
                }
                .padding(20)
                .frame(maxWidth: 680)
                .frame(maxWidth: .infinity)
            }
            .background(
                LinearGradient(
                    colors: [
                        Color(red: 0.02, green: 0.04, blue: 0.08),
                        Color(red: 0.16, green: 0.07, blue: 0.03),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
            )
            .navigationTitle("GAME MODE")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("DONE") {
                        dismiss()
                    }
                    .fontWeight(.bold)
                    .accessibilityIdentifier("gameMode.done")
                }
            }
        }
        .preferredColorScheme(.dark)
        .presentationDetents([.medium, .large])
    }

    private func modeButton(_ mode: GameMode) -> some View {
        let isSelected = flow.gameModeSelection.mode == mode
        return Button {
            flow.selectGameMode(mode)
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: mode == .survival ? "shield.checkered" : "person.3.fill")
                    .font(.title3.bold())
                    .foregroundStyle(isSelected ? .black : .orange)
                    .frame(width: 40, height: 40)
                    .background(
                        isSelected ? Color.orange : Color.orange.opacity(0.12),
                        in: Circle()
                    )
                VStack(alignment: .leading, spacing: 3) {
                    Text(mode.displayName)
                        .font(.headline.bold())
                        .foregroundStyle(.white)
                    Text(mode.detail)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.66))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.orange)
                        .accessibilityHidden(true)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 84, alignment: .leading)
            .background(
                isSelected ? Color.orange.opacity(0.12) : Color.white.opacity(0.055),
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(
                        isSelected ? Color.orange.opacity(0.76) : Color.white.opacity(0.10)
                    )
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(mode.displayName)
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
        .accessibilityHint(mode.detail)
        .accessibilityIdentifier("gameMode.\(mode.rawValue)")
    }
}

private struct RacingEnvironmentPickerView: View {
    let flow: AppFlowController

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    optionSection(
                        title: "TRACK",
                        subtitle: "Each route changes corner rhythm, elevation and scenery."
                    ) {
                        ForEach(RacingTrack.allCases) { track in
                            optionButton(
                                title: track.displayName,
                                detail: track.detail,
                                symbolName: track.symbolName,
                                isSelected: flow.environmentSelection.track == track,
                                accessibilityID: "environment.track.\(track.rawValue)"
                            ) {
                                flow.selectTrack(track)
                            }
                        }
                    }

                    optionSection(
                        title: "WEATHER",
                        subtitle: "Visibility, sunlight and asphalt reflections react to conditions."
                    ) {
                        ForEach(RacingWeather.allCases) { weather in
                            optionButton(
                                title: weather.displayName,
                                detail: weather.detail,
                                symbolName: weather.symbolName,
                                isSelected: flow.environmentSelection.weather == weather,
                                accessibilityID: "environment.weather.\(weather.rawValue)"
                            ) {
                                flow.selectWeather(weather)
                            }
                        }
                    }
                }
                .padding(20)
                .frame(maxWidth: 760)
                .frame(maxWidth: .infinity)
            }
            .background(
                LinearGradient(
                    colors: [
                        Color(red: 0.02, green: 0.04, blue: 0.08),
                        Color(red: 0.03, green: 0.12, blue: 0.15),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
            )
            .navigationTitle("TRACK CONDITIONS")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("DONE") {
                        dismiss()
                    }
                    .fontWeight(.bold)
                    .accessibilityIdentifier("environment.done")
                }
            }
        }
        .preferredColorScheme(.dark)
        .presentationDetents([.medium, .large])
    }

    private func optionSection<Content: View>(
        title: String,
        subtitle: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.caption.bold())
                .tracking(1.2)
                .foregroundStyle(.mint)
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.62))
            LazyVStack(spacing: 10) {
                content()
            }
        }
    }

    private func optionButton(
        title: String,
        detail: String,
        symbolName: String,
        isSelected: Bool,
        accessibilityID: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: symbolName)
                    .font(.title3.bold())
                    .foregroundStyle(isSelected ? .black : .mint)
                    .frame(width: 38, height: 38)
                    .background(isSelected ? Color.mint : Color.mint.opacity(0.12), in: Circle())
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.headline.bold())
                        .foregroundStyle(.white)
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.66))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.mint)
                        .accessibilityHidden(true)
                }
            }
            .padding(13)
            .frame(maxWidth: .infinity, minHeight: 82, alignment: .leading)
            .background(
                isSelected ? Color.mint.opacity(0.12) : Color.white.opacity(0.055),
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(isSelected ? Color.mint.opacity(0.74) : Color.white.opacity(0.10))
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
        .accessibilityHint(detail)
        .accessibilityIdentifier(accessibilityID)
    }
}
