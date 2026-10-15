import AVFoundation
@testable import StudioAudio
@testable import StudioCore
import XCTest

final class AudioTests: XCTestCase {
    func sine(_ f: Double, _ seconds: Double = 1, sr: Double = 48000, amp: Float = 0.5) -> PCMBuffer {
        let n = Int(seconds * sr)
        let c = (0 ..< n).map { amp * Float(sin(2 * .pi * f * Double($0) / sr)) }
        return PCMBuffer(sampleRate: sr, channels: [c, c])
    }

    func testNormalizeAndFade() {
        var b = sine(440, amp: 0.25)
        b.normalize(to: -1)
        let peakDB = gainToDB(Double(b.peak))
        check("audio.normalize", abs(peakDB + 1) < 0.05, expected: "-1.00 dBFS", observed: String(format: "%.2f dBFS", peakDB))
        b.fade(inSeconds: 0.5, outSeconds: 0.5)
        check("audio.fade", abs(b.channels[0][0]) < 1e-6 && abs(b.channels[0][b.frames - 1]) < 1e-3, expected: "silent at both ends",
              observed: "\(b.channels[0][0]) … \(b.channels[0][b.frames - 1])")
    }

    func testLowPassAttenuatesHighs() {
        var b = sine(10000)
        var eq = EQSettings()
        eq.lowPassHz = 1000
        let before = b.rms
        AudioEffects.applyEQ(eq, to: &b)
        let drop = gainToDB(Double(b.rms / before))
        check("audio.lowpass", drop < -20, expected: "10 kHz attenuated > 20 dB by a 1 kHz low-pass", observed: String(format: "%.1f dB", drop))
        var low = sine(100)
        let l0 = low.rms
        AudioEffects.applyEQ(eq, to: &low)
        XCTAssertGreaterThan(Double(low.rms / l0), 0.9, "100 Hz passes")
    }

    func testShelfGain() {
        var b = sine(60)
        let r0 = b.rms
        var eq = EQSettings()
        eq.lowGainDB = 6
        AudioEffects.applyEQ(eq, to: &b)
        let g = gainToDB(Double(b.rms / r0))
        check("audio.lowshelf", g > 4.5 && g < 7, expected: "≈ +6 dB at 60 Hz", observed: String(format: "%.2f dB", g))
    }

    func testGate() {
        var b = sine(440, 1, amp: 0.002) // -54 dBFS
        AudioEffects.gate(&b, thresholdDB: -40)
        // after the 120 ms release the gate is closed: measure the second half
        let tail = b.slice(from: b.frames / 2, count: b.frames / 2)
        let db = gainToDB(Double(tail.peak))
        check("audio.gate", db < -85, expected: "signal under threshold attenuated ~40 dB (−54 → ≈−94 dBFS)", observed: String(format: "%.1f dBFS", db))
        // a loud signal passes unchanged
        var loud = sine(440, 1, amp: 0.5)
        AudioEffects.gate(&loud, thresholdDB: -40)
        XCTAssertGreaterThan(loud.slice(from: loud.frames / 2, count: loud.frames / 2).peak, 0.49)
    }

    func testMixExportAndReadBack() throws {
        let dir = Fixtures.tempDir("audio")
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("Media"), withIntermediateDirectories: true)
        try Fixtures.tone(dir.appendingPathComponent("Media/a.wav"), seconds: 2, freq: 220, amplitude: 0.4)
        try Fixtures.tone(dir.appendingPathComponent("Media/b.wav"), seconds: 1, freq: 880, amplitude: 0.4)
        var p = AudioProject()
        let a = try AudioMediaProbe.probeSync(dir.appendingPathComponent("Media/a.wav"), path: "Media/a.wav")
        let b = try AudioMediaProbe.probeSync(dir.appendingPathComponent("Media/b.wav"), path: "Media/b.wav")
        p.media = [a, b]
        p.addClip(a, track: 0)
        p.addClip(b, track: 1, at: 0.5)
        p.tracks[1].pan = -1
        let r = try AudioRenderer().render(p, projectURL: dir)
        check("audio.mix.length", abs(r.duration - 2) < 0.01, expected: "2.00 s", observed: String(format: "%.3f s", r.duration))
        // hard-left pan: track 2 is absent from the right channel
        let win = r.slice(from: Int(0.75 * 48000), count: 4800)
        let left = PCMBuffer(sampleRate: 48000, channels: [win.channels[0]]).rms, right = PCMBuffer(sampleRate: 48000, channels: [win.channels[1]]).rms
        check("audio.pan", left > right * 1.3, expected: "left louder than right", observed: "L \(left) R \(right)")
        p.cut(from: 0.5, to: 1.0, ripple: true)
        XCTAssertEqual(p.duration, 1.5, accuracy: 1e-9)

        for fmt in AudioIO.ExportFormat.allCases {
            let out = dir.appendingPathComponent("mix.\(fmt.ext)")
            try AudioIO.write(r, to: out, format: fmt)
            let back = try AudioIO.read(out, sampleRate: 48000)
            check("audio.export.\(fmt.rawValue)", abs(back.duration - 2) < 0.05 && back.peak > 0.3,
                  expected: "readable 2 s file", observed: String(format: "%.3f s, peak %.2f", back.duration, back.peak))
        }
    }

    func testClippingReport() {
        var b = sine(100, amp: 0.9)
        b.applyGain(2)
        for c in b.channels.indices { b.channels[c] = b.channels[c].map { max(-1, min(1, $0)) } }
        check("audio.clipping", b.clippedSamples > 0, expected: "clipped samples counted", observed: "\(b.clippedSamples)")
    }
}
