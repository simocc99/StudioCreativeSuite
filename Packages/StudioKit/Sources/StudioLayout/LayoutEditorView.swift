import StudioCore
import SwiftUI
import UniformTypeIdentifiers

@MainActor
@Observable
final class LayoutEditorModel {
    let project: ProjectController<LayoutProject>
    var page = 0
    var selected: UUID?
    var zoom: CGFloat = 1
    var error: String?
    var exported: ExportedFile?

    init(project: ProjectController<LayoutProject>) { self.project = project }
    var doc: LayoutProject { project.payload }

    var frame: LayoutFrame? { doc.pages[safe: page]?.frames.first { $0.id == selected } }

    func edit(_ label: String, _ f: (inout LayoutProject) -> Void) { project.mutate(label, f) }

    func updateFrame(_ label: String, _ f: (inout LayoutFrame) -> Void) {
        guard let id = selected else { return }
        let p = page
        edit(label) { d in if let i = d.pages[p].frames.firstIndex(where: { $0.id == id }) { f(&d.pages[p].frames[i]) } }
    }

    func addTextFrame() {
        let cols = doc.columnRects(page: page)
        let r = cols.first.map { CGRect(x: $0.minX, y: $0.minY, width: doc.contentRect(page: page).width, height: $0.height / 2) } ?? CGRect(x: 50, y: 50, width: 300, height: 200)
        var f = LayoutFrame(rect: r, content: .text("Scrivi qui il testo. Le cornici di testo supportano più colonne, stili di paragrafo e sillabazione.", style: doc.styles.first { $0.name == "Corpo" }?.id))
        f.columns = doc.columns
        f.gutter = doc.gutter
        let p = page
        edit("Cornice di testo") { $0.pages[p].frames.append(f) }
        selected = f.id
    }

    func addImage(_ url: URL) {
        do {
            let rel = try project.importMedia(url)
            let c = doc.contentRect(page: page)
            let f = LayoutFrame(rect: CGRect(x: c.minX, y: c.minY, width: c.width, height: c.height / 3), content: .image(rel, fill: true))
            let p = page
            edit("Immagine") { $0.pages[p].frames.append(f) }
            selected = f.id
        } catch {
            self.error = error.localizedDescription
        }
    }

    func addRectangle() {
        let c = doc.contentRect(page: page)
        let f = LayoutFrame(rect: CGRect(x: c.minX, y: c.minY, width: c.width, height: 40), content: .rectangle(RGBAColor(0.9, 0.3, 0.25)))
        let p = page
        edit("Rettangolo") { $0.pages[p].frames.append(f) }
        selected = f.id
    }

    func addPage(after i: Int) {
        edit("Nuova pagina") { $0.pages.insert(LayoutPage(), at: min(i + 1, $0.pages.count)) }
        page = min(i + 1, doc.pages.count - 1)
    }

    func deletePage() {
        guard doc.pages.count > 1 else { return }
        let p = page
        edit("Elimina pagina") { $0.pages.remove(at: p) }
        page = max(0, p - 1)
    }

    func deleteFrame() {
        guard let id = selected else { return }
        let p = page
        edit("Elimina cornice") { $0.pages[p].frames.removeAll { $0.id == id } }
        selected = nil
    }

    func exportPDF() {
        let data = LayoutRenderer.pdf(doc, projectURL: project.url)
        let url = StudioPaths.exportURL(name: project.header.name, ext: "pdf")
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

public struct LayoutEditorView: View {
    @State private var model: LayoutEditorModel
    @State private var importing = false
    @State private var dragStart: CGRect?

    public init(project: ProjectController<LayoutProject>) {
        _model = State(initialValue: LayoutEditorModel(project: project))
    }

    public var body: some View {
        HStack(spacing: 0) {
            pageStrip.studioPanel(width: 150, edge: .trailing)
            GeometryReader { geo in
                ScrollView([.horizontal, .vertical]) {
                    pageView(fit: min(geo.size.width / model.doc.size.width, geo.size.height / model.doc.size.height) * 0.92)
                        .padding(30)
                        .frame(minWidth: geo.size.width, minHeight: geo.size.height)
                }
                .background(StudioTheme.canvas)
            }
            inspector.studioPanel(width: 300)
        }
        .navigationTitle(model.project.header.name)
        .navigationBarTitleDisplayMode(.inline)
        .undoRedoToolbar(canUndo: model.project.canUndo, canRedo: model.project.canRedo, undo: { model.project.undo() }, redo: { model.project.redo() })
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button { model.addTextFrame() } label: { Label("Testo", systemImage: "text.alignleft") }
                Button { importing = true } label: { Label("Immagine", systemImage: "photo") }
                Button { model.addRectangle() } label: { Label("Forma", systemImage: "rectangle.fill") }
                Button { model.exportPDF() } label: { Label("Esporta PDF", systemImage: "square.and.arrow.up") }
            }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.image]) { r in
            if case .success(let url) = r { model.addImage(url) }
        }
        .shareSheet($model.exported)
        .overlay(alignment: .top) { if let e = model.error { ErrorBanner(e) { model.error = nil } } }
        .onDisappear { model.project.save() }
    }

    private func pageView(fit: CGFloat) -> some View {
        let s = fit * model.zoom
        let d = model.doc
        return ZStack(alignment: .topLeading) {
            Canvas { ctx, _ in
                ctx.scaleBy(x: s, y: s)
                ctx.withCGContext { LayoutRenderer.draw(d, page: model.page, in: $0, projectURL: model.project.url, guides: d.showGuides) }
            }
            .frame(width: d.size.width * s, height: d.size.height * s)
            .shadow(radius: 8)
            .onTapGesture { model.selected = nil }
            ForEach(d.pages[safe: model.page]?.frames ?? []) { f in
                let sel = model.selected == f.id
                Rectangle().fill(Color.clear).contentShape(Rectangle())
                    .frame(width: f.rect.width * s, height: f.rect.height * s)
                    .overlay(Rectangle().stroke(sel ? Color.accentColor : Color.clear, lineWidth: 2))
                    .overlay(alignment: .bottomTrailing) {
                        if sel {
                            Circle().fill(Color.accentColor).frame(width: 18, height: 18)
                                .gesture(DragGesture().onChanged { v in
                                    if dragStart == nil { dragStart = f.rect; model.project.beginGesture() }
                                    let r = dragStart!
                                    model.updateFrame("Ridimensiona") { $0.rect.size = CGSize(width: max(10, r.width + v.translation.width / s), height: max(10, r.height + v.translation.height / s)) }
                                }.onEnded { _ in dragStart = nil; model.project.endGesture() })
                                .offset(x: 9, y: 9)
                        }
                    }
                    .offset(x: f.rect.minX * s, y: f.rect.minY * s)
                    .onTapGesture { model.selected = f.id }
                    .gesture(DragGesture(minimumDistance: 4).onChanged { v in
                        model.selected = f.id
                        if dragStart == nil { dragStart = f.rect; model.project.beginGesture() }
                        let r = dragStart!
                        // snap the frame's left edge to the nearest column
                        var x = r.minX + v.translation.width / s
                        for c in d.columnRects(page: model.page) where abs(c.minX - x) < 6 { x = c.minX }
                        model.updateFrame("Sposta") { $0.rect.origin = CGPoint(x: x, y: r.minY + v.translation.height / s) }
                    }.onEnded { _ in dragStart = nil; model.project.endGesture() })
            }
        }
        .frame(width: d.size.width * s, height: d.size.height * s, alignment: .topLeading)
    }

    private var pageStrip: some View {
        ScrollView {
            VStack(spacing: 12) {
                ForEach(Array(model.doc.pages.enumerated()), id: \.element.id) { i, _ in
                    let s = 110 / model.doc.size.width
                    Canvas { ctx, _ in
                        ctx.scaleBy(x: s, y: s)
                        ctx.withCGContext { LayoutRenderer.draw(model.doc, page: i, in: $0, projectURL: model.project.url, guides: false) }
                    }
                    .frame(width: 110, height: model.doc.size.height * s)
                    .overlay(Rectangle().stroke(model.page == i ? Color.accentColor : Color.gray.opacity(0.4), lineWidth: model.page == i ? 3 : 1))
                    .overlay(alignment: .bottom) { Text("\(i + 1)").font(.caption2).padding(2) }
                    .onTapGesture { model.page = i; model.selected = nil }
                }
                Button { model.addPage(after: model.page) } label: { Label("Pagina", systemImage: "plus") }.buttonStyle(.bordered)
                Button(role: .destructive) { model.deletePage() } label: { Label("Elimina", systemImage: "trash") }.buttonStyle(.bordered).disabled(model.doc.pages.count < 2)
            }
            .padding()
        }
        .background(StudioTheme.panel)
    }

    private var inspector: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                if let f = model.frame { framePanel(f) }
                documentPanel
                stylesPanel
            }
            .padding()
        }
        .background(StudioTheme.panel)
    }

    private func framePanel(_ f: LayoutFrame) -> some View {
        PanelSection("Cornice") {
            switch f.content {
            case .text(let s, let style):
                TextEditor(text: Binding(get: { s }, set: { v in model.updateFrame("Testo") { $0.content = .text(v, style: style) } }))
                    .frame(minHeight: 160).border(Color.secondary.opacity(0.3))
                Picker("Stile", selection: Binding(get: { style ?? model.doc.styles.first!.id }, set: { v in model.updateFrame("Stile") { $0.content = .text(s, style: v) } })) {
                    ForEach(model.doc.styles) { Text($0.name).tag($0.id) }
                }
                Stepper("Colonne: \(f.columns)", value: Binding(get: { f.columns }, set: { v in model.updateFrame("Colonne") { $0.columns = max(1, min(6, v)) } }), in: 1 ... 6)
            case .image(let p, let fill):
                Toggle("Riempi la cornice", isOn: Binding(get: { fill }, set: { v in model.updateFrame("Adatta") { $0.content = .image(p, fill: v) } }))
            case .rectangle(let c):
                ColorPicker("Colore", selection: Binding(get: { Color(rgba: c) }, set: { v in model.updateFrame("Colore") { $0.content = .rectangle(RGBAColor(v)) } }))
            }
            ValueSlider("Bordo (pt)", value: Binding(get: { f.stroke }, set: { v in model.updateFrame("Bordo") { $0.stroke = v } }), range: 0 ... 8, step: 0.25,
                        format: { String(format: "%.2f", $0) })
            Text(String(format: "x %.0f  y %.0f  ·  %.0f × %.0f pt", f.rect.minX, f.rect.minY, f.rect.width, f.rect.height)).font(.caption.monospacedDigit())
            Button("Elimina cornice", role: .destructive) { model.deleteFrame() }
        }
    }

    private var documentPanel: some View {
        PanelSection("Documento", expanded: model.selected == nil) {
            Picker("Formato", selection: Binding(get: { model.doc.size.name }, set: { n in
                if let s = PageSize.all.first(where: { $0.name == n }) { model.edit("Formato") { $0.size = s } }
            })) { ForEach(PageSize.all, id: \.name) { Text($0.name).tag($0.name) } }
            ValueSlider("Margine superiore", value: Binding(get: { model.doc.marginTop }, set: { v in model.edit("Margini") { $0.marginTop = v } }), range: 0 ... 150)
            ValueSlider("Margine inferiore", value: Binding(get: { model.doc.marginBottom }, set: { v in model.edit("Margini") { $0.marginBottom = v } }), range: 0 ... 150)
            ValueSlider("Margine interno", value: Binding(get: { model.doc.marginInside }, set: { v in model.edit("Margini") { $0.marginInside = v } }), range: 0 ... 150)
            ValueSlider("Margine esterno", value: Binding(get: { model.doc.marginOutside }, set: { v in model.edit("Margini") { $0.marginOutside = v } }), range: 0 ... 150)
            Stepper("Colonne griglia: \(model.doc.columns)", value: Binding(get: { model.doc.columns }, set: { v in model.edit("Griglia") { $0.columns = max(1, min(12, v)) } }), in: 1 ... 12)
            ValueSlider("Spazio colonne", value: Binding(get: { model.doc.gutter }, set: { v in model.edit("Griglia") { $0.gutter = v } }), range: 0 ... 60)
            Toggle("Mostra guide", isOn: Binding(get: { model.doc.showGuides }, set: { v in model.edit("Guide") { $0.showGuides = v } }))
            Toggle("Numeri di pagina", isOn: Binding(get: { model.doc.pageNumbers }, set: { v in model.edit("Numeri") { $0.pageNumbers = v } }))
            ValueSlider("Zoom", value: Binding(get: { Double(model.zoom) }, set: { model.zoom = CGFloat($0) }), range: 0.5 ... 4, step: 0.05, defaultValue: 1,
                        format: { String(format: "%.0f%%", $0 * 100) })
        }
    }

    private var stylesPanel: some View {
        PanelSection("Stili di paragrafo", expanded: false) {
            ForEach(Array(model.doc.styles.enumerated()), id: \.element.id) { i, st in
                VStack(alignment: .leading) {
                    Text(st.name).font(.subheadline.weight(.semibold))
                    ValueSlider("Corpo (pt)", value: Binding(get: { st.size }, set: { v in model.edit("Stile") { $0.styles[i].size = v } }), range: 5 ... 96, step: 0.5,
                                format: { String(format: "%.1f", $0) })
                    ValueSlider("Interlinea", value: Binding(get: { st.leading }, set: { v in model.edit("Stile") { $0.styles[i].leading = v } }), range: 0.8 ... 2.5, step: 0.05,
                                defaultValue: 1.25, format: { String(format: "%.2f", $0) })
                    Picker("Allineamento", selection: Binding(get: { st.alignment }, set: { v in model.edit("Stile") { $0.styles[i].alignment = v } })) {
                        Text("Sx").tag(0); Text("Centro").tag(1); Text("Dx").tag(2); Text("Giust.").tag(3)
                    }
                    .pickerStyle(.segmented)
                    Toggle("Grassetto", isOn: Binding(get: { st.weightBold }, set: { v in model.edit("Stile") { $0.styles[i].weightBold = v } }))
                    ColorPicker("Colore", selection: Binding(get: { Color(rgba: st.color) }, set: { v in model.edit("Stile") { $0.styles[i].color = RGBAColor(v) } }))
                }
                Divider()
            }
            Text("I font usati sono quelli installati su iPadOS; vengono incorporati nel PDF secondo le loro licenze.").font(.caption2).foregroundStyle(.secondary)
        }
    }
}
