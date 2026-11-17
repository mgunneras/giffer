// Draws the app icon: swift make-icon.swift <out.png>   (run from the project root)
// Swiss poster layout on an 8 px grid, set in Jost (SIL Open Font License, assets/fonts).
// The artwork is a plain square with no rounded corners.
import AppKit
import CoreText

// ---- Grid: the artwork is a full 1024 px square on an 8 px unit, measured from the top-left ----
let T: CGFloat = 1024, OX: CGFloat = 0, OY: CGFloat = 0
let MARGIN: CGFloat = 88            // 11 units
let COL: CGFloat = 128, GUT: CGFloat = 16   // 6 columns: 6*128 + 5*16 = 848
let CAP: CGFloat = 120              // big cap height, 15 units
let PITCH: CGFloat = 136            // big line pitch, 17 units (cap + one gutter)
let SCAP: CGFloat = 24              // small cap height, 3 units
let SLEAD: CGFloat = 32             // small leading, 4 units; the 4th row shares DROP's baseline
let BAND: CGFloat = 280             // white band height, 35 units
let DOT: CGFloat = 64               // 8 units
func colX(_ i: Int) -> CGFloat { OX + MARGIN + CGFloat(i) * (COL + GUT) }
func Y(_ fromTop: CGFloat) -> CGFloat { OY + T - fromTop }
let RIGHT = OX + T - MARGIN

let red = NSColor(red: 0.90, green: 0.08, blue: 0.11, alpha: 1)
typealias Maker = (CGFloat) -> CTFont

func file(_ name: String, wght: CGFloat? = nil) -> Maker {
    let url = URL(fileURLWithPath: "assets/fonts/\(name)") as CFURL
    var d = (CTFontManagerCreateFontDescriptorsFromURL(url) as! [CTFontDescriptor])[0]
    if let wght { d = CTFontDescriptorCreateCopyWithVariation(d, NSNumber(value: 0x77676874), wght) }
    return { CTFontCreateWithFontDescriptor(d, $0, nil) }
}

func ctline(_ s: String, _ f: CTFont, track: CGFloat, color: NSColor, pairs: [String: CGFloat] = [:]) -> CTLine {
    let size = CTFontGetSize(f)
    let a = NSMutableAttributedString(string: s, attributes: [
        NSAttributedString.Key(kCTFontAttributeName as String): f,
        NSAttributedString.Key(kCTForegroundColorAttributeName as String): color.cgColor,
    ])
    let chars = Array(s)
    for i in 0 ..< chars.count {
        var k = track
        if i + 1 < chars.count, let extra = pairs[String([chars[i], chars[i + 1]])] { k += extra }
        a.addAttribute(NSAttributedString.Key(kCTKernAttributeName as String), value: k * size, range: NSRange(location: i, length: 1))
    }
    return CTLineCreateWithAttributedString(a)
}
/// Font size at which a flat capital is exactly `cap` px tall (measured on the ink of "H").
func sized(_ make: Maker, cap: CGFloat, _ c: CGContext) -> CTFont {
    let h = CTLineGetImageBounds(ctline("H", make(1000), track: 0, color: .white), c).height
    return make(1000 * cap / h)
}
enum Edge { case left, right }
/// Draws text with its ink edge (not its advance box) on `x`, baseline on `baseline`.
func draw(_ c: CGContext, _ s: String, _ f: CTFont, track: CGFloat, color: NSColor, edge: Edge, x: CGFloat,
          baseline: CGFloat, pairs: [String: CGFloat] = [:], overshoot: CGFloat = 0) {
    let line = ctline(s, f, track: track, color: color, pairs: pairs)
    c.textPosition = .zero
    let ink = CTLineGetImageBounds(line, c)
    let px = edge == .left ? x - ink.minX - overshoot : x - ink.maxX + overshoot
    c.textPosition = CGPoint(x: px, y: baseline)
    CTLineDraw(line, c)
}

let bold = file("Jost.ttf", wght: 700), medium = file("Jost.ttf", wght: 500)
let TRACK: CGFloat = -0.012        // big text tracking, in em
let SMALL_TRACK: CGFloat = 0.03
let ROUND: CGFloat = 0.008         // how far round letters hang over the margin, in em

func icon(_ c: CGContext) {
    let tile = CGRect(x: OX, y: OY, width: T, height: T)
    c.setFillColor(NSColor.black.cgColor); c.fill(tile)
    c.setFillColor(NSColor.white.cgColor); c.fill(CGRect(x: OX, y: OY, width: T, height: BAND))

    let big = sized(bold, cap: CAP, c), size = CTFontGetSize(big)
    let roundEnd: Set<Character> = ["O", "P", "D", "G", "C", "S"]
    for (i, s) in ["DROP", "VIDEO", "HERE"].enumerated() {
        draw(c, s, big, track: TRACK, color: .white, edge: .right, x: RIGHT,
             baseline: Y(MARGIN + CAP + CGFloat(i) * PITCH), pairs: [:],
             overshoot: roundEnd.contains(s.last!) ? ROUND * size : 0)
    }
    draw(c, "GIFFER", big, track: TRACK, color: .black, edge: .left, x: colX(0),
         baseline: Y(T - MARGIN), pairs: [:], overshoot: ROUND * size)

    let head = sized(bold, cap: SCAP, c), item = sized(medium, cap: SCAP, c)
    for (col, lines) in [["Input", "", "MP4", "MOV", "WEBM", "MKV"], ["Output", "", "GIF", "WEBP", "AVIF", "APNG"]].enumerated() {
        for (i, s) in lines.enumerated() where !s.isEmpty {
            draw(c, s, i == 0 ? head : item, track: SMALL_TRACK, color: .white, edge: .left, x: colX(col),
                 baseline: Y(MARGIN + SCAP + CGFloat(i) * SLEAD))
        }
    }
    c.setFillColor(red.cgColor)
    c.fillEllipse(in: CGRect(x: RIGHT - DOT, y: Y(T - MARGIN) + (CAP - DOT) / 2, width: DOT, height: DOT))

}


let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1024, pixelsHigh: 1024, bitsPerSample: 8,
                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
let graphics = NSGraphicsContext(bitmapImageRep: rep)!
NSGraphicsContext.current = graphics
icon(graphics.cgContext)
graphics.flushGraphics()
try! rep.representation(using: .png, properties: [:])!
    .write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
