import CoreGraphics
import Foundation
import Observation
import StudioCore

@MainActor
@Observable
public final class PhotoEditorModel {
    public let project: ProjectController<PhotoProject>
    public private(set) var engine: PhotoEngine?
    public private(set) var image: CGImage?
    public private(set) var beforeImage: CGImage?
    public private(set) var histogram: [Double] = []
    public private(set) var isOpening = false
    public private(set) var isRendering = false
    public var showBefore = false { didSet { if showBefore, beforeImage == nil { requestBefore() } } }
    public var error: String?
    public var exportProgress: String?
    public var exported: ExportedFile?

    @ObservationIgnored private var renderTask: Task<Void, Never>?
    @ObservationIgnored private var pending: (JSONValue, CGSize, Bool)?
    @ObservationIgnored public var viewportPixels = CGSize(width: 2048, height: 2048)

    public init(project: ProjectController<PhotoProject>) {
        self.project = project
    }

    public var settings: JSONValue {
        project.payload.settings ?? engine?.defaultSettings ?? .object([:])
    }

    public func load() async {
        guard engine == nil, let src = project.payload.source else { return }
        isOpening = true
        defer { isOpening = false }
        do {
            let e = try await PhotoEngine.open(project.resolve(src))
            engine = e
            if project.payload.settings == nil {
                project.payload.settings = e.defaultSettings
            }
            requestRender(draft: false)
        } catch {
            self.error = error.localizedDescription
        }
    }

    public func importSource(_ url: URL) async {
        do {
            let rel = try project.importMedia(url)
            project.mutate("Importa") { $0.source = rel; $0.settings = nil }
            engine = nil
            image = nil
            beforeImage = nil
            await load()
        } catch {
            self.error = error.localizedDescription
        }
    }

    // MARK: editing

    public func value(_ path: String) -> Double {
        settings[path: path]?.doubleValue ?? 0
    }

    public func defaultValue(_ path: String) -> Double {
        engine?.defaultSettings[path: path]?.doubleValue ?? 0
    }

    public func set(_ path: String, _ v: Double, label: String) {
        var s = settings
        s[path: path] = .number(v)
        if path.hasPrefix("wb.temp") || path.hasPrefix("wb.tint") { s[path: "wb.mode"] = .string("custom") }
        project.mutate(label) { $0.settings = s }
        requestRender(draft: dragging)
    }

    public func setString(_ path: String, _ v: String, label: String) {
        var s = settings
        s[path: path] = .string(v)
        project.mutate(label) { $0.settings = s }
        requestRender(draft: false)
    }

    public func setBool(_ path: String, _ v: Bool, label: String) {
        var s = settings
        s[path: path] = .bool(v)
        project.mutate(label) { $0.settings = s }
        requestRender(draft: false)
    }

    public private(set) var dragging = false

    public func editing(_ active: Bool) {
        dragging = active
        if active { project.beginGesture() } else {
            project.endGesture()
            requestRender(draft: false)
        }
    }

    public func rotate(clockwise: Bool) {
        let cur = settings[path: "orientation"]?.stringValue ?? "Normal"
        let r = DevelopControls.rotations
        let i = r.firstIndex(of: cur) ?? 0
        setString("orientation", r[(i + (clockwise ? 1 : r.count - 1)) % r.count], label: "Ruota")
    }

    public func applyPreset(_ p: DevelopPreset) {
        guard let d = engine?.defaultSettings else { return }
        let s = p.apply(to: settings, defaults: d)
        project.mutate("Preset \(p.name)") { $0.settings = s }
        requestRender(draft: false)
    }

    public func resetAll() {
        guard let d = engine?.defaultSettings else { return }
        project.mutate("Ripristina") { $0.settings = d }
        requestRender(draft: false)
    }

    public func undo() { project.undo(); requestRender(draft: false) }
    public func redo() { project.redo(); requestRender(draft: false) }

    // MARK: rendering

    /// Coalesces requests: while one render runs, only the newest pending request is kept.
    public func requestRender(draft: Bool) {
        guard engine != nil else { return }
        if !draft {
            beforeImage = nil
            if showBefore { requestBefore() }
        }
        pending = (settings, viewportPixels, draft)
        guard renderTask == nil else { return }
        renderTask = Task { [weak self] in
            while let self, let (s, size, d) = self.pending, let engine = self.engine {
                self.pending = nil
                self.isRendering = true
                do {
                    let img = try await engine.render(s, maxSize: size, draft: d)
                    self.image = img
                    if !d { self.updateHistogram(img) }
                } catch {
                    self.error = error.localizedDescription
                }
            }
            self?.isRendering = false
            self?.renderTask = nil
        }
    }

    private func requestBefore() {
        guard let engine else { return }
        var s = engine.defaultSettings
        // "before" keeps the geometry so the two views line up
        for k in ["orientation", "crop"] { s[k] = settings[k] }
        let size = viewportPixels
        Task {
            beforeImage = try? await engine.render(s, maxSize: size)
        }
    }

    private func updateHistogram(_ img: CGImage) {
        Task.detached(priority: .utility) {
            let h = Histogram.luminance(img, bins: 64)
            await MainActor.run { self.histogram = h }
        }
    }

    // MARK: export

    public func export(format: PhotoExportFormat, quality: Int, longEdge: Int) async {
        guard let engine else { return }
        let name = project.header.name
        let url = StudioPaths.exportURL(name: name, ext: format.rawValue)
        exportProgress = "Esportazione \(format.title) a piena risoluzione…"
        defer { exportProgress = nil }
        do {
            guard let src = project.payload.source else { return }
            _ = try await engine.exportAdaptive(settings, to: url, format: format, quality: quality, longEdge: longEdge,
                                                sourceURL: project.resolve(src))
            exported = ExportedFile(url)
        } catch {
            self.error = error.localizedDescription
        }
    }
}

public enum Histogram {
    /// Normalised luminance histogram of an 8-bit image (max bin = 1).
    public static func luminance(_ img: CGImage, bins: Int) -> [Double] {
        let w = min(img.width, 512), h = max(1, img.height * w / max(1, img.width))
        var px = [UInt8](repeating: 0, count: w * h * 4)
        guard let ctx = CGContext(data: &px, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
        else { return [] }
        ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
        var counts = [Double](repeating: 0, count: bins)
        for i in stride(from: 0, to: px.count, by: 4) {
            let l = 0.2126 * Double(px[i]) + 0.7152 * Double(px[i + 1]) + 0.0722 * Double(px[i + 2])
            counts[min(bins - 1, Int(l / 256 * Double(bins)))] += 1
        }
        let m = counts.max() ?? 1
        return counts.map { $0 / max(m, 1) }
    }
}
