import AVFoundation
import StudioCore
import UIKit

public enum MediaProbe {
    /// Reads duration, tracks and codec of a media file (no decoding).
    public static func probe(_ url: URL, relativePath: String) async throws -> MediaItem {
        let a = AVURLAsset(url: url, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])
        let duration: CMTime
        do { duration = try await a.load(.duration) } catch { throw StudioError.unsupportedFile("\(url.lastPathComponent): \(error.localizedDescription)") }
        let v = try await a.loadTracks(withMediaType: .video).first
        let au = try await a.loadTracks(withMediaType: .audio).first
        guard v != nil || au != nil, duration.seconds.isFinite, duration.seconds > 0 else {
            throw StudioError.unsupportedFile("\(url.lastPathComponent): nessuna traccia audio o video leggibile")
        }
        var item = MediaItem(path: relativePath, name: url.lastPathComponent, duration: duration.seconds, hasVideo: v != nil, hasAudio: au != nil)
        if let v {
            let size = try await v.load(.naturalSize)
            let t = try await v.load(.preferredTransform)
            let r = CGRect(origin: .zero, size: size).applying(t)
            item.width = abs(r.width)
            item.height = abs(r.height)
            if let fd = try await v.load(.formatDescriptions).first {
                item.videoCodec = fourCC(CMFormatDescriptionGetMediaSubType(fd))
            }
        }
        return item
    }

    public static func fourCC(_ code: FourCharCode) -> String {
        let bytes = [24, 16, 8, 0].map { UInt8((code >> $0) & 0xff) }
        return String(bytes: bytes, encoding: .ascii)?.trimmingCharacters(in: .whitespaces) ?? "\(code)"
    }

    /// Human name of a FourCC (only the codecs this app knows about; see docs/FORMATS.md).
    public static func codecName(_ fourCC: String?) -> String {
        switch fourCC {
        case "avc1", "avc3": "H.264"
        case "hvc1", "hev1": "HEVC"
        case "apco": "ProRes 422 Proxy"
        case "apcs": "ProRes 422 LT"
        case "apcn": "ProRes 422"
        case "apch": "ProRes 422 HQ"
        case "ap4h": "ProRes 4444"
        case "ap4x": "ProRes 4444 XQ"
        case "aprn", "aprh": "ProRes RAW"
        case nil: "—"
        case let s?: s
        }
    }

    /// Decodes the first video frame through AVAssetReader: proof the codec actually decodes here.
    public static func canDecodeVideo(_ url: URL) async -> Bool {
        let a = AVURLAsset(url: url)
        guard let t = try? await a.loadTracks(withMediaType: .video).first, let r = try? AVAssetReader(asset: a) else { return false }
        let out = AVAssetReaderTrackOutput(track: t, outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
        guard r.canAdd(out) else { return false }
        r.add(out)
        guard r.startReading() else { return false }
        let ok = out.copyNextSampleBuffer().flatMap(CMSampleBufferGetImageBuffer) != nil
        r.cancelReading()
        return ok
    }
}

/// Thumbnails and waveforms for the timeline, computed off the main thread and cached in memory.
public actor MediaPreviewCache {
    public static let shared = MediaPreviewCache()
    private var thumbs: [String: [CGImage]] = [:]
    private var waves: [String: [Float]] = [:]

    public func thumbnails(_ url: URL, count: Int, duration: Double) async -> [CGImage] {
        let key = "\(url.path)#\(count)"
        if let t = thumbs[key] { return t }
        let gen = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        gen.appliesPreferredTrackTransform = true
        gen.maximumSize = CGSize(width: 160, height: 90)
        gen.requestedTimeToleranceBefore = cm(0.5)
        gen.requestedTimeToleranceAfter = cm(0.5)
        var out: [CGImage] = []
        for i in 0 ..< count {
            let t = duration * (Double(i) + 0.5) / Double(count)
            if let img = try? await gen.image(at: cm(t)).image { out.append(img) }
        }
        thumbs[key] = out
        return out
    }

    /// Peak amplitudes (0…1) in `buckets` buckets over the whole file.
    public func waveform(_ url: URL, buckets: Int = 400) async -> [Float] {
        let key = "\(url.path)#\(buckets)"
        if let w = waves[key] { return w }
        let w = (try? await Self.readPeaks(url, buckets: buckets)) ?? []
        waves[key] = w
        return w
    }

    static func readPeaks(_ url: URL, buckets: Int) async throws -> [Float] {
        let a = AVURLAsset(url: url)
        guard let t = try await a.loadTracks(withMediaType: .audio).first else { return [] }
        let duration = try await a.load(.duration).seconds
        let r = try AVAssetReader(asset: a)
        let rate = 8000.0
        let out = AVAssetReaderTrackOutput(track: t, outputSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM, AVLinearPCMBitDepthKey: 32, AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsNonInterleaved: false, AVNumberOfChannelsKey: 1, AVSampleRateKey: rate,
        ])
        r.add(out)
        r.startReading()
        let total = max(1, Int(duration * rate))
        let per = max(1, total / buckets)
        var peaks = [Float](repeating: 0, count: buckets)
        var index = 0
        while let sb = out.copyNextSampleBuffer(), let bb = CMSampleBufferGetDataBuffer(sb) {
            var len = 0
            var ptr: UnsafeMutablePointer<CChar>?
            CMBlockBufferGetDataPointer(bb, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &len, dataPointerOut: &ptr)
            guard let ptr else { continue }
            ptr.withMemoryRebound(to: Float.self, capacity: len / 4) { f in
                for i in 0 ..< len / 4 {
                    let b = min(buckets - 1, index / per)
                    peaks[b] = max(peaks[b], abs(f[i]))
                    index += 1
                }
            }
        }
        return peaks
    }
}

public enum ProxyMaker {
    /// Writes a 960×540 H.264 proxy into the project's Media/Proxies folder; returns its relative path.
    public static func makeProxy(for item: MediaItem, projectURL: URL) async throws -> String {
        let src = AVURLAsset(url: projectURL.appendingPathComponent(item.path))
        let dir = projectURL.appendingPathComponent("Media/Proxies", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let name = (item.path as NSString).lastPathComponent
        let rel = "Media/Proxies/\((name as NSString).deletingPathExtension)-proxy.mp4"
        let dest = projectURL.appendingPathComponent(rel)
        try? FileManager.default.removeItem(at: dest)
        guard let s = AVAssetExportSession(asset: src, presetName: AVAssetExportPreset960x540) else {
            throw StudioError.notAvailable("preset proxy 960×540")
        }
        try await s.export(to: dest, as: .mp4)
        return rel
    }
}
