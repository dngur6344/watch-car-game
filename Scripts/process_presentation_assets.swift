#!/usr/bin/env -S xcrun swift

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

private struct RGBAImage {
    let width: Int
    let height: Int
    var bytes: [UInt8]

    init(cgImage: CGImage, width: Int, height: Int) throws {
        guard width > 0, height > 0,
              let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else {
            throw ProcessingError.invalidDimensions
        }

        var buffer = [UInt8](repeating: 0, count: width * height * 4)
        guard let context = CGContext(
            data: &buffer,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue
                | CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw ProcessingError.couldNotCreateContext
        }

        context.interpolationQuality = .high
        context.clear(CGRect(x: 0, y: 0, width: width, height: height))
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        self.width = width
        self.height = height
        bytes = buffer
    }

    init(width: Int, height: Int, bytes: [UInt8]) {
        self.width = width
        self.height = height
        self.bytes = bytes
    }

    func makeCGImage() throws -> CGImage {
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let provider = CGDataProvider(data: Data(bytes) as CFData),
              let image = CGImage(
                width: width,
                height: height,
                bitsPerComponent: 8,
                bitsPerPixel: 32,
                bytesPerRow: width * 4,
                space: colorSpace,
                bitmapInfo: CGBitmapInfo.byteOrder32Big.union(
                    CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
                ),
                provider: provider,
                decode: nil,
                shouldInterpolate: true,
                intent: .defaultIntent
              ) else {
            throw ProcessingError.couldNotCreateImage
        }
        return image
    }
}

private enum ProcessingError: Error, CustomStringConvertible {
    case invalidArguments(String)
    case invalidDimensions
    case couldNotDecode(URL)
    case couldNotCreateContext
    case couldNotCreateImage
    case couldNotCreateDestination(URL)
    case couldNotFinalize(URL)
    case emptyPaintMask(URL)

    var description: String {
        switch self {
        case let .invalidArguments(message): message
        case .invalidDimensions: "Image dimensions must be positive."
        case let .couldNotDecode(url): "Could not decode image at \(url.path)."
        case .couldNotCreateContext: "Could not create an sRGB RGBA context."
        case .couldNotCreateImage: "Could not create an sRGB RGBA image."
        case let .couldNotCreateDestination(url): "Could not create PNG at \(url.path)."
        case let .couldNotFinalize(url): "Could not finalize PNG at \(url.path)."
        case let .emptyPaintMask(url): "Paint extraction produced an empty mask for \(url.path)."
        }
    }
}

private struct RGBColor {
    let red: CGFloat
    let green: CGFloat
    let blue: CGFloat
}

private let presentationColors: [RGBColor] = [
    RGBColor(red: 0.20, green: 0.94, blue: 0.78),
    RGBColor(red: 0.10, green: 0.68, blue: 0.94),
    RGBColor(red: 0.40, green: 0.22, blue: 0.96),
    RGBColor(red: 0.94, green: 0.10, blue: 0.52),
    RGBColor(red: 1.00, green: 0.24, blue: 0.20),
    RGBColor(red: 1.00, green: 0.58, blue: 0.08),
    RGBColor(red: 0.78, green: 0.84, blue: 0.92),
    RGBColor(red: 0.04, green: 0.06, blue: 0.12),
]

private func image(at url: URL) throws -> CGImage {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
        throw ProcessingError.couldNotDecode(url)
    }
    return image
}

private func writePNG(_ image: RGBAImage, to url: URL) throws {
    try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    guard let destination = CGImageDestinationCreateWithURL(
        url as CFURL,
        UTType.png.identifier as CFString,
        1,
        nil
    ) else {
        throw ProcessingError.couldNotCreateDestination(url)
    }

    let properties: [CFString: Any] = [
        kCGImagePropertyProfileName: "sRGB IEC61966-2.1",
        kCGImagePropertyPNGDictionary: [
            kCGImagePropertyPNGInterlaceType: 0,
        ],
    ]
    CGImageDestinationAddImage(destination, try image.makeCGImage(), properties as CFDictionary)
    guard CGImageDestinationFinalize(destination) else {
        throw ProcessingError.couldNotFinalize(url)
    }
}

private func normalize(
    sourceURL: URL,
    outputURL: URL,
    width: Int,
    height: Int
) throws {
    let normalized = try RGBAImage(
        cgImage: image(at: sourceURL),
        width: width,
        height: height
    )
    try writePNG(normalized, to: outputURL)
}

private func splitVehicle(
    sourceURL: URL,
    paintURL: URL,
    detailsURL: URL,
    width: Int,
    height: Int
) throws {
    let source = try RGBAImage(
        cgImage: image(at: sourceURL),
        width: width,
        height: height
    )
    let pixelCount = width * height
    var paintLike = [Bool](repeating: false, count: pixelCount)
    var candidates = [Bool](repeating: false, count: pixelCount)

    for pixel in 0..<pixelCount {
        let offset = pixel * 4
        let alpha = Double(source.bytes[offset + 3]) / 255
        guard alpha > 0.01 else { continue }

        let red = min(Double(source.bytes[offset]) / 255 / alpha, 1)
        let green = min(Double(source.bytes[offset + 1]) / 255 / alpha, 1)
        let blue = min(Double(source.bytes[offset + 2]) / 255 / alpha, 1)
        let maximum = max(red, green, blue)
        let minimum = min(red, green, blue)
        let chroma = maximum - minimum
        let luminance = 0.2126 * red + 0.7152 * green + 0.0722 * blue

        paintLike[pixel] = luminance >= 0.38
            && chroma <= 0.30
            && (maximum == 0 || chroma / maximum <= 0.44)
        candidates[pixel] = alpha >= 0.55 && paintLike[pixel]
    }

    var retained = retainConnectedComponents(
        in: candidates,
        width: width,
        height: height,
        minimumPixelCount: max(6_000, pixelCount / 170),
        minimumWidePixelCount: max(2_000, pixelCount / 500),
        minimumWideAspectRatio: 4
    )

    retained = addAntialiasedFringe(
        to: retained,
        paintLike: paintLike,
        width: width,
        height: height
    )

    guard retained.contains(true) else {
        throw ProcessingError.emptyPaintMask(sourceURL)
    }

    var paintBytes = [UInt8](repeating: 0, count: source.bytes.count)
    var detailsBytes = source.bytes
    for pixel in 0..<pixelCount where retained[pixel] {
        let offset = pixel * 4
        let alpha = source.bytes[offset + 3]
        paintBytes[offset] = alpha
        paintBytes[offset + 1] = alpha
        paintBytes[offset + 2] = alpha
        paintBytes[offset + 3] = alpha
        detailsBytes[offset] = 0
        detailsBytes[offset + 1] = 0
        detailsBytes[offset + 2] = 0
        detailsBytes[offset + 3] = 0
    }

    clearTransparentBorder(in: &paintBytes, width: width, height: height, inset: 8)
    clearTransparentBorder(in: &detailsBytes, width: width, height: height, inset: 8)

    try writePNG(RGBAImage(width: width, height: height, bytes: paintBytes), to: paintURL)
    try writePNG(RGBAImage(width: width, height: height, bytes: detailsBytes), to: detailsURL)
}

private func clearTransparentBorder(
    in bytes: inout [UInt8],
    width: Int,
    height: Int,
    inset: Int
) {
    for y in 0..<height {
        for x in 0..<width where x < inset || x >= width - inset
            || y < inset || y >= height - inset {
            let offset = (y * width + x) * 4
            bytes[offset] = 0
            bytes[offset + 1] = 0
            bytes[offset + 2] = 0
            bytes[offset + 3] = 0
        }
    }
}

private func addAntialiasedFringe(
    to retained: [Bool],
    paintLike: [Bool],
    width: Int,
    height: Int
) -> [Bool] {
    var result = retained
    for y in 0..<height {
        for x in 0..<width {
            let pixel = y * width + x
            guard paintLike[pixel], !retained[pixel] else { continue }
            let minimumX = max(0, x - 2)
            let maximumX = min(width - 1, x + 2)
            let minimumY = max(0, y - 2)
            let maximumY = min(height - 1, y + 2)
            var touchesPaint = false
            for neighborY in minimumY...maximumY {
                for neighborX in minimumX...maximumX
                    where retained[neighborY * width + neighborX] {
                    touchesPaint = true
                    break
                }
                if touchesPaint { break }
            }
            result[pixel] = touchesPaint
        }
    }
    return result
}

private func retainConnectedComponents(
    in candidates: [Bool],
    width: Int,
    height: Int,
    minimumPixelCount: Int,
    minimumWidePixelCount: Int,
    minimumWideAspectRatio: Double
) -> [Bool] {
    var visited = [Bool](repeating: false, count: candidates.count)
    var retained = [Bool](repeating: false, count: candidates.count)
    let neighbors = [
        (-1, -1), (0, -1), (1, -1),
        (-1, 0),            (1, 0),
        (-1, 1),  (0, 1),  (1, 1),
    ]

    for start in candidates.indices where candidates[start] && !visited[start] {
        var component: [Int] = []
        var queue = [start]
        visited[start] = true
        var head = 0

        while head < queue.count {
            let pixel = queue[head]
            head += 1
            component.append(pixel)
            let x = pixel % width
            let y = pixel / width

            for (dx, dy) in neighbors {
                let nextX = x + dx
                let nextY = y + dy
                guard nextX >= 0, nextX < width, nextY >= 0, nextY < height else {
                    continue
                }
                let next = nextY * width + nextX
                guard candidates[next], !visited[next] else { continue }
                visited[next] = true
                queue.append(next)
            }
        }

        let xs = component.map { $0 % width }
        let ys = component.map { $0 / width }
        let componentWidth = (xs.max() ?? 0) - (xs.min() ?? 0) + 1
        let componentHeight = (ys.max() ?? 0) - (ys.min() ?? 0) + 1
        let aspectRatio = Double(componentWidth) / Double(max(componentHeight, 1))
        let shouldRetain = component.count >= minimumPixelCount
            || (component.count >= minimumWidePixelCount
                && aspectRatio >= minimumWideAspectRatio)

        if shouldRetain {
            if ProcessInfo.processInfo.environment["PRESENTATION_SPLIT_DEBUG"] == "1" {
                print(
                    "component pixels=\(component.count) "
                        + "bounds=\(xs.min() ?? 0),\(ys.min() ?? 0)-"
                        + "\(xs.max() ?? 0),\(ys.max() ?? 0)"
                )
            }
            for pixel in component {
                retained[pixel] = true
            }
        }
    }
    return retained
}

private func makeContactSheet(
    presentationDirectory: URL,
    outputURL: URL
) throws {
    let vehicleNames = ["rally", "gt", "angular", "rally-rs"]
    let cellSize = 200
    let width = cellSize * presentationColors.count
    let height = cellSize * vehicleNames.count
    guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else {
        throw ProcessingError.couldNotCreateContext
    }

    var sheetBytes = [UInt8](repeating: 0, count: width * height * 4)
    guard let sheetContext = CGContext(
        data: &sheetBytes,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: width * 4,
        space: colorSpace,
        bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue
            | CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        throw ProcessingError.couldNotCreateContext
    }
    sheetContext.setFillColor(CGColor(red: 0.025, green: 0.035, blue: 0.065, alpha: 1))
    sheetContext.fill(CGRect(x: 0, y: 0, width: width, height: height))
    sheetContext.interpolationQuality = .high

    for (row, vehicle) in vehicleNames.enumerated() {
        let paint = try image(at: presentationDirectory.appendingPathComponent("\(vehicle)_hero_paint.png"))
        let details = try image(at: presentationDirectory.appendingPathComponent("\(vehicle)_hero_details_shadow.png"))

        for (column, color) in presentationColors.enumerated() {
            let composite = try tintedComposite(paint: paint, details: details, color: color)
            let rect = CGRect(
                x: column * cellSize,
                y: (vehicleNames.count - row - 1) * cellSize,
                width: cellSize,
                height: cellSize
            ).insetBy(dx: 5, dy: 5)
            sheetContext.draw(composite, in: rect)
        }
    }

    try writePNG(
        RGBAImage(width: width, height: height, bytes: sheetBytes),
        to: outputURL
    )
}

private func tintedComposite(
    paint: CGImage,
    details: CGImage,
    color: RGBColor
) throws -> CGImage {
    let width = paint.width
    let height = paint.height
    guard details.width == width, details.height == height,
          let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else {
        throw ProcessingError.invalidDimensions
    }
    var bytes = [UInt8](repeating: 0, count: width * height * 4)
    guard let context = CGContext(
        data: &bytes,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: width * 4,
        space: colorSpace,
        bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue
            | CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        throw ProcessingError.couldNotCreateContext
    }
    let bounds = CGRect(x: 0, y: 0, width: width, height: height)
    context.clear(bounds)
    context.draw(paint, in: bounds)
    context.setBlendMode(.sourceIn)
    context.setFillColor(CGColor(red: color.red, green: color.green, blue: color.blue, alpha: 1))
    context.fill(bounds)
    context.setBlendMode(.normal)
    context.draw(details, in: bounds)
    guard let result = context.makeImage() else {
        throw ProcessingError.couldNotCreateImage
    }
    return result
}

private func int(_ value: String, named name: String) throws -> Int {
    guard let result = Int(value), result > 0 else {
        throw ProcessingError.invalidArguments("Invalid \(name): \(value)")
    }
    return result
}

private func run() throws {
    let arguments = Array(CommandLine.arguments.dropFirst())
    guard let command = arguments.first else {
        throw ProcessingError.invalidArguments(
            "usage: process_presentation_assets.swift normalize <source> <output> <width> <height>\n"
                + "   or: process_presentation_assets.swift split <source> <paint-output> <details-output> <width> <height>\n"
                + "   or: process_presentation_assets.swift contact-sheet <presentation-directory> <output>"
        )
    }

    switch command {
    case "normalize":
        guard arguments.count == 5 else {
            throw ProcessingError.invalidArguments("normalize requires source, output, width, and height")
        }
        try normalize(
            sourceURL: URL(fileURLWithPath: arguments[1]),
            outputURL: URL(fileURLWithPath: arguments[2]),
            width: try int(arguments[3], named: "width"),
            height: try int(arguments[4], named: "height")
        )
    case "split":
        guard arguments.count == 6 else {
            throw ProcessingError.invalidArguments(
                "split requires source, paint output, details output, width, and height"
            )
        }
        try splitVehicle(
            sourceURL: URL(fileURLWithPath: arguments[1]),
            paintURL: URL(fileURLWithPath: arguments[2]),
            detailsURL: URL(fileURLWithPath: arguments[3]),
            width: try int(arguments[4], named: "width"),
            height: try int(arguments[5], named: "height")
        )
    case "contact-sheet":
        guard arguments.count == 3 else {
            throw ProcessingError.invalidArguments(
                "contact-sheet requires presentation directory and output"
            )
        }
        try makeContactSheet(
            presentationDirectory: URL(fileURLWithPath: arguments[1], isDirectory: true),
            outputURL: URL(fileURLWithPath: arguments[2])
        )
    default:
        throw ProcessingError.invalidArguments("Unknown command: \(command)")
    }
}

do {
    try run()
} catch {
    fputs("error: \(error)\n", stderr)
    exit(1)
}
