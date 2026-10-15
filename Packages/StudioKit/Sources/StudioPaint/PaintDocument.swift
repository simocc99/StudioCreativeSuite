import CoreGraphics
import Foundation
import ImageIO
import StudioCore
import UniformTypeIdentifiers

public struct PaintProject: ProjectPayload {
    public static let kind = StudioModule.paint
    public static let formatVersion = 1

    public var width = 2732
    public var height = 2048
    public var background = RGBAColor.white
    /// Bottom → top. Pixels live in `Media/Layers/<id>.png`.
    public var layers: [PaintLayerInfo] = [PaintLayerInfo(name: "Livello 1")]
    public var brush = Brush()
    public var swatches: [RGBAColor] = [.black, .white, RGBAColor(0.85, 0.2, 0.2), RGBAColor(0.95, 0.65, 0.15), RGBAColor(0.2, 0.6, 0.3), RGBAColor(0.2, 0.4, 0.85)]

    public init() {}
}

public struct PaintLayerInfo: Codable, Hashable, Identifiable, Sendable {
    public var id = UUID()
    public var name: String
    public var opacity: Double = 1
    public var visible = true
    public var blend: LayerBlend = .normal
    public init(name: String) { self.name = name }
    public var file: String { "Media/Layers/\(id.uuidString).png" }
}

/// Live pixels of a paint document plus its pixel undo stack.
@MainActor
public final class PaintDocumentState {
    public private(set) var bitmaps: [UUID: BitmapLayer] = [:]
    public let width: Int, height: Int

    struct UndoEntry {
        var layers: [PaintLayerInfo]
        var images: [UUID: CGImage?]
        var label: String
    }
    private var undoStack: [UndoEntry] = []
    private var redoStack: [UndoEntry] = []
    private let maxUndo = 40

    public init(project: PaintProject, projectURL: URL) {
        width = project.width
        height = project.height
        for l in project.layers {
            let img = Self.loadPNG(projectURL.appendingPathComponent(l.file))
            bitmaps[l.id] = img.map { BitmapLayer(image: $0, width: width, height: height) } ?? BitmapLayer(width: width, height: height)
        }
    }

    public func bitmap(_ id: UUID) -> BitmapLayer {
        if let b = bitmaps[id] { return b }
        let b = BitmapLayer(width: width, height: height)
        bitmaps[id] = b
        return b
    }

    /// Records the current pixels of `ids` and the layer list before a change.
    public func checkpoint(_ layers: [PaintLayerInfo], ids: [UUID], label: String) {
        var imgs: [UUID: CGImage?] = [:]
        for id in ids { imgs[id] = bitmaps[id]?.makeImage() }
        undoStack.append(UndoEntry(layers: layers, images: imgs, label: label))
        if undoStack.count > maxUndo { undoStack.removeFirst() }
        redoStack.removeAll()
    }

    public var canUndo: Bool { !undoStack.isEmpty }
    public var canRedo: Bool { !redoStack.isEmpty }

    /// Restores the last checkpoint; returns the layer list to put back.
    public func undo(current: [PaintLayerInfo]) -> [PaintLayerInfo]? { swap(&undoStack, &redoStack, current: current) }
    public func redo(current: [PaintLayerInfo]) -> [PaintLayerInfo]? { swap(&redoStack, &undoStack, current: current) }

    private func swap(_ from: inout [UndoEntry], _ to: inout [UndoEntry], current: [PaintLayerInfo]) -> [PaintLayerInfo]? {
        guard let e = from.popLast() else { return nil }
        var back: [UUID: CGImage?] = [:]
        for id in e.images.keys { back[id] = bitmaps[id]?.makeImage() }
        to.append(UndoEntry(layers: current, images: back, label: e.label))
        for (id, img) in e.images { bitmap(id).set(img ?? nil) }
        return e.layers
    }

    // MARK: persistence

    public func save(_ project: PaintProject, to projectURL: URL) throws {
        let dir = projectURL.appendingPathComponent("Media/Layers", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for l in project.layers {
            guard let img = bitmaps[l.id]?.makeImage() else { continue }
            try Self.writePNG(img, to: projectURL.appendingPathComponent(l.file))
        }
        // drop pixel files of deleted layers
        let keep = Set(project.layers.map { "\($0.id.uuidString).png" })
        for f in (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? [] where !keep.contains(f) {
            try? FileManager.default.removeItem(at: dir.appendingPathComponent(f))
        }
    }

    /// Flattens visible layers with their opacity and blend mode.
    public func flatten(_ project: PaintProject, background: Bool = true) -> CGImage? {
        let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let r = CGRect(x: 0, y: 0, width: width, height: height)
        if background {
            ctx.setFillColor(project.background.cgColor)
            ctx.fill(r)
        }
        for l in project.layers where l.visible {
            guard let img = bitmaps[l.id]?.makeImage() else { continue }
            ctx.saveGState()
            ctx.setAlpha(l.opacity)
            ctx.setBlendMode(l.blend.cgBlend)
            ctx.draw(img, in: r)
            ctx.restoreGState()
        }
        return ctx.makeImage()
    }

    public static func loadPNG(_ url: URL) -> CGImage? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(src, 0, nil)
    }

    public static func writePNG(_ img: CGImage, to url: URL, type: UTType = .png, quality: Double = 0.92) throws {
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil) else {
            throw StudioError.io("impossibile scrivere \(url.lastPathComponent)")
        }
        CGImageDestinationAddImage(dest, img, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { throw StudioError.io("scrittura \(url.lastPathComponent) non riuscita") }
    }
}
