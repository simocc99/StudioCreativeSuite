import CoreGraphics
import ImageIO
import PDFKit
@testable import StudioAssets
@testable import StudioCore
@testable import StudioLayout
@testable import StudioMotion
@testable import StudioPaint
@testable import StudioPDF
@testable import StudioVector
import UIKit
import XCTest

final class VectorTests: XCTestCase {
    func doc() -> VectorProject {
        var d = VectorProject()
        d.width = 200
        d.height = 100
        var r = VectorShape(name: "r", kind: .rect(cornerRadius: 0), frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        r.fill = .solid(RGBAColor(1, 0, 0))
        var e = VectorShape(name: "e", kind: .ellipse, frame: CGRect(x: 100, y: 0, width: 100, height: 100))
        e.fill = .linear([GradientStop(location: 0, color: .black), GradientStop(location: 1, color: .white)], angle: 0)
        let p = VectorShape(name: "p", kind: .path(nodes: [BezierNode(CGPoint(x: 10, y: 10)), BezierNode(CGPoint(x: 50, y: 90), in: CGPoint(x: 20, y: 90), out: CGPoint(x: 80, y: 90)),
                                                           BezierNode(CGPoint(x: 90, y: 10))], closed: true), frame: .zero)
        d.layers[0].shapes = [r, e, p]
        return d
    }

    func testSVGRoundTrip() throws {
        let svg = SVG.export(doc())
        let (back, report) = try SVG.parse(Data(svg.utf8))
        check("vector.svg.roundtrip", report.shapes == 3 && back.width == 200 && back.background == .white, expected: "3 shapes, white background, 200 wide",
              observed: "\(report.shapes) shapes, \(back.width) wide, skipped \(report.skipped)")
        let path = back.layers[0].shapes.first { if case .path = $0.kind { true } else { false } }
        XCTAssertEqual(path.map { $0.bounds.minX } ?? 0, 10, accuracy: 0.5)
    }

    func testSVGRelativeCommands() throws {
        let svg = ##"<svg width="100" height="100"><path d="m10 10 h50 v30 h-50 z" fill="#00ff00"/><circle cx="50" cy="50" r="10"/><foo/></svg>"##
        let (d, r) = try SVG.parse(Data(svg.utf8))
        let b = d.layers[0].shapes[0].bounds
        check("vector.svg.relative", b.equalTo(CGRect(x: 10, y: 10, width: 50, height: 30)) && r.skipped["foo"] == 1,
              expected: "rect 10,10 50×30; unknown element reported", observed: "\(b) \(r.skipped)")
    }

    func testBooleanUnion() {
        let a = VectorShape(name: "a", kind: .rect(cornerRadius: 0), frame: CGRect(x: 0, y: 0, width: 60, height: 60))
        let b = VectorShape(name: "b", kind: .rect(cornerRadius: 0), frame: CGRect(x: 30, y: 30, width: 60, height: 60))
        let u = VectorOps.boolean(.union, [a, b])!
        let i = VectorOps.boolean(.intersect, [a, b])!
        check("vector.boolean", u.bounds.equalTo(CGRect(x: 0, y: 0, width: 90, height: 90)) && i.bounds.equalTo(CGRect(x: 30, y: 30, width: 30, height: 30)),
              expected: "union 90×90, intersection 30×30", observed: "\(u.bounds) / \(i.bounds)")
    }

    func testRasterAndPDFExport() {
        let png = VectorRenderer.png(doc(), scale: 4)
        let img = UIImage(data: png)!.cgImage!
        // doc x 1…9, y 40…60: inside the red rect, outside the blue path
        let left = Fixtures.average(img, in: CGRect(x: 4, y: 160, width: 32, height: 80))
        check("vector.png", img.width == 800 && left.0 > 250 && left.1 < 5, expected: "800 px wide, red rect", observed: "\(img.width) px, \(Int(left.0)),\(Int(left.1))")
        let pdf = PDFDocument(data: VectorRenderer.pdf(doc()))
        XCTAssertEqual(pdf?.pageCount, 1)
    }

    func testAlign() {
        var shapes = doc().layers[0].shapes
        VectorOps.align(&shapes, .right, artboard: CGRect(x: 0, y: 0, width: 200, height: 100))
        XCTAssertTrue(shapes.allSatisfy { abs($0.bounds.maxX - 200) < 0.01 })
    }
}

final class PaintTests: XCTestCase {
    @MainActor
    func testBrushStrokeEraseAndPersist() throws {
        let dir = Fixtures.tempDir("paint")
        var p = PaintProject()
        p.width = 200
        p.height = 200
        let state = PaintDocumentState(project: p, projectURL: dir)
        let layer = state.bitmap(p.layers[0].id)
        var brush = Brush(kind: .ink)
        brush.size = 20
        brush.color = RGBAColor(0, 0, 1)
        let e = BrushEngine(brush: brush)
        _ = e.begin(StrokeSample(point: CGPoint(x: 20, y: 100), pressure: 1), in: layer.context)
        _ = e.move(to: StrokeSample(point: CGPoint(x: 180, y: 100), pressure: 1), in: layer.context)
        e.end()
        let mid = layer.color(at: CGPoint(x: 100, y: 100))
        let off = layer.color(at: CGPoint(x: 100, y: 20))
        check("paint.stroke", (mid?.b ?? 0) > 0.9 && (mid?.a ?? 0) > 0.9 && (off?.a ?? 1) == 0,
              expected: "blue along the stroke, transparent elsewhere", observed: "mid \(String(describing: mid)) off \(String(describing: off))")
        // pressure changes the width
        let thin = BitmapLayer(width: 200, height: 200)
        var pb = brush
        pb.pressureSize = true
        let e2 = BrushEngine(brush: pb)
        _ = e2.begin(StrokeSample(point: CGPoint(x: 20, y: 100), pressure: 0.1), in: thin.context)
        _ = e2.move(to: StrokeSample(point: CGPoint(x: 180, y: 100), pressure: 0.1), in: thin.context)
        XCTAssertEqual(thin.color(at: CGPoint(x: 100, y: 107))?.a ?? 0, 0, accuracy: 0.01, "light pressure gives a thin line")

        var eraser = Brush(kind: .eraser)
        eraser.size = 40
        eraser.hardness = 1
        let er = BrushEngine(brush: eraser)
        _ = er.begin(StrokeSample(point: CGPoint(x: 100, y: 100)), in: layer.context)
        check("paint.erase", (layer.color(at: CGPoint(x: 100, y: 100))?.a ?? 1) < 0.05, expected: "erased to transparent",
              observed: "\(layer.color(at: CGPoint(x: 100, y: 100))?.a ?? -1)")
        try state.save(p, to: dir)
        let reloaded = PaintDocumentState(project: p, projectURL: dir)
        let px = reloaded.bitmap(p.layers[0].id).color(at: CGPoint(x: 30, y: 100))
        check("paint.persist", (px?.b ?? 0) > 0.9, expected: "pixels survive save + reopen", observed: "\(String(describing: px))")
        let flat = state.flatten(p)!
        XCTAssertEqual(flat.width, 200)
    }
}

final class MotionTests: XCTestCase {
    func testKeyframeInterpolation() {
        var v = AnimatedValue(0)
        v.set(0, at: 0, keyframe: true)
        v.set(100, at: 2, keyframe: true)
        v.keys[0].easing = .linear
        check("motion.linear", abs(v.at(1) - 50) < 1e-9, expected: "50 at t=1", observed: "\(v.at(1))")
        v.keys[0].easing = .hold
        XCTAssertEqual(v.at(1.9), 0)
        v.keys[0].easing = .easeInOut
        XCTAssertLessThan(v.at(0.5), 25)
        XCTAssertEqual(v.at(5), 100)
    }

    func testRenderAndExport() async throws {
        let dir = Fixtures.tempDir("motion")
        var p = MotionProject()
        p.width = 320
        p.height = 180
        p.duration = 1
        p.background = .black
        var l = MotionLayer(name: "box", kind: .rectangle(cornerRadius: 0))
        l.width = 40
        l.height = 40
        l.color = RGBAColor(1, 1, 1)
        l.outPoint = 1
        l.x.set(20, at: 0, keyframe: true)
        l.x.set(300, at: 1, keyframe: true)
        l.x.keys[0].easing = .linear
        l.y = AnimatedValue(90)
        p.layers = [l]
        let r = MotionRenderer(projectURL: dir)
        let f0 = r.frameImage(p, at: 0)!, f1 = r.frameImage(p, at: 0.99)!
        let leftAt0 = Fixtures.average(f0, in: CGRect(x: 10, y: 80, width: 20, height: 20)).0
        let rightAt1 = Fixtures.average(f1, in: CGRect(x: 285, y: 80, width: 20, height: 20)).0
        check("motion.render", leftAt0 > 250 && rightAt1 > 250, expected: "box moves left → right", observed: "\(Int(leftAt0)) / \(Int(rightAt1))")
        let out = dir.appendingPathComponent("m.mp4")
        try await FrameVideoWriter.write(to: out, width: p.width, height: p.height, fps: p.fps, frameCount: p.frameCount) { i, ctx in
            r.draw(p, at: Double(i) / Double(p.fps), in: ctx)
        }
        let d = try await AVURLAsset(url: out).load(.duration).seconds
        check("motion.export", abs(d - 1) < 0.05, expected: "1 s movie", observed: String(format: "%.3f s", d))
        let seq = try FrameVideoWriter.writePNGSequence(to: dir.appendingPathComponent("seq"), width: 32, height: 18, frameCount: 5) { i, ctx in
            r.draw(p, at: Double(i) / 5, in: ctx)
        }
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: seq.path).count, 5)
    }
}

final class DocumentTests: XCTestCase {
    func testLayoutPDFAndOverflow() throws {
        var d = LayoutProject()
        d.pages = [LayoutPage(), LayoutPage(), LayoutPage()]
        d.pages[0].frames = [LayoutFrame(rect: CGRect(x: 50, y: 50, width: 400, height: 300), content: .text("Studio impaginazione prova unica", style: nil))]
        d.pages[1].frames = [LayoutFrame(rect: CGRect(x: 50, y: 50, width: 60, height: 20), content: .text(String(repeating: "testo lungo ", count: 200), style: nil))]
        let data = LayoutRenderer.pdf(d, projectURL: Fixtures.tempDir("layout"))
        let pdf = PDFDocument(data: data)!
        let found = PDFOperations.search(pdf, "impaginazione")
        check("layout.pdf", pdf.pageCount == 3 && found.count == 1, expected: "3 pages, text searchable", observed: "\(pdf.pageCount) pages, \(found.count) hits")
        let ctx = CGContext(data: nil, width: 600, height: 850, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let overflow = LayoutRenderer.draw(d, page: 1, in: ctx, projectURL: URL(fileURLWithPath: "/"), guides: false)
        check("layout.overflow", overflow, expected: "overflow detected", observed: "\(overflow)")
    }

    func testPDFOperations() throws {
        let dir = Fixtures.tempDir("pdf")
        var d = LayoutProject()
        d.pages = (0 ..< 3).map { i in
            var p = LayoutPage()
            p.frames = [LayoutFrame(rect: CGRect(x: 60, y: 60, width: 400, height: 100), content: .text("Pagina numero \(i + 1) parola\(i + 1)", style: nil))]
            return p
        }
        let a = PDFDocument(data: LayoutRenderer.pdf(d, projectURL: dir))!
        let b = PDFDocument(data: LayoutRenderer.pdf(d, projectURL: dir))!
        PDFOperations.merge(a, with: b)
        XCTAssertEqual(a.pageCount, 6)
        PDFOperations.movePage(a, from: 2, to: 0)
        check("pdf.reorder", a.page(at: 0)?.string?.contains("parola3") == true, expected: "page 3 first", observed: a.page(at: 0)?.string ?? "")
        PDFOperations.delete(a, page: 5)
        PDFOperations.rotate(a, page: 0, by: 90)
        let hit = PDFOperations.search(a, "parola2")
        XCTAssertEqual(hit.count, 2)
        PDFOperations.highlight(hit[0])
        PDFOperations.addNote(a.page(at: 1)!, at: CGPoint(x: 100, y: 100), text: "nota")
        PDFOperations.addInk(a.page(at: 1)!, points: [CGPoint(x: 10, y: 10), CGPoint(x: 100, y: 120)], color: .red, width: 2)
        let url = dir.appendingPathComponent("out.pdf")
        XCTAssertTrue(a.write(to: url))
        let back = PDFDocument(url: url)!
        let n = PDFOperations.annotationCount(back)
        check("pdf.save", back.pageCount == 5 && n >= 3 && back.page(at: 0)?.rotation == 90,
              expected: "5 pages, ≥3 annotations, rotation kept", observed: "\(back.pageCount) pages, \(n) annotations, rot \(back.page(at: 0)?.rotation ?? -1)")
    }

    func testAssetDedupAndSearch() async throws {
        let cat = AssetCatalog(root: Fixtures.tempDir("assets"))
        let src = Fixtures.tempDir("asrc")
        let f1 = src.appendingPathComponent("uno.png"), f2 = src.appendingPathComponent("copia.png"), f3 = src.appendingPathComponent("altro.png")
        Fixtures.png(f1, width: 8, height: 8, color: .black)
        try FileManager.default.copyItem(at: f1, to: f2)
        Fixtures.png(f3, width: 8, height: 8, color: .white)
        let r = try await cat.importFiles([f1, f2, f3])
        check("assets.dedup", r.added.count == 2 && r.duplicates.count == 1, expected: "2 stored, 1 duplicate",
              observed: "\(r.added.count) added, \(r.duplicates.count) duplicates")
        cat.update(r.added[0].id) { $0.tags = ["viaggio"]; $0.favorite = true }
        XCTAssertEqual(cat.search("viagg", kind: nil, favoritesOnly: false, tag: nil).count, 1)
        XCTAssertEqual(cat.search("", kind: .photo, favoritesOnly: true, tag: nil).count, 1)
        XCTAssertEqual(r.added[0].metadata["Dimensioni"], "8×8")
        let reopened = AssetCatalog(root: cat.root)
        XCTAssertEqual(reopened.assets.count, 2)
    }
}

import AVFoundation
