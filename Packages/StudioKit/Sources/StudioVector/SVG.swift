import CoreGraphics
import Foundation
import StudioCore

/// SVG 1.1 subset. Export: rect, ellipse, path, text, linear/radial gradients, groups per layer.
/// Import: rect, circle, ellipse, line, polyline, polygon, path (M L H V C S Q T Z, absolute and
/// relative; arcs are approximated with lines), fill/stroke/stroke-width/opacity via attributes or
/// `style`, `translate()` transforms, `<text>`. Filters, masks, clipping, CSS classes, `<use>` and
/// embedded images are not imported (see docs/FORMATS.md).
public enum SVG {
    // MARK: export

    public static func export(_ doc: VectorProject) -> String {
        var defs: [String] = []
        var body: [String] = []
        for layer in doc.layers where layer.visible {
            body.append("  <g id=\"\(esc(layer.name))\" opacity=\"\(n(layer.opacity))\">")
            for s in layer.shapes {
                var fill = "none"
                switch s.fill {
                case .none: break
                case .solid(let c): fill = c.hex + (c.a < 1 ? "\" fill-opacity=\"\(n(c.a))" : "")
                case .linear(let stops, let angle):
                    let id = "g\(defs.count)"
                    let r = angle * .pi / 180
                    defs.append("    <linearGradient id=\"\(id)\" x1=\"\(n(0.5 - cos(r) / 2))\" y1=\"\(n(0.5 - sin(r) / 2))\" x2=\"\(n(0.5 + cos(r) / 2))\" y2=\"\(n(0.5 + sin(r) / 2))\">"
                        + stops.map { "<stop offset=\"\(n($0.location))\" stop-color=\"\($0.color.hex)\" stop-opacity=\"\(n($0.color.a))\"/>" }.joined() + "</linearGradient>")
                    fill = "url(#\(id))"
                case .radial(let stops):
                    let id = "g\(defs.count)"
                    defs.append("    <radialGradient id=\"\(id)\">"
                        + stops.map { "<stop offset=\"\(n($0.location))\" stop-color=\"\($0.color.hex)\" stop-opacity=\"\(n($0.color.a))\"/>" }.joined() + "</radialGradient>")
                    fill = "url(#\(id))"
                }
                var common = "fill=\"\(fill)\""
                if s.strokeWidth > 0 { common += " stroke=\"\(s.stroke.hex)\" stroke-width=\"\(n(s.strokeWidth))\"" }
                if s.opacity < 1 { common += " opacity=\"\(n(s.opacity))\"" }
                if s.rotation != 0 { common += " transform=\"rotate(\(n(s.rotation)) \(n(s.bounds.midX)) \(n(s.bounds.midY)))\"" }
                let f = s.frame
                switch s.kind {
                case .rect(let r):
                    body.append("    <rect x=\"\(n(f.minX))\" y=\"\(n(f.minY))\" width=\"\(n(f.width))\" height=\"\(n(f.height))\" rx=\"\(n(r))\" \(common)/>")
                case .ellipse:
                    body.append("    <ellipse cx=\"\(n(f.midX))\" cy=\"\(n(f.midY))\" rx=\"\(n(f.width / 2))\" ry=\"\(n(f.height / 2))\" \(common)/>")
                case .path(let nodes, let closed):
                    body.append("    <path d=\"\(d([nodes], closed: closed))\" \(common)/>")
                case .compound(let subs):
                    body.append("    <path d=\"\(d(subs, closed: true))\" fill-rule=\"evenodd\" \(common)/>")
                case .text(let str, let size, let font):
                    let color = s.fill.solidColor?.hex ?? "#000000"
                    body.append("    <text x=\"\(n(f.minX))\" y=\"\(n(f.minY + size))\" font-size=\"\(n(size))\" font-family=\"\(esc(font ?? "Helvetica"))\" fill=\"\(color)\"\(s.opacity < 1 ? " opacity=\"\(n(s.opacity))\"" : "")>\(esc(str))</text>")
                }
            }
            body.append("  </g>")
        }
        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <svg xmlns="http://www.w3.org/2000/svg" width="\(n(doc.width))" height="\(n(doc.height))" viewBox="0 0 \(n(doc.width)) \(n(doc.height))">
          <defs>
        \(defs.joined(separator: "\n"))
          </defs>
          <rect width="100%" height="100%" fill="\(doc.background.hex)"/>
        \(body.joined(separator: "\n"))
        </svg>
        """
    }

    static func d(_ subs: [[BezierNode]], closed: Bool) -> String {
        var out: [String] = []
        for nodes in subs {
            guard let first = nodes.first else { continue }
            out.append("M\(n(first.point.x)) \(n(first.point.y))")
            for (a, b) in zip(nodes, nodes.dropFirst()) {
                if a.isCorner && b.isCorner { out.append("L\(n(b.point.x)) \(n(b.point.y))") } else {
                    out.append("C\(n(a.outHandle.x)) \(n(a.outHandle.y)) \(n(b.inHandle.x)) \(n(b.inHandle.y)) \(n(b.point.x)) \(n(b.point.y))")
                }
            }
            if closed, let last = nodes.last {
                if !(last.isCorner && first.isCorner) {
                    out.append("C\(n(last.outHandle.x)) \(n(last.outHandle.y)) \(n(first.inHandle.x)) \(n(first.inHandle.y)) \(n(first.point.x)) \(n(first.point.y))")
                }
                out.append("Z")
            }
        }
        return out.joined(separator: " ")
    }

    static func n(_ v: Double) -> String {
        let r = (v * 1000).rounded() / 1000
        return r == r.rounded() ? String(Int(r)) : String(r)
    }

    static func n(_ v: CGFloat) -> String { n(Double(v)) }

    static func esc(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
    }

    // MARK: import

    public struct ImportReport: Sendable {
        public var shapes = 0
        public var skipped: [String: Int] = [:]
    }

    public static func parse(_ data: Data) throws -> (VectorProject, ImportReport) {
        let p = Parser()
        let xml = XMLParser(data: data)
        xml.delegate = p
        guard xml.parse() else { throw StudioError.unsupportedFile("SVG non valido: \(xml.parserError?.localizedDescription ?? "")") }
        var doc = VectorProject()
        doc.width = p.width ?? 1000
        doc.height = p.height ?? 1000
        if let bg = p.background { doc.background = bg }
        doc.layers = [VectorLayer(name: "SVG importato")]
        doc.layers[0].shapes = p.shapes
        var r = ImportReport()
        r.shapes = p.shapes.count
        r.skipped = p.skipped
        return (doc, r)
    }

    final class Parser: NSObject, XMLParserDelegate {
        var width: Double?, height: Double?
        var background: RGBAColor?
        var shapes: [VectorShape] = []
        var skipped: [String: Int] = [:]
        var styleStack: [[String: String]] = [[:]]
        var offsetStack: [CGPoint] = [.zero]
        var textAttrs: [String: String]?
        var textBuf = ""
        var defsDepth = 0

        func parser(_ parser: XMLParser, didStartElement el: String, namespaceURI: String?, qualifiedName: String?, attributes a: [String: String] = [:]) {
            var style = styleStack.last ?? [:]
            for k in ["fill", "stroke", "stroke-width", "opacity", "fill-opacity", "font-size", "font-family"] { if let v = a[k] { style[k] = v } }
            if let s = a["style"] {
                for decl in s.split(separator: ";") {
                    let kv = decl.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
                    if kv.count == 2 { style[kv[0]] = kv[1] }
                }
            }
            var off = offsetStack.last ?? .zero
            if let t = a["transform"], let m = t.range(of: #"translate\(([^)]*)\)"#, options: .regularExpression) {
                let nums = Self.numbers(String(t[m]).replacingOccurrences(of: "translate", with: ""))
                off.x += nums.first ?? 0
                off.y += nums.count > 1 ? nums[1] : 0
            }
            styleStack.append(style)
            offsetStack.append(off)
            if el == "defs" { defsDepth += 1 }
            guard defsDepth == 0 else { return }
            let num = { (k: String) in Double(a[k]?.replacingOccurrences(of: "px", with: "") ?? "") }
            switch el {
            case "svg":
                width = num("width") ?? viewBox(a["viewBox"])?.2
                height = num("height") ?? viewBox(a["viewBox"])?.3
            case "rect":
                if a["width"] == "100%", a["height"] == "100%" {
                    // full-canvas rect = document background (as written by `export`)
                    if let c = Self.color(style["fill"]) { background = c }
                    return
                }
                guard let w = num("width"), let h = num("height") else { skipped["rect (unità non supportate)", default: 0] += 1; return }
                add(.rect(cornerRadius: num("rx") ?? 0), CGRect(x: (num("x") ?? 0) + off.x, y: (num("y") ?? 0) + off.y, width: w, height: h), style, "Rettangolo")
            case "circle":
                guard let r = num("r") else { return }
                add(.ellipse, CGRect(x: (num("cx") ?? 0) - r + off.x, y: (num("cy") ?? 0) - r + off.y, width: 2 * r, height: 2 * r), style, "Cerchio")
            case "ellipse":
                guard let rx = num("rx"), let ry = num("ry") else { return }
                add(.ellipse, CGRect(x: (num("cx") ?? 0) - rx + off.x, y: (num("cy") ?? 0) - ry + off.y, width: 2 * rx, height: 2 * ry), style, "Ellisse")
            case "line":
                let pts = [CGPoint(x: (num("x1") ?? 0) + off.x, y: (num("y1") ?? 0) + off.y), CGPoint(x: (num("x2") ?? 0) + off.x, y: (num("y2") ?? 0) + off.y)]
                var st = style
                st["fill"] = "none"
                addPath([pts.map { BezierNode($0) }], closed: false, st, "Linea")
            case "polyline", "polygon":
                let v = Self.numbers(a["points"] ?? "")
                let pts = stride(from: 0, to: v.count - 1, by: 2).map { BezierNode(CGPoint(x: v[$0] + off.x, y: v[$0 + 1] + off.y)) }
                addPath([pts], closed: el == "polygon", style, el == "polygon" ? "Poligono" : "Polilinea")
            case "path":
                let subs = PathData.parse(a["d"] ?? "", offset: off)
                let closed = (a["d"] ?? "").lowercased().contains("z")
                addPath(subs, closed: closed, style, "Tracciato")
            case "text":
                textAttrs = a
                textBuf = ""
            case "g", "title", "desc", "tspan", "metadata": break
            default:
                skipped[el, default: 0] += 1
            }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            if textAttrs != nil { textBuf += string }
        }

        func parser(_ parser: XMLParser, didEndElement el: String, namespaceURI: String?, qualifiedName: String?) {
            if el == "text", let a = textAttrs {
                let style = styleStack.last ?? [:]
                let size = Double(style["font-size"]?.replacingOccurrences(of: "px", with: "") ?? "") ?? 16
                let off = offsetStack.last ?? .zero
                let x = (Double(a["x"] ?? "") ?? 0) + off.x, y = (Double(a["y"] ?? "") ?? 0) + off.y
                let str = textBuf.trimmingCharacters(in: .whitespacesAndNewlines)
                if !str.isEmpty {
                    let sz = VectorRenderer.textSize(str, size: size, fontName: style["font-family"])
                    var s = VectorShape(name: "Testo", kind: .text(str, fontSize: size, fontName: style["font-family"]),
                                        frame: CGRect(x: x, y: y - size, width: sz.width, height: sz.height))
                    s.fill = .solid(Self.color(style["fill"]) ?? .black)
                    shapes.append(s)
                }
                textAttrs = nil
            }
            if el == "defs" { defsDepth -= 1 }
            styleStack.removeLast()
            offsetStack.removeLast()
        }

        func viewBox(_ s: String?) -> (Double, Double, Double, Double)? {
            let v = Self.numbers(s ?? "")
            return v.count == 4 ? (v[0], v[1], v[2], v[3]) : nil
        }

        func add(_ kind: ShapeKind, _ frame: CGRect, _ style: [String: String], _ name: String) {
            var s = VectorShape(name: name, kind: kind, frame: frame)
            apply(style, to: &s)
            shapes.append(s)
        }

        func addPath(_ subs: [[BezierNode]], closed: Bool, _ style: [String: String], _ name: String) {
            guard !subs.isEmpty else { return }
            let kind: ShapeKind = subs.count == 1 ? .path(nodes: subs[0], closed: closed) : .compound(subs)
            var s = VectorShape(name: name, kind: kind, frame: .zero)
            s.frame = s.basePath.boundingBoxOfPath
            apply(style, to: &s)
            shapes.append(s)
        }

        func apply(_ st: [String: String], to s: inout VectorShape) {
            // SVG default fill is black
            let f = st["fill"] ?? "#000000"
            if f == "none" { s.fill = .none } else if var c = Self.color(f) {
                if let fo = Double(st["fill-opacity"] ?? "") { c.a = fo }
                s.fill = .solid(c)
            } else { s.fill = .solid(.black) }
            if let sc = st["stroke"], sc != "none", let c = Self.color(sc) {
                s.stroke = c
                s.strokeWidth = Double(st["stroke-width"]?.replacingOccurrences(of: "px", with: "") ?? "") ?? 1
            }
            if let o = Double(st["opacity"] ?? "") { s.opacity = o }
        }

        static let named: [String: String] = ["black": "#000000", "white": "#ffffff", "red": "#ff0000", "green": "#008000", "blue": "#0000ff",
                                              "yellow": "#ffff00", "orange": "#ffa500", "purple": "#800080", "gray": "#808080", "grey": "#808080"]

        static func color(_ s: String?) -> RGBAColor? {
            guard var s = s?.trimmingCharacters(in: .whitespaces).lowercased() else { return nil }
            if let h = named[s] { s = h }
            if s.hasPrefix("rgb(") {
                let v = numbers(s)
                return v.count >= 3 ? RGBAColor(v[0] / 255, v[1] / 255, v[2] / 255) : nil
            }
            return RGBAColor(hex: s)
        }

        static let numberRegex = try! NSRegularExpression(pattern: #"[-+]?(?:\d+\.?\d*|\.\d+)(?:[eE][-+]?\d+)?"#)

        static func numbers(_ s: String) -> [Double] {
            let ns = s as NSString
            return numberRegex.matches(in: s, range: NSRange(location: 0, length: ns.length)).compactMap { Double(ns.substring(with: $0.range)) }
        }
    }
}

/// SVG path data parser.
enum PathData {
    static func parse(_ d: String, offset: CGPoint) -> [[BezierNode]] {
        var tokens: [(Character, [Double])] = []
        var cmd: Character?
        var buf = ""
        for ch in d {
            if "MmLlHhVvCcSsQqTtAaZz".contains(ch) {
                if let c = cmd { tokens.append((c, SVG.Parser.numbers(buf))) }
                cmd = ch
                buf = ""
            } else { buf.append(ch) }
        }
        if let c = cmd { tokens.append((c, SVG.Parser.numbers(buf))) }

        var subs: [[BezierNode]] = []
        var cur: [BezierNode] = []
        var p = CGPoint.zero, start = CGPoint.zero
        var lastCtrl: CGPoint?
        func flush() { if cur.count > 1 { subs.append(cur) }; cur = [] }
        func lineTo(_ q: CGPoint) { cur.append(BezierNode(q)); p = q; lastCtrl = nil }
        func curve(_ c1: CGPoint, _ c2: CGPoint, _ q: CGPoint) {
            if !cur.isEmpty { cur[cur.count - 1].outHandle = c1 }
            cur.append(BezierNode(q, in: c2))
            p = q
            lastCtrl = c2
        }
        for (c, v) in tokens {
            let rel = c.isLowercase
            let o = rel ? p : .zero
            switch c.uppercased().first! {
            case "M":
                guard v.count >= 2 else { continue }
                flush()
                p = CGPoint(x: v[0] + o.x, y: v[1] + o.y)
                start = p
                cur = [BezierNode(p)]
                var i = 2
                while i + 1 < v.count {
                    let b = rel ? p : .zero
                    lineTo(CGPoint(x: v[i] + b.x, y: v[i + 1] + b.y))
                    i += 2
                }
            case "L":
                var i = 0
                while i + 1 < v.count {
                    let b = rel ? p : .zero
                    lineTo(CGPoint(x: v[i] + b.x, y: v[i + 1] + b.y))
                    i += 2
                }
            case "H": for x in v { lineTo(CGPoint(x: x + (rel ? p.x : 0), y: p.y)) }
            case "V": for y in v { lineTo(CGPoint(x: p.x, y: y + (rel ? p.y : 0))) }
            case "C":
                var i = 0
                while i + 5 < v.count {
                    let b = rel ? p : .zero
                    curve(CGPoint(x: v[i] + b.x, y: v[i + 1] + b.y), CGPoint(x: v[i + 2] + b.x, y: v[i + 3] + b.y), CGPoint(x: v[i + 4] + b.x, y: v[i + 5] + b.y))
                    i += 6
                }
            case "S":
                var i = 0
                while i + 3 < v.count {
                    let b = rel ? p : .zero
                    let c1 = lastCtrl.map { CGPoint(x: 2 * p.x - $0.x, y: 2 * p.y - $0.y) } ?? p
                    curve(c1, CGPoint(x: v[i] + b.x, y: v[i + 1] + b.y), CGPoint(x: v[i + 2] + b.x, y: v[i + 3] + b.y))
                    i += 4
                }
            case "Q", "T":
                let isT = c.uppercased() == "T"
                var i = 0
                let step = isT ? 2 : 4
                while i + step - 1 < v.count {
                    let b = rel ? p : .zero
                    let ctrl = isT ? (lastCtrl.map { CGPoint(x: 2 * p.x - $0.x, y: 2 * p.y - $0.y) } ?? p) : CGPoint(x: v[i] + b.x, y: v[i + 1] + b.y)
                    let q = isT ? CGPoint(x: v[i] + b.x, y: v[i + 1] + b.y) : CGPoint(x: v[i + 2] + b.x, y: v[i + 3] + b.y)
                    let c1 = CGPoint(x: p.x + 2 / 3 * (ctrl.x - p.x), y: p.y + 2 / 3 * (ctrl.y - p.y))
                    let c2 = CGPoint(x: q.x + 2 / 3 * (ctrl.x - q.x), y: q.y + 2 / 3 * (ctrl.y - q.y))
                    curve(c1, c2, q)
                    lastCtrl = ctrl
                    i += step
                }
            case "A":
                // approximated by its end point (documented limitation)
                var i = 0
                while i + 6 < v.count {
                    let b = rel ? p : .zero
                    lineTo(CGPoint(x: v[i + 5] + b.x, y: v[i + 6] + b.y))
                    i += 7
                }
            case "Z":
                p = start
                flush()
            default: break
            }
        }
        flush()
        return subs.map { $0.map { BezierNode(CGPoint(x: $0.point.x + offset.x, y: $0.point.y + offset.y),
                                             in: CGPoint(x: $0.inHandle.x + offset.x, y: $0.inHandle.y + offset.y),
                                             out: CGPoint(x: $0.outHandle.x + offset.x, y: $0.outHandle.y + offset.y)) } }
    }
}
