import AVFoundation
@testable import StudioCore
@testable import StudioVideo
import XCTest

/// Records which codecs this run-time can actually encode, decode and probe. Only H.264 is required;
/// the others are reported as observed (simulator and device can differ: run on the iPad too).
final class CodecInventoryTests: XCTestCase {
    func testCodecs() async throws {
        let dir = Fixtures.tempDir("codecs")
        for codec in FrameVideoWriter.Codec.allCases {
            let url = dir.appendingPathComponent("c-\(codec.rawValue).\(codec.ext)")
            var encoded = false, decoded = false, fourcc = "—"
            do {
                try await FrameVideoWriter.write(to: url, width: 320, height: 180, fps: 30, frameCount: 15, codec: codec) { _, ctx in
                    ctx.setFillColor(CGColor(srgbRed: 0, green: 1, blue: 0, alpha: 1))
                    ctx.fill(CGRect(x: 0, y: 0, width: 320, height: 180))
                }
                encoded = true
                let item = try await MediaProbe.probe(url, relativePath: url.lastPathComponent)
                fourcc = item.videoCodec ?? "—"
                decoded = await MediaProbe.canDecodeVideo(url)
            } catch {
                fourcc = "errore: \(error.localizedDescription)"
            }
            #if targetEnvironment(simulator)
            let where_ = "simulatore"
            #else
            let where_ = "dispositivo"
            #endif
            let required = codec == .h264
            Report.record("codec.\(codec.rawValue).\(where_)", expected: required ? "encode + decode" : "osservazione",
                          observed: "encode=\(encoded) decode=\(decoded) fourcc=\(fourcc)", pass: !required || (encoded && decoded))
            if required { XCTAssertTrue(encoded && decoded) }
        }
    }
}
