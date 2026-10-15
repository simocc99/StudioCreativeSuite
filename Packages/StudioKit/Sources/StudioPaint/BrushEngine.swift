import CoreGraphics
import Foundation
import StudioCore
import UIKit

public enum BrushKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case round, pencil, marker, airbrush, ink, eraser
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .round: "Tondo"
        case .pencil: "Matita"
        case .marker: "Pennarello"
        case .airbrush: "Aerografo"
        case .ink: "Inchiostro"
        case .eraser: "Gomma"
        }
    }
    public var icon: String {
        switch self {
        case .round: "paintbrush.pointed"
        case .pencil: "pencil"
        case .marker: "highlighter"
        case .airbrush: "aqi.medium"
        case .ink: "scribble"
        case .eraser: "eraser"
        }
    }
}

public struct Brush: Codable, Hashable, Sendable {
    public var kind: BrushKind = .round
    public var size: Double = 24
    /// Per-stamp opacity (flow): overlapping stamps accumulate.
    public var opacity: Double = 1
    public var hardness: Double = 0.8
    /// Stamp spacing as a fraction of the size.
    public var spacing: Double = 0.12
    public var pressureSize = true
    public var pressureOpacity = false
    public var tiltShading = true
    public var color = RGBAColor.black

    public init(kind: BrushKind = .round) {
        self.kind = kind
        switch kind {
        case .round: break
        case .pencil: size = 6; hardness = 0.6; opacity = 0.7; spacing = 0.15
        case .marker: size = 40; hardness = 0.95; opacity = 0.25; pressureSize = false; spacing = 0.08
        case .airbrush: size = 120; hardness = 0; opacity = 0.06; pressureOpacity = true; pressureSize = false; spacing = 0.06
        case .ink: size = 10; hardness = 1; spacing = 0.05
        case .eraser: size = 40; hardness = 0.7
        }
    }
}

/// One input sample (canvas pixels).
public struct StrokeSample: Sendable {
    public var point: CGPoint
    /// 0…1 (1 for fingers / no pressure).
    public var pressure: Double
    /// Altitude angle in radians: π/2 = perpendicular to the screen.
    public var altitude: Double

    public init(point: CGPoint, pressure: Double = 1, altitude: Double = .pi / 2) {
        self.point = point
        self.pressure = pressure
        self.altitude = altitude
    }
}

/// Stamp-based rasteriser: stamps the brush tip along the stroke into a bitmap context.
public final class BrushEngine {
    public var brush: Brush { didSet { if brush.hardness != oldValue.hardness || brush.kind != oldValue.kind { stamp = Self.makeStamp(brush) } } }
    private var stamp: CGImage
    private var last: StrokeSample?
    private var residual: Double = 0

    public init(brush: Brush) {
        self.brush = brush
        stamp = Self.makeStamp(brush)
    }

    public func begin(_ s: StrokeSample, in ctx: CGContext) -> CGRect {
        last = s
        residual = 0
        return dab(s, in: ctx)
    }

    /// Continues the stroke to `s`; returns the dirty rect.
    public func move(to s: StrokeSample, in ctx: CGContext) -> CGRect {
        guard let a = last else { return begin(s, in: ctx) }
        let dist = hypot(s.point.x - a.point.x, s.point.y - a.point.y)
        let step = max(0.5, effectiveSize(s) * brush.spacing)
        var dirty = CGRect.null
        var t = step - residual
        while t <= dist {
            let u = t / max(dist, 1e-6)
            let p = StrokeSample(point: CGPoint(x: a.point.x + (s.point.x - a.point.x) * u, y: a.point.y + (s.point.y - a.point.y) * u),
                                 pressure: a.pressure + (s.pressure - a.pressure) * u, altitude: a.altitude + (s.altitude - a.altitude) * u)
            dirty = dirty.union(dab(p, in: ctx))
            t += step
        }
        residual = dist - (t - step)
        last = s
        return dirty
    }

    public func end() { last = nil }

    func effectiveSize(_ s: StrokeSample) -> Double {
        var size = brush.size
        if brush.pressureSize { size *= 0.2 + 0.8 * s.pressure }
        if brush.tiltShading, brush.kind == .pencil {
            // lying the Pencil flat widens the tip like graphite shading
            let tilt = 1 - min(1, s.altitude / (.pi / 2))
            size *= 1 + tilt * 4
        }
        return max(0.5, size)
    }

    func effectiveOpacity(_ s: StrokeSample) -> Double {
        var o = brush.opacity
        if brush.pressureOpacity { o *= s.pressure }
        if brush.tiltShading, brush.kind == .pencil {
            let tilt = 1 - min(1, s.altitude / (.pi / 2))
            o *= 1 - tilt * 0.6
        }
        return max(0, min(1, o))
    }

    private func dab(_ s: StrokeSample, in ctx: CGContext) -> CGRect {
        let size = effectiveSize(s)
        let r = CGRect(x: s.point.x - size / 2, y: s.point.y - size / 2, width: size, height: size)
        ctx.saveGState()
        if brush.kind == .eraser {
            ctx.setBlendMode(.destinationOut)
            ctx.setFillColor(UIColor.black.withAlphaComponent(effectiveOpacity(s)).cgColor)
        } else {
            ctx.setBlendMode(.normal)
            var c = brush.color
            c.a *= effectiveOpacity(s)
            ctx.setFillColor(c.cgColor)
        }
        ctx.clip(to: r, mask: stamp)
        ctx.fill(r)
        ctx.restoreGState()
        return r.insetBy(dx: -2, dy: -2)
    }

    /// Greyscale tip (white = paint). Pencil tips get grain.
    static func makeStamp(_ b: Brush) -> CGImage {
        let n = 128
        var px = [UInt8](repeating: 0, count: n * n)
        let hard = max(0, min(0.99, b.hardness))
        var rng = SplitMix(seed: 42)
        for y in 0 ..< n {
            for x in 0 ..< n {
                let dx = (Double(x) + 0.5) / Double(n) * 2 - 1, dy = (Double(y) + 0.5) / Double(n) * 2 - 1
                let d = sqrt(dx * dx + dy * dy)
                var a: Double = d >= 1 ? 0 : d <= hard ? 1 : 1 - (d - hard) / (1 - hard)
                a = a * a * (3 - 2 * a)
                if b.kind == .pencil { a *= 0.45 + 0.55 * rng.next() }
                if b.kind == .marker && d < 1 { a = min(1, a * 1.2) }
                px[y * n + x] = UInt8(max(0, min(255, a * 255)))
            }
        }
        // a DeviceGray image (not an image mask): clip(to:mask:) then uses each sample as alpha (white = paint)
        let provider = CGDataProvider(data: Data(px) as CFData)!
        return CGImage(width: n, height: n, bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: n, space: CGColorSpaceCreateDeviceGray(),
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue), provider: provider, decode: nil,
                       shouldInterpolate: true, intent: .defaultIntent)!
    }
}

struct SplitMix {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> Double {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return Double((z ^ (z >> 31)) >> 11) / Double(1 << 53)
    }
}

/// A premultiplied RGBA bitmap layer with a top-left origin.
public final class BitmapLayer {
    public let width: Int
    public let height: Int
    public let context: CGContext

    public init(width: Int, height: Int) {
        self.width = width
        self.height = height
        context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)
        context.interpolationQuality = .high
    }

    public convenience init(image: CGImage, width: Int, height: Int) {
        self.init(width: width, height: height)
        set(image)
    }

    public func makeImage() -> CGImage? { context.makeImage() }

    /// Replaces the contents with `image` (drawn upright).
    public func set(_ image: CGImage?) {
        context.saveGState()
        context.setBlendMode(.copy)
        context.clear(CGRect(x: 0, y: 0, width: width, height: height))
        if let image {
            // undo the flip for CGImage drawing so the image stays upright
            context.translateBy(x: 0, y: CGFloat(height))
            context.scaleBy(x: 1, y: -1)
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        context.restoreGState()
    }

    public func clear() { set(nil) }

    /// Colour of a pixel (top-left origin), un-premultiplied.
    public func color(at p: CGPoint) -> RGBAColor? {
        let x = Int(p.x), y = Int(p.y)
        guard x >= 0, y >= 0, x < width, y < height, let data = context.data else { return nil }
        let row = context.bytesPerRow
        let o = y * row + x * 4
        let b = data.assumingMemoryBound(to: UInt8.self)
        let a = Double(b[o + 3]) / 255
        guard a > 0 else { return RGBAColor(0, 0, 0, 0) }
        return RGBAColor(Double(b[o]) / 255 / a, Double(b[o + 1]) / 255 / a, Double(b[o + 2]) / 255 / a, a)
    }
}

public enum LayerBlend: String, Codable, CaseIterable, Sendable {
    case normal, multiply, screen, overlay, darken, lighten, colorDodge, colorBurn, softLight, hardLight, difference, color, luminosity
    public var title: String {
        switch self {
        case .normal: "Normale"
        case .multiply: "Moltiplica"
        case .screen: "Scolora"
        case .overlay: "Sovrapponi"
        case .darken: "Scurisci"
        case .lighten: "Schiarisci"
        case .colorDodge: "Colore schiarito"
        case .colorBurn: "Colore brucia"
        case .softLight: "Luce soffusa"
        case .hardLight: "Luce intensa"
        case .difference: "Differenza"
        case .color: "Colore"
        case .luminosity: "Luminosità"
        }
    }
    public var cgBlend: CGBlendMode {
        switch self {
        case .normal: .normal
        case .multiply: .multiply
        case .screen: .screen
        case .overlay: .overlay
        case .darken: .darken
        case .lighten: .lighten
        case .colorDodge: .colorDodge
        case .colorBurn: .colorBurn
        case .softLight: .softLight
        case .hardLight: .hardLight
        case .difference: .difference
        case .color: .color
        case .luminosity: .luminosity
        }
    }
}
