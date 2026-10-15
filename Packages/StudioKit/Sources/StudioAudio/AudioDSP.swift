import Accelerate
import Foundation

/// Planar float audio (one array per channel).
public struct PCMBuffer: Sendable, Equatable {
    public var sampleRate: Double
    public var channels: [[Float]]

    public init(sampleRate: Double, channels: [[Float]]) {
        self.sampleRate = sampleRate
        self.channels = channels
    }

    public init(sampleRate: Double, channelCount: Int, frames: Int) {
        self.sampleRate = sampleRate
        channels = Array(repeating: [Float](repeating: 0, count: frames), count: channelCount)
    }

    public var frames: Int { channels.first?.count ?? 0 }
    public var duration: Double { Double(frames) / sampleRate }

    public var peak: Float {
        channels.map { c -> Float in
            var m: Float = 0
            vDSP_maxmgv(c, 1, &m, vDSP_Length(c.count))
            return m
        }.max() ?? 0
    }

    public var rms: Float {
        let all = channels.map { c -> Float in
            var r: Float = 0
            vDSP_rmsqv(c, 1, &r, vDSP_Length(c.count))
            return r
        }
        return all.max() ?? 0
    }

    /// Samples whose magnitude reaches full scale (clipping).
    public var clippedSamples: Int {
        channels.reduce(0) { $0 + $1.reduce(0) { $0 + (abs($1) >= 0.9999 ? 1 : 0) } }
    }

    public mutating func applyGain(_ g: Float) {
        for i in channels.indices { vDSP.multiply(g, channels[i], result: &channels[i]) }
    }

    /// Scales so the peak reaches `targetDB` dBFS. Returns the applied gain in dB.
    @discardableResult
    public mutating func normalize(to targetDB: Double = -1) -> Double {
        let p = peak
        guard p > 0 else { return 0 }
        let g = Float(dbToGain(targetDB)) / p
        applyGain(g)
        return gainToDB(Double(g))
    }

    public mutating func fade(inSeconds: Double, outSeconds: Double) {
        let n = frames
        let fi = min(n, Int(inSeconds * sampleRate)), fo = min(n, Int(outSeconds * sampleRate))
        for c in channels.indices {
            for i in 0 ..< fi { channels[c][i] *= Float(i) / Float(max(1, fi)) }
            for i in 0 ..< fo { channels[c][n - 1 - i] *= Float(i) / Float(max(1, fo)) }
        }
    }

    public mutating func reverse() {
        for c in channels.indices { channels[c].reverse() }
    }

    public func slice(from a: Int, count: Int) -> PCMBuffer {
        let a = max(0, min(a, frames)), b = max(a, min(frames, a + count))
        return PCMBuffer(sampleRate: sampleRate, channels: channels.map { Array($0[a ..< b]) })
    }

    /// Peak amplitude per bucket, for waveform drawing.
    public func peaks(buckets: Int) -> [Float] {
        guard frames > 0, buckets > 0 else { return [] }
        let per = max(1, frames / buckets)
        return (0 ..< min(buckets, frames)).map { b in
            let a = b * per, len = min(per, frames - a)
            var m: Float = 0
            for c in channels {
                var cm: Float = 0
                c.withUnsafeBufferPointer { p in vDSP_maxmgv(p.baseAddress! + a, 1, &cm, vDSP_Length(len)) }
                m = max(m, cm)
            }
            return m
        }
    }
}

public func dbToGain(_ db: Double) -> Double { pow(10, db / 20) }
public func gainToDB(_ g: Double) -> Double { 20 * log10(max(g, 1e-9)) }

/// RBJ cookbook biquad (direct form I), per channel state.
public struct Biquad: Sendable {
    public enum Kind: Sendable { case lowShelf, highShelf, peak, highPass, lowPass }
    var b0 = 1.0, b1 = 0.0, b2 = 0.0, a1 = 0.0, a2 = 0.0

    public init(_ kind: Kind, freq: Double, sampleRate: Double, gainDB: Double = 0, q: Double = 0.707) {
        let f = min(freq, sampleRate * 0.49)
        let A = pow(10, gainDB / 40)
        let w0 = 2 * Double.pi * f / sampleRate
        let cw = cos(w0), sw = sin(w0)
        let alpha = sw / (2 * q)
        var b0 = 1.0, b1 = 0.0, b2 = 0.0, a0 = 1.0, a1 = 0.0, a2 = 0.0
        switch kind {
        case .peak:
            b0 = 1 + alpha * A; b1 = -2 * cw; b2 = 1 - alpha * A
            a0 = 1 + alpha / A; a1 = -2 * cw; a2 = 1 - alpha / A
        case .lowShelf:
            let s = 2 * sqrt(A) * alpha
            b0 = A * ((A + 1) - (A - 1) * cw + s); b1 = 2 * A * ((A - 1) - (A + 1) * cw); b2 = A * ((A + 1) - (A - 1) * cw - s)
            a0 = (A + 1) + (A - 1) * cw + s; a1 = -2 * ((A - 1) + (A + 1) * cw); a2 = (A + 1) + (A - 1) * cw - s
        case .highShelf:
            let s = 2 * sqrt(A) * alpha
            b0 = A * ((A + 1) + (A - 1) * cw + s); b1 = -2 * A * ((A - 1) + (A + 1) * cw); b2 = A * ((A + 1) + (A - 1) * cw - s)
            a0 = (A + 1) - (A - 1) * cw + s; a1 = 2 * ((A - 1) - (A + 1) * cw); a2 = (A + 1) - (A - 1) * cw - s
        case .highPass:
            b0 = (1 + cw) / 2; b1 = -(1 + cw); b2 = (1 + cw) / 2
            a0 = 1 + alpha; a1 = -2 * cw; a2 = 1 - alpha
        case .lowPass:
            b0 = (1 - cw) / 2; b1 = 1 - cw; b2 = (1 - cw) / 2
            a0 = 1 + alpha; a1 = -2 * cw; a2 = 1 - alpha
        }
        self.b0 = b0 / a0; self.b1 = b1 / a0; self.b2 = b2 / a0; self.a1 = a1 / a0; self.a2 = a2 / a0
    }

    public func process(_ x: inout [Float]) {
        var x1 = 0.0, x2 = 0.0, y1 = 0.0, y2 = 0.0
        for i in x.indices {
            let xi = Double(x[i])
            let y = b0 * xi + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
            x2 = x1; x1 = xi; y2 = y1; y1 = y
            x[i] = Float(y)
        }
    }
}

public enum AudioEffects {
    public static func applyEQ(_ eq: EQSettings, to buf: inout PCMBuffer) {
        guard !eq.isFlat else { return }
        var filters: [Biquad] = []
        let sr = buf.sampleRate
        if eq.highPassHz > 0 { filters.append(Biquad(.highPass, freq: eq.highPassHz, sampleRate: sr)) }
        if eq.lowPassHz > 0 { filters.append(Biquad(.lowPass, freq: eq.lowPassHz, sampleRate: sr)) }
        if eq.lowGainDB != 0 { filters.append(Biquad(.lowShelf, freq: 120, sampleRate: sr, gainDB: eq.lowGainDB)) }
        if eq.midGainDB != 0 { filters.append(Biquad(.peak, freq: eq.midFreq, sampleRate: sr, gainDB: eq.midGainDB, q: 1)) }
        if eq.highGainDB != 0 { filters.append(Biquad(.highShelf, freq: 8000, sampleRate: sr, gainDB: eq.highGainDB)) }
        for c in buf.channels.indices {
            for f in filters { f.process(&buf.channels[c]) }
        }
    }

    /// Downward expander: attenuates (by up to -40 dB) while the envelope is under the threshold.
    public static func gate(_ buf: inout PCMBuffer, thresholdDB: Double, attack: Double = 0.005, release: Double = 0.12) {
        let thr = Float(dbToGain(thresholdDB))
        let floorGain: Float = 0.01
        let att = Float(exp(-1 / (attack * buf.sampleRate))), rel = Float(exp(-1 / (release * buf.sampleRate)))
        var env: Float = 0, g: Float = 1
        for i in 0 ..< buf.frames {
            let m = buf.channels.reduce(Float(0)) { max($0, abs($1[i])) }
            env = m > env ? m : env * rel + m * (1 - rel)
            let target: Float = env >= thr ? 1 : floorGain
            g = target > g ? target + (g - target) * att : target + (g - target) * rel
            for c in buf.channels.indices { buf.channels[c][i] *= g }
        }
    }
}
