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

/// A slider bound to a settings path. Ranges and defaults follow LightCraft's control table
/// (crates/develop/src/controls.rs); paths are the JSON (snake_case) field names of `DevelopSettings`.
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

    public init(title: String, controls: [DevelopControl]) {
        self.title = title
        self.controls = controls
    }
}

/// The eight colour bands of the HSL mixer, B&W mixer and point colour (LightCraft order).
public struct ColorBand: Identifiable, Sendable {
    public var id: String { key }
    public let key: String
    public let name: String
    /// Hue in degrees, for the swatch in the UI.
    public let hue: Double
}

/// A colour-grading wheel (shadows, midtones, highlights, global).
public struct GradingWheel: Identifiable, Sendable {
    public var id: String { key }
    public let key: String
    public let name: String
}

/// A creative profile from LightCraft's registry (crates/pipeline/src/profiles.rs).
public struct DevelopProfile: Identifiable, Sendable {
    public let id: String
    public let name: String
    public let group: String
}

public enum DevelopControls {
    public static let whiteBalance = DevelopSection(title: "Bilanciamento del bianco", controls: [
        DevelopControl("wb.temp", "Temperatura (K)", 2000 ... 50000, step: 50),
        DevelopControl("wb.tint", "Tinta", -150 ... 150),
    ])

    public static let light = DevelopSection(title: "Luce", controls: [
        DevelopControl("light.exposure", "Esposizione", -5 ... 5, step: 0.01, decimals: 2),
        DevelopControl("light.contrast", "Contrasto", -100 ... 100),
        DevelopControl("light.highlights", "Alte luci", -100 ... 100),
        DevelopControl("light.shadows", "Ombre", -100 ... 100),
        DevelopControl("light.whites", "Bianchi", -100 ... 100),
        DevelopControl("light.blacks", "Neri", -100 ... 100),
    ])

    public static let presence = DevelopSection(title: "Presenza", controls: [
        DevelopControl("effects.texture", "Texture", -100 ... 100),
        DevelopControl("effects.clarity", "Chiarezza", -100 ... 100),
        DevelopControl("effects.dehaze", "Rimozione foschia", -100 ... 100),
        DevelopControl("color.vibrance", "Vividezza", -100 ... 100),
        DevelopControl("color.saturation", "Saturazione", -100 ... 100),
    ])

    public static let curveRegions = DevelopSection(title: "Curva parametrica", controls: [
        DevelopControl("curve.highlights", "Luci alte", -100 ... 100),
        DevelopControl("curve.lights", "Luci", -100 ... 100),
        DevelopControl("curve.darks", "Scuri", -100 ... 100),
        DevelopControl("curve.shadows", "Ombre", -100 ... 100),
        DevelopControl("curve.split_shadows", "Divisione ombre", 10 ... 70),
        DevelopControl("curve.split_mid", "Divisione mezzitoni", 20 ... 80),
        DevelopControl("curve.split_highlights", "Divisione luci", 30 ... 90),
        DevelopControl("curve.refine_saturation", "Affina saturazione", 0 ... 100),
    ])

    /// Point-curve channels: settings path and label.
    public static let curveChannels: [(path: String, name: String)] = [
        ("curve.master", "RGB"), ("curve.red", "Rosso"), ("curve.green", "Verde"), ("curve.blue", "Blu"),
    ]

    public static let bands: [ColorBand] = [
        ColorBand(key: "red", name: "Rossi", hue: 0), ColorBand(key: "orange", name: "Arancioni", hue: 30),
        ColorBand(key: "yellow", name: "Gialli", hue: 55), ColorBand(key: "green", name: "Verdi", hue: 120),
        ColorBand(key: "aqua", name: "Acqua", hue: 180), ColorBand(key: "blue", name: "Blu", hue: 225),
        ColorBand(key: "purple", name: "Viola", hue: 275), ColorBand(key: "magenta", name: "Magenta", hue: 315),
    ]

    /// HSL mixer: `component` is "hue", "sat" or "lum".
    public static func mixer(_ component: String) -> [DevelopControl] {
        bands.map { DevelopControl("mixer.\($0.key).\(component)", $0.name, -100 ... 100) }
    }

    public static let bwMix = DevelopSection(title: "Miscelatore bianco e nero",
                                             controls: bands.map { DevelopControl("bw_mix.\($0.key)", $0.name, -100 ... 100) })

    public static let wheels: [GradingWheel] = [
        GradingWheel(key: "shadows", name: "Ombre"), GradingWheel(key: "midtones", name: "Mezzitoni"),
        GradingWheel(key: "highlights", name: "Luci"), GradingWheel(key: "global", name: "Globale"),
    ]

    public static let gradingBlend = DevelopSection(title: "Fusione", controls: [
        DevelopControl("grading.blending", "Fusione", 0 ... 100),
        DevelopControl("grading.balance", "Bilanciamento", -100 ... 100),
    ])

    public static let vignette = DevelopSection(title: "Vignettatura", controls: [
        DevelopControl("vignette.amount", "Fattore", -100 ... 100),
        DevelopControl("vignette.midpoint", "Punto medio", 0 ... 100),
        DevelopControl("vignette.roundness", "Rotondità", -100 ... 100),
        DevelopControl("vignette.feather", "Sfumatura", 0 ... 100),
        DevelopControl("vignette.highlights", "Alte luci", 0 ... 100),
    ])

    public static let vignetteStyles: [(String, String)] = [
        ("highlightPriority", "Priorità luci"), ("colorPriority", "Priorità colore"), ("paintOverlay", "Sovrapposizione"),
    ]

    public static let grain = DevelopSection(title: "Grana", controls: [
        DevelopControl("grain.amount", "Fattore", 0 ... 100),
        DevelopControl("grain.size", "Dimensione", 0 ... 100),
        DevelopControl("grain.roughness", "Ruvidità", 0 ... 100),
    ])

    public static let sharpening = DevelopSection(title: "Nitidezza", controls: [
        DevelopControl("detail.sharpen_amount", "Fattore", 0 ... 150),
        DevelopControl("detail.sharpen_radius", "Raggio", 0.5 ... 3, step: 0.1, decimals: 1),
        DevelopControl("detail.sharpen_detail", "Dettaglio", 0 ... 100),
        DevelopControl("detail.sharpen_masking", "Mascheratura", 0 ... 100),
    ])

    public static let noise = DevelopSection(title: "Riduzione rumore", controls: [
        DevelopControl("detail.nr_luminance", "Luminanza", 0 ... 100),
        DevelopControl("detail.nr_detail", "Dettaglio", 0 ... 100),
        DevelopControl("detail.nr_contrast", "Contrasto", 0 ... 100),
        DevelopControl("detail.nr_color", "Colore", 0 ... 100),
        DevelopControl("detail.nr_color_detail", "Dettaglio colore", 0 ... 100),
        DevelopControl("detail.nr_color_smoothness", "Uniformità colore", 0 ... 100),
    ])

    public static let lensProfile = DevelopSection(title: "Profilo obiettivo", controls: [
        DevelopControl("optics.profile_distortion", "Distorsione profilo", 0 ... 200),
        DevelopControl("optics.profile_vignetting", "Vignettatura profilo", 0 ... 200),
    ])

    public static let manualOptics = DevelopSection(title: "Correzione manuale", controls: [
        DevelopControl("optics.distortion", "Distorsione", -100 ... 100),
        DevelopControl("optics.vignetting", "Vignettatura obiettivo", -100 ... 100),
        DevelopControl("optics.vignetting_midpoint", "Punto medio", 0 ... 100),
        DevelopControl("optics.ca_red", "Frange rosso/ciano", -100 ... 100),
        DevelopControl("optics.ca_blue", "Frange blu/giallo", -100 ... 100),
    ])

    public static let defringe = DevelopSection(title: "Rimuovi frange", controls: [
        DevelopControl("optics.defringe_purple_amount", "Viola: fattore", 0 ... 20),
        DevelopControl("optics.defringe_purple_hue_lo", "Viola: tonalità min", 0 ... 90),
        DevelopControl("optics.defringe_purple_hue_hi", "Viola: tonalità max", 10 ... 100),
        DevelopControl("optics.defringe_green_amount", "Verde: fattore", 0 ... 20),
        DevelopControl("optics.defringe_green_hue_lo", "Verde: tonalità min", 0 ... 90),
        DevelopControl("optics.defringe_green_hue_hi", "Verde: tonalità max", 10 ... 100),
    ])

    public static let geometry = DevelopSection(title: "Geometria", controls: [
        DevelopControl("crop.geometry.angle", "Raddrizza (°)", -45 ... 45, step: 0.1, decimals: 1),
        DevelopControl("geometry.vertical", "Verticale", -100 ... 100),
        DevelopControl("geometry.horizontal", "Orizzontale", -100 ... 100),
        DevelopControl("geometry.rotate", "Ruota (°)", -10 ... 10, step: 0.1, decimals: 1),
        DevelopControl("geometry.aspect", "Proporzioni", -100 ... 100),
        DevelopControl("geometry.scale", "Scala", 50 ... 150),
        DevelopControl("geometry.offset_x", "Spostamento X", -100 ... 100, step: 0.1, decimals: 1),
        DevelopControl("geometry.offset_y", "Spostamento Y", -100 ... 100, step: 0.1, decimals: 1),
    ])

    public static let calibration = DevelopSection(title: "Calibrazione", controls: [
        DevelopControl("calibration.shadows_tint", "Tinta ombre", -100 ... 100),
        DevelopControl("calibration.red_hue", "Rosso primario: tonalità", -100 ... 100),
        DevelopControl("calibration.red_sat", "Rosso primario: saturazione", -100 ... 100),
        DevelopControl("calibration.green_hue", "Verde primario: tonalità", -100 ... 100),
        DevelopControl("calibration.green_sat", "Verde primario: saturazione", -100 ... 100),
        DevelopControl("calibration.blue_hue", "Blu primario: tonalità", -100 ... 100),
        DevelopControl("calibration.blue_sat", "Blu primario: saturazione", -100 ... 100),
    ])

    /// Every slider, for validation and "reset section".
    public static var allSliders: [DevelopControl] {
        [whiteBalance, light, presence, curveRegions, bwMix, gradingBlend, vignette, grain, sharpening, noise,
         lensProfile, manualOptics, defringe, geometry, calibration].flatMap(\.controls)
            + ["hue", "sat", "lum"].flatMap(mixer)
            + wheels.flatMap { w in [
                DevelopControl("grading.\(w.key).hue", "Tonalità", 0 ... 360),
                DevelopControl("grading.\(w.key).sat", "Saturazione", 0 ... 100),
                DevelopControl("grading.\(w.key).lum", "Luminanza", -100 ... 100),
            ] }
            + [DevelopControl("profile.amount", "Intensità profilo", 0 ... 200)]
    }

    /// Kept for presets and older call sites: the tonal and colour sliders a preset resets.
    public static var sections: [DevelopSection] { [light, presence, curveRegions, vignette, grain] }

    /// White-balance presets (LightCraft `WbMode`, camelCase).
    public static let wbModes: [(String, String)] = [
        ("asShot", "Come scattato"), ("auto", "Automatico"), ("daylight", "Luce diurna"), ("cloudy", "Nuvoloso"),
        ("shade", "Ombra"), ("tungsten", "Tungsteno"), ("fluorescent", "Fluorescente"), ("flash", "Flash"), ("custom", "Personalizzato"),
    ]

    /// Orientation cycle for the rotate buttons (LightCraft `Orientation`).
    public static let rotations = ["Normal", "Rotate90", "Rotate180", "Rotate270"]

    public static let profiles: [DevelopProfile] = [
        DevelopProfile(id: "lc.color", name: "Colore", group: "Base"),
        DevelopProfile(id: "lc.neutral", name: "Neutro", group: "Base"),
        DevelopProfile(id: "lc.vivid", name: "Vivace", group: "Base"),
        DevelopProfile(id: "lc.landscape", name: "Paesaggio", group: "Base"),
        DevelopProfile(id: "lc.portrait", name: "Ritratto", group: "Base"),
        DevelopProfile(id: "lc.mono", name: "Monocromatico", group: "Base"),
        DevelopProfile(id: "lc.film.warm-print", name: "Stampa calda", group: "Pellicola"),
        DevelopProfile(id: "lc.film.cool-fade", name: "Sbiadito freddo", group: "Pellicola"),
        DevelopProfile(id: "lc.film.golden-hour", name: "Ora d'oro", group: "Pellicola"),
        DevelopProfile(id: "lc.film.faded-slide", name: "Diapositiva sbiadita", group: "Pellicola"),
        DevelopProfile(id: "lc.cine.teal-amber", name: "Ottanio e ambra", group: "Cinematografico"),
        DevelopProfile(id: "lc.cine.night-blue", name: "Blu notte", group: "Cinematografico"),
        DevelopProfile(id: "lc.cine.desert-heat", name: "Calore del deserto", group: "Cinematografico"),
        DevelopProfile(id: "lc.cine.neon-dusk", name: "Crepuscolo neon", group: "Cinematografico"),
        DevelopProfile(id: "lc.muted.matte-soft", name: "Opaco morbido", group: "Tenue"),
        DevelopProfile(id: "lc.muted.bleached", name: "Sbiancato", group: "Tenue"),
        DevelopProfile(id: "lc.muted.pastel-haze", name: "Foschia pastello", group: "Tenue"),
        DevelopProfile(id: "lc.muted.quiet-green", name: "Verde quieto", group: "Tenue"),
        DevelopProfile(id: "lc.bw.mono-rich", name: "B/N ricco", group: "Bianco e nero"),
        DevelopProfile(id: "lc.bw.red-filter", name: "B/N filtro rosso", group: "Bianco e nero"),
        DevelopProfile(id: "lc.bw.soft", name: "B/N morbido", group: "Bianco e nero"),
        DevelopProfile(id: "lc.bw.sepia", name: "Seppia", group: "Bianco e nero"),
    ]
}
