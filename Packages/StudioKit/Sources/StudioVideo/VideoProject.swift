import CoreGraphics
import Foundation
import StudioCore

/// Multitrack edit. Times are seconds on the timeline (Double; converted to CMTime at timescale 600).
public struct VideoProject: ProjectPayload {
    public static let kind = StudioModule.video
    public static let formatVersion = 1

    public var tracks: [VideoTrack] = [VideoTrack(kind: .video, name: "V1"), VideoTrack(kind: .video, name: "V2"), VideoTrack(kind: .audio, name: "A1")]
    public var titles: [TitleClip] = []
    public var markers: [Marker] = []
    public var media: [MediaItem] = []
    public var renderWidth: Int = 1920
    public var renderHeight: Int = 1080
    public var frameRate: Int = 30

    public init() {}

    public var duration: Double {
        let c = tracks.flatMap(\.clips).map(\.end).max() ?? 0
        let t = titles.map { $0.start + $0.duration }.max() ?? 0
        return max(c, t)
    }

    public var renderSize: CGSize { CGSize(width: renderWidth, height: renderHeight) }
}

public struct MediaItem: Codable, Hashable, Identifiable, Sendable {
    public var id: String { path }
    /// Relative to the project folder.
    public var path: String
    public var name: String
    public var duration: Double
    public var hasVideo: Bool
    public var hasAudio: Bool
    public var width: Double
    public var height: Double
    /// FourCC of the video codec (avc1, hvc1, apcn, aprn…), if any.
    public var videoCodec: String?
    public var proxyPath: String?

    public init(path: String, name: String, duration: Double, hasVideo: Bool, hasAudio: Bool, width: Double = 0, height: Double = 0, videoCodec: String? = nil) {
        self.path = path
        self.name = name
        self.duration = duration
        self.hasVideo = hasVideo
        self.hasAudio = hasAudio
        self.width = width
        self.height = height
        self.videoCodec = videoCodec
    }
}

public enum TrackKind: String, Codable, Sendable { case video, audio }

public struct VideoTrack: Codable, Hashable, Identifiable, Sendable {
    public var id = UUID()
    public var kind: TrackKind
    public var name: String
    public var clips: [Clip] = []
    public var muted = false
    public var hidden = false
    public var locked = false
    public var volume: Double = 1

    public init(kind: TrackKind, name: String) {
        self.kind = kind
        self.name = name
    }
}

/// Per-clip animatable transform, relative to the fitted frame (scale 1 = fit to the render size).
public struct ClipTransform: Codable, Hashable, Sendable {
    public var scale: Double = 1
    public var x: Double = 0
    public var y: Double = 0
    public var rotation: Double = 0
    public var opacity: Double = 1
    public init() {}

    func lerp(_ o: ClipTransform, _ t: Double) -> ClipTransform {
        var r = ClipTransform()
        r.scale = scale + (o.scale - scale) * t
        r.x = x + (o.x - x) * t
        r.y = y + (o.y - y) * t
        r.rotation = rotation + (o.rotation - rotation) * t
        r.opacity = opacity + (o.opacity - opacity) * t
        return r
    }
}

public struct ClipKeyframe: Codable, Hashable, Sendable {
    /// Seconds from the clip's start on the timeline.
    public var time: Double
    public var value: ClipTransform
    public init(time: Double, value: ClipTransform) {
        self.time = time
        self.value = value
    }
}

public struct ColorAdjust: Codable, Hashable, Sendable {
    public var brightness: Double = 0 // -1 … 1
    public var contrast: Double = 1 // 0 … 2
    public var saturation: Double = 1 // 0 … 2
    public var temperature: Double = 6500 // K, CITemperatureAndTint target
    public init() {}
    public var isIdentity: Bool { self == ColorAdjust() }
}

public enum ClipEffect: String, Codable, CaseIterable, Sendable {
    case none, mono, sepia, blur, sharpen, vignette, invert
    public var title: String {
        switch self {
        case .none: "Nessuno"
        case .mono: "Monocromatico"
        case .sepia: "Seppia"
        case .blur: "Sfocatura"
        case .sharpen: "Nitidezza"
        case .vignette: "Vignettatura"
        case .invert: "Inverti"
        }
    }
}

public struct Clip: Codable, Hashable, Identifiable, Sendable {
    public var id = UUID()
    public var media: String
    /// Start on the timeline.
    public var start: Double
    /// Where the used part begins in the source.
    public var sourceStart: Double
    /// Length of the used part of the source (before speed).
    public var sourceDuration: Double
    public var speed: Double = 1
    public var volume: Double = 1
    public var fadeIn: Double = 0
    public var fadeOut: Double = 0
    /// Cross-dissolve with the previous clip on the same track (overlap length).
    public var transitionIn: Double = 0
    public var transform = ClipTransform()
    public var keyframes: [ClipKeyframe] = []
    public var color = ColorAdjust()
    public var effect: ClipEffect = .none
    public var hasVideo: Bool
    public var hasAudio: Bool

    public init(media: String, start: Double, sourceStart: Double = 0, sourceDuration: Double, hasVideo: Bool, hasAudio: Bool) {
        self.media = media
        self.start = start
        self.sourceStart = sourceStart
        self.sourceDuration = sourceDuration
        self.hasVideo = hasVideo
        self.hasAudio = hasAudio
    }

    public var duration: Double { sourceDuration / max(speed, 0.01) }
    public var end: Double { start + duration }

    /// Transform at a timeline time (keyframes interpolated linearly, smoothstep-eased).
    public func transform(at t: Double) -> ClipTransform {
        let local = t - start
        let kf = keyframes.sorted { $0.time < $1.time }
        guard let first = kf.first, let last = kf.last else { return transform }
        if local <= first.time { return first.value }
        if local >= last.time { return last.value }
        for (a, b) in zip(kf, kf.dropFirst()) where local >= a.time && local <= b.time {
            let u = (local - a.time) / max(b.time - a.time, 1e-6)
            return a.value.lerp(b.value, u * u * (3 - 2 * u))
        }
        return transform
    }

    /// Opacity multiplier from fades and the incoming transition at a timeline time.
    public func fadeFactor(at t: Double) -> Double {
        let local = t - start
        var f = 1.0
        let fin = max(fadeIn, transitionIn)
        if fin > 0, local < fin { f = min(f, max(0, local / fin)) }
        if fadeOut > 0, end - t < fadeOut { f = min(f, max(0, (end - t) / fadeOut)) }
        return f
    }
}

public struct TitleClip: Codable, Hashable, Identifiable, Sendable {
    public var id = UUID()
    public var text: String
    public var start: Double
    public var duration: Double
    public var fontSize: Double = 72
    public var color = RGBAColor.white
    public var background = RGBAColor(0, 0, 0, 0.45)
    /// Normalised centre (0…1, origin top-left).
    public var x: Double = 0.5
    public var y: Double = 0.85
    public var fade: Double = 0.3
    public var isSubtitle = false

    public init(text: String, start: Double, duration: Double) {
        self.text = text
        self.start = start
        self.duration = duration
    }

    public func opacity(at t: Double) -> Double {
        let local = t - start
        guard local >= 0, local <= duration else { return 0 }
        guard fade > 0 else { return 1 }
        return min(1, local / fade, (duration - local) / fade)
    }
}

public struct Marker: Codable, Hashable, Identifiable, Sendable {
    public var id = UUID()
    public var time: Double
    public var name: String
    public init(time: Double, name: String) {
        self.time = time
        self.name = name
    }
}
