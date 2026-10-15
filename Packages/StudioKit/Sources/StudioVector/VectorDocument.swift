import CoreGraphics
import Foundation
import StudioCore

public struct VectorProject: ProjectPayload {
    public static let kind = StudioModule.vector
    public static let formatVersion = 1

    public var width: Double = 1920
    public var height: Double = 1080
    public var background = RGBAColor.white
    public var layers: [VectorLayer] = [VectorLayer(name: "Livello 1")]

    public init() {}

    public var allShapes: [VectorShape] { layers.flatMap(\.shapes) }

    public func locate(_ id: UUID) -> (Int, Int)? {
        for (li, l) in layers.enumerated() {
            if let si = l.shapes.firstIndex(where: { $0.id == id }) { return (li, si) }
        }
        return nil
    }

    public func shape(_ id: UUID) -> VectorShape? { locate(id).map { layers[$0.0].shapes[$0.1] } }

    public mutating func update(_ id: UUID, _ f: (inout VectorShape) -> Void) {
        guard let (l, s) = locate(id) else { return }
        f(&layers[l].shapes[s])
    }
}

public struct VectorLayer: Codable, Hashable, Identifiable, Sendable {
    public var id = UUID()
    public var name: String
    public var visible = true
    public var locked = false
    public var opacity: Double = 1
    public var shapes: [VectorShape] = []
    public init(name: String) { self.name = name }
}

/// A cubic Bézier anchor with absolute control handles (equal to `point` for a corner).
public struct BezierNode: Codable, Hashable, Sendable {
    public var point: CGPoint
    public var inHandle: CGPoint
    public var outHandle: CGPoint

    public init(_ p: CGPoint, in i: CGPoint? = nil, out o: CGPoint? = nil) {
        point = p
        inHandle = i ?? p
        outHandle = o ?? p
    }

    public var isCorner: Bool { inHandle == point && outHandle == point }
}

public struct GradientStop: Codable, Hashable, Sendable {
    public var location: Double
    public var color: RGBAColor
}

public enum Paint: Codable, Hashable, Sendable {
    case none
    case solid(RGBAColor)
    /// Linear gradient across the shape's bounds at `angle` degrees.
    case linear([GradientStop], angle: Double)
    /// Radial gradient from the centre of the bounds.
    case radial([GradientStop])

    public var solidColor: RGBAColor? { if case .solid(let c) = self { c } else { nil } }
}

public enum ShapeKind: Codable, Hashable, Sendable {
    case rect(cornerRadius: Double)
    case ellipse
    case path(nodes: [BezierNode], closed: Bool)
    /// Several subpaths (results of boolean operations), even-odd filled.
    case compound([[BezierNode]])
    case text(String, fontSize: Double, fontName: String?)
}

public struct VectorShape: Codable, Hashable, Identifiable, Sendable {
    public var id = UUID()
    public var name: String
    public var kind: ShapeKind
    /// Bounds for rect/ellipse/text, in document points. Path shapes keep absolute node coordinates.
    public var frame: CGRect
    public var rotation: Double = 0
    public var fill: Paint = .solid(RGBAColor(0.2, 0.45, 0.9))
    public var stroke = RGBAColor.black
    public var strokeWidth: Double = 0
    public var opacity: Double = 1
    public var groupID: UUID?

    public init(name: String, kind: ShapeKind, frame: CGRect) {
        self.name = name
        self.kind = kind
        self.frame = frame
    }

    /// Untransformed outline in document coordinates (text has no outline here; it is drawn by Core Text).
    public var basePath: CGPath {
        switch kind {
        case .rect(let r):
            return CGPath(roundedRect: frame, cornerWidth: min(r, frame.width / 2), cornerHeight: min(r, frame.height / 2), transform: nil)
        case .ellipse:
            return CGPath(ellipseIn: frame, transform: nil)
        case .path(let nodes, let closed):
            return Self.cgPath([nodes], closed: closed)
        case .compound(let subs):
            return Self.cgPath(subs, closed: true)
        case .text:
            return CGPath(rect: frame, transform: nil)
        }
    }

    /// Outline with the shape's rotation (about the bounds' centre) applied.
    public var path: CGPath {
        guard rotation != 0 else { return basePath }
        var t = rotationTransform
        return basePath.copy(using: &t) ?? basePath
    }

    public var rotationTransform: CGAffineTransform {
        let c = bounds.center
        return CGAffineTransform(translationX: c.x, y: c.y).rotated(by: rotation * .pi / 180).translatedBy(x: -c.x, y: -c.y)
    }

    public var bounds: CGRect {
        switch kind {
        case .path, .compound: basePath.boundingBoxOfPath
        default: frame
        }
    }

    static func cgPath(_ subpaths: [[BezierNode]], closed: Bool) -> CGPath {
        let p = CGMutablePath()
        for nodes in subpaths {
            guard let first = nodes.first else { continue }
            p.move(to: first.point)
            for (a, b) in zip(nodes, nodes.dropFirst()) {
                if a.isCorner && b.isCorner { p.addLine(to: b.point) } else { p.addCurve(to: b.point, control1: a.outHandle, control2: b.inHandle) }
            }
            if closed, nodes.count > 2, let last = nodes.last {
                if !(last.isCorner && first.isCorner) { p.addCurve(to: first.point, control1: last.outHandle, control2: first.inHandle) }
                p.closeSubpath()
            }
        }
        return p
    }

    /// Moves the shape by (dx, dy).
    public mutating func offset(dx: Double, dy: Double) {
        frame = frame.offsetBy(dx: dx, dy: dy)
        let move = { (n: BezierNode) -> BezierNode in
            BezierNode(CGPoint(x: n.point.x + dx, y: n.point.y + dy), in: CGPoint(x: n.inHandle.x + dx, y: n.inHandle.y + dy),
                       out: CGPoint(x: n.outHandle.x + dx, y: n.outHandle.y + dy))
        }
        switch kind {
        case .path(let nodes, let c): kind = .path(nodes: nodes.map(move), closed: c)
        case .compound(let s): kind = .compound(s.map { $0.map(move) })
        default: break
        }
    }

    /// Resizes to `rect` (paths are scaled about their bounds).
    public mutating func resize(to rect: CGRect) {
        let old = bounds
        frame = rect
        guard old.width > 0, old.height > 0 else { return }
        let sx = rect.width / old.width, sy = rect.height / old.height
        let map = { (p: CGPoint) -> CGPoint in CGPoint(x: rect.minX + (p.x - old.minX) * sx, y: rect.minY + (p.y - old.minY) * sy) }
        let mapN = { (n: BezierNode) -> BezierNode in BezierNode(map(n.point), in: map(n.inHandle), out: map(n.outHandle)) }
        switch kind {
        case .path(let nodes, let c): kind = .path(nodes: nodes.map(mapN), closed: c)
        case .compound(let s): kind = .compound(s.map { $0.map(mapN) })
        default: break
        }
    }
}

public extension CGRect {
    var center: CGPoint { CGPoint(x: midX, y: midY) }
}

// MARK: - boolean operations and alignment

public enum BooleanOp: String, CaseIterable, Sendable {
    case union, intersect, subtract, exclude
    public var title: String {
        switch self {
        case .union: "Unisci"
        case .intersect: "Interseca"
        case .subtract: "Sottrai"
        case .exclude: "Escludi"
        }
    }
}

public enum VectorOps {
    /// Combines shapes with CGPath's boolean operations (iOS 16+). The first shape's style is kept.
    public static func boolean(_ op: BooleanOp, _ shapes: [VectorShape]) -> VectorShape? {
        guard var acc = shapes.first?.path, shapes.count >= 2, let style = shapes.first else { return nil }
        for s in shapes.dropFirst() {
            let p = s.path
            switch op {
            case .union: acc = acc.union(p, using: .winding)
            case .intersect: acc = acc.intersection(p, using: .winding)
            case .subtract: acc = acc.subtracting(p, using: .winding)
            case .exclude: acc = acc.symmetricDifference(p, using: .winding)
            }
        }
        let subs = nodes(from: acc)
        guard !subs.isEmpty else { return nil }
        var out = VectorShape(name: op.title, kind: .compound(subs), frame: acc.boundingBoxOfPath)
        out.fill = style.fill
        out.stroke = style.stroke
        out.strokeWidth = style.strokeWidth
        out.opacity = style.opacity
        return out
    }

    /// Converts a CGPath into Bézier subpaths (quadratics are raised to cubics).
    public static func nodes(from path: CGPath) -> [[BezierNode]] {
        var subs: [[BezierNode]] = []
        var cur: [BezierNode] = []
        path.applyWithBlock { el in
            let e = el.pointee
            switch e.type {
            case .moveToPoint:
                if cur.count > 1 { subs.append(cur) }
                cur = [BezierNode(e.points[0])]
            case .addLineToPoint:
                cur.append(BezierNode(e.points[0]))
            case .addQuadCurveToPoint:
                guard let last = cur.last else { return }
                let c = e.points[0], p = e.points[1]
                let c1 = CGPoint(x: last.point.x + 2 / 3 * (c.x - last.point.x), y: last.point.y + 2 / 3 * (c.y - last.point.y))
                let c2 = CGPoint(x: p.x + 2 / 3 * (c.x - p.x), y: p.y + 2 / 3 * (c.y - p.y))
                cur[cur.count - 1].outHandle = c1
                cur.append(BezierNode(p, in: c2))
            case .addCurveToPoint:
                guard !cur.isEmpty else { return }
                cur[cur.count - 1].outHandle = e.points[0]
                cur.append(BezierNode(e.points[2], in: e.points[1]))
            case .closeSubpath:
                if cur.count > 1, let f = cur.first, let l = cur.last, hypot(f.point.x - l.point.x, f.point.y - l.point.y) < 0.001 {
                    cur[0].inHandle = l.inHandle
                    cur.removeLast()
                }
                if cur.count > 1 { subs.append(cur) }
                cur = []
            @unknown default: break
            }
        }
        if cur.count > 1 { subs.append(cur) }
        return subs
    }

    public enum Alignment: String, CaseIterable, Sendable { case left, centerX, right, top, centerY, bottom }

    /// Aligns shapes to the selection bounds (or the artboard for a single shape).
    public static func align(_ shapes: inout [VectorShape], _ a: Alignment, artboard: CGRect) {
        guard !shapes.isEmpty else { return }
        let ref = shapes.count == 1 ? artboard : shapes.map(\.bounds).reduce(shapes[0].bounds) { $0.union($1) }
        for i in shapes.indices {
            let b = shapes[i].bounds
            var dx = 0.0, dy = 0.0
            switch a {
            case .left: dx = ref.minX - b.minX
            case .centerX: dx = ref.midX - b.midX
            case .right: dx = ref.maxX - b.maxX
            case .top: dy = ref.minY - b.minY
            case .centerY: dy = ref.midY - b.midY
            case .bottom: dy = ref.maxY - b.maxY
            }
            shapes[i].offset(dx: dx, dy: dy)
        }
    }
}
