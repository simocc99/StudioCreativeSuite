import Foundation
import StudioCore

public struct AudioProject: ProjectPayload {
    public static let kind = StudioModule.audio
    public static let formatVersion = 1

    public var sampleRate: Double = 48000
    public var tracks: [AudioTrackDoc] = [AudioTrackDoc(name: "Traccia 1"), AudioTrackDoc(name: "Traccia 2")]
    public var media: [AudioMedia] = []
    public var masterGainDB: Double = 0

    public init() {}

    public var duration: Double { tracks.flatMap(\.clips).map(\.end).max() ?? 0 }
}

public struct AudioMedia: Codable, Hashable, Identifiable, Sendable {
    public var id: String { path }
    public var path: String
    public var name: String
    public var duration: Double
    public var sampleRate: Double
    public var channels: Int
}

public struct EQSettings: Codable, Hashable, Sendable {
    public var lowGainDB: Double = 0 // shelf @ 120 Hz
    public var midGainDB: Double = 0 // peak
    public var midFreq: Double = 1000
    public var highGainDB: Double = 0 // shelf @ 8 kHz
    public var highPassHz: Double = 0 // 0 = off
    public var lowPassHz: Double = 0 // 0 = off
    public init() {}
    public var isFlat: Bool { self == EQSettings() }
}

public struct AutomationPoint: Codable, Hashable, Sendable {
    public var time: Double
    public var gainDB: Double
    public init(time: Double, gainDB: Double) {
        self.time = time
        self.gainDB = gainDB
    }
}

public struct AudioTrackDoc: Codable, Hashable, Identifiable, Sendable {
    public var id = UUID()
    public var name: String
    public var clips: [AudioClipDoc] = []
    public var volumeDB: Double = 0
    public var pan: Double = 0 // -1 … 1
    public var muted = false
    public var solo = false
    public var eq = EQSettings()
    /// Noise gate threshold in dBFS (nil = off): a downward expander, not a noise remover.
    public var gateThresholdDB: Double?
    public var automation: [AutomationPoint] = []

    public init(name: String) { self.name = name }

    /// Automation gain (dB) at time t: linear between points, flat outside.
    public func automationDB(at t: Double) -> Double {
        let pts = automation.sorted { $0.time < $1.time }
        guard let f = pts.first, let l = pts.last else { return 0 }
        if t <= f.time { return f.gainDB }
        if t >= l.time { return l.gainDB }
        for (a, b) in zip(pts, pts.dropFirst()) where t >= a.time && t <= b.time {
            return a.gainDB + (b.gainDB - a.gainDB) * (t - a.time) / max(b.time - a.time, 1e-9)
        }
        return 0
    }
}

public struct AudioClipDoc: Codable, Hashable, Identifiable, Sendable {
    public var id = UUID()
    public var media: String
    public var start: Double
    public var sourceStart: Double = 0
    public var duration: Double
    public var gainDB: Double = 0
    public var fadeIn: Double = 0
    public var fadeOut: Double = 0
    public var reversed = false

    public init(media: String, start: Double, duration: Double) {
        self.media = media
        self.start = start
        self.duration = duration
    }

    public var end: Double { start + duration }
}

public extension AudioProject {
    func locate(_ id: UUID) -> (Int, Int)? {
        for (ti, t) in tracks.enumerated() {
            if let ci = t.clips.firstIndex(where: { $0.id == id }) { return (ti, ci) }
        }
        return nil
    }

    @discardableResult
    mutating func addClip(_ m: AudioMedia, track: Int, at time: Double? = nil) -> UUID {
        let start = time ?? (tracks[track].clips.map(\.end).max() ?? 0)
        let c = AudioClipDoc(media: m.path, start: start, duration: m.duration)
        tracks[track].clips.append(c)
        tracks[track].clips.sort { $0.start < $1.start }
        return c.id
    }

    @discardableResult
    mutating func split(_ id: UUID, at t: Double) -> UUID? {
        guard let (ti, ci) = locate(id) else { return nil }
        let c = tracks[ti].clips[ci]
        guard t > c.start + 0.001, t < c.end - 0.001 else { return nil }
        var l = c, r = c
        l.duration = t - c.start
        l.fadeOut = 0
        r.id = UUID()
        r.start = t
        r.sourceStart = c.sourceStart + (t - c.start)
        r.duration = c.end - t
        r.fadeIn = 0
        tracks[ti].clips[ci] = l
        tracks[ti].clips.insert(r, at: ci + 1)
        return r.id
    }

    /// Removes the time range [a, b) from every unlocked clip on `track` (nil = all tracks), optionally closing the gap.
    mutating func cut(from a: Double, to b: Double, track: Int? = nil, ripple: Bool) {
        guard b > a else { return }
        for ti in tracks.indices where track == nil || track == ti {
            for c in tracks[ti].clips where c.start < b && c.end > a {
                if c.start < a { split(c.id, at: a) }
            }
            for c in tracks[ti].clips where c.start < b && c.end > b { split(c.id, at: b) }
            tracks[ti].clips.removeAll { $0.start >= a - 1e-9 && $0.end <= b + 1e-9 }
            if ripple {
                for i in tracks[ti].clips.indices where tracks[ti].clips[i].start >= b - 1e-9 {
                    tracks[ti].clips[i].start -= (b - a)
                }
            }
        }
    }

    mutating func updateClip(_ id: UUID, _ f: (inout AudioClipDoc) -> Void) {
        guard let (ti, ci) = locate(id) else { return }
        f(&tracks[ti].clips[ci])
    }
}

import AVFoundation

public enum AudioMediaProbe {
    /// Reads duration / rate / channels of an audio file synchronously (header only).
    public static func probeSync(_ url: URL, path: String) throws -> AudioMedia {
        let f: AVAudioFile
        do { f = try AVAudioFile(forReading: url) } catch {
            throw StudioError.unsupportedFile("\(url.lastPathComponent): non è un file audio leggibile")
        }
        let sr = f.fileFormat.sampleRate
        return AudioMedia(path: path, name: url.lastPathComponent, duration: Double(f.length) / sr, sampleRate: sr, channels: Int(f.fileFormat.channelCount))
    }
}
