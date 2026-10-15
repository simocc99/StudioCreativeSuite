import AVFoundation
import CoreGraphics
import Foundation
import ImageIO
@testable import StudioAudio
@testable import StudioCore
import UniformTypeIdentifiers
import XCTest

/// Fixtures generated at test time (no binary test data in the repository).
enum Fixtures {
    static func tempDir(_ name: String = UUID().uuidString) -> URL {
        let u = FileManager.default.temporaryDirectory.appendingPathComponent("StudioTests-\(name)", isDirectory: true)
        try? FileManager.default.removeItem(at: u)
        try! FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }

    /// A solid-colour H.264 movie.
    static func movie(_ url: URL, seconds: Double, color: RGBAColor, size: CGSize = CGSize(width: 320, height: 180), fps: Int = 30) async throws {
        try await FrameVideoWriter.write(to: url, width: Int(size.width), height: Int(size.height), fps: fps, frameCount: Int(seconds * Double(fps))) { _, ctx in
            ctx.setFillColor(color.cgColor)
            ctx.fill(CGRect(origin: .zero, size: size))
        }
    }

    /// A stereo sine WAV.
    static func tone(_ url: URL, seconds: Double, freq: Double, amplitude: Float = 0.5, sampleRate: Double = 48000) throws {
        let n = Int(seconds * sampleRate)
        let c = (0 ..< n).map { amplitude * Float(sin(2 * .pi * freq * Double($0) / sampleRate)) }
        try AudioIO.write(PCMBuffer(sampleRate: sampleRate, channels: [c, c]), to: url, format: .wav16)
    }

    static func png(_ url: URL, width: Int, height: Int, color: RGBAColor) {
        let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(color.cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let d = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(d, ctx.makeImage()!, nil)
        CGImageDestinationFinalize(d)
    }

    /// Average RGB (0…255) of a CGImage region (top-left coordinates).
    static func average(_ img: CGImage, in r: CGRect? = nil) -> (Double, Double, Double) {
        let rect = r ?? CGRect(x: 0, y: 0, width: img.width, height: img.height)
        guard let crop = img.cropping(to: rect) else { return (0, 0, 0) }
        let w = crop.width, h = crop.height
        var px = [UInt8](repeating: 0, count: w * h * 4)
        let ctx = CGContext(data: &px, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(crop, in: CGRect(x: 0, y: 0, width: w, height: h))
        var s = (0.0, 0.0, 0.0)
        for i in stride(from: 0, to: px.count, by: 4) { s.0 += Double(px[i]); s.1 += Double(px[i + 1]); s.2 += Double(px[i + 2]) }
        let n = Double(w * h)
        return (s.0 / n, s.1 / n, s.2 / n)
    }

    static func frame(_ url: URL, at t: Double) async throws -> CGImage {
        let g = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        g.requestedTimeToleranceBefore = .zero
        g.requestedTimeToleranceAfter = .zero
        g.appliesPreferredTrackTransform = true
        return try await g.image(at: CMTime(seconds: t, preferredTimescale: 600)).image
    }

    /// Directory with raw samples (set STUDIO_RAW_DIR, or TEST_RUNNER_STUDIO_RAW_DIR via xcodebuild).
    static var rawDir: URL? {
        let env = ProcessInfo.processInfo.environment
        if let p = env["STUDIO_RAW_DIR"] ?? env["TEST_RUNNER_STUDIO_RAW_DIR"], FileManager.default.fileExists(atPath: p) { return URL(fileURLWithPath: p) }
        // on the device the samples are copied into the host app's Documents/TestRAW (Scripts/run-device-tests.sh)
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("TestRAW")
        return FileManager.default.fileExists(atPath: docs.path) ? docs : nil
    }
}

/// Collects expected/observed pairs into a JSON report (STUDIO_TEST_REPORT / TEST_RUNNER_STUDIO_TEST_REPORT).
enum Report {
    nonisolated(unsafe) static var lines: [[String: String]] = []
    static let lock = NSLock()

    static func record(_ test: String, expected: String, observed: String, pass: Bool) {
        lock.withLock { lines.append(["test": test, "expected": expected, "observed": observed, "result": pass ? "PASS" : "FAIL"]) }
        let env = ProcessInfo.processInfo.environment
        #if targetEnvironment(simulator)
        guard let p = env["STUDIO_TEST_REPORT"] ?? env["TEST_RUNNER_STUDIO_TEST_REPORT"] else { return }
        #else
        let p = env["STUDIO_TEST_REPORT"] ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("test-report.json").path
        #endif
        let data = lock.withLock { try? JSONSerialization.data(withJSONObject: lines, options: [.prettyPrinted, .sortedKeys]) }
        try? data?.write(to: URL(fileURLWithPath: p))
    }
}

func check(_ test: String, _ cond: Bool, expected: String, observed: String, file: StaticString = #filePath, line: UInt = #line) {
    Report.record(test, expected: expected, observed: observed, pass: cond)
    XCTAssertTrue(cond, "\(test): expected \(expected), observed \(observed)", file: file, line: line)
}
