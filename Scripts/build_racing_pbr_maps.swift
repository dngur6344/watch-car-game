#!/usr/bin/env swift

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

private enum BuildError: Error, CustomStringConvertible {
    case usage
    case unreadableSource(URL)
    case contextCreation
    case imageCreation
    case destinationCreation(URL)
    case destinationFinalize(URL)

    var description: String {
        switch self {
        case .usage:
            return "usage: build_racing_pbr_maps.swift <source.png> <normal.png> <roughness.png>"
        case let .unreadableSource(url):
            return "unable to read source image: \(url.path)"
        case .contextCreation:
            return "unable to create sRGB RGBA context"
        case .imageCreation:
            return "unable to create output CGImage"
        case let .destinationCreation(url):
            return "unable to create PNG destination: \(url.path)"
        case let .destinationFinalize(url):
            return "unable to finalize PNG destination: \(url.path)"
        }
    }
}

private struct Raster {
    let width: Int
    let height: Int
    var pixels: [UInt8]

    init(contentsOf url: URL) throws {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw BuildError.unreadableSource(url)
        }

        width = image.width
        height = image.height
        pixels = [UInt8](repeating: 0, count: width * height * 4)
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                  data: &pixels,
                  width: width,
                  height: height,
                  bitsPerComponent: 8,
                  bytesPerRow: width * 4,
                  space: colorSpace,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else {
            throw BuildError.contextCreation
        }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    }

    init(width: Int, height: Int) {
        self.width = width
        self.height = height
        pixels = [UInt8](repeating: 0, count: width * height * 4)
    }

    func luminance(x: Int, y: Int) -> Float {
        let wrappedX = (x % width + width) % width
        let wrappedY = (y % height + height) % height
        let offset = (wrappedY * width + wrappedX) * 4
        return (
            Float(pixels[offset]) * 0.2126
                + Float(pixels[offset + 1]) * 0.7152
                + Float(pixels[offset + 2]) * 0.0722
        ) / 255
    }

    mutating func setPixel(x: Int, y: Int, red: Float, green: Float, blue: Float) {
        let offset = (y * width + x) * 4
        pixels[offset] = UInt8(clamping: Int((min(max(red, 0), 1) * 255).rounded()))
        pixels[offset + 1] = UInt8(clamping: Int((min(max(green, 0), 1) * 255).rounded()))
        pixels[offset + 2] = UInt8(clamping: Int((min(max(blue, 0), 1) * 255).rounded()))
        pixels[offset + 3] = 255
    }

    func writePNG(to url: URL) throws {
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let provider = CGDataProvider(data: Data(pixels) as CFData),
              let image = CGImage(
                  width: width,
                  height: height,
                  bitsPerComponent: 8,
                  bitsPerPixel: 32,
                  bytesPerRow: width * 4,
                  space: colorSpace,
                  bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                  provider: provider,
                  decode: nil,
                  shouldInterpolate: true,
                  intent: .defaultIntent
              ) else {
            throw BuildError.imageCreation
        }
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else {
            throw BuildError.destinationCreation(url)
        }
        CGImageDestinationAddImage(destination, image, [
            kCGImagePropertyColorModel: kCGImagePropertyColorModelRGB,
            kCGImagePropertyProfileName: "sRGB IEC61966-2.1",
        ] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw BuildError.destinationFinalize(url)
        }
    }
}

private func buildMaps(source: Raster) -> (normal: Raster, roughness: Raster) {
    var normal = Raster(width: source.width, height: source.height)
    var roughness = Raster(width: source.width, height: source.height)

    for y in 0..<source.height {
        for x in 0..<source.width {
            let left = source.luminance(x: x - 1, y: y)
            let right = source.luminance(x: x + 1, y: y)
            let up = source.luminance(x: x, y: y - 1)
            let down = source.luminance(x: x, y: y + 1)
            let center = source.luminance(x: x, y: y)
            let dx = (right - left) * 3.6
            let dy = (down - up) * 3.6
            let inverseLength = 1 / sqrt(dx * dx + dy * dy + 1)
            normal.setPixel(
                x: x,
                y: y,
                red: (-dx * inverseLength) * 0.5 + 0.5,
                green: (-dy * inverseLength) * 0.5 + 0.5,
                blue: inverseLength * 0.5 + 0.5
            )

            let localContrast = min(abs(right - left) + abs(down - up), 0.35)
            let value = min(max(0.74 + (1 - center) * 0.18 + localContrast * 0.28, 0.68), 0.97)
            roughness.setPixel(x: x, y: y, red: value, green: value, blue: value)
        }
    }
    return (normal, roughness)
}

do {
    guard CommandLine.arguments.count == 4 else {
        throw BuildError.usage
    }
    let sourceURL = URL(fileURLWithPath: CommandLine.arguments[1])
    let normalURL = URL(fileURLWithPath: CommandLine.arguments[2])
    let roughnessURL = URL(fileURLWithPath: CommandLine.arguments[3])
    let maps = buildMaps(source: try Raster(contentsOf: sourceURL))
    try maps.normal.writePNG(to: normalURL)
    try maps.roughness.writePNG(to: roughnessURL)
    print("wrote \(normalURL.path)")
    print("wrote \(roughnessURL.path)")
} catch {
    fputs("error: \(error)\n", stderr)
    exit(1)
}
