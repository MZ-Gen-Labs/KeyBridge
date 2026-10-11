import AppKit
import Foundation

let target = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "Resources", isDirectory: true)
let iconset = target.appendingPathComponent("AppIcon.iconset", isDirectory: true)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

func paint(_ width: Int, _ height: Int, draw: () -> Void) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    let context = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    draw()
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

func drawMark(scale: CGFloat, menu: Bool) {
    let transform = NSAffineTransform(); transform.scale(by: scale); transform.concat()
    let color = menu ? NSColor.black : NSColor.white
    color.setStroke(); color.setFill()
    // A key above a bridge: the bridge represents carrying credentials to programs.
    let ring = NSBezierPath(ovalIn: NSRect(x: 185, y: 515, width: 210, height: 210))
    ring.lineWidth = 66; ring.stroke()
    let stem = NSBezierPath(); stem.move(to: NSPoint(x: 390, y: 620)); stem.line(to: NSPoint(x: 795, y: 620))
    stem.lineWidth = 66; stem.lineCapStyle = .round; stem.stroke()
    let teeth = NSBezierPath(); teeth.move(to: NSPoint(x: 690, y: 620)); teeth.line(to: NSPoint(x: 690, y: 530)); teeth.move(to: NSPoint(x: 785, y: 620)); teeth.line(to: NSPoint(x: 785, y: 545))
    teeth.lineWidth = 64; teeth.lineCapStyle = .round; teeth.stroke()
    let bridge = NSBezierPath(); bridge.move(to: NSPoint(x: 175, y: 280)); bridge.line(to: NSPoint(x: 300, y: 280)); bridge.curve(to: NSPoint(x: 700, y: 280), controlPoint1: NSPoint(x: 330, y: 485), controlPoint2: NSPoint(x: 670, y: 485)); bridge.line(to: NSPoint(x: 825, y: 280))
    bridge.lineWidth = 68; bridge.lineCapStyle = .round; bridge.stroke()
}

for points in [16, 32, 128, 256, 512] {
    for factor in [1, 2] {
        let pixels = points * factor
        let data = paint(pixels, pixels) {
            let scale = CGFloat(pixels) / 1024
            let bg = NSBezierPath(roundedRect: NSRect(x: 64 * scale, y: 64 * scale, width: 896 * scale, height: 896 * scale), xRadius: 200 * scale, yRadius: 200 * scale)
            NSGradient(starting: NSColor(calibratedRed: 0.10, green: 0.58, blue: 0.72, alpha: 1), ending: NSColor(calibratedRed: 0.08, green: 0.17, blue: 0.36, alpha: 1))!.draw(in: bg, angle: -65)
            drawMark(scale: scale, menu: false)
        }
        let suffix = factor == 2 ? "@2x" : ""
        try data.write(to: iconset.appendingPathComponent("icon_\(points)x\(points)\(suffix).png"))
    }
}
let menu = paint(44, 36) {
    let transform = NSAffineTransform(); transform.translateX(by: -1, yBy: -4); transform.concat()
    drawMark(scale: 0.044, menu: true)
}
try menu.write(to: target.appendingPathComponent("MenuBarIcon.png"))
print("Generated application and menu bar icons")
