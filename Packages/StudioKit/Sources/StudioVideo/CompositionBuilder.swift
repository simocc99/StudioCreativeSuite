import AVFoundation
import StudioCore

func cm(_ s: Double) -> CMTime { CMTime(seconds: s, preferredTimescale: 600) }

/// Turns a `VideoProject` into an AVFoundation composition + video composition + audio mix.
public struct BuiltComposition: @unchecked Sendable {
    public let composition: AVMutableComposition
    public let videoComposition: AVMutableVideoComposition?
    public let audioMix: AVMutableAudioMix
    public let duration: Double

    public func playerItem() -> AVPlayerItem {
        let item = AVPlayerItem(asset: composition.copy() as! AVAsset)
        item.videoComposition = videoComposition
        item.audioMix = audioMix
        item.audioTimePitchAlgorithm = .spectral
        return item
    }
}

public enum CompositionBuilder {
    public static func build(_ project: VideoProject, projectURL: URL, useProxies: Bool = false) async throws -> BuiltComposition {
        let comp = AVMutableComposition()
        var assets: [String: AVURLAsset] = [:]
        func asset(_ path: String) -> AVURLAsset {
            if let a = assets[path] { return a }
            var rel = path
            if useProxies, let p = project.media.first(where: { $0.path == path })?.proxyPath { rel = p }
            let a = AVURLAsset(url: projectURL.appendingPathComponent(rel), options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])
            assets[path] = a
            return a
        }

        var layersByClip: [UUID: (CMPersistentTrackID, CGImagePropertyOrientation)] = [:]
        var audioParams: [AVMutableAudioMixInputParameters] = []

        for track in project.tracks {
            let sorted = track.clips.sorted { $0.start < $1.start }
            // A/B composition tracks so overlapping clips (cross dissolves) can play together
            var videoAB: [AVMutableCompositionTrack] = []
            var audioAB: [AVMutableCompositionTrack] = []
            var videoEnd: [Double] = [0, 0]
            var audioEnd: [Double] = [0, 0]
            var audioAux: [AVMutableAudioMixInputParameters?] = [nil, nil]

            for (i, clip) in sorted.enumerated() {
                let slot = i % 2
                let a = asset(clip.media)
                let srcRange = CMTimeRange(start: cm(clip.sourceStart), duration: cm(clip.sourceDuration))

                if track.kind == .video, clip.hasVideo, !track.hidden,
                   let vt = try await a.loadTracks(withMediaType: .video).first {
                    while videoAB.count <= slot {
                        guard let t = comp.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else {
                            throw StudioError.engine("impossibile creare una traccia video")
                        }
                        videoAB.append(t)
                    }
                    let ct = videoAB[slot]
                    try insert(ct, range: srcRange, of: vt, at: clip.start, trackEnd: &videoEnd[slot], clip: clip)
                    let transform = try await vt.load(.preferredTransform)
                    layersByClip[clip.id] = (ct.trackID, CGImagePropertyOrientation(transform))
                }

                if clip.hasAudio, !track.muted, let at = try await a.loadTracks(withMediaType: .audio).first {
                    while audioAB.count <= slot {
                        guard let t = comp.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else {
                            throw StudioError.engine("impossibile creare una traccia audio")
                        }
                        audioAB.append(t)
                        audioAux[slot] = AVMutableAudioMixInputParameters(track: t)
                    }
                    try insert(audioAB[slot], range: srcRange, of: at, at: clip.start, trackEnd: &audioEnd[slot], clip: clip)
                    if let p = audioAux[slot] { applyVolume(p, clip: clip, trackVolume: track.volume) }
                }
            }
            audioParams += audioAux.compactMap { $0 }
        }

        let duration = project.duration
        // titles may outlast the clips: pad a video track so the composition (and its instructions) cover them
        if duration > 0, comp.duration.seconds < duration - 1e-3 {
            let pad = comp.tracks(withMediaType: .video).first ?? comp.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)
            if let pad {
                let end = pad.timeRange.end.seconds.isFinite ? pad.timeRange.end.seconds : 0
                pad.insertEmptyTimeRange(CMTimeRange(start: cm(end), duration: cm(duration - end)))
            }
        }
        let mix = AVMutableAudioMix()
        mix.inputParameters = audioParams

        var vc: AVMutableVideoComposition?
        if duration > 0 {
            let v = AVMutableVideoComposition()
            v.customVideoCompositorClass = StudioVideoCompositor.self
            v.renderSize = project.renderSize
            v.frameDuration = CMTime(value: 1, timescale: CMTimeScale(max(1, project.frameRate)))
            v.instructions = instructions(project, layers: layersByClip, duration: duration)
            vc = v
        }
        return BuiltComposition(composition: comp, videoComposition: vc, audioMix: mix, duration: duration)
    }

    private static func insert(_ ct: AVMutableCompositionTrack, range: CMTimeRange, of src: AVAssetTrack, at start: Double, trackEnd: inout Double, clip: Clip) throws {
        if start > trackEnd + 1e-6 {
            ct.insertEmptyTimeRange(CMTimeRange(start: cm(trackEnd), duration: cm(start - trackEnd)))
        }
        let at = cm(max(start, trackEnd))
        try ct.insertTimeRange(range, of: src, at: at)
        if abs(clip.speed - 1) > 1e-6 {
            ct.scaleTimeRange(CMTimeRange(start: at, duration: range.duration), toDuration: cm(clip.duration))
        }
        trackEnd = max(start, trackEnd) + clip.duration
    }

    private static func applyVolume(_ p: AVMutableAudioMixInputParameters, clip: Clip, trackVolume: Double) {
        let v = Float(clip.volume * trackVolume)
        let fin = max(clip.fadeIn, clip.transitionIn)
        if fin > 0 {
            p.setVolumeRamp(fromStartVolume: 0, toEndVolume: v, timeRange: CMTimeRange(start: cm(clip.start), duration: cm(fin)))
        } else {
            p.setVolume(v, at: cm(clip.start))
        }
        if clip.fadeOut > 0 {
            p.setVolumeRamp(fromStartVolume: v, toEndVolume: 0, timeRange: CMTimeRange(start: cm(clip.end - clip.fadeOut), duration: cm(clip.fadeOut)))
        }
    }

    /// One instruction per interval between edit points, covering [0, duration) without gaps.
    static func instructions(_ project: VideoProject, layers: [UUID: (CMPersistentTrackID, CGImagePropertyOrientation)], duration: Double) -> [StudioInstruction] {
        var cuts: Set<Double> = [0, duration]
        for c in project.tracks.flatMap(\.clips) { cuts.insert(c.start); cuts.insert(c.end) }
        for t in project.titles { cuts.insert(t.start); cuts.insert(t.start + t.duration) }
        let points = cuts.filter { $0 >= 0 && $0 <= duration }.sorted()
        var out: [StudioInstruction] = []
        let fps = Double(max(1, project.frameRate))
        for (a, b) in zip(points, points.dropFirst()) where b - a > 0.5 / fps / 100 {
            let mid = (a + b) / 2
            var specs: [LayerSpec] = []
            for (ti, track) in project.tracks.enumerated() where track.kind == .video && !track.hidden {
                for clip in project.activeClips(track: ti, at: mid).sorted(by: { $0.start < $1.start }) {
                    if let (id, o) = layers[clip.id] { specs.append(LayerSpec(trackID: id, clip: clip, orientation: o)) }
                }
            }
            let titles = project.titles.filter { $0.start < b && $0.start + $0.duration > a }
            let range = CMTimeRange(start: cm(a), end: cm(b))
            out.append(StudioInstruction(timeRange: range, layers: specs, titles: titles, renderSize: project.renderSize))
        }
        // make the ranges exactly contiguous in CMTime
        for i in out.indices.dropFirst() where out[i].timeRange.start != out[i - 1].timeRange.end {
            let prev = out[i - 1]
            out[i - 1] = StudioInstruction(timeRange: CMTimeRange(start: prev.timeRange.start, end: out[i].timeRange.start),
                                           layers: prev.layers, titles: prev.titles, renderSize: prev.renderSize)
        }
        return out
    }
}
