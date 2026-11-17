import AppKit
import CoreText
import SwiftUI
import UniformTypeIdentifiers

/// File endings the bundled ffmpeg is tested to read, in the order shown in the drop zone.
enum SupportedInput {
    static let endings = ["MP4", "MOV", "M4V", "WEBM", "MKV", "AVI", "MPG", "WMV", "FLV", "TS", "3GP", "GIF"]
    static var contentTypes: [UTType] {
        [.movie, .video] + endings.compactMap { UTType(filenameExtension: $0.lowercased()) }
    }
}

/// The icon's typeface, loaded from the app bundle. Falls back to the system font.
enum Jost {
    private static let descriptor: CTFontDescriptor? = {
        guard let url = Bundle.main.url(forResource: "Jost", withExtension: "ttf") else { return nil }
        return (CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor])?.first
    }()

    /// A font whose capital letters are `cap` points tall.
    static func font(cap: CGFloat, weight: CGFloat) -> CTFont {
        guard let descriptor else {
            let f = NSFont.systemFont(ofSize: 100, weight: weight >= 600 ? .bold : .medium)
            return NSFont.systemFont(ofSize: 100 * cap / f.capHeight, weight: weight >= 600 ? .bold : .medium) as CTFont
        }
        let wght = NSNumber(value: 0x7767_6874)   // 'wght' variation axis
        let d = CTFontDescriptorCreateCopyWithVariation(descriptor, wght, weight)
        let probe = CTFontCreateWithFontDescriptor(d, 100, nil)
        return CTFontCreateWithFontDescriptor(d, 100 * cap / CTFontGetCapHeight(probe), nil)
    }
}

/// The top of the drop zone, set like the icon: input and output columns on the
/// left, "DROP VIDEO HERE" flush right. Text is aligned on its ink, as in the icon.
final class PosterView: NSView {
    static let cap: CGFloat = 34, gap: CGFloat = 8
    static let smallCap: CGFloat = 8, lead: CGFloat = 13, column: CGFloat = 44
    static let height = 3 * cap + 2 * gap

    override var intrinsicContentSize: NSSize { NSSize(width: NSView.noIntrinsicMetric, height: Self.height) }
    override func viewDidChangeEffectiveAppearance() { needsDisplay = true }

    private enum Edge { case left, right }

    private func put(_ c: CGContext, _ s: String, _ font: CTFont, track: CGFloat, color: NSColor,
                     edge: Edge, x: CGFloat, baseline: CGFloat) {
        let text = NSAttributedString(string: s, attributes: [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): color.cgColor,
            NSAttributedString.Key(kCTKernAttributeName as String): track * CTFontGetSize(font),
        ])
        let line = CTLineCreateWithAttributedString(text)
        c.textPosition = .zero
        let ink = CTLineGetImageBounds(line, c)
        c.textPosition = CGPoint(x: edge == .left ? x - ink.minX : x - ink.maxX, y: baseline)
        CTLineDraw(line, c)
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let c = NSGraphicsContext.current?.cgContext else { return }
        let top = bounds.maxY

        let big = Jost.font(cap: Self.cap, weight: 700)
        for (i, word) in ["DROP", "VIDEO", "HERE"].enumerated() {
            put(c, word, big, track: -0.012, color: .labelColor, edge: .right, x: bounds.maxX,
                baseline: top - Self.cap - CGFloat(i) * (Self.cap + Self.gap))
        }

        let head = Jost.font(cap: Self.smallCap, weight: 700), item = Jost.font(cap: Self.smallCap, weight: 500)
        func list(_ title: String, _ items: [String], x: CGFloat) {
            put(c, title, head, track: 0.03, color: .labelColor, edge: .left, x: x, baseline: top - Self.smallCap)
            for (i, s) in items.enumerated() {
                put(c, s, item, track: 0.03, color: .secondaryLabelColor, edge: .left,
                    x: x + CGFloat(i / 6) * Self.column,
                    baseline: top - Self.smallCap - CGFloat(i % 6 + 2) * Self.lead)
            }
        }
        list("Input", SupportedInput.endings, x: 0)
        list("Output", Format.allCases.map { $0.label.uppercased() }, x: 2 * Self.column + 16)
    }

    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityRole() -> NSAccessibility.Role? { .staticText }
    override func accessibilityLabel() -> String? {
        "Drop video here. Input: \(SupportedInput.endings.joined(separator: ", ")). "
            + "Output: \(Format.allCases.map(\.label).joined(separator: ", "))."
    }
}

struct Poster: NSViewRepresentable {
    func makeNSView(context: Context) -> PosterView { PosterView() }
    func updateNSView(_ view: PosterView, context: Context) {}
}
