import CoreGraphics
import StudioCore
import SwiftUI

/// Frame-by-frame 2D animation (vector strokes per frame and layer, onion skin, playback).
public struct AnimationProject: ProjectPayload {
    public static let kind = StudioModule.animation
    public static let formatVersion = 1

    public var width = 1920
    public var height = 1080
    public var fps = 12
    public var background = RGBAColor.white
    public var layers: [AnimLayer] = [AnimLayer(name: "Livello 1")]
    public var frameCount = 24

    public init() {}
}

public struct AnimLayer: Codable, Hashable, Identifiable, Sendable {
    public var id = UUID()
    public var name: String
    public var visible = true
    /// Frame index → strokes. A frame without drawing shows the previous drawn frame (hold) when `hold` is on.
    public var frames: [Int: [AnimStroke]] = [:]
    public var hold = true
    public init(name: String) { self.name = name }

    public func strokes(at f: Int) -> [AnimStroke] {
        if let s = frames[f] { return s }
        guard hold else { return [] }
        let prev = frames.keys.filter { $0 < f }.max()
        return prev.flatMap { frames[$0] } ?? []
    }
}

public struct AnimStroke: Codable, Hashable, Sendable {
    public var points: [CGPoint]
    public var widths: [Double]
    public var color: RGBAColor
    public var eraser = false
}

public enum AnimRenderer {
    public static func draw(_ p: AnimationProject, frame f: Int, in ctx: CGContext, onion: Bool = false) {
        ctx.setFillColor(p.background.cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: p.width, height: p.height))
        if onion {
            for (d, color) in [(-1, RGBAColor(0.9, 0.2, 0.2, 0.3)), (1, RGBAColor(0.2, 0.5, 0.9, 0.3))] where f + d >= 0 && f + d < p.frameCount {
                for l in p.layers where l.visible {
                    for s in l.strokes(at: f + d) where !s.eraser { var c = s; c.color = color; draw(c, ctx) }
                }
            }
        }
        for l in p.layers where l.visible {
            ctx.saveGState()
            ctx.beginTransparencyLayer(auxiliaryInfo: nil)
            for s in l.strokes(at: f) { draw(s, ctx) }
            ctx.endTransparencyLayer()
            ctx.restoreGState()
        }
    }

    static func draw(_ s: AnimStroke, _ ctx: CGContext) {
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        ctx.setBlendMode(s.eraser ? .clear : .normal)
        ctx.setStrokeColor(s.color.cgColor)
        guard s.points.count > 1 else {
            if let p = s.points.first {
                let w = s.widths.first ?? 4
                ctx.setFillColor(s.color.cgColor)
                ctx.fillEllipse(in: CGRect(x: p.x - w / 2, y: p.y - w / 2, width: w, height: w))
            }
            return
        }
        for i in 1 ..< s.points.count {
            ctx.setLineWidth(s.widths[min(i, s.widths.count - 1)])
            ctx.move(to: s.points[i - 1])
            ctx.addLine(to: s.points[i])
            ctx.strokePath()
        }
        ctx.setBlendMode(.normal)
    }
}

@MainActor
@Observable
final class AnimationEditorModel {
    let project: ProjectController<AnimationProject>
    var frame = 0
    var layer = 0
    var playing = false
    var onion = true
    var color = RGBAColor.black
    var width: Double = 6
    var eraser = false
    var current: AnimStroke?
    var exported: ExportedFile?
    var error: String?
    var progress: Double?
    @ObservationIgnored var lastTick: Date?

    init(project: ProjectController<AnimationProject>) { self.project = project }
    var doc: AnimationProject { project.payload }

    func commit(_ s: AnimStroke) {
        let f = frame, l = min(layer, doc.layers.count - 1)
        project.mutate("Tratto") { p in
            // drawing on a held frame starts a new drawing that copies the held one
            var strokes = p.layers[l].frames[f] ?? p.layers[l].strokes(at: f)
            strokes.append(s)
            p.layers[l].frames[f] = strokes
        }
    }

    func tick(_ d: Date) {
        guard playing else { lastTick = nil; return }
        if let last = lastTick, d.timeIntervalSince(last) < 1 / Double(doc.fps) { return }
        lastTick = d
        frame = (frame + 1) % doc.frameCount
    }

    func clearFrame() {
        let f = frame, l = layer
        project.mutate("Svuota fotogramma") { $0.layers[l].frames[f] = [] }
    }

    func duplicatePrevious() {
        let f = frame, l = layer
        guard f > 0 else { return }
        project.mutate("Duplica fotogramma") { $0.layers[l].frames[f] = $0.layers[l].strokes(at: f - 1) }
    }

    func export(video: Bool) {
        let snap = doc, name = project.header.name
        progress = 0
        Task {
            do {
                let url: URL
                if video {
                    url = StudioPaths.exportURL(name: name, ext: "mp4")
                    try await FrameVideoWriter.write(to: url, width: snap.width, height: snap.height, fps: snap.fps, frameCount: snap.frameCount,
                                                     progress: { p in Task { @MainActor in self.progress = p } }) { i, ctx in
                        AnimRenderer.draw(snap, frame: i, in: ctx)
                    }
                } else {
                    url = StudioPaths.exportURL(name: name, ext: "gif")
                    try FrameVideoWriter.writeGIF(to: url, width: snap.width / 2, height: snap.height / 2, fps: snap.fps, frameCount: snap.frameCount) { i, ctx in
                        ctx.scaleBy(x: 0.5, y: 0.5)
                        AnimRenderer.draw(snap, frame: i, in: ctx)
                    }
                }
                exported = ExportedFile(url)
            } catch {
                self.error = error.localizedDescription
            }
            progress = nil
        }
    }
}

public struct AnimationEditorView: View {
    @State private var model: AnimationEditorModel

    public init(project: ProjectController<AnimationProject>) {
        _model = State(initialValue: AnimationEditorModel(project: project))
    }

    public var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                tools.studioPanel(width: 240, edge: .trailing)
                canvas
            }
            frames.frame(height: 110).studioBar()
        }
        .navigationTitle(model.project.header.name)
        .navigationBarTitleDisplayMode(.inline)
        .undoRedoToolbar(canUndo: model.project.canUndo, canRedo: model.project.canRedo, undo: { model.project.undo() }, redo: { model.project.redo() })
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Menu {
                    Button("Video H.264") { model.export(video: true) }
                    Button("GIF animata") { model.export(video: false) }
                } label: { Label("Esporta", systemImage: "square.and.arrow.up") }
            }
        }
        .shareSheet($model.exported)
        .overlay(alignment: .top) { if let e = model.error { ErrorBanner(e) { model.error = nil } } }
        .overlay { if let p = model.progress { ProgressOverlay("Rendering…", progress: p) } }
        .onDisappear { model.project.save() }
    }

    private var canvas: some View {
        GeometryReader { geo in
            let s = min(geo.size.width / CGFloat(model.doc.width), geo.size.height / CGFloat(model.doc.height)) * 0.95
            let origin = CGPoint(x: (geo.size.width - CGFloat(model.doc.width) * s) / 2, y: (geo.size.height - CGFloat(model.doc.height) * s) / 2)
            TimelineView(.animation(paused: !model.playing)) { tl in
                Canvas { gc, _ in
                    gc.translateBy(x: origin.x, y: origin.y)
                    gc.scaleBy(x: s, y: s)
                    gc.withCGContext { AnimRenderer.draw(model.doc, frame: model.frame, in: $0, onion: model.onion && !model.playing) }
                    if let c = model.current { gc.withCGContext { AnimRenderer.draw(c, $0) } }
                }
                .onChange(of: tl.date) { _, d in model.tick(d) }
            }
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { v in
                    let p = CGPoint(x: (v.location.x - origin.x) / s, y: (v.location.y - origin.y) / s)
                    if model.current == nil {
                        model.current = AnimStroke(points: [p], widths: [model.width], color: model.color, eraser: model.eraser)
                    } else {
                        model.current?.points.append(p)
                        model.current?.widths.append(model.width)
                    }
                }
                .onEnded { _ in
                    if let c = model.current { model.commit(c) }
                    model.current = nil
                })
            .background(StudioTheme.canvas)
        }
    }

    private var tools: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                ColorPicker("Colore", selection: Binding(get: { Color(rgba: model.color) }, set: { model.color = RGBAColor($0) }))
                ValueSlider("Spessore", value: $model.width, range: 1 ... 60, defaultValue: 6)
                Toggle("Gomma", isOn: $model.eraser)
                Toggle("Onion skin", isOn: $model.onion)
                Picker("FPS", selection: Binding(get: { model.doc.fps }, set: { v in model.project.mutate("FPS") { $0.fps = v } })) {
                    ForEach([6, 8, 12, 15, 24, 30], id: \.self) { Text("\($0)").tag($0) }
                }
                Stepper("Fotogrammi: \(model.doc.frameCount)", value: Binding(get: { model.doc.frameCount }, set: { v in model.project.mutate("Durata") { $0.frameCount = max(1, v) } }), in: 1 ... 2000)
                HStack {
                    Button("Svuota") { model.clearFrame() }
                    Button("Copia precedente") { model.duplicatePrevious() }
                }
                .buttonStyle(.bordered).font(.caption)
                PanelSection("Livelli") {
                    ForEach(Array(model.doc.layers.enumerated()).reversed(), id: \.element.id) { i, l in
                        HStack {
                            Button { model.project.mutate("Visibilità") { $0.layers[i].visible.toggle() } } label: { Image(systemName: l.visible ? "eye" : "eye.slash") }
                                .buttonStyle(.plain)
                            Text(l.name).fontWeight(model.layer == i ? .bold : .regular)
                        }
                        .onTapGesture { model.layer = i }
                    }
                    Button("Nuovo livello") {
                        model.project.mutate("Nuovo livello") { $0.layers.append(AnimLayer(name: "Livello \($0.layers.count + 1)")) }
                        model.layer = model.doc.layers.count - 1
                    }
                    .buttonStyle(.bordered).font(.caption)
                }
            }
            .padding()
        }
        .background(StudioTheme.panel)
    }

    private var frames: some View {
        VStack(spacing: 4) {
            HStack {
                Button { model.frame = max(0, model.frame - 1) } label: { Image(systemName: "backward.frame.fill") }
                Button { model.playing.toggle() } label: { Image(systemName: model.playing ? "pause.fill" : "play.fill") }
                Button { model.frame = min(model.doc.frameCount - 1, model.frame + 1) } label: { Image(systemName: "forward.frame.fill") }
                Text("Fotogramma \(model.frame + 1)/\(model.doc.frameCount)").font(.callout.monospacedDigit())
                Spacer()
            }
            .padding(.horizontal)
            ScrollView(.horizontal) {
                LazyHStack(spacing: 2) {
                    ForEach(0 ..< model.doc.frameCount, id: \.self) { f in
                        let drawn = model.doc.layers.indices.contains(model.layer) && model.doc.layers[model.layer].frames[f] != nil
                        RoundedRectangle(cornerRadius: 3)
                            .fill(f == model.frame ? Color.accentColor : drawn ? Color.gray.opacity(0.7) : Color.gray.opacity(0.25))
                            .frame(width: 22, height: 44)
                            .overlay(Text("\(f + 1)").font(.system(size: 8)).foregroundStyle(.white))
                            .onTapGesture { model.playing = false; model.frame = f }
                    }
                }
                .padding(.horizontal)
            }
        }
        .padding(.vertical, 6)
        .background(StudioTheme.panel)
    }
}
