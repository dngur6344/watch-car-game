#!/usr/bin/env swift

import Foundation

private struct V3 {
    let x: Double
    let y: Double
    let z: Double

    var usd: String { "(\(format(x)), \(format(y)), \(format(z)))" }
}

private struct BodyProfile {
    let z: Double
    let halfWidth: Double
    let bottom: Double
    let shoulder: Double
    let top: Double
}

private enum AeroStyle {
    case rallyWing
    case ducktail
    case bladeWing
    case subtleLip
}

private enum LampStyle {
    case rallyBlocks
    case continuousBar
    case segmentedBlade
    case sedan
}

private struct VehicleSpec {
    let filename: String
    let rootName: String
    let profiles: [BodyProfile]
    let canopyProfiles: [BodyProfile]
    let wheelX: Double
    let frontWheelZ: Double
    let rearWheelZ: Double
    let frontWheelRadius: Double
    let rearWheelRadius: Double
    let aero: AeroStyle
    let lamps: LampStyle
    let accentColor: V3
    let heroDetail: Bool
    let roofScoop: Bool
}

private let outputDirectory: URL = {
    guard CommandLine.arguments.count == 2 else {
        fputs("usage: build_production_racing_usd.swift <output-directory>\n", stderr)
        exit(64)
    }
    return URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
}()

private let vehicles: [VehicleSpec] = [
    VehicleSpec(
        filename: "rally_racer.usda",
        rootName: "RallyRacer",
        profiles: [
            .init(z: -1.43, halfWidth: 0.50, bottom: 0.18, shoulder: 0.48, top: 0.54),
            .init(z: -1.14, halfWidth: 0.72, bottom: 0.16, shoulder: 0.63, top: 0.69),
            .init(z: -0.72, halfWidth: 0.79, bottom: 0.15, shoulder: 0.68, top: 0.74),
            .init(z: 0.34, halfWidth: 0.81, bottom: 0.15, shoulder: 0.69, top: 0.75),
            .init(z: 0.92, halfWidth: 0.79, bottom: 0.16, shoulder: 0.67, top: 0.72),
            .init(z: 1.33, halfWidth: 0.71, bottom: 0.18, shoulder: 0.58, top: 0.63),
            .init(z: 1.47, halfWidth: 0.58, bottom: 0.21, shoulder: 0.50, top: 0.54),
        ],
        canopyProfiles: [
            .init(z: -0.57, halfWidth: 0.53, bottom: 0.70, shoulder: 0.88, top: 0.99),
            .init(z: -0.31, halfWidth: 0.57, bottom: 0.72, shoulder: 1.00, top: 1.08),
            .init(z: 0.47, halfWidth: 0.58, bottom: 0.72, shoulder: 1.01, top: 1.09),
            .init(z: 0.76, halfWidth: 0.51, bottom: 0.70, shoulder: 0.89, top: 0.99),
        ],
        wheelX: 0.80,
        frontWheelZ: -0.90,
        rearWheelZ: 0.91,
        frontWheelRadius: 0.32,
        rearWheelRadius: 0.32,
        aero: .rallyWing,
        lamps: .rallyBlocks,
        accentColor: V3(x: 0.98, y: 0.31, z: 0.04),
        heroDetail: true,
        roofScoop: true
    ),
    VehicleSpec(
        filename: "gt_racer.usda",
        rootName: "GTRacer",
        profiles: [
            .init(z: -1.72, halfWidth: 0.43, bottom: 0.15, shoulder: 0.37, top: 0.40),
            .init(z: -1.42, halfWidth: 0.69, bottom: 0.13, shoulder: 0.50, top: 0.55),
            .init(z: -0.88, halfWidth: 0.78, bottom: 0.12, shoulder: 0.59, top: 0.65),
            .init(z: 0.38, halfWidth: 0.82, bottom: 0.12, shoulder: 0.63, top: 0.69),
            .init(z: 1.02, halfWidth: 0.80, bottom: 0.13, shoulder: 0.60, top: 0.66),
            .init(z: 1.50, halfWidth: 0.70, bottom: 0.16, shoulder: 0.51, top: 0.56),
            .init(z: 1.67, halfWidth: 0.57, bottom: 0.19, shoulder: 0.45, top: 0.49),
        ],
        canopyProfiles: [
            .init(z: -0.67, halfWidth: 0.50, bottom: 0.64, shoulder: 0.79, top: 0.88),
            .init(z: -0.34, halfWidth: 0.57, bottom: 0.66, shoulder: 0.91, top: 1.00),
            .init(z: 0.48, halfWidth: 0.59, bottom: 0.67, shoulder: 0.92, top: 1.01),
            .init(z: 0.85, halfWidth: 0.51, bottom: 0.64, shoulder: 0.79, top: 0.88),
        ],
        wheelX: 0.79,
        frontWheelZ: -1.08,
        rearWheelZ: 1.08,
        frontWheelRadius: 0.30,
        rearWheelRadius: 0.32,
        aero: .ducktail,
        lamps: .continuousBar,
        accentColor: V3(x: 0.08, y: 0.82, z: 0.94),
        heroDetail: true,
        roofScoop: false
    ),
    VehicleSpec(
        filename: "angular_racer.usda",
        rootName: "AngularRacer",
        profiles: [
            .init(z: -1.58, halfWidth: 0.36, bottom: 0.15, shoulder: 0.31, top: 0.34),
            .init(z: -1.27, halfWidth: 0.73, bottom: 0.13, shoulder: 0.48, top: 0.53),
            .init(z: -0.67, halfWidth: 0.82, bottom: 0.12, shoulder: 0.61, top: 0.68),
            .init(z: 0.46, halfWidth: 0.84, bottom: 0.12, shoulder: 0.65, top: 0.71),
            .init(z: 1.08, halfWidth: 0.81, bottom: 0.14, shoulder: 0.61, top: 0.67),
            .init(z: 1.48, halfWidth: 0.64, bottom: 0.18, shoulder: 0.49, top: 0.54),
        ],
        canopyProfiles: [
            .init(z: -0.62, halfWidth: 0.47, bottom: 0.67, shoulder: 0.79, top: 0.86),
            .init(z: -0.30, halfWidth: 0.57, bottom: 0.69, shoulder: 0.94, top: 1.01),
            .init(z: 0.43, halfWidth: 0.59, bottom: 0.70, shoulder: 0.94, top: 1.01),
            .init(z: 0.78, halfWidth: 0.49, bottom: 0.66, shoulder: 0.79, top: 0.86),
        ],
        wheelX: 0.82,
        frontWheelZ: -0.96,
        rearWheelZ: 1.00,
        frontWheelRadius: 0.31,
        rearWheelRadius: 0.33,
        aero: .bladeWing,
        lamps: .segmentedBlade,
        accentColor: V3(x: 0.96, y: 0.16, z: 0.49),
        heroDetail: true,
        roofScoop: false
    ),
    VehicleSpec(
        filename: "traffic_sedan_3d.usda",
        rootName: "TrafficSedan",
        profiles: [
            .init(z: -1.43, halfWidth: 0.43, bottom: 0.17, shoulder: 0.38, top: 0.43),
            .init(z: -1.14, halfWidth: 0.66, bottom: 0.15, shoulder: 0.51, top: 0.58),
            .init(z: -0.57, halfWidth: 0.72, bottom: 0.15, shoulder: 0.61, top: 0.67),
            .init(z: 0.72, halfWidth: 0.73, bottom: 0.15, shoulder: 0.62, top: 0.68),
            .init(z: 1.31, halfWidth: 0.61, bottom: 0.18, shoulder: 0.50, top: 0.55),
            .init(z: 1.43, halfWidth: 0.52, bottom: 0.20, shoulder: 0.45, top: 0.49),
        ],
        canopyProfiles: [
            .init(z: -0.52, halfWidth: 0.49, bottom: 0.66, shoulder: 0.82, top: 0.90),
            .init(z: -0.24, halfWidth: 0.54, bottom: 0.68, shoulder: 0.94, top: 1.01),
            .init(z: 0.55, halfWidth: 0.55, bottom: 0.68, shoulder: 0.94, top: 1.01),
            .init(z: 0.84, halfWidth: 0.48, bottom: 0.65, shoulder: 0.80, top: 0.89),
        ],
        wheelX: 0.70,
        frontWheelZ: -0.88,
        rearWheelZ: 0.91,
        frontWheelRadius: 0.28,
        rearWheelRadius: 0.28,
        aero: .subtleLip,
        lamps: .sedan,
        accentColor: V3(x: 0.98, y: 0.74, z: 0.08),
        heroDetail: false,
        roofScoop: false
    ),
]

private func format(_ value: Double) -> String {
    String(format: "%.5f", locale: Locale(identifier: "en_US_POSIX"), value)
}

private func material(
    _ name: String,
    color: V3,
    metallic: Double,
    roughness: Double,
    emissive: V3? = nil,
    clearcoat: Double = 0,
    clearcoatRoughness: Double = 0,
    opacity: Double = 1,
    ior: Double = 1.5
) -> String {
    let emissiveLine = emissive.map {
        "                color3f inputs:emissiveColor = \($0.usd)\n"
    } ?? ""
    var surfaceLines = ""
    if clearcoat > 0 {
        surfaceLines += "                float inputs:clearcoat = \(format(clearcoat))\n"
        surfaceLines += "                float inputs:clearcoatRoughness = \(format(clearcoatRoughness))\n"
    }
    if opacity < 1 {
        surfaceLines += "                float inputs:opacity = \(format(opacity))\n"
        surfaceLines += "                float inputs:ior = \(format(ior))\n"
    }
    return """
        def Material "\(name)"
        {
            token outputs:surface.connect = </__ROOT__/Materials/\(name)/Surface.outputs:surface>
            def Shader "Surface"
            {
                uniform token info:id = "UsdPreviewSurface"
                color3f inputs:diffuseColor = \(color.usd)
                float inputs:metallic = \(format(metallic))
                float inputs:roughness = \(format(roughness))
\(surfaceLines)\(emissiveLine)                token outputs:surface
            }
        }
"""
}

private func cube(
    _ name: String,
    scale: V3,
    at position: V3,
    material: String,
    rotateX: Double? = nil,
    rotateY: Double? = nil,
    rotateZ: Double? = nil
) -> String {
    var operations = ["xformOp:translate"]
    var rotationLines = ""
    if let rotateX {
        rotationLines += "        float xformOp:rotateX = \(format(rotateX))\n"
        operations.append("xformOp:rotateX")
    }
    if let rotateY {
        rotationLines += "        float xformOp:rotateY = \(format(rotateY))\n"
        operations.append("xformOp:rotateY")
    }
    if let rotateZ {
        rotationLines += "        float xformOp:rotateZ = \(format(rotateZ))\n"
        operations.append("xformOp:rotateZ")
    }
    operations.append("xformOp:scale")
    let order = operations.map { "\"\($0)\"" }.joined(separator: ", ")
    return """
    def Cube "\(name)" (prepend apiSchemas = ["MaterialBindingAPI"])
    {
        double size = 2
        double3 xformOp:translate = \(position.usd)
\(rotationLines)        float3 xformOp:scale = \(scale.usd)
        uniform token[] xformOpOrder = [\(order)]
        rel material:binding = </__ROOT__/Materials/\(material)>
    }

"""
}

private func cylinder(
    _ name: String,
    radius: Double,
    height: Double,
    axis: String,
    at position: V3,
    material: String
) -> String {
    """
    def Cylinder "\(name)" (prepend apiSchemas = ["MaterialBindingAPI"])
    {
        uniform token axis = "\(axis)"
        double height = \(format(height))
        double radius = \(format(radius))
        double3 xformOp:translate = \(position.usd)
        uniform token[] xformOpOrder = ["xformOp:translate"]
        rel material:binding = </__ROOT__/Materials/\(material)>
    }

"""
}

private func sphere(
    _ name: String,
    scale: V3,
    at position: V3,
    material: String
) -> String {
    """
    def Sphere "\(name)" (prepend apiSchemas = ["MaterialBindingAPI"])
    {
        double radius = 1
        double3 xformOp:translate = \(position.usd)
        float3 xformOp:scale = \(scale.usd)
        uniform token[] xformOpOrder = ["xformOp:translate", "xformOp:scale"]
        rel material:binding = </__ROOT__/Materials/\(material)>
    }

"""
}

private func ringMesh(
    name: String,
    profiles: [BodyProfile],
    material: String,
    subdivisions: Int = 1
) -> String {
    let profiles = refinedProfiles(profiles, subdivisions: subdivisions)
    let ringPointCount = 12
    var points: [V3] = []
    for profile in profiles {
        let w = profile.halfWidth
        let upperShoulder = profile.shoulder + (profile.top - profile.shoulder) * 0.58
        points += [
            V3(x: -w * 0.74, y: profile.bottom, z: profile.z),
            V3(x: -w * 0.94, y: profile.bottom + 0.045, z: profile.z),
            V3(x: -w, y: profile.bottom + 0.12, z: profile.z),
            V3(x: -w, y: profile.shoulder, z: profile.z),
            V3(x: -w * 0.90, y: upperShoulder, z: profile.z),
            V3(x: -w * 0.62, y: profile.top, z: profile.z),
            V3(x: w * 0.62, y: profile.top, z: profile.z),
            V3(x: w * 0.90, y: upperShoulder, z: profile.z),
            V3(x: w, y: profile.shoulder, z: profile.z),
            V3(x: w, y: profile.bottom + 0.12, z: profile.z),
            V3(x: w * 0.94, y: profile.bottom + 0.045, z: profile.z),
            V3(x: w * 0.74, y: profile.bottom, z: profile.z),
        ]
    }

    var counts: [Int] = []
    var indices: [Int] = []
    for ring in 0..<(profiles.count - 1) {
        let current = ring * ringPointCount
        let next = (ring + 1) * ringPointCount
        for edge in 0..<ringPointCount {
            let following = (edge + 1) % ringPointCount
            counts.append(4)
            indices += [current + edge, current + following, next + following, next + edge]
        }
    }
    counts += [ringPointCount, ringPointCount]
    indices += Array(0..<ringPointCount)
    let last = (profiles.count - 1) * ringPointCount
    indices += (0..<ringPointCount).reversed().map { last + $0 }

    let pointText = points.map { "            \($0.usd)" }.joined(separator: ",\n")
    let countText = counts.map(String.init).joined(separator: ", ")
    let indexText = indices.map(String.init).joined(separator: ", ")
    return """
    def Mesh "\(name)" (prepend apiSchemas = ["MaterialBindingAPI"])
    {
        uniform bool doubleSided = 0
        int[] faceVertexCounts = [\(countText)]
        int[] faceVertexIndices = [\(indexText)]
        point3f[] points = [
\(pointText)
        ]
        uniform token subdivisionScheme = "none"
        rel material:binding = </__ROOT__/Materials/\(material)>
    }

"""
}

private func refinedProfiles(
    _ source: [BodyProfile],
    subdivisions: Int
) -> [BodyProfile] {
    let subdivisions = max(subdivisions, 1)
    guard source.count > 1, subdivisions > 1 else { return source }
    var result: [BodyProfile] = []
    result.reserveCapacity((source.count - 1) * subdivisions + 1)

    for index in 0..<(source.count - 1) {
        let start = source[index]
        let end = source[index + 1]
        for step in 0..<subdivisions {
            let t = Double(step) / Double(subdivisions)
            let eased = t * t * (3 - 2 * t)
            func blend(_ lhs: Double, _ rhs: Double, amount: Double) -> Double {
                lhs + (rhs - lhs) * amount
            }
            result.append(
                BodyProfile(
                    z: blend(start.z, end.z, amount: t),
                    halfWidth: blend(start.halfWidth, end.halfWidth, amount: eased),
                    bottom: blend(start.bottom, end.bottom, amount: eased),
                    shoulder: blend(start.shoulder, end.shoulder, amount: eased),
                    top: blend(start.top, end.top, amount: eased)
                )
            )
        }
    }
    result.append(source[source.count - 1])
    return result
}

private func annulusMesh(
    name: String,
    outerRadius: Double,
    innerRadius: Double,
    depth: Double,
    centerX: Double,
    material: String,
    segments: Int = 18
) -> String {
    var points: [V3] = []
    for face in [-0.5, 0.5] {
        let x = centerX + Double(face) * depth
        for index in 0..<segments {
            let angle = Double(index) * 2 * Double.pi / Double(segments)
            points.append(V3(x: x, y: cos(angle) * outerRadius, z: sin(angle) * outerRadius))
            points.append(V3(x: x, y: cos(angle) * innerRadius, z: sin(angle) * innerRadius))
        }
    }

    let faceStride = segments * 2
    var counts: [Int] = []
    var indices: [Int] = []
    for index in 0..<segments {
        let next = (index + 1) % segments
        let backOuter = index * 2
        let backInner = backOuter + 1
        let nextBackOuter = next * 2
        let nextBackInner = nextBackOuter + 1
        let frontOuter = faceStride + backOuter
        let frontInner = frontOuter + 1
        let nextFrontOuter = faceStride + nextBackOuter
        let nextFrontInner = nextFrontOuter + 1

        counts += [4, 4, 4, 4]
        indices += [frontOuter, nextFrontOuter, nextFrontInner, frontInner]
        indices += [backOuter, backInner, nextBackInner, nextBackOuter]
        indices += [backOuter, nextBackOuter, nextFrontOuter, frontOuter]
        indices += [backInner, frontInner, nextFrontInner, nextBackInner]
    }

    let pointText = points.map { "            \($0.usd)" }.joined(separator: ",\n")
    let countText = counts.map(String.init).joined(separator: ", ")
    let indexText = indices.map(String.init).joined(separator: ", ")
    return """
    def Mesh "\(name)" (prepend apiSchemas = ["MaterialBindingAPI"])
    {
        uniform bool doubleSided = 0
        int[] faceVertexCounts = [\(countText)]
        int[] faceVertexIndices = [\(indexText)]
        point3f[] points = [
\(pointText)
        ]
        uniform token subdivisionScheme = "none"
        rel material:binding = </__ROOT__/Materials/\(material)>
    }

"""
}

private func wheel(
    name: String,
    position: V3,
    radius: Double,
    heroDetail: Bool
) -> String {
    let outward = position.x < 0 ? -1.0 : 1.0
    let tireDepth = heroDetail ? 0.30 : 0.25
    let faceX = outward * tireDepth * 0.52
    var children = cylinder(
        "tire",
        radius: radius,
        height: tireDepth,
        axis: "X",
        at: V3(x: 0, y: 0, z: 0),
        material: "Tire"
    )
    children += annulusMesh(
        name: "tire_sidewall",
        outerRadius: radius * 0.985,
        innerRadius: radius * 0.73,
        depth: 0.018,
        centerX: faceX,
        material: "Tire"
    )
    children += cylinder(
        "rim_barrel",
        radius: radius * 0.68,
        height: heroDetail ? 0.12 : 0.10,
        axis: "X",
        at: V3(x: outward * tireDepth * 0.30, y: 0, z: 0),
        material: "DarkMetal"
    )
    children += annulusMesh(
        name: "rim_outer",
        outerRadius: radius * 0.70,
        innerRadius: radius * 0.55,
        depth: 0.028,
        centerX: faceX + outward * 0.010,
        material: "Rim"
    )
    children += cylinder(
        "brake_disc",
        radius: radius * 0.47,
        height: 0.025,
        axis: "X",
        at: V3(x: faceX - outward * 0.018, y: 0, z: 0),
        material: "Brake"
    )
    children += cylinder(
        "hub",
        radius: radius * 0.13,
        height: 0.050,
        axis: "X",
        at: V3(x: faceX + outward * 0.014, y: 0, z: 0),
        material: "DarkMetal"
    )
    if heroDetail {
        for index in 0..<6 {
            children += cube(
                "spoke_\(index)",
                scale: V3(x: 0.012, y: radius * 0.39, z: 0.018),
                at: V3(x: faceX + outward * 0.028, y: 0, z: 0),
                material: "Rim",
                rotateX: Double(index) * 30
            )
        }
        children += cube(
            "caliper",
            scale: V3(x: 0.014, y: radius * 0.16, z: radius * 0.075),
            at: V3(x: faceX + outward * 0.012, y: 0, z: radius * 0.38),
            material: "Accent"
        )
    }
    return """
    def Xform "\(name)"
    {
        double3 xformOp:translate = \(position.usd)
        uniform token[] xformOpOrder = ["xformOp:translate"]
\(children)
    }

"""
}

private func lamps(for spec: VehicleSpec, rearZ: Double, frontZ: Double) -> String {
    var result = ""
    switch spec.lamps {
    case .rallyBlocks:
        for side in [-1.0, 1.0] {
            result += cube(
                "tail_light_\(side < 0 ? "left" : "right")_upper",
                scale: V3(x: 0.24, y: 0.045, z: 0.018),
                at: V3(x: side * 0.41, y: 0.53, z: rearZ),
                material: "TailLight"
            )
            result += cube(
                "tail_light_\(side < 0 ? "left" : "right")_vertical",
                scale: V3(x: 0.045, y: 0.12, z: 0.019),
                at: V3(x: side * 0.61, y: 0.44, z: rearZ + 0.002),
                material: "TailLight"
            )
        }
    case .continuousBar:
        result += cube(
            "tail_light_center_bar",
            scale: V3(x: 0.56, y: 0.034, z: 0.018),
            at: V3(x: 0, y: 0.49, z: rearZ),
            material: "TailLight"
        )
        for side in [-1.0, 1.0] {
            result += cube(
                "tail_light_\(side < 0 ? "left" : "right")_blade",
                scale: V3(x: 0.19, y: 0.052, z: 0.019),
                at: V3(x: side * 0.52, y: 0.50, z: rearZ),
                material: "TailLight",
                rotateZ: side * 7
            )
        }
    case .segmentedBlade:
        for index in 0..<7 {
            let x = (Double(index) - 3) * 0.17
            result += cube(
                "tail_light_segment_\(index)",
                scale: V3(x: 0.065, y: 0.050 + abs(Double(index) - 3) * 0.008, z: 0.018),
                at: V3(x: x, y: 0.50, z: rearZ),
                material: index == 3 ? "Accent" : "TailLight",
                rotateZ: (Double(index) - 3) * -2.2
            )
        }
    case .sedan:
        for side in [-1.0, 1.0] {
            result += cube(
                "tail_light_\(side < 0 ? "left" : "right")",
                scale: V3(x: 0.24, y: 0.055, z: 0.018),
                at: V3(x: side * 0.40, y: 0.49, z: rearZ),
                material: "TailLight"
            )
        }
    }
    for side in [-1.0, 1.0] {
        result += cube(
            "head_light_\(side < 0 ? "left" : "right")",
            scale: V3(x: spec.heroDetail ? 0.25 : 0.21, y: 0.035, z: 0.018),
            at: V3(x: side * 0.42, y: 0.46, z: frontZ),
            material: "HeadLight",
            rotateZ: side * -7
        )
    }
    return result
}

private func aero(for spec: VehicleSpec, rearZ: Double) -> String {
    switch spec.aero {
    case .rallyWing:
        return cube(
            "paint_spoiler",
            scale: V3(x: 0.68, y: 0.024, z: 0.10),
            at: V3(x: 0, y: 1.04, z: rearZ - 0.20),
            material: "Paint",
            rotateX: -5
        ) + cube(
            "spoiler_post_left",
            scale: V3(x: 0.026, y: 0.13, z: 0.034),
            at: V3(x: -0.49, y: 0.90, z: rearZ - 0.22),
            material: "DarkMetal"
        ) + cube(
            "spoiler_post_right",
            scale: V3(x: 0.026, y: 0.13, z: 0.034),
            at: V3(x: 0.49, y: 0.90, z: rearZ - 0.22),
            material: "DarkMetal"
        )
    case .ducktail:
        return cube(
            "paint_ducktail",
            scale: V3(x: 0.67, y: 0.038, z: 0.14),
            at: V3(x: 0, y: 0.65, z: rearZ - 0.14),
            material: "Paint",
            rotateX: 13
        )
    case .bladeWing:
        return cube(
            "paint_spoiler",
            scale: V3(x: 0.73, y: 0.022, z: 0.095),
            at: V3(x: 0, y: 0.92, z: rearZ - 0.18),
            material: "Paint",
            rotateX: -3
        ) + cube(
            "spoiler_post_left",
            scale: V3(x: 0.020, y: 0.19, z: 0.030),
            at: V3(x: -0.51, y: 0.72, z: rearZ - 0.19),
            material: "DarkMetal",
            rotateZ: -12
        ) + cube(
            "spoiler_post_right",
            scale: V3(x: 0.020, y: 0.19, z: 0.030),
            at: V3(x: 0.51, y: 0.72, z: rearZ - 0.19),
            material: "DarkMetal",
            rotateZ: 12
        )
    case .subtleLip:
        return cube(
            "paint_rear_lip",
            scale: V3(x: 0.56, y: 0.025, z: 0.08),
            at: V3(x: 0, y: 0.58, z: rearZ - 0.05),
            material: "Paint",
            rotateX: 8
        )
    }
}

private func makeVehicle(_ spec: VehicleSpec) -> String {
    let frontZ = (spec.profiles.first?.z ?? -1.4) - 0.012
    let rearZ = (spec.profiles.last?.z ?? 1.4) + 0.012
    let subdivisions = spec.heroDetail ? 3 : 2
    var body = ringMesh(
        name: "paint_body_shell",
        profiles: spec.profiles,
        material: "Paint",
        subdivisions: subdivisions
    )
    body += ringMesh(
        name: "glass_canopy",
        profiles: spec.canopyProfiles,
        material: "Glass",
        subdivisions: subdivisions
    )

    for side in [-1.0, 1.0] {
        body += sphere(
            "paint_fender_front_\(side < 0 ? "left" : "right")",
            scale: V3(x: 0.13, y: spec.frontWheelRadius * 0.88, z: spec.frontWheelRadius * 1.30),
            at: V3(x: side * spec.wheelX, y: spec.frontWheelRadius + 0.08, z: spec.frontWheelZ),
            material: "Paint"
        )
        body += sphere(
            "paint_fender_rear_\(side < 0 ? "left" : "right")",
            scale: V3(x: 0.14, y: spec.rearWheelRadius * 0.90, z: spec.rearWheelRadius * 1.32),
            at: V3(x: side * spec.wheelX, y: spec.rearWheelRadius + 0.08, z: spec.rearWheelZ),
            material: "Paint"
        )
        body += cube(
            "dark_side_skirt_\(side < 0 ? "left" : "right")",
            scale: V3(x: 0.035, y: 0.070, z: abs(rearZ - frontZ) * 0.36),
            at: V3(x: side * (spec.wheelX + 0.015), y: 0.18, z: 0.05),
            material: "Carbon"
        )
        body += cube(
            "carbon_side_intake_\(side < 0 ? "left" : "right")",
            scale: V3(x: 0.025, y: 0.115, z: 0.25),
            at: V3(x: side * (spec.wheelX + 0.018), y: 0.40, z: 0.20),
            material: "Carbon",
            rotateX: side * -7
        )
        body += cube(
            "accent_sill_\(side < 0 ? "left" : "right")",
            scale: V3(x: 0.012, y: 0.018, z: abs(rearZ - frontZ) * 0.23),
            at: V3(x: side * (spec.wheelX + 0.040), y: 0.255, z: 0.06),
            material: "Accent"
        )
        body += cube(
            "mirror_\(side < 0 ? "left" : "right")",
            scale: V3(x: 0.12, y: 0.055, z: 0.13),
            at: V3(x: side * (spec.wheelX + 0.06), y: 0.74, z: -0.30),
            material: "Paint",
            rotateY: side * -8
        )
        body += cube(
            "glass_side_\(side < 0 ? "left" : "right")_divider",
            scale: V3(x: 0.012, y: 0.19, z: 0.025),
            at: V3(x: side * 0.59, y: 0.83, z: 0.16),
            material: "DarkMetal",
            rotateX: -5
        )
    }

    body += cube(
        "dark_rear_bumper",
        scale: V3(x: 0.62, y: 0.095, z: 0.055),
        at: V3(x: 0, y: 0.28, z: rearZ),
        material: "Carbon"
    )
    body += cube(
        "rear_light_recess",
        scale: V3(x: 0.67, y: 0.105, z: 0.026),
        at: V3(x: 0, y: 0.49, z: rearZ + 0.008),
        material: "DarkMetal"
    )
    body += cube(
        "dark_front_splitter",
        scale: V3(x: 0.62, y: 0.035, z: 0.14),
        at: V3(x: 0, y: 0.16, z: frontZ + 0.08),
        material: "Carbon",
        rotateX: -4
    )
    body += cube(
        "accent_center_spine",
        scale: V3(x: 0.026, y: 0.009, z: abs(rearZ - frontZ) * 0.34),
        at: V3(x: 0, y: spec.profiles[2].top + 0.018, z: -0.15),
        material: "Accent"
    )
    body += lamps(for: spec, rearZ: rearZ + 0.038, frontZ: frontZ)
    body += aero(for: spec, rearZ: rearZ)

    if spec.roofScoop {
        body += cube(
            "paint_roof_scoop",
            scale: V3(x: 0.16, y: 0.055, z: 0.30),
            at: V3(x: 0, y: 1.12, z: 0.13),
            material: "Paint",
            rotateX: -4
        )
        body += cube(
            "roof_scoop_intake",
            scale: V3(x: 0.12, y: 0.035, z: 0.025),
            at: V3(x: 0, y: 1.16, z: -0.18),
            material: "Carbon"
        )
    }

    if spec.heroDetail {
        body += cube(
            "interior_cockpit",
            scale: V3(x: 0.47, y: 0.075, z: 0.54),
            at: V3(x: 0, y: 0.69, z: 0.10),
            material: "Interior"
        )
        for side in [-1.0, 1.0] {
            body += sphere(
                "interior_seat_\(side < 0 ? "left" : "right")",
                scale: V3(x: 0.18, y: 0.24, z: 0.14),
                at: V3(x: side * 0.25, y: 0.80, z: 0.28),
                material: "Interior"
            )
            body += cube(
                "rear_deck_vent_\(side < 0 ? "left" : "right")",
                scale: V3(x: 0.13, y: 0.008, z: 0.22),
                at: V3(x: side * 0.25, y: spec.profiles[4].top + 0.024, z: 0.84),
                material: "Carbon",
                rotateX: -4
            )
        }
        for x in [-0.39, -0.13, 0.13, 0.39] {
            body += cube(
                "diffuser_fin_\(Int((x + 0.4) * 100))",
                scale: V3(x: 0.018, y: 0.10, z: 0.22),
                at: V3(x: x, y: 0.19, z: rearZ + 0.03),
                material: "Carbon",
                rotateX: -8
            )
        }
        for x in [-0.30, 0.30] {
            body += cylinder(
                "exhaust_\(x < 0 ? "left" : "right")",
                radius: 0.070,
                height: 0.13,
                axis: "Z",
                at: V3(x: x, y: 0.25, z: rearZ + 0.08),
                material: "Exhaust"
            )
        }
        for side in [-1.0, 1.0] {
            for vent in 0..<2 {
                body += cube(
                    "hood_vent_\(side < 0 ? "left" : "right")_\(vent)",
                    scale: V3(x: 0.095, y: 0.008, z: 0.20),
                    at: V3(x: side * (0.25 + Double(vent) * 0.14), y: spec.profiles[1].top + 0.025, z: -0.89),
                    material: "Carbon",
                    rotateX: -3
                )
            }
        }
    }

    body += wheel(
        name: "wheel_front_left",
        position: V3(x: -spec.wheelX, y: spec.frontWheelRadius, z: spec.frontWheelZ),
        radius: spec.frontWheelRadius,
        heroDetail: spec.heroDetail
    )
    body += wheel(
        name: "wheel_front_right",
        position: V3(x: spec.wheelX, y: spec.frontWheelRadius, z: spec.frontWheelZ),
        radius: spec.frontWheelRadius,
        heroDetail: spec.heroDetail
    )
    body += wheel(
        name: "wheel_rear_left",
        position: V3(x: -spec.wheelX, y: spec.rearWheelRadius, z: spec.rearWheelZ),
        radius: spec.rearWheelRadius,
        heroDetail: spec.heroDetail
    )
    body += wheel(
        name: "wheel_rear_right",
        position: V3(x: spec.wheelX, y: spec.rearWheelRadius, z: spec.rearWheelZ),
        radius: spec.rearWheelRadius,
        heroDetail: spec.heroDetail
    )

    let materials = [
        material("Paint", color: V3(x: 0.11, y: 0.60, z: 0.78), metallic: 0.48, roughness: 0.22, clearcoat: 0.96, clearcoatRoughness: 0.07),
        material("Glass", color: V3(x: 0.012, y: 0.035, z: 0.070), metallic: 0.08, roughness: 0.05, clearcoat: 0.34, clearcoatRoughness: 0.03, opacity: 0.78, ior: 1.46),
        material("DarkMetal", color: V3(x: 0.025, y: 0.032, z: 0.045), metallic: 0.90, roughness: 0.24),
        material("Carbon", color: V3(x: 0.012, y: 0.016, z: 0.023), metallic: 0.48, roughness: 0.34),
        material("Interior", color: V3(x: 0.018, y: 0.022, z: 0.030), metallic: 0.10, roughness: 0.72),
        material("Tire", color: V3(x: 0.006, y: 0.007, z: 0.009), metallic: 0, roughness: 0.94),
        material("Rim", color: V3(x: 0.44, y: 0.50, z: 0.55), metallic: 0.96, roughness: 0.18),
        material("Brake", color: V3(x: 0.20, y: 0.22, z: 0.24), metallic: 0.92, roughness: 0.28),
        material("Exhaust", color: V3(x: 0.16, y: 0.18, z: 0.20), metallic: 0.98, roughness: 0.20),
        material("TailLight", color: V3(x: 0.52, y: 0.004, z: 0.012), metallic: 0.05, roughness: 0.10, emissive: V3(x: 1.0, y: 0.012, z: 0.024), clearcoat: 0.72, clearcoatRoughness: 0.05),
        material("HeadLight", color: V3(x: 0.62, y: 0.86, z: 1.0), metallic: 0.02, roughness: 0.08, emissive: V3(x: 0.68, y: 0.91, z: 1.0), clearcoat: 0.78, clearcoatRoughness: 0.04),
        material("Accent", color: spec.accentColor, metallic: 0.54, roughness: 0.18, emissive: V3(x: spec.accentColor.x * 0.28, y: spec.accentColor.y * 0.28, z: spec.accentColor.z * 0.28), clearcoat: 0.42, clearcoatRoughness: 0.08),
    ].joined(separator: "\n").replacingOccurrences(of: "__ROOT__", with: spec.rootName)

    return """
#usda 1.0
(
    defaultPrim = "\(spec.rootName)"
    metersPerUnit = 1
    upAxis = "Y"
)

def Xform "\(spec.rootName)" (
    kind = "component"
    customData = {
        string assetRole = "\(spec.heroDetail ? "hero-vehicle" : "traffic-vehicle")"
        string authoringTool = "Scripts/build_production_racing_usd.swift"
        string license = "project-original"
        int productionRevision = 3
    }
)
{
    def Scope "Materials"
    {
\(materials)
    }

\(body.replacingOccurrences(of: "__ROOT__", with: spec.rootName))
}
"""
}

private func makeBarrier() -> String {
    let root = "TrackBarrier"
    let materials = [
        material("White", color: V3(x: 0.82, y: 0.84, z: 0.80), metallic: 0.08, roughness: 0.54),
        material("Orange", color: V3(x: 0.96, y: 0.24, z: 0.025), metallic: 0.10, roughness: 0.42),
        material("DarkMetal", color: V3(x: 0.035, y: 0.042, z: 0.050), metallic: 0.86, roughness: 0.31),
        material("Reflector", color: V3(x: 1.0, y: 0.52, z: 0.08), metallic: 0.02, roughness: 0.08, emissive: V3(x: 1.0, y: 0.22, z: 0.02)),
    ].joined(separator: "\n").replacingOccurrences(of: "__ROOT__", with: root)
    var body = cube(
        "dark_base",
        scale: V3(x: 0.80, y: 0.085, z: 0.22),
        at: V3(x: 0, y: 0.085, z: 0),
        material: "DarkMetal"
    )
    for index in 0..<5 {
        let x = (Double(index) - 2) * 0.30
        body += cube(
            "panel_\(index)",
            scale: V3(x: 0.15, y: 0.25, z: 0.145),
            at: V3(x: x, y: 0.41, z: 0),
            material: index.isMultiple(of: 2) ? "White" : "Orange",
            rotateZ: index.isMultiple(of: 2) ? -3 : 3
        )
        body += cube(
            "reflector_\(index)",
            scale: V3(x: 0.045, y: 0.045, z: 0.008),
            at: V3(x: x, y: 0.43, z: 0.154),
            material: "Reflector"
        )
    }
    for x in [-0.58, 0.58] {
        body += cube(
            "foot_\(x < 0 ? "left" : "right")",
            scale: V3(x: 0.07, y: 0.18, z: 0.07),
            at: V3(x: x, y: 0.18, z: 0),
            material: "DarkMetal"
        )
    }
    return """
#usda 1.0
(
    defaultPrim = "\(root)"
    metersPerUnit = 1
    upAxis = "Y"
)

def Xform "\(root)" (
    kind = "component"
    customData = {
        string assetRole = "track-obstacle"
        string authoringTool = "Scripts/build_production_racing_usd.swift"
        string license = "project-original"
        int productionRevision = 2
    }
)
{
    def Scope "Materials"
    {
\(materials)
    }

\(body.replacingOccurrences(of: "__ROOT__", with: root))
}
"""
}

do {
    try FileManager.default.createDirectory(
        at: outputDirectory,
        withIntermediateDirectories: true
    )
    for spec in vehicles {
        let url = outputDirectory.appendingPathComponent(spec.filename)
        try makeVehicle(spec).write(to: url, atomically: true, encoding: .utf8)
        print("wrote \(url.path)")
    }
    let barrierURL = outputDirectory.appendingPathComponent("track_barrier.usda")
    try makeBarrier().write(to: barrierURL, atomically: true, encoding: .utf8)
    print("wrote \(barrierURL.path)")
} catch {
    fputs("error: \(error)\n", stderr)
    exit(1)
}
