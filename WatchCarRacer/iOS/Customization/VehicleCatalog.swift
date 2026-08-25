import CoreGraphics
import Foundation

enum VehicleID: String, CaseIterable, Codable, Hashable, Sendable {
    case rally
    case gt
    case angular
}

enum VehicleColorID: String, CaseIterable, Codable, Hashable, Sendable {
    case auroraMint = "aurora-mint"
    case voltCyan = "volt-cyan"
    case ultraviolet
    case pulseMagenta = "pulse-magenta"
    case solarCoral = "solar-coral"
    case emberGold = "ember-gold"
    case lunarSilver = "lunar-silver"
    case midnightInk = "midnight-ink"
}

struct VehicleSelection: Codable, Equatable, Sendable {
    let vehicleID: VehicleID
    let colorID: VehicleColorID
}

struct NormalizedPivot: Codable, Equatable, Sendable {
    let x: Double
    let y: Double

    static let collisionCenter = NormalizedPivot(x: 0.5, y: 0.5)
}

struct VehicleTextureLayers: Equatable, Sendable {
    let shadow: String
    let paint: String
    let details: String

    var allNames: [String] {
        [shadow, paint, details]
    }
}

struct VehicleDescriptor: Equatable, Sendable {
    let id: VehicleID
    let displayName: String
    let accessibilityName: String
    let textures: VehicleTextureLayers
    let logicalRenderSize: CGSize
    let pivot: NormalizedPivot
}

struct RGBAComponents: Equatable, Sendable {
    let red: Double
    let green: Double
    let blue: Double
    let alpha: Double

    init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = Self.normalized(red)
        self.green = Self.normalized(green)
        self.blue = Self.normalized(blue)
        self.alpha = Self.normalized(alpha)
    }

    var all: [Double] {
        [red, green, blue, alpha]
    }

    private static func normalized(_ component: Double) -> Double {
        guard component.isFinite else { return 0 }
        return min(max(component, 0), 1)
    }
}

struct VehicleColorDescriptor: Equatable, Sendable {
    let id: VehicleColorID
    let displayName: String
    let accessibilityName: String
    let rgba: RGBAComponents
}

struct VehicleAppearance: Equatable, Sendable {
    let vehicle: VehicleDescriptor
    let color: VehicleColorDescriptor
}

enum VehicleCatalog {
    static let all: [VehicleDescriptor] = VehicleID.allCases.map(descriptor(for:))
    static let colors: [VehicleColorDescriptor] = VehicleColorID.allCases.map(color(for:))
    static let defaultSelection = VehicleSelection(vehicleID: .rally, colorID: .auroraMint)
    static let allSelections: [VehicleSelection] = all.flatMap { vehicle in
        colors.map { color in
            VehicleSelection(vehicleID: vehicle.id, colorID: color.id)
        }
    }

    static func descriptor(for id: VehicleID) -> VehicleDescriptor {
        switch id {
        case .rally:
            return VehicleDescriptor(
                id: .rally,
                displayName: "Rally Hatch",
                accessibilityName: "Rally hatch vehicle",
                textures: VehicleTextureLayers(
                    shadow: "rally_shadow",
                    paint: "rally_paint",
                    details: "rally_details"
                ),
                logicalRenderSize: CGSize(width: 50, height: 75),
                pivot: .collisionCenter
            )
        case .gt:
            return VehicleDescriptor(
                id: .gt,
                displayName: "GT Coupe",
                accessibilityName: "GT coupe vehicle",
                textures: VehicleTextureLayers(
                    shadow: "gt_shadow",
                    paint: "gt_paint",
                    details: "gt_details"
                ),
                logicalRenderSize: CGSize(width: 50, height: 75),
                pivot: .collisionCenter
            )
        case .angular:
            return VehicleDescriptor(
                id: .angular,
                displayName: "Angular Performance",
                accessibilityName: "Angular performance vehicle",
                textures: VehicleTextureLayers(
                    shadow: "angular_shadow",
                    paint: "angular_paint",
                    details: "angular_details"
                ),
                logicalRenderSize: CGSize(width: 50, height: 75),
                pivot: .collisionCenter
            )
        }
    }

    static func color(for id: VehicleColorID) -> VehicleColorDescriptor {
        switch id {
        case .auroraMint:
            return VehicleColorDescriptor(
                id: .auroraMint,
                displayName: "Aurora Mint",
                accessibilityName: "Aurora mint body color",
                rgba: RGBAComponents(red: 0.20, green: 0.94, blue: 0.78)
            )
        case .voltCyan:
            return VehicleColorDescriptor(
                id: .voltCyan,
                displayName: "Volt Cyan",
                accessibilityName: "Volt cyan body color",
                rgba: RGBAComponents(red: 0.10, green: 0.72, blue: 1)
            )
        case .ultraviolet:
            return VehicleColorDescriptor(
                id: .ultraviolet,
                displayName: "Ultraviolet",
                accessibilityName: "Ultraviolet body color",
                rgba: RGBAComponents(red: 0.48, green: 0.31, blue: 0.98)
            )
        case .pulseMagenta:
            return VehicleColorDescriptor(
                id: .pulseMagenta,
                displayName: "Pulse Magenta",
                accessibilityName: "Pulse magenta body color",
                rgba: RGBAComponents(red: 0.95, green: 0.16, blue: 0.62)
            )
        case .solarCoral:
            return VehicleColorDescriptor(
                id: .solarCoral,
                displayName: "Solar Coral",
                accessibilityName: "Solar coral body color",
                rgba: RGBAComponents(red: 1, green: 0.31, blue: 0.28)
            )
        case .emberGold:
            return VehicleColorDescriptor(
                id: .emberGold,
                displayName: "Ember Gold",
                accessibilityName: "Ember gold body color",
                rgba: RGBAComponents(red: 1, green: 0.67, blue: 0.16)
            )
        case .lunarSilver:
            return VehicleColorDescriptor(
                id: .lunarSilver,
                displayName: "Lunar Silver",
                accessibilityName: "Lunar silver body color",
                rgba: RGBAComponents(red: 0.72, green: 0.78, blue: 0.88)
            )
        case .midnightInk:
            return VehicleColorDescriptor(
                id: .midnightInk,
                displayName: "Midnight Ink",
                accessibilityName: "Midnight ink body color",
                rgba: RGBAComponents(red: 0.08, green: 0.10, blue: 0.18)
            )
        }
    }

    static func resolve(_ selection: VehicleSelection) -> VehicleAppearance? {
        guard let vehicle = all.first(where: { $0.id == selection.vehicleID }),
              let color = colors.first(where: { $0.id == selection.colorID }) else {
            return nil
        }
        return VehicleAppearance(vehicle: vehicle, color: color)
    }

    static func resolve(vehicleID: String, colorID: String) -> VehicleAppearance? {
        guard let vehicleID = VehicleID(rawValue: vehicleID),
              let colorID = VehicleColorID(rawValue: colorID) else {
            return nil
        }
        return resolve(VehicleSelection(vehicleID: vehicleID, colorID: colorID))
    }
}
