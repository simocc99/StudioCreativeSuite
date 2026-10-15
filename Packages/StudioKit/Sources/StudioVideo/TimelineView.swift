import StudioCore
import SwiftUI

/// Multitrack timeline: ruler, markers, track headers, clips (move / trim), titles row, playhead.
struct TimelineView: View {
    @Bindable var model: VideoEditorModel
    @State private var zoomBase: Double?
    static let trackHeight: CGFloat = 64
    static let headerWidth: CGFloat = 132
    static let rulerHeight: CGFloat = 28

    var pps: Double { model.pixelsPerSecond }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            headers
            ScrollView(.horizontal) {
                ZStack(alignment: .topLeading) {
                    VStack(alignment: .leading, spacing: 0) {
                        ruler
                        titlesRow
                        ForEach(Array(model.doc.tracks.enumerated()), id: \.element.id) { i, track in
                            trackRow(i, track)
                        }
                    }
                    playheadLine
                }
                .frame(width: contentWidth, alignment: .leading)
            }
            .simultaneousGesture(
                MagnifyGesture()
                    .onChanged { v in
                        if zoomBase == nil { zoomBase = pps }
                        model.pixelsPerSecond = min(600, max(4, (zoomBase ?? pps) * v.magnification))
                    }
                    .onEnded { _ in zoomBase = nil }
            )
        }
        .background(StudioTheme.background)
    }

    var contentWidth: CGFloat { CGFloat(max(model.doc.duration + 30, 60) * pps) }

    private var headers: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: Self.rulerHeight)
            Text("Titoli").font(.caption2.weight(.semibold)).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 8)
                .frame(height: 30)
            ForEach(Array(model.doc.tracks.enumerated()), id: \.element.id) { i, track in
                VStack(alignment: .leading, spacing: 4) {
                    Text(track.name).font(.caption.weight(.bold))
                    HStack(spacing: 10) {
                        if track.kind == .video {
                            toggle(track.hidden ? "eye.slash" : "eye", track.hidden) { $0.tracks[i].hidden.toggle() }
                        }
                        toggle(track.muted ? "speaker.slash" : "speaker.wave.2", track.muted) { $0.tracks[i].muted.toggle() }
                        toggle(track.locked ? "lock" : "lock.open", track.locked) { $0.tracks[i].locked.toggle() }
                    }
                }
                .padding(.horizontal, 8)
                .frame(width: Self.headerWidth, height: Self.trackHeight, alignment: .leading)
                .background(track.kind == .video ? Color.blue.opacity(0.12) : Color.green.opacity(0.12))
                .overlay(alignment: .bottom) { Divider() }
            }
        }
        .frame(width: Self.headerWidth)
        .background(StudioTheme.panel)
    }

    private func toggle(_ icon: String, _ on: Bool, _ change: @escaping (inout VideoProject) -> Void) -> some View {
        Button { model.edit("Traccia", change) } label: {
            Image(systemName: icon).font(.caption).foregroundStyle(on ? .orange : .secondary)
        }
        .buttonStyle(.plain)
    }

    private var ruler: some View {
        Canvas { ctx, size in
            let step = tickStep
            var t = 0.0
            while t * pps < size.width {
                let x = t * pps
                let major = Int((t / step).rounded()) % 5 == 0
                ctx.stroke(Path { $0.move(to: CGPoint(x: x, y: size.height)); $0.addLine(to: CGPoint(x: x, y: major ? 8 : 18)) },
                           with: .color(.secondary), lineWidth: 1)
                if major {
                    ctx.draw(Text(timecode(t)).font(.system(size: 9).monospacedDigit()).foregroundStyle(.secondary), at: CGPoint(x: x + 3, y: 6), anchor: .topLeading)
                }
                t += step
            }
            for m in model.doc.markers {
                let x = m.time * pps
                ctx.fill(Path { p in
                    p.move(to: CGPoint(x: x - 5, y: 0)); p.addLine(to: CGPoint(x: x + 5, y: 0)); p.addLine(to: CGPoint(x: x, y: 10))
                }, with: .color(.yellow))
            }
        }
        .frame(height: Self.rulerHeight)
        .contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance: 0).onChanged { v in
            model.pause()
            model.seek(Double(v.location.x) / pps)
        })
        .accessibilityLabel("Righello temporale")
    }

    private var tickStep: Double {
        let candidates = [1.0 / 30, 0.1, 0.2, 0.5, 1, 2, 5, 10, 30, 60]
        return candidates.first { $0 * pps >= 12 } ?? 60
    }

    private var titlesRow: some View {
        ZStack(alignment: .topLeading) {
            Color.purple.opacity(0.06)
            ForEach(model.doc.titles) { title in
                let selected = model.selection.contains(title.id)
                Text(title.text).font(.caption2).lineLimit(1).padding(.horizontal, 4)
                    .frame(width: max(8, title.duration * pps), height: 24, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 4).fill(title.isSubtitle ? Color.teal.opacity(0.6) : Color.purple.opacity(0.6)))
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(selected ? Color.white : .clear, lineWidth: 2))
                    .offset(x: title.start * pps, y: 3)
                    .onTapGesture { model.selection = [title.id] }
                    .gesture(DragGesture(minimumDistance: 4).onEnded { v in
                        let id = title.id
                        model.edit("Sposta titolo") { p in
                            if let i = p.titles.firstIndex(where: { $0.id == id }) {
                                p.titles[i].start = max(0, p.titles[i].start + Double(v.translation.width) / pps)
                            }
                        }
                    })
            }
        }
        .frame(height: 30)
    }

    private func trackRow(_ index: Int, _ track: VideoTrack) -> some View {
        ZStack(alignment: .topLeading) {
            Rectangle().fill(index % 2 == 0 ? Color.white.opacity(0.03) : Color.clear)
            ForEach(track.clips) { clip in
                ClipView(model: model, clip: clip, trackIndex: index, track: track)
            }
        }
        .frame(height: Self.trackHeight)
        .overlay(alignment: .bottom) { Divider() }
        .contentShape(Rectangle())
        .onTapGesture { model.selection.removeAll() }
    }

    private var playheadLine: some View {
        Rectangle().fill(StudioTheme.playhead).frame(width: 2)
            .frame(maxHeight: .infinity)
            .offset(x: model.playhead * pps - 1)
            .allowsHitTesting(false)
    }
}

func timecode(_ t: Double, fps: Int = 30) -> String {
    // round to the nearest frame first, so 0.99999 s reads 00:01:00 and not 00:00:29
    let frames = Int((max(0, t) * Double(fps)).rounded())
    let secs = frames / max(1, fps)
    return String(format: "%02d:%02d:%02d", secs / 60, secs % 60, frames % max(1, fps))
}

struct ClipView: View {
    @Bindable var model: VideoEditorModel
    let clip: Clip
    let trackIndex: Int
    let track: VideoTrack
    @State private var dragOffset: CGSize = .zero
    @State private var trimLeft: CGFloat = 0
    @State private var trimRight: CGFloat = 0
    @State private var thumbs: [CGImage] = []
    @State private var wave: [Float] = []

    var pps: Double { model.pixelsPerSecond }
    var selected: Bool { model.selection.contains(clip.id) }
    var width: CGFloat { max(6, CGFloat(clip.duration * pps) - trimLeft + trimRight) }

    var body: some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 5).fill(track.kind == .video ? Color.blue.opacity(0.55) : Color.green.opacity(0.5))
            if track.kind == .video, !thumbs.isEmpty {
                HStack(spacing: 0) {
                    ForEach(Array(thumbs.enumerated()), id: \.offset) { _, t in
                        Image(decorative: t, scale: 1).resizable().aspectRatio(contentMode: .fill).frame(width: 64, height: 40).clipped()
                    }
                }
                .frame(width: width, height: 40, alignment: .leading).clipped().opacity(0.85).offset(y: -8)
            }
            if clip.hasAudio, !wave.isEmpty { waveform.frame(height: track.kind == .video ? 18 : 44).offset(y: track.kind == .video ? 20 : 0) }
            VStack(alignment: .leading, spacing: 0) {
                Text((clip.media as NSString).lastPathComponent).font(.system(size: 10, weight: .semibold)).lineLimit(1)
                if clip.speed != 1 { Text(String(format: "%.2fx", clip.speed)).font(.system(size: 9)) }
            }
            .padding(.horizontal, 6).frame(maxHeight: .infinity, alignment: .top).padding(.top, 2)
            .shadow(radius: 2)
            if clip.transitionIn > 0 {
                LinearGradient(colors: [.white.opacity(0.6), .clear], startPoint: .leading, endPoint: .trailing)
                    .frame(width: clip.transitionIn * pps)
            }
            if !clip.keyframes.isEmpty {
                ForEach(clip.keyframes, id: \.time) { k in
                    Image(systemName: "diamond.fill").font(.system(size: 8)).foregroundStyle(.yellow)
                        .offset(x: k.time * pps - 4, y: 22)
                }
            }
        }
        .frame(width: width, height: TimelineView.trackHeight - 8)
        .clipShape(RoundedRectangle(cornerRadius: 5))
        .overlay(RoundedRectangle(cornerRadius: 5).stroke(selected ? Color.white : Color.black.opacity(0.4), lineWidth: selected ? 2 : 1))
        .overlay(alignment: .leading) { handle(left: true) }
        .overlay(alignment: .trailing) { handle(left: false) }
        .offset(x: clip.start * pps + trimLeft + dragOffset.width, y: 4 + dragOffset.height)
        .onTapGesture {
            if model.selection.contains(clip.id) && model.selection.count > 1 {
                model.selection.remove(clip.id)
            } else {
                model.selection = [clip.id]
            }
        }
        .onLongPressGesture(minimumDuration: 0.35) { model.selection.formSymmetricDifference([clip.id]) }
        .gesture(moveGesture)
        .task(id: clip.media) { await loadPreviews() }
        .accessibilityLabel("Clip \((clip.media as NSString).lastPathComponent)")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var waveform: some View {
        Canvas { ctx, size in
            let src = model.sourceLength(clip)
            guard src > 0 else { return }
            let a = Int(Double(wave.count) * clip.sourceStart / src)
            let b = Int(Double(wave.count) * (clip.sourceStart + clip.sourceDuration) / src)
            let slice = wave[max(0, min(a, wave.count)) ..< max(0, min(b, wave.count))]
            guard !slice.isEmpty else { return }
            let step = size.width / CGFloat(slice.count)
            var p = Path()
            for (i, v) in slice.enumerated() {
                let h = CGFloat(v) * size.height * CGFloat(clip.volume)
                p.addRect(CGRect(x: CGFloat(i) * step, y: (size.height - h) / 2, width: max(1, step), height: h))
            }
            ctx.fill(p, with: .color(.white.opacity(0.75)))
        }
    }

    private func handle(left: Bool) -> some View {
        Rectangle().fill(Color.white.opacity(selected ? 0.5 : 0.001)).frame(width: 14)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 1)
                .onChanged { v in
                    if left { trimLeft = v.translation.width } else { trimRight = v.translation.width }
                }
                .onEnded { v in
                    let d = Double(v.translation.width) / pps
                    let src = model.sourceLength(clip)
                    let id = clip.id
                    trimLeft = 0
                    trimRight = 0
                    model.edit(left ? "Rifila inizio" : "Rifila fine") { p in
                        if left { p.trimStart(id, by: d, sourceLength: src) } else { p.trimEnd(id, by: d, sourceLength: src) }
                    }
                })
    }

    private var moveGesture: some Gesture {
        DragGesture(minimumDistance: 6)
            .onChanged { v in dragOffset = v.translation }
            .onEnded { v in
                var start = clip.start + Double(v.translation.width) / pps
                if model.snapping { start = model.doc.snap(start, tolerance: 8 / pps, excluding: clip.id) }
                let rows = Int((v.translation.height / TimelineView.trackHeight).rounded())
                let dest = min(max(0, trackIndex + rows), model.doc.tracks.count - 1)
                let id = clip.id
                dragOffset = .zero
                model.edit("Sposta clip") { $0.move(id, to: start, track: dest) }
                model.selection = [id]
            }
    }

    private func loadPreviews() async {
        let url = model.project.resolve(clip.media)
        let src = model.sourceLength(clip)
        if track.kind == .video, clip.hasVideo {
            thumbs = await MediaPreviewCache.shared.thumbnails(url, count: 6, duration: src)
        }
        if clip.hasAudio { wave = await MediaPreviewCache.shared.waveform(url) }
    }
}
