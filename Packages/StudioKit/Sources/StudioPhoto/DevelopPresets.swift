import Foundation
import StudioCore

/// A value in a preset: a number (interpolated by the preset amount) or a string (profile, treatment…).
public enum PresetValue: Sendable, Hashable, ExpressibleByFloatLiteral, ExpressibleByIntegerLiteral, ExpressibleByStringLiteral {
    case number(Double)
    case text(String)

    public init(floatLiteral v: Double) { self = .number(v) }
    public init(integerLiteral v: Int) { self = .number(Double(v)) }
    public init(stringLiteral v: String) { self = .text(v) }

    public var json: JSONValue {
        switch self {
        case .number(let n): .number(n)
        case .text(let s): .string(s)
        }
    }
}

/// A develop preset: values at settings paths. Applying it first returns the "look" (profile,
/// tone, colour, grading, effects) to the engine's defaults, so presets never stack on each other;
/// exposure, white balance, detail, optics and geometry stay as the user set them unless the
/// preset names them. Preset white balance is relative to the photo's "as shot". `amount` (0…2) interpolates numbers between the current settings and the
/// preset, like Lightroom's preset amount.
public struct DevelopPreset: Identifiable, Sendable, Hashable {
    public var id: String { "\(group)/\(name)" }
    public let group: String
    public let name: String
    public let values: [String: PresetValue]

    public init(_ group: String, _ name: String, _ values: [String: PresetValue]) {
        self.group = group
        self.name = name
        self.values = values
    }

    /// Paths a preset resets before applying its own values.
    public static let lookPaths: [String] = {
        var p = ["profile.id", "profile.amount", "treatment",
                 "light.contrast", "light.highlights", "light.shadows", "light.whites", "light.blacks",
                 "curve.master", "curve.red", "curve.green", "curve.blue"]
        p += (DevelopControls.presence.controls + DevelopControls.curveRegions.controls + DevelopControls.bwMix.controls
            + DevelopControls.gradingBlend.controls + DevelopControls.vignette.controls + DevelopControls.grain.controls
            + DevelopControls.calibration.controls).map(\.path)
        p += ["hue", "sat", "lum"].flatMap(DevelopControls.mixer).map(\.path)
        p += DevelopControls.wheels.flatMap { w in ["hue", "sat", "lum"].map { "grading.\(w.key).\($0)" } }
        return p
    }()

    public func apply(to base: JSONValue, defaults: JSONValue, amount: Double = 1) -> JSONValue {
        var target = base
        for path in Self.lookPaths {
            if let d = defaults[path: path] { target[path: path] = d }
        }
        for (k, v) in values { target[path: k] = v.json }
        // White balance in presets is written as if "as shot" were 6500 K / tint 0: it becomes a
        // shift from this photo's own as-shot values (in mireds for temperature), so a "warm"
        // preset warms a tungsten shot instead of turning it orange.
        if case .number(let k)? = values["wb.temp"]?.json, let shot = defaults[path: "wb.temp"]?.doubleValue, k > 0, shot > 0 {
            let mired = 1e6 / shot + (1e6 / k - 1e6 / 6500)
            target[path: "wb.temp"] = .number((min(50000, max(2000, 1e6 / mired)) / 10).rounded() * 10)
        }
        if case .number(let t)? = values["wb.tint"]?.json, let shot = defaults[path: "wb.tint"]?.doubleValue {
            target[path: "wb.tint"] = .number(min(150, max(-150, shot + t)))
        }
        if amount == 1 { return target }
        var out = base
        for path in Set(Self.lookPaths + values.keys) {
            guard let t = target[path: path] else { continue }
            if case .number(let b) = target[path: path], case .number(let a)? = base[path: path] {
                out[path: path] = .number(a + (b - a) * amount)
            } else if amount > 0 {
                out[path: path] = t
            }
        }
        return out
    }

    public static var groups: [String] {
        var seen = Set<String>()
        return builtIn.map(\.group).filter { seen.insert($0).inserted }
    }

    // swiftlint:disable line_length
    public static let builtIn: [DevelopPreset] = [
        // Correzioni rapide
        DevelopPreset("Correzioni", "Neutro", [:]),
        DevelopPreset("Correzioni", "Recupera alte luci", ["light.highlights": -70, "light.whites": -20, "curve.highlights": -15]),
        DevelopPreset("Correzioni", "Apri le ombre", ["light.shadows": 60, "light.blacks": 15, "curve.shadows": 10]),
        DevelopPreset("Correzioni", "Gamma estesa", ["light.highlights": -60, "light.shadows": 50, "light.whites": 15, "light.blacks": -15, "effects.clarity": 8]),
        DevelopPreset("Correzioni", "Più contrasto", ["light.contrast": 30, "curve.lights": 10, "curve.darks": -10]),
        DevelopPreset("Correzioni", "Meno foschia", ["effects.dehaze": 30, "light.contrast": 8, "color.vibrance": 10]),
        DevelopPreset("Correzioni", "Nitido e pulito", ["effects.texture": 20, "effects.clarity": 12, "detail.sharpen_amount": 60, "detail.sharpen_masking": 30]),
        DevelopPreset("Correzioni", "Riduci rumore", ["detail.nr_luminance": 40, "detail.nr_color": 35, "detail.sharpen_amount": 25, "detail.sharpen_masking": 50]),
        DevelopPreset("Correzioni", "Correggi obiettivo", ["optics.defringe_purple_amount": 4, "optics.ca_red": 0, "optics.vignetting": 30]),

        // Ritratto
        DevelopPreset("Ritratto", "Pelle morbida", ["profile.id": "lc.portrait", "effects.texture": -25, "effects.clarity": -10, "light.highlights": -15, "light.shadows": 15, "mixer.orange.lum": 10, "mixer.orange.sat": -8]),
        DevelopPreset("Ritratto", "Luminoso", ["profile.id": "lc.portrait", "light.exposure": 0.25, "light.contrast": -10, "light.shadows": 30, "light.whites": 15, "effects.texture": -12, "color.vibrance": 8]),
        DevelopPreset("Ritratto", "Caldo dorato", ["profile.id": "lc.portrait", "wb.mode": "custom", "wb.temp": 6900, "wb.tint": 6, "grading.highlights.hue": 42, "grading.highlights.sat": 18, "effects.texture": -10]),
        DevelopPreset("Ritratto", "Editoriale", ["light.contrast": 25, "light.blacks": -20, "color.saturation": -15, "effects.clarity": 10, "grading.shadows.hue": 210, "grading.shadows.sat": 10, "vignette.amount": -15]),
        DevelopPreset("Ritratto", "Pastello delicato", ["light.contrast": -25, "light.blacks": 25, "color.saturation": -20, "grading.highlights.hue": 330, "grading.highlights.sat": 12, "grading.shadows.hue": 200, "grading.shadows.sat": 10]),
        DevelopPreset("Ritratto", "Drammatico", ["light.contrast": 35, "light.highlights": -40, "light.shadows": -15, "effects.clarity": 20, "color.saturation": -20, "vignette.amount": -30]),
        DevelopPreset("Ritratto", "Studio pulito", ["profile.id": "lc.neutral", "light.whites": 20, "light.blacks": -10, "effects.texture": -8, "detail.sharpen_amount": 40]),
        DevelopPreset("Ritratto", "Tono pesca", ["mixer.orange.hue": 6, "mixer.orange.lum": 12, "mixer.red.sat": -10, "grading.midtones.hue": 25, "grading.midtones.sat": 8, "light.contrast": -8]),

        // Paesaggio
        DevelopPreset("Paesaggio", "Paesaggio vivace", ["profile.id": "lc.landscape", "effects.dehaze": 15, "color.vibrance": 30, "light.highlights": -45, "light.shadows": 35, "effects.clarity": 15]),
        DevelopPreset("Paesaggio", "Cieli profondi", ["mixer.blue.sat": 25, "mixer.blue.lum": -30, "mixer.aqua.lum": -15, "light.highlights": -50, "effects.dehaze": 12]),
        DevelopPreset("Paesaggio", "Verdi rigogliosi", ["mixer.green.sat": 25, "mixer.green.hue": -10, "mixer.yellow.hue": -15, "mixer.yellow.sat": 15, "color.vibrance": 15]),
        DevelopPreset("Paesaggio", "Autunno", ["mixer.green.hue": -40, "mixer.yellow.hue": -20, "mixer.orange.sat": 25, "mixer.red.sat": 15, "wb.mode": "custom", "wb.temp": 6800, "grading.highlights.hue": 38, "grading.highlights.sat": 15]),
        DevelopPreset("Paesaggio", "Montagna limpida", ["profile.id": "lc.landscape", "effects.dehaze": 25, "effects.clarity": 20, "light.contrast": 15, "mixer.blue.lum": -20, "detail.sharpen_amount": 50]),
        DevelopPreset("Paesaggio", "Mare tropicale", ["mixer.aqua.sat": 35, "mixer.aqua.hue": -10, "mixer.blue.sat": 20, "light.exposure": 0.15, "light.whites": 15, "color.vibrance": 20]),
        DevelopPreset("Paesaggio", "Nebbia morbida", ["effects.dehaze": -20, "light.contrast": -20, "light.blacks": 25, "color.saturation": -15, "grading.global.hue": 210, "grading.global.sat": 6]),
        DevelopPreset("Paesaggio", "Deserto", ["profile.id": "lc.cine.desert-heat", "wb.mode": "custom", "wb.temp": 7200, "mixer.orange.sat": 20, "mixer.yellow.sat": 10, "effects.clarity": 12]),
        DevelopPreset("Paesaggio", "Notte stellata", ["wb.mode": "custom", "wb.temp": 3900, "light.shadows": 30, "light.blacks": -15, "effects.dehaze": 20, "effects.clarity": 15, "detail.nr_luminance": 35]),

        // Viaggio e città
        DevelopPreset("Viaggio e città", "Street contrastato", ["light.contrast": 35, "light.blacks": -25, "effects.clarity": 25, "color.saturation": -25, "vignette.amount": -20, "grain.amount": 15]),
        DevelopPreset("Viaggio e città", "Città fredda", ["wb.mode": "custom", "wb.temp": 5200, "grading.shadows.hue": 205, "grading.shadows.sat": 20, "color.saturation": -15, "light.contrast": 15]),
        DevelopPreset("Viaggio e città", "Architettura", ["profile.id": "lc.neutral", "effects.clarity": 20, "effects.texture": 15, "light.highlights": -30, "light.shadows": 25, "detail.sharpen_amount": 55]),
        DevelopPreset("Viaggio e città", "Diario di viaggio", ["light.contrast": -10, "light.blacks": 20, "color.vibrance": 15, "grading.highlights.hue": 45, "grading.highlights.sat": 12, "grain.amount": 12]),
        DevelopPreset("Viaggio e città", "Mediterraneo", ["mixer.blue.sat": 20, "mixer.aqua.sat": 20, "mixer.orange.sat": 15, "light.exposure": 0.2, "light.whites": 10, "wb.mode": "custom", "wb.temp": 6700]),
        DevelopPreset("Viaggio e città", "Tokyo neon", ["profile.id": "lc.cine.neon-dusk", "mixer.purple.sat": 25, "mixer.magenta.sat": 25, "mixer.blue.sat": 15, "light.contrast": 20, "effects.clarity": 10]),

        // Cinematografico
        DevelopPreset("Cinematografico", "Ottanio e arancio", ["profile.id": "lc.cine.teal-amber", "grading.shadows.hue": 195, "grading.shadows.sat": 28, "grading.highlights.hue": 35, "grading.highlights.sat": 22, "grading.balance": 10, "light.contrast": 14]),
        DevelopPreset("Cinematografico", "Blockbuster", ["grading.shadows.hue": 190, "grading.shadows.sat": 35, "grading.highlights.hue": 30, "grading.highlights.sat": 30, "light.contrast": 30, "light.blacks": -15, "color.saturation": -10, "vignette.amount": -20]),
        DevelopPreset("Cinematografico", "Blu notte", ["profile.id": "lc.cine.night-blue", "wb.mode": "custom", "wb.temp": 4300, "light.exposure": -0.3, "grading.shadows.hue": 220, "grading.shadows.sat": 30, "light.contrast": 15]),
        DevelopPreset("Cinematografico", "Thriller verde", ["grading.shadows.hue": 150, "grading.shadows.sat": 20, "grading.midtones.hue": 90, "grading.midtones.sat": 8, "color.saturation": -25, "light.contrast": 20, "vignette.amount": -25]),
        DevelopPreset("Cinematografico", "Western", ["profile.id": "lc.cine.desert-heat", "grading.highlights.hue": 40, "grading.highlights.sat": 30, "grading.shadows.hue": 25, "grading.shadows.sat": 15, "light.contrast": 20, "grain.amount": 20]),
        DevelopPreset("Cinematografico", "Anamorfico", ["light.contrast": 18, "light.highlights": -30, "grading.shadows.hue": 210, "grading.shadows.sat": 18, "vignette.amount": -30, "vignette.roundness": -40, "grain.amount": 10]),
        DevelopPreset("Cinematografico", "Bleach bypass", ["profile.id": "lc.muted.bleached", "color.saturation": -45, "light.contrast": 40, "effects.clarity": 20, "light.blacks": -20]),
        DevelopPreset("Cinematografico", "Crepuscolo neon", ["profile.id": "lc.cine.neon-dusk", "grading.shadows.hue": 260, "grading.shadows.sat": 30, "grading.highlights.hue": 320, "grading.highlights.sat": 20]),

        // Pellicola e vintage
        DevelopPreset("Pellicola e vintage", "Pellicola", ["grain.amount": 25, "vignette.amount": -15, "light.contrast": 10, "color.saturation": -10]),
        DevelopPreset("Pellicola e vintage", "Stampa calda", ["profile.id": "lc.film.warm-print", "light.blacks": 18, "grain.amount": 22, "grain.size": 35]),
        DevelopPreset("Pellicola e vintage", "Kodak anni '80", ["profile.id": "lc.film.warm-print", "mixer.red.sat": 15, "mixer.yellow.hue": -10, "grading.highlights.hue": 45, "grading.highlights.sat": 20, "light.blacks": 15, "grain.amount": 25]),
        DevelopPreset("Pellicola e vintage", "Fuji verde", ["mixer.green.hue": 15, "mixer.green.sat": -15, "grading.shadows.hue": 160, "grading.shadows.sat": 15, "light.contrast": 10, "grain.amount": 18]),
        DevelopPreset("Pellicola e vintage", "Sbiadito freddo", ["profile.id": "lc.film.cool-fade", "light.blacks": 25, "light.contrast": -10, "grain.amount": 15]),
        DevelopPreset("Pellicola e vintage", "Diapositiva", ["profile.id": "lc.film.faded-slide", "color.vibrance": 15, "light.contrast": 15, "vignette.amount": -10]),
        DevelopPreset("Pellicola e vintage", "Polaroid", ["light.contrast": -20, "light.blacks": 30, "light.whites": -15, "grading.highlights.hue": 50, "grading.highlights.sat": 18, "grading.shadows.hue": 190, "grading.shadows.sat": 15, "vignette.amount": -20]),
        DevelopPreset("Pellicola e vintage", "Anni '70", ["wb.mode": "custom", "wb.temp": 7400, "color.saturation": -10, "mixer.orange.sat": 20, "grading.midtones.hue": 35, "grading.midtones.sat": 12, "light.blacks": 20, "grain.amount": 30, "grain.size": 45]),
        DevelopPreset("Pellicola e vintage", "Cross processing", ["grading.shadows.hue": 200, "grading.shadows.sat": 35, "grading.highlights.hue": 60, "grading.highlights.sat": 35, "light.contrast": 25, "color.saturation": 10]),
        DevelopPreset("Pellicola e vintage", "Lomo", ["light.contrast": 35, "color.saturation": 25, "vignette.amount": -55, "vignette.midpoint": 30, "grain.amount": 20]),

        // Bianco e nero
        DevelopPreset("Bianco e nero", "Bianco e nero", ["treatment": "bw", "light.contrast": 20]),
        DevelopPreset("Bianco e nero", "B/N ad alto contrasto", ["treatment": "bw", "profile.id": "lc.bw.mono-rich", "light.contrast": 45, "light.blacks": -25, "light.whites": 20, "effects.clarity": 20]),
        DevelopPreset("Bianco e nero", "B/N morbido", ["treatment": "bw", "profile.id": "lc.bw.soft", "light.contrast": -15, "light.blacks": 15, "grain.amount": 10]),
        DevelopPreset("Bianco e nero", "Filtro rosso", ["treatment": "bw", "profile.id": "lc.bw.red-filter", "bw_mix.red": 30, "bw_mix.blue": -40, "bw_mix.aqua": -25, "light.contrast": 20]),
        DevelopPreset("Bianco e nero", "Filtro verde", ["treatment": "bw", "bw_mix.green": 35, "bw_mix.red": -20, "bw_mix.orange": -10, "light.contrast": 15]),
        DevelopPreset("Bianco e nero", "Seppia", ["treatment": "bw", "profile.id": "lc.bw.sepia", "light.contrast": 10, "grain.amount": 15]),
        DevelopPreset("Bianco e nero", "Selenio", ["treatment": "bw", "grading.shadows.hue": 260, "grading.shadows.sat": 15, "grading.highlights.hue": 40, "grading.highlights.sat": 8, "light.contrast": 15]),
        DevelopPreset("Bianco e nero", "Noir", ["treatment": "bw", "light.contrast": 55, "light.shadows": -30, "light.blacks": -35, "vignette.amount": -40, "grain.amount": 20]),
        DevelopPreset("Bianco e nero", "Pellicola granulosa", ["treatment": "bw", "light.contrast": 25, "grain.amount": 45, "grain.size": 40, "grain.roughness": 70]),
        DevelopPreset("Bianco e nero", "Alto key", ["treatment": "bw", "light.exposure": 0.6, "light.contrast": -20, "light.blacks": 25, "light.shadows": 40]),

        // Stagioni e luce
        DevelopPreset("Stagioni e luce", "Ora d'oro", ["profile.id": "lc.film.golden-hour", "wb.mode": "custom", "wb.temp": 7300, "wb.tint": 8, "grading.highlights.hue": 40, "grading.highlights.sat": 22, "light.shadows": 15]),
        DevelopPreset("Stagioni e luce", "Ora blu", ["wb.mode": "custom", "wb.temp": 4600, "grading.shadows.hue": 225, "grading.shadows.sat": 22, "light.highlights": -20, "color.vibrance": 15]),
        DevelopPreset("Stagioni e luce", "Estate", ["light.exposure": 0.2, "color.vibrance": 30, "mixer.aqua.sat": 20, "mixer.yellow.sat": 15, "wb.mode": "custom", "wb.temp": 6800, "light.whites": 10]),
        DevelopPreset("Stagioni e luce", "Inverno", ["wb.mode": "custom", "wb.temp": 5000, "color.saturation": -20, "light.exposure": 0.15, "light.whites": 15, "grading.global.hue": 210, "grading.global.sat": 8]),
        DevelopPreset("Stagioni e luce", "Primavera", ["mixer.green.sat": 15, "mixer.green.lum": 15, "mixer.magenta.sat": 15, "light.contrast": -10, "light.exposure": 0.15, "color.vibrance": 15]),
        DevelopPreset("Stagioni e luce", "Controluce", ["light.highlights": -55, "light.shadows": 55, "effects.dehaze": -10, "grading.highlights.hue": 45, "grading.highlights.sat": 15, "light.blacks": 10]),
        DevelopPreset("Stagioni e luce", "Giorno nuvoloso", ["wb.mode": "custom", "wb.temp": 6600, "effects.dehaze": 15, "light.contrast": 15, "color.vibrance": 20, "effects.clarity": 10]),

        // Notte
        DevelopPreset("Notte", "Luci della città", ["light.highlights": -40, "light.shadows": 20, "light.blacks": -10, "color.vibrance": 20, "detail.nr_luminance": 30, "detail.nr_color": 40]),
        DevelopPreset("Notte", "Notte cinematica", ["profile.id": "lc.cine.night-blue", "grading.shadows.hue": 215, "grading.shadows.sat": 25, "grading.highlights.hue": 35, "grading.highlights.sat": 18, "detail.nr_luminance": 25]),
        DevelopPreset("Notte", "Concerto", ["light.contrast": 30, "light.blacks": -30, "mixer.purple.sat": 20, "mixer.magenta.sat": 20, "detail.nr_luminance": 35, "grain.amount": 10]),
        DevelopPreset("Notte", "Lume di candela", ["wb.mode": "custom", "wb.temp": 4200, "light.shadows": 25, "grading.midtones.hue": 35, "grading.midtones.sat": 12, "vignette.amount": -25]),

        // Cibo e prodotto
        DevelopPreset("Cibo e prodotto", "Cibo luminoso", ["light.exposure": 0.25, "light.shadows": 25, "color.vibrance": 25, "effects.texture": 15, "mixer.red.sat": 10, "mixer.orange.sat": 10]),
        DevelopPreset("Cibo e prodotto", "Rustico", ["light.contrast": 20, "light.exposure": -0.15, "effects.clarity": 15, "grading.shadows.hue": 30, "grading.shadows.sat": 12, "vignette.amount": -25]),
        DevelopPreset("Cibo e prodotto", "Prodotto su bianco", ["profile.id": "lc.neutral", "light.exposure": 0.3, "light.whites": 30, "light.highlights": -10, "effects.texture": 10, "detail.sharpen_amount": 50]),
        DevelopPreset("Cibo e prodotto", "Caffè", ["wb.mode": "custom", "wb.temp": 6900, "light.contrast": 15, "mixer.orange.lum": -10, "mixer.orange.sat": 12, "effects.clarity": 10, "vignette.amount": -15]),

        // Tenui e pastello
        DevelopPreset("Tenui e pastello", "Opaco", ["profile.id": "lc.muted.matte-soft", "light.blacks": 30, "light.contrast": -15]),
        DevelopPreset("Tenui e pastello", "Pastello", ["profile.id": "lc.muted.pastel-haze", "light.exposure": 0.2, "color.saturation": -15, "light.contrast": -15]),
        DevelopPreset("Tenui e pastello", "Verde quieto", ["profile.id": "lc.muted.quiet-green", "light.blacks": 15]),
        DevelopPreset("Tenui e pastello", "Minimal", ["color.saturation": -35, "light.contrast": -10, "light.exposure": 0.2, "light.whites": 15, "grading.global.hue": 35, "grading.global.sat": 5]),
        DevelopPreset("Tenui e pastello", "Sogno", ["effects.clarity": -30, "effects.dehaze": -15, "light.highlights": 15, "light.exposure": 0.2, "grading.highlights.hue": 320, "grading.highlights.sat": 10]),
        DevelopPreset("Tenui e pastello", "Beige", ["color.saturation": -25, "grading.global.hue": 38, "grading.global.sat": 12, "light.blacks": 20, "light.contrast": -8]),

        // Creativi
        DevelopPreset("Creativi", "Pop vivace", ["profile.id": "lc.vivid", "color.vibrance": 40, "color.saturation": 8, "light.contrast": 18, "light.whites": 10, "light.blacks": -10, "effects.clarity": 12]),
        DevelopPreset("Creativi", "Colore selettivo rosso", ["mixer.orange.sat": -100, "mixer.yellow.sat": -100, "mixer.green.sat": -100, "mixer.aqua.sat": -100, "mixer.blue.sat": -100, "mixer.purple.sat": -100, "mixer.magenta.sat": -60, "mixer.red.sat": 30]),
        DevelopPreset("Creativi", "Infrarosso", ["mixer.green.hue": -100, "mixer.green.lum": 60, "mixer.yellow.lum": 40, "mixer.blue.lum": -40, "light.contrast": 25]),
        DevelopPreset("Creativi", "Duotono viola", ["treatment": "bw", "grading.shadows.hue": 270, "grading.shadows.sat": 45, "grading.highlights.hue": 30, "grading.highlights.sat": 30, "light.contrast": 15]),
        DevelopPreset("Creativi", "Sole al tramonto", ["grading.global.hue": 25, "grading.global.sat": 20, "grading.highlights.hue": 45, "grading.highlights.sat": 30, "wb.mode": "custom", "wb.temp": 7800]),
        DevelopPreset("Creativi", "Glow", ["effects.clarity": -40, "light.highlights": 25, "light.whites": 15, "effects.dehaze": -20, "color.vibrance": 15]),
        DevelopPreset("Creativi", "Grunge", ["effects.clarity": 45, "effects.texture": 30, "color.saturation": -35, "light.contrast": 25, "vignette.amount": -35, "grain.amount": 30]),
        DevelopPreset("Creativi", "Vignetta artistica", ["vignette.amount": -60, "vignette.midpoint": 25, "vignette.feather": 80, "light.contrast": 10]),
    ]
    // swiftlint:enable line_length
}

/// The user's own presets: full looks saved from a photo, in Documents/Presets/user-presets.json.
public enum UserPresetStore {
    /// Settings groups a user preset leaves out (they belong to one photo, not to a look).
    static let excluded: Set<String> = ["crop", "orientation", "geometry", "masks", "spots", "red_eye", "version", "process", "lens_blur", "wb"]

    static var url: URL {
        StudioPaths.documents.appendingPathComponent("Presets", isDirectory: true).appendingPathComponent("user-presets.json")
    }

    struct Stored: Codable {
        var name: String
        var settings: JSONValue
    }

    public static func load() -> [DevelopPreset] {
        guard let data = try? Data(contentsOf: url), let items = try? JSONDecoder().decode([Stored].self, from: data) else { return [] }
        return items.map { DevelopPreset("I miei preset", $0.name, flatten($0.settings)) }
    }

    public static func save(name: String, settings: JSONValue) throws {
        var items = (try? JSONDecoder().decode([Stored].self, from: Data(contentsOf: url))) ?? []
        var kept: [String: JSONValue] = [:]
        if case .object(let o) = settings { kept = o.filter { !excluded.contains($0.key) } }
        items.removeAll { $0.name == name }
        items.append(Stored(name: name, settings: .object(kept)))
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(items).write(to: url, options: .atomic)
    }

    public static func delete(name: String) {
        guard var items = try? JSONDecoder().decode([Stored].self, from: Data(contentsOf: url)) else { return }
        items.removeAll { $0.name == name }
        try? JSONEncoder().encode(items).write(to: url, options: .atomic)
    }

    /// Leaf numbers and strings by dotted path (arrays such as point curves are kept whole as text-less
    /// values are not representable; curves stay at the engine default in user presets).
    static func flatten(_ v: JSONValue, prefix: String = "") -> [String: PresetValue] {
        switch v {
        case .number(let n): return [prefix: .number(n)]
        case .string(let s): return [prefix: .text(s)]
        case .object(let o):
            var out: [String: PresetValue] = [:]
            for (k, child) in o { out.merge(flatten(child, prefix: prefix.isEmpty ? k : "\(prefix).\(k)")) { a, _ in a } }
            return out
        default: return [:]
        }
    }
}
