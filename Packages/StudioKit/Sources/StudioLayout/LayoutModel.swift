import CoreGraphics
import Foundation
import ImageIO
import StudioCore
import UIKit

public struct PageSize: Codable, Hashable, Sendable {
    public var name: String
    public var width: Double // points
    public var height: Double

    public static let a4 = PageSize(name: "A4", width: 595.28, height: 841.89)
    public static let a5 = PageSize(name: "A5", width: 419.53, height: 595.28)
    public static let a3 = PageSize(name: "A3", width: 841.89, height: 1190.55)
    public static let letter = PageSize(name: "Letter", width: 612, height: 792)
    public static let square = PageSize(name: "Quadrato 210 mm", width: 595.28, height: 595.28)
    public static let all = [a4, a5, a3, letter, square]
}

public struct ParagraphStyleDoc: Codable, Hashable, Identifiable, Sendable {
    public var id = UUID()
    public var name: String
    public var fontName: String?
    public var size: Double
    public var weightBold = false
    public var leading: Double = 1.25
    public var color = RGBAColor.black
    public var alignment: Int = 0 // 0 left, 1 centre, 2 right, 3 justified
    public var spaceAfter: Double = 6

    public func attributes() -> [NSAttributedString.Key: Any] {
        let p = NSMutableParagraphStyle()
        p.alignment = [.left, .center, .right, .justified][min(3, max(0, alignment))]
        p.lineHeightMultiple = leading
        p.paragraphSpacing = spaceAfter
        p.hyphenationFactor = 0.8
        var font = fontName.flatMap { UIFont(name: $0, size: size) } ?? .systemFont(ofSize: size)
        if weightBold, let d = font.fontDescriptor.withSymbolicTraits(.traitBold) { font = UIFont(descriptor: d, size: size) }
        return [.font: font, .foregroundColor: color.uiColor, .paragraphStyle: p]
    }

    public static let defaults: [ParagraphStyleDoc] = [
        ParagraphStyleDoc(name: "Titolo", size: 32, weightBold: true, leading: 1.1, spaceAfter: 12),
        ParagraphStyleDoc(name: "Sottotitolo", size: 18, weightBold: true, leading: 1.2, color: RGBAColor(0.3, 0.3, 0.35), spaceAfter: 8),
        ParagraphStyleDoc(name: "Corpo", size: 11, leading: 1.35, alignment: 3),
        ParagraphStyleDoc(name: "Didascalia", size: 8.5, leading: 1.2, color: RGBAColor(0.4, 0.4, 0.4)),
    ]
}

public enum FrameContent: Codable, Hashable, Sendable {
    case text(String, style: UUID?)
    case image(String, fill: Bool)
    case rectangle(RGBAColor)
}

public struct LayoutFrame: Codable, Hashable, Identifiable, Sendable {
    public var id = UUID()
    public var rect: CGRect
    public var content: FrameContent
    public var columns = 1
    public var gutter: Double = 12
    public var stroke: Double = 0
}

public struct LayoutPage: Codable, Hashable, Identifiable, Sendable {
    public var id = UUID()
    public var frames: [LayoutFrame] = []
    public init() {}
}

public struct LayoutProject: ProjectPayload {
    public static let kind = StudioModule.layout
    public static let formatVersion = 1

    public var size = PageSize.a4
    public var marginTop: Double = 56
    public var marginBottom: Double = 56
    public var marginInside: Double = 56
    public var marginOutside: Double = 48
    public var columns = 2
    public var gutter: Double = 14
    public var baseline: Double = 14
    public var showGuides = true
    public var styles = ParagraphStyleDoc.defaults
    public var pages: [LayoutPage] = [LayoutPage()]
    public var pageNumbers = true

    public init() {}

    public func contentRect(page i: Int) -> CGRect {
        // facing pages: even indices are right-hand pages
        let left = i % 2 == 1
        let l = left ? marginOutside : marginInside, r = left ? marginInside : marginOutside
        return CGRect(x: l, y: marginTop, width: size.width - l - r, height: size.height - marginTop - marginBottom)
    }

    public func columnRects(page i: Int) -> [CGRect] {
        let c = contentRect(page: i)
        let n = max(1, columns)
        let w = (c.width - Double(n - 1) * gutter) / Double(n)
        return (0 ..< n).map { CGRect(x: c.minX + Double($0) * (w + gutter), y: c.minY, width: w, height: c.height) }
    }

    public func style(_ id: UUID?) -> ParagraphStyleDoc {
        styles.first { $0.id == id } ?? styles.first { $0.name == "Corpo" } ?? ParagraphStyleDoc.defaults[2]
    }
}

public enum LayoutRenderer {
    /// Draws page `i` (top-left origin, points). Returns whether some text did not fit its frame.
    @discardableResult
    public static func draw(_ doc: LayoutProject, page i: Int, in ctx: CGContext, projectURL: URL, guides: Bool) -> Bool {
        let page = doc.pages[i]
        let full = CGRect(x: 0, y: 0, width: doc.size.width, height: doc.size.height)
        ctx.setFillColor(UIColor.white.cgColor)
        ctx.fill(full)
        if guides {
            ctx.setStrokeColor(UIColor.systemPink.withAlphaComponent(0.5).cgColor)
            ctx.setLineWidth(0.5)
            ctx.stroke(doc.contentRect(page: i))
            ctx.setStrokeColor(UIColor.systemBlue.withAlphaComponent(0.35).cgColor)
            for c in doc.columnRects(page: i) { ctx.stroke(c) }
        }
        var overflow = false
        UIGraphicsPushContext(ctx)
        for f in page.frames {
            switch f.content {
            case .rectangle(let c):
                ctx.setFillColor(c.cgColor)
                ctx.fill(f.rect)
            case .image(let path, let fillFrame):
                if let img = loadImage(projectURL.appendingPathComponent(path)) {
                    ctx.saveGState()
                    ctx.clip(to: f.rect)
                    let iw = Double(img.width), ih = Double(img.height)
                    let s = fillFrame ? max(f.rect.width / iw, f.rect.height / ih) : min(f.rect.width / iw, f.rect.height / ih)
                    let r = CGRect(x: f.rect.midX - iw * s / 2, y: f.rect.midY - ih * s / 2, width: iw * s, height: ih * s)
                    UIImage(cgImage: img).draw(in: r)
                    ctx.restoreGState()
                } else if guides {
                    ctx.setStrokeColor(UIColor.gray.cgColor)
                    ctx.stroke(f.rect)
                }
            case .text(let s, let style):
                overflow = drawText(s, style: doc.style(style), frame: f) || overflow
            }
            if f.stroke > 0 {
                ctx.setStrokeColor(UIColor.black.cgColor)
                ctx.setLineWidth(f.stroke)
                ctx.stroke(f.rect)
            }
        }
        if doc.pageNumbers {
            let n = NSAttributedString(string: "\(i + 1)", attributes: [.font: UIFont.systemFont(ofSize: 9), .foregroundColor: UIColor.darkGray])
            let x = i % 2 == 1 ? doc.marginOutside : doc.size.width - doc.marginOutside - n.size().width
            n.draw(at: CGPoint(x: x, y: doc.size.height - doc.marginBottom / 2 - 5))
        }
        UIGraphicsPopContext()
        return overflow
    }

    /// Multi-column text with Core Text-free TextKit layout. Returns true when text overflows.
    static func drawText(_ s: String, style: ParagraphStyleDoc, frame f: LayoutFrame) -> Bool {
        let attr = NSAttributedString(string: s, attributes: style.attributes())
        let storage = NSTextStorage(attributedString: attr)
        let lm = NSLayoutManager()
        storage.addLayoutManager(lm)
        let n = max(1, f.columns)
        let w = (f.rect.width - Double(n - 1) * f.gutter) / Double(n)
        var containers: [NSTextContainer] = []
        for _ in 0 ..< n {
            let c = NSTextContainer(size: CGSize(width: w, height: f.rect.height))
            c.lineFragmentPadding = 0
            lm.addTextContainer(c)
            containers.append(c)
        }
        for (i, c) in containers.enumerated() {
            let range = lm.glyphRange(for: c)
            let origin = CGPoint(x: f.rect.minX + Double(i) * (w + f.gutter), y: f.rect.minY)
            lm.drawBackground(forGlyphRange: range, at: origin)
            lm.drawGlyphs(forGlyphRange: range, at: origin)
        }
        let used = containers.last.map { lm.glyphRange(for: $0) }.map { NSMaxRange($0) } ?? 0
        return used < lm.numberOfGlyphs
    }

    static func loadImage(_ url: URL) -> CGImage? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateThumbnailAtIndex(src, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                                            kCGImageSourceThumbnailMaxPixelSize: 3000,
                                                            kCGImageSourceCreateThumbnailWithTransform: true] as CFDictionary)
    }

    /// Exports every page to a PDF (fonts are embedded by the system PDF writer).
    public static func pdf(_ doc: LayoutProject, projectURL: URL) -> Data {
        let r = CGRect(x: 0, y: 0, width: doc.size.width, height: doc.size.height)
        let meta = UIGraphicsPDFRendererFormat()
        meta.documentInfo = [kCGPDFContextCreator as String: "Studio Creative Suite"]
        return UIGraphicsPDFRenderer(bounds: r, format: meta).pdfData { c in
            for i in doc.pages.indices {
                c.beginPage()
                draw(doc, page: i, in: c.cgContext, projectURL: projectURL, guides: false)
            }
        }
    }
}
