import CoreImage
import ImageIO
import StudioCore
import StudioPaint
import SwiftUI
import UniformTypeIdentifiers

public enum RasterTool: String, CaseIterable {
    case move, select, brush, eraser, mask
    var icon: String {
        switch self {
        case .move: "arrow.up.and.down.and.arrow.left.and.right"
        case .select: "rectangle.dashed"
        case .brush: "paintbrush"
        case .eraser: "eraser"
        case .mask: "theatermask.and.paintbrush"
        }
    }
    var title: String {
        switch self {
        case .move: "Sposta livello"
        case .select: "Selezione rettangolare"
        case .brush: "Pennello"
        case .eraser: "Gomma"
        case .mask: "Pennello maschera"
        }
    }
}

@MainActor
@Observable
final class RasterEditorModel {
    let project: ProjectController<RasterProject>
    let compositor: RasterCompositor
    var image: CGImage?
    var active: UUID?
    var tool: RasterTool = .move
    var selection: CGRect?
    var brush = Brush()
    var maskReveal = false
    var error: String?
    var exported: ExportedFile?
    var canUndo = false
    var canRedo = false
    var viewport = CGSize(width: 2000, height: 2000)

    @ObservationIgnored private var bitmaps: [String: BitmapLayer] = [:]
    @ObservationIgnored private var engine = BrushEngine(brush: Brush())
    @ObservationIgnored private var renderTask: Task<Void, Never>?
    @ObservationIgnored private var dirtyRender = false

    struct Entry { var payload: RasterProject; var pixels: [String: CGImage?] }
    @ObservationIgnored private var undoStack: [Entry] = []
    @ObservationIgnored private var redoStack: [Entry] = []

    init(project: ProjectController<RasterProject>) {
        self.project = project
        compositor = RasterCompositor(projectURL: project.url)
        active = project.payload.layers.last?.id
        render()
    }

    var doc: RasterProject { project.payload }
    var layer: RasterLayer? { doc.layers.first { $0.id == active } }

    // MARK: undo

    func checkpoint(pixels keys: [String] = []) {
        var px: [String: CGImage?] = [:]
        for k in keys { px[k] = bitmap(k, create: false)?.makeImage() }
        undoStack.append(Entry(payload: doc, pixels: px))
        if undoStack.count > 40 { undoStack.removeFirst() }
        redoStack.removeAll()
        refreshUndo()
    }

    func undo() { swap(&undoStack, &redoStack) }
    func redo() { swap(&redoStack, &undoStack) }

    private func swap(_ a: inout [Entry], _ b: inout [Entry]) {
        guard let e = a.popLast() else { return }
        var px: [String: CGImage?] = [:]
        for k in e.pixels.keys { px[k] = bitmap(k, create: false)?.makeImage() }
        b.append(Entry(payload: doc, pixels: px))
        project.payload = e.payload
        for (k, img) in e.pixels { bitmap(k, create: true)?.set(img ?? nil) }
        if !doc.layers.contains(where: { $0.id == active }) { active = doc.layers.last?.id }
        refreshUndo()
        render()
    }

    private func refreshUndo() { canUndo = !undoStack.isEmpty; canRedo = !redoStack.isEmpty }

    func change(_ f: (inout RasterProject) -> Void) {
        checkpoint()
        f(&project.payload)
        render()
    }

    func updateLayer(_ f: (inout RasterLayer) -> Void) {
        guard let id = active, let i = doc.layers.firstIndex(where: { $0.id == id }) else { return }
        change { f(&$0.layers[i]) }
    }

    // MARK: pixels

    func bitmap(_ key: String, create: Bool) -> BitmapLayer? {
        if let b = bitmaps[key] { return b }
        let url = project.resolve(key)
        if let img = PaintDocumentState.loadPNG(url) {
            let b = BitmapLayer(image: img, width: doc.width, height: doc.height)
            bitmaps[key] = b
            return b
        }
        guard create else { return nil }
        let b = BitmapLayer(width: doc.width, height: doc.height)
        bitmaps[key] = b
        return b
    }

    var overrides: [String: CIImage] {
        var o: [String: CIImage] = [:]
        for (k, b) in bitmaps { if let img = b.makeImage() { o[k] = CIImage(cgImage: img) } }
        return o
    }

    // MARK: layers

    func importImage(_ url: URL) {
        do {
            let rel = try project.importMedia(url)
            let first = doc.layers.isEmpty
            if first, let src = CGImageSourceCreateWithURL(project.resolve(rel) as CFURL, nil),
               let p = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
               let w = p[kCGImagePropertyPixelWidth] as? Int, let h = p[kCGImagePropertyPixelHeight] as? Int {
                // the first image sets the canvas size (capped to keep memory reasonable)
                let s = min(1, 8000.0 / Double(max(w, h)))
                change { $0.width = Int(Double(w) * s); $0.height = Int(Double(h) * s) }
            }
            let l = RasterLayer(name: url.deletingPathExtension().lastPathComponent, content: .image(rel))
            change { $0.layers.append(l) }
            active = l.id
        } catch {
            self.error = error.localizedDescription
        }
    }

    func addPaintLayer() {
        let l = RasterLayer(name: "Pittura \(doc.layers.count + 1)", content: .paint)
        change { $0.layers.append(l) }
        active = l.id
        _ = bitmap(l.paintFile, create: true)
        tool = .brush
    }

    func addFillLayer() {
        let l = RasterLayer(name: "Riempimento", content: .fill(brush.color))
        change { $0.layers.append(l) }
        active = l.id
    }

    func deleteLayer() {
        guard let id = active else { return }
        change { $0.layers.removeAll { $0.id == id } }
        active = doc.layers.last?.id
    }

    func moveLayer(up: Bool) {
        guard let id = active, let i = doc.layers.firstIndex(where: { $0.id == id }) else { return }
        let j = up ? i + 1 : i - 1
        guard doc.layers.indices.contains(j) else { return }
        change { $0.layers.swapAt(i, j) }
    }

    // MARK: selection actions

    func addMaskFromSelection() {
        guard let l = layer else { return }
        let key = l.maskFile
        checkpoint(pixels: [key])
        guard let m = bitmap(key, create: true) else { return }
        m.context.setFillColor(UIColor.black.cgColor)
        m.context.fill(CGRect(x: 0, y: 0, width: doc.width, height: doc.height))
        m.context.setFillColor(UIColor.white.cgColor)
        m.context.fill(selection ?? CGRect(x: 0, y: 0, width: doc.width, height: doc.height))
        if let i = doc.layers.firstIndex(where: { $0.id == l.id }) { project.payload.layers[i].hasMask = true }
        render()
    }

    func invertMask() {
        guard let l = layer, l.hasMask, let m = bitmap(l.maskFile, create: false), let img = m.makeImage() else { return }
        checkpoint(pixels: [l.maskFile])
        let inv = CIImage(cgImage: img).applyingFilter("CIColorInvert")
        m.set(compositor.context.createCGImage(inv, from: inv.extent))
        render()
    }

    func fillSelection() {
        guard let sel = selection else { error = "Disegna prima una selezione"; return }
        if layer.map({ if case .paint = $0.content { false } else { true } }) ?? true { addPaintLayer() }
        guard let l = layer else { return }
        checkpoint(pixels: [l.paintFile])
        let b = bitmap(l.paintFile, create: true)!
        b.context.setFillColor(brush.color.cgColor)
        b.context.fill(sel)
        render()
    }

    func clearSelection() {
        guard let sel = selection, let l = layer, case .paint = l.content, let b = bitmap(l.paintFile, create: true) else {
            error = "Cancellare una selezione richiede un livello di pittura attivo"
            return
        }
        checkpoint(pixels: [l.paintFile])
        b.context.clear(sel)
        render()
    }

    func cropToSelection() {
        guard let sel = selection?.integral, sel.width > 4, sel.height > 4 else { return }
        // move every layer so the selection's top-left becomes the origin; pixel layers are shifted
        let keys = doc.layers.flatMap { [$0.paintFile, $0.maskFile] }.filter { bitmap($0, create: false) != nil }
        checkpoint(pixels: keys)
        let newW = Int(sel.width), newH = Int(sel.height)
        for k in keys {
            guard let old = bitmap(k, create: false)?.makeImage(), let cropped = old.cropping(to: sel) else { continue }
            bitmaps[k] = BitmapLayer(image: cropped, width: newW, height: newH)
        }
        let dx = Double(doc.width) / 2 - Double(sel.midX), dy = Double(doc.height) / 2 - Double(sel.midY)
        let oldW = Double(doc.width), oldH = Double(doc.height)
        project.payload.width = newW
        project.payload.height = newH
        for i in doc.layers.indices {
            guard case .image(let path) = doc.layers[i].content, let e = compositor.load(path)?.extent, e.width > 0, e.height > 0 else { continue }
            // keep the image's pixels where they were: same displayed size, centre shifted by the crop
            let fitOld = min(oldW / e.width, oldH / e.height)
            let fitNew = min(Double(newW) / e.width, Double(newH) / e.height)
            project.payload.layers[i].scale *= fitOld / fitNew
            project.payload.layers[i].x += dx
            project.payload.layers[i].y += dy
        }
        selection = nil
        compositor.invalidate()
        render()
    }

    // MARK: painting

    private var strokeKey: String?

    func strokeBegan(_ p: CGPoint) {
        guard let l = layer else { return }
        var b = brush
        let key: String
        switch tool {
        case .mask:
            key = l.maskFile
            if !l.hasMask {
                checkpoint(pixels: [key])
                let m = bitmap(key, create: true)!
                m.context.setFillColor(UIColor.white.cgColor)
                m.context.fill(CGRect(x: 0, y: 0, width: doc.width, height: doc.height))
                if let i = doc.layers.firstIndex(where: { $0.id == l.id }) { project.payload.layers[i].hasMask = true }
            } else { checkpoint(pixels: [key]) }
            b.kind = .round
            b.color = maskReveal ? .white : .black
        case .eraser:
            guard case .paint = l.content else { error = "La gomma agisce sui livelli di pittura"; return }
            key = l.paintFile
            checkpoint(pixels: [key])
            b.kind = .eraser
        default:
            guard case .paint = l.content else { addPaintLayer(); strokeBegan(p); return }
            key = l.paintFile
            checkpoint(pixels: [key])
        }
        strokeKey = key
        engine.brush = b
        guard let bm = bitmap(key, create: true) else { return }
        _ = engine.begin(StrokeSample(point: p), in: bm.context)
        renderSoon()
    }

    func strokeMoved(_ p: CGPoint) {
        guard let key = strokeKey, let bm = bitmap(key, create: true) else { return }
        _ = engine.move(to: StrokeSample(point: p), in: bm.context)
        renderSoon()
    }

    func strokeEnded() {
        engine.end()
        strokeKey = nil
        render()
    }

    // MARK: render + save

    func renderSoon() {
        dirtyRender = true
        guard renderTask == nil else { return }
        renderTask = Task { [weak self] in
            while let self, self.dirtyRender {
                self.dirtyRender = false
                let p = self.doc, o = self.overrides, c = self.compositor, size = self.viewport
                let img = await Task.detached(priority: .userInitiated) { c.render(p, maxSize: size, overrides: o) }.value
                self.image = img
            }
            self?.renderTask = nil
        }
    }

    func render() { renderSoon() }

    func save() {
        do {
            try FileManager.default.createDirectory(at: project.url.appendingPathComponent("Media/Raster"), withIntermediateDirectories: true)
            for (k, b) in bitmaps {
                guard let img = b.makeImage() else { continue }
                try PaintDocumentState.writePNG(img, to: project.resolve(k))
                compositor.invalidate(k)
            }
            project.save()
        } catch {
            self.error = error.localizedDescription
        }
    }

    func export(_ type: UTType) {
        save()
        let url = StudioPaths.exportURL(name: project.header.name, ext: type == .png ? "png" : type == .tiff ? "tif" : "jpg")
        do {
            let p = doc, o = overrides
            var img = compositor.compose(p, overrides: o)
            img = img.cropped(to: CGRect(x: 0, y: 0, width: p.width, height: p.height))
            guard let cg = compositor.context.createCGImage(img, from: img.extent, format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)) else { return }
            try PaintDocumentState.writePNG(cg, to: url, type: type)
            exported = ExportedFile(url)
        } catch {
            self.error = error.localizedDescription
        }
    }
}

public struct RasterEditorView: View {
    @State private var model: RasterEditorModel
    @State private var importing = false
    @State private var selStart: CGPoint?
    @State private var moveStart: (Double, Double)?

    public init(project: ProjectController<RasterProject>) {
        _model = State(initialValue: RasterEditorModel(project: project))
    }

    public var body: some View {
        HStack(spacing: 0) {
            tools
            canvas
            panel.studioPanel(width: 300)
        }
        .navigationTitle(model.project.header.name)
        .navigationBarTitleDisplayMode(.inline)
        .undoRedoToolbar(canUndo: model.canUndo, canRedo: model.canRedo, undo: model.undo, redo: model.redo)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button { importing = true } label: { Label("Importa immagine", systemImage: "photo.badge.plus") }
                Menu {
                    Button("PNG") { model.export(.png) }
                    Button("JPEG") { model.export(.jpeg) }
                    Button("TIFF") { model.export(.tiff) }
                } label: { Label("Esporta", systemImage: "square.and.arrow.up") }
            }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.image]) { r in
            if case .success(let u) = r { model.importImage(u) }
        }
        .shareSheet($model.exported)
        .overlay(alignment: .top) { if let e = model.error { ErrorBanner(e) { model.error = nil } } }
        .onDisappear {
            model.save()
            model.project.saveThumbnail(model.image)
        }
    }

    private var tools: some View {
        VStack(spacing: 4) {
            ForEach(RasterTool.allCases, id: \.self) { t in
                ToolRailButton(t.title, systemImage: t.icon, isSelected: model.tool == t) { model.tool = t }
            }
            RailDivider()
            ColorPicker("Colore", selection: Binding(get: { Color(rgba: model.brush.color) }, set: { model.brush.color = RGBAColor($0) })).labelsHidden()
            Spacer()
        }
        .studioRail()
    }

    private var canvas: some View {
        GeometryReader { geo in
            let d = model.doc
            let s = min(geo.size.width / CGFloat(d.width), geo.size.height / CGFloat(d.height)) * 0.95
            let origin = CGPoint(x: (geo.size.width - CGFloat(d.width) * s) / 2, y: (geo.size.height - CGFloat(d.height) * s) / 2)
            let toDoc = { (p: CGPoint) in CGPoint(x: (p.x - origin.x) / s, y: (p.y - origin.y) / s) }
            ZStack(alignment: .topLeading) {
                StudioTheme.canvas
                if let img = model.image {
                    Image(decorative: img, scale: 1).resizable().frame(width: CGFloat(d.width) * s, height: CGFloat(d.height) * s)
                        .offset(x: origin.x, y: origin.y)
                }
                if let sel = model.selection {
                    Rectangle().stroke(Color.white, style: StrokeStyle(lineWidth: 1.5, dash: [6]))
                        .frame(width: sel.width * s, height: sel.height * s)
                        .offset(x: origin.x + sel.minX * s, y: origin.y + sel.minY * s)
                        .allowsHitTesting(false)
                }
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { v in
                    let p = toDoc(v.location), start = toDoc(v.startLocation)
                    switch model.tool {
                    case .select:
                        model.selection = CGRect(x: min(start.x, p.x), y: min(start.y, p.y), width: abs(p.x - start.x), height: abs(p.y - start.y))
                            .intersection(CGRect(x: 0, y: 0, width: d.width, height: d.height))
                    case .move:
                        guard let l = model.layer else { return }
                        if moveStart == nil { moveStart = (l.x, l.y); model.checkpoint() }
                        if let (x0, y0) = moveStart, let i = d.layers.firstIndex(where: { $0.id == l.id }) {
                            model.project.payload.layers[i].x = x0 + (p.x - start.x)
                            model.project.payload.layers[i].y = y0 + (p.y - start.y)
                            model.renderSoon()
                        }
                    case .brush, .eraser, .mask:
                        if selStart == nil { selStart = start; model.strokeBegan(start) }
                        model.strokeMoved(p)
                    }
                }
                .onEnded { _ in
                    if selStart != nil { model.strokeEnded() }
                    selStart = nil
                    moveStart = nil
                    if model.tool == .select, let s = model.selection, s.width < 3 || s.height < 3 { model.selection = nil }
                })
            .onAppear { model.viewport = CGSize(width: geo.size.width * 2, height: geo.size.height * 2); model.render() }
        }
    }

    private var panel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                if model.tool == .brush || model.tool == .eraser || model.tool == .mask {
                    PanelSection("Pennello") {
                        ValueSlider("Dimensione", value: $model.brush.size, range: 1 ... 600, defaultValue: 24)
                        ValueSlider("Flusso", value: $model.brush.opacity, range: 0.01 ... 1, step: 0.01, defaultValue: 1, format: { String(format: "%.0f%%", $0 * 100) })
                        ValueSlider("Durezza", value: $model.brush.hardness, range: 0 ... 1, step: 0.01, defaultValue: 0.8, format: { String(format: "%.2f", $0) })
                        if model.tool == .mask {
                            Picker("Maschera", selection: $model.maskReveal) {
                                Text("Nascondi (nero)").tag(false)
                                Text("Rivela (bianco)").tag(true)
                            }
                            .pickerStyle(.segmented)
                        }
                    }
                }
                PanelSection("Selezione", expanded: model.selection != nil) {
                    if let s = model.selection {
                        Text(String(format: "%.0f × %.0f px", s.width, s.height)).font(.caption.monospacedDigit())
                    } else {
                        Text("Usa lo strumento selezione per tracciare un rettangolo.").font(.caption).foregroundStyle(.secondary)
                    }
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 120))]) {
                        Button("Ritaglia tela") { model.cropToSelection() }
                        Button("Riempi") { model.fillSelection() }
                        Button("Cancella") { model.clearSelection() }
                        Button("Maschera") { model.addMaskFromSelection() }
                        Button("Deseleziona") { model.selection = nil }
                    }
                    .buttonStyle(.bordered).font(.caption).disabled(model.selection == nil)
                }
                if let l = model.layer { layerPanel(l) }
                layersList
            }
            .padding()
        }
        .background(StudioTheme.panel)
    }

    private func layerPanel(_ l: RasterLayer) -> some View {
        PanelSection("Livello: \(l.name)") {
            ValueSlider("Opacità", value: Binding(get: { l.opacity }, set: { v in model.updateLayer { $0.opacity = v } }), range: 0 ... 1, step: 0.01,
                        defaultValue: 1, format: { String(format: "%.0f%%", $0 * 100) })
            Picker("Fusione", selection: Binding(get: { l.blend }, set: { v in model.updateLayer { $0.blend = v } })) {
                ForEach(RasterBlend.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            if case .image = l.content {
                ValueSlider("Scala", value: Binding(get: { l.scale }, set: { v in model.updateLayer { $0.scale = v } }), range: 0.05 ... 5, step: 0.01, defaultValue: 1,
                            format: { String(format: "%.2f", $0) })
                ValueSlider("Rotazione", value: Binding(get: { l.rotation }, set: { v in model.updateLayer { $0.rotation = v } }), range: -180 ... 180)
            }
            if case .fill(let c) = l.content {
                ColorPicker("Colore", selection: Binding(get: { Color(rgba: c) }, set: { v in model.updateLayer { $0.content = .fill(RGBAColor(v)) } }))
            }
            if l.hasMask {
                Toggle("Maschera attiva", isOn: Binding(get: { l.maskEnabled }, set: { v in model.updateLayer { $0.maskEnabled = v } }))
                HStack {
                    Button("Inverti maschera") { model.invertMask() }
                    Button("Rimuovi", role: .destructive) { model.updateLayer { $0.hasMask = false } }
                }
                .buttonStyle(.bordered).font(.caption)
            }
            Text("Filtri non distruttivi").font(.caption.weight(.semibold)).padding(.top, 4)
            ForEach(Array(l.filters.enumerated()), id: \.element.id) { i, f in
                HStack {
                    Toggle("", isOn: Binding(get: { f.enabled }, set: { v in model.updateLayer { $0.filters[i].enabled = v } })).labelsHidden()
                    ValueSlider(f.kind.title, value: Binding(get: { f.amount }, set: { v in
                        model.project.payload.layers[model.doc.layers.firstIndex { $0.id == l.id }!].filters[i].amount = v
                        model.renderSoon()
                    }), range: f.kind.range, step: (f.kind.range.upperBound - f.kind.range.lowerBound) / 200, defaultValue: f.kind.defaultAmount,
                                format: { String(format: "%.2f", $0) }, onEditing: { if $0 { model.checkpoint() } })
                    Button { model.updateLayer { $0.filters.remove(at: i) } } label: { Image(systemName: "minus.circle") }.buttonStyle(.plain)
                }
            }
            Menu("Aggiungi filtro") {
                ForEach(RasterFilterKind.allCases, id: \.self) { k in Button(k.title) { model.updateLayer { $0.filters.append(RasterFilter(k)) } } }
            }
        }
    }

    private var layersList: some View {
        PanelSection("Livelli") {
            ForEach(model.doc.layers.reversed()) { l in
                HStack {
                    Button { model.active = l.id; model.updateLayer { $0.visible.toggle() } } label: { Image(systemName: l.visible ? "eye" : "eye.slash") }.buttonStyle(.plain)
                    Image(systemName: { if case .paint = l.content { "paintbrush" } else if case .fill = l.content { "square.fill" } else { "photo" } }())
                    Text(l.name).lineLimit(1).fontWeight(model.active == l.id ? .bold : .regular)
                    if l.hasMask { Image(systemName: "theatermasks").font(.caption) }
                    Spacer()
                }
                .padding(6)
                .background(model.active == l.id ? Color.accentColor.opacity(0.2) : .clear, in: RoundedRectangle(cornerRadius: 6))
                .contentShape(Rectangle())
                .onTapGesture { model.active = l.id }
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 110))]) {
                Button("Pittura") { model.addPaintLayer() }
                Button("Riempimento") { model.addFillLayer() }
                Button("Su") { model.moveLayer(up: true) }
                Button("Giù") { model.moveLayer(up: false) }
                Button("Elimina", role: .destructive) { model.deleteLayer() }
            }
            .buttonStyle(.bordered).font(.caption)
        }
    }
}
