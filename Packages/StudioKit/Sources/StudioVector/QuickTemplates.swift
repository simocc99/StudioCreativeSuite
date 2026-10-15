import CoreGraphics
import Foundation
import StudioCore

/// Original quick-design templates (the "Express" workflow): editable vector documents.
public struct QuickTemplate: Identifiable, Sendable {
    public var id: String { name }
    public let name: String
    public let width: Double
    public let height: Double
    public let build: @Sendable (Double, Double) -> [VectorShape]

    public func document() -> VectorProject {
        var d = VectorProject()
        d.width = width
        d.height = height
        d.layers = [VectorLayer(name: "Grafica")]
        d.layers[0].shapes = build(width, height)
        return d
    }

    static func text(_ s: String, size: Double, at p: CGPoint, color: RGBAColor) -> VectorShape {
        let sz = VectorRenderer.textSize(s, size: size, fontName: nil)
        var t = VectorShape(name: "Testo", kind: .text(s, fontSize: size, fontName: nil), frame: CGRect(origin: p, size: sz))
        t.fill = .solid(color)
        return t
    }

    public static let all: [QuickTemplate] = [
        QuickTemplate(name: "Post quadrato 1080×1080", width: 1080, height: 1080) { w, h in
            var bg = VectorShape(name: "Sfondo", kind: .rect(cornerRadius: 0), frame: CGRect(x: 0, y: 0, width: w, height: h))
            bg.fill = .linear([GradientStop(location: 0, color: RGBAColor(0.98, 0.45, 0.3)), GradientStop(location: 1, color: RGBAColor(0.55, 0.2, 0.75))], angle: 45)
            var disc = VectorShape(name: "Cerchio", kind: .ellipse, frame: CGRect(x: w * 0.55, y: -h * 0.1, width: w * 0.6, height: w * 0.6))
            disc.fill = .solid(RGBAColor(1, 1, 1, 0.18))
            return [bg, disc, text("Il tuo titolo", size: 110, at: CGPoint(x: 80, y: h * 0.55), color: .white),
                    text("Sottotitolo o invito all'azione", size: 44, at: CGPoint(x: 84, y: h * 0.55 + 150), color: RGBAColor(1, 1, 1, 0.85))]
        },
        QuickTemplate(name: "Storia 1080×1920", width: 1080, height: 1920) { w, h in
            var bg = VectorShape(name: "Sfondo", kind: .rect(cornerRadius: 0), frame: CGRect(x: 0, y: 0, width: w, height: h))
            bg.fill = .linear([GradientStop(location: 0, color: RGBAColor(0.1, 0.12, 0.2)), GradientStop(location: 1, color: RGBAColor(0.15, 0.5, 0.6))], angle: 90)
            var card = VectorShape(name: "Riquadro", kind: .rect(cornerRadius: 48), frame: CGRect(x: 80, y: h * 0.35, width: w - 160, height: 600))
            card.fill = .solid(RGBAColor(1, 1, 1, 0.12))
            card.stroke = RGBAColor(1, 1, 1, 0.4)
            card.strokeWidth = 3
            return [bg, card, text("Novità", size: 140, at: CGPoint(x: 130, y: h * 0.35 + 80), color: .white),
                    text("Racconta qui la tua storia", size: 52, at: CGPoint(x: 134, y: h * 0.35 + 280), color: RGBAColor(1, 1, 1, 0.8))]
        },
        QuickTemplate(name: "Copertina 1920×1080", width: 1920, height: 1080) { w, h in
            var bg = VectorShape(name: "Sfondo", kind: .rect(cornerRadius: 0), frame: CGRect(x: 0, y: 0, width: w, height: h))
            bg.fill = .solid(RGBAColor(0.96, 0.95, 0.92))
            var band = VectorShape(name: "Fascia", kind: .rect(cornerRadius: 0), frame: CGRect(x: 0, y: h * 0.72, width: w, height: h * 0.28))
            band.fill = .solid(RGBAColor(0.12, 0.12, 0.14))
            return [bg, band, text("TITOLO DEL CANALE", size: 150, at: CGPoint(x: 120, y: h * 0.25), color: RGBAColor(0.12, 0.12, 0.14)),
                    text("episodi ogni settimana", size: 60, at: CGPoint(x: 124, y: h * 0.78), color: .white)]
        },
        QuickTemplate(name: "Locandina A4 (pt)", width: 595, height: 842) { w, h in
            var bg = VectorShape(name: "Sfondo", kind: .rect(cornerRadius: 0), frame: CGRect(x: 0, y: 0, width: w, height: h))
            bg.fill = .solid(RGBAColor(0.07, 0.2, 0.32))
            var sun = VectorShape(name: "Sole", kind: .ellipse, frame: CGRect(x: w / 2 - 160, y: 120, width: 320, height: 320))
            sun.fill = .radial([GradientStop(location: 0, color: RGBAColor(1, 0.85, 0.4)), GradientStop(location: 1, color: RGBAColor(0.95, 0.4, 0.2))])
            return [bg, sun, text("EVENTO", size: 72, at: CGPoint(x: 60, y: 500), color: .white),
                    text("Sabato · ore 21 · Piazza Centrale", size: 22, at: CGPoint(x: 62, y: 600), color: RGBAColor(1, 1, 1, 0.85))]
        },
    ]
}
