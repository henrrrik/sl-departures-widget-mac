#!/usr/bin/env swift
//
// Renders every size in AppIcon.appiconset from one square source image.
//
//   swift Tools/make-app-icon.swift <source> <appiconset directory>
//
// The source is laid out on Apple's macOS grid rather than used edge to edge:
// a 1024 canvas with the art inset to 824, its corners rounded, and the soft
// shadow the platform's own icons carry. An icon that skips the grid is the
// one that looks a size too big beside everything else in the Dock.

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let canvas = 1024.0
let content = 824.0           // the art square inside the canvas
let radius = 185.4            // Apple's corner radius at this size
/// The source is a sticker on a concrete wall with room to spare around it;
/// cropping in makes the letters legible at 32 points, where most of an app
/// icon's life is spent.
let cropFraction = 0.86

let arguments = CommandLine.arguments
guard arguments.count == 3,
      let imageSource = CGImageSourceCreateWithURL(URL(fileURLWithPath: arguments[1]) as CFURL, nil),
      let sourceImage = CGImageSourceCreateImageAtIndex(imageSource, 0, nil)
else {
    FileHandle.standardError.write(Data("usage: make-app-icon.swift <source> <appiconset>\n".utf8))
    exit(1)
}
let outputDirectory = URL(fileURLWithPath: arguments[2])

// MARK: - The 1024 master

let side = min(Double(sourceImage.width), Double(sourceImage.height)) * cropFraction
let crop = CGRect(
    x: (Double(sourceImage.width) - side) / 2,
    y: (Double(sourceImage.height) - side) / 2,
    width: side,
    height: side
)
guard let cropped = sourceImage.cropping(to: crop) else { exit(1) }

guard let context = CGContext(
    data: nil,
    width: Int(canvas),
    height: Int(canvas),
    bitsPerComponent: 8,
    bytesPerRow: 0,
    space: CGColorSpaceCreateDeviceRGB(),
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else { exit(1) }

context.interpolationQuality = .high
context.clear(CGRect(x: 0, y: 0, width: canvas, height: canvas))

let art = CGRect(
    x: (canvas - content) / 2,
    y: (canvas - content) / 2,
    width: content,
    height: content
)
let shape = CGPath(roundedRect: art, cornerWidth: radius, cornerHeight: radius, transform: nil)

// Painted first, purely so the shadow has something to fall from; the art
// covers it completely.
context.saveGState()
context.setShadow(
    offset: CGSize(width: 0, height: -12),
    blur: 24,
    color: CGColor(red: 0, green: 0, blue: 0, alpha: 0.28)
)
context.addPath(shape)
context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
context.fillPath()
context.restoreGState()

context.saveGState()
context.addPath(shape)
context.clip()
context.draw(cropped, in: art)
context.restoreGState()

guard let master = context.makeImage() else { exit(1) }

// MARK: - Every size the catalog asks for

func write(pixels: Int, to name: String) {
    guard let scaled = CGContext(
        data: nil,
        width: pixels,
        height: pixels,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return }
    scaled.interpolationQuality = .high
    scaled.draw(master, in: CGRect(x: 0, y: 0, width: pixels, height: pixels))

    let url = outputDirectory.appendingPathComponent(name) as CFURL
    guard let image = scaled.makeImage(),
          let destination = CGImageDestinationCreateWithURL(url, UTType.png.identifier as CFString, 1, nil)
    else { return }
    CGImageDestinationAddImage(destination, image, nil)
    CGImageDestinationFinalize(destination)
}

for points in [16, 32, 128, 256, 512] {
    write(pixels: points, to: "icon_\(points).png")
    write(pixels: points * 2, to: "icon_\(points)@2x.png")
}
print("wrote 10 icons to \(outputDirectory.path)")
