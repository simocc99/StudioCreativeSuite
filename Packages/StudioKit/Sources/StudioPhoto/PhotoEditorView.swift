import StudioCore
import SwiftUI
import UniformTypeIdentifiers

public struct PhotoEditorView: View {
    @State private var model: PhotoEditorModel
    @State private var importing = false
    @State private var showExport = false
    @State private var zoom: CGFloat = 1
    @State private var zoomBase: CGFloat = 1
    @State private var pan: CGSize = .zero
    @State private var panBase: CGSize = .zero
    @Environment(\.displayScale) private var displayScale

    public init(project: ProjectController<PhotoProject>) {
        _model = State(initialValue: PhotoEditorModel(project: project))
    }

    public var body: some View {
        HStack(spacing: 0) {
            canvas
            if model.engine != nil { inspector.studioPanel(width: 340) }
        }
        .navigationTitle(model.project.header.name)
        .navigationBarTitleDisplayMode(.inline)
        .undoRedoToolbar(canUndo: model.project.canUndo, canRedo: model.project.canRedo, undo: model.undo, redo: model.redo)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button { importing = true } label: { Label("Importa foto", systemImage: "square.and.arrow.down") }
                if model.engine != nil {
                    Toggle(isOn: $model.showBefore) { Label("Prima/dopo", systemImage: "rectangle.split.2x1") }
                        .keyboardShortcut("\\", modifiers: [])
                    Button { showExport = true } label: { Label("Esporta", systemImage: "square.and.arrow.up") }
                        .keyboardShortcut("e", modifiers: [.command, .shift])
                }
            }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: Self.importTypes) { r in
            if case .success(let url) = r { Task { await model.importSource(url) } }
        }
        .sheet(isPresented: $showExport) { PhotoExportSheet(model: model) }
        .shareSheet($model.exported)
        .overlay(alignment: .top) {
            if let e = model.error { ErrorBanner(e) { model.error = nil } }
        }
        .overlay {
            if model.isOpening { ProgressOverlay("Decodifica dell'originale…") }
            if let p = model.exportProgress { ProgressOverlay(p) }
        }
        .task { await model.load() }
        .onDisappear {
            model.project.save()
            model.project.saveThumbnail(model.image)
        }
    }

    static var importTypes: [UTType] {
        var t: [UTType] = [.rawImage, .image]
        for ext in PhotoEngine.rawExtensions { if let u = UTType(filenameExtension: ext) { t.append(u) } }
        return t
    }

    private var canvas: some View {
        GeometryReader { geo in
            ZStack {
                StudioTheme.canvas
                if let img = model.showBefore ? (model.beforeImage ?? model.image) : model.image {
                    Image(decorative: img, scale: displayScale)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fit)
                        .scaleEffect(zoom)
                        .offset(pan)
                        .gesture(zoomGesture.simultaneously(with: panGesture))
                        .onTapGesture(count: 2) { withAnimation(.snappy) { zoom = 1; pan = .zero; zoomBase = 1; panBase = .zero } }
                        .accessibilityLabel("Anteprima foto")
                } else if model.project.payload.source == nil {
                    ContentUnavailableView {
                        Label("Nessuna foto", systemImage: "camera.aperture")
                    } description: {
                        Text("Importa un RAW (DNG, CR2, CR3, NEF, ARW, RAF, RW2…) o un'immagine JPEG, PNG, TIFF, HEIC. L'originale viene copiato nel progetto e non viene mai modificato.")
                    } actions: {
                        Button("Importa foto") { importing = true }.buttonStyle(.borderedProminent)
                    }
                }
                if model.showBefore {
                    Text("PRIMA").font(.caption.weight(.heavy)).padding(6).background(.thinMaterial, in: Capsule())
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).padding()
                }
                if model.isRendering {
                    ProgressView().controlSize(.small).padding(8)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                }
            }
            .clipped()
            .onAppear { updateViewport(geo.size) }
            .onChange(of: geo.size) { _, s in updateViewport(s) }
        }
    }

    private func updateViewport(_ size: CGSize) {
        let s = displayScale
        model.viewportPixels = CGSize(width: min(size.width * s, 3000), height: min(size.height * s, 3000))
        model.requestRender(draft: false)
    }

    private var zoomGesture: some Gesture {
        MagnifyGesture()
            .onChanged { v in zoom = min(8, max(1, zoomBase * v.magnification)) }
            .onEnded { _ in zoomBase = zoom }
    }

    private var panGesture: some Gesture {
        DragGesture()
            .onChanged { v in if zoom > 1 { pan = CGSize(width: panBase.width + v.translation.width, height: panBase.height + v.translation.height) } }
            .onEnded { _ in panBase = pan }
    }

    private var inspector: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                HistogramView(bins: model.histogram).frame(height: 70)
                if let info = model.engine?.info { sourceBadge(info) }
                Divider()
                PanelSection("Profilo") {
                    Picker("Trattamento", selection: Binding(
                        get: { model.settings[path: "treatment"]?.stringValue ?? "color" },
                        set: { model.setString("treatment", $0, label: "Trattamento") })) {
                        Text("Colore").tag("color")
                        Text("Bianco e nero").tag("bw")
                    }
                    .pickerStyle(.segmented)
                }
                PanelSection(DevelopControls.whiteBalance.title) {
                    Picker("Preset", selection: Binding(
                        get: { model.settings[path: "wb.mode"]?.stringValue ?? "asShot" },
                        set: { model.setString("wb.mode", $0, label: "Bilanciamento") })) {
                        ForEach(DevelopControls.wbModes, id: \.0) { Text($0.1).tag($0.0) }
                    }
                    ForEach(DevelopControls.whiteBalance.controls) { slider($0) }
                }
                ForEach(DevelopControls.sections) { section in
                    PanelSection(section.title, expanded: section.title == "Luce") {
                        ForEach(section.controls) { slider($0) }
                        if section.title == "Geometria" { geometryButtons }
                    }
                }
                PanelSection("Preset", expanded: false) {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 140))], spacing: 8) {
                        ForEach(DevelopPreset.builtIn) { p in
                            Button(p.name) { model.applyPreset(p) }.buttonStyle(.bordered).frame(maxWidth: .infinity)
                        }
                    }
                }
                PanelSection("Cronologia", expanded: false) {
                    let past = model.project.history.past
                    if past.isEmpty { Text("Nessuna modifica").font(.caption).foregroundStyle(.secondary) }
                    ForEach(Array(past.enumerated().reversed()), id: \.offset) { _, e in
                        Text(e.label).font(.caption)
                    }
                }
                Button("Ripristina tutto", role: .destructive) { model.resetAll() }.padding(.top, 8)
            }
            .padding()
        }
        .background(StudioTheme.panel)
    }

    private var geometryButtons: some View {
        HStack {
            Button { model.rotate(clockwise: false) } label: { Image(systemName: "rotate.left") }
            Button { model.rotate(clockwise: true) } label: { Image(systemName: "rotate.right") }
            Button { model.setBool("crop.flip_h", !(model.settings[path: "crop.flip_h"]?.boolValue ?? false), label: "Rifletti") } label: {
                Image(systemName: "arrow.left.and.right.righttriangle.left.righttriangle.right")
            }
            Button { model.setBool("crop.flip_v", !(model.settings[path: "crop.flip_v"]?.boolValue ?? false), label: "Rifletti") } label: {
                Image(systemName: "arrow.up.and.down.righttriangle.up.righttriangle.down")
            }
        }
        .buttonStyle(.bordered)
    }

    private func sourceBadge(_ info: PhotoSourceInfo) -> some View {
        HStack {
            Text(info.isRaw ? "RAW \(info.rawFormat ?? "")" : "Immagine renderizzata")
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(info.isRaw ? Color.orange.opacity(0.25) : Color.gray.opacity(0.25), in: Capsule())
            if info.isRaw { Text("sviluppato dai dati del sensore").font(.caption2).foregroundStyle(.secondary) }
        }
    }

    private func slider(_ c: DevelopControl) -> some View {
        ValueSlider(
            c.label,
            value: Binding(get: { model.value(c.path) }, set: { model.set(c.path, $0, label: c.label) }),
            range: c.range, step: c.step, defaultValue: model.defaultValue(c.path),
            format: { String(format: "%.\(c.decimals)f", $0) },
            onEditing: { model.editing($0) }
        )
    }
}

struct HistogramView: View {
    let bins: [Double]
    var body: some View {
        Canvas { ctx, size in
            guard !bins.isEmpty else { return }
            let w = size.width / CGFloat(bins.count)
            var p = Path()
            p.move(to: CGPoint(x: 0, y: size.height))
            for (i, b) in bins.enumerated() {
                p.addLine(to: CGPoint(x: CGFloat(i) * w, y: size.height * (1 - b)))
                p.addLine(to: CGPoint(x: CGFloat(i + 1) * w, y: size.height * (1 - b)))
            }
            p.addLine(to: CGPoint(x: size.width, y: size.height))
            ctx.fill(p, with: .color(.secondary.opacity(0.6)))
        }
        .background(Color.black.opacity(0.25), in: RoundedRectangle(cornerRadius: 6))
        .accessibilityLabel("Istogramma")
    }
}

struct PhotoExportSheet: View {
    let model: PhotoEditorModel
    @State private var format: PhotoExportFormat = .jpg
    @State private var quality = 92.0
    @State private var longEdge = 0
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Picker("Formato", selection: $format) {
                    ForEach(PhotoExportFormat.allCases) { Text($0.title).tag($0) }
                }
                if format == .jpg || format == .webp || format == .avif {
                    ValueSlider("Qualità", value: $quality, range: 1 ... 100, defaultValue: 92)
                }
                Picker("Dimensione", selection: $longEdge) {
                    Text("Originale").tag(0)
                    Text("4096 px").tag(4096)
                    Text("2048 px").tag(2048)
                    Text("1080 px").tag(1080)
                }
                Section {
                    Text("L'esportazione decodifica di nuovo l'originale a piena risoluzione con lo stesso motore dell'anteprima. L'originale non viene modificato.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Esporta foto")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annulla") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Esporta") {
                        dismiss()
                        Task { await model.export(format: format, quality: Int(quality), longEdge: longEdge) }
                    }
                }
            }
        }
    }
}
