import AVFoundation
import Foundation
import Observation
import StudioCore

@MainActor
@Observable
public final class VideoEditorModel {
    public let project: ProjectController<VideoProject>
    public let player = AVPlayer()
    public var playhead: Double = 0
    public var isPlaying = false
    public var selection: Set<UUID> = []
    public var pixelsPerSecond: Double = 60
    public var useProxies = false { didSet { rebuild() } }
    public var snapping = true
    public var error: String?
    public var exportProgress: Double?
    public var exportTask: Task<Void, Never>?
    public var exported: ExportedFile?
    public var busy: String?
    public private(set) var availablePresets: [VideoExportPreset] = []

    @ObservationIgnored private var rebuildTask: Task<Void, Never>?
    @ObservationIgnored private var timeObserver: Any?
    @ObservationIgnored private var built: BuiltComposition?

    public init(project: ProjectController<VideoProject>) {
        self.project = project
        timeObserver = player.addPeriodicTimeObserver(forInterval: cm(1.0 / 30), queue: .main) { [weak self] t in
            MainActor.assumeIsolated {
                guard let self, self.isPlaying else { return }
                self.playhead = t.seconds
                if t.seconds >= self.doc.duration - 1e-3 { self.pause() }
            }
        }
        rebuild()
    }

    public var doc: VideoProject { project.payload }

    public func edit(_ label: String, _ change: (inout VideoProject) -> Void) {
        project.mutate(label, change)
        rebuild()
    }

    public func undo() { project.undo(); selection.removeAll(); rebuild() }
    public func redo() { project.redo(); rebuild() }

    // MARK: media

    public func importMedia(_ urls: [URL]) async {
        busy = "Importazione…"
        defer { busy = nil }
        for url in urls {
            do {
                let rel = try project.importMedia(url)
                let item = try await MediaProbe.probe(project.resolve(rel), relativePath: rel)
                edit("Importa \(item.name)") { $0.media.append(item) }
            } catch {
                self.error = "\(url.lastPathComponent): \(error.localizedDescription)"
            }
        }
    }

    /// Adds media to the first suitable track at the playhead (video → V1, audio-only → first audio track).
    public func addToTimeline(_ item: MediaItem, track: Int? = nil) {
        let target = track ?? doc.tracks.firstIndex { item.hasVideo ? $0.kind == .video : $0.kind == .audio } ?? 0
        var newID: UUID?
        edit("Aggiungi clip") { newID = $0.addClip(item, track: target, at: nil) }
        if let newID { selection = [newID] } else {
            error = "La traccia scelta non accetta questo media (video su tracce video, audio su tracce audio)."
        }
    }

    public func makeProxy(_ item: MediaItem) async {
        busy = "Creazione proxy per \(item.name)…"
        defer { busy = nil }
        do {
            let rel = try await ProxyMaker.makeProxy(for: item, projectURL: project.url)
            edit("Proxy") { p in
                if let i = p.media.firstIndex(of: item) { p.media[i].proxyPath = rel }
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    public func sourceLength(_ clip: Clip) -> Double {
        doc.media.first { $0.path == clip.media }?.duration ?? clip.sourceStart + clip.sourceDuration
    }

    // MARK: editing commands

    public func splitAtPlayhead() {
        if selection.isEmpty {
            edit("Dividi") { $0.splitAll(at: playhead) }
        } else {
            let ids = selection
            edit("Dividi") { p in for id in ids { p.split(id, at: playhead) } }
        }
    }

    public func deleteSelection(ripple: Bool) {
        let ids = selection
        guard !ids.isEmpty else { return }
        edit(ripple ? "Elimina con ripple" : "Elimina") { $0.delete(ids, ripple: ripple) }
        selection.removeAll()
    }

    public func addMarker() { edit("Marcatore") { $0.addMarker(at: playhead) } }

    public func addTitle(subtitle: Bool) {
        var id: UUID?
        edit(subtitle ? "Sottotitolo" : "Titolo") { id = $0.addTitle(subtitle ? "Sottotitolo" : "Titolo", at: playhead, subtitle: subtitle) }
        if let id { selection = [id] }
    }

    public func importSRT(_ url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { error = "SRT non leggibile"; return }
        var n = 0
        edit("Importa SRT") { n = $0.importSRT(text) }
        if n == 0 { error = "Nessun sottotitolo valido nel file SRT" }
    }

    public func addTrack(_ kind: TrackKind) {
        edit("Nuova traccia") { p in
            let n = p.tracks.filter { $0.kind == kind }.count + 1
            p.tracks.append(VideoTrack(kind: kind, name: (kind == .video ? "V" : "A") + "\(n)"))
        }
    }

    public var selectedClip: Clip? {
        guard selection.count == 1, let id = selection.first else { return nil }
        return doc.clip(id)
    }

    public var selectedTitle: TitleClip? {
        guard selection.count == 1, let id = selection.first else { return nil }
        return doc.titles.first { $0.id == id }
    }

    public func updateClip(_ label: String, _ change: @escaping (inout Clip) -> Void) {
        guard let id = selectedClip?.id else { return }
        edit(label) { $0.update(id, change) }
    }

    public func updateTitle(_ label: String, _ change: (inout TitleClip) -> Void) {
        guard let id = selectedTitle?.id else { return }
        edit(label) { p in
            if let i = p.titles.firstIndex(where: { $0.id == id }) { change(&p.titles[i]) }
        }
    }

    /// Adds/replaces a keyframe for the selected clip at the playhead with the clip's current transform.
    public func addKeyframe() {
        guard let c = selectedClip else { return }
        let local = min(max(0, playhead - c.start), c.duration)
        let value = c.transform(at: playhead)
        updateClip("Keyframe") { clip in
            clip.keyframes.removeAll { abs($0.time - local) < 1.0 / 60 }
            clip.keyframes.append(ClipKeyframe(time: local, value: value))
            clip.keyframes.sort { $0.time < $1.time }
        }
    }

    /// Edits the transform: at a keyframe when the clip has keyframes, else the static transform.
    public func setTransform(_ label: String, _ change: @escaping (inout ClipTransform) -> Void) {
        guard let c = selectedClip else { return }
        let local = playhead - c.start
        updateClip(label) { clip in
            if clip.keyframes.isEmpty {
                change(&clip.transform)
            } else {
                var v = clip.transform(at: clip.start + local)
                change(&v)
                clip.keyframes.removeAll { abs($0.time - local) < 1.0 / 60 }
                clip.keyframes.append(ClipKeyframe(time: min(max(0, local), clip.duration), value: v))
                clip.keyframes.sort { $0.time < $1.time }
            }
        }
    }

    // MARK: playback

    public func togglePlay() { isPlaying ? pause() : play() }

    public func play() {
        guard doc.duration > 0 else { return }
        if playhead >= doc.duration - 1e-3 { seek(0) }
        isPlaying = true
        player.play()
    }

    public func pause() {
        isPlaying = false
        player.pause()
    }

    public func seek(_ t: Double) {
        playhead = min(max(0, t), max(0, doc.duration))
        player.seek(to: cm(playhead), toleranceBefore: .zero, toleranceAfter: .zero)
    }

    public func step(frames: Int) {
        pause()
        seek(playhead + Double(frames) / Double(doc.frameRate))
    }

    /// Rebuilds the composition (debounced) after edits, keeping the playhead.
    public func rebuild() {
        rebuildTask?.cancel()
        let snapshot = doc, url = project.url, proxies = useProxies
        rebuildTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(120))
            guard !Task.isCancelled else { return }
            do {
                let b = try await CompositionBuilder.build(snapshot, projectURL: url, useProxies: proxies)
                guard !Task.isCancelled, let self else { return }
                self.built = b
                let wasPlaying = self.isPlaying
                self.player.replaceCurrentItem(with: b.playerItem())
                self.player.seek(to: cm(self.playhead), toleranceBefore: .zero, toleranceAfter: .zero) { _ in }
                if wasPlaying { self.player.play() }
            } catch {
                self?.error = error.localizedDescription
            }
        }
    }

    // MARK: export

    public func prepareExport() async {
        guard let b = try? await CompositionBuilder.build(doc, projectURL: project.url) else { return }
        availablePresets = await VideoExporter.availablePresets(for: b)
    }

    public func export(_ preset: VideoExportPreset) {
        pause()
        exportProgress = 0
        let snapshot = doc, url = project.url, name = project.header.name
        exportTask = Task { [weak self] in
            do {
                let b = try await CompositionBuilder.build(snapshot, projectURL: url, useProxies: false)
                let out = StudioPaths.exportURL(name: name, ext: preset.fileExtension)
                try await VideoExporter.export(b, preset: preset, to: out) { p in
                    Task { @MainActor in self?.exportProgress = p }
                }
                self?.exported = ExportedFile(out)
            } catch {
                self?.error = error.localizedDescription
            }
            self?.exportProgress = nil
        }
    }

    public func cancelExport() {
        exportTask?.cancel()
        exportProgress = nil
    }
}
