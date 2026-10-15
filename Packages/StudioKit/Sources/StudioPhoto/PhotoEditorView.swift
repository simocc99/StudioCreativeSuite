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
    @State private var tab: DevelopTab = .base
    @State private var curveChannel = "curve.master"
    @State private var mixerComponent = "hue"
    @State private var wheel = "shadows"
    @State private var savingPreset = false
    @State private var newPresetName = ""

    public init(project: ProjectController<PhotoProject>) {
        _model = State(initialValue: PhotoEditorModel(project: project))
    }

    public var body: some View {
        HStack(spacing: 0) {
            canvas
            if model.engine != nil { inspector.studioPanel(width: 360) }
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
        VStack(spacing: 0) {
            DevelopTabBar(selection: $tab)
                .padding(.horizontal, 12).padding(.vertical, 10)
                .overlay(alignment: .bottom) { StudioTheme.hairline.frame(height: 1) }
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(tab.title).font(.title3.weight(.semibold))
                        Spacer()
                        if let paths = tab.resettablePaths {
                            Button("Azzera") { model.reset(paths, label: "Azzera \(tab.title.lowercased())") }
                                .font(.caption.weight(.semibold))
                        }
                    }
                    .padding(.bottom, 4)
                    switch tab {
                    case .base: baseTab
                    case .presets: presetsTab
                    case .curve: curveTab
                    case .color: colorTab
                    case .effects: effectsTab
                    case .detail: sections([DevelopControls.sharpening, DevelopControls.noise])
                    case .optics: opticsTab
                    case .geometry: geometryTab
                    case .calibration: sections([DevelopControls.calibration])
                    case .history: historyTab
                    }
                }
                .padding()
            }
        }
        .background(StudioTheme.panel)
    }

    private func sections(_ list: [DevelopSection]) -> some View {
        ForEach(list) { section in
            PanelSection(section.title) { ForEach(section.controls) { slider($0) } }
        }
    }

    // MARK: Base

    private var baseTab: some View {
        VStack(alignment: .leading, spacing: 4) {
            HistogramView(bins: model.histogram).frame(height: 70)
            if let info = model.engine?.info { sourceBadge(info) }
            HStack(spacing: 8) {
                Button { Task { await model.autoTone() } } label: {
                    Label(model.isAuto ? "Calcolo…" : "Auto", systemImage: "wand.and.stars").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.isAuto)
                Picker("Trattamento", selection: Binding(
                    get: { model.settings[path: "treatment"]?.stringValue ?? "color" },
                    set: { model.setString("treatment", $0, label: "Trattamento") })) {
                    Text("Colore").tag("color")
                    Text("B/N").tag("bw")
                }
                .pickerStyle(.segmented)
            }
            .padding(.vertical, 8)
            PanelSection("Profilo") {
                let current = model.settings[path: "profile.id"]?.stringValue ?? "lc.color"
                Menu {
                    ForEach(Array(Set(DevelopControls.profiles.map(\.group))).sorted(by: profileGroupOrder), id: \.self) { group in
                        Section(group) {
                            ForEach(DevelopControls.profiles.filter { $0.group == group }) { pr in
                                Button { model.setString("profile.id", pr.id, label: "Profilo") } label: {
                                    if pr.id == current { Label(pr.name, systemImage: "checkmark") } else { Text(pr.name) }
                                }
                            }
                        }
                    }
                } label: {
                    HStack {
                        Text(DevelopControls.profiles.first { $0.id == current }?.name ?? current)
                        Spacer()
                        Image(systemName: "chevron.up.chevron.down").font(.caption)
                    }
                    .padding(10)
                    .studioCard(radius: 8)
                }
                .buttonStyle(.plain)
                slider(DevelopControl("profile.amount", "Intensità", 0 ... 200))
            }
            PanelSection(DevelopControls.whiteBalance.title) {
                Picker("Preset", selection: Binding(
                    get: { model.settings[path: "wb.mode"]?.stringValue ?? "asShot" },
                    set: { model.setString("wb.mode", $0, label: "Bilanciamento") })) {
                    ForEach(DevelopControls.wbModes, id: \.0) { Text($0.1).tag($0.0) }
                }
                ForEach(DevelopControls.whiteBalance.controls) { slider($0) }
            }
            sections([DevelopControls.light, DevelopControls.presence])
            Button("Ripristina tutto", role: .destructive) { model.resetAll() }.padding(.top, 10)
        }
    }

    private func profileGroupOrder(_ a: String, _ b: String) -> Bool {
        let order = ["Base", "Pellicola", "Cinematografico", "Tenue", "Bianco e nero"]
        return (order.firstIndex(of: a) ?? 99) < (order.firstIndex(of: b) ?? 99)
    }

    // MARK: Presets

    private var presetsTab: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let p = model.activePreset {
                VStack(alignment: .leading, spacing: 6) {
                    Text("\(p.name)").font(.subheadline.weight(.semibold))
                    ValueSlider("Intensità", value: Binding(get: { model.presetAmount * 100 }, set: { model.setPresetAmount($0 / 100) }),
                                range: 0 ... 200, step: 1, defaultValue: 100, format: { "\(Int($0))%" }, onEditing: { model.editing($0) })
                }
                .padding(12)
                .studioCard(radius: 10)
            }
            Button { newPresetName = ""; savingPreset = true } label: {
                Label("Salva le impostazioni come preset", systemImage: "plus.square.on.square").frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            if !model.userPresets.isEmpty { presetGroup("I miei preset", model.userPresets, deletable: true) }
            ForEach(DevelopPreset.groups, id: \.self) { g in
                presetGroup(g, DevelopPreset.builtIn.filter { $0.group == g }, deletable: false)
            }
        }
        .alert("Nuovo preset", isPresented: $savingPreset) {
            TextField("Nome", text: $newPresetName)
            Button("Salva") { model.saveUserPreset(name: newPresetName) }
            Button("Annulla", role: .cancel) {}
        } message: {
            Text("Salva il look di questa foto (profilo, toni, colore, effetti, dettaglio). Bilanciamento del bianco, ritaglio e geometria restano esclusi.")
        }
    }

    private func presetGroup(_ title: String, _ presets: [DevelopPreset], deletable: Bool) -> some View {
        PanelSection(title, expanded: title == "I miei preset" || title == "Correzioni") {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                ForEach(presets) { p in
                    Button { model.applyPreset(p) } label: {
                        VStack(spacing: 0) {
                            ZStack {
                                StudioTheme.canvas
                                if let img = model.presetThumbnails[p.id] {
                                    Image(decorative: img, scale: 1).resizable().aspectRatio(contentMode: .fill)
                                } else {
                                    ProgressView().controlSize(.small)
                                }
                            }
                            .frame(height: 82)
                            .clipped()
                            Text(p.name).font(.caption2.weight(.medium)).lineLimit(1).padding(.vertical, 5).padding(.horizontal, 4)
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .studioCard(radius: 8, selected: model.activePreset?.id == p.id)
                    }
                    .buttonStyle(.plain)
                    .task(id: model.thumbnailEpoch) { await model.thumbnail(for: p) }
                    .contextMenu {
                        if deletable {
                            Button(role: .destructive) { model.deleteUserPreset(p) } label: { Label("Elimina preset", systemImage: "trash") }
                        }
                    }
                    .accessibilityLabel("Preset \(p.name)")
                }
            }
        }
    }

    // MARK: Curve

    private var curveTab: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Canale", selection: $curveChannel) {
                ForEach(DevelopControls.curveChannels, id: \.path) { Text($0.name).tag($0.path) }
            }
            .pickerStyle(.segmented)
            ToneCurveEditor(points: model.curvePoints(curveChannel), tint: curveTint,
                            onChange: { model.setCurve(curveChannel, $0) }, onEditing: { model.editing($0) })
            Text("Trascina sulla curva per aggiungere un punto; trascina un punto fuori dal riquadro per toglierlo.")
                .font(.caption2).foregroundStyle(.secondary)
            Button("Curva lineare") { model.setCurve(curveChannel, []) }.font(.caption.weight(.semibold))
            sections([DevelopControls.curveRegions])
        }
    }

    private var curveTint: Color {
        switch curveChannel {
        case "curve.red": .red
        case "curve.green": .green
        case "curve.blue": Color(red: 0.35, green: 0.55, blue: 1)
        default: .white
        }
    }

    // MARK: Color

    private var colorTab: some View {
        VStack(alignment: .leading, spacing: 4) {
            if (model.settings[path: "treatment"]?.stringValue ?? "color") == "bw" {
                sections([DevelopControls.bwMix])
            } else {
                PanelSection("Miscelatore colore") {
                    Picker("Componente", selection: $mixerComponent) {
                        Text("Tonalità").tag("hue")
                        Text("Saturazione").tag("sat")
                        Text("Luminanza").tag("lum")
                    }
                    .pickerStyle(.segmented)
                    ForEach(Array(zip(DevelopControls.bands, DevelopControls.mixer(mixerComponent))), id: \.1.path) { band, c in
                        HStack(alignment: .bottom, spacing: 8) {
                            Circle().fill(Color(hue: band.hue / 360, saturation: 0.8, brightness: 0.9)).frame(width: 10, height: 10)
                                .padding(.bottom, 8)
                            slider(c)
                        }
                    }
                }
            }
            PanelSection("Color grading") {
                Picker("Ruota", selection: $wheel) {
                    ForEach(DevelopControls.wheels) { Text($0.name).tag($0.key) }
                }
                .pickerStyle(.segmented)
                ColorWheel(hue: model.value("grading.\(wheel).hue"), sat: model.value("grading.\(wheel).sat"),
                           onChange: { h, s in
                               model.set("grading.\(wheel).hue", h, label: "Color grading")
                               model.set("grading.\(wheel).sat", s, label: "Color grading")
                           },
                           onEditing: { model.editing($0) })
                    .frame(maxWidth: 220)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                HStack {
                    Text("Tonalità \(Int(model.value("grading.\(wheel).hue")))° · saturazione \(Int(model.value("grading.\(wheel).sat")))")
                        .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    Spacer()
                    Button("Azzera") {
                        model.reset(["hue", "sat", "lum"].map { "grading.\(wheel).\($0)" }, label: "Azzera ruota")
                    }
                    .font(.caption.weight(.semibold))
                }
                slider(DevelopControl("grading.\(wheel).lum", "Luminanza", -100 ... 100))
                ForEach(DevelopControls.gradingBlend.controls) { slider($0) }
            }
        }
    }

    // MARK: Effects, optics, geometry

    private var effectsTab: some View {
        VStack(alignment: .leading, spacing: 4) {
            PanelSection(DevelopControls.vignette.title) {
                Picker("Stile", selection: Binding(
                    get: { model.settings[path: "vignette.style"]?.stringValue ?? "highlightPriority" },
                    set: { model.setString("vignette.style", $0, label: "Stile vignettatura") })) {
                    ForEach(DevelopControls.vignetteStyles, id: \.0) { Text($0.1).tag($0.0) }
                }
                ForEach(DevelopControls.vignette.controls) { slider($0) }
            }
            sections([DevelopControls.grain])
        }
    }

    private var opticsTab: some View {
        VStack(alignment: .leading, spacing: 4) {
            PanelSection("Correzioni automatiche") {
                toggle("optics.remove_ca", "Rimuovi aberrazione cromatica")
                toggle("optics.lens_profile", "Usa il profilo dell'obiettivo")
                if model.settings[path: "optics.lens_profile"]?.boolValue == true {
                    ForEach(DevelopControls.lensProfile.controls) { slider($0) }
                }
            }
            sections([DevelopControls.manualOptics, DevelopControls.defringe])
        }
    }

    private var geometryTab: some View {
        VStack(alignment: .leading, spacing: 4) {
            geometryButtons.padding(.vertical, 6)
            sections([DevelopControls.geometry])
        }
    }

    private var historyTab: some View {
        VStack(alignment: .leading, spacing: 6) {
            let past = model.project.history.past
            if past.isEmpty { Text("Nessuna modifica").font(.caption).foregroundStyle(.secondary) }
            ForEach(Array(past.enumerated().reversed()), id: \.offset) { _, e in
                Text(e.label).font(.callout)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 6)
                    .overlay(alignment: .bottom) { StudioTheme.hairline.frame(height: 1) }
            }
            Button("Ripristina tutto", role: .destructive) { model.resetAll() }.padding(.top, 10)
        }
    }

    private func toggle(_ path: String, _ label: String) -> some View {
        Toggle(label, isOn: Binding(get: { model.settings[path: path]?.boolValue ?? false },
                                    set: { model.setBool(path, $0, label: label) }))
            .font(.callout)
            .tint(StudioTheme.accent)
    }

    private var geometryButtons: some View {
        HStack {
            Button { model.rotate(clockwise: false) } label: { Image(systemName: "rotate.left") }
                .accessibilityLabel("Ruota a sinistra")
            Button { model.rotate(clockwise: true) } label: { Image(systemName: "rotate.right") }
                .accessibilityLabel("Ruota a destra")
            Button { model.setBool("crop.flip_h", !(model.settings[path: "crop.flip_h"]?.boolValue ?? false), label: "Rifletti") } label: {
                Image(systemName: "arrow.left.and.right.righttriangle.left.righttriangle.right")
            }
            .accessibilityLabel("Rifletti in orizzontale")
            Button { model.setBool("crop.flip_v", !(model.settings[path: "crop.flip_v"]?.boolValue ?? false), label: "Rifletti") } label: {
                Image(systemName: "arrow.up.and.down.righttriangle.up.righttriangle.down")
            }
            .accessibilityLabel("Rifletti in verticale")
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

/// Inspector tabs of the develop editor (Lightroom's panels).
enum DevelopTab: String, CaseIterable, Identifiable {
    case base, presets, curve, color, effects, detail, optics, geometry, calibration, history
    var id: String { rawValue }

    var title: String {
        switch self {
        case .base: "Base"
        case .presets: "Preset"
        case .curve: "Curva"
        case .color: "Colore"
        case .effects: "Effetti"
        case .detail: "Dettaglio"
        case .optics: "Ottica"
        case .geometry: "Geometria"
        case .calibration: "Calibrazione"
        case .history: "Cronologia"
        }
    }

    var icon: String {
        switch self {
        case .base: "slider.horizontal.3"
        case .presets: "camera.filters"
        case .curve: "chart.xyaxis.line"
        case .color: "paintpalette"
        case .effects: "circle.lefthalf.filled"
        case .detail: "camera.macro"
        case .optics: "camera.aperture"
        case .geometry: "perspective"
        case .calibration: "dial.medium"
        case .history: "clock.arrow.circlepath"
        }
    }

    /// Settings the "Azzera" button of the tab returns to the engine defaults (nil: no button).
    var resettablePaths: [String]? {
        switch self {
        case .curve: (DevelopControls.curveRegions.controls.map(\.path)) + DevelopControls.curveChannels.map(\.path)
        case .color: DevelopPreset.lookPaths.filter { $0.hasPrefix("mixer.") || $0.hasPrefix("grading.") || $0.hasPrefix("bw_mix.") }
        case .effects: (DevelopControls.vignette.controls + DevelopControls.grain.controls).map(\.path) + ["vignette.style"]
        case .detail: (DevelopControls.sharpening.controls + DevelopControls.noise.controls).map(\.path)
        case .optics: (DevelopControls.lensProfile.controls + DevelopControls.manualOptics.controls + DevelopControls.defringe.controls).map(\.path)
            + ["optics.remove_ca", "optics.lens_profile"]
        case .geometry: DevelopControls.geometry.controls.map(\.path)
        case .calibration: DevelopControls.calibration.controls.map(\.path)
        case .base, .presets, .history: nil
        }
    }
}

/// Two rows of icon tabs with their names, the selected one filled with the accent.
struct DevelopTabBar: View {
    @Binding var selection: DevelopTab

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 5), spacing: 6) {
            ForEach(DevelopTab.allCases) { t in
                Button { selection = t } label: {
                    VStack(spacing: 3) {
                        Image(systemName: t.icon).font(.system(size: 15, weight: .medium)).frame(height: 18)
                        Text(t.title).font(.system(size: 9, weight: .medium)).lineLimit(1).minimumScaleFactor(0.7)
                    }
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .foregroundStyle(selection == t ? Color.white : Color.secondary)
                    .background(selection == t ? StudioTheme.accent : Color.clear, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(t.title)
                .accessibilityAddTraits(selection == t ? .isSelected : [])
            }
        }
    }
}
