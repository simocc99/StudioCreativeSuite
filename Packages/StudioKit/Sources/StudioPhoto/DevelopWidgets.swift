import StudioCore
import SwiftUI

/// Colour-grading wheel: angle = hue (0…360°, clockwise from the right, red at 0°), distance
/// from the centre = saturation (0…100). Drag anywhere on the wheel to place the puck.
struct ColorWheel: View {
    let hue: Double
    let sat: Double
    let onChange: (_ hue: Double, _ sat: Double) -> Void
    let onEditing: (Bool) -> Void
    @State private var dragging = false

    var body: some View {
        GeometryReader { g in
            let size = min(g.size.width, g.size.height)
            let r = size / 2
            let center = CGPoint(x: g.size.width / 2, y: g.size.height / 2)
            let angle = hue * .pi / 180
            let reach = r * CGFloat(sat / 100)
            let puck = CGPoint(x: center.x + CGFloat(cos(angle)) * reach, y: center.y + CGFloat(sin(angle)) * reach)
            ZStack {
                Circle()
                    .fill(AngularGradient(colors: stride(from: 0.0, through: 360, by: 30).map { Color(hue: $0 / 360, saturation: 0.85, brightness: 0.95) },
                                          center: .center))
                    .frame(width: size, height: size)
                Circle()
                    .fill(RadialGradient(colors: [Color(white: 0.55), Color(white: 0.55).opacity(0)], center: .center, startRadius: 0, endRadius: r))
                    .frame(width: size, height: size)
                Circle().strokeBorder(StudioTheme.hairline, lineWidth: 1).frame(width: size, height: size)
                Path { p in
                    p.move(to: center)
                    p.addLine(to: puck)
                }
                .stroke(Color.white.opacity(0.5), lineWidth: 1)
                Circle()
                    .fill(Color(hue: hue / 360, saturation: sat / 100 * 0.85, brightness: 0.95))
                    .overlay(Circle().strokeBorder(Color.white, lineWidth: 2))
                    .frame(width: dragging ? 26 : 20, height: dragging ? 26 : 20)
                    .position(puck)
            }
            .contentShape(Circle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { v in
                        if !dragging { dragging = true; onEditing(true) }
                        let dx = v.location.x - center.x, dy = v.location.y - center.y
                        var h = Double(atan2(dy, dx)) * 180 / .pi
                        if h < 0 { h += 360 }
                        let s = min(100, Double((dx * dx + dy * dy).squareRoot() / r) * 100)
                        onChange(h.rounded(), s.rounded())
                    }
                    .onEnded { _ in dragging = false; onEditing(false) }
            )
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityElement()
        .accessibilityLabel("Ruota colore")
        .accessibilityValue("Tonalità \(Int(hue)) gradi, saturazione \(Int(sat))")
        .accessibilityAdjustableAction { dir in
            onEditing(true)
            onChange(hue, max(0, min(100, sat + (dir == .increment ? 5 : -5))))
            onEditing(false)
        }
    }
}

/// Point tone curve in 0…1: drag a point to move it, drag on empty space to add one, drag an inner
/// point out of the box to remove it.
/// The two end points stay at x = 0 and x = 1. Drawn with a monotone cubic, as the engine evaluates it.
struct ToneCurveEditor: View {
    let points: [CGPoint]
    let tint: Color
    let onChange: ([CGPoint]) -> Void
    let onEditing: (Bool) -> Void
    @State private var dragIndex: Int?

    private var pts: [CGPoint] {
        let p = points.sorted { $0.x < $1.x }
        return p.count >= 2 ? p : [CGPoint(x: 0, y: 0), CGPoint(x: 1, y: 1)]
    }

    var body: some View {
        GeometryReader { g in
            let w = g.size.width, h = g.size.height
            let toView = { (p: CGPoint) in CGPoint(x: p.x * w, y: (1 - p.y) * h) }
            let toCurve = { (v: CGPoint) in CGPoint(x: min(1, max(0, v.x / w)), y: min(1, max(0, 1 - v.y / h))) }
            ZStack {
                StudioTheme.canvas
                Path { p in
                    for i in 1 ..< 4 {
                        let f = CGFloat(i) / 4
                        p.move(to: CGPoint(x: f * w, y: 0)); p.addLine(to: CGPoint(x: f * w, y: h))
                        p.move(to: CGPoint(x: 0, y: f * h)); p.addLine(to: CGPoint(x: w, y: f * h))
                    }
                }
                .stroke(StudioTheme.hairline, lineWidth: 1)
                Path { p in
                    p.move(to: CGPoint(x: 0, y: h)); p.addLine(to: CGPoint(x: w, y: 0))
                }
                .stroke(Color.white.opacity(0.12), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                Path { p in
                    let samples = Self.sample(pts, count: 96)
                    p.move(to: toView(samples[0]))
                    for s in samples.dropFirst() { p.addLine(to: toView(s)) }
                }
                .stroke(tint, lineWidth: 2)
                ForEach(Array(pts.enumerated()), id: \.offset) { i, pt in
                    Circle()
                        .fill(dragIndex == i ? tint : StudioTheme.panel)
                        .overlay(Circle().strokeBorder(tint, lineWidth: 2))
                        .frame(width: 16, height: 16)
                        .position(toView(pt))
                        .allowsHitTesting(false)
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { v in
                        var p = pts
                        if dragIndex == nil {
                            let start = toCurve(v.startLocation)
                            if let near = p.indices.min(by: { hypot(p[$0].x - start.x, p[$0].y - start.y) < hypot(p[$1].x - start.x, p[$1].y - start.y) }),
                               hypot((p[near].x - start.x) * w, (p[near].y - start.y) * h) < 28 {
                                dragIndex = near
                            } else {
                                p.append(start)
                                p.sort { $0.x < $1.x }
                                dragIndex = p.firstIndex(of: start)
                            }
                            onEditing(true)
                        }
                        guard let i = dragIndex, i < p.count else { return }
                        // dragged out of the box: inner points are removed on release
                        if i > 0, i < p.count - 1, v.location.y < -24 || v.location.y > h + 24 { return }
                        var c = toCurve(v.location)
                        // ends stay on the edges; inner points stay between their neighbours
                        if i == 0 { c.x = 0 } else if i == p.count - 1 { c.x = 1 } else {
                            c.x = min(max(c.x, p[i - 1].x + 0.01), p[i + 1].x - 0.01)
                        }
                        p[i] = CGPoint(x: (c.x * 1000).rounded() / 1000, y: (c.y * 1000).rounded() / 1000)
                        onChange(p)
                    }
                    .onEnded { v in
                        if let i = dragIndex, i > 0, i < pts.count - 1, v.location.y < -24 || v.location.y > h + 24 {
                            var p = pts
                            p.remove(at: i)
                            onChange(p)
                        }
                        dragIndex = nil
                        onEditing(false)
                    }
            )
        }
        .aspectRatio(1, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(StudioTheme.hairline))
        .accessibilityElement()
        .accessibilityLabel("Curva di tono a punti")
        .accessibilityValue("\(pts.count) punti")
    }

    /// Monotone cubic (Fritsch–Carlson) through the points, sampled for drawing.
    static func sample(_ p: [CGPoint], count: Int) -> [CGPoint] {
        guard p.count > 1 else { return [CGPoint(x: 0, y: 0), CGPoint(x: 1, y: 1)] }
        let n = p.count
        var d = [CGFloat](repeating: 0, count: n - 1), m = [CGFloat](repeating: 0, count: n)
        for i in 0 ..< n - 1 { d[i] = (p[i + 1].y - p[i].y) / max(p[i + 1].x - p[i].x, 1e-6) }
        m[0] = d[0]
        m[n - 1] = d[n - 2]
        for i in 1 ..< n - 1 { m[i] = d[i - 1] * d[i] <= 0 ? 0 : (d[i - 1] + d[i]) / 2 }
        for i in 0 ..< n - 1 where d[i] == 0 { m[i] = 0; m[i + 1] = 0 }
        return (0 ... count).map { k in
            let x = CGFloat(k) / CGFloat(count)
            if x <= p[0].x { return CGPoint(x: x, y: p[0].y) }
            if x >= p[n - 1].x { return CGPoint(x: x, y: p[n - 1].y) }
            let i = max(0, min(n - 2, (p.lastIndex { $0.x <= x } ?? 0)))
            let hgt = p[i + 1].x - p[i].x
            let t = (x - p[i].x) / max(hgt, 1e-6)
            let t2 = t * t, t3 = t2 * t
            let y = (2 * t3 - 3 * t2 + 1) * p[i].y + (t3 - 2 * t2 + t) * hgt * m[i]
                + (-2 * t3 + 3 * t2) * p[i + 1].y + (t3 - t2) * hgt * m[i + 1]
            return CGPoint(x: x, y: min(1, max(0, y)))
        }
    }
}
