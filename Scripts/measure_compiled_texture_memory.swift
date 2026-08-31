#!/usr/bin/env -S xcrun swift

import Foundation
import ImageIO

private let allocationLimit = 112 * 1_024 * 1_024
private let pageDimensionLimit = 2_048
private let expectedEnvironmentAllocation = 36 * 1_024 * 1_024
private let expectedAtlasPages = Set([
    "Environment.atlasc/Environment.1.png",
    "Obstacles.atlasc/Obstacles.1.png",
    "Vehicles.atlasc/Vehicles.1.png",
])
private let backgroundNames = Set(["sky_horizon.png", "asphalt.png"])
private let presentationNames = Set([
    "hub_expressway_portal.png",
    "maintenance_pit_lane.png",
    "rally_hero_paint.png",
    "rally_hero_details_shadow.png",
    "gt_hero_paint.png",
    "gt_hero_details_shadow.png",
    "angular_hero_paint.png",
    "angular_hero_details_shadow.png",
])
private let racing3DNames = Set(["asphalt_normal.png", "asphalt_roughness.png"])
private let expectedEnvironmentNames = Set([
    "ocean_terrain_basecolor.png",
    "ocean_terrain_normal.png",
    "ocean_terrain_roughness.png",
    "alpine_terrain_basecolor.png",
    "alpine_terrain_normal.png",
    "alpine_terrain_roughness.png",
    "desert_terrain_basecolor.png",
    "desert_terrain_normal.png",
    "desert_terrain_roughness.png",
])
private let metadataExtensions = Set(["plist", "json", "strings", "car"])

enum Family: String, CaseIterable {
    case compiledAtlasPages = "compiled-atlas-pages"
    case backgrounds = "backgrounds-standalone"
    case presentation = "presentation-standalone"
    case racing3D = "racing3d-standalone-pbr"
    case racingEnvironment3D = "racing-environment3d-runtime"
}

struct EnvironmentManifest: Decodable {
    struct Track: Decodable {
        struct Texture: Decodable {
            let filename: String
        }

        let textures: [Texture]
    }

    let tracks: [Track]
}

struct Options {
    let appURL: URL
    let metalAllocationBytes: Int?
    let metalMaximumDimension: Int?
}

struct Page {
    let family: Family
    let url: URL
    let width: Int
    let height: Int

    var allocationBytes: Int {
        width * height * 4
    }
}

private func parseOptions() -> Options {
    let arguments = Array(CommandLine.arguments.dropFirst())
    guard let appPath = arguments.first else {
        fputs(
            "usage: measure_compiled_texture_memory.swift <built.app> "
                + "[--metal-allocation-bytes <bytes> --metal-max-dimension <pixels>]\n",
            stderr
        )
        exit(64)
    }

    var metalBytes: Int?
    var metalDimension: Int?
    var index = 1
    while index < arguments.count {
        guard index + 1 < arguments.count, let value = Int(arguments[index + 1]) else {
            fputs("invalid fallback argument near \(arguments[index])\n", stderr)
            exit(64)
        }
        switch arguments[index] {
        case "--metal-allocation-bytes":
            metalBytes = value
        case "--metal-max-dimension":
            metalDimension = value
        default:
            fputs("unknown argument: \(arguments[index])\n", stderr)
            exit(64)
        }
        index += 2
    }

    return Options(
        appURL: URL(fileURLWithPath: appPath, isDirectory: true),
        metalAllocationBytes: metalBytes,
        metalMaximumDimension: metalDimension
    )
}

private func relativePath(_ url: URL, appURL: URL) -> String {
    url.path.replacingOccurrences(of: appURL.path + "/", with: "")
}

private func isInsideEmbeddedWatchApp(_ url: URL, appURL: URL) -> Bool {
    relativePath(url, appURL: appURL).hasPrefix("Watch/")
}

private func isAtlasPageCandidate(_ url: URL) -> Bool {
    guard url.pathComponents.contains(where: { $0.hasSuffix(".atlasc") }) else {
        return false
    }
    return !metadataExtensions.contains(url.pathExtension.lowercased())
}

private func decodePage(at url: URL, family: Family) -> Page? {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
          let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil)
            as? [CFString: Any],
          let width = properties[kCGImagePropertyPixelWidth] as? Int,
          let height = properties[kCGImagePropertyPixelHeight] as? Int else {
        return nil
    }
    return Page(family: family, url: url, width: width, height: height)
}

private func environmentNames(in appURL: URL) -> Set<String> {
    let manifestURL = appURL.appendingPathComponent("RacingEnvironmentAssetManifest.json")
    guard let data = try? Data(contentsOf: manifestURL),
          let manifest = try? JSONDecoder().decode(EnvironmentManifest.self, from: data) else {
        fputs("FAIL: missing or invalid RacingEnvironmentAssetManifest.json\n", stderr)
        exit(1)
    }
    let names = Set(manifest.tracks.flatMap(\.textures).map(\.filename))
    guard manifest.tracks.count == 3, names == expectedEnvironmentNames else {
        fputs("FAIL: environment manifest must declare the expected three tracks and nine runtime textures\n", stderr)
        exit(1)
    }
    return names
}

private func requireExactNames(
    _ urls: [URL],
    expected: Set<String>,
    family: Family,
    appURL: URL,
    useRelativePaths: Bool = false
) {
    let names = urls.map {
        useRelativePaths ? relativePath($0, appURL: appURL) : $0.lastPathComponent
    }
    guard urls.count == expected.count, Set(names) == expected else {
        let actual = names.sorted().joined(separator: ",")
        fputs(
            "FAIL: family \(family.rawValue) names/count mismatch; actual=[\(actual)]\n",
            stderr
        )
        exit(1)
    }
}

let options = parseOptions()
var isDirectory: ObjCBool = false
guard FileManager.default.fileExists(
    atPath: options.appURL.path,
    isDirectory: &isDirectory
), isDirectory.boolValue else {
    fputs("built app does not exist: \(options.appURL.path)\n", stderr)
    exit(66)
}

let environmentTextureNames = environmentNames(in: options.appURL)
guard let enumerator = FileManager.default.enumerator(
    at: options.appURL,
    includingPropertiesForKeys: [.isRegularFileKey],
    options: [.skipsHiddenFiles]
) else {
    fputs("could not enumerate built app: \(options.appURL.path)\n", stderr)
    exit(74)
}

var candidates = Dictionary(uniqueKeysWithValues: Family.allCases.map { ($0, [URL]()) })
var unexpectedStandalonePNGs: [String] = []
var classifiedPaths = Set<String>()
for case let url as URL in enumerator {
    guard !isInsideEmbeddedWatchApp(url, appURL: options.appURL),
          (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else {
        continue
    }

    let family: Family?
    if isAtlasPageCandidate(url) {
        family = .compiledAtlasPages
    } else if backgroundNames.contains(url.lastPathComponent) {
        family = .backgrounds
    } else if presentationNames.contains(url.lastPathComponent) {
        family = .presentation
    } else if racing3DNames.contains(url.lastPathComponent) {
        family = .racing3D
    } else if environmentTextureNames.contains(url.lastPathComponent) {
        family = .racingEnvironment3D
    } else {
        family = nil
    }

    if let family {
        guard classifiedPaths.insert(url.path).inserted else {
            fputs("FAIL: texture classified more than once: \(url.path)\n", stderr)
            exit(1)
        }
        candidates[family, default: []].append(url)
    } else if url.pathExtension.lowercased() == "png" {
        unexpectedStandalonePNGs.append(relativePath(url, appURL: options.appURL))
    }
}

guard unexpectedStandalonePNGs.isEmpty else {
    fputs(
        "FAIL: unclassified standalone PNGs: \(unexpectedStandalonePNGs.sorted().joined(separator: ","))\n",
        stderr
    )
    exit(1)
}

requireExactNames(
    candidates[.compiledAtlasPages, default: []],
    expected: expectedAtlasPages,
    family: .compiledAtlasPages,
    appURL: options.appURL,
    useRelativePaths: true
)
requireExactNames(
    candidates[.backgrounds, default: []],
    expected: backgroundNames,
    family: .backgrounds,
    appURL: options.appURL
)
requireExactNames(
    candidates[.presentation, default: []],
    expected: presentationNames,
    family: .presentation,
    appURL: options.appURL
)
requireExactNames(
    candidates[.racing3D, default: []],
    expected: racing3DNames,
    family: .racing3D,
    appURL: options.appURL
)
requireExactNames(
    candidates[.racingEnvironment3D, default: []],
    expected: expectedEnvironmentNames,
    family: .racingEnvironment3D,
    appURL: options.appURL
)

var decodedPages: [Page] = []
var undecodableAtlasPages: [URL] = []
for family in Family.allCases {
    for candidate in candidates[family, default: []].sorted(by: { $0.path < $1.path }) {
        if let page = decodePage(at: candidate, family: family) {
            decodedPages.append(page)
        } else if family == .compiledAtlasPages {
            undecodableAtlasPages.append(candidate)
        } else {
            fputs("FAIL: standalone runtime texture is not ImageIO-decodable: \(candidate.path)\n", stderr)
            exit(1)
        }
    }
}

var familyAllocations = Dictionary(uniqueKeysWithValues: Family.allCases.map { ($0, 0) })
var familyMaximumDimensions = Dictionary(uniqueKeysWithValues: Family.allCases.map { ($0, 0) })
for page in decodedPages {
    familyAllocations[page.family, default: 0] += page.allocationBytes
    familyMaximumDimensions[page.family, default: 0] = max(
        familyMaximumDimensions[page.family, default: 0],
        page.width,
        page.height
    )
    print(
        "family=\(page.family.rawValue) page=\(relativePath(page.url, appURL: options.appURL)) "
            + "pixels=\(page.width)x\(page.height) allocationBytes=\(page.allocationBytes) decoder=ImageIO"
    )
}

if !undecodableAtlasPages.isEmpty {
    for page in undecodableAtlasPages {
        print(
            "family=\(Family.compiledAtlasPages.rawValue) "
                + "page=\(relativePath(page, appURL: options.appURL)) decoder=unavailable"
        )
    }
    guard let metalAllocation = options.metalAllocationBytes,
          let metalMaximumDimension = options.metalMaximumDimension else {
        fputs(
            "FAIL: GPU-only atlas page detected. Record the compiled-atlas preload/render "
                + "Metal allocated-size delta and maximum texture dimension, then rerun with "
                + "--metal-allocation-bytes and --metal-max-dimension.\n",
            stderr
        )
        exit(2)
    }
    familyAllocations[.compiledAtlasPages] = max(
        familyAllocations[.compiledAtlasPages, default: 0],
        metalAllocation
    )
    familyMaximumDimensions[.compiledAtlasPages] = max(
        familyMaximumDimensions[.compiledAtlasPages, default: 0],
        metalMaximumDimension
    )
    print(
        "family=\(Family.compiledAtlasPages.rawValue) metalFallbackBytes=\(metalAllocation) "
            + "metalFallbackMaxDimension=\(metalMaximumDimension)"
    )
}

guard familyAllocations[.racingEnvironment3D] == expectedEnvironmentAllocation else {
    fputs(
        "FAIL: racing environment family must equal exactly 37748736 decoded bytes\n",
        stderr
    )
    exit(1)
}

let familySum = Family.allCases.reduce(0) { $0 + familyAllocations[$1, default: 0] }
let measuredAllocation = decodedPages
    .filter { $0.family != .compiledAtlasPages }
    .reduce(familyAllocations[.compiledAtlasPages, default: 0]) { $0 + $1.allocationBytes }
let measuredMaximumDimension = Family.allCases.reduce(0) {
    max($0, familyMaximumDimensions[$1, default: 0])
}
guard familySum == measuredAllocation else {
    fputs("FAIL: family allocation sum does not equal total allocation\n", stderr)
    exit(1)
}

for family in Family.allCases {
    let bytes = familyAllocations[family, default: 0]
    print(
        "familySummary name=\(family.rawValue) count=\(candidates[family, default: []].count) "
            + "allocationBytes=\(bytes) "
            + String(format: "allocationMiB=%.2f", Double(bytes) / 1_048_576.0)
    )
}

let allocationPass = measuredAllocation <= allocationLimit
let dimensionPass = measuredMaximumDimension <= pageDimensionLimit
let result = allocationPass && dimensionPass ? "PASS" : "FAIL"
print(
    "summary familySumBytes=\(familySum) totalAllocationBytes=\(measuredAllocation) "
        + "maxDimension=\(measuredMaximumDimension) "
        + String(format: "allocationMiB=%.2f", Double(measuredAllocation) / 1_048_576.0)
        + " limitMiB=112 environmentMiB=36 result=\(result)"
)

if !allocationPass || !dimensionPass {
    exit(1)
}
