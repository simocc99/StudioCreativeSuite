import StudioCore
import SwiftUI
import UniformTypeIdentifiers

public struct AudioEditorView: View {
    @State private var model: AudioEditorModel
    @State private var importing = false
    @State private var showExport = false

    public init(project: ProjectController<AudioProject>) {
        _model = State(initialValue: AudioEditorModel(project: project))
    }

    public var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                transport.studioBar(edge: .bottom)
                lanes
            }
            inspector.studioPanel(width: 300)
        }
        .navigationTitle(model.project.header.name)
        .navigationBarTitleDisplayMode(.inline)
        .undoRedoToolbar(canUndo: model.project.canUndo, canRedo: model.project.canRedo, undo: model.undo, redo: model.redo)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button { importing = true } label: { Label("Importa audio", systemImage: "square.and.arrow.down") }
                Button { showExport = true } label: { Label("Esporta", systemImage: "square.and.arrow.up") }.disabled(model.doc.duration <= 0)
            }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.audio], allowsMultipleSelection: true) { r in
            if case .success(let urls) = r { Task { await model.importFiles(urls) } }
        }
        .sheet(isPresented: $showExport) { AudioExportSheet(model: model) }
        .shareSheet($model.exported)
        .overlay(alignment: .top) { if let e = model.error { ErrorBanner(e) { model.error = nil } } }
        .overlay { if let b = model.busy { ProgressOverlay(b) } }
        .onDisappear { model.stop(); model.project.save() }
        .background(
            Group {
                Button("") { model.togglePlay() }.keyboardShortcut(.space, modifiers: [])
                Button("") { model.split() }.keyboardShortcut("b", modifiers: .command)
                Button("") { model.cutRange(ripple: true) }.keyboardShortcut("x", modifiers: .command)
            }.opacity(0)
        )
    }

    private var transport: some View {
        ScrollView(.horizontal, showsIndicators: false) { transportButtons }
    }

    private var transportButtons: some View {
        HStack(spacing: 16) {
            Button { model.seek(0) } label: { Image(systemName: "backward.end.fill") }
            Button { model.togglePlay() } label: { Image(systemName: model.isPlaying ? "stop.fill" : "play.fill").font(.title2) }
            Button { Task { await model.toggleRecord() } } label: {
                Image(systemName: model.isRecording ? "stop.circle.fill" : "record.circle").font(.title2).foregroundStyle(.red)
            }
            .accessibilityLabel(model.isRecording ? "Ferma registrazione" : "Registra")
            Text(String(format: "%02d:%05.2f", Int(model.playhead) / 60, model.playhead.truncatingRemainder(dividingBy: 60)))
                .font(.title3.monospacedDigit())
            MeterView(levels: model.meterPeak).frame(width: 120, height: 18)
            Button { model.split() } label: { Label("Dividi", systemImage: "scissors") }
            Button { model.cutRange(ripple: true) } label: { Label("Taglia selezione", systemImage: "scissors.badge.ellipsis") }.disabled(model.range == nil)
            Button { model.cutRange(ripple: false) } label: { Label("Silenzia", systemImage: "speaker.slash") }.disabled(model.range == nil)
            Button { model.addTrack() } label: { Label("Traccia", systemImage: "plus") }
            Slider(value: $model.pixelsPerSecond, in: 10 ... 600).frame(width: 120)
        }
        .labelStyle(.titleAndIcon)
        .lineLimit(1)
        .fixedSize(horizontal: true, vertical: false)
        .padding(10)
    }

    private var lanes: some View {
        ScrollView([.horizontal, .vertical]) {
            VStack(alignment: .leading, spacing: 0) {
                rulerAndRange
                ForEach(Array(model.doc.tracks.enumerated()), id: \.element.id) { i, t in
                    AudioLane(model: model, index: i, track: t)
                }
            }
            .frame(width: max(1200, (model.doc.duration + 20) * model.pixelsPerSecond), alignment: .leading)
            .overlay(alignment: .topLeading) {
                Rectangle().fill(StudioTheme.playhead).frame(width: 2).offset(x: model.playhead * model.pixelsPerSecond).allowsHitTesting(false)
            }
        }
        .background(StudioTheme.canvas)
    }

    @State private var rangeStart: Double?

    private var rulerAndRange: some View {
        ZStack(alignment: .topLeading) {
            Canvas { ctx, size in
                let pps = model.pixelsPerSecond
                let step: Double = pps > 200 ? 0.5 : pps > 50 ? 1 : 5
                var t = 0.0
                while t * pps < size.width {
                    ctx.stroke(Path { $0.move(to: CGPoint(x: t * pps, y: size.height)); $0.addLine(to: CGPoint(x: t * pps, y: 12)) }, with: .color(.secondary))
                    ctx.draw(Text(String(format: "%.0fs", t)).font(.system(size: 9)).foregroundStyle(.secondary), at: CGPoint(x: t * pps + 2, y: 2), anchor: .topLeading)
                    t += step
                }
            }
            if let r = model.range {
                Rectangle().fill(Color.accentColor.opacity(0.35))
                    .frame(width: (r.upperBound - r.lowerBound) * model.pixelsPerSecond, height: 30)
                    .offset(x: r.lowerBound * model.pixelsPerSecond)
            }
        }
        .frame(height: 30)
        .contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance: 0)
            .onChanged { v in
                let a = Double(v.startLocation.x) / model.pixelsPerSecond, b = Double(v.location.x) / model.pixelsPerSecond
                if abs(v.translation.width) < 4 { model.seek(a); model.range = nil } else { model.range = min(a, b) ... max(a, b) }
            })
        .accessibilityLabel("Righello: tocca per spostare il cursore, trascina per selezionare un intervallo")
    }

    private var inspector: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Master").font(.headline)
                    Spacer()
                    Text(model.masterPeakDB.isFinite ? String(format: "picco %.1f dBFS", model.masterPeakDB) : "silenzio").font(.caption.monospacedDigit())
                }
                if model.clipCount > 0 {
                    Label("\(model.clipCount) campioni in clipping: abbassa il volume o normalizza in esportazione", systemImage: "exclamationmark.octagon.fill")
                        .font(.caption).foregroundStyle(.red)
                }
                ValueSlider("Guadagno master (dB)", value: Binding(get: { model.doc.masterGainDB }, set: { v in model.edit("Master") { $0.masterGainDB = v } }),
                            range: -24 ... 12, step: 0.1, format: { String(format: "%.1f", $0) }, onEditing: gesture)
                Divider()
                if let id = model.selectedClip, let (t, c) = model.doc.locate(id) { clipPanel(model.doc.tracks[t].clips[c]) }
                if model.doc.tracks.indices.contains(model.selectedTrack) { trackPanel(model.selectedTrack) }
            }
            .padding()
        }
        .background(StudioTheme.panel)
    }

    private func gesture(_ on: Bool) { on ? model.project.beginGesture() : model.project.endGesture() }

    private func clipPanel(_ c: AudioClipDoc) -> some View {
        PanelSection("Clip") {
            ValueSlider("Guadagno (dB)", value: Binding(get: { c.gainDB }, set: { v in model.updateClip("Guadagno") { $0.gainDB = v } }),
                        range: -48 ... 24, step: 0.1, format: { String(format: "%.1f", $0) }, onEditing: gesture)
            ValueSlider("Fade in (s)", value: Binding(get: { c.fadeIn }, set: { v in model.updateClip("Fade in") { $0.fadeIn = min(v, c.duration) } }),
                        range: 0 ... 10, step: 0.05, format: { String(format: "%.2f", $0) }, onEditing: gesture)
            ValueSlider("Fade out (s)", value: Binding(get: { c.fadeOut }, set: { v in model.updateClip("Fade out") { $0.fadeOut = min(v, c.duration) } }),
                        range: 0 ... 10, step: 0.05, format: { String(format: "%.2f", $0) }, onEditing: gesture)
            Toggle("Inverti (reverse)", isOn: Binding(get: { c.reversed }, set: { v in model.updateClip("Reverse") { $0.reversed = v } }))
            HStack {
                Button("Normalizza a -1 dBFS") { model.normalizeClip() }
                Button("Elimina", role: .destructive) { model.deleteClip() }
            }
            .buttonStyle(.bordered)
        }
    }

    private func trackPanel(_ i: Int) -> some View {
        let t = model.doc.tracks[i]
        return PanelSection("Traccia: \(t.name)") {
            ValueSlider("Volume (dB)", value: Binding(get: { t.volumeDB }, set: { v in model.updateTrack(i, "Volume") { $0.volumeDB = v } }),
                        range: -60 ... 12, step: 0.1, format: { String(format: "%.1f", $0) }, onEditing: gesture)
            ValueSlider("Pan", value: Binding(get: { t.pan }, set: { v in model.updateTrack(i, "Pan") { $0.pan = v } }),
                        range: -1 ... 1, step: 0.01, format: { String(format: "%.2f", $0) }, onEditing: gesture)
            Text("Equalizzatore").font(.caption.weight(.semibold)).padding(.top, 4)
            ValueSlider("Bassi 120 Hz (dB)", value: Binding(get: { t.eq.lowGainDB }, set: { v in model.updateTrack(i, "EQ") { $0.eq.lowGainDB = v } }),
                        range: -18 ... 18, step: 0.5, format: { String(format: "%.1f", $0) }, onEditing: gesture)
            ValueSlider("Medi (dB)", value: Binding(get: { t.eq.midGainDB }, set: { v in model.updateTrack(i, "EQ") { $0.eq.midGainDB = v } }),
                        range: -18 ... 18, step: 0.5, format: { String(format: "%.1f", $0) }, onEditing: gesture)
            ValueSlider("Frequenza medi (Hz)", value: Binding(get: { t.eq.midFreq }, set: { v in model.updateTrack(i, "EQ") { $0.eq.midFreq = v } }),
                        range: 200 ... 6000, step: 10, defaultValue: 1000, onEditing: gesture)
            ValueSlider("Alti 8 kHz (dB)", value: Binding(get: { t.eq.highGainDB }, set: { v in model.updateTrack(i, "EQ") { $0.eq.highGainDB = v } }),
                        range: -18 ... 18, step: 0.5, format: { String(format: "%.1f", $0) }, onEditing: gesture)
            ValueSlider("Passa-alto (Hz, 0 = off)", value: Binding(get: { t.eq.highPassHz }, set: { v in model.updateTrack(i, "Filtro") { $0.eq.highPassHz = v } }),
                        range: 0 ... 1000, step: 5, onEditing: gesture)
            ValueSlider("Passa-basso (Hz, 0 = off)", value: Binding(get: { t.eq.lowPassHz }, set: { v in model.updateTrack(i, "Filtro") { $0.eq.lowPassHz = v } }),
                        range: 0 ... 20000, step: 50, onEditing: gesture)
            Toggle("Noise gate", isOn: Binding(get: { t.gateThresholdDB != nil }, set: { v in model.updateTrack(i, "Gate") { $0.gateThresholdDB = v ? -45 : nil } }))
            if let g = t.gateThresholdDB {
                ValueSlider("Soglia gate (dBFS)", value: Binding(get: { g }, set: { v in model.updateTrack(i, "Gate") { $0.gateThresholdDB = v } }),
                            range: -80 ... -10, step: 0.5, defaultValue: -45, format: { String(format: "%.1f", $0) }, onEditing: gesture)
                Text("Il gate attenua le pause sotto la soglia; non elimina il rumore presente sotto la voce.").font(.caption2).foregroundStyle(.secondary)
            }
            Text("Automazione volume").font(.caption.weight(.semibold)).padding(.top, 4)
            HStack {
                Button("Punto 0 dB") { model.addAutomationPoint(track: i, gainDB: 0) }
                Button("Punto -12 dB") { model.addAutomationPoint(track: i, gainDB: -12) }
                Button("Cancella") { model.updateTrack(i, "Automazione") { $0.automation.removeAll() } }
            }
            .buttonStyle(.bordered).font(.caption)
        }
    }
}

struct AudioLane: View {
    let model: AudioEditorModel
    let index: Int
    let track: AudioTrackDoc

    var body: some View {
        ZStack(alignment: .topLeading) {
            Rectangle().fill(model.selectedTrack == index ? Color.accentColor.opacity(0.08) : Color.clear)
            ForEach(track.clips) { c in
                clipView(c)
            }
            if !track.automation.isEmpty {
                Path { p in
                    let pts = track.automation.sorted { $0.time < $1.time }
                    for (i, a) in pts.enumerated() {
                        let pt = CGPoint(x: a.time * model.pixelsPerSecond, y: 50 - (a.gainDB + 24) / 36 * 80)
                        i == 0 ? p.move(to: pt) : p.addLine(to: pt)
                    }
                }
                .stroke(Color.yellow, lineWidth: 1.5)
                .allowsHitTesting(false)
            }
            HStack(spacing: 8) {
                Text(track.name).font(.caption.weight(.bold))
                Button { model.updateTrack(index, "Muto") { $0.muted.toggle() } } label: {
                    Text("M").font(.caption.weight(.heavy)).foregroundStyle(track.muted ? .orange : .secondary)
                }
                Button { model.updateTrack(index, "Solo") { $0.solo.toggle() } } label: {
                    Text("S").font(.caption.weight(.heavy)).foregroundStyle(track.solo ? .yellow : .secondary)
                }
            }
            .padding(4).background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 4)).padding(4)
        }
        .frame(height: 100)
        .overlay(alignment: .bottom) { Divider() }
        .contentShape(Rectangle())
        .onTapGesture { model.selectedTrack = index; model.selectedClip = nil }
    }

    func clipView(_ c: AudioClipDoc) -> some View {
        let peaks = model.peaks[c.media] ?? []
        let media = model.doc.media.first { $0.path == c.media }
        let selected = model.selectedClip == c.id
        return Canvas { ctx, size in
            ctx.fill(Path(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: 4), with: .color(.green.opacity(0.35)))
            guard let media, media.duration > 0, !peaks.isEmpty else { return }
            let a = Int(Double(peaks.count) * c.sourceStart / media.duration)
            let b = Int(Double(peaks.count) * (c.sourceStart + c.duration) / media.duration)
            var slice = Array(peaks[max(0, min(a, peaks.count)) ..< max(0, min(b, peaks.count))])
            if c.reversed { slice.reverse() }
            guard !slice.isEmpty else { return }
            let g = Float(dbToGain(c.gainDB))
            let step = size.width / CGFloat(slice.count)
            var p = Path()
            for (i, v) in slice.enumerated() {
                let tt = Double(i) / Double(slice.count) * c.duration
                var f: Float = 1
                if c.fadeIn > 0, tt < c.fadeIn { f = Float(tt / c.fadeIn) }
                if c.fadeOut > 0, c.duration - tt < c.fadeOut { f = min(f, Float((c.duration - tt) / c.fadeOut)) }
                let h = CGFloat(min(1, v * g * f)) * size.height * 0.9
                p.addRect(CGRect(x: CGFloat(i) * step, y: (size.height - h) / 2, width: max(1, step), height: h))
            }
            ctx.fill(p, with: .color(min(1, (slice.max() ?? 0) * g) >= 0.999 ? .red : .white.opacity(0.8)))
        }
        .frame(width: max(4, c.duration * model.pixelsPerSecond), height: 84)
        .overlay(RoundedRectangle(cornerRadius: 4).stroke(selected ? Color.white : .clear, lineWidth: 2))
        .offset(x: c.start * model.pixelsPerSecond, y: 8)
        .onTapGesture { model.selectedClip = c.id; model.selectedTrack = index }
        .gesture(DragGesture(minimumDistance: 6).onEnded { v in
            let id = c.id, d = Double(v.translation.width) / model.pixelsPerSecond
            model.edit("Sposta clip") { $0.updateClip(id) { $0.start = max(0, $0.start + d) } }
        })
    }
}

struct MeterView: View {
    let levels: [Float]
    var body: some View {
        VStack(spacing: 2) {
            ForEach(Array(levels.enumerated()), id: \.offset) { _, l in
                GeometryReader { g in
                    let db = gainToDB(Double(l))
                    let f = max(0, min(1, (db + 60) / 60))
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.gray.opacity(0.3))
                        Capsule().fill(db > -1 ? Color.red : db > -9 ? Color.yellow : Color.green).frame(width: g.size.width * f)
                    }
                }
            }
        }
        .accessibilityLabel("Livelli di uscita")
    }
}

struct AudioExportSheet: View {
    let model: AudioEditorModel
    @State private var format: AudioIO.ExportFormat = .wav24
    @State private var normalize = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Picker("Formato", selection: $format) { ForEach(AudioIO.ExportFormat.allCases) { Text($0.title).tag($0) } }
                Toggle("Normalizza il mix a -1 dBFS", isOn: $normalize)
                Text(String(format: "Frequenza di campionamento: %.0f Hz · stereo", model.doc.sampleRate)).font(.footnote).foregroundStyle(.secondary)
            }
            .navigationTitle("Esporta audio")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annulla") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Esporta") { dismiss(); Task { await model.export(format, normalize: normalize) } }
                }
            }
        }
    }
}
