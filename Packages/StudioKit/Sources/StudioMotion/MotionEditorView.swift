import StudioCore
import SwiftUI
import UniformTypeIdentifiers

@MainActor
@Observable
final class MotionEditorModel {
    let project: ProjectController<MotionProject>
    let renderer: MotionRenderer
    var time: Double = 0
    var playing = false
    var selected: UUID?
    var autoKey = true
    var error: String?
    var progress: Double?
    var exported: ExportedFile?
    @ObservationIgnored var playStart: Date?
    @ObservationIgnored var playFrom: Double = 0

    init(project: ProjectController<MotionProject>) {
        self.project = project
        renderer = MotionRenderer(projectURL: project.url)
    }

    var doc: MotionProject { project.payload }
    var layer: MotionLayer? { doc.layers.first { $0.id == selected } }

    func edit(_ label: String, _ f: (inout MotionProject) -> Void) { project.mutate(label, f) }

    func updateLayer(_ label: String, _ f: (inout MotionLayer) -> Void) {
        guard let id = selected else { return }
        edit(label) { p in if let i = p.layers.firstIndex(where: { $0.id == id }) { f(&p.layers[i]) } }
    }

    func addLayer(_ kind: MotionLayerKind, name: String) {
        var l = MotionLayer(name: name, kind: kind)
        l.x = AnimatedValue(Double(doc.width) / 2)
        l.y = AnimatedValue(Double(doc.height) / 2)
        l.outPoint = doc.duration
        switch kind {
        case .text: l.width = Double(doc.width) * 0.8; l.height = 200; l.color = .white
        case .solid: l.width = Double(doc.width); l.height = Double(doc.height); l.color = RGBAColor(0.2, 0.25, 0.4)
        default: break
        }
        edit("Nuovo livello") { $0.layers.append(l) }
        selected = l.id
    }

    func importImage(_ url: URL) {
        do {
            let rel = try project.importMedia(url)
            var l = MotionLayer(name: url.deletingPathExtension().lastPathComponent, kind: .image(rel))
            if let img = renderer.image(rel) {
                let s = min(Double(doc.width) / Double(img.width), Double(doc.height) / Double(img.height), 1)
                l.width = Double(img.width) * s
                l.height = Double(img.height) * s
            }
            l.x = AnimatedValue(Double(doc.width) / 2)
            l.y = AnimatedValue(Double(doc.height) / 2)
            l.outPoint = doc.duration
            edit("Importa immagine") { $0.layers.append(l); $0.media.append(rel) }
            selected = l.id
        } catch {
            self.error = error.localizedDescription
        }
    }

    func setProperty(_ kp: WritableKeyPath<MotionLayer, AnimatedValue>, _ v: Double, label: String) {
        let t = time, key = autoKey
        updateLayer(label) { $0[keyPath: kp].set(v, at: t, keyframe: key) }
    }

    func toggleKeyframes(_ kp: WritableKeyPath<MotionLayer, AnimatedValue>) {
        let t = time
        updateLayer("Keyframe") { l in
            if l[keyPath: kp].isAnimated {
                l[keyPath: kp].value = l[keyPath: kp].at(t)
                l[keyPath: kp].keys.removeAll()
            } else {
                l[keyPath: kp].keys = [Keyframe(time: t, value: l[keyPath: kp].value)]
            }
        }
    }

    func setEasing(_ kp: WritableKeyPath<MotionLayer, AnimatedValue>, _ e: Easing) {
        let t = time
        updateLayer("Interpolazione") { l in
            // the keyframe at or just before the playhead controls the segment after it
            if let i = l[keyPath: kp].keys.lastIndex(where: { $0.time <= t + 1e-4 }) { l[keyPath: kp].keys[i].easing = e }
        }
    }

    func togglePlay() {
        playing.toggle()
        if playing {
            if time >= doc.duration { time = 0 }
            playStart = .now
            playFrom = time
        }
    }

    func tick(_ date: Date) {
        guard playing, let s = playStart else { return }
        time = playFrom + date.timeIntervalSince(s)
        if time >= doc.duration { time = doc.duration; playing = false }
    }

    enum ExportKind: String, CaseIterable, Identifiable {
        case h264, hevc, prores, png, gif
        var id: String { rawValue }
        var title: String {
            switch self {
            case .h264: "Video H.264 (.mp4)"
            case .hevc: "Video HEVC (.mov)"
            case .prores: "Video ProRes 422 (.mov)"
            case .png: "Sequenza PNG"
            case .gif: "GIF animata (metà risoluzione)"
            }
        }
    }

    func export(_ k: ExportKind) {
        let snapshot = doc, renderer = renderer, name = project.header.name
        progress = 0
        Task {
            do {
                let n = snapshot.frameCount, fps = Double(snapshot.fps)
                let draw: (Int, CGContext) -> Void = { i, ctx in renderer.draw(snapshot, at: Double(i) / fps, in: ctx) }
                let url: URL
                switch k {
                case .h264, .hevc, .prores:
                    let codec: FrameVideoWriter.Codec = k == .h264 ? .h264 : k == .hevc ? .hevc : .prores
                    url = StudioPaths.exportURL(name: name, ext: codec.ext)
                    try await FrameVideoWriter.write(to: url, width: snapshot.width, height: snapshot.height, fps: snapshot.fps, frameCount: n, codec: codec,
                                                     progress: { p in Task { @MainActor in self.progress = p } }, draw: draw)
                case .png:
                    url = try FrameVideoWriter.writePNGSequence(to: StudioPaths.exportURL(name: name + " frames", ext: "seq"), width: snapshot.width,
                                                                height: snapshot.height, frameCount: n, draw: draw)
                case .gif:
                    url = StudioPaths.exportURL(name: name, ext: "gif")
                    try FrameVideoWriter.writeGIF(to: url, width: snapshot.width / 2, height: snapshot.height / 2, fps: min(snapshot.fps, 25),
                                                  frameCount: Int(snapshot.duration * Double(min(snapshot.fps, 25)))) { i, ctx in
                        ctx.scaleBy(x: 0.5, y: 0.5)
                        renderer.draw(snapshot, at: Double(i) / Double(min(snapshot.fps, 25)), in: ctx)
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

public struct MotionEditorView: View {
    @State private var model: MotionEditorModel
    @State private var importing = false

    public init(project: ProjectController<MotionProject>) {
        _model = State(initialValue: MotionEditorModel(project: project))
    }

    public var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                layerList.studioPanel(width: 220, edge: .trailing)
                preview
                inspector.studioPanel(width: 300)
            }
            timeline.frame(height: 220).studioBar()
        }
        .navigationTitle(model.project.header.name)
        .navigationBarTitleDisplayMode(.inline)
        .undoRedoToolbar(canUndo: model.project.canUndo, canRedo: model.project.canRedo, undo: { model.project.undo() }, redo: { model.project.redo() })
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Menu {
                    Button("Rettangolo") { model.addLayer(.rectangle(cornerRadius: 24), name: "Rettangolo") }
                    Button("Ellisse") { model.addLayer(.ellipse, name: "Ellisse") }
                    Button("Stella") { model.addLayer(.star(points: 5), name: "Stella") }
                    Button("Testo") { model.addLayer(.text("Titolo animato", fontSize: 120), name: "Testo") }
                    Button("Tinta unita") { model.addLayer(.solid, name: "Tinta unita") }
                    Button("Immagine…") { importing = true }
                } label: { Label("Livello", systemImage: "plus.square.on.square") }
                Menu {
                    ForEach(MotionEditorModel.ExportKind.allCases) { k in Button(k.title) { model.export(k) } }
                } label: { Label("Renderizza", systemImage: "square.and.arrow.up") }
            }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.image]) { r in
            if case .success(let url) = r { model.importImage(url) }
        }
        .shareSheet($model.exported)
        .overlay(alignment: .top) { if let e = model.error { ErrorBanner(e) { model.error = nil } } }
        .overlay { if let p = model.progress { ProgressOverlay("Rendering della composizione…", progress: p) } }
        .onDisappear { model.project.save() }
        .background(Button("") { model.togglePlay() }.keyboardShortcut(.space, modifiers: []).opacity(0))
    }

    @State private var dragOrigin: CGPoint?

    private var preview: some View {
        VStack(spacing: 0) {
            GeometryReader { geo in
                let s = min(geo.size.width / CGFloat(model.doc.width), geo.size.height / CGFloat(model.doc.height))
                TimelineView(.animation(paused: !model.playing)) { ctx in
                    Canvas { gc, size in
                        gc.translateBy(x: (size.width - CGFloat(model.doc.width) * s) / 2, y: (size.height - CGFloat(model.doc.height) * s) / 2)
                        gc.scaleBy(x: s, y: s)
                        gc.withCGContext { cg in model.renderer.draw(model.doc, at: model.time, in: cg) }
                        if let l = model.layer {
                            let t = model.time
                            let r = CGRect(x: l.x.at(t) - l.width * l.scale.at(t) / 200, y: l.y.at(t) - l.height * l.scale.at(t) / 200,
                                           width: l.width * l.scale.at(t) / 100, height: l.height * l.scale.at(t) / 100)
                            gc.stroke(Path(r), with: .color(.accentColor), style: StrokeStyle(lineWidth: 2 / s, dash: [6 / s]))
                        }
                    }
                    .onChange(of: ctx.date) { _, d in model.tick(d) }
                }
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 2)
                    .onChanged { v in
                        guard let l = model.layer, s > 0 else { return }
                        if dragOrigin == nil {
                            dragOrigin = CGPoint(x: l.x.at(model.time), y: l.y.at(model.time))
                            model.project.beginGesture()
                        }
                        guard let o = dragOrigin else { return }
                        model.setProperty(\.x, o.x + v.translation.width / s, label: "Sposta livello")
                        model.setProperty(\.y, o.y + v.translation.height / s, label: "Sposta livello")
                    }
                    .onEnded { _ in
                        dragOrigin = nil
                        model.project.endGesture()
                    })
            }
            .background(StudioTheme.canvas)
            .accessibilityLabel("Anteprima composizione: trascina per spostare il livello selezionato")
            HStack {
                Button { model.time = 0 } label: { Image(systemName: "backward.end.fill") }
                Button { model.togglePlay() } label: { Image(systemName: model.playing ? "pause.fill" : "play.fill").font(.title3) }
                Text(String(format: "%.2f s  ·  fotogramma %d", model.time, Int(model.time * Double(model.doc.fps)))).font(.callout.monospacedDigit())
                Spacer()
                Toggle("Keyframe automatici", isOn: $model.autoKey).fixedSize()
            }
            .padding(8)
        }
    }

    private var layerList: some View {
        List(selection: $model.selected) {
            ForEach(model.doc.layers.reversed()) { l in
                HStack {
                    Image(systemName: icon(l.kind))
                    Text(l.name).lineLimit(1)
                    Spacer()
                    Button { model.selected = l.id; model.updateLayer("Visibilità") { $0.visible.toggle() } } label: {
                        Image(systemName: l.visible ? "eye" : "eye.slash")
                    }
                    .buttonStyle(.plain)
                }
                .tag(l.id)
            }
            .onMove { from, to in
                // the list shows top layer first; convert to bottom → top indices
                model.edit("Ordina livelli") { p in
                    var rev = Array(p.layers.reversed())
                    rev.move(fromOffsets: from, toOffset: to)
                    p.layers = rev.reversed()
                }
            }
            .onDelete { idx in
                model.edit("Elimina livello") { p in
                    let ids = idx.map { Array(p.layers.reversed())[$0].id }
                    p.layers.removeAll { ids.contains($0.id) }
                }
            }
        }
        .overlay {
            if model.doc.layers.isEmpty {
                ContentUnavailableView("Composizione vuota", systemImage: "sparkles", description: Text("Aggiungi forme, testi o immagini dal menu Livello."))
            }
        }
    }

    private func icon(_ k: MotionLayerKind) -> String {
        switch k {
        case .rectangle: "rectangle"
        case .ellipse: "circle"
        case .star: "star"
        case .text: "textformat"
        case .image: "photo"
        case .solid: "square.fill"
        }
    }

    private var inspector: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                if let l = model.layer { layerPanel(l) } else { compPanel }
            }
            .padding()
        }
        .background(StudioTheme.panel)
    }

    private var compPanel: some View {
        PanelSection("Composizione") {
            Picker("Formato", selection: Binding(get: { "\(model.doc.width)x\(model.doc.height)" }, set: { v in
                let p = v.split(separator: "x").compactMap { Int($0) }
                model.edit("Formato") { $0.width = p[0]; $0.height = p[1] }
            })) {
                Text("1920×1080").tag("1920x1080"); Text("1080×1920").tag("1080x1920"); Text("1080×1080").tag("1080x1080"); Text("3840×2160").tag("3840x2160")
            }
            Picker("FPS", selection: Binding(get: { model.doc.fps }, set: { v in model.edit("FPS") { $0.fps = v } })) {
                ForEach([24, 25, 30, 60], id: \.self) { Text("\($0)").tag($0) }
            }
            ValueSlider("Durata (s)", value: Binding(get: { model.doc.duration }, set: { v in model.edit("Durata") { $0.duration = v } }), range: 1 ... 120,
                        step: 0.5, defaultValue: 10, format: { String(format: "%.1f", $0) })
            ColorPicker("Sfondo", selection: Binding(get: { Color(rgba: model.doc.background) }, set: { v in model.edit("Sfondo") { $0.background = RGBAColor(v) } }))
        }
    }

    private func layerPanel(_ l: MotionLayer) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Nome", text: Binding(get: { l.name }, set: { v in model.updateLayer("Nome") { $0.name = v } })).textFieldStyle(.roundedBorder)
            if case .text(let str, let size) = l.kind {
                TextField("Testo", text: Binding(get: { str }, set: { v in model.updateLayer("Testo") { $0.kind = .text(v, fontSize: size) } }), axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                ValueSlider("Corpo", value: Binding(get: { size }, set: { v in model.updateLayer("Corpo") { $0.kind = .text(str, fontSize: v) } }), range: 12 ... 400, defaultValue: 120)
                Picker("Animazione testo", selection: Binding(get: { l.textAnimation }, set: { v in model.updateLayer("Animazione testo") { $0.textAnimation = v } })) {
                    ForEach(TextAnimation.allCases, id: \.self) { Text($0.title).tag($0) }
                }
            }
            ColorPicker("Colore", selection: Binding(get: { Color(rgba: l.color) }, set: { v in model.updateLayer("Colore") { $0.color = RGBAColor(v) } }))
            HStack {
                ValueSlider("Larghezza", value: Binding(get: { l.width }, set: { v in model.updateLayer("Dimensione") { $0.width = v } }), range: 1 ... 4000, defaultValue: 400)
                ValueSlider("Altezza", value: Binding(get: { l.height }, set: { v in model.updateLayer("Dimensione") { $0.height = v } }), range: 1 ... 4000, defaultValue: 400)
            }
            HStack {
                ValueSlider("Entrata (s)", value: Binding(get: { l.inPoint }, set: { v in model.updateLayer("Entrata") { $0.inPoint = min(v, $0.outPoint - 0.04) } }),
                            range: 0 ... model.doc.duration, step: 0.04, format: { String(format: "%.2f", $0) })
                ValueSlider("Uscita (s)", value: Binding(get: { l.outPoint }, set: { v in model.updateLayer("Uscita") { $0.outPoint = max(v, $0.inPoint + 0.04) } }),
                            range: 0 ... model.doc.duration, step: 0.04, defaultValue: model.doc.duration, format: { String(format: "%.2f", $0) })
            }
            Picker("Maschera", selection: Binding(get: { l.mask }, set: { v in model.updateLayer("Maschera") { $0.mask = v } })) {
                ForEach(MaskShape.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            PanelSection("Proprietà animabili") {
                ForEach(l.animatedProperties, id: \.0) { name, kp in property(l, name, kp) }
            }
        }
    }

    private func range(_ name: String) -> ClosedRange<Double> {
        switch name {
        case "Posizione X": -Double(model.doc.width) ... Double(model.doc.width) * 2
        case "Posizione Y": -Double(model.doc.height) ... Double(model.doc.height) * 2
        case "Scala %": 0 ... 400
        case "Rotazione °": -720 ... 720
        case "Sfocatura": 0 ... 60
        default: 0 ... 100
        }
    }

    private func property(_ l: MotionLayer, _ name: String, _ kp: WritableKeyPath<MotionLayer, AnimatedValue>) -> some View {
        let v = l[keyPath: kp]
        return VStack(alignment: .leading, spacing: 2) {
            HStack {
                Button { model.toggleKeyframes(kp) } label: {
                    Image(systemName: "stopwatch").foregroundStyle(v.isAnimated ? Color.accentColor : .secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Keyframe per \(name)")
                ValueSlider(name, value: Binding(get: { v.at(model.time) }, set: { model.setProperty(kp, $0, label: name) }), range: range(name),
                            defaultValue: kp == \.scale || kp == \.opacity || kp == \.maskReveal || kp == \.textProgress ? 100 : 0,
                            format: { String(format: "%.1f", $0) },
                            onEditing: { $0 ? model.project.beginGesture() : model.project.endGesture() })
            }
            if v.isAnimated {
                Picker("Interpolazione", selection: Binding(get: {
                    v.keys.last(where: { $0.time <= model.time + 1e-4 })?.easing ?? .easeInOut
                }, set: { model.setEasing(kp, $0) })) {
                    ForEach(Easing.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .font(.caption)
            }
        }
    }

    private var timeline: some View {
        GeometryReader { geo in
            let w = geo.size.width - 160
            let pps = w / max(model.doc.duration, 0.1)
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 0) {
                        Text("Livelli").font(.caption.weight(.semibold)).frame(width: 160, alignment: .leading).padding(.leading, 8)
                        Canvas { ctx, size in
                            var t = 0.0
                            while t <= model.doc.duration {
                                ctx.stroke(Path { $0.move(to: CGPoint(x: t * pps, y: 14)); $0.addLine(to: CGPoint(x: t * pps, y: size.height)) }, with: .color(.secondary))
                                ctx.draw(Text("\(Int(t))s").font(.system(size: 9)).foregroundStyle(.secondary), at: CGPoint(x: t * pps + 2, y: 0), anchor: .topLeading)
                                t += 1
                            }
                        }
                        .frame(height: 24)
                        .contentShape(Rectangle())
                        .gesture(DragGesture(minimumDistance: 0).onChanged { v in model.playing = false; model.time = min(max(0, v.location.x / pps), model.doc.duration) })
                    }
                    ForEach(model.doc.layers.reversed()) { l in
                        HStack(spacing: 0) {
                            Text(l.name).font(.caption).lineLimit(1).frame(width: 160, alignment: .leading).padding(.leading, 8)
                            ZStack(alignment: .leading) {
                                Capsule().fill(model.selected == l.id ? StudioTheme.accent.opacity(0.6) : StudioTheme.raisedStrong)
                                    .frame(width: max(4, (l.outPoint - l.inPoint) * pps), height: 16)
                                    .offset(x: l.inPoint * pps)
                                ForEach(l.animatedProperties, id: \.0) { _, kp in
                                    ForEach(l[keyPath: kp].keys, id: \.time) { k in
                                        Image(systemName: "diamond.fill").font(.system(size: 9)).foregroundStyle(.yellow)
                                            .offset(x: k.time * pps - 4)
                                            .onTapGesture { model.selected = l.id; model.time = k.time }
                                    }
                                }
                            }
                            .frame(width: w, height: 28, alignment: .leading)
                        }
                        .contentShape(Rectangle())
                        .onTapGesture { model.selected = l.id }
                    }
                }
                .overlay(alignment: .topLeading) {
                    Rectangle().fill(StudioTheme.playhead).frame(width: 2).frame(maxHeight: .infinity).offset(x: 160 + model.time * pps).allowsHitTesting(false)
                }
            }
        }
        .background(StudioTheme.panel)
    }
}
