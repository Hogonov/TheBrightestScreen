import AppKit

let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                                      bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                      isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        let p = CGFloat(pixels)
        let backdrop = NSBezierPath(roundedRect: NSRect(x: p * 0.06, y: p * 0.06, width: p * 0.88, height: p * 0.88),
                                    xRadius: p * 0.2, yRadius: p * 0.2)
        NSGradient(starting: NSColor(calibratedRed: 0.11, green: 0.14, blue: 0.23, alpha: 1),
                   ending: NSColor(calibratedRed: 0.035, green: 0.05, blue: 0.10, alpha: 1))!.draw(in: backdrop, angle: 90)
        NSColor(calibratedRed: 1, green: 0.75, blue: 0.26, alpha: 1).set()
        NSBezierPath(ovalIn: NSRect(x: p * 0.355, y: p * 0.355, width: p * 0.29, height: p * 0.29)).fill()
        let rays = NSBezierPath()
        rays.lineWidth = p * 0.044
        rays.lineCapStyle = .round
        for i in 0..<8 {
            let angle = Double(i) * .pi / 4
            rays.move(to: NSPoint(x: p * (0.5 + 0.23 * cos(angle)), y: p * (0.5 + 0.23 * sin(angle))))
            rays.line(to: NSPoint(x: p * (0.5 + 0.30 * cos(angle)), y: p * (0.5 + 0.30 * sin(angle))))
        }
        rays.stroke()
        NSGraphicsContext.restoreGraphicsState()
        let suffix = scale == 2 ? "@2x" : ""
        try bitmap.representation(using: .png, properties: [:])!.write(to: directory.appendingPathComponent("icon_\(size)x\(size)\(suffix).png"))
    }
}
