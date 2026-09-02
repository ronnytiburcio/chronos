#!/usr/bin/env swift
//
//  render-icons.swift — renders every raster asset Chronos ships from the one
//  bolt outline that `Chronos/UI/BoltShape.swift` also draws.
//
//  Run it from the repo root (it also finds the root from its own path):
//
//      swift Scripts/render-icons.swift
//
//  Outputs, all committed:
//    Chronos/Resources/Assets.xcassets/AppIcon.appiconset/icon_*.png  (+ Contents.json)
//    Chronos/Resources/Assets.xcassets/MenuBarBoltIdle.imageset/      (+ Contents.json)
//    Chronos/Resources/Assets.xcassets/MenuBarBoltRunning.imageset/   (+ Contents.json)
//    Assets/chronos-bolt.svg, Assets/icon-1024.png   (README artwork, not bundled)
//
//  This is a standalone script: no Xcode project, no third-party dependencies.
//

import AppKit
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

// MARK: - Geometry

/// The bolt outline in a unit box, clockwise from the apex, y **down**.
///
/// - Important: this list is duplicated from `BoltShape.points` in
///   `Chronos/UI/BoltShape.swift`. **The two must stay identical.**
///   `ChronosTests/BoltShapeTests.swift` pins the app-side copy against the same
///   fixture, so a drift here means re-running this script after fixing it.
let boltPoints: [CGPoint] = [
    CGPoint(x: 0.72, y: 0.00),   // apex
    CGPoint(x: 0.14, y: 0.56),   // left kink, outer
    CGPoint(x: 0.44, y: 0.56),   // left kink, inner
    CGPoint(x: 0.28, y: 1.00),   // bottom tip
    CGPoint(x: 0.86, y: 0.44),   // right kink, outer
    CGPoint(x: 0.60, y: 0.44)    // right kink, inner
]

/// The bolt scaled into `rect`, flipped into Core Graphics' y-up space.
func boltPath(in rect: CGRect) -> CGPath {
    let path = CGMutablePath()
    let scaled = boltPoints.map { point in
        CGPoint(
            x: rect.minX + point.x * rect.width,
            y: rect.maxY - point.y * rect.height   // unit box is y-down; CG is y-up
        )
    }
    path.move(to: scaled[0])
    for point in scaled.dropFirst() { path.addLine(to: point) }
    path.closeSubpath()
    return path
}

// MARK: - Palette (SPEC §9)

let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!

func srgb(_ hex: UInt32, alpha: CGFloat = 1) -> CGColor {
    CGColor(
        colorSpace: colorSpace,
        components: [
            CGFloat((hex >> 16) & 0xFF) / 255,
            CGFloat((hex >> 8) & 0xFF) / 255,
            CGFloat(hex & 0xFF) / 255,
            alpha
        ]
    )!
}

let scarlet = srgb(0xD7262F)
let ink = srgb(0x15171C)
/// The top of the icon's gradient: Ink lifted just enough to read as a light
/// source, not as a second color.
let inkLifted = srgb(0x242832)
let black = srgb(0x000000)

// MARK: - Bitmap helpers

func makeContext(pixels: Int) -> CGContext {
    guard let context = CGContext(
        data: nil,
        width: pixels,
        height: pixels,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        fatalError("Could not create a \(pixels)x\(pixels) bitmap context")
    }
    context.setAllowsAntialiasing(true)
    context.setShouldAntialias(true)
    context.interpolationQuality = .high
    return context
}

func writePNG(_ image: CGImage, to url: URL) {
    guard let destination = CGImageDestinationCreateWithURL(
        url as CFURL,
        UTType.png.identifier as CFString,
        1,
        nil
    ) else {
        fatalError("Could not open \(url.path) for writing")
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else {
        fatalError("Could not write \(url.path)")
    }
}

func write(_ text: String, to url: URL) {
    do {
        try text.data(using: .utf8)!.write(to: url, options: .atomic)
    } catch {
        fatalError("Could not write \(url.path): \(error)")
    }
}

func makeDirectory(_ url: URL) {
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
}

// MARK: - App icon

/// A macOS-style rounded square: the icon body inset by 10% of the canvas on
/// every side (Apple's transparent margin), corners at 22.4% of the body, an
/// Ink fill lit by a subtle vertical gradient, and the Scarlet bolt on top.
func renderAppIcon(pixels: Int) -> CGImage {
    let size = CGFloat(pixels)
    let context = makeContext(pixels: pixels)

    let body = CGRect(x: 0, y: 0, width: size, height: size).insetBy(dx: size * 0.10, dy: size * 0.10)
    let radius = body.width * 0.224

    context.saveGState()
    context.addPath(CGPath(roundedRect: body, cornerWidth: radius, cornerHeight: radius, transform: nil))
    context.clip()
    let gradient = CGGradient(
        colorsSpace: colorSpace,
        colors: [inkLifted, ink] as CFArray,
        locations: [0, 1]
    )!
    context.drawLinearGradient(
        gradient,
        start: CGPoint(x: 0, y: body.maxY),
        end: CGPoint(x: 0, y: body.minY),
        options: []
    )
    context.restoreGState()

    // The bolt's unit box is square; its own side margins centre it horizontally.
    let boltSide = size * 0.58
    let boltRect = CGRect(
        x: (size - boltSide) / 2,
        y: (size - boltSide) / 2,
        width: boltSide,
        height: boltSide
    )
    context.addPath(boltPath(in: boltRect))
    context.setFillColor(scarlet)
    context.fillPath()

    guard let image = context.makeImage() else { fatalError("Could not render the \(pixels)px icon") }
    return image
}

// MARK: - Menu bar templates

/// 18x18pt, black on transparent, for the asset catalog's template rendering
/// intent. `MenuBarController` tints the filled one Scarlet with
/// `contentTintColor`; the outline one takes the menu bar's own color.
func renderMenuBarBolt(scale: Int, filled: Bool) -> CGImage {
    let points: CGFloat = 18
    let pixels = Int(points) * scale
    let context = makeContext(pixels: pixels)

    // 16pt of bolt inside an 18pt box, the usual menu bar breathing room.
    let side = 16 * CGFloat(scale)
    var rect = CGRect(
        x: (CGFloat(pixels) - side) / 2,
        y: (CGFloat(pixels) - side) / 2,
        width: side,
        height: side
    )

    if filled {
        context.addPath(boltPath(in: rect))
        context.setFillColor(black)
        context.fillPath()
    } else {
        let lineWidth = 1.5 * CGFloat(scale)
        // Stroke straddles the path, so pull the outline in by half a line.
        rect = rect.insetBy(dx: lineWidth / 2, dy: lineWidth / 2)
        context.addPath(boltPath(in: rect))
        context.setStrokeColor(black)
        context.setLineWidth(lineWidth)
        context.setLineJoin(.miter)
        // Past the limit the apex bevels instead of growing a spike.
        context.setMiterLimit(3)
        context.strokePath()
    }

    guard let image = context.makeImage() else { fatalError("Could not render the menu bar bolt") }
    return image
}

// MARK: - SVG

/// The bolt as a plain SVG on transparent, for the README and anywhere a vector
/// is wanted. Same unit box, scaled by 100.
func boltSVG() -> String {
    let commands = boltPoints.enumerated().map { index, point -> String in
        let x = String(format: "%.1f", point.x * 100)
        let y = String(format: "%.1f", point.y * 100)
        return "\(index == 0 ? "M" : "L")\(x) \(y)"
    }.joined(separator: " ")

    return """
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100" width="100" height="100" \
    role="img" aria-label="Chronos bolt">
      <path fill="#D7262F" d="\(commands) Z"/>
    </svg>

    """
}

// MARK: - Asset catalog metadata

func appIconContentsJSON(_ slots: [(size: Int, scale: Int, filename: String)]) -> String {
    let images = slots.map { slot in
        """
          {
              "filename" : "\(slot.filename)",
              "idiom" : "mac",
              "scale" : "\(slot.scale)x",
              "size" : "\(slot.size)x\(slot.size)"
            }
        """.trimmingCharacters(in: .whitespacesAndNewlines)
    }.joined(separator: ",\n    ")

    return """
    {
      "images" : [
        \(images)
      ],
      "info" : {
        "author" : "render-icons.swift",
        "version" : 1
      }
    }

    """
}

func templateImageSetContentsJSON(name: String) -> String {
    """
    {
      "images" : [
        {
          "filename" : "\(name).png",
          "idiom" : "universal",
          "scale" : "1x"
        },
        {
          "filename" : "\(name)@2x.png",
          "idiom" : "universal",
          "scale" : "2x"
        }
      ],
      "info" : {
        "author" : "render-icons.swift",
        "version" : 1
      },
      "properties" : {
        "template-rendering-intent" : "template"
      }
    }

    """
}

// MARK: - Run

/// The repo root: the script's own parent's parent, so the script works from
/// any working directory, falling back to the current directory.
let repoRoot: URL = {
    let fromScript = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()   // Scripts/
        .deletingLastPathComponent()   // repo root
    if FileManager.default.fileExists(atPath: fromScript.appendingPathComponent("project.yml").path) {
        return fromScript.standardizedFileURL
    }
    return URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
}()

let catalog = repoRoot
    .appendingPathComponent("Chronos/Resources/Assets.xcassets")
let appIconSet = catalog.appendingPathComponent("AppIcon.appiconset")
let readmeAssets = repoRoot.appendingPathComponent("Assets")

makeDirectory(appIconSet)
makeDirectory(readmeAssets)

// --- App icon -------------------------------------------------------------

let appIconSlots: [(size: Int, scale: Int, filename: String)] = [
    (16, 1, "icon_16x16.png"),
    (16, 2, "icon_16x16@2x.png"),
    (32, 1, "icon_32x32.png"),
    (32, 2, "icon_32x32@2x.png"),
    (128, 1, "icon_128x128.png"),
    (128, 2, "icon_128x128@2x.png"),
    (256, 1, "icon_256x256.png"),
    (256, 2, "icon_256x256@2x.png"),
    (512, 1, "icon_512x512.png"),
    (512, 2, "icon_512x512@2x.png")
]

// Seven distinct pixel sizes fill the ten slots; render each once.
var renderedIcons: [Int: CGImage] = [:]
for slot in appIconSlots {
    let pixels = slot.size * slot.scale
    let image = renderedIcons[pixels] ?? renderAppIcon(pixels: pixels)
    renderedIcons[pixels] = image
    writePNG(image, to: appIconSet.appendingPathComponent(slot.filename))
    print("  \(slot.filename)  \(pixels)x\(pixels)")
}
write(appIconContentsJSON(appIconSlots), to: appIconSet.appendingPathComponent("Contents.json"))
print("  Contents.json (AppIcon.appiconset)")

// --- Menu bar templates ---------------------------------------------------

for (name, filled) in [("MenuBarBoltIdle", false), ("MenuBarBoltRunning", true)] {
    let imageSet = catalog.appendingPathComponent("\(name).imageset")
    makeDirectory(imageSet)
    for scale in [1, 2] {
        let suffix = scale == 1 ? "" : "@\(scale)x"
        let filename = "\(name)\(suffix).png"
        writePNG(renderMenuBarBolt(scale: scale, filled: filled), to: imageSet.appendingPathComponent(filename))
        print("  \(name).imageset/\(filename)  \(18 * scale)x\(18 * scale)")
    }
    write(templateImageSetContentsJSON(name: name), to: imageSet.appendingPathComponent("Contents.json"))
    print("  Contents.json (\(name).imageset)")
}

// --- README artwork (not bundled) ----------------------------------------

write(boltSVG(), to: readmeAssets.appendingPathComponent("chronos-bolt.svg"))
print("  Assets/chronos-bolt.svg")
writePNG(renderedIcons[1024] ?? renderAppIcon(pixels: 1024), to: readmeAssets.appendingPathComponent("icon-1024.png"))
print("  Assets/icon-1024.png  1024x1024")

print("Done. Rendered into \(repoRoot.path)")
