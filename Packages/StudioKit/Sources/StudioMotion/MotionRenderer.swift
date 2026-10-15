import CoreGraphics
import CoreImage
import Foundation
import ImageIO
import StudioCore
import UIKit

/// Renders a composition frame with Core Graphics (top-left origin). Used by the preview and the exporters.
public final class MotionRenderer: @unchecked Sendable {
    private var images: [String: CGImage] = [:]
    private let projectURL: URL
    private let ci = CIContext()

    public init(projectURL: URL) { self.projectURL = projectURL }

    func image(_ path: String) -> CGImage? {
        if let i = images[path] { return i }
        guard let src = CGImageSourceCreateWithURL(projectURL.appendingPathComponent(path) as CFURL, nil),
              let img = CGImageSourceCreateImageAtIndex(src, 0, nil) else { return nil }
        images[path] = img
        return img
    }

    public func draw(_ p: MotionProject, at t: Double, in ctx: CGContext) {
        ctx.setFillColor(p.background.cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: p.width, height: p.height))
        for l in p.layers where l.visible && t >= l.inPoint && t < l.outPoint {
            draw(l, comp: p, at: t, in: ctx)
        }
    }

    func draw(_ l: MotionLayer, comp: MotionProject, at t: Double, in ctx: CGContext) {
        let opacity = l.opacity.at(t) / 100
        guard opacity > 0.001 else { return }
        let s = l.scale.at(t) / 100
        let blur = l.blur.at(t)
        if blur > 0.5 {
            // rasterise the layer, blur it with Core Image, then draw the result
            guard let flat = rasterise(l, comp: comp, at: t) else { return }
            let input = CIImage(cgImage: flat)
            let out = input.clampedToExtent().applyingGaussianBlur(sigma: blur).cropped(to: input.extent)
            guard let cg = ci.createCGImage(out, from: input.extent) else { return }
            ctx.saveGState()
            ctx.translateBy(x: 0, y: CGFloat(comp.height))
            ctx.scaleBy(x: 1, y: -1)
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: comp.width, height: comp.height))
            ctx.restoreGState()
            return
        }
        ctx.saveGState()
        ctx.setAlpha(opacity)
        ctx.translateBy(x: l.x.at(t), y: l.y.at(t))
        ctx.rotate(by: l.rotation.at(t) * .pi / 180)
        ctx.scaleBy(x: s, y: s)
        let r = CGRect(x: -l.width / 2, y: -l.height / 2, width: l.width, height: l.height)
        applyMask(l, rect: r, at: t, ctx: ctx)
        ctx.setFillColor(l.color.cgColor)
        switch l.kind {
        case .rectangle(let cr):
            ctx.addPath(CGPath(roundedRect: r, cornerWidth: min(cr, r.width / 2), cornerHeight: min(cr, r.height / 2), transform: nil))
            ctx.fillPath()
        case .ellipse:
            ctx.fillEllipse(in: r)
        case .star(let n):
            ctx.addPath(Self.star(in: r, points: max(3, n)))
            ctx.fillPath()
        case .solid:
            ctx.fill(r)
        case .text(let str, let size):
            drawText(l, str, size: size, rect: r, at: t, ctx: ctx)
        case .image(let path):
            if let img = image(path) {
                ctx.saveGState()
                ctx.translateBy(x: 0, y: r.maxY + r.minY)
                ctx.scaleBy(x: 1, y: -1)
                ctx.draw(img, in: r)
                ctx.restoreGState()
            }
        }
        ctx.restoreGState()
    }

    private func rasterise(_ l: MotionLayer, comp: MotionProject, at t: Double) -> CGImage? {
        guard let c = CGContext(data: nil, width: comp.width, height: comp.height, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        c.translateBy(x: 0, y: CGFloat(comp.height))
        c.scaleBy(x: 1, y: -1)
        var copy = l
        copy.blur = AnimatedValue(0)
        draw(copy, comp: comp, at: t, in: c)
        return c.makeImage()
    }

    private func applyMask(_ l: MotionLayer, rect r: CGRect, at t: Double, ctx: CGContext) {
        guard l.mask != .none else { return }
        let reveal = max(0, min(1, l.maskReveal.at(t) / 100))
        // the mask grows from the centre as `reveal` goes 0 → 1
        let m = CGRect(x: r.midX - r.width * reveal / 2, y: r.midY - r.height * reveal / 2, width: r.width * reveal, height: r.height * reveal)
        switch l.mask {
        case .rectangle: ctx.addRect(m)
        case .ellipse: ctx.addEllipse(in: m)
        case .none: return
        }
        ctx.clip()
    }

    private func drawText(_ l: MotionLayer, _ str: String, size: Double, rect: CGRect, at t: Double, ctx: CGContext) {
        let progress = max(0, min(1, l.textProgress.at(t) / 100))
        UIGraphicsPushContext(ctx)
        defer { UIGraphicsPopContext() }
        let para = NSMutableParagraphStyle()
        para.alignment = .center
        let font = UIFont.systemFont(ofSize: size, weight: .bold)
        let full = NSMutableAttributedString(string: str, attributes: [.font: font, .foregroundColor: l.color.uiColor, .paragraphStyle: para])
        switch l.textAnimation {
        case .none: break
        case .typewriter:
            let n = Int((Double(str.count) * progress).rounded())
            let ns = str as NSString
            let cut = (str.prefix(n) as Substring).utf16.count
            full.addAttribute(.foregroundColor, value: UIColor.clear, range: NSRange(location: cut, length: ns.length - cut))
        case .fadeByWord:
            let words = str.split(separator: " ", omittingEmptySubsequences: false)
            var loc = 0
            for (i, w) in words.enumerated() {
                let len = w.utf16.count
                let wp = max(0, min(1, progress * Double(words.count) - Double(i)))
                full.addAttribute(.foregroundColor, value: l.color.uiColor.withAlphaComponent(l.color.a * wp), range: NSRange(location: loc, length: len))
                loc += len + 1
            }
        }
        let bounds = full.boundingRect(with: CGSize(width: rect.width, height: .greatestFiniteMagnitude), options: [.usesLineFragmentOrigin], context: nil)
        full.draw(with: CGRect(x: rect.minX, y: rect.midY - bounds.height / 2, width: rect.width, height: bounds.height), options: [.usesLineFragmentOrigin], context: nil)
    }

    static func star(in r: CGRect, points n: Int) -> CGPath {
        let p = CGMutablePath()
        for i in 0 ..< n * 2 {
            let a = Double(i) * .pi / Double(n) - .pi / 2
            let rad = i % 2 == 0 ? 1.0 : 0.45
            let pt = CGPoint(x: r.midX + cos(a) * r.width / 2 * rad, y: r.midY + sin(a) * r.height / 2 * rad)
            i == 0 ? p.move(to: pt) : p.addLine(to: pt)
        }
        p.closeSubpath()
        return p
    }

    public func frameImage(_ p: MotionProject, at t: Double, scale: Double = 1) -> CGImage? {
        let w = Int(Double(p.width) * scale), h = Int(Double(p.height) * scale)
        guard let c = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        c.translateBy(x: 0, y: CGFloat(h))
        c.scaleBy(x: scale, y: -scale)
        draw(p, at: t, in: c)
        return c.makeImage()
    }
}
