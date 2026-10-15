import PDFKit
import StudioCore
import SwiftUI
import UniformTypeIdentifiers

/// The PDF library: copies of imported PDFs in Documents/PDF (originals stay untouched).
public enum PDFLibrary {
    public static var folder: URL {
        let u = StudioPaths.documents.appendingPathComponent("PDF", isDirectory: true)
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }

    public static func list() -> [URL] {
        ((try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.contentModificationDateKey])) ?? [])
            .filter { $0.pathExtension.lowercased() == "pdf" }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }

    public static func importCopy(_ src: URL) throws -> URL {
        let scoped = src.startAccessingSecurityScopedResource()
        defer { if scoped { src.stopAccessingSecurityScopedResource() } }
        var dest = folder.appendingPathComponent(src.lastPathComponent)
        var n = 2
        while FileManager.default.fileExists(atPath: dest.path) {
            dest = folder.appendingPathComponent("\(src.deletingPathExtension().lastPathComponent) \(n).pdf")
            n += 1
        }
        try FileManager.default.copyItem(at: src, to: dest)
        _ = try PDFOperations.open(dest)
        return dest
    }
}

public enum PDFMode: String, CaseIterable {
    case read, highlight, note, ink
    var title: String {
        switch self {
        case .read: "Lettura"
        case .highlight: "Evidenzia"
        case .note: "Nota"
        case .ink: "Disegno"
        }
    }
    var icon: String {
        switch self {
        case .read: "hand.point.up.left"
        case .highlight: "highlighter"
        case .note: "note.text"
        case .ink: "pencil.tip"
        }
    }
}

@MainActor
@Observable
final class PDFEditorModel {
    let url: URL
    let document: PDFDocument
    var mode: PDFMode = .read
    var query = ""
    var results: [PDFSelection] = []
    var revision = 0
    var dirty = false
    var error: String?
    var exported: ExportedFile?
    var inkColor = Color.red
    var currentPage = 0
    weak var pdfView: PDFView?

    init(url: URL) throws {
        self.url = url
        document = try PDFOperations.open(url)
    }

    func changed() {
        dirty = true
        revision += 1
    }

    func search() {
        results = PDFOperations.search(document, query)
        if let f = results.first { pdfView?.go(to: f); pdfView?.setCurrentSelection(f, animate: true) }
    }

    func highlightSelection() {
        guard let sel = pdfView?.currentSelection, !(sel.string ?? "").isEmpty else {
            error = "Seleziona prima del testo con il dito o la Pencil, poi tocca Evidenzia."
            return
        }
        PDFOperations.highlight(sel)
        pdfView?.clearSelection()
        changed()
    }

    func move(from: IndexSet, to: Int) {
        guard let f = from.first else { return }
        PDFOperations.movePage(document, from: f, to: f < to ? to - 1 : to)
        changed()
    }

    func merge(_ other: URL) {
        let scoped = other.startAccessingSecurityScopedResource()
        defer { if scoped { other.stopAccessingSecurityScopedResource() } }
        do {
            PDFOperations.merge(document, with: try PDFOperations.open(other))
            changed()
        } catch {
            self.error = error.localizedDescription
        }
    }

    func save() {
        guard document.write(to: url) else { error = "Salvataggio non riuscito"; return }
        dirty = false
    }

    func exportCopy() {
        let dest = StudioPaths.exportURL(name: url.deletingPathExtension().lastPathComponent, ext: "pdf")
        if document.write(to: dest) { exported = ExportedFile(dest) } else { error = "Esportazione non riuscita" }
    }
}

public struct PDFEditorView: View {
    @State private var model: PDFEditorModel
    @State private var merging = false
    @State private var noteText = ""

    public init(url: URL) throws {
        _model = State(initialValue: try PDFEditorModel(url: url))
    }

    public var body: some View {
        HStack(spacing: 0) {
            pages.studioPanel(width: 170, edge: .trailing)
            VStack(spacing: 0) {
                modeBar.studioBar(edge: .bottom)
                PDFKitView(model: model)
            }
            searchPanel.studioPanel(width: 260)
        }
        .navigationTitle(model.url.deletingPathExtension().lastPathComponent + (model.dirty ? " •" : ""))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button { merging = true } label: { Label("Unisci PDF", systemImage: "doc.on.doc") }
                Button { model.save() } label: { Label("Salva", systemImage: "square.and.arrow.down") }
                    .keyboardShortcut("s", modifiers: .command).disabled(!model.dirty)
                Button { model.exportCopy() } label: { Label("Esporta copia", systemImage: "square.and.arrow.up") }
            }
        }
        .fileImporter(isPresented: $merging, allowedContentTypes: [.pdf]) { r in
            if case .success(let u) = r { model.merge(u) }
        }
        .shareSheet($model.exported)
        .overlay(alignment: .top) { if let e = model.error { ErrorBanner(e) { model.error = nil } } }
    }

    private var modeBar: some View {
        HStack {
            Picker("Modalità", selection: $model.mode) {
                ForEach(PDFMode.allCases, id: \.self) { Label($0.title, systemImage: $0.icon).tag($0) }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 460)
            if model.mode == .highlight { Button("Evidenzia selezione") { model.highlightSelection() }.buttonStyle(.borderedProminent) }
            if model.mode == .ink { ColorPicker("Colore", selection: $model.inkColor).labelsHidden() }
            if model.mode == .note { TextField("Testo della nota", text: $noteText).textFieldStyle(.roundedBorder).frame(width: 200) }
            Spacer()
            Text("Le annotazioni si aggiungono sopra le pagine: il contenuto originale non viene modificato.")
                .font(.caption2).foregroundStyle(.secondary).lineLimit(2).frame(maxWidth: 260)
        }
        .padding(8)
        .onChange(of: noteText) { _, v in PDFKitView.pendingNote = v }
    }

    private var pages: some View {
        List {
            ForEach(0 ..< model.document.pageCount, id: \.self) { i in
                VStack(spacing: 4) {
                    if let p = model.document.page(at: i) {
                        Image(uiImage: p.thumbnail(of: CGSize(width: 120, height: 160), for: .mediaBox))
                            .resizable().aspectRatio(contentMode: .fit).frame(height: 150)
                            .overlay(Rectangle().stroke(model.currentPage == i ? Color.accentColor : .clear, lineWidth: 2))
                    }
                    HStack {
                        Text("\(i + 1)").font(.caption2)
                        Spacer()
                        Button { PDFOperations.rotate(model.document, page: i, by: 90); model.changed() } label: { Image(systemName: "rotate.right") }
                        Button { PDFOperations.delete(model.document, page: i); model.changed() } label: { Image(systemName: "trash") }
                            .disabled(model.document.pageCount < 2)
                    }
                    .buttonStyle(.plain).font(.caption)
                }
                .contentShape(Rectangle())
                .onTapGesture { if let p = model.document.page(at: i) { model.pdfView?.go(to: p) } }
            }
            .onMove { model.move(from: $0, to: $1) }
            Button { PDFOperations.insertBlankPage(model.document, at: model.currentPage + 1); model.changed() } label: {
                Label("Pagina vuota", systemImage: "plus")
            }
        }
        .listStyle(.plain)
        .id(model.revision)
    }

    private var searchPanel: some View {
        VStack(alignment: .leading) {
            TextField("Cerca nel documento", text: $model.query).textFieldStyle(.roundedBorder).onSubmit { model.search() }
            Text(model.query.isEmpty ? "" : "\(model.results.count) risultati").font(.caption).foregroundStyle(.secondary)
            List(Array(model.results.enumerated()), id: \.offset) { _, r in
                Button {
                    model.pdfView?.go(to: r)
                    model.pdfView?.setCurrentSelection(r, animate: true)
                } label: {
                    VStack(alignment: .leading) {
                        Text("Pagina \((r.pages.first.map { model.document.index(for: $0) } ?? 0) + 1)").font(.caption2).foregroundStyle(.secondary)
                        Text(context(r)).font(.caption).lineLimit(2)
                    }
                }
            }
            .listStyle(.plain)
            Text("Annotazioni: \(PDFOperations.annotationCount(model.document))").font(.caption2).foregroundStyle(.secondary).id(model.revision)
        }
        .padding()
        .background(StudioTheme.panel)
    }

    private func context(_ s: PDFSelection) -> String {
        guard let e = s.copy() as? PDFSelection else { return s.string ?? "" }
        e.extend(atStart: 30)
        e.extend(atEnd: 30)
        return (e.string ?? "").replacingOccurrences(of: "\n", with: " ")
    }
}

/// PDFView plus a transparent overlay that turns touches into notes / ink when those modes are on.
struct PDFKitView: UIViewRepresentable {
    let model: PDFEditorModel
    nonisolated(unsafe) static var pendingNote = ""

    func makeUIView(context: Context) -> Container {
        let c = Container()
        c.pdf.document = model.document
        c.pdf.autoScales = true
        c.pdf.displayMode = .singlePageContinuous
        c.pdf.usePageViewController(false)
        c.model = model
        model.pdfView = c.pdf
        NotificationCenter.default.addObserver(forName: .PDFViewPageChanged, object: c.pdf, queue: .main) { [weak c] _ in
            MainActor.assumeIsolated {
                guard let c, let p = c.pdf.currentPage else { return }
                model.currentPage = model.document.index(for: p)
            }
        }
        return c
    }

    func updateUIView(_ c: Container, context: Context) {
        c.overlay.isUserInteractionEnabled = model.mode == .note || model.mode == .ink
        _ = model.revision
        c.pdf.layoutDocumentView()
    }

    final class Container: UIView {
        let pdf = PDFView()
        let overlay = InkOverlay()
        weak var model: PDFEditorModel?

        override init(frame: CGRect) {
            super.init(frame: frame)
            addSubview(pdf)
            addSubview(overlay)
            overlay.container = self
        }
        required init?(coder: NSCoder) { fatalError() }
        override func layoutSubviews() {
            pdf.frame = bounds
            overlay.frame = bounds
        }
    }

    final class InkOverlay: UIView {
        weak var container: Container?
        private var points: [CGPoint] = []
        private var page: PDFPage?
        private let shape = CAShapeLayer()

        override init(frame: CGRect) {
            super.init(frame: frame)
            backgroundColor = .clear
            shape.fillColor = nil
            shape.lineWidth = 3
            shape.lineCap = .round
            layer.addSublayer(shape)
        }
        required init?(coder: NSCoder) { fatalError() }

        override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
            guard let c = container, let m = c.model, let t = touches.first else { return }
            let p = t.location(in: c.pdf)
            guard let pg = c.pdf.page(for: p, nearest: true) else { return }
            if m.mode == .note {
                let text = PDFKitView.pendingNote.isEmpty ? "Nota" : PDFKitView.pendingNote
                PDFOperations.addNote(pg, at: c.pdf.convert(p, to: pg), text: text)
                m.changed()
                return
            }
            page = pg
            points = [p]
            shape.strokeColor = UIColor(m.inkColor).cgColor
        }

        override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
            guard page != nil, let c = container, let t = touches.first else { return }
            for ct in event?.coalescedTouches(for: t) ?? [t] { points.append(ct.location(in: c.pdf)) }
            let path = UIBezierPath()
            path.move(to: points[0])
            for p in points.dropFirst() { path.addLine(to: p) }
            shape.path = path.cgPath
        }

        override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
            defer { points = []; page = nil; shape.path = nil }
            guard let pg = page, let c = container, let m = c.model else { return }
            let pts = points.map { c.pdf.convert($0, to: pg) }
            PDFOperations.addInk(pg, points: pts, color: UIColor(m.inkColor), width: 2 / max(c.pdf.scaleFactor, 0.1) * 1.5)
            m.changed()
        }
    }
}

/// List of PDFs in the library with import.
public struct PDFLibraryView: View {
    @State private var files = PDFLibrary.list()
    @State private var importing = false
    @State private var error: String?

    public init() {}

    public var body: some View {
        List {
            ForEach(files, id: \.self) { u in
                NavigationLink {
                    PDFEditorHost(url: u)
                } label: {
                    Label(u.deletingPathExtension().lastPathComponent, systemImage: "doc.richtext")
                }
            }
        }
        .overlay {
            if files.isEmpty {
                ContentUnavailableView("Nessun PDF", systemImage: "doc.text.magnifyingglass",
                                       description: Text("Importa un PDF: ne verrà creata una copia nella libreria dell'app."))
            }
        }
        .navigationTitle("PDF")
        .toolbar {
            Button { importing = true } label: { Label("Importa PDF", systemImage: "plus") }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.pdf], allowsMultipleSelection: true) { r in
            if case .success(let urls) = r {
                for u in urls {
                    do { _ = try PDFLibrary.importCopy(u) } catch { self.error = error.localizedDescription }
                }
                files = PDFLibrary.list()
            }
        }
        .overlay(alignment: .top) { if let e = error { ErrorBanner(e) { error = nil } } }
        .onAppear { files = PDFLibrary.list() }
    }
}

public struct PDFEditorHost: View {
    let url: URL
    public init(url: URL) { self.url = url }
    public var body: some View {
        if let v = try? PDFEditorView(url: url) { v } else {
            ContentUnavailableView("PDF non leggibile", systemImage: "exclamationmark.triangle", description: Text(url.lastPathComponent))
        }
    }
}
