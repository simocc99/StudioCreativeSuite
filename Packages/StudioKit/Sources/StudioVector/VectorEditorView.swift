import StudioCore
import SwiftUI
import UniformTypeIdentifiers

public enum VectorTool: String, CaseIterable, Identifiable {
    case select, node, rect, ellipse, pen, text
    public var id: String { rawValue }
    var icon: String {
        switch self {
        case .select: "cursorarrow"
        case .node: "point.topleft.down.to.point.bottomright.curvepath"
        case .rect: "rectangle"
        case .ellipse: "circle"
        case .pen: "pencil.tip"
        case .text: "textformat"
        }
    }
    var title: String {
        switch self {
        case .select: "Selezione (V)"
        case .node: "Nodi (A)"
        case .rect: "Rettangolo (M)"
        case .ellipse: "Ellisse (L)"
        case .pen: "Penna (P)"
        case .text: "Testo (T)"
        }
    }
}

@MainActor
@Observable
final class VectorEditorModel {
    let project: ProjectController<VectorProject>
    var tool: VectorTool = .select
    var selection: Set<UUID> = []
    var activeLayer = 0
    var zoom: CGFloat = 0.5
    var error: String?
    var exported: ExportedFile?
    /// The path being drawn with the pen tool.
    var penNodes: [BezierNode] = []
    var draft: VectorShape?
    var fillColor = RGBAColor(0.2, 0.45, 0.9)
    var strokeColor = RGBAColor.black
    var strokeWidth: Double = 0

    init(project: ProjectController<VectorProject>) {
        self.project = project
    }

    var doc: VectorProject { project.payload }
    var selectedShapes: [VectorShape] { doc.allShapes.filter { selection.contains($0.id) } }

    func edit(_ label: String, _ f: (inout VectorProject) -> Void) { project.mutate(label, f) }

    func add(_ s: VectorShape) {
        if doc.layers[safe: activeLayer]?.locked == true { error = "Il livello è bloccato"; return }
        let layer = min(activeLayer, doc.layers.count - 1)
        edit("Aggiungi \(s.name)") { $0.layers[layer].shapes.append(s) }
        selection = [s.id]
    }

    func hit(_ p: CGPoint) -> VectorShape? {
        for layer in doc.layers.reversed() where layer.visible && !layer.locked {
            for s in layer.shapes.reversed() {
                let tol = max(6, s.strokeWidth) / zoom
                if s.path.contains(p) || s.path.copy(strokingWithWidth: tol, lineCap: .round, lineJoin: .round, miterLimit: 1).contains(p) { return s }
                if case .text = s.kind, s.frame.contains(p) { return s }
            }
        }
        return nil
    }

    func moveSelection(dx: Double, dy: Double) {
        let ids = selection
        edit("Sposta") { d in for id in ids { d.update(id) { $0.offset(dx: dx, dy: dy) } } }
    }

    func deleteSelection() {
        let ids = selection
        edit("Elimina") { d in for i in d.layers.indices { d.layers[i].shapes.removeAll { ids.contains($0.id) } } }
        selection.removeAll()
    }

    func duplicateSelection() {
        let shapes = selectedShapes
        var newIDs: Set<UUID> = []
        edit("Duplica") { d in
            for s in shapes {
                guard let (l, _) = d.locate(s.id) else { continue }
                var c = s
                c.id = UUID()
                c.offset(dx: 20, dy: 20)
                d.layers[l].shapes.append(c)
                newIDs.insert(c.id)
            }
        }
        selection = newIDs
    }

    func boolean(_ op: BooleanOp) {
        let shapes = doc.allShapes.filter { selection.contains($0.id) }
        guard shapes.count >= 2 else { error = "Seleziona almeno due forme"; return }
        guard let r = VectorOps.boolean(op, shapes) else { error = "Il risultato è vuoto"; return }
        let ids = selection
        let layer = doc.locate(shapes[0].id)?.0 ?? 0
        edit(op.title) { d in
            for i in d.layers.indices { d.layers[i].shapes.removeAll { ids.contains($0.id) } }
            d.layers[layer].shapes.append(r)
        }
        selection = [r.id]
    }

    func align(_ a: VectorOps.Alignment) {
        let ids = selection
        let art = CGRect(x: 0, y: 0, width: doc.width, height: doc.height)
        edit("Allinea") { d in
            var shapes = d.allShapes.filter { ids.contains($0.id) }
            VectorOps.align(&shapes, a, artboard: art)
            for s in shapes { d.update(s.id) { $0 = s } }
        }
    }

    func group() {
        let ids = selection, g = UUID()
        edit("Raggruppa") { d in for id in ids { d.update(id) { $0.groupID = g } } }
    }

    func ungroup() {
        let ids = selection
        edit("Separa") { d in for id in ids { d.update(id) { $0.groupID = nil } } }
    }

    /// Selecting a grouped shape selects its whole group.
    func select(_ s: VectorShape?, extend: Bool) {
        guard let s else { if !extend { selection.removeAll() }; return }
        var ids: Set<UUID> = [s.id]
        if let g = s.groupID { ids = Set(doc.allShapes.filter { $0.groupID == g }.map(\.id)) }
        if extend { selection.formSymmetricDifference(ids) } else { selection = ids }
    }

    func arrange(front: Bool) {
        let ids = selection
        edit(front ? "Porta in primo piano" : "Porta in fondo") { d in
            for i in d.layers.indices {
                let sel = d.layers[i].shapes.filter { ids.contains($0.id) }
                d.layers[i].shapes.removeAll { ids.contains($0.id) }
                d.layers[i].shapes = front ? d.layers[i].shapes + sel : sel + d.layers[i].shapes
            }
        }
    }

    func finishPen(closed: Bool) {
        guard penNodes.count >= 2 else { penNodes = []; return }
        var s = VectorShape(name: "Tracciato", kind: .path(nodes: penNodes, closed: closed), frame: .zero)
        s.frame = s.basePath.boundingBoxOfPath
        s.fill = closed ? .solid(fillColor) : .none
        s.stroke = strokeColor
        s.strokeWidth = closed ? strokeWidth : max(2, strokeWidth)
        penNodes = []
        add(s)
    }

    // MARK: files

    func importSVG(_ url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            let (imported, report) = try SVG.parse(Data(contentsOf: url))
            edit("Importa SVG") { d in
                var layer = imported.layers[0]
                layer.name = url.deletingPathExtension().lastPathComponent
                d.layers.append(layer)
            }
            activeLayer = doc.layers.count - 1
            if !report.skipped.isEmpty {
                error = "Importate \(report.shapes) forme. Elementi non supportati ignorati: " + report.skipped.map { "\($0.key) ×\($0.value)" }.joined(separator: ", ")
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    enum ExportKind: String, CaseIterable, Identifiable { case svg, png1, png2, png4, jpg, pdf
        var id: String { rawValue }
        var title: String {
            switch self {
            case .svg: "SVG"
            case .png1: "PNG 1×"
            case .png2: "PNG 2×"
            case .png4: "PNG 4× (alta risoluzione)"
            case .jpg: "JPEG 2×"
            case .pdf: "PDF vettoriale"
            }
        }
    }

    func export(_ k: ExportKind) {
        let name = project.header.name
        let (data, ext): (Data, String) = switch k {
        case .svg: (Data(SVG.export(doc).utf8), "svg")
        case .png1: (VectorRenderer.png(doc, scale: 1), "png")
        case .png2: (VectorRenderer.png(doc, scale: 2), "png")
        case .png4: (VectorRenderer.png(doc, scale: 4), "png")
        case .jpg: (VectorRenderer.jpeg(doc, scale: 2), "jpg")
        case .pdf: (VectorRenderer.pdf(doc), "pdf")
        }
        let url = StudioPaths.exportURL(name: name, ext: ext)
        do {
            try data.write(to: url)
            exported = ExportedFile(url)
        } catch {
            self.error = error.localizedDescription
        }
    }
}

extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}

public struct VectorEditorView: View {
    @State private var model: VectorEditorModel
    @State private var importRequest: ImportSource?
    @State private var dragStart: CGPoint?
    @State private var dragLast: CGPoint?
    @State private var nodeDrag: (UUID, Int, Int)? // shape, node, part (0 point, 1 in, 2 out)
    @State private var zoomBase: CGFloat?

    public init(project: ProjectController<VectorProject>) {
        _model = State(initialValue: VectorEditorModel(project: project))
    }

    public var body: some View {
        HStack(spacing: 0) {
            toolbox
            GeometryReader { geo in
                ScrollView([.horizontal, .vertical]) {
                    canvas
                        .frame(width: model.doc.width * model.zoom, height: model.doc.height * model.zoom)
                        .padding(60)
                        .frame(minWidth: geo.size.width, minHeight: geo.size.height)
                }
                .background(StudioTheme.canvas)
                .simultaneousGesture(MagnifyGesture().onChanged { v in
                    if zoomBase == nil { zoomBase = model.zoom }
                    model.zoom = min(8, max(0.05, (zoomBase ?? 1) * v.magnification))
                }.onEnded { _ in zoomBase = nil })
            }
            VectorInspector(model: model).studioPanel(width: 300)
        }
        .navigationTitle(model.project.header.name)
        .navigationBarTitleDisplayMode(.inline)
        .undoRedoToolbar(canUndo: model.project.canUndo, canRedo: model.project.canRedo, undo: { model.project.undo() }, redo: { model.project.redo() })
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                ImportMenu("Importa SVG", systemImage: "square.and.arrow.down", request: $importRequest, library: .none)
                Menu {
                    ForEach(VectorEditorModel.ExportKind.allCases) { k in Button(k.title) { model.export(k) } }
                } label: { Label("Esporta", systemImage: "square.and.arrow.up") }
            }
        }
        .mediaImporter($importRequest, types: [.svg], library: .none) { urls in
            if let url = urls.first { model.importSVG(url) }
        }
        .shareSheet($model.exported)
        .overlay(alignment: .top) { if let e = model.error { ErrorBanner(e) { model.error = nil } } }
        .onDisappear {
            model.project.save()
            let d = model.project.payload
            model.project.saveThumbnail(VectorRenderer.image(d, scale: min(1, 640 / max(d.width, d.height, 1)), opaque: true).cgImage)
        }
        .background(shortcuts)
    }

    private var shortcuts: some View {
        Group {
            Button("") { model.tool = .select }.keyboardShortcut("v", modifiers: [])
            Button("") { model.tool = .node }.keyboardShortcut("a", modifiers: [])
            Button("") { model.tool = .rect }.keyboardShortcut("m", modifiers: [])
            Button("") { model.tool = .ellipse }.keyboardShortcut("l", modifiers: [])
            Button("") { model.tool = .pen }.keyboardShortcut("p", modifiers: [])
            Button("") { model.tool = .text }.keyboardShortcut("t", modifiers: [])
            Button("") { model.deleteSelection() }.keyboardShortcut(.delete, modifiers: [])
            Button("") { model.duplicateSelection() }.keyboardShortcut("d", modifiers: .command)
            Button("") { model.group() }.keyboardShortcut("g", modifiers: .command)
            Button("") { model.ungroup() }.keyboardShortcut("g", modifiers: [.command, .shift])
            Button("") { model.finishPen(closed: false) }.keyboardShortcut(.return, modifiers: [])
            Button("") { model.penNodes = []; model.selection.removeAll() }.keyboardShortcut(.escape, modifiers: [])
        }
        .opacity(0)
    }

    private var toolbox: some View {
        VStack(spacing: 4) {
            ForEach(VectorTool.allCases) { t in
                ToolRailButton(t.title, systemImage: t.icon, isSelected: model.tool == t) {
                    model.tool = t
                    if t != .pen { model.finishPen(closed: false) }
                }
            }
            RailDivider()
            ColorPicker("Riempimento", selection: Binding(get: { Color(rgba: model.fillColor) }, set: { model.fillColor = RGBAColor($0) })).labelsHidden()
            ColorPicker("Contorno", selection: Binding(get: { Color(rgba: model.strokeColor) }, set: { model.strokeColor = RGBAColor($0) })).labelsHidden()
            Spacer()
            if model.tool == .pen, !model.penNodes.isEmpty {
                Button("Chiudi") { model.finishPen(closed: true) }.font(.caption)
                Button("Fine") { model.finishPen(closed: false) }.font(.caption)
            }
            Text("\(Int(model.zoom * 100))%").font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
        }
        .studioRail()
    }

    private var canvas: some View {
        Canvas { ctx, _ in
            ctx.scaleBy(x: model.zoom, y: model.zoom)
            ctx.withCGContext { cg in VectorRenderer.draw(model.doc, in: cg) }
            if let d = model.draft { ctx.withCGContext { VectorRenderer.draw(d, in: $0) } }
            let lw = 1 / model.zoom
            for s in model.selectedShapes {
                ctx.stroke(Path(s.path.boundingBoxOfPath.insetBy(dx: -2 * lw, dy: -2 * lw)), with: .color(.accentColor), style: StrokeStyle(lineWidth: lw, dash: [4 * lw]))
                if model.tool == .node { drawNodes(s, ctx: ctx, lw: lw) }
            }
            if !model.penNodes.isEmpty {
                let p = VectorShape.cgPath([model.penNodes], closed: false)
                ctx.stroke(Path(p), with: .color(.accentColor), lineWidth: 2 * lw)
                for n in model.penNodes {
                    ctx.fill(Path(ellipseIn: CGRect(x: n.point.x - 4 * lw, y: n.point.y - 4 * lw, width: 8 * lw, height: 8 * lw)), with: .color(.accentColor))
                }
            }
        }
        .shadow(radius: 6)
        .contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance: 0).onChanged(dragChanged).onEnded(dragEnded))
        .accessibilityLabel("Tavola da disegno")
    }

    private func drawNodes(_ s: VectorShape, ctx: GraphicsContext, lw: CGFloat) {
        let subs: [[BezierNode]] = switch s.kind {
        case .path(let n, _): [n]
        case .compound(let n): n
        default: []
        }
        for nodes in subs {
            for n in nodes {
                for h in [n.inHandle, n.outHandle] where h != n.point {
                    ctx.stroke(Path { $0.move(to: n.point); $0.addLine(to: h) }, with: .color(.orange), lineWidth: lw)
                    ctx.fill(Path(ellipseIn: CGRect(x: h.x - 3 * lw, y: h.y - 3 * lw, width: 6 * lw, height: 6 * lw)), with: .color(.orange))
                }
                ctx.fill(Path(CGRect(x: n.point.x - 4 * lw, y: n.point.y - 4 * lw, width: 8 * lw, height: 8 * lw)), with: .color(.white))
                ctx.stroke(Path(CGRect(x: n.point.x - 4 * lw, y: n.point.y - 4 * lw, width: 8 * lw, height: 8 * lw)), with: .color(.accentColor), lineWidth: lw)
            }
        }
    }

    private func docPoint(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x / model.zoom, y: p.y / model.zoom) }

    private func dragChanged(_ v: DragGesture.Value) {
        let p = docPoint(v.location), start = docPoint(v.startLocation)
        let first = dragStart == nil
        if first { dragStart = start; dragLast = start }
        defer { dragLast = p }
        switch model.tool {
        case .select:
            if first {
                let hit = model.hit(start)
                if let hit, model.selection.contains(hit.id) {} else { model.select(hit, extend: false) }
                model.project.beginGesture()
            } else if !model.selection.isEmpty, let last = dragLast {
                model.moveSelection(dx: p.x - last.x, dy: p.y - last.y)
            }
        case .node:
            if first {
                nodeDrag = findNode(start)
                if nodeDrag == nil { model.select(model.hit(start), extend: false) }
                model.project.beginGesture()
            } else if let (id, ni, part) = nodeDrag {
                moveNode(id, ni, part, to: p)
            }
        case .rect, .ellipse:
            let r = CGRect(x: min(start.x, p.x), y: min(start.y, p.y), width: abs(p.x - start.x), height: abs(p.y - start.y))
            var s = VectorShape(name: model.tool == .rect ? "Rettangolo" : "Ellisse", kind: model.tool == .rect ? .rect(cornerRadius: 0) : .ellipse, frame: r)
            s.fill = .solid(model.fillColor)
            s.stroke = model.strokeColor
            s.strokeWidth = model.strokeWidth
            model.draft = s
        case .pen:
            if first {
                model.penNodes.append(BezierNode(start))
            } else if !model.penNodes.isEmpty {
                // dragging pulls symmetric handles: a smooth node
                let i = model.penNodes.count - 1
                let a = model.penNodes[i].point
                model.penNodes[i].outHandle = p
                model.penNodes[i].inHandle = CGPoint(x: 2 * a.x - p.x, y: 2 * a.y - p.y)
            }
        case .text:
            break
        }
    }

    private func dragEnded(_ v: DragGesture.Value) {
        let p = docPoint(v.location), start = docPoint(v.startLocation)
        defer { dragStart = nil; dragLast = nil; nodeDrag = nil }
        switch model.tool {
        case .select, .node:
            model.project.endGesture()
        case .rect, .ellipse:
            if var d = model.draft, d.frame.width > 2, d.frame.height > 2 {
                d.id = UUID()
                model.add(d)
            }
            model.draft = nil
        case .pen:
            // tapping the first node closes the path
            if model.penNodes.count > 2, let f = model.penNodes.first, hypot(start.x - f.point.x, start.y - f.point.y) < 10 / model.zoom,
               hypot(p.x - start.x, p.y - start.y) < 3 {
                model.penNodes.removeLast()
                model.finishPen(closed: true)
            }
        case .text:
            let size = 64.0
            let str = "Testo"
            let sz = VectorRenderer.textSize(str, size: size, fontName: nil)
            var s = VectorShape(name: "Testo", kind: .text(str, fontSize: size, fontName: nil), frame: CGRect(origin: p, size: sz))
            s.fill = .solid(model.fillColor)
            model.add(s)
            model.tool = .select
        }
    }

    private func findNode(_ p: CGPoint) -> (UUID, Int, Int)? {
        let tol = 10 / model.zoom
        for s in model.selectedShapes {
            guard case .path(let nodes, _) = s.kind else { continue }
            for (i, n) in nodes.enumerated() {
                for (part, q) in [(1, n.inHandle), (2, n.outHandle), (0, n.point)] where hypot(q.x - p.x, q.y - p.y) < tol {
                    return (s.id, i, part)
                }
            }
        }
        return nil
    }

    private func moveNode(_ id: UUID, _ i: Int, _ part: Int, to p: CGPoint) {
        model.edit("Modifica nodo") { d in
            d.update(id) { s in
                guard case .path(var nodes, let closed) = s.kind, nodes.indices.contains(i) else { return }
                var n = nodes[i]
                switch part {
                case 0:
                    let dx = p.x - n.point.x, dy = p.y - n.point.y
                    n.point = p
                    n.inHandle = CGPoint(x: n.inHandle.x + dx, y: n.inHandle.y + dy)
                    n.outHandle = CGPoint(x: n.outHandle.x + dx, y: n.outHandle.y + dy)
                case 1: n.inHandle = p
                default: n.outHandle = p
                }
                nodes[i] = n
                s.kind = .path(nodes: nodes, closed: closed)
                s.frame = s.basePath.boundingBoxOfPath
            }
        }
    }
}

struct VectorInspector: View {
    @Bindable var model: VectorEditorModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                if let s = model.selectedShapes.first, model.selection.count == 1 { shapePanel(s) }
                else if model.selection.count > 1 { Text("\(model.selection.count) forme selezionate").font(.headline) }
                if !model.selection.isEmpty { arrangePanel }
                documentPanel
                layersPanel
            }
            .padding()
        }
        .background(StudioTheme.panel)
    }

    private func g(_ on: Bool) { on ? model.project.beginGesture() : model.project.endGesture() }

    private func upd(_ label: String, _ f: @escaping (inout VectorShape) -> Void) {
        guard let id = model.selection.first else { return }
        model.edit(label) { $0.update(id, f) }
    }

    private func shapePanel(_ s: VectorShape) -> some View {
        PanelSection(s.name) {
            let b = s.bounds
            HStack {
                num("X", b.minX) { v in upd("Posizione") { $0.offset(dx: v - b.minX, dy: 0) } }
                num("Y", b.minY) { v in upd("Posizione") { $0.offset(dx: 0, dy: v - b.minY) } }
            }
            HStack {
                num("L", b.width) { v in upd("Dimensione") { $0.resize(to: CGRect(x: b.minX, y: b.minY, width: max(1, v), height: b.height)) } }
                num("A", b.height) { v in upd("Dimensione") { $0.resize(to: CGRect(x: b.minX, y: b.minY, width: b.width, height: max(1, v))) } }
            }
            ValueSlider("Rotazione (°)", value: Binding(get: { s.rotation }, set: { v in upd("Rotazione") { $0.rotation = v } }), range: -180 ... 180, onEditing: g)
            ValueSlider("Opacità", value: Binding(get: { s.opacity }, set: { v in upd("Opacità") { $0.opacity = v } }), range: 0 ... 1, step: 0.01, defaultValue: 1,
                        format: { String(format: "%.2f", $0) }, onEditing: g)
            if case .rect(let r) = s.kind {
                ValueSlider("Raggio angoli", value: Binding(get: { r }, set: { v in upd("Angoli") { $0.kind = .rect(cornerRadius: v) } }), range: 0 ... 500, onEditing: g)
            }
            if case .text(let str, let size, let font) = s.kind {
                TextField("Testo", text: Binding(get: { str }, set: { v in
                    upd("Testo") { sh in
                        sh.kind = .text(v, fontSize: size, fontName: font)
                        sh.frame.size = VectorRenderer.textSize(v, size: size, fontName: font)
                    }
                }), axis: .vertical).textFieldStyle(.roundedBorder)
                ValueSlider("Corpo", value: Binding(get: { size }, set: { v in
                    upd("Corpo") { sh in
                        sh.kind = .text(str, fontSize: v, fontName: font)
                        sh.frame.size = VectorRenderer.textSize(str, size: v, fontName: font)
                    }
                }), range: 6 ... 400, defaultValue: 64, onEditing: g)
                Picker("Font", selection: Binding(get: { font ?? "" }, set: { v in
                    upd("Font") { sh in
                        sh.kind = .text(str, fontSize: size, fontName: v.isEmpty ? nil : v)
                        sh.frame.size = VectorRenderer.textSize(str, size: size, fontName: v.isEmpty ? nil : v)
                    }
                })) {
                    Text("Sistema").tag("")
                    ForEach(UIFont.familyNames.sorted(), id: \.self) { f in Text(f).tag(UIFont.fontNames(forFamilyName: f).first ?? f) }
                }
            }
            fillPanel(s)
            ColorPicker("Contorno", selection: Binding(get: { Color(rgba: s.stroke) }, set: { v in upd("Contorno") { $0.stroke = RGBAColor(v) } }))
            ValueSlider("Spessore contorno", value: Binding(get: { s.strokeWidth }, set: { v in upd("Contorno") { $0.strokeWidth = v } }), range: 0 ... 50, step: 0.5,
                        format: { String(format: "%.1f", $0) }, onEditing: g)
        }
    }

    private func fillPanel(_ s: VectorShape) -> some View {
        VStack(alignment: .leading) {
            Picker("Riempimento", selection: Binding(get: { fillKind(s.fill) }, set: { k in
                let c = s.fill.solidColor ?? model.fillColor
                upd("Riempimento") { sh in
                    switch k {
                    case 0: sh.fill = .none
                    case 1: sh.fill = .solid(c)
                    case 2: sh.fill = .linear([GradientStop(location: 0, color: c), GradientStop(location: 1, color: .white)], angle: 0)
                    default: sh.fill = .radial([GradientStop(location: 0, color: .white), GradientStop(location: 1, color: c)])
                    }
                }
            })) {
                Text("Nessuno").tag(0); Text("Tinta").tag(1); Text("Lineare").tag(2); Text("Radiale").tag(3)
            }
            .pickerStyle(.segmented)
            switch s.fill {
            case .solid(let c):
                ColorPicker("Colore", selection: Binding(get: { Color(rgba: c) }, set: { v in upd("Colore") { $0.fill = .solid(RGBAColor(v)) } }))
            case .linear(let stops, let angle):
                gradientStops(stops) { new in upd("Gradiente") { $0.fill = .linear(new, angle: angle) } }
                ValueSlider("Angolo", value: Binding(get: { angle }, set: { v in upd("Gradiente") { $0.fill = .linear(stops, angle: v) } }), range: -180 ... 180, onEditing: g)
            case .radial(let stops):
                gradientStops(stops) { new in upd("Gradiente") { $0.fill = .radial(new) } }
            case .none: EmptyView()
            }
        }
    }

    private func gradientStops(_ stops: [GradientStop], set: @escaping ([GradientStop]) -> Void) -> some View {
        ForEach(Array(stops.enumerated()), id: \.offset) { i, st in
            ColorPicker("Colore \(i + 1)", selection: Binding(get: { Color(rgba: st.color) }, set: { v in
                var s = stops
                s[i].color = RGBAColor(v)
                set(s)
            }))
        }
    }

    private func fillKind(_ p: Paint) -> Int {
        switch p {
        case .none: 0
        case .solid: 1
        case .linear: 2
        case .radial: 3
        }
    }

    private var arrangePanel: some View {
        PanelSection("Disponi") {
            HStack {
                ForEach(VectorOps.Alignment.allCases, id: \.self) { a in
                    Button { model.align(a) } label: { Image(systemName: icon(a)) }.buttonStyle(.bordered)
                }
            }
            HStack {
                ForEach(BooleanOp.allCases, id: \.self) { op in Button(op.title) { model.boolean(op) }.font(.caption).buttonStyle(.bordered) }
            }
            .disabled(model.selection.count < 2)
            HStack {
                Button("Primo piano") { model.arrange(front: true) }
                Button("In fondo") { model.arrange(front: false) }
            }
            .font(.caption).buttonStyle(.bordered)
            HStack {
                Button("Raggruppa") { model.group() }
                Button("Separa") { model.ungroup() }
                Button("Duplica") { model.duplicateSelection() }
                Button("Elimina", role: .destructive) { model.deleteSelection() }
            }
            .font(.caption).buttonStyle(.bordered)
        }
    }

    private func icon(_ a: VectorOps.Alignment) -> String {
        switch a {
        case .left: "align.horizontal.left"
        case .centerX: "align.horizontal.center"
        case .right: "align.horizontal.right"
        case .top: "align.vertical.top"
        case .centerY: "align.vertical.center"
        case .bottom: "align.vertical.bottom"
        }
    }

    private var documentPanel: some View {
        PanelSection("Documento", expanded: model.selection.isEmpty) {
            HStack {
                num("Larghezza", model.doc.width) { v in model.edit("Tavola") { $0.width = max(16, v) } }
                num("Altezza", model.doc.height) { v in model.edit("Tavola") { $0.height = max(16, v) } }
            }
            ColorPicker("Sfondo", selection: Binding(get: { Color(rgba: model.doc.background) }, set: { v in model.edit("Sfondo") { $0.background = RGBAColor(v) } }))
            ValueSlider("Spessore contorno nuove forme", value: $model.strokeWidth, range: 0 ... 30)
        }
    }

    private var layersPanel: some View {
        PanelSection("Livelli") {
            ForEach(Array(model.doc.layers.enumerated()).reversed(), id: \.element.id) { i, l in
                HStack {
                    Button { model.edit("Visibilità") { $0.layers[i].visible.toggle() } } label: { Image(systemName: l.visible ? "eye" : "eye.slash") }
                    Button { model.edit("Blocco") { $0.layers[i].locked.toggle() } } label: { Image(systemName: l.locked ? "lock" : "lock.open") }
                    Text(l.name).font(.callout).fontWeight(model.activeLayer == i ? .bold : .regular)
                    Spacer()
                    Text("\(l.shapes.count)").font(.caption2).foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .contentShape(Rectangle())
                .onTapGesture { model.activeLayer = i }
            }
            HStack {
                Button("Nuovo livello") {
                    model.edit("Nuovo livello") { $0.layers.append(VectorLayer(name: "Livello \($0.layers.count + 1)")) }
                    model.activeLayer = model.doc.layers.count - 1
                }
                Button("Elimina livello", role: .destructive) {
                    let i = model.activeLayer
                    guard model.doc.layers.count > 1 else { return }
                    model.edit("Elimina livello") { $0.layers.remove(at: i) }
                    model.activeLayer = max(0, i - 1)
                }
            }
            .font(.caption).buttonStyle(.bordered)
        }
    }

    private func num(_ label: String, _ v: Double, set: @escaping (Double) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption2).foregroundStyle(.secondary)
            TextField(label, value: Binding(get: { (v * 10).rounded() / 10 }, set: set), format: .number)
                .textFieldStyle(.roundedBorder).keyboardType(.decimalPad)
        }
    }
}
