import CoreGraphics
import XCTest
@testable import WatchCarRacer

final class VehicleCatalogTests: XCTestCase {
    func testCatalogHasExactlyFourStableVehiclesAndEightStableColors() {
        XCTAssertEqual(VehicleID.allCases, [.rally, .gt, .angular, .rallyRS])
        XCTAssertEqual(
            VehicleColorID.allCases,
            [
                .auroraMint, .voltCyan, .ultraviolet, .pulseMagenta,
                .solarCoral, .emberGold, .lunarSilver, .midnightInk,
            ]
        )
        XCTAssertEqual(VehicleCatalog.all.count, 4)
        XCTAssertEqual(VehicleCatalog.colors.count, 8)
        XCTAssertEqual(Set(VehicleID.allCases.map(\.rawValue)).count, 4)
        XCTAssertEqual(Set(VehicleColorID.allCases.map(\.rawValue)).count, 8)
        XCTAssertEqual(Set(VehicleCatalog.all.map(\.displayName)).count, 4)
        XCTAssertEqual(Set(VehicleCatalog.all.map(\.accessibilityName)).count, 4)
        XCTAssertEqual(Set(VehicleCatalog.colors.map(\.displayName)).count, 8)
        XCTAssertEqual(Set(VehicleCatalog.colors.map(\.accessibilityName)).count, 8)
    }

    func testVehicleTextureDescriptorsRenderSizesAndPivotsRemainValid() {
        XCTAssertEqual(Set(VehicleCatalog.all.flatMap(\.textures.allNames)).count, 9)

        for descriptor in VehicleCatalog.all {
            XCTAssertFalse(descriptor.displayName.isEmpty)
            XCTAssertFalse(descriptor.accessibilityName.isEmpty)
            XCTAssertEqual(descriptor.logicalRenderSize, CGSize(width: 50, height: 75))
            XCTAssertEqual(descriptor.pivot, .collisionCenter)
            XCTAssertTrue((0...1).contains(descriptor.pivot.x))
            XCTAssertTrue((0...1).contains(descriptor.pivot.y))
            XCTAssertEqual(descriptor.textures.allNames.count, 3)
            XCTAssertTrue(descriptor.textures.shadow.hasSuffix("_shadow"))
            XCTAssertTrue(descriptor.textures.paint.hasSuffix("_paint"))
            XCTAssertTrue(descriptor.textures.details.hasSuffix("_details"))
            XCTAssertTrue(descriptor.textures.allNames.allSatisfy { !$0.isEmpty })
        }
    }

    func testColorDescriptorsHaveFiniteNormalizedRGBAComponents() {
        for color in VehicleCatalog.colors {
            XCTAssertFalse(color.displayName.isEmpty)
            XCTAssertFalse(color.accessibilityName.isEmpty)
            XCTAssertEqual(color.rgba.all.count, 4)
            XCTAssertTrue(color.rgba.all.allSatisfy(\.isFinite), color.id.rawValue)
            XCTAssertTrue(
                color.rgba.all.allSatisfy { (0...1).contains($0) },
                color.id.rawValue
            )
        }

        let normalized = RGBAComponents(red: -1, green: 2, blue: .nan, alpha: .infinity)
        XCTAssertEqual(normalized, RGBAComponents(red: 0, green: 1, blue: 0, alpha: 0))
    }

    func testCatalogResolvesExactlyThirtyTwoUniqueVisualOnlyAppearances() throws {
        XCTAssertEqual(VehicleCatalog.allSelections.count, 32)
        XCTAssertEqual(
            Set(VehicleCatalog.allSelections.map { "\($0.vehicleID.rawValue)|\($0.colorID.rawValue)" }).count,
            32
        )

        var appearanceKeys = Set<String>()
        for selection in VehicleCatalog.allSelections {
            let appearance = try XCTUnwrap(VehicleCatalog.resolve(selection))
            XCTAssertEqual(appearance.vehicle.id, selection.vehicleID)
            XCTAssertEqual(appearance.color.id, selection.colorID)
            XCTAssertEqual(
                Set(Mirror(reflecting: appearance).children.compactMap(\.label)),
                ["vehicle", "color"]
            )
            appearanceKeys.insert(
                "\(appearance.vehicle.id.rawValue)|\(appearance.color.id.rawValue)"
            )
        }
        XCTAssertEqual(appearanceKeys.count, 32)
        XCTAssertNil(VehicleCatalog.resolve(vehicleID: "unknown", colorID: "aurora-mint"))
        XCTAssertNil(VehicleCatalog.resolve(vehicleID: "rally", colorID: "unknown"))
    }

    func testVehicleSelectionCodableRoundTripKeepsStableIDs() throws {
        let selection = VehicleSelection(vehicleID: .angular, colorID: .emberGold)
        let data = try JSONEncoder().encode(selection)

        XCTAssertEqual(try JSONDecoder().decode(VehicleSelection.self, from: data), selection)
    }
}
