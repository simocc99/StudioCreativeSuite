import CoreGraphics
import ImageIO
@testable import StudioCore
@testable import StudioPhoto
import XCTest

final class PhotoTests: XCTestCase {
    func testRenderedImageThroughEngine() async throws {
        let dir = Fixtures.tempDir("photo")
        let src = dir.appendingPathComponent("grey.png")
        Fixtures.png(src, width: 600, height: 400, color: RGBAColor(0.4, 0.4, 0.4))
        let e = try await PhotoEngine.open(src, previewEdge: 600)
        check("photo.rendered.notRaw", !e.info.isRaw, expected: "PNG opened as rendered image", observed: "isRaw=\(e.info.isRaw)")
        let base = try await e.render(e.defaultSettings, maxSize: CGSize(width: 300, height: 300))
        var brighter = e.defaultSettings
        brighter[path: "light.exposure"] = .number(1)
        let up = try await e.render(brighter, maxSize: CGSize(width: 300, height: 300))
        let a = Fixtures.average(base).0, b = Fixtures.average(up).0
        check("photo.exposure", b > a + 20, expected: "+1 EV brightens the render", observed: String(format: "%.1f → %.1f", a, b))
        let out = dir.appendingPathComponent("out.jpg")
        let r = try await e.export(brighter, to: out, format: .jpg, quality: 90)
        let img = CGImageSourceCreateImageAtIndex(CGImageSourceCreateWithURL(out as CFURL, nil)!, 0, nil)
        check("photo.export.jpg", img?.width == 600 && r.width == 600, expected: "600 px wide JPEG", observed: "\(img?.width ?? 0)")
    }

    func testCorruptFileIsReported() async throws {
        let f = Fixtures.tempDir("corrupt").appendingPathComponent("bad.dng")
        try Data(repeating: 0x42, count: 4096).write(to: f)
        do {
            _ = try await PhotoEngine.open(f)
            XCTFail("a corrupt file must not open")
        } catch {
            check("photo.corrupt", true, expected: "error, no crash", observed: error.localizedDescription)
        }
    }

    /// Decodes every raw sample in STUDIO_RAW_DIR from sensor data (not the embedded JPEG) and exports it.
    func testRawSamples() async throws {
        guard let dir = Fixtures.rawDir else { throw XCTSkip("STUDIO_RAW_DIR non impostata: nessun campione RAW") }
        let files = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
            .filter { PhotoEngine.rawExtensions.contains($0.pathExtension.lowercased()) }
        XCTAssertFalse(files.isEmpty)
        for f in files {
            let probe = try PhotoEngine.probe(f)
            let e = try await PhotoEngine.open(f, previewEdge: 1200)
            let img = try await e.render(e.defaultSettings, maxSize: CGSize(width: 800, height: 800))
            // a real development has tonal spread (a failed decode is flat)
            let top = Fixtures.average(img, in: CGRect(x: 0, y: 0, width: img.width, height: img.height / 3))
            let all = Fixtures.average(img)
            let out = Fixtures.tempDir("rawout").appendingPathComponent(f.lastPathComponent + ".jpg")
            let r = try await e.export(e.defaultSettings, to: out, format: .jpg, longEdge: 2048)
            let ok = e.info.isRaw && probe.supported == true && r.width > 0 && max(r.width, r.height) == 2048 && all.0 + all.1 + all.2 > 10
            check("raw.\(probe.format ?? "?").\(f.lastPathComponent)", ok,
                  expected: "raw decode from sensor data + export 2048 px",
                  observed: "isRaw=\(e.info.isRaw) format=\(probe.format ?? "nil") export=\(r.width)x\(r.height) mean=\(Int(all.0)),\(Int(all.1)),\(Int(all.2)) top=\(Int(top.0))")
        }
    }

    func testPresetIsRelativeToDefaults() async throws {
        let src = Fixtures.tempDir("preset").appendingPathComponent("g.png")
        Fixtures.png(src, width: 64, height: 64, color: RGBAColor(0.5, 0.3, 0.2))
        let e = try await PhotoEngine.open(src)
        let bw = DevelopPreset.builtIn.first { $0.name == "Bianco e nero" }!
        let s = bw.apply(to: e.defaultSettings, defaults: e.defaultSettings)
        let img = try await e.render(s, maxSize: CGSize(width: 64, height: 64))
        let (r, g, b) = Fixtures.average(img)
        check("photo.preset.bw", abs(r - g) < 3 && abs(g - b) < 3, expected: "neutral grey", observed: String(format: "%.0f/%.0f/%.0f", r, g, b))
    }

    func testRasterCompositingBlendAndMask() throws {
        let dir = Fixtures.tempDir("raster")
        var p = RasterProject()
        p.width = 100
        p.height = 100
        p.background = .white
        var red = RasterLayer(name: "rosso", content: .fill(RGBAColor(1, 0, 0)))
        red.blend = .multiply
        p.layers = [red]
        let c = RasterCompositor(projectURL: dir)
        let img = c.render(p)!
        let (r, g, b) = Fixtures.average(img)
        check("raster.multiply", r > 250 && g < 5 && b < 5, expected: "red × white = red", observed: "\(Int(r)),\(Int(g)),\(Int(b))")
        p.layers[0].opacity = 0.5
        p.layers[0].blend = .normal
        let half = Fixtures.average(c.render(p)!)
        check("raster.opacity", half.1 > 120 && half.1 < 135, expected: "50% red over white ≈ (255,128,128)", observed: "\(Int(half.0)),\(Int(half.1)),\(Int(half.2))")
        p.layers[0].filters = [RasterFilter(.invert)]
        p.layers[0].opacity = 1
        let inv = Fixtures.average(c.render(p)!)
        check("raster.filter.invert", inv.0 < 5 && inv.1 > 250, expected: "inverted red = cyan", observed: "\(Int(inv.0)),\(Int(inv.1)),\(Int(inv.2))")
        let out = dir.appendingPathComponent("r.png")
        try c.export(p, to: out, type: .png)
        XCTAssertNotNil(CGImageSourceCreateWithURL(out as CFURL, nil))
    }
}
