import AVFoundation
import Foundation
import Observation
import StudioCore

@MainActor
@Observable
public final class AudioEditorModel {
    public let project: ProjectController<AudioProject>
    public var playhead: Double = 0
    public var isPlaying = false
    public var isRecording = false
    public var selectedClip: UUID?
    public var selectedTrack = 0
    /// Time selection for cut / process.
    public var range: ClosedRange<Double>?
    public var pixelsPerSecond: Double = 80
    public var error: String?
    public var busy: String?
    public var exported: ExportedFile?
    public private(set) var meterPeak: [Float] = [0, 0]
    public private(set) var masterPeakDB: Double = -.infinity
    public private(set) var clipCount = 0
    public private(set) var peaks: [String: [Float]] = [:]

    @ObservationIgnored private let renderer = AudioRenderer()
    @ObservationIgnored private let engine = AVAudioEngine()
    @ObservationIgnored private let player = AVAudioPlayerNode()
    @ObservationIgnored private var mix: PCMBuffer?
    @ObservationIgnored private var mixTask: Task<Void, Never>?
    @ObservationIgnored private var tick: Timer?
    @ObservationIgnored private var playStartTime: Double = 0
    @ObservationIgnored private var recorder: AVAudioFile?
    @ObservationIgnored private var recordURL: URL?
    @ObservationIgnored private var recordStart: Double = 0

    public init(project: ProjectController<AudioProject>) {
        self.project = project
        engine.attach(player)
        remix()
        Task { for m in project.payload.media { await loadPeaks(m.path) } }
    }

    public var doc: AudioProject { project.payload }

    public func edit(_ label: String, _ change: (inout AudioProject) -> Void) {
        project.mutate(label, change)
        remix()
    }

    public func undo() { project.undo(); remix() }
    public func redo() { project.redo(); remix() }

    // MARK: media

    public func importFiles(_ urls: [URL]) async {
        busy = "Importazione audio…"
        defer { busy = nil }
        for url in urls {
            do {
                let rel = try project.importMedia(url)
                let m = try await Self.probe(project.resolve(rel), path: rel)
                edit("Importa \(m.name)") { p in
                    p.media.append(m)
                    p.addClip(m, track: min(self.selectedTrack, p.tracks.count - 1))
                }
                await loadPeaks(rel)
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    public nonisolated static func probe(_ url: URL, path: String) async throws -> AudioMedia {
        let f: AVAudioFile
        do { f = try AVAudioFile(forReading: url) } catch {
            throw StudioError.unsupportedFile("\(url.lastPathComponent): non è un file audio leggibile")
        }
        let sr = f.fileFormat.sampleRate
        return AudioMedia(path: path, name: url.lastPathComponent, duration: Double(f.length) / sr, sampleRate: sr, channels: Int(f.fileFormat.channelCount))
    }

    func loadPeaks(_ path: String) async {
        let url = project.resolve(path), sr = doc.sampleRate
        let p = await Task.detached(priority: .utility) { () -> [Float] in
            guard let b = try? AudioIO.read(url, sampleRate: sr) else { return [] }
            return b.peaks(buckets: max(200, Int(b.duration * 100)))
        }.value
        peaks[path] = p
    }

    // MARK: editing

    public func split() {
        if let id = selectedClip {
            edit("Dividi") { _ = $0.split(id, at: playhead) }
        } else {
            edit("Dividi") { p in for t in p.tracks.indices { for c in p.tracks[t].clips where c.start < playhead && c.end > playhead { p.split(c.id, at: playhead) } } }
        }
    }

    public func cutRange(ripple: Bool) {
        guard let r = range else { return }
        edit(ripple ? "Taglia (ripple)" : "Silenzia intervallo") { $0.cut(from: r.lowerBound, to: r.upperBound, track: nil, ripple: ripple) }
        range = nil
    }

    public func deleteClip() {
        guard let id = selectedClip else { return }
        edit("Elimina clip") { p in
            if let (t, c) = p.locate(id) { p.tracks[t].clips.remove(at: c) }
        }
        selectedClip = nil
    }

    /// Sets the clip gain so its peak reaches -1 dBFS (non-destructive: stored as clip gain).
    public func normalizeClip() {
        guard let id = selectedClip, let (t, c) = doc.locate(id) else { return }
        var clip = doc.tracks[t].clips[c]
        clip.gainDB = 0
        clip.fadeIn = 0
        clip.fadeOut = 0
        guard let b = try? renderer.clipBuffer(clip, projectURL: project.url, sampleRate: doc.sampleRate) else { return }
        let p = Double(b.peak)
        guard p > 0 else { return }
        let g = -1 - gainToDB(p)
        edit("Normalizza") { $0.updateClip(id) { $0.gainDB = g } }
    }

    public func updateClip(_ label: String, _ f: @escaping (inout AudioClipDoc) -> Void) {
        guard let id = selectedClip else { return }
        edit(label) { $0.updateClip(id, f) }
    }

    public func updateTrack(_ i: Int, _ label: String, _ f: (inout AudioTrackDoc) -> Void) {
        guard doc.tracks.indices.contains(i) else { return }
        edit(label) { f(&$0.tracks[i]) }
    }

    public func addAutomationPoint(track i: Int, gainDB: Double) {
        let t = playhead
        updateTrack(i, "Automazione") { tr in
            tr.automation.removeAll { abs($0.time - t) < 0.01 }
            tr.automation.append(AutomationPoint(time: t, gainDB: gainDB))
            tr.automation.sort { $0.time < $1.time }
        }
    }

    public func addTrack() {
        edit("Nuova traccia") { $0.tracks.append(AudioTrackDoc(name: "Traccia \($0.tracks.count + 1)")) }
    }

    // MARK: mix + playback

    /// Re-renders the mix off the main thread (debounced) and updates the clipping report.
    public func remix() {
        mixTask?.cancel()
        let snapshot = doc, url = project.url, renderer = renderer
        mixTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else { return }
            let r = await Task.detached(priority: .userInitiated) { try? renderer.render(snapshot, projectURL: url) }.value
            guard !Task.isCancelled, let self, let r else { return }
            self.mix = r
            self.masterPeakDB = gainToDB(Double(r.peak))
            self.clipCount = r.clippedSamples
            if self.isPlaying { self.restartPlayback() }
        }
    }

    public func togglePlay() { isPlaying ? stop() : play() }

    public func play() {
        guard let mix, mix.frames > 0 else { return }
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
            if playhead >= mix.duration { playhead = 0 }
            engine.connect(player, to: engine.mainMixerNode, format: AVAudioFormat(standardFormatWithSampleRate: mix.sampleRate, channels: 2))
            if !engine.isRunning { try engine.start() }
            schedule(from: playhead)
            player.play()
            isPlaying = true
            playStartTime = playhead
            tick = Timer.scheduledTimer(withTimeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.updatePlayhead() }
            }
        } catch {
            self.error = "Riproduzione: \(error.localizedDescription)"
        }
    }

    private func schedule(from t: Double) {
        guard let mix, let fmt = AVAudioFormat(standardFormatWithSampleRate: mix.sampleRate, channels: 2) else { return }
        let start = Int(t * mix.sampleRate)
        let n = mix.frames - start
        guard n > 0, let pb = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: AVAudioFrameCount(n)) else { return }
        pb.frameLength = AVAudioFrameCount(n)
        for c in 0 ..< 2 {
            mix.channels[c].withUnsafeBufferPointer { p in pb.floatChannelData![c].update(from: p.baseAddress! + start, count: n) }
        }
        player.stop()
        player.scheduleBuffer(pb, at: nil)
    }

    private func restartPlayback() {
        let t = playhead
        schedule(from: t)
        playStartTime = t
        player.play()
    }

    private func updatePlayhead() {
        guard isPlaying, let nt = player.lastRenderTime, let pt = player.playerTime(forNodeTime: nt), let mix else { return }
        playhead = playStartTime + Double(pt.sampleTime) / pt.sampleRate
        // meters: peak of the last 1/30 s
        let i = Int(playhead * mix.sampleRate), n = Int(mix.sampleRate / 30)
        if i < mix.frames {
            let s = mix.slice(from: i, count: n)
            meterPeak = s.channels.map { c in c.reduce(0) { max($0, abs($1)) } }
        }
        if playhead >= mix.duration { stop() }
    }

    public func stop() {
        player.stop()
        tick?.invalidate()
        tick = nil
        isPlaying = false
        meterPeak = [0, 0]
    }

    public func seek(_ t: Double) {
        playhead = max(0, t)
        if isPlaying { restartPlayback() }
    }

    // MARK: recording (microphone, after the system permission prompt)

    public func toggleRecord() async {
        if isRecording { finishRecording(); return }
        let granted = await AVAudioApplication.requestRecordPermission()
        guard granted else {
            error = "Accesso al microfono negato. Puoi abilitarlo in Impostazioni › Privacy › Microfono."
            return
        }
        do {
            stop()
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetoothHFP])
            try session.setActive(true)
            let input = engine.inputNode
            let fmt = input.outputFormat(forBus: 0)
            guard fmt.sampleRate > 0 else { throw StudioError.notAvailable("nessun ingresso audio") }
            let url = project.mediaURL.appendingPathComponent("Registrazione \(Int(Date().timeIntervalSince1970)).caf")
            let file = try AVAudioFile(forWriting: url, settings: fmt.settings)
            recorder = file
            recordURL = url
            recordStart = playhead
            input.installTap(onBus: 0, bufferSize: 4096, format: fmt) { buf, _ in
                try? file.write(from: buf)
            }
            if !engine.isRunning { try engine.start() }
            isRecording = true
        } catch {
            self.error = "Registrazione: \(error.localizedDescription)"
        }
    }

    private func finishRecording() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isRecording = false
        recorder = nil
        guard let url = recordURL else { return }
        let rel = "\(ProjectStore.mediaFolder)/\(url.lastPathComponent)"
        let start = recordStart
        Task {
            do {
                let m = try await Self.probe(url, path: rel)
                edit("Registrazione") { p in
                    p.media.append(m)
                    p.addClip(m, track: min(self.selectedTrack, p.tracks.count - 1), at: start)
                }
                await loadPeaks(rel)
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    // MARK: export

    public func export(_ format: AudioIO.ExportFormat, normalize: Bool) async {
        busy = "Mixdown ed esportazione…"
        defer { busy = nil }
        let snapshot = doc, url = project.url, renderer = renderer
        let out = StudioPaths.exportURL(name: project.header.name, ext: format.ext)
        do {
            try await Task.detached(priority: .userInitiated) {
                var b = try renderer.render(snapshot, projectURL: url)
                if normalize { b.normalize(to: -1) }
                try AudioIO.write(b, to: out, format: format)
            }.value
            exported = ExportedFile(out)
        } catch {
            self.error = error.localizedDescription
        }
    }
}
