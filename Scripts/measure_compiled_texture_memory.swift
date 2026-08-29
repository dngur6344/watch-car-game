#!/usr/bin/env -S xcrun swift

import Foundation
import ImageIO

private let allocationLimit = 64 * 1_024 * 1_024
private let pageDimensionLimit = 2_048
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
private let metadataExtensions = Set(["plist", "json", "strings", "car"])

struct Options {
    let appURL: URL
    let metalAllocationBytes: Int?
    let metalMaximumDimension: Int?
}

struct Page {
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

private func isInsideEmbeddedWatchApp(_ url: URL, appURL: URL) -> Bool {
    let relative = url.path.replacingOccurrences(of: appURL.path + "/", with: "")
    return relative.hasPrefix("Watch/")
}

private func isAtlasPageCandidate(_ url: URL) -> Bool {
    let components = url.pathComponents
    guard components.contains(where: { $0.hasSuffix(".atlasc") }) else {
        return false
    }
    return !metadataExtensions.contains(url.pathExtension.lowercased())
}

private func decodePage(at url: URL) -> Page? {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
          let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil)
            as? [CFString: Any],
          let width = properties[kCGImagePropertyPixelWidth] as? Int,
          let height = properties[kCGImagePropertyPixelHeight] as? Int else {
        return nil
    }
    return Page(url: url, width: width, height: height)
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

guard let enumerator = FileManager.default.enumerator(
    at: options.appURL,
    includingPropertiesForKeys: [.isRegularFileKey],
    options: [.skipsHiddenFiles]
) else {
    fputs("could not enumerate built app: \(options.appURL.path)\n", stderr)
    exit(74)
}

var atlasCandidates: [URL] = []
var backgroundCandidates: [URL] = []
var presentationCandidates: [URL] = []
for case let url as URL in enumerator {
    guard !isInsideEmbeddedWatchApp(url, appURL: options.appURL),
          (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else {
        continue
    }
    if isAtlasPageCandidate(url) {
        atlasCandidates.append(url)
    } else if backgroundNames.contains(url.lastPathComponent) {
        backgroundCandidates.append(url)
    } else if presentationNames.contains(url.lastPathComponent) {
        presentationCandidates.append(url)
    }
}

guard !atlasCandidates.isEmpty else {
    fputs("FAIL: no compiled atlas pages found in the iOS app\n", stderr)
    exit(1)
}
guard Set(backgroundCandidates.map(\.lastPathComponent)) == backgroundNames else {
    fputs("FAIL: standalone sky_horizon.png and asphalt.png must both be present\n", stderr)
    exit(1)
}
guard Set(presentationCandidates.map(\.lastPathComponent)) == presentationNames else {
    fputs("FAIL: all eight standalone presentation PNGs must be present exactly once\n", stderr)
    exit(1)
}

let candidates = (
    atlasCandidates + backgroundCandidates + presentationCandidates
).sorted { $0.path < $1.path }
var decodedPages: [Page] = []
var undecodablePages: [URL] = []
for candidate in candidates {
    if let page = decodePage(at: candidate) {
        decodedPages.append(page)
    } else {
        undecodablePages.append(candidate)
    }
}

let imageIOAllocation = decodedPages.reduce(0) { $0 + $1.allocationBytes }
let imageIOMaximumDimension = decodedPages.reduce(0) {
    max($0, $1.width, $1.height)
}

for page in decodedPages {
    let relative = page.url.path.replacingOccurrences(of: options.appURL.path + "/", with: "")
    print(
        "page=\(relative) pixels=\(page.width)x\(page.height) "
            + "allocationBytes=\(page.allocationBytes) decoder=ImageIO"
    )
}

var measuredAllocation = imageIOAllocation
var measuredMaximumDimension = imageIOMaximumDimension
if !undecodablePages.isEmpty {
    for page in undecodablePages {
        let relative = page.path.replacingOccurrences(of: options.appURL.path + "/", with: "")
        print("page=\(relative) decoder=unavailable")
    }
    guard let metalAllocation = options.metalAllocationBytes,
          let metalMaximumDimension = options.metalMaximumDimension else {
        fputs(
            "FAIL: GPU-only atlas page detected. Record the preload/render Metal "
                + "allocated-size delta and maximum texture dimension, then rerun with "
                + "--metal-allocation-bytes and --metal-max-dimension.\n",
            stderr
        )
        exit(2)
    }
    measuredAllocation = max(imageIOAllocation, metalAllocation)
    measuredMaximumDimension = max(imageIOMaximumDimension, metalMaximumDimension)
    print(
        "metalFallbackBytes=\(metalAllocation) "
            + "metalFallbackMaxDimension=\(metalMaximumDimension)"
    )
}

let allocationPass = measuredAllocation <= allocationLimit
let dimensionPass = measuredMaximumDimension <= pageDimensionLimit
let result = allocationPass && dimensionPass ? "PASS" : "FAIL"
let mib = Double(measuredAllocation) / 1_048_576.0
print(
    "summary compiledAtlasPages=\(atlasCandidates.count) "
        + "standaloneBackgrounds=\(backgroundCandidates.count) "
        + "standalonePresentation=\(presentationCandidates.count) "
        + "maxDimension=\(measuredMaximumDimension) "
        + "allocationBytes=\(measuredAllocation) "
        + String(format: "allocationMiB=%.2f", mib)
        + " limitMiB=64 result=\(result)"
)

if !allocationPass || !dimensionPass {
    exit(1)
}
