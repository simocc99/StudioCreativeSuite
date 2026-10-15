import CoreGraphics
import CoreText
import Foundation
import StudioCore
import UIKit

/// Draws a vector document into a CGContext with a top-left origin (UIKit convention).
/// The same code draws the canvas, PNG/JPEG exports and PDF exports.
public enum VectorRenderer {
    public static func draw(_ doc: VectorProject, in ctx: CGContext, drawBackground: Bool = true) {
        if drawBackground {
            ctx.setFillColor(doc.background.cgColor)
            ctx.fill(CGRect(x: 0, y: 0, width: doc.width, height: doc.height))
        }
        for layer in doc.layers where layer.visible {
            ctx.saveGState()
            ctx.setAlpha(layer.opacity)
            ctx.beginTransparencyLayer(auxiliaryInfo: nil)
            for s in layer.shapes { draw(s, in: ctx) }
            ctx.endTransparencyLayer()
            ctx.restoreGState()
        }
    }

    public static func draw(_ s: VectorShape, in ctx: CGContext) {
        ctx.saveGState()
        ctx.setAlpha(s.opacity)
        if case .text(let str, let size, let font) = s.kind {
            ctx.concatenate(s.rotationTransform)
            drawText(str, size: size, fontName: font, color: s.fill.solidColor ?? .black, in: s.frame, ctx: ctx)
            ctx.restoreGState()
            return
        }
        let path = s.path
        let evenOdd: Bool = if case .compound = s.kind { true } else { false }
        switch s.fill {
        case .none: break
        case .solid(let c):
            ctx.addPath(path)
            ctx.setFillColor(c.cgColor)
            ctx.fillPath(using: evenOdd ? .evenOdd : .winding)
        case .linear(let stops, let angle):
            if let g = gradient(stops) {
                ctx.saveGState()
                ctx.addPath(path)
                evenOdd ? ctx.clip(using: .evenOdd) : ctx.clip()
                let b = path.boundingBoxOfPath
                let r = angle * .pi / 180
                let half = (abs(cos(r)) * b.width + abs(sin(r)) * b.height) / 2
                let start = CGPoint(x: b.midX - cos(r) * half, y: b.midY - sin(r) * half)
                let end = CGPoint(x: b.midX + cos(r) * half, y: b.midY + sin(r) * half)
                ctx.drawLinearGradient(g, start: start, end: end, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
                ctx.restoreGState()
            }
        case .radial(let stops):
            if let g = gradient(stops) {
                ctx.saveGState()
                ctx.addPath(path)
                evenOdd ? ctx.clip(using: .evenOdd) : ctx.clip()
                let b = path.boundingBoxOfPath
                ctx.drawRadialGradient(g, startCenter: b.center, startRadius: 0, endCenter: b.center,
                                       endRadius: max(b.width, b.height) / 2, options: [.drawsAfterEndLocation])
                ctx.restoreGState()
            }
        }
        if s.strokeWidth > 0 {
            ctx.addPath(path)
            ctx.setStrokeColor(s.stroke.cgColor)
            ctx.setLineWidth(s.strokeWidth)
            ctx.setLineJoin(.round)
            ctx.setLineCap(.round)
            ctx.strokePath()
        }
        ctx.restoreGState()
    }

    static func gradient(_ stops: [GradientStop]) -> CGGradient? {
        let sorted = stops.sorted { $0.location < $1.location }
        return CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: sorted.map(\.color.cgColor) as CFArray,
                          locations: sorted.map { CGFloat($0.location) })
    }

    public static func font(_ name: String?, size: Double) -> UIFont {
        if let name, let f = UIFont(name: name, size: size) { return f }
        return .systemFont(ofSize: size, weight: .semibold)
    }

    static func drawText(_ s: String, size: Double, fontName: String?, color: RGBAColor, in rect: CGRect, ctx: CGContext) {
        UIGraphicsPushContext(ctx)
        let attrs: [NSAttributedString.Key: Any] = [.font: font(fontName, size: size), .foregroundColor: color.uiColor]
        NSAttributedString(string: s, attributes: attrs).draw(with: rect, options: [.usesLineFragmentOrigin], context: nil)
        UIGraphicsPopContext()
    }

    /// Size a text shape needs for its string (width limited to `maxWidth`).
    public static func textSize(_ s: String, size: Double, fontName: String?, maxWidth: Double = 4000) -> CGSize {
        let attrs: [NSAttributedString.Key: Any] = [.font: font(fontName, size: size)]
        let r = NSAttributedString(string: s, attributes: attrs).boundingRect(with: CGSize(width: maxWidth, height: .greatestFiniteMagnitude),
                                                                               options: [.usesLineFragmentOrigin], context: nil)
        return CGSize(width: ceil(r.width) + 2, height: ceil(r.height) + 2)
    }

    // MARK: exports

    public static func png(_ doc: VectorProject, scale: Double, transparent: Bool = false) -> Data {
        image(doc, scale: scale, opaque: !transparent).pngData() ?? Data()
    }

    public static func jpeg(_ doc: VectorProject, scale: Double, quality: Double = 0.92) -> Data {
        image(doc, scale: scale, opaque: true).jpegData(compressionQuality: quality) ?? Data()
    }

    public static func image(_ doc: VectorProject, scale: Double, opaque: Bool) -> UIImage {
        let f = UIGraphicsImageRendererFormat()
        f.scale = scale
        f.opaque = opaque
        return UIGraphicsImageRenderer(size: CGSize(width: doc.width, height: doc.height), format: f).image { c in
            draw(doc, in: c.cgContext, drawBackground: opaque)
        }
    }

    public static func pdf(_ doc: VectorProject) -> Data {
        let r = CGRect(x: 0, y: 0, width: doc.width, height: doc.height)
        return UIGraphicsPDFRenderer(bounds: r).pdfData { c in
            c.beginPage()
            draw(doc, in: c.cgContext)
        }
    }
}
