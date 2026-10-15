import AVFoundation
import Foundation
import StudioCore

public enum AudioIO {
    /// Decodes any file AVAudioFile reads (WAV, AIFF, CAF, M4A/AAC, MP3, ALAC, FLAC…) to stereo float at `sampleRate`.
    public static func read(_ url: URL, sampleRate: Double) throws -> PCMBuffer {
        let file: AVAudioFile
        do { file = try AVAudioFile(forReading: url) } catch {
            throw StudioError.unsupportedFile("\(url.lastPathComponent): \(error.localizedDescription)")
        }
        let src = file.processingFormat
        guard let dstFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 2, interleaved: false),
              let converter = AVAudioConverter(from: src, to: dstFormat)
        else { throw StudioError.unsupportedFile("formato audio non convertibile") }
        if src.channelCount == 1 { converter.channelMap = [0, 0] }
        let inFrames = AVAudioFrameCount(file.length)
        guard let inBuf = AVAudioPCMBuffer(pcmFormat: src, frameCapacity: max(1, inFrames)) else { throw StudioError.io("memoria insufficiente") }
        try file.read(into: inBuf)
        let outCap = AVAudioFrameCount(Double(inFrames) * sampleRate / src.sampleRate) + 4096
        guard let outBuf = AVAudioPCMBuffer(pcmFormat: dstFormat, frameCapacity: outCap) else { throw StudioError.io("memoria insufficiente") }
        var fed = false
        var err: NSError?
        let status = converter.convert(to: outBuf, error: &err) { _, s in
            if fed { s.pointee = .endOfStream; return nil }
            fed = true
            s.pointee = .haveData
            return inBuf
        }
        if status == .error { throw StudioError.engine(err?.localizedDescription ?? "conversione audio") }
        let n = Int(outBuf.frameLength)
        let chans = (0 ..< 2).map { c in Array(UnsafeBufferPointer(start: outBuf.floatChannelData![c], count: n)) }
        return PCMBuffer(sampleRate: sampleRate, channels: chans)
    }

    public enum ExportFormat: String, CaseIterable, Identifiable, Sendable {
        case wav16, wav24, aiff, m4a, caf
        public var id: String { rawValue }
        public var title: String {
            switch self {
            case .wav16: "WAV 16 bit"
            case .wav24: "WAV 24 bit"
            case .aiff: "AIFF 16 bit"
            case .m4a: "AAC 256 kbps (.m4a)"
            case .caf: "CAF 32 bit float"
            }
        }
        public var ext: String {
            switch self {
            case .wav16, .wav24: "wav"
            case .aiff: "aiff"
            case .m4a: "m4a"
            case .caf: "caf"
            }
        }
    }

    public static func write(_ buf: PCMBuffer, to url: URL, format: ExportFormat) throws {
        var settings: [String: Any] = [AVSampleRateKey: buf.sampleRate, AVNumberOfChannelsKey: buf.channels.count]
        switch format {
        case .wav16, .aiff:
            settings[AVFormatIDKey] = kAudioFormatLinearPCM
            settings[AVLinearPCMBitDepthKey] = 16
            settings[AVLinearPCMIsFloatKey] = false
            settings[AVLinearPCMIsBigEndianKey] = format == .aiff
        case .wav24:
            settings[AVFormatIDKey] = kAudioFormatLinearPCM
            settings[AVLinearPCMBitDepthKey] = 24
            settings[AVLinearPCMIsFloatKey] = false
            settings[AVLinearPCMIsBigEndianKey] = false
        case .caf:
            settings[AVFormatIDKey] = kAudioFormatLinearPCM
            settings[AVLinearPCMBitDepthKey] = 32
            settings[AVLinearPCMIsFloatKey] = true
        case .m4a:
            settings[AVFormatIDKey] = kAudioFormatMPEG4AAC
            settings[AVEncoderBitRateKey] = 256_000
        }
        try? FileManager.default.removeItem(at: url)
        let f = try AVAudioFile(forWriting: url, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
        guard let fmt = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: buf.sampleRate, channels: AVAudioChannelCount(buf.channels.count), interleaved: false) else { return }
        let chunk = 65536
        var pos = 0
        while pos < buf.frames {
            let n = min(chunk, buf.frames - pos)
            guard let pb = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: AVAudioFrameCount(n)) else { break }
            pb.frameLength = AVAudioFrameCount(n)
            for c in buf.channels.indices {
                buf.channels[c].withUnsafeBufferPointer { p in
                    pb.floatChannelData![c].update(from: p.baseAddress! + pos, count: n)
                }
            }
            try f.write(from: pb)
            pos += n
        }
    }
}

/// Offline mixer: clips → per-track (gain, fades, EQ, gate, automation, pan, volume) → master.
public final class AudioRenderer: @unchecked Sendable {
    private var cache: [String: PCMBuffer] = [:]
    private let lock = NSLock()

    public init() {}

    func source(_ path: String, projectURL: URL, sampleRate: Double) throws -> PCMBuffer {
        let key = "\(path)@\(sampleRate)"
        lock.lock()
        if let b = cache[key] { lock.unlock(); return b }
        lock.unlock()
        let b = try AudioIO.read(projectURL.appendingPathComponent(path), sampleRate: sampleRate)
        lock.lock()
        cache[key] = b
        lock.unlock()
        return b
    }

    public func clipBuffer(_ clip: AudioClipDoc, projectURL: URL, sampleRate: Double) throws -> PCMBuffer {
        let src = try source(clip.media, projectURL: projectURL, sampleRate: sampleRate)
        var b = src.slice(from: Int(clip.sourceStart * sampleRate), count: Int(clip.duration * sampleRate))
        if clip.reversed { b.reverse() }
        if clip.gainDB != 0 { b.applyGain(Float(dbToGain(clip.gainDB))) }
        b.fade(inSeconds: clip.fadeIn, outSeconds: clip.fadeOut)
        return b
    }

    public func render(_ project: AudioProject, projectURL: URL, isCancelled: () -> Bool = { false }) throws -> PCMBuffer {
        let sr = project.sampleRate
        let frames = Int(ceil(project.duration * sr))
        var master = PCMBuffer(sampleRate: sr, channelCount: 2, frames: frames)
        let anySolo = project.tracks.contains { $0.solo }
        for track in project.tracks where !track.muted && (!anySolo || track.solo) {
            if isCancelled() { throw StudioError.cancelled }
            var bus = PCMBuffer(sampleRate: sr, channelCount: 2, frames: frames)
            for clip in track.clips {
                let b = try clipBuffer(clip, projectURL: projectURL, sampleRate: sr)
                let off = Int(clip.start * sr)
                for c in 0 ..< 2 {
                    let n = min(b.frames, frames - off)
                    guard n > 0 else { continue }
                    for i in 0 ..< n { bus.channels[c][off + i] += b.channels[c][i] }
                }
            }
            AudioEffects.applyEQ(track.eq, to: &bus)
            if let thr = track.gateThresholdDB { AudioEffects.gate(&bus, thresholdDB: thr) }
            // volume + equal-power pan + automation
            let base = dbToGain(track.volumeDB)
            let angle = (track.pan + 1) * .pi / 4
            let lg = Float(base * cos(angle) * sqrt(2)), rg = Float(base * sin(angle) * sqrt(2))
            let hasAuto = !track.automation.isEmpty
            let block = 256
            var i = 0
            while i < frames {
                let a: Float = hasAuto ? Float(dbToGain(track.automationDB(at: Double(i) / sr))) : 1
                let end = min(frames, i + block)
                for j in i ..< end {
                    master.channels[0][j] += bus.channels[0][j] * lg * a
                    master.channels[1][j] += bus.channels[1][j] * rg * a
                }
                i = end
            }
        }
        if project.masterGainDB != 0 { master.applyGain(Float(dbToGain(project.masterGainDB))) }
        return master
    }

    public func invalidate() {
        lock.lock()
        cache.removeAll()
        lock.unlock()
    }
}
