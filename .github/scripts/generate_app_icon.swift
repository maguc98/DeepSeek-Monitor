import AppKit
import Foundation

let size = 1024
let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()

let rect = NSRect(x: 0, y: 0, width: size, height: size)
NSColor.white.setFill()
rect.fill()

func gradient(_ colors: [NSColor], in path: NSBezierPath, angle: CGFloat = 90) {
    NSGradient(colors: colors)!.draw(in: path, angle: angle)
}

let barColors = [
    NSColor(calibratedRed: 0.52, green: 0.78, blue: 1.0, alpha: 1),
    NSColor(calibratedRed: 0.27, green: 0.59, blue: 0.98, alpha: 1),
    NSColor(calibratedRed: 0.18, green: 0.39, blue: 0.94, alpha: 1)
]
for (x, y, w, h, color) in [
    (285.0, 470.0, 132.0, 205.0, barColors[0]),
    (438.0, 430.0, 140.0, 300.0, barColors[1]),
    (600.0, 390.0, 148.0, 390.0, barColors[2])
] {
    let p = NSBezierPath(roundedRect: NSRect(x: x, y: y, width: w, height: h),
                         xRadius: 38, yRadius: 38)
    gradient([color, NSColor(calibratedRed: 0.22, green: 0.40, blue: 0.95, alpha: 1)], in: p)
}

let body = NSBezierPath()
body.move(to: NSPoint(x: 170, y: 405))
body.curve(to: NSPoint(x: 780, y: 410),
           controlPoint1: NSPoint(x: 340, y: 520),
           controlPoint2: NSPoint(x: 610, y: 520))
body.curve(to: NSPoint(x: 850, y: 590),
           controlPoint1: NSPoint(x: 830, y: 470),
           controlPoint2: NSPoint(x: 845, y: 545))
body.curve(to: NSPoint(x: 905, y: 650),
           controlPoint1: NSPoint(x: 890, y: 610),
           controlPoint2: NSPoint(x: 900, y: 630))
body.curve(to: NSPoint(x: 785, y: 610),
           controlPoint1: NSPoint(x: 865, y: 690),
           controlPoint2: NSPoint(x: 820, y: 685))
body.curve(to: NSPoint(x: 748, y: 500),
           controlPoint1: NSPoint(x: 750, y: 560),
           controlPoint2: NSPoint(x: 735, y: 525))
body.curve(to: NSPoint(x: 610, y: 275),
           controlPoint1: NSPoint(x: 770, y: 455),
           controlPoint2: NSPoint(x: 700, y: 300))
body.curve(to: NSPoint(x: 170, y: 405),
           controlPoint1: NSPoint(x: 420, y: 180),
           controlPoint2: NSPoint(x: 220, y: 230))
body.close()
gradient([
    NSColor(calibratedRed: 0.34, green: 0.57, blue: 1.0, alpha: 1),
    NSColor(calibratedRed: 0.22, green: 0.30, blue: 0.91, alpha: 1)
], in: body, angle: 35)

let belly = NSBezierPath()
belly.move(to: NSPoint(x: 170, y: 405))
belly.curve(to: NSPoint(x: 625, y: 245),
            controlPoint1: NSPoint(x: 300, y: 355),
            controlPoint2: NSPoint(x: 430, y: 220))
belly.curve(to: NSPoint(x: 420, y: 300),
            controlPoint1: NSPoint(x: 545, y: 235),
            controlPoint2: NSPoint(x: 485, y: 270))
belly.curve(to: NSPoint(x: 170, y: 405),
            controlPoint1: NSPoint(x: 330, y: 375),
            controlPoint2: NSPoint(x: 235, y: 420))
belly.close()
gradient([NSColor(calibratedRed: 0.98, green: 0.99, blue: 1, alpha: 1),
          NSColor(calibratedRed: 0.76, green: 0.84, blue: 1, alpha: 1)], in: belly, angle: 90)

let eye = NSBezierPath(ovalIn: NSRect(x: 370, y: 365, width: 27, height: 27))
NSColor.white.setFill()
eye.fill()

let wave = NSBezierPath()
wave.lineWidth = 16
wave.lineCapStyle = .round
wave.move(to: NSPoint(x: 625, y: 710))
wave.curve(to: NSPoint(x: 770, y: 585),
           controlPoint1: NSPoint(x: 610, y: 625),
           controlPoint2: NSPoint(x: 700, y: 550))
NSColor.white.setStroke()
wave.stroke()

// Unlock the source image before copying it into the bitmap representation.
// The previous deferred unlock kept it locked during rasterization and emitted
// an almost-solid white PNG despite the drawing commands succeeding.
image.unlockFocus()

let cg = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
                          bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                          isPlanar: false, colorSpaceName: .deviceRGB,
                          bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
let bitmapContext = NSGraphicsContext(bitmapImageRep: cg)!
bitmapContext.imageInterpolation = .high
NSGraphicsContext.current = bitmapContext
image.draw(in: rect)
bitmapContext.flushGraphics()
NSGraphicsContext.restoreGraphicsState()

let output = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Sources/DeepSeekMonitor/Assets.xcassets/AppIcon.appiconset/AppIcon.png"
let outputURL = URL(fileURLWithPath: output)
try FileManager.default.createDirectory(at: outputURL.deletingLastPathComponent(),
                                        withIntermediateDirectories: true)
guard let png = cg.representation(using: .png, properties: [:]) else {
    fatalError("Failed to encode app icon PNG")
}
try png.write(to: outputURL)

// Validate the exported PNG itself, not just the existence of the file.
guard let savedData = try? Data(contentsOf: outputURL),
      let verification = NSBitmapImageRep(data: savedData) else {
    fatalError("Generated app icon cannot be reopened")
}
var coloredSamples = 0
for y in stride(from: 0, to: size, by: 4) {
    for x in stride(from: 0, to: size, by: 4) {
        guard let color = verification.colorAt(x: x, y: y)?.usingColorSpace(NSColorSpace.deviceRGB) else { continue }
        let maximum = max(color.redComponent, color.greenComponent, color.blueComponent)
        let minimum = min(color.redComponent, color.greenComponent, color.blueComponent)
        if maximum - minimum > CGFloat(0.12) { coloredSamples += 1 }
    }
}
guard coloredSamples > 100 else {
    fatalError("Generated app icon is blank: only \(coloredSamples) colored samples found")
}
print("Generated \(output) with \(coloredSamples) colored samples")
