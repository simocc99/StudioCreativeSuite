import Foundation
import StudioCore

/// A develop project: one original (copied into the project's Media folder, never modified)
/// and the engine settings applied to it.
public struct PhotoProject: ProjectPayload {
    public static let kind = StudioModule.photo
    public static let formatVersion = 1

    /// Path relative to the project folder.
    public var source: String?
    /// LightCraft `DevelopSettings` JSON (engine-owned schema, kept whole).
    public var settings: JSONValue?
    public var rating: Int = 0
    public var notes: String = ""

    public init() {}
}

/// A slider bound to a settings path. Ranges follow LightCraft's control table (crates/develop/src/controls.rs).
public struct DevelopControl: Identifiable, Sendable {
    public var id: String { path }
    public let path: String
    public let label: String
    public let range: ClosedRange<Double>
    public let step: Double
    public let decimals: Int

    public init(_ path: String, _ label: String, _ range: ClosedRange<Double>, step: Double = 1, decimals: Int = 0) {
        self.path = path
        self.label = label
        self.range = range
        self.step = step
        self.decimals = decimals
    }
}

public struct DevelopSection: Identifiable, Sendable {
    public var id: String { title }
    public let title: String
    public let controls: [DevelopControl]
}

public enum DevelopControls {
    public static let whiteBalance = DevelopSection(title: "Bilanciamento del bianco", controls: [
        DevelopControl("wb.temp", "Temperatura (K)", 2000 ... 50000, step: 50),
        DevelopControl("wb.tint", "Tinta", -150 ... 150),
    ])

    public static let sections: [DevelopSection] = [
        DevelopSection(title: "Luce", controls: [
            DevelopControl("light.exposure", "Esposizione", -5 ... 5, step: 0.01, decimals: 2),
            DevelopControl("light.contrast", "Contrasto", -100 ... 100),
            DevelopControl("light.highlights", "Alte luci", -100 ... 100),
            DevelopControl("light.shadows", "Ombre", -100 ... 100),
            DevelopControl("light.whites", "Bianchi", -100 ... 100),
            DevelopControl("light.blacks", "Neri", -100 ... 100),
        ]),
        DevelopSection(title: "Curva di tono", controls: [
            DevelopControl("curve.highlights", "Luci alte", -100 ... 100),
            DevelopControl("curve.lights", "Luci", -100 ... 100),
            DevelopControl("curve.darks", "Scuri", -100 ... 100),
            DevelopControl("curve.shadows", "Ombre", -100 ... 100),
        ]),
        DevelopSection(title: "Presenza e colore", controls: [
            DevelopControl("effects.texture", "Texture", -100 ... 100),
            DevelopControl("effects.clarity", "Chiarezza", -100 ... 100),
            DevelopControl("effects.dehaze", "Rimozione foschia", -100 ... 100),
            DevelopControl("color.vibrance", "Vividezza", -100 ... 100),
            DevelopControl("color.saturation", "Saturazione", -100 ... 100),
        ]),
        DevelopSection(title: "Miscelatore colore (saturazione)", controls: ["red": "Rossi", "orange": "Arancioni", "yellow": "Gialli", "green": "Verdi", "aqua": "Acqua", "blue": "Blu", "purple": "Viola", "magenta": "Magenta"]
            .sorted { bandOrder($0.key) < bandOrder($1.key) }
            .map { DevelopControl("mixer.\($0.key).sat", $0.value, -100 ... 100) }),
        DevelopSection(title: "Dettaglio", controls: [
            DevelopControl("detail.sharpen_amount", "Nitidezza", 0 ... 150),
            DevelopControl("detail.sharpen_radius", "Raggio", 0.5 ... 3, step: 0.1, decimals: 1),
            DevelopControl("detail.nr_luminance", "Riduzione rumore", 0 ... 100),
            DevelopControl("detail.nr_color", "Rumore colore", 0 ... 100),
        ]),
        DevelopSection(title: "Effetti", controls: [
            DevelopControl("vignette.amount", "Vignettatura", -100 ... 100),
            DevelopControl("grain.amount", "Grana", 0 ... 100),
        ]),
        DevelopSection(title: "Geometria", controls: [
            DevelopControl("crop.geometry.angle", "Raddrizza (°)", -45 ... 45, step: 0.1, decimals: 1),
            DevelopControl("geometry.vertical", "Verticale", -100 ... 100),
            DevelopControl("geometry.horizontal", "Orizzontale", -100 ... 100),
        ]),
    ]

    static func bandOrder(_ b: String) -> Int {
        ["red", "orange", "yellow", "green", "aqua", "blue", "purple", "magenta"].firstIndex(of: b) ?? 0
    }

    /// White-balance presets (LightCraft `WbMode`, camelCase).
    public static let wbModes: [(String, String)] = [
        ("asShot", "Come scattato"), ("auto", "Automatico"), ("daylight", "Luce diurna"), ("cloudy", "Nuvoloso"),
        ("shade", "Ombra"), ("tungsten", "Tungsteno"), ("fluorescent", "Fluorescente"), ("flash", "Flash"), ("custom", "Personalizzato"),
    ]

    /// Orientation cycle for the rotate buttons (LightCraft `Orientation`).
    public static let rotations = ["Normal", "Rotate90", "Rotate180", "Rotate270"]
}

/// Built-in presets: partial settings merged over the current ones.
public struct DevelopPreset: Identifiable, Sendable {
    public var id: String { name }
    public let name: String
    public let values: [String: Double]
    public let treatment: String?

    public static let builtIn: [DevelopPreset] = [
        DevelopPreset(name: "Neutro", values: [:], treatment: nil),
        DevelopPreset(name: "Contrasto vivace", values: ["light.contrast": 25, "color.vibrance": 20, "effects.clarity": 10], treatment: nil),
        DevelopPreset(name: "Morbido", values: ["light.contrast": -15, "light.highlights": -30, "light.shadows": 25, "effects.clarity": -10], treatment: nil),
        DevelopPreset(name: "Paesaggio", values: ["effects.dehaze": 15, "color.vibrance": 25, "light.highlights": -40, "light.shadows": 30], treatment: nil),
        DevelopPreset(name: "Bianco e nero", values: ["light.contrast": 20], treatment: "bw"),
        DevelopPreset(name: "Pellicola", values: ["grain.amount": 25, "vignette.amount": -15, "light.contrast": 10, "color.saturation": -10], treatment: nil),
    ]

    public func apply(to settings: JSONValue, defaults: JSONValue) -> JSONValue {
        var s = settings
        // a preset is relative to the engine's starting point, not stacked on the previous preset
        for c in DevelopControls.sections.flatMap(\.controls) {
            s[path: c.path] = defaults[path: c.path]
        }
        for (k, v) in values { s[path: k] = .number(v) }
        s[path: "treatment"] = .string(treatment ?? (defaults[path: "treatment"]?.stringValue ?? "color"))
        return s
    }
}
