import CoreGraphics
@testable import StudioCore
@testable import StudioPhoto
import XCTest

/// The Lightroom-style develop panel: every control and preset must address a real engine setting.
final class DevelopTests: XCTestCase {
    private func openSample(_ color: RGBAColor = RGBAColor(0.7, 0.25, 0.2)) async throws -> PhotoEngine {
        let src = Fixtures.tempDir("develop").appendingPathComponent("s.png")
        Fixtures.png(src, width: 96, height: 64, color: color)
        return try await PhotoEngine.open(src, previewEdge: 96)
    }

    func testEveryControlAddressesAnEngineSetting() async throws {
        let d = try await openSample().defaultSettings
        let missing = DevelopControls.allSliders.filter { d[path: $0.path]?.doubleValue == nil }.map(\.path)
        let outOfRange = DevelopControls.allSliders.filter { c in
            guard let v = d[path: c.path]?.doubleValue else { return false }
            return !c.range.contains(v)
        }.map(\.path)
        let curves = DevelopControls.curveChannels.filter { if case .array? = d[path: $0.path] { false } else { true } }.map(\.path)
        check("develop.controls.paths", missing.isEmpty && outOfRange.isEmpty && curves.isEmpty,
              expected: "\(DevelopControls.allSliders.count) sliders and 4 curves present in the engine defaults, defaults inside the ranges",
              observed: "missing \(missing), default out of range \(outOfRange), curves \(curves)")
    }

    func testEveryPresetValueIsValid() async throws {
        let d = try await openSample().defaultSettings
        let ranges = Dictionary(DevelopControls.allSliders.map { ($0.path, $0.range) }, uniquingKeysWith: { a, _ in a })
        let profiles = Set(DevelopControls.profiles.map(\.id))
        var problems: [String] = []
        for p in DevelopPreset.builtIn {
            for (path, v) in p.values {
                switch (v, d[path: path]) {
                case (.number(let n), .number?):
                    if let r = ranges[path], !r.contains(n) { problems.append("\(p.name): \(path)=\(n) fuori da \(r)") }
                case (.text(let t), .string?):
                    if path == "profile.id", !profiles.contains(t) { problems.append("\(p.name): profilo \(t)") }
                default:
                    problems.append("\(p.name): \(path) non esiste o ha un altro tipo")
                }
            }
        }
        let names = DevelopPreset.builtIn.map(\.id)
        check("develop.presets.valid", problems.isEmpty && Set(names).count == names.count && names.count >= 80,
              expected: "≥ 80 presets, unique, all paths and ranges valid", observed: problems.isEmpty ? "\(names.count) presets" : problems.joined(separator: "; "))
    }

    func testPresetAmountAndNoStacking() async throws {
        let e = try await openSample()
        let d = e.defaultSettings
        let contrast = DevelopPreset.builtIn.first { $0.name == "Più contrasto" }!
        let half = contrast.apply(to: d, defaults: d, amount: 0.5)
        let none = contrast.apply(to: d, defaults: d, amount: 0)
        let teal = DevelopPreset.builtIn.first { $0.name == "Ottanio e arancio" }!
        // switching from a grading preset to one without grading must not keep the grading
        let after = contrast.apply(to: teal.apply(to: d, defaults: d), defaults: d)
        let ok = half[path: "light.contrast"]?.doubleValue == 15 && none[path: "light.contrast"]?.doubleValue == 0
            && after[path: "grading.shadows.sat"]?.doubleValue == 0
        check("develop.presets.amount", ok, expected: "contrast 15 at 50 %, 0 at 0 %, no grading left from the previous preset",
              observed: "\(half[path: "light.contrast"]?.doubleValue ?? -1) / \(none[path: "light.contrast"]?.doubleValue ?? -1) / \(after[path: "grading.shadows.sat"]?.doubleValue ?? -1)")
        let img = try await e.render(teal.apply(to: d, defaults: d), maxSize: CGSize(width: 64, height: 64))
        check("develop.presets.render", img.width > 0, expected: "preset renders", observed: "\(img.width)x\(img.height)")
    }

    func testAutoTone() async throws {
        let dark = try await openSample(RGBAColor(0.08, 0.07, 0.06))
        let auto = try await dark.autoSettings(dark.defaultSettings)
        let ev = auto[path: "light.exposure"]?.doubleValue
        check("develop.auto", (ev ?? 0) > 0 && auto[path: "bw_mix.red"]?.doubleValue != nil,
              expected: "a dark photo gets positive auto exposure and a B&W mix", observed: "exposure \(ev.map { String($0) } ?? "nil")")
    }

    func testHslHueShiftChangesColour() async throws {
        let e = try await openSample(RGBAColor(0.85, 0.15, 0.1))
        var s = e.defaultSettings
        let base = Fixtures.average(try await e.render(s, maxSize: CGSize(width: 64, height: 64)))
        s[path: "mixer.red.hue"] = .number(100)
        s[path: "mixer.orange.hue"] = .number(100)
        let shifted = Fixtures.average(try await e.render(s, maxSize: CGSize(width: 64, height: 64)))
        check("develop.mixer.hue", abs(shifted.1 - base.1) > 4, expected: "red hue +100 moves red towards orange (more green)",
              observed: String(format: "G %.0f → %.0f", base.1, shifted.1))
    }

    func testPointCurveDarkens() async throws {
        let e = try await openSample(RGBAColor(0.5, 0.5, 0.5))
        var s = e.defaultSettings
        let base = Fixtures.average(try await e.render(s, maxSize: CGSize(width: 64, height: 64)))
        s[path: "curve.master"] = .array([0.0, 0.5, 1.0].map { x in
            .object(["x": .number(x), "y": .number(x == 0.5 ? 0.3 : x)])
        })
        let darker = Fixtures.average(try await e.render(s, maxSize: CGSize(width: 64, height: 64)))
        check("develop.curve.points", darker.0 < base.0 - 10, expected: "midpoint pulled down darkens mid grey",
              observed: String(format: "%.0f → %.0f", base.0, darker.0))
    }
}
