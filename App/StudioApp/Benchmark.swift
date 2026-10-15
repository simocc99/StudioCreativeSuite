import CoreImage
import Foundation
import os
import StudioAudio
import StudioCore
import StudioPaint
import StudioPhoto
import StudioVideo
import SwiftUI

/// Repeatable workloads for profiling on the device. Started only by the launch argument
/// `-StudioBenchmark YES` (Scripts/run-benchmark.sh); never in normal use.
/// Writes Documents/benchmark.json with timings and peak memory (phys_footprint).
@MainActor
@Observable
final class Benchmark {
    static var requested: Bool { UserDefaults.standard.bool(forKey: "StudioBenchmark") }

    var status = "In preparazione…"
    var done = false
    private let log = Logger(subsystem: "studio.benchmark", category: "bench")
    private var results: [[String: Any]] = []

    nonisolated static func footprintMB() -> Double {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let kr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count) }
        }
        return kr == KERN_SUCCESS ? Double(info.phys_footprint) / 1_048_576 : -1
    }

    /// Runs `work`, sampling memory every 20 ms; records duration and peak footprint.
    private func measure(_ name: String, detail: String = "", _ work: () async throws -> String) async {
        status = name
        print("BENCH start \(name) footprint \(Int(Self.footprintMB())) MB")
        fflush(stdout)
        let sampler = PeakSampler(label: name)
        sampler.start()
        let before = Self.footprintMB()
        let t0 = ContinuousClock.now
        var note = detail, ok = true
        do { let r = try await work(); if !r.isEmpty { note = r } } catch { ok = false; note = error.localizedDescription }
        let ms = Double((ContinuousClock.now - t0).components.attoseconds) / 1e15 + Double((ContinuousClock.now - t0).components.seconds) * 1000
        let peak = sampler.stop()
        log.info("BENCH \(name, privacy: .public): \(ms, format: .fixed(precision: 1)) ms, peak \(peak, format: .fixed(precision: 0)) MB")
        results.append(["name": name, "ms": (ms * 10).rounded() / 10, "peakMB": peak.rounded(), "startMB": before.rounded(), "ok": ok, "note": note])
        print("BENCH end \(name) \(Int(ms)) ms peak \(Int(peak)) MB ok=\(ok) \(note)")
        fflush(stdout)
    }

    func run() async {
        let docs = StudioPaths.documents
        let work = FileManager.default.temporaryDirectory.appendingPathComponent("bench", isDirectory: true)
        try? FileManager.default.removeItem(at: work)
        try? FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        let raws = ((try? FileManager.default.contentsOfDirectory(at: docs.appendingPathComponent("TestRAW"), includingPropertiesForKeys: nil)) ?? [])
            .sorted { $0.lastPathComponent < $1.lastPathComponent }

        // RAW: open (decode to a 2400 px preview), interactive renders, full-resolution export
        for raw in raws {
            var engine: PhotoEngine?
            await measure("raw.open \(raw.lastPathComponent)") {
                let e = try await PhotoEngine.open(raw, previewEdge: 2400)
                engine = e
                return "\(e.info.rawFormat ?? "?") anteprima \(e.info.previewWidth)×\(e.info.previewHeight)"
            }
            guard let e = engine else { continue }
            await measure("raw.render10 \(raw.lastPathComponent)") {
                // ten renders as a slider drag would issue them (draft quality, 2732×2048 viewport)
                var s = e.defaultSettings
                for i in 0 ..< 10 {
                    s[path: "light.exposure"] = .number(Double(i) * 0.1)
                    _ = try await e.render(s, maxSize: CGSize(width: 2732, height: 2048), draft: true)
                }
                return "10 render draft"
            }
            await measure("raw.exportFullAdaptive \(raw.lastPathComponent)") {
                let (r, tiled) = try await e.exportAdaptive(e.defaultSettings, to: work.appendingPathComponent("x.jpg"), format: .jpg, sourceURL: raw)
                return "JPEG \(r.width)×\(r.height) \(tiled ? "a tasselli" : "pipeline completa")"
            }
            await measure("raw.exportFullTiled \(raw.lastPathComponent)") {
                let img = try await e.renderTiled(e.defaultSettings)
                return "render \(img.width)×\(img.height)"
            }
        }

        // Video: two 10 s 1080p clips → HEVC 1080p export through the custom compositor
        let a = work.appendingPathComponent("a.mp4"), b = work.appendingPathComponent("b.mp4")
        await measure("video.makeClips", detail: "2 × 10 s 1080p H.264 (AVAssetWriter)") {
            for (u, c) in [(a, RGBAColor(1, 0, 0)), (b, RGBAColor(0, 0, 1))] {
                try await FrameVideoWriter.write(to: u, width: 1920, height: 1080, fps: 30, frameCount: 300) { i, ctx in
                    ctx.setFillColor(c.cgColor)
                    ctx.fill(CGRect(x: 0, y: 0, width: 1920, height: 1080))
                    ctx.setFillColor(UIColor.white.cgColor)
                    ctx.fill(CGRect(x: Double(i) * 5, y: 500, width: 120, height: 120))
                }
            }
            return ""
        }
        await measure("video.exportHEVC1080", detail: "20 s, dissolvenza, titolo, keyframe") {
            var p = VideoProject()
            p.media = [try await MediaProbe.probe(a, relativePath: "a.mp4"), try await MediaProbe.probe(b, relativePath: "b.mp4")]
            let c1 = p.addClip(p.media[0], track: 0)!
            let c2 = p.addClip(p.media[1], track: 0)!
            p.setTransition(c2, 1)
            p.update(c1) { $0.keyframes = [ClipKeyframe(time: 0, value: ClipTransform()), ClipKeyframe(time: 9, value: { var t = ClipTransform(); t.scale = 1.5; t.rotation = 10; return t }())] }
            p.addTitle("Benchmark", at: 2, duration: 5)
            let built = try await CompositionBuilder.build(p, projectURL: work)
            let preset: VideoExportPreset = await VideoExporter.availablePresets(for: built).contains(.hevc_1080) ? .hevc_1080 : .h264_1080
            try await VideoExporter.export(built, preset: preset, to: work.appendingPathComponent("out.\(preset.fileExtension)")) { _ in }
            return "\(preset.title), \(String(format: "%.1f", p.duration)) s"
        }

        // Audio: 4 tracks × 60 s, EQ + gate + automation, mixdown
        await measure("audio.mix4x60s") {
            let src = work.appendingPathComponent("tone.wav")
            let n = 48000 * 60
            var c = [Float](repeating: 0, count: n)
            let w: Double = 2 * Double.pi * 220 / 48000
            for i in 0 ..< n { c[i] = Float(0.3 * sin(w * Double(i))) }
            try AudioIO.write(PCMBuffer(sampleRate: 48000, channels: [c, c]), to: src, format: .wav16)
            var p = AudioProject()
            let m = try AudioMediaProbe.probeSync(src, path: "tone.wav")
            p.media = [m]
            p.tracks = (0 ..< 4).map { AudioTrackDoc(name: "T\($0)") }
            for t in 0 ..< 4 {
                p.addClip(m, track: t)
                p.tracks[t].eq.lowGainDB = 3
                p.tracks[t].eq.highPassHz = 80
                p.tracks[t].gateThresholdDB = -50
                p.tracks[t].automation = [AutomationPoint(time: 0, gainDB: -6), AutomationPoint(time: 60, gainDB: 0)]
            }
            let r = try await Task.detached { try AudioRenderer().render(p, projectURL: work) }.value
            return String(format: "%.0f s stereo, picco %.1f dBFS", r.duration, gainToDB(Double(r.peak)))
        }

        // Raster: 6000×4000 canvas, image + fill layers, blend + filters, full render
        await measure("raster.compose6000x4000") {
            var p = RasterProject()
            p.width = 6000
            p.height = 4000
            var fill = RasterLayer(name: "f", content: .fill(RGBAColor(0.9, 0.5, 0.2)))
            fill.blend = .multiply
            fill.filters = [RasterFilter(.gaussianBlur), RasterFilter(.vignette)]
            var paint = RasterLayer(name: "p", content: .fill(RGBAColor(0.2, 0.4, 0.9)))
            paint.blend = .softLight
            paint.opacity = 0.6
            p.layers = [fill, paint]
            let c = RasterCompositor(projectURL: work)
            let img = try await Task.detached { () throws -> CGImage in
                guard let i = c.render(p) else { throw StudioError.engine("render") }
                return i
            }.value
            return "\(img.width)×\(img.height)"
        }

        // Paint: a long stroke on an iPad-sized canvas
        await measure("paint.stroke2000") {
            let layer = BitmapLayer(width: 2732, height: 2048)
            var brush = Brush(kind: .round)
            brush.size = 60
            let e = BrushEngine(brush: brush)
            _ = e.begin(StrokeSample(point: CGPoint(x: 10, y: 10)), in: layer.context)
            for i in 1 ... 2000 {
                let t = Double(i) / 2000
                let x: Double = 10 + t * 2700
                let y: Double = 1024 + sin(t * 30) * 900
                let pr: Double = 0.5 + 0.5 * sin(t * 50)
                _ = e.move(to: StrokeSample(point: CGPoint(x: x, y: y), pressure: pr), in: layer.context)
            }
            _ = layer.makeImage()
            return "2000 campioni, pennello 60 px"
        }

        let device = UIDevice.current
        let out: [String: Any] = ["device": device.model, "system": "\(device.systemName) \(device.systemVersion)",
                                  "physicalMemoryGB": Double(ProcessInfo.processInfo.physicalMemory) / 1_073_741_824,
                                  "date": ISO8601DateFormatter().string(from: .now), "results": results]
        if let d = try? JSONSerialization.data(withJSONObject: out, options: [.prettyPrinted, .sortedKeys]) {
            try? d.write(to: docs.appendingPathComponent("benchmark.json"))
        }
        try? FileManager.default.removeItem(at: work)
        status = "Completato: \(results.count) misure in Documents/benchmark.json"
        log.info("BENCH DONE")
        done = true
    }
}

/// Samples the process footprint on a background thread and keeps the maximum.
final class PeakSampler: @unchecked Sendable {
    private var peak = 0.0
    private var running = false
    private let lock = NSLock()
    private let label: String
    init(label: String) { self.label = label }

    func start() {
        lock.withLock { running = true; peak = Benchmark.footprintMB() }
        Thread.detachNewThread { [self] in
            while lock.withLock({ running }) {
                let m = Benchmark.footprintMB()
                let jump = lock.withLock { () -> Bool in
                    let j = m > peak + 500
                    peak = max(peak, m)
                    return j
                }
                if jump { print("BENCH mem \(label) \(Int(m)) MB, disponibili \(os_proc_available_memory() / 1_048_576) MB"); fflush(stdout) }
                Thread.sleep(forTimeInterval: 0.02)
            }
        }
    }

    func stop() -> Double {
        lock.withLock { running = false; return max(peak, Benchmark.footprintMB()) }
    }
}

struct BenchmarkView: View {
    @State private var bench = Benchmark()
    var body: some View {
        VStack(spacing: 16) {
            if !bench.done { ProgressView() }
            Text("Benchmark Studio").font(.title.bold())
            Text(bench.status).font(.callout.monospaced()).multilineTextAlignment(.center)
        }
        .padding()
        .task { await bench.run() }
    }
}
