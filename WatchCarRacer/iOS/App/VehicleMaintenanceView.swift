import SwiftUI

struct VehicleMaintenanceView: View {
    static let vehicleOptions = VehicleCatalog.all
    static let colorOptions = VehicleCatalog.colors
    static let pendingText = "Pending until Drive"
    static let pendingAccessibilityValue =
        "Changes are pending until Drive and have not been saved"

    let flow: AppFlowController
    let presentationAssetLibrary: PresentationAssetLibrary

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var presentationStatus: PresentationLoadStatus = .idle
    @State private var presentationReloadRequest = 0

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                if let appearance = flow.draftAppearance {
                    VehiclePresentationView(
                        route: .maintenance,
                        appearance: appearance,
                        assetLibrary: presentationAssetLibrary,
                        reloadRequest: presentationReloadRequest,
                        loadStatus: $presentationStatus
                    )
                }

                LinearGradient(
                    colors: [.clear, .black.opacity(0.16), .black.opacity(0.72)],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .ignoresSafeArea()
                .accessibilityHidden(true)

                maintenanceContent(width: proxy.size.width)
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
            }
        }
        .preferredColorScheme(.dark)
    }

    @ViewBuilder
    private func maintenanceContent(width: CGFloat) -> some View {
        if dynamicTypeSize.isAccessibilitySize {
            controlRail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            HStack(alignment: .top, spacing: 18) {
                heroLabel
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)

                controlRail
                    .frame(width: min(max(width * 0.39, 300), 430))
                    .frame(maxHeight: .infinity)
            }
        }
    }

    private var heroLabel: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("PIT LANE 01")
                .font(.caption.bold())
                .tracking(1.4)
                .foregroundStyle(.mint)
            if let appearance = flow.draftAppearance {
                Text(appearance.vehicle.displayName)
                    .font(.system(.title, design: .rounded, weight: .black))
                    .foregroundStyle(.white)
                Text(appearance.color.displayName)
                    .font(.headline)
                    .foregroundStyle(.white.opacity(0.78))
            }
        }
        .padding(14)
        .premiumPanel(reduceTransparency: reduceTransparency)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
        .accessibilityIdentifier("maintenance.currentSelection")
    }

    private var controlRail: some View {
        VStack(spacing: 10) {
            navigation

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    vehiclePicker
                    colorPicker
                    pendingNotice
                    presentationAssetStatus
                }
                .padding(.vertical, 2)
            }
            .scrollIndicators(.visible)
        }
        .padding(14)
        .premiumPanel(reduceTransparency: reduceTransparency)
    }

    private var navigation: some View {
        HStack(spacing: 10) {
            Button {
                flow.exitMaintenance()
            } label: {
                Label("BACK", systemImage: "chevron.left")
                    .font(.headline.bold())
                    .frame(maxWidth: .infinity, minHeight: 46)
            }
            .buttonStyle(.bordered)
            .accessibilityHint("Return to the hub and keep these changes pending")
            .accessibilityIdentifier("maintenance.back")

            Button {
                flow.exitMaintenance()
            } label: {
                Label("DONE", systemImage: "checkmark")
                    .font(.headline.bold())
                    .frame(maxWidth: .infinity, minHeight: 46)
            }
            .buttonStyle(.borderedProminent)
            .tint(.mint)
            .foregroundStyle(.black)
            .accessibilityHint("Return to the hub and keep these changes pending")
            .accessibilityIdentifier("maintenance.done")
        }
    }

    private var vehiclePicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("VEHICLE")

            ForEach(Self.vehicleOptions, id: \.id) { vehicle in
                let isSelected = vehicle.id == flow.draftSelection.vehicleID
                Button {
                    flow.selectVehicle(vehicle.id)
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                            .font(.title3)
                            .accessibilityHidden(true)
                        Text(vehicle.displayName)
                            .font(.callout.bold())
                            .multilineTextAlignment(.leading)
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .padding(.horizontal, 10)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(isSelected ? .black : .white)
                .background(
                    isSelected ? Color.mint : Color.white.opacity(0.08),
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(isSelected ? .white : .white.opacity(0.18), lineWidth: 2)
                }
                .accessibilityLabel(vehicle.accessibilityName)
                .accessibilityValue(isSelected ? "Selected" : "Not selected")
                .accessibilityAddTraits(isSelected ? .isSelected : [])
                .accessibilityHint("Select this appearance-only vehicle body")
                .accessibilityIdentifier("maintenance.vehicle.\(vehicle.id.rawValue)")
            }
        }
    }

    private var colorPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("BODY COLOR")

            LazyVGrid(
                columns: [GridItem(.flexible()), GridItem(.flexible())],
                spacing: 8
            ) {
                ForEach(Self.colorOptions, id: \.id) { color in
                    MaintenanceColorButton(
                        color: color,
                        isSelected: color.id == flow.draftSelection.colorID,
                        onSelect: { flow.selectColor(color.id) }
                    )
                }
            }
        }
    }

    private var pendingNotice: some View {
        Label(Self.pendingText, systemImage: "clock.badge.exclamationmark")
            .font(.callout.bold())
            .foregroundStyle(.yellow)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .accessibilityLabel("Vehicle changes")
            .accessibilityValue(Self.pendingAccessibilityValue)
            .accessibilityIdentifier("maintenance.pending")
    }

    @ViewBuilder
    private var presentationAssetStatus: some View {
        if case let .failed(message) = presentationStatus {
            VStack(alignment: .leading, spacing: 8) {
                Label(
                    "Unable to load vehicle presentation. \(message)",
                    systemImage: "exclamationmark.triangle.fill"
                )
                .font(.callout)
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)

                Button("RETRY PRESENTATION") {
                    presentationReloadRequest += 1
                }
                .buttonStyle(.bordered)
                .frame(minHeight: 44)
                .accessibilityIdentifier("maintenance.retryPresentation")
            }
        } else if presentationStatus == .loading {
            Label("PREPARING PIT LANE", systemImage: "arrow.trianglehead.2.clockwise.rotate.90")
                .font(.caption.bold())
                .foregroundStyle(.white.opacity(0.74))
                .accessibilityIdentifier("maintenance.loading")
        }
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.caption.bold())
            .tracking(1.1)
            .foregroundStyle(.mint)
            .accessibilityAddTraits(.isHeader)
    }

}

private struct MaintenanceColorButton: View {
    let color: VehicleColorDescriptor
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 7) {
                ZStack {
                    Circle()
                        .fill(color.swiftUIColor)
                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(.caption.bold())
                            .foregroundStyle(checkmarkColor)
                    }
                }
                .frame(width: 28, height: 28)
                .overlay {
                    Circle().stroke(.white, lineWidth: isSelected ? 3 : 1)
                }
                .accessibilityHidden(true)

                Text(color.displayName)
                    .font(.caption.bold())
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, minHeight: 48)
            .padding(.horizontal, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
        .background(
            isSelected ? Color.white.opacity(0.20) : Color.white.opacity(0.07),
            in: RoundedRectangle(cornerRadius: 11, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .stroke(isSelected ? .mint : .white.opacity(0.12), lineWidth: 2)
        }
        .accessibilityLabel(color.accessibilityName)
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityHint("Select this body color")
        .accessibilityIdentifier("maintenance.color.\(color.id.rawValue)")
    }

    private var checkmarkColor: Color {
        let components = color.rgba
        let luminance = components.red * 0.299
            + components.green * 0.587
            + components.blue * 0.114
        return luminance > 0.58 ? .black : .white
    }
}
