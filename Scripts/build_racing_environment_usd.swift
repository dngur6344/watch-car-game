#!/usr/bin/env swift

import Foundation

private let toolVersion = "1.1.0"
private let revision = 2
private let packageTimestamp = Date(timeIntervalSince1970: 1_788_048_000)

private struct V3 {
    let x: Double
    let y: Double
    let z: Double

    var usd: String {
        "(\(decimal(x)), \(decimal(y)), \(decimal(z)))"
    }
}

private struct MaterialSpec {
    let name: String
    let color: V3
    let roughness: Double
}

private struct TrackSpec {
    let slug: String
    let trackID: String
    let baseRoot: String
    let enhancedRoot: String
    let variants: [String]
    let hero: String
    let ridgeProfile: [Double]
    let materials: [MaterialSpec]
}

private enum BuildError: Error, CustomStringConvertible {
    case usage
    case missingFile(URL)
    case unexpectedContents(URL)
    case packagingFailed(filename: String, status: Int32)

    var description: String {
        switch self {
        case .usage:
            return "usage: build_racing_environment_usd.swift [build|validate|package] <output-directory>"
        case let .missingFile(url):
            return "missing generated USDA: \(url.path)"
        case let .unexpectedContents(url):
            return "generated USDA does not match deterministic authoring output: \(url.path)"
        case let .packagingFailed(filename, status):
            return "usdzip compliance packaging failed for \(filename) with status \(status)"
        }
    }
}

private let tracks = [
    TrackSpec(
        slug: "ocean",
        trackID: "coastal",
        baseRoot: "OceanEnvironmentBase",
        enhancedRoot: "OceanEnvironmentEnhanced",
        variants: [
            "Coastal_ShorelineRock",
            "Coastal_PalmGrove",
            "Coastal_CliffOutcrop",
            "Coastal_SeaStack",
        ],
        hero: "Coastal_CliffCove_Hero",
        ridgeProfile: [0.03, 0.19, 0.53, 0.42, 0.88, 0.64, 1.00, 0.36, 0.05],
        materials: [
            .init(name: "Terrain", color: .init(x: 0.56, y: 0.43, z: 0.29), roughness: 0.88),
            .init(name: "Rock", color: .init(x: 0.64, y: 0.59, z: 0.48), roughness: 0.82),
            .init(name: "Vegetation", color: .init(x: 0.17, y: 0.31, z: 0.22), roughness: 0.91),
            .init(name: "Accent", color: .init(x: 0.21, y: 0.38, z: 0.39), roughness: 0.73),
        ]
    ),
    TrackSpec(
        slug: "alpine",
        trackID: "alpine",
        baseRoot: "AlpineEnvironmentBase",
        enhancedRoot: "AlpineEnvironmentEnhanced",
        variants: [
            "Alpine_RockOutcrop",
            "Alpine_PineGrove",
            "Alpine_ForestBelt",
            "Alpine_SnowRidge",
        ],
        hero: "Alpine_TunnelPeak_Hero",
        ridgeProfile: [0.04, 0.28, 0.46, 0.91, 0.61, 1.00, 0.73, 0.32, 0.06],
        materials: [
            .init(name: "Terrain", color: .init(x: 0.25, y: 0.27, z: 0.25), roughness: 0.92),
            .init(name: "Rock", color: .init(x: 0.37, y: 0.41, z: 0.43), roughness: 0.86),
            .init(name: "Vegetation", color: .init(x: 0.10, y: 0.24, z: 0.18), roughness: 0.94),
            .init(name: "Accent", color: .init(x: 0.78, y: 0.83, z: 0.82), roughness: 0.70),
        ]
    ),
    TrackSpec(
        slug: "desert",
        trackID: "desert",
        baseRoot: "DesertEnvironmentBase",
        enhancedRoot: "DesertEnvironmentEnhanced",
        variants: [
            "Desert_CactusCluster",
            "Desert_BoulderCluster",
            "Desert_CanyonWall",
            "Desert_Mesa",
        ],
        hero: "Desert_StoneArch_Hero",
        ridgeProfile: [0.05, 0.34, 0.72, 0.58, 0.96, 0.87, 0.48, 0.25, 0.04],
        materials: [
            .init(name: "Terrain", color: .init(x: 0.55, y: 0.27, z: 0.13), roughness: 0.90),
            .init(name: "Rock", color: .init(x: 0.64, y: 0.31, z: 0.16), roughness: 0.85),
            .init(name: "Vegetation", color: .init(x: 0.25, y: 0.34, z: 0.18), roughness: 0.95),
            .init(name: "Accent", color: .init(x: 0.77, y: 0.49, z: 0.21), roughness: 0.81),
        ]
    ),
]

private func decimal(_ value: Double) -> String {
    String(format: "%.5f", locale: Locale(identifier: "en_US_POSIX"), value)
}

private func material(_ spec: MaterialSpec, rootName: String) -> String {
    """
        def Material "\(spec.name)"
        {
            token outputs:surface.connect = </\(rootName)/Materials/\(spec.name)/Surface.outputs:surface>
            def Shader "Surface"
            {
                uniform token info:id = "UsdPreviewSurface"
                color3f inputs:diffuseColor = \(spec.color.usd)
                float inputs:metallic = 0.00000
                float inputs:roughness = \(decimal(spec.roughness))
                token outputs:surface
            }
        }
"""
}

private func mesh(
    name: String,
    points: [V3],
    faceCounts: [Int],
    faceIndices: [Int],
    materialName: String,
    rootName: String,
    role: String,
    topology: String? = nil
) -> String {
    let pointText = points.map(\.usd).joined(separator: ", ")
    let countText = faceCounts.map(String.init).joined(separator: ", ")
    let indexText = faceIndices.map(String.init).joined(separator: ", ")
    let topologyMetadata = topology.map { "\n                        string topology = \"\($0)\"" } ?? ""
    return """
                def Mesh "\(name)" (
                    prepend apiSchemas = ["MaterialBindingAPI"]
                    customData = {
                        string role = "\(role)"\(topologyMetadata)
                    }
                )
                {
                    uniform bool doubleSided = 1
                    int[] faceVertexCounts = [\(countText)]
                    int[] faceVertexIndices = [\(indexText)]
                    rel material:binding = </\(rootName)/Materials/\(materialName)>
                    point3f[] points = [\(pointText)]
                    uniform token subdivisionScheme = "none"
                }
"""
}

private func ridgeMesh(
    name: String,
    profile: [Double],
    width: Double,
    height: Double,
    depth: Double,
    materialName: String,
    rootName: String,
    role: String,
    yOffset: Double = 0,
    xOffset: Double = 0
) -> String {
    let profile = softenedRidgeProfile(profile)
    let zFractions = [-0.50, -0.24, 0.02, 0.29, 0.50]
    let sliceScales = [0.76, 1.04, 0.89, 1.10, 0.71]
    let erosion = [0.00, -0.04, 0.03, -0.10, 0.05, -0.02, 0.02]
    var points: [V3] = []
    for (zIndex, zFraction) in zFractions.enumerated() {
        for (xIndex, profileHeight) in profile.enumerated() {
            let xFraction = Double(xIndex) / Double(profile.count - 1) - 0.5
            let notch = erosion[(xIndex + zIndex * 2) % erosion.count]
            let authoredHeight = max(0, profileHeight * sliceScales[zIndex] + notch)
            points.append(
                V3(
                    x: xOffset + xFraction * width,
                    y: yOffset + authoredHeight * height,
                    z: zFraction * depth
                )
            )
        }
    }

    let topPointCount = points.count
    let baseY = min(yOffset - 0.12, -0.12)
    points.append(contentsOf: points.map { point in
        V3(x: point.x, y: baseY, z: point.z)
    })

    var faceCounts: [Int] = []
    var indices: [Int] = []
    for z in 0..<(zFractions.count - 1) {
        for x in 0..<(profile.count - 1) {
            let lower = z * profile.count + x
            let upper = (z + 1) * profile.count + x
            faceCounts.append(4)
            indices.append(contentsOf: [lower, lower + 1, upper + 1, upper])
        }
    }

    let rowWidth = profile.count
    let lastRowOffset = (zFractions.count - 1) * rowWidth

    for z in 0..<(zFractions.count - 1) {
        for x in 0..<(rowWidth - 1) {
            let lower = topPointCount + z * rowWidth + x
            let upper = topPointCount + (z + 1) * rowWidth + x
            faceCounts.append(4)
            indices.append(contentsOf: [lower, upper, upper + 1, lower + 1])
        }
    }

    for x in 0..<(rowWidth - 1) {
        faceCounts.append(4)
        indices.append(contentsOf: [x, topPointCount + x, topPointCount + x + 1, x + 1])

        let back = lastRowOffset + x
        faceCounts.append(4)
        indices.append(contentsOf: [back, back + 1, topPointCount + back + 1, topPointCount + back])
    }

    for z in 0..<(zFractions.count - 1) {
        let left = z * rowWidth
        let nextLeft = (z + 1) * rowWidth
        faceCounts.append(4)
        indices.append(contentsOf: [left, nextLeft, topPointCount + nextLeft, topPointCount + left])

        let right = left + rowWidth - 1
        let nextRight = nextLeft + rowWidth - 1
        faceCounts.append(4)
        indices.append(contentsOf: [right, topPointCount + right, topPointCount + nextRight, nextRight])
    }

    return mesh(
        name: name,
        points: points,
        faceCounts: faceCounts,
        faceIndices: indices,
        materialName: materialName,
        rootName: rootName,
        role: role,
        topology: "closed-volume"
    )
}

private func softenedRidgeProfile(_ source: [Double]) -> [Double] {
    guard source.count > 2 else { return source }
    let softened = source.indices.map { index in
        guard index > source.startIndex, index < source.index(before: source.endIndex) else {
            return source[index]
        }
        return source[index - 1] * 0.18 + source[index] * 0.64 + source[index + 1] * 0.18
    }
    let subdivisions = 3
    var result: [Double] = []
    result.reserveCapacity((softened.count - 1) * subdivisions + 1)

    for index in 0..<(softened.count - 1) {
        let previous = softened[max(index - 1, 0)]
        let start = softened[index]
        let end = softened[index + 1]
        let next = softened[min(index + 2, softened.count - 1)]
        for subdivision in 0..<subdivisions {
            let t = Double(subdivision) / Double(subdivisions)
            let t2 = t * t
            let t3 = t2 * t
            let value = 0.5 * (
                2 * start
                    + (-previous + end) * t
                    + (2 * previous - 5 * start + 4 * end - next) * t2
                    + (-previous + 3 * start - 3 * end + next) * t3
            )
            result.append(min(max(value, 0), 1))
        }
    }
    result.append(softened[softened.count - 1])
    return result
}

private func facetedMesh(
    name: String,
    center: V3,
    width: Double,
    height: Double,
    depth: Double,
    materialName: String,
    rootName: String,
    role: String,
    lean: Double = 0
) -> String {
    let sides = 7
    let levels: [(height: Double, radius: Double, offset: Double)] = [
        (0.00, 0.78, 0.00),
        (0.27, 1.00, -0.05),
        (0.61, 0.67, 0.08),
        (0.86, 0.42, -0.03),
        (1.00, 0.12, 0.02),
    ]
    let radialVariation = [1.00, 0.83, 1.08, 0.91, 1.04, 0.79, 0.96]
    var points: [V3] = []
    for level in levels {
        for side in 0..<sides {
            let angle = Double(side) * 2 * Double.pi / Double(sides) + level.offset
            let radius = level.radius * radialVariation[side]
            points.append(
                V3(
                    x: center.x + cos(angle) * width * radius + lean * level.height,
                    y: center.y + height * level.height,
                    z: center.z + sin(angle) * depth * radius
                )
            )
        }
    }

    var counts = [Int](repeating: 4, count: (levels.count - 1) * sides)
    var indices: [Int] = []
    for level in 0..<(levels.count - 1) {
        for side in 0..<sides {
            let next = (side + 1) % sides
            let lower = level * sides
            let upper = (level + 1) * sides
            indices.append(contentsOf: [lower + side, lower + next, upper + next, upper + side])
        }
    }
    counts.append(sides)
    indices.append(contentsOf: (0..<sides).reversed())
    counts.append(sides)
    let top = (levels.count - 1) * sides
    indices.append(contentsOf: (0..<sides).map { top + $0 })
    return mesh(
        name: name,
        points: points,
        faceCounts: counts,
        faceIndices: indices,
        materialName: materialName,
        rootName: rootName,
        role: role
    )
}

private func bladeMesh(
    name: String,
    start: V3,
    end: V3,
    halfWidth: Double,
    materialName: String,
    rootName: String,
    role: String
) -> String {
    let points = [
        V3(x: start.x - halfWidth, y: start.y, z: start.z),
        V3(x: start.x + halfWidth, y: start.y, z: start.z),
        V3(x: end.x + halfWidth * 0.38, y: end.y, z: end.z),
        V3(x: end.x - halfWidth * 0.38, y: end.y, z: end.z),
    ]
    return mesh(
        name: name,
        points: points,
        faceCounts: [4],
        faceIndices: [0, 1, 2, 3],
        materialName: materialName,
        rootName: rootName,
        role: role
    )
}

private func archCrownMesh(
    name: String,
    apertureWidth: Double,
    centerHeight: Double,
    depth: Double,
    materialName: String,
    rootName: String
) -> String {
    let segmentCount = 10
    let innerRadius = apertureWidth / 2
    let thickness = 2.4
    let variations = [0.00, 0.12, -0.08, 0.18, -0.04, 0.09, -0.13, 0.15, -0.06, 0.10, 0.00]
    var points: [V3] = []
    for segment in 0...segmentCount {
        let angle = Double.pi - Double(segment) * Double.pi / Double(segmentCount)
        let irregularity = variations[segment]
        for z in [-depth / 2, depth / 2] {
            let inner = innerRadius + irregularity
            let outer = innerRadius + thickness + irregularity * 0.55
            points.append(V3(x: cos(angle) * inner, y: centerHeight + sin(angle) * inner, z: z))
            points.append(V3(x: cos(angle) * outer, y: centerHeight + sin(angle) * outer, z: z))
        }
    }

    var counts: [Int] = []
    var indices: [Int] = []
    for segment in 0..<segmentCount {
        let a = segment * 4
        let b = (segment + 1) * 4
        counts.append(contentsOf: [4, 4, 4, 4])
        indices.append(contentsOf: [a, b, b + 1, a + 1])
        indices.append(contentsOf: [a + 2, a + 3, b + 3, b + 2])
        indices.append(contentsOf: [a + 1, b + 1, b + 3, a + 3])
        indices.append(contentsOf: [a, a + 2, b + 2, b])
    }
    return mesh(
        name: name,
        points: points,
        faceCounts: counts,
        faceIndices: indices,
        materialName: materialName,
        rootName: rootName,
        role: "hero-arch-crown"
    )
}

private func variantEntity(
    name: String,
    role: String,
    contents: String,
    roadClearance: Double = 6
) -> String {
    """
            def Xform "\(name)"
            (
                customData = {
                    string assetRole = "\(role)"
                    double roadClearanceHalfWidth = \(decimal(roadClearance))
                }
            )
            {
\(contents)
            }
"""
}

private func heroEntity(spec: TrackSpec, rootName: String, tier: String) -> String {
    let aperture = 14.0
    let pillarMaterial = spec.slug == "alpine" ? "Rock" : "Terrain"
    let accentMaterial = spec.slug == "alpine" ? "Accent" : "Rock"
    let left = facetedMesh(
        name: "LeftErodedButtress",
        center: .init(x: -10.0, y: 0, z: 0),
        width: 2.0,
        height: spec.slug == "alpine" ? 12.5 : 10.8,
        depth: 2.7,
        materialName: pillarMaterial,
        rootName: rootName,
        role: "hero-buttress",
        lean: 0.25
    )
    let right = facetedMesh(
        name: "RightErodedButtress",
        center: .init(x: 10.0, y: 0, z: 0.35),
        width: 2.2,
        height: spec.slug == "alpine" ? 11.8 : 10.2,
        depth: 2.9,
        materialName: pillarMaterial,
        rootName: rootName,
        role: "hero-buttress",
        lean: -0.18
    )
    let crown = archCrownMesh(
        name: spec.slug == "alpine" ? "TunnelPeakFrame" : "NaturalStoneCrown",
        apertureWidth: aperture,
        centerHeight: 1.2,
        depth: 4.2,
        materialName: accentMaterial,
        rootName: rootName
    )
    let distantProfile = spec.ridgeProfile.enumerated().map { index, value in
        min(1.0, value * (index.isMultiple(of: 2) ? 0.92 : 1.08))
    }
    let backdropName = spec.slug == "ocean"
        ? "CliffCoveBackdrop"
        : (spec.slug == "alpine" ? "PrincipalPeakBackdrop" : "TwinMesaBackdrop")
    let leftRidge = ridgeMesh(
        name: "\(backdropName)Left",
        profile: distantProfile,
        width: 20,
        height: spec.slug == "alpine" ? 22 : 15,
        depth: 8,
        materialName: pillarMaterial,
        rootName: rootName,
        role: "hero-backdrop",
        yOffset: -0.2,
        xOffset: -18
    )
    let rightRidge = ridgeMesh(
        name: "\(backdropName)Right",
        profile: Array(distantProfile.reversed()),
        width: 20,
        height: spec.slug == "alpine" ? 20 : 14,
        depth: 8,
        materialName: pillarMaterial,
        rootName: rootName,
        role: "hero-backdrop",
        yOffset: -0.2,
        xOffset: 18
    )
    return """
        def Xform "Hero"
        (
            customData = {
                string role = "persistent-hero-root"
            }
        )
        {
            def Xform "\(spec.hero)"
            (
                customData = {
                    double roadApertureWidth = \(decimal(aperture))
                    double roadClearanceHalfWidth = 6.00000
                    string role = "hero-vista"
                    string tier = "\(tier)"
                }
            )
            {
\(left)
\(right)
\(crown)
\(leftRidge)
\(rightRidge)
            }
        }
"""
}

private func oceanVariant(
    _ index: Int,
    spec: TrackSpec,
    rootName: String,
    enhanced: Bool
) -> String {
    switch index {
    case 0:
        let rocks = [
            facetedMesh(name: "WeatheredRockA", center: .init(x: -0.8, y: 0, z: 0.2), width: 1.1, height: 1.7, depth: 0.9, materialName: "Rock", rootName: rootName, role: "shoreline-rock", lean: 0.16),
            facetedMesh(name: "WeatheredRockB", center: .init(x: 0.9, y: 0, z: -0.3), width: 0.8, height: 1.2, depth: 0.7, materialName: "Accent", rootName: rootName, role: "shoreline-rock", lean: -0.12),
        ]
        return variantEntity(name: spec.variants[index], role: "foreground-variant", contents: rocks.joined(separator: "\n"))
    case 1:
        var pieces = [
            facetedMesh(name: "WindBentTrunk", center: .init(x: 0, y: 0, z: 0), width: 0.32, height: 5.8, depth: 0.29, materialName: "Terrain", rootName: rootName, role: "palm-trunk", lean: 0.85),
        ]
        let frondCount = enhanced ? 8 : 5
        for index in 0..<frondCount {
            let angle = Double(index) * 2 * Double.pi / Double(frondCount)
            pieces.append(
                bladeMesh(
                    name: "WindFrond\(index + 1)",
                    start: .init(x: 0.76, y: 5.6, z: 0),
                    end: .init(x: 0.76 + cos(angle) * 2.5, y: 5.25 + Double(index % 2) * 0.22, z: sin(angle) * 2.0),
                    halfWidth: 0.32,
                    materialName: "Vegetation",
                    rootName: rootName,
                    role: "wind-frond"
                )
            )
        }
        return variantEntity(name: spec.variants[index], role: "foreground-variant", contents: pieces.joined(separator: "\n"))
    case 2:
        return variantEntity(
            name: spec.variants[index],
            role: "midground-variant",
            contents: ridgeMesh(name: "UndercutCliff", profile: spec.ridgeProfile, width: enhanced ? 15 : 12, height: enhanced ? 9 : 7, depth: 5.2, materialName: "Terrain", rootName: rootName, role: "eroded-cliff")
        )
    default:
        let stack = facetedMesh(name: "AsymmetricSeaStack", center: .init(x: 0, y: 0, z: 0), width: 3.2, height: enhanced ? 13 : 10, depth: 2.6, materialName: "Rock", rootName: rootName, role: "far-sea-stack", lean: 0.65)
        return variantEntity(name: spec.variants[index], role: "far-variant", contents: stack)
    }
}

private func pineGrove(
    name: String,
    rootName: String,
    count: Int,
    role: String
) -> String {
    var pieces: [String] = []
    for index in 0..<count {
        let x = Double(index) * 1.45 - Double(count - 1) * 0.72
        let height = 4.2 + Double((index * 7) % 3) * 0.65
        pieces.append(facetedMesh(name: "FacetedTrunk\(index + 1)", center: .init(x: x, y: 0, z: Double(index % 2) * 0.55), width: 0.24, height: height * 0.62, depth: 0.22, materialName: "Terrain", rootName: rootName, role: "pine-trunk", lean: index.isMultiple(of: 2) ? 0.08 : -0.06))
        pieces.append(facetedMesh(name: "IrregularCrown\(index + 1)", center: .init(x: x, y: height * 0.28, z: Double(index % 2) * 0.55), width: 1.25, height: height * 0.72, depth: 1.05, materialName: "Vegetation", rootName: rootName, role: "pine-crown", lean: index.isMultiple(of: 2) ? -0.13 : 0.16))
    }
    return variantEntity(name: name, role: role, contents: pieces.joined(separator: "\n"))
}

private func alpineVariant(
    _ index: Int,
    spec: TrackSpec,
    rootName: String,
    enhanced: Bool
) -> String {
    switch index {
    case 0:
        let rockCount = enhanced ? 4 : 3
        var pieces: [String] = []
        for rock in 0..<rockCount {
            let center = V3(
                x: Double(rock) * 1.2 - 1.3,
                y: 0,
                z: Double(rock % 2) * 0.5
            )
            pieces.append(
                facetedMesh(
                    name: "FracturedGranite\(rock + 1)",
                    center: center,
                    width: 1.0 - Double(rock) * 0.08,
                    height: 2.4 + Double(rock % 2) * 0.8,
                    depth: 0.9,
                    materialName: rock == 2 ? "Accent" : "Rock",
                    rootName: rootName,
                    role: "fractured-outcrop",
                    lean: Double(rock - 1) * 0.12
                )
            )
        }
        return variantEntity(name: spec.variants[index], role: "foreground-variant", contents: pieces.joined(separator: "\n"))
    case 1:
        return pineGrove(name: spec.variants[index], rootName: rootName, count: enhanced ? 5 : 3, role: "foreground-variant")
    case 2:
        return pineGrove(name: spec.variants[index], rootName: rootName, count: enhanced ? 8 : 5, role: "midground-variant")
    default:
        return variantEntity(
            name: spec.variants[index],
            role: "far-variant",
            contents: ridgeMesh(
                name: "FracturedMountainRange",
                profile: spec.ridgeProfile,
                width: enhanced ? 24 : 20,
                height: enhanced ? 17 : 14,
                depth: 6.5,
                materialName: "Rock",
                rootName: rootName,
                role: "far-snow-ridge"
            )
        )
    }
}

private func cactusCluster(name: String, rootName: String, enhanced: Bool) -> String {
    var pieces = [
        facetedMesh(name: "CactusMain", center: .init(x: 0, y: 0, z: 0), width: 0.42, height: 4.8, depth: 0.38, materialName: "Vegetation", rootName: rootName, role: "cactus-stem", lean: 0.12),
        facetedMesh(name: "CactusArmLeft", center: .init(x: -0.65, y: 1.35, z: 0.02), width: 0.28, height: 2.2, depth: 0.25, materialName: "Vegetation", rootName: rootName, role: "cactus-arm", lean: 0.62),
        facetedMesh(name: "CactusArmRight", center: .init(x: 0.72, y: 1.9, z: -0.08), width: 0.25, height: 1.7, depth: 0.23, materialName: "Vegetation", rootName: rootName, role: "cactus-arm", lean: -0.52),
    ]
    if enhanced {
        pieces.append(facetedMesh(name: "YoungCactus", center: .init(x: 1.45, y: 0, z: 0.75), width: 0.24, height: 2.1, depth: 0.22, materialName: "Vegetation", rootName: rootName, role: "cactus-stem", lean: -0.08))
    }
    return variantEntity(name: name, role: "foreground-variant", contents: pieces.joined(separator: "\n"))
}

private func desertVariant(
    _ index: Int,
    spec: TrackSpec,
    rootName: String,
    enhanced: Bool
) -> String {
    switch index {
    case 0:
        return cactusCluster(name: spec.variants[index], rootName: rootName, enhanced: enhanced)
    case 1:
        let rockCount = enhanced ? 5 : 3
        var pieces: [String] = []
        for rock in 0..<rockCount {
            let center = V3(
                x: Double(rock) * 1.25 - 1.5,
                y: 0,
                z: Double((rock * 3) % 2) * 0.65
            )
            pieces.append(
                facetedMesh(
                    name: "WindCutBoulder\(rock + 1)",
                    center: center,
                    width: 1.15 - Double(rock % 3) * 0.14,
                    height: 1.6 + Double(rock % 2) * 0.55,
                    depth: 0.95,
                    materialName: rock.isMultiple(of: 2) ? "Rock" : "Accent",
                    rootName: rootName,
                    role: "wind-cut-boulder",
                    lean: Double(rock - 2) * 0.09
                )
            )
        }
        return variantEntity(name: spec.variants[index], role: "foreground-variant", contents: pieces.joined(separator: "\n"))
    case 2:
        return variantEntity(name: spec.variants[index], role: "midground-variant", contents: ridgeMesh(name: "LayeredCanyonWall", profile: spec.ridgeProfile, width: enhanced ? 20 : 16, height: enhanced ? 10 : 8, depth: 6, materialName: "Rock", rootName: rootName, role: "eroded-canyon-wall"))
    default:
        let mesaProfile = spec.ridgeProfile.map { min($0, 0.72) }
        return variantEntity(name: spec.variants[index], role: "far-variant", contents: ridgeMesh(name: "AsymmetricPlateau", profile: mesaProfile, width: enhanced ? 25 : 21, height: enhanced ? 13 : 11, depth: 8, materialName: "Terrain", rootName: rootName, role: "far-mesa"))
    }
}

private func variant(_ index: Int, spec: TrackSpec, rootName: String, enhanced: Bool) -> String {
    switch spec.slug {
    case "ocean":
        return oceanVariant(index, spec: spec, rootName: rootName, enhanced: enhanced)
    case "alpine":
        return alpineVariant(index, spec: spec, rootName: rootName, enhanced: enhanced)
    default:
        return desertVariant(index, spec: spec, rootName: rootName, enhanced: enhanced)
    }
}

private func layer(
    name: String,
    role: String,
    indices: [Int],
    spec: TrackSpec,
    rootName: String,
    enhanced: Bool
) -> String {
    let variants = indices.map { variant($0, spec: spec, rootName: rootName, enhanced: enhanced) }
        .joined(separator: "\n")
    return """
        def Xform "\(name)"
        (
            customData = {
                string distanceLayer = "\(role)"
                string role = "lod-root"
            }
        )
        {
            def Xform "Variants"
            (
                customData = {
                    string role = "variant-root"
                }
            )
            {
\(variants)
            }
        }
"""
}

private func document(for spec: TrackSpec, tier: String) -> String {
    let enhanced = tier == "enhanced"
    let rootName = enhanced ? spec.enhancedRoot : spec.baseRoot
    let materialText = spec.materials.map { material($0, rootName: rootName) }
        .joined(separator: "\n")
    let foreground = layer(name: "ForegroundLOD", role: "foreground", indices: [0, 1], spec: spec, rootName: rootName, enhanced: enhanced)
    let midground = layer(name: "MidgroundLOD", role: "midground", indices: [2], spec: spec, rootName: rootName, enhanced: enhanced)
    let far = layer(name: "FarLOD", role: "far", indices: [3], spec: spec, rootName: rootName, enhanced: enhanced)
    let hero = heroEntity(spec: spec, rootName: rootName, tier: tier)
    return """
#usda 1.0
(
    defaultPrim = "\(rootName)"
    metersPerUnit = 1
    upAxis = "Y"
)

def Xform "\(rootName)"
(
    customData = {
        string authoringTool = "Scripts/build_racing_environment_usd.swift@\(toolVersion)"
        string license = "project-original"
        int revision = \(revision)
        double roadApertureWidth = 14.00000
        double roadClearanceHalfWidth = 6.00000
        string role = "racing-environment-pack"
        string tier = "\(tier)"
        string track = "\(spec.trackID)"
    }
)
{
    def Scope "Materials"
    {
\(materialText)
    }

\(foreground)

\(midground)

\(far)

\(hero)
}
""" + "\n"
}

private func expectedDocuments() -> [(filename: String, contents: String)] {
    tracks.flatMap { spec in
        ["base", "enhanced"].map { tier in
            ("\(spec.slug)_environment_\(tier).usda", document(for: spec, tier: tier))
        }
    }
}

private func build(to outputDirectory: URL) throws {
    try FileManager.default.createDirectory(
        at: outputDirectory,
        withIntermediateDirectories: true
    )
    for output in expectedDocuments() {
        let url = outputDirectory.appendingPathComponent(output.filename)
        try Data(output.contents.utf8).write(to: url, options: .atomic)
        print("wrote \(url.path)")
    }
}

private func validate(in outputDirectory: URL) throws {
    for output in expectedDocuments() {
        let url = outputDirectory.appendingPathComponent(output.filename)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw BuildError.missingFile(url)
        }
        guard try Data(contentsOf: url) == Data(output.contents.utf8) else {
            throw BuildError.unexpectedContents(url)
        }
        let requiredNames = ["ForegroundLOD", "MidgroundLOD", "FarLOD", "Variants", "Hero"]
        guard requiredNames.allSatisfy({ output.contents.contains("\"\($0)\"") }) else {
            throw BuildError.unexpectedContents(url)
        }
        print("validated \(url.path)")
    }
}

private func package(in outputDirectory: URL) throws {
    try validate(in: outputDirectory)
    for output in expectedDocuments() {
        let sourceURL = outputDirectory.appendingPathComponent(output.filename)
        let packageFilename = sourceURL.deletingPathExtension().lastPathComponent + ".usdz"
        let packageURL = outputDirectory.appendingPathComponent(packageFilename)
        if FileManager.default.fileExists(atPath: packageURL.path) {
            try FileManager.default.removeItem(at: packageURL)
        }
        try FileManager.default.setAttributes(
            [.modificationDate: packageTimestamp],
            ofItemAtPath: sourceURL.path
        )

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/usdzip")
        process.arguments = ["--checkCompliance", packageFilename, output.filename]
        process.currentDirectoryURL = outputDirectory
        var environment = ProcessInfo.processInfo.environment
        environment["TZ"] = "UTC"
        process.environment = environment
        try process.run()
        process.waitUntilExit()
        guard process.terminationReason == .exit, process.terminationStatus == 0 else {
            throw BuildError.packagingFailed(
                filename: packageFilename,
                status: process.terminationStatus
            )
        }
        print("wrote compliant deterministic package \(packageURL.path)")
    }
}

do {
    let arguments = Array(CommandLine.arguments.dropFirst())
    let mode: String
    let outputPath: String
    if arguments.count == 1 {
        mode = "build"
        outputPath = arguments[0]
    } else if arguments.count == 2, ["build", "validate", "package"].contains(arguments[0]) {
        mode = arguments[0]
        outputPath = arguments[1]
    } else {
        throw BuildError.usage
    }

    let outputDirectory = URL(fileURLWithPath: outputPath, isDirectory: true)
    if mode == "build" {
        try build(to: outputDirectory)
    } else if mode == "validate" {
        try validate(in: outputDirectory)
    } else {
        try package(in: outputDirectory)
    }
} catch {
    fputs("error: \(error)\n", stderr)
    exit(1)
}
