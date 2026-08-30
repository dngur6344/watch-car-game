import SwiftUI
import UIKit

enum PresentationLoadStatus: Equatable {
    case idle
    case loading
    case ready
    case failed(String)
}

struct VehiclePresentationView: View {
    let route: PresentationRoute
    let appearance: VehicleAppearance
    let assetLibrary: PresentationAssetLibrary
    let reloadRequest: Int
    var materialSweepTrigger = 0
    var effectIntensity: SensoryEffectIntensity = .balanced
    @Binding var loadStatus: PresentationLoadStatus

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var routeAssets: PresentationRouteAssets?
    @State private var vehicleImage: UIImage?
    @State private var lastMaterialSweepTrigger = 0
    @State private var materialSweepProgress: CGFloat = -0.76
    @State private var materialSweepOpacity = 0.0

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                background

                if let vehicleImage {
                    Image(uiImage: vehicleImage)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fit)
                        .frame(
                            width: heroWidth(in: proxy.size),
                            height: proxy.size.height * 0.88
                        )
                        .position(heroPosition(in: proxy.size))
#if DEBUG
                        .onAppear(perform: recordPresentationReadyIfDecoded)
#endif
                }

                materialSweep(in: proxy.size)
            }
        }
        .accessibilityHidden(true)
        .task(id: loadKey) {
            loadPresentation()
        }
        .transaction { transaction in
            if reduceMotion {
                transaction.animation = nil
            }
        }
    }

    @ViewBuilder
    private var background: some View {
        if let routeAssets {
            Image(uiImage: routeAssets.background)
                .resizable()
                .interpolation(.high)
                .scaledToFill()
                .ignoresSafeArea()
        } else {
            LinearGradient(
                colors: [
                    Color(red: 0.015, green: 0.025, blue: 0.055),
                    Color(red: 0.025, green: 0.11, blue: 0.16),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
        }
    }

    private var loadKey: String {
        "\(route.rawValue)|\(appearance.vehicle.id.rawValue)|"
            + "\(appearance.color.id.rawValue)|\(reloadRequest)"
    }

    private func loadPresentation() {
        loadStatus = .loading
        routeAssets = nil
        vehicleImage = nil

        do {
            let assets = try assetLibrary.load(
                route: route,
                vehicleID: appearance.vehicle.id
            )
            routeAssets = assets
            vehicleImage = PresentationVehicleCompositor.image(
                hero: assets.hero,
                tint: appearance.color.uiColor
            )
            loadStatus = .ready
            presentMaterialSweepIfNeeded()
        } catch {
            loadStatus = .failed(error.localizedDescription)
        }
    }

    @ViewBuilder
    private func materialSweep(in size: CGSize) -> some View {
        if let vehicleImage, materialSweepOpacity > 0 {
            let style = SensoryMicroInteractionStyle(
                effectIntensity: effectIntensity,
                reduceMotion: reduceMotion
            )
            Group {
                if style.usesMotion {
                    LinearGradient(
                        colors: [
                            .clear,
                            .white.opacity(0.64),
                            .mint.opacity(0.92),
                            .white.opacity(0.70),
                            .clear,
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: heroWidth(in: size) * 0.30)
                    .offset(x: materialSweepProgress * heroWidth(in: size))
                } else {
                    Color.white
                }
            }
            .frame(width: size.width, height: size.height)
            .mask {
                Image(uiImage: vehicleImage)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(
                        width: heroWidth(in: size),
                        height: size.height * 0.88
                    )
                    .position(heroPosition(in: size))
            }
            .blendMode(.screen)
            .opacity(materialSweepOpacity)
            .allowsHitTesting(false)
        }
    }

    private func presentMaterialSweepIfNeeded() {
        guard materialSweepTrigger != lastMaterialSweepTrigger else { return }
        lastMaterialSweepTrigger = materialSweepTrigger
        let style = SensoryMicroInteractionStyle(
            effectIntensity: effectIntensity,
            reduceMotion: reduceMotion
        )
        materialSweepProgress = -0.76
        materialSweepOpacity = style.materialSweepAlpha

        if style.usesMotion {
            withAnimation(.easeInOut(duration: 0.44)) {
                materialSweepProgress = 0.76
            }
            withAnimation(.easeOut(duration: 0.16).delay(0.32)) {
                materialSweepOpacity = 0
            }
        } else {
            withAnimation(.easeOut(duration: 0.34)) {
                materialSweepOpacity = 0
            }
        }
    }

    private func heroWidth(in size: CGSize) -> CGFloat {
        switch route {
        case .hub:
            min(size.width * 0.56, 720)
        case .maintenance:
            min(size.width * 0.64, 820)
        }
    }

#if DEBUG
    private func recordPresentationReadyIfDecoded() {
        guard routeAssets != nil,
              vehicleImage != nil,
              loadStatus == .ready else {
            return
        }
        SG6AcceptanceProbe.recordPresentationReady(route: route)
    }
#endif

    private func heroPosition(in size: CGSize) -> CGPoint {
        switch route {
        case .hub:
            CGPoint(x: size.width * 0.48, y: size.height * 0.61)
        case .maintenance:
            CGPoint(x: size.width * 0.40, y: size.height * 0.59)
        }
    }
}

extension VehicleColorDescriptor {
    var swiftUIColor: Color {
        Color(uiColor)
    }

    var uiColor: UIColor {
        UIColor(
            red: rgba.red,
            green: rgba.green,
            blue: rgba.blue,
            alpha: rgba.alpha
        )
    }
}

private struct PremiumPanelModifier: ViewModifier {
    let reduceTransparency: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if reduceTransparency {
            content
                .background(
                    Color(red: 0.025, green: 0.045, blue: 0.075).opacity(0.98),
                    in: RoundedRectangle(cornerRadius: 22, style: .continuous)
                )
        } else {
            content
                .background(
                    .ultraThinMaterial,
                    in: RoundedRectangle(cornerRadius: 22, style: .continuous)
                )
        }
    }
}

extension View {
    func premiumPanel(reduceTransparency: Bool) -> some View {
        modifier(PremiumPanelModifier(reduceTransparency: reduceTransparency))
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(.white.opacity(0.18), lineWidth: 1)
            }
    }
}
