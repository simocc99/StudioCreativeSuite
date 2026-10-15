import AVFoundation
import StudioCore
import SwiftUI
import UniformTypeIdentifiers

public struct VideoEditorView: View {
    @State private var model: VideoEditorModel
    @State private var importRequest: ImportSource?
    @State private var importingSRT = false
    @State private var showExport = false
    @State private var timelineHeight: CGFloat = 320

    public init(project: ProjectController<VideoProject>) {
        _model = State(initialValue: VideoEditorModel(project: project))
    }

    public var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                MediaBinView(model: model, importRequest: $importRequest).studioPanel(width: 230, edge: .trailing)
                VStack(spacing: 0) {
                    PlayerLayerView(player: model.player)
                        .aspectRatio(CGFloat(model.doc.renderWidth) / CGFloat(max(1, model.doc.renderHeight)), contentMode: .fit)
                        .background(Color.black)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(StudioTheme.canvas)
                    transport
                }
                VideoInspector(model: model).studioPanel(width: 300)
            }
            resizeHandle
            toolStrip
            TimelineView(model: model).frame(height: timelineHeight)
        }
        .navigationTitle(model.project.header.name)
        .navigationBarTitleDisplayMode(.inline)
        .undoRedoToolbar(canUndo: model.project.canUndo, canRedo: model.project.canRedo, undo: model.undo, redo: model.redo)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Toggle(isOn: $model.useProxies) { Label("Proxy", systemImage: "bolt.horizontal") }
                Button { importingSRT = true } label: { Label("Importa SRT", systemImage: "captions.bubble") }
                Button { showExport = true } label: { Label("Esporta", systemImage: "square.and.arrow.up") }
                    .keyboardShortcut("e", modifiers: [.command])
                    .disabled(model.doc.duration <= 0)
            }
        }
        .mediaImporter($importRequest, types: [.movie, .audio, .mpeg4Movie, .quickTimeMovie], library: .videos, camera: .videos, multiple: true) { urls in
            Task { await model.importMedia(urls) }
        }
        .fileImporter(isPresented: $importingSRT, allowedContentTypes: [UTType(filenameExtension: "srt") ?? .plainText, .plainText]) { r in
            if case .success(let url) = r { model.importSRT(url) }
        }
        .sheet(isPresented: $showExport) { VideoExportSheet(model: model) }
        .shareSheet($model.exported)
        .overlay(alignment: .top) { if let e = model.error { ErrorBanner(e) { model.error = nil } } }
        .overlay {
            if let p = model.exportProgress { ProgressOverlay("Rendering ed esportazione…", progress: p) { model.cancelExport() } }
            if let b = model.busy { ProgressOverlay(b) }
        }
        .onDisappear { model.pause(); model.project.save() }
        .background(KeyCommands(model: model))
    }

    private var resizeHandle: some View {
        Capsule().fill(Color.white.opacity(0.25)).frame(width: 44, height: 4).padding(.vertical, 5)
            .frame(maxWidth: .infinity).studioBar()
            .gesture(DragGesture().onChanged { v in timelineHeight = min(600, max(160, timelineHeight - v.translation.height)) })
            .accessibilityLabel("Ridimensiona timeline")
    }

    private var transport: some View {
        HStack(spacing: 18) {
            Text(timecode(model.playhead, fps: model.doc.frameRate)).font(.callout.monospacedDigit())
            Spacer()
            Button { model.seek(0) } label: { Image(systemName: "backward.end.fill") }
            Button { model.step(frames: -1) } label: { Image(systemName: "backward.frame.fill") }
            Button { model.togglePlay() } label: { Image(systemName: model.isPlaying ? "pause.fill" : "play.fill").font(.title2) }
            Button { model.step(frames: 1) } label: { Image(systemName: "forward.frame.fill") }
            Button { model.seek(model.doc.duration) } label: { Image(systemName: "forward.end.fill") }
            Spacer()
            Text(timecode(model.doc.duration, fps: model.doc.frameRate)).font(.callout.monospacedDigit()).foregroundStyle(.secondary)
        }
        .padding(.horizontal).padding(.vertical, 8)
        .studioBar()
    }

    private var toolStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) { toolButtons }
            .studioBar()
    }

    private var toolButtons: some View {
        HStack(spacing: 14) {
            Button { model.splitAtPlayhead() } label: { Label("Dividi", systemImage: "scissors") }
            Button { model.deleteSelection(ripple: false) } label: { Label("Elimina", systemImage: "trash") }.disabled(model.selection.isEmpty)
            Button { model.deleteSelection(ripple: true) } label: { Label("Ripple", systemImage: "arrow.left.to.line") }.disabled(model.selection.isEmpty)
            Button { model.addMarker() } label: { Label("Marcatore", systemImage: "bookmark") }
            Button { model.addTitle(subtitle: false) } label: { Label("Titolo", systemImage: "textformat") }
            Button { model.addTitle(subtitle: true) } label: { Label("Sottotitolo", systemImage: "captions.bubble") }
            Button { model.addKeyframe() } label: { Label("Keyframe", systemImage: "diamond") }.disabled(model.selectedClip == nil)
            Menu {
                Button("Traccia video") { model.addTrack(.video) }
                Button("Traccia audio") { model.addTrack(.audio) }
            } label: { Label("Traccia", systemImage: "plus.rectangle.on.rectangle") }
            Toggle(isOn: $model.snapping) { Label("Aggancio", systemImage: "arrow.right.to.line.compact") }.toggleStyle(.button)
            Image(systemName: "minus.magnifyingglass")
            Slider(value: $model.pixelsPerSecond, in: 4 ... 600).frame(width: 160)
            Image(systemName: "plus.magnifyingglass")
        }
        .labelStyle(.titleAndIcon)
        .lineLimit(1)
        .fixedSize(horizontal: true, vertical: false)
        .font(.callout)
        .padding(.horizontal).padding(.vertical, 6)
    }
}

/// Keyboard shortcuts for an external keyboard (space, B, Delete, M, arrows).
private struct KeyCommands: View {
    let model: VideoEditorModel
    var body: some View {
        Group {
            Button("Play/Pausa") { model.togglePlay() }.keyboardShortcut(.space, modifiers: [])
            Button("Dividi") { model.splitAtPlayhead() }.keyboardShortcut("b", modifiers: .command)
            Button("Elimina") { model.deleteSelection(ripple: false) }.keyboardShortcut(.delete, modifiers: [])
            Button("Ripple") { model.deleteSelection(ripple: true) }.keyboardShortcut(.delete, modifiers: .shift)
            Button("Marcatore") { model.addMarker() }.keyboardShortcut("m", modifiers: [])
            Button("Fotogramma -") { model.step(frames: -1) }.keyboardShortcut(.leftArrow, modifiers: [])
            Button("Fotogramma +") { model.step(frames: 1) }.keyboardShortcut(.rightArrow, modifiers: [])
        }
        .opacity(0)
        .accessibilityHidden(true)
    }
}

struct PlayerLayerView: UIViewRepresentable {
    let player: AVPlayer
    func makeUIView(context: Context) -> PlayerUIView {
        let v = PlayerUIView()
        v.playerLayer.player = player
        v.playerLayer.videoGravity = .resizeAspect
        return v
    }
    func updateUIView(_ v: PlayerUIView, context: Context) { v.playerLayer.player = player }

    final class PlayerUIView: UIView {
        override class var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    }
}

struct MediaBinView: View {
    let model: VideoEditorModel
    @Binding var importRequest: ImportSource?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Media").font(.headline)
                Spacer()
                Menu { ImportMenuItems(request: $importRequest, library: .videos, camera: .videos) } label: { Image(systemName: "plus") }
                    .accessibilityLabel("Importa media")
            }
            .padding()
            if model.doc.media.isEmpty {
                ContentUnavailableView("Nessun media", systemImage: "film", description: Text("Importa video o audio. I file vengono copiati nel progetto."))
            }
            List(model.doc.media) { item in
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.name).font(.caption.weight(.semibold)).lineLimit(1)
                    Text(detail(item)).font(.caption2).foregroundStyle(.secondary)
                    HStack {
                        Button("Aggiungi") { model.addToTimeline(item) }.font(.caption2).buttonStyle(.bordered)
                        if item.hasVideo, item.proxyPath == nil {
                            Button("Proxy") { Task { await model.makeProxy(item) } }.font(.caption2).buttonStyle(.bordered)
                        }
                        if item.proxyPath != nil { Image(systemName: "bolt.horizontal.fill").font(.caption2).foregroundStyle(.yellow) }
                    }
                }
                .draggable(item.path)
                .listRowBackground(Color.clear)
            }
            .studioList()
        }
        .background(StudioTheme.panel)
    }

    func detail(_ m: MediaItem) -> String {
        var s = timecode(m.duration)
        if m.hasVideo { s += " · \(Int(m.width))×\(Int(m.height)) · \(MediaProbe.codecName(m.videoCodec))" }
        if m.hasAudio { s += " · audio" }
        return s
    }
}

struct VideoInspector: View {
    @Bindable var model: VideoEditorModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                if let c = model.selectedClip { clipInspector(c) }
                else if let t = model.selectedTitle { titleInspector(t) }
                else if model.selection.count > 1 { Text("\(model.selection.count) elementi selezionati").font(.callout) }
                else { projectInspector }
            }
            .padding()
        }
        .background(StudioTheme.panel)
    }

    private var projectInspector: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Sequenza").font(.headline)
            Picker("Formato", selection: Binding(
                get: { "\(model.doc.renderWidth)x\(model.doc.renderHeight)" },
                set: { v in
                    let p = v.split(separator: "x").compactMap { Int($0) }
                    model.edit("Formato") { $0.renderWidth = p[0]; $0.renderHeight = p[1] }
                })) {
                Text("1920×1080 (16:9)").tag("1920x1080")
                Text("3840×2160 (4K)").tag("3840x2160")
                Text("1080×1920 (9:16)").tag("1080x1920")
                Text("1080×1080 (1:1)").tag("1080x1080")
                Text("1280×720").tag("1280x720")
            }
            Picker("Fotogrammi/s", selection: Binding(get: { model.doc.frameRate }, set: { v in model.edit("FPS") { $0.frameRate = v } })) {
                ForEach([24, 25, 30, 50, 60], id: \.self) { Text("\($0)").tag($0) }
            }
            Text("Seleziona una clip o un titolo per modificarne le proprietà.").font(.caption).foregroundStyle(.secondary)
            if !model.doc.markers.isEmpty {
                Text("Marcatori").font(.subheadline.weight(.semibold)).padding(.top)
                ForEach(model.doc.markers) { m in
                    Button { model.seek(m.time) } label: { Text("\(timecode(m.time)) · \(m.name)").font(.caption) }
                }
            }
        }
    }

    private func clipInspector(_ c: Clip) -> some View {
        let t = c.transform(at: model.playhead)
        return VStack(alignment: .leading, spacing: 6) {
            Text((c.media as NSString).lastPathComponent).font(.headline).lineLimit(1)
            Text("\(timecode(c.start)) → \(timecode(c.end))").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            PanelSection("Velocità e audio") {
                slider("Velocità", c.speed, 0.1 ... 4, step: 0.05, fmt: "%.2fx", def: 1) { v in model.edit("Velocità") { $0.setSpeed(c.id, v) } }
                slider("Volume", c.volume, 0 ... 2, step: 0.01, fmt: "%.2f", def: 1) { v in model.updateClip("Volume") { $0.volume = v } }
                slider("Dissolvenza in entrata (s)", c.fadeIn, 0 ... 5, step: 0.05, fmt: "%.2f") { v in model.updateClip("Fade in") { $0.fadeIn = v } }
                slider("Dissolvenza in uscita (s)", c.fadeOut, 0 ... 5, step: 0.05, fmt: "%.2f") { v in model.updateClip("Fade out") { $0.fadeOut = v } }
                slider("Transizione incrociata (s)", c.transitionIn, 0 ... 3, step: 0.05, fmt: "%.2f") { v in
                    model.edit("Transizione") { $0.setTransition(c.id, v) }
                }
            }
            if c.hasVideo {
                PanelSection(c.keyframes.isEmpty ? "Trasformazione" : "Trasformazione (keyframe al playhead)") {
                    slider("Scala", t.scale, 0.1 ... 4, step: 0.01, fmt: "%.2f", def: 1) { v in model.setTransform("Scala") { $0.scale = v } }
                    slider("Posizione X", t.x, -1 ... 1, step: 0.005, fmt: "%.3f") { v in model.setTransform("Posizione") { $0.x = v } }
                    slider("Posizione Y", t.y, -1 ... 1, step: 0.005, fmt: "%.3f") { v in model.setTransform("Posizione") { $0.y = v } }
                    slider("Rotazione (°)", t.rotation, -180 ... 180, step: 0.5, fmt: "%.1f") { v in model.setTransform("Rotazione") { $0.rotation = v } }
                    slider("Opacità", t.opacity, 0 ... 1, step: 0.01, fmt: "%.2f", def: 1) { v in model.setTransform("Opacità") { $0.opacity = v } }
                    if !c.keyframes.isEmpty {
                        Button("Rimuovi keyframe", role: .destructive) { model.updateClip("Keyframe") { $0.keyframes.removeAll() } }.font(.caption)
                    }
                }
                PanelSection("Colore") {
                    slider("Luminosità", c.color.brightness, -0.5 ... 0.5, step: 0.01, fmt: "%.2f") { v in model.updateClip("Colore") { $0.color.brightness = v } }
                    slider("Contrasto", c.color.contrast, 0.5 ... 1.5, step: 0.01, fmt: "%.2f", def: 1) { v in model.updateClip("Colore") { $0.color.contrast = v } }
                    slider("Saturazione", c.color.saturation, 0 ... 2, step: 0.01, fmt: "%.2f", def: 1) { v in model.updateClip("Colore") { $0.color.saturation = v } }
                    slider("Temperatura (K)", c.color.temperature, 2500 ... 11000, step: 50, fmt: "%.0f", def: 6500) { v in model.updateClip("Colore") { $0.color.temperature = v } }
                }
                PanelSection("Effetto") {
                    Picker("Effetto", selection: Binding(get: { c.effect }, set: { v in model.updateClip("Effetto") { $0.effect = v } })) {
                        ForEach(ClipEffect.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                }
            }
        }
    }

    private func titleInspector(_ t: TitleClip) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(t.isSubtitle ? "Sottotitolo" : "Titolo").font(.headline)
            TextField("Testo", text: Binding(get: { t.text }, set: { v in model.updateTitle("Testo") { $0.text = v } }), axis: .vertical)
                .textFieldStyle(.roundedBorder)
            slider("Inizio (s)", t.start, 0 ... max(10, model.doc.duration), step: 0.05, fmt: "%.2f") { v in model.updateTitle("Titolo") { $0.start = v } }
            slider("Durata (s)", t.duration, 0.2 ... 30, step: 0.05, fmt: "%.2f", def: 3) { v in model.updateTitle("Titolo") { $0.duration = v } }
            slider("Dimensione", t.fontSize, 12 ... 240, step: 1, fmt: "%.0f", def: 72) { v in model.updateTitle("Titolo") { $0.fontSize = v } }
            slider("Posizione X", t.x, 0 ... 1, step: 0.01, fmt: "%.2f", def: 0.5) { v in model.updateTitle("Titolo") { $0.x = v } }
            slider("Posizione Y", t.y, 0 ... 1, step: 0.01, fmt: "%.2f", def: 0.85) { v in model.updateTitle("Titolo") { $0.y = v } }
            slider("Dissolvenza (s)", t.fade, 0 ... 2, step: 0.05, fmt: "%.2f", def: 0.3) { v in model.updateTitle("Titolo") { $0.fade = v } }
            ColorPicker("Colore testo", selection: Binding(get: { Color(rgba: t.color) }, set: { v in model.updateTitle("Colore") { $0.color = RGBAColor(v) } }))
            ColorPicker("Sfondo", selection: Binding(get: { Color(rgba: t.background) }, set: { v in model.updateTitle("Sfondo") { $0.background = RGBAColor(v) } }))
        }
    }

    private func slider(_ label: String, _ value: Double, _ range: ClosedRange<Double>, step: Double, fmt: String, def: Double = 0,
                        set: @escaping (Double) -> Void) -> some View {
        ValueSlider(label, value: Binding(get: { value }, set: set), range: range, step: step, defaultValue: def,
                    format: { String(format: fmt, $0) },
                    onEditing: { $0 ? model.project.beginGesture() : model.project.endGesture() })
    }
}

struct VideoExportSheet: View {
    let model: VideoEditorModel
    @State private var preset: VideoExportPreset = .h264_1080
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                if model.availablePresets.isEmpty {
                    HStack { ProgressView(); Text("Verifica dei formati supportati dal dispositivo…") }
                } else {
                    Picker("Formato", selection: $preset) {
                        ForEach(model.availablePresets) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.inline)
                }
                Section {
                    Text("Sono elencati solo i preset che AVFoundation dichiara compatibili con questa sequenza su questo dispositivo. L'esportazione usa lo stesso compositor dell'anteprima.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Esporta video")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annulla") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Esporta") { dismiss(); model.export(preset) }.disabled(!model.availablePresets.contains(preset))
                }
            }
            .task {
                await model.prepareExport()
                if !model.availablePresets.contains(preset), let f = model.availablePresets.first { preset = f }
            }
        }
    }
}
