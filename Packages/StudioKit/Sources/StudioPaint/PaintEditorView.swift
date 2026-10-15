import StudioCore
import SwiftUI
import UniformTypeIdentifiers

@MainActor
@Observable
final class PaintEditorModel {
    let project: ProjectController<PaintProject>
    let state: PaintDocumentState
    var activeLayer: UUID?
    var pencilOnly = false
    var eyedropper = false
    var revision = 0
    var error: String?
    var exported: ExportedFile?
    var canUndo = false
    var canRedo = false
    @ObservationIgnored private var saveTask: Task<Void, Never>?

    init(project: ProjectController<PaintProject>) {
        self.project = project
        state = PaintDocumentState(project: project.payload, projectURL: project.url)
        activeLayer = project.payload.layers.last?.id
    }

    var doc: PaintProject { project.payload }
    var brush: Brush {
        get { doc.brush }
        set { project.payload.brush = newValue }
    }

    func strokeBegan() {
        guard let id = activeLayer else { return }
        state.checkpoint(doc.layers, ids: [id], label: "Tratto")
        refreshUndo()
    }

    func strokeEnded() { scheduleSave() }

    func pick(_ p: CGPoint) {
        guard let img = state.flatten(doc) else { return }
        let tmp = BitmapLayer(image: img, width: state.width, height: state.height)
        if var c = tmp.color(at: p) {
            c.a = 1
            brush.color = c
            if brush.kind == .eraser { brush.kind = .round }
        }
        eyedropper = false
    }

    func setBrushKind(_ k: BrushKind) {
        var b = Brush(kind: k)
        b.color = brush.color
        brush = b
    }

    func addLayer() {
        state.checkpoint(doc.layers, ids: [], label: "Nuovo livello")
        let l = PaintLayerInfo(name: "Livello \(doc.layers.count + 1)")
        let idx = doc.layers.firstIndex { $0.id == activeLayer }.map { $0 + 1 } ?? doc.layers.count
        project.payload.layers.insert(l, at: idx)
        activeLayer = l.id
        refreshUndo()
        scheduleSave()
    }

    func deleteLayer() {
        guard doc.layers.count > 1, let id = activeLayer, let i = doc.layers.firstIndex(where: { $0.id == id }) else { return }
        state.checkpoint(doc.layers, ids: [id], label: "Elimina livello")
        project.payload.layers.remove(at: i)
        activeLayer = doc.layers[max(0, i - 1)].id
        refreshUndo()
        scheduleSave()
    }

    func clearLayer() {
        guard let id = activeLayer else { return }
        state.checkpoint(doc.layers, ids: [id], label: "Cancella livello")
        state.bitmap(id).clear()
        revision += 1
        refreshUndo()
        scheduleSave()
    }

    func mergeDown() {
        guard let id = activeLayer, let i = doc.layers.firstIndex(where: { $0.id == id }), i > 0 else { return }
        let below = doc.layers[i - 1], top = doc.layers[i]
        state.checkpoint(doc.layers, ids: [below.id, top.id], label: "Unisci in basso")
        if let img = state.bitmap(top.id).makeImage() {
            let ctx = state.bitmap(below.id).context
            ctx.saveGState()
            ctx.translateBy(x: 0, y: CGFloat(state.height))
            ctx.scaleBy(x: 1, y: -1)
            ctx.setAlpha(top.opacity)
            ctx.setBlendMode(top.blend.cgBlend)
            ctx.draw(img, in: CGRect(x: 0, y: 0, width: state.width, height: state.height))
            ctx.restoreGState()
        }
        project.payload.layers.remove(at: i)
        activeLayer = below.id
        revision += 1
        refreshUndo()
        scheduleSave()
    }

    func moveLayer(up: Bool) {
        guard let id = activeLayer, let i = doc.layers.firstIndex(where: { $0.id == id }) else { return }
        let j = up ? i + 1 : i - 1
        guard doc.layers.indices.contains(j) else { return }
        state.checkpoint(doc.layers, ids: [], label: "Ordina livelli")
        project.payload.layers.swapAt(i, j)
        refreshUndo()
    }

    func updateLayer(_ id: UUID, _ f: (inout PaintLayerInfo) -> Void) {
        guard let i = doc.layers.firstIndex(where: { $0.id == id }) else { return }
        f(&project.payload.layers[i])
        scheduleSave()
    }

    func undo() {
        if let l = state.undo(current: doc.layers) { project.payload.layers = l }
        fixActive()
        revision += 1
        refreshUndo()
        scheduleSave()
    }

    func redo() {
        if let l = state.redo(current: doc.layers) { project.payload.layers = l }
        fixActive()
        revision += 1
        refreshUndo()
        scheduleSave()
    }

    private func fixActive() {
        if !doc.layers.contains(where: { $0.id == activeLayer }) { activeLayer = doc.layers.last?.id }
    }

    private func refreshUndo() {
        canUndo = state.canUndo
        canRedo = state.canRedo
    }

    func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            self?.saveNow()
        }
    }

    func saveNow() {
        do {
            try state.save(doc, to: project.url)
            project.save()
        } catch {
            self.error = error.localizedDescription
        }
    }

    func importImage(_ url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let img = PaintDocumentState.loadPNG(url) else { error = "Immagine non leggibile"; return }
        state.checkpoint(doc.layers, ids: [], label: "Importa immagine")
        let l = PaintLayerInfo(name: url.deletingPathExtension().lastPathComponent)
        let b = state.bitmap(l.id)
        // fit inside the canvas, centred
        let s = min(Double(state.width) / Double(img.width), Double(state.height) / Double(img.height), 1)
        let w = Double(img.width) * s, h = Double(img.height) * s
        let ctx = b.context
        ctx.saveGState()
        ctx.translateBy(x: 0, y: CGFloat(state.height))
        ctx.scaleBy(x: 1, y: -1)
        ctx.draw(img, in: CGRect(x: (Double(state.width) - w) / 2, y: (Double(state.height) - h) / 2, width: w, height: h))
        ctx.restoreGState()
        project.payload.layers.append(l)
        activeLayer = l.id
        revision += 1
        refreshUndo()
        scheduleSave()
    }

    func export(_ type: UTType) {
        guard let img = state.flatten(doc, background: true) else { return }
        let url = StudioPaths.exportURL(name: project.header.name, ext: type == .png ? "png" : "jpg")
        do {
            try PaintDocumentState.writePNG(img, to: url, type: type)
            exported = ExportedFile(url)
        } catch {
            self.error = error.localizedDescription
        }
    }
}

public struct PaintEditorView: View {
    @State private var model: PaintEditorModel
    @State private var importing = false

    public init(project: ProjectController<PaintProject>) {
        _model = State(initialValue: PaintEditorModel(project: project))
    }

    public var body: some View {
        HStack(spacing: 0) {
            brushes
            PaintCanvasRepresentable(
                state: model.state, project: model.doc, activeLayer: model.activeLayer, pencilOnly: model.pencilOnly,
                eyedropper: model.eyedropper, revision: model.revision,
                onStrokeBegan: { model.strokeBegan() }, onStrokeEnded: { model.strokeEnded() }, onPick: { model.pick($0) }
            )
            .accessibilityLabel("Tela di pittura")
            sidebar.studioPanel(width: 280)
        }
        .navigationTitle(model.project.header.name)
        .navigationBarTitleDisplayMode(.inline)
        .undoRedoToolbar(canUndo: model.canUndo, canRedo: model.canRedo, undo: model.undo, redo: model.redo)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Toggle(isOn: $model.pencilOnly) { Label("Solo Pencil", systemImage: "applepencil") }
                Button { importing = true } label: { Label("Importa immagine", systemImage: "photo.badge.plus") }
                Menu {
                    Button("PNG") { model.export(.png) }
                    Button("JPEG") { model.export(.jpeg) }
                } label: { Label("Esporta", systemImage: "square.and.arrow.up") }
            }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.image]) { r in
            if case .success(let url) = r { model.importImage(url) }
        }
        .shareSheet($model.exported)
        .overlay(alignment: .top) { if let e = model.error { ErrorBanner(e) { model.error = nil } } }
        .onDisappear {
            model.saveNow()
            model.project.saveThumbnail(model.state.flatten(model.doc))
        }
    }

    private var brushes: some View {
        VStack(spacing: 4) {
            ForEach(BrushKind.allCases) { k in
                ToolRailButton(k.title, systemImage: k.icon, isSelected: model.brush.kind == k && !model.eyedropper) {
                    model.eyedropper = false
                    model.setBrushKind(k)
                }
            }
            RailDivider()
            ToolRailButton("Contagocce", systemImage: "eyedropper", isSelected: model.eyedropper) { model.eyedropper.toggle() }
            Spacer()
        }
        .studioRail()
    }

    private var sidebar: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                PanelSection("Pennello: \(model.brush.kind.title)") {
                    ColorPicker("Colore", selection: Binding(get: { Color(rgba: model.brush.color) }, set: { model.brush.color = RGBAColor($0) }))
                    HStack {
                        ForEach(Array(model.doc.swatches.enumerated()), id: \.offset) { _, c in
                            Circle().fill(Color(rgba: c)).frame(width: 26, height: 26).overlay(Circle().stroke(.secondary))
                                .onTapGesture { model.brush.color = c }
                        }
                    }
                    ValueSlider("Dimensione", value: Binding(get: { model.brush.size }, set: { model.brush.size = $0 }), range: 1 ... 400, defaultValue: 24)
                    ValueSlider("Flusso", value: Binding(get: { model.brush.opacity }, set: { model.brush.opacity = $0 }), range: 0.01 ... 1, step: 0.01,
                                defaultValue: 1, format: { String(format: "%.0f%%", $0 * 100) })
                    ValueSlider("Durezza", value: Binding(get: { model.brush.hardness }, set: { model.brush.hardness = $0 }), range: 0 ... 1, step: 0.01,
                                defaultValue: 0.8, format: { String(format: "%.2f", $0) })
                    ValueSlider("Spaziatura", value: Binding(get: { model.brush.spacing }, set: { model.brush.spacing = $0 }), range: 0.02 ... 1, step: 0.01,
                                defaultValue: 0.12, format: { String(format: "%.2f", $0) })
                    Toggle("Pressione → dimensione", isOn: Binding(get: { model.brush.pressureSize }, set: { model.brush.pressureSize = $0 }))
                    Toggle("Pressione → opacità", isOn: Binding(get: { model.brush.pressureOpacity }, set: { model.brush.pressureOpacity = $0 }))
                    Toggle("Inclinazione (matita)", isOn: Binding(get: { model.brush.tiltShading }, set: { model.brush.tiltShading = $0 }))
                }
                PanelSection("Livelli") {
                    ForEach(model.doc.layers.reversed()) { l in
                        HStack {
                            Button { model.updateLayer(l.id) { $0.visible.toggle() } } label: { Image(systemName: l.visible ? "eye" : "eye.slash") }
                                .buttonStyle(.plain)
                            Text(l.name).fontWeight(model.activeLayer == l.id ? .bold : .regular)
                            Spacer()
                            Text(l.blend.title).font(.caption2).foregroundStyle(.secondary)
                        }
                        .padding(6)
                        .background(model.activeLayer == l.id ? Color.accentColor.opacity(0.2) : .clear, in: RoundedRectangle(cornerRadius: 6))
                        .contentShape(Rectangle())
                        .onTapGesture { model.activeLayer = l.id }
                    }
                    if let id = model.activeLayer, let l = model.doc.layers.first(where: { $0.id == id }) {
                        ValueSlider("Opacità livello", value: Binding(get: { l.opacity }, set: { v in model.updateLayer(id) { $0.opacity = v } }), range: 0 ... 1,
                                    step: 0.01, defaultValue: 1, format: { String(format: "%.0f%%", $0 * 100) })
                        Picker("Fusione", selection: Binding(get: { l.blend }, set: { v in model.updateLayer(id) { $0.blend = v } })) {
                            ForEach(LayerBlend.allCases, id: \.self) { Text($0.title).tag($0) }
                        }
                        Text("Le modalità di fusione sono applicate nell'esportazione e nell'unione dei livelli; la tela mostra la fusione normale.")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 110))]) {
                        Button("Nuovo") { model.addLayer() }
                        Button("Su") { model.moveLayer(up: true) }
                        Button("Giù") { model.moveLayer(up: false) }
                        Button("Unisci sotto") { model.mergeDown() }
                        Button("Svuota") { model.clearLayer() }
                        Button("Elimina", role: .destructive) { model.deleteLayer() }
                    }
                    .buttonStyle(.bordered).font(.caption)
                }
            }
            .padding()
        }
        .background(StudioTheme.panel)
    }
}
