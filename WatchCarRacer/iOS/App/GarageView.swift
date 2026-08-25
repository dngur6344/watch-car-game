import SpriteKit
import SwiftUI

struct GarageView: View {
    let flow: AppFlowController

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.025, green: 0.035, blue: 0.075),
                    Color(red: 0.13, green: 0.055, blue: 0.20),
                    Color(red: 0.025, green: 0.12, blue: 0.16),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            ScrollView {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .center, spacing: 28) {
                        previewSection
                            .frame(minWidth: 220, maxWidth: .infinity)
                        controlsSection
                            .frame(minWidth: 330, maxWidth: 540)
                    }

                    VStack(spacing: 22) {
                        previewSection
                        controlsSection
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 18)
            }
        }
        .preferredColorScheme(.dark)
        .task {
            await flow.prepareAssets()
        }
    }

    private var previewSection: some View {
        VStack(spacing: 12) {
            VStack(spacing: 2) {
                Text("NIGHTSHIFT GARAGE")
                    .font(.system(.largeTitle, design: .rounded, weight: .black))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                Text("Choose your ride, paint it, then own the expressway.")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.72))
                    .multilineTextAlignment(.center)
            }

            preview
                .frame(minHeight: 150, idealHeight: 190, maxHeight: 230)
                .frame(maxWidth: 400)
                .background(.black.opacity(0.28), in: RoundedRectangle(cornerRadius: 24))
                .overlay {
                    RoundedRectangle(cornerRadius: 24)
                        .stroke(.mint.opacity(0.48), lineWidth: 1)
                }

            if let appearance = flow.draftAppearance {
                Text("\(appearance.vehicle.displayName) · \(appearance.color.displayName)")
                    .font(.headline.bold())
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .accessibilityIdentifier("garage.previewSelection")
            }
        }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var preview: some View {
        switch flow.assetReadiness {
        case .idle, .loading:
            VStack(spacing: 10) {
                ProgressView()
                    .controlSize(.large)
                    .tint(.mint)
                Text("Preparing vehicle preview")
                    .font(.callout.bold())
                    .foregroundStyle(.white.opacity(0.82))
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Preparing vehicle preview")
        case .ready:
            if let appearance = flow.draftAppearance {
                GarageVehiclePreview(
                    appearance: appearance,
                    assetLibrary: flow.assetLibrary
                )
                .id(
                    "\(flow.draftSelection.vehicleID.rawValue)|"
                        + flow.draftSelection.colorID.rawValue
                )
            }
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 44))
                .foregroundStyle(.orange)
                .accessibilityLabel("Vehicle preview unavailable")
        }
    }

    private var controlsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            vehiclePicker
            colorPicker
            assetStatus
            driveButton
        }
        .padding(18)
        .background(.black.opacity(0.42), in: RoundedRectangle(cornerRadius: 22))
    }

    private var vehiclePicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("VEHICLE")
                .font(.caption.bold())
                .foregroundStyle(.mint)

            HStack(spacing: 8) {
                ForEach(VehicleCatalog.all, id: \.id) { vehicle in
                    let isSelected = vehicle.id == flow.draftSelection.vehicleID
                    Button {
                        flow.selectVehicle(vehicle.id)
                    } label: {
                        VStack(spacing: 5) {
                            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                .font(.title3)
                            Text(vehicle.displayName)
                                .font(.caption.bold())
                                .lineLimit(2)
                                .minimumScaleFactor(0.75)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity, minHeight: 58)
                        .padding(.horizontal, 4)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(isSelected ? .black : .white)
                    .background(
                        isSelected ? Color.mint : Color.white.opacity(0.09),
                        in: RoundedRectangle(cornerRadius: 12)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(isSelected ? .white : .white.opacity(0.20), lineWidth: 2)
                    }
                    .accessibilityLabel(vehicle.accessibilityName)
                    .accessibilityValue(isSelected ? "Selected" : "Not selected")
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                    .accessibilityIdentifier("garage.vehicle.\(vehicle.id.rawValue)")
                }
            }
        }
    }

    private var colorPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("BODY COLOR")
                .font(.caption.bold())
                .foregroundStyle(.mint)

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 104), spacing: 8)],
                spacing: 8
            ) {
                ForEach(VehicleCatalog.colors, id: \.id) { color in
                    let isSelected = color.id == flow.draftSelection.colorID
                    Button {
                        flow.selectColor(color.id)
                    } label: {
                        HStack(spacing: 7) {
                            ZStack {
                                Circle()
                                    .fill(swiftUIColor(color.rgba))
                                if isSelected {
                                    Image(systemName: "checkmark")
                                        .font(.caption.bold())
                                        .foregroundStyle(checkmarkColor(for: color.rgba))
                                }
                            }
                            .frame(width: 28, height: 28)
                            .overlay {
                                Circle()
                                    .stroke(.white, lineWidth: isSelected ? 3 : 1)
                            }

                            Text(color.displayName)
                                .font(.caption.bold())
                                .lineLimit(2)
                                .minimumScaleFactor(0.75)
                            Spacer(minLength: 0)
                        }
                        .frame(maxWidth: .infinity, minHeight: 46)
                        .padding(.horizontal, 8)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.white)
                    .background(
                        isSelected ? Color.white.opacity(0.18) : Color.white.opacity(0.07),
                        in: RoundedRectangle(cornerRadius: 11)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 11)
                            .stroke(isSelected ? .mint : .clear, lineWidth: 2)
                    }
                    .accessibilityLabel(color.accessibilityName)
                    .accessibilityValue(isSelected ? "Selected" : "Not selected")
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                    .accessibilityIdentifier("garage.color.\(color.id.rawValue)")
                }
            }
        }
    }

    @ViewBuilder
    private var assetStatus: some View {
        if let errorMessage = flow.errorMessage {
            VStack(alignment: .leading, spacing: 8) {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("garage.error")

                if flow.assetReadiness == .failed {
                    Button("RETRY ASSET LOAD") {
                        Task {
                            await flow.retryAssetPreparation()
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .accessibilityIdentifier("garage.retryAssetLoad")
                }
            }
            .accessibilityElement(children: .contain)
        } else if flow.assetReadiness == .loading {
            Label("LOADING GAME ASSETS", systemImage: "arrow.trianglehead.2.clockwise.rotate.90")
                .font(.caption.bold())
                .foregroundStyle(.white.opacity(0.72))
                .accessibilityIdentifier("garage.loading")
        }
    }

    private var driveButton: some View {
        Button {
            flow.drive()
        } label: {
            Label("DRIVE", systemImage: "steeringwheel")
                .font(.title3.bold())
                .frame(maxWidth: .infinity, minHeight: 48)
        }
        .buttonStyle(.borderedProminent)
        .buttonBorderShape(.capsule)
        .tint(.mint)
        .foregroundStyle(.black)
        .disabled(!flow.canDrive)
        .accessibilityHint(
            flow.canDrive
                ? "Save this vehicle and start a new drive"
                : "Available after all game assets finish loading"
        )
        .accessibilityIdentifier("garage.drive")
    }

    private func swiftUIColor(_ components: RGBAComponents) -> Color {
        Color(
            red: components.red,
            green: components.green,
            blue: components.blue,
            opacity: components.alpha
        )
    }

    private func checkmarkColor(for components: RGBAComponents) -> Color {
        let luminance = components.red * 0.299
            + components.green * 0.587
            + components.blue * 0.114
        return luminance > 0.58 ? .black : .white
    }
}

private struct GarageVehiclePreview: View {
    private let scene: GarageVehiclePreviewScene?
    private let errorMessage: String?

    init(appearance: VehicleAppearance, assetLibrary: GameAssetLibrary) {
        do {
            scene = try GarageVehiclePreviewScene(
                appearance: appearance,
                assetLibrary: assetLibrary
            )
            errorMessage = nil
        } catch {
            scene = nil
            errorMessage = error.localizedDescription
        }
    }

    var body: some View {
        if let scene {
            SpriteView(scene: scene, options: [.allowsTransparency])
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Selected vehicle preview")
                .accessibilityIdentifier("garage.vehiclePreview")
        } else {
            Label(
                errorMessage ?? "Vehicle preview unavailable",
                systemImage: "exclamationmark.triangle.fill"
            )
            .font(.callout)
            .foregroundStyle(.orange)
            .multilineTextAlignment(.center)
            .padding()
            .accessibilityIdentifier("garage.previewError")
        }
    }
}

@MainActor
private final class GarageVehiclePreviewScene: SKScene {
    init(appearance: VehicleAppearance, assetLibrary: GameAssetLibrary) throws {
        super.init(size: CGSize(width: 320, height: 210))
        scaleMode = .aspectFit
        backgroundColor = .clear

        let vehicle = try VehicleSpriteNode(
            appearance: appearance,
            assetLibrary: assetLibrary
        )
        vehicle.position = CGPoint(x: size.width / 2, y: size.height / 2)
        vehicle.setScale(2.15)
        addChild(vehicle)
    }

    @available(*, unavailable)
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }
}
