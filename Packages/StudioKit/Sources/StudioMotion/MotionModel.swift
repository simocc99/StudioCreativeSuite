import CoreGraphics
import Foundation
import StudioCore

public enum Easing: String, Codable, CaseIterable, Sendable {
    case linear, easeIn, easeOut, easeInOut, hold, overshoot

    public var title: String {
        switch self {
        case .linear: "Lineare"
        case .easeIn: "Accelera"
        case .easeOut: "Rallenta"
        case .easeInOut: "Morbido"
        case .hold: "Tieni"
        case .overshoot: "Rimbalzo"
        }
    }

    public func apply(_ t: Double) -> Double {
        switch self {
        case .linear: t
        case .easeIn: t * t * t
        case .easeOut: 1 - pow(1 - t, 3)
        case .easeInOut: t < 0.5 ? 4 * t * t * t : 1 - pow(-2 * t + 2, 3) / 2
        case .hold: 0
        case .overshoot:
            // easeOutBack
            1 + 2.70158 * pow(t - 1, 3) + 1.70158 * pow(t - 1, 2)
        }
    }
}

public struct Keyframe: Codable, Hashable, Sendable {
    public var time: Double
    public var value: Double
    /// Easing from this keyframe to the next.
    public var easing: Easing = .easeInOut
    public init(time: Double, value: Double, easing: Easing = .easeInOut) {
        self.time = time
        self.value = value
        self.easing = easing
    }
}

/// A property that is either constant or keyframed.
public struct AnimatedValue: Codable, Hashable, Sendable {
    public var value: Double
    public var keys: [Keyframe] = []

    public init(_ v: Double) { value = v }

    public var isAnimated: Bool { !keys.isEmpty }

    public func at(_ t: Double) -> Double {
        guard let first = keys.first, let last = keys.last else { return value }
        if t <= first.time { return first.value }
        if t >= last.time { return last.value }
        for (a, b) in zip(keys, keys.dropFirst()) where t >= a.time && t <= b.time {
            let u = (t - a.time) / max(b.time - a.time, 1e-9)
            return a.value + (b.value - a.value) * a.easing.apply(u)
        }
        return value
    }

    /// Sets the value at time t: adds/replaces a keyframe when animated, else changes the constant.
    public mutating func set(_ v: Double, at t: Double, keyframe: Bool) {
        if keyframe || isAnimated {
            keys.removeAll { abs($0.time - t) < 1e-4 }
            keys.append(Keyframe(time: t, value: v))
            keys.sort { $0.time < $1.time }
        } else {
            value = v
        }
    }
}

public enum MotionLayerKind: Codable, Hashable, Sendable {
    case rectangle(cornerRadius: Double)
    case ellipse
    case star(points: Int)
    case text(String, fontSize: Double)
    /// Image or video frame source (relative path in the project).
    case image(String)
    /// Another composition-sized solid colour.
    case solid
}

public enum TextAnimation: String, Codable, CaseIterable, Sendable {
    case none, typewriter, fadeByWord
    public var title: String {
        switch self {
        case .none: "Nessuna"
        case .typewriter: "Macchina da scrivere"
        case .fadeByWord: "Parola per parola"
        }
    }
}

public enum MaskShape: String, Codable, CaseIterable, Sendable {
    case none, rectangle, ellipse
    public var title: String {
        switch self {
        case .none: "Nessuna"
        case .rectangle: "Rettangolo"
        case .ellipse: "Ellisse"
        }
    }
}

public struct MotionLayer: Codable, Hashable, Identifiable, Sendable {
    public var id = UUID()
    public var name: String
    public var kind: MotionLayerKind
    public var inPoint: Double = 0
    public var outPoint: Double = 10
    public var width: Double = 400
    public var height: Double = 400
    public var color = RGBAColor(0.95, 0.45, 0.2)
    public var visible = true
    // transform (composition pixels, anchor at the layer centre)
    public var x = AnimatedValue(960)
    public var y = AnimatedValue(540)
    public var scale = AnimatedValue(100)
    public var rotation = AnimatedValue(0)
    public var opacity = AnimatedValue(100)
    // mask in layer-local normalised coordinates, animatable reveal (0…100 %)
    public var mask: MaskShape = .none
    public var maskReveal = AnimatedValue(100)
    public var maskFeather: Double = 0
    public var textAnimation: TextAnimation = .none
    /// 0…100 % of the text shown (for text animations).
    public var textProgress = AnimatedValue(100)
    public var blur = AnimatedValue(0)

    public init(name: String, kind: MotionLayerKind) {
        self.name = name
        self.kind = kind
    }

    public var animatedProperties: [(String, WritableKeyPath<MotionLayer, AnimatedValue>)] {
        [("Posizione X", \.x), ("Posizione Y", \.y), ("Scala %", \.scale), ("Rotazione °", \.rotation), ("Opacità %", \.opacity),
         ("Rivelazione maschera %", \.maskReveal), ("Testo %", \.textProgress), ("Sfocatura", \.blur)]
    }
}

public struct MotionProject: ProjectPayload {
    public static let kind = StudioModule.motion
    public static let formatVersion = 1

    public var width = 1920
    public var height = 1080
    public var fps = 30
    public var duration: Double = 10
    public var background = RGBAColor(0.08, 0.08, 0.1)
    /// Bottom → top.
    public var layers: [MotionLayer] = []
    public var media: [String] = []

    public init() {}

    public var frameCount: Int { max(1, Int((duration * Double(fps)).rounded())) }
}
