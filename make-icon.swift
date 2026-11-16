// Draws the app icon: swift make-icon.swift <out.png>
import AppKit

let size = 1024
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

let rect = NSRect(x: 100, y: 100, width: 824, height: 824)
let shape = NSBezierPath(roundedRect: rect, xRadius: 185, yRadius: 185)
NSGradient(colors: [
    NSColor(red: 1.00, green: 0.42, blue: 0.21, alpha: 1),
    NSColor(red: 0.93, green: 0.16, blue: 0.48, alpha: 1),
    NSColor(red: 0.47, green: 0.18, blue: 0.86, alpha: 1),
])!.draw(in: shape, angle: -55)

// Film-strip perforations along top and bottom.
NSColor(white: 1, alpha: 0.28).setFill()
for row in [rect.minY + 62, rect.maxY - 62 - 56] {
    for i in 0 ..< 6 {
        let x = rect.minX + 97 + CGFloat(i) * 110
        NSBezierPath(roundedRect: NSRect(x: x, y: row, width: 80, height: 56), xRadius: 16, yRadius: 16).fill()
    }
}

let font = NSFont.systemFont(ofSize: 330, weight: .heavy)
let rounded = font.fontDescriptor.withDesign(.rounded).flatMap { NSFont(descriptor: $0, size: 330) } ?? font
let text = NSAttributedString(string: "GIF", attributes: [
    .font: rounded, .foregroundColor: NSColor.white, .kern: -6,
])
let t = text.size()
text.draw(at: NSPoint(x: rect.midX - t.width / 2, y: rect.midY - t.height / 2 + 6))

NSGraphicsContext.current?.flushGraphics()
try! rep.representation(using: .png, properties: [:])!
    .write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
