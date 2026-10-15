import AVFoundation
@testable import StudioCore
import UniformTypeIdentifiers
import XCTest

/// The import pipeline behind "Libreria Foto / File / Fotocamera / Incolla / trascina".
final class ImportTests: XCTestCase {
    func testStagingKeepsNamesAndExtensions() throws {
        let src = Fixtures.tempDir("import").appendingPathComponent("abc.tmp.jpeg")
        try Data([0xFF, 0xD8, 0xFF]).write(to: src)
        let a = try ImportStaging.copy(src)
        let b = try ImportStaging.copy(src, preferredName: "IMG_0042", type: .jpeg)
        let c = try ImportStaging.copy(src, preferredName: "Vacanze.jpeg", type: .jpeg)
        let ok = a.lastPathComponent == "abc.tmp.jpeg" && b.lastPathComponent == "IMG_0042.jpeg" && c.lastPathComponent == "Vacanze.jpeg"
            && a.deletingLastPathComponent() != b.deletingLastPathComponent() && FileManager.default.fileExists(atPath: b.path)
        check("import.staging.names", ok, expected: "original name, suggested name + extension, no doubled extension, separate folders",
              observed: "\(a.lastPathComponent) · \(b.lastPathComponent) · \(c.lastPathComponent)")
    }

    func testAudioFromVideo() async throws {
        let dir = Fixtures.tempDir("import-video")
        // a silent clip: extraction must say so instead of producing an empty file
        let silent = dir.appendingPathComponent("muto.mp4")
        try await FrameVideoWriter.write(to: silent, width: 320, height: 240, fps: 10, frameCount: 10) { _, ctx in
            ctx.setFillColor(CGColor(gray: 0.5, alpha: 1))
            ctx.fill(CGRect(x: 0, y: 0, width: 320, height: 240))
        }
        var message = ""
        do { _ = try await ImportStaging.extractAudio(silent) } catch { message = error.localizedDescription }
        check("import.audioFromVideo.silent", message.contains("traccia audio"), expected: "clear error for a video without audio", observed: message)

        // a clip with audio: a 1 s tone muxed into a movie, then extracted to M4A
        let withAudio = dir.appendingPathComponent("tono.mov")
        try await Self.writeToneMovie(to: withAudio)
        let m4a = try await ImportStaging.extractAudio(withAudio)
        let dur = try await AVURLAsset(url: m4a).load(.duration).seconds
        check("import.audioFromVideo.m4a", m4a.pathExtension == "m4a" && dur > 0.8, expected: "M4A of about 1 s",
              observed: "\(m4a.lastPathComponent) \(String(format: "%.2f", dur)) s")
    }

    /// One second of 440 Hz as AAC in a QuickTime movie (audio-only movie is enough for the importer).
    static func writeToneMovie(to url: URL) async throws {
        try? FileManager.default.removeItem(at: url)
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .audio, outputSettings: [
            AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 44100, AVNumberOfChannelsKey: 1, AVEncoderBitRateKey: 96000,
        ])
        writer.add(input)
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)
        let rate = 44100.0
        var asbd = AudioStreamBasicDescription(mSampleRate: rate, mFormatID: kAudioFormatLinearPCM,
                                               mFormatFlags: kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked,
                                               mBytesPerPacket: 2, mFramesPerPacket: 1, mBytesPerFrame: 2, mChannelsPerFrame: 1,
                                               mBitsPerChannel: 16, mReserved: 0)
        var format: CMAudioFormatDescription?
        CMAudioFormatDescriptionCreate(allocator: nil, asbd: &asbd, layoutSize: 0, layout: nil, magicCookieSize: 0,
                                       magicCookie: nil, extensions: nil, formatDescriptionOut: &format)
        let frames = 1024
        var written = 0
        while written < Int(rate) {
            while !input.isReadyForMoreMediaData { try await Task.sleep(for: .milliseconds(5)) }
            var pcm = [Int16](repeating: 0, count: frames)
            for i in 0 ..< frames { pcm[i] = Int16(sin(2 * .pi * 440 * Double(written + i) / rate) * 12000) }
            var block: CMBlockBuffer?
            let bytes = frames * 2
            CMBlockBufferCreateWithMemoryBlock(allocator: nil, memoryBlock: nil, blockLength: bytes, blockAllocator: nil,
                                               customBlockSource: nil, offsetToData: 0, dataLength: bytes, flags: 0, blockBufferOut: &block)
            pcm.withUnsafeBytes { _ = CMBlockBufferReplaceDataBytes(with: $0.baseAddress!, blockBuffer: block!, offsetIntoDestination: 0, dataLength: bytes) }
            var sample: CMSampleBuffer?
            CMAudioSampleBufferCreateReadyWithPacketDescriptions(allocator: nil, dataBuffer: block!, formatDescription: format!,
                                                                 sampleCount: frames, presentationTimeStamp: CMTime(value: CMTimeValue(written), timescale: Int32(rate)),
                                                                 packetDescriptions: nil, sampleBufferOut: &sample)
            input.append(sample!)
            written += frames
        }
        input.markAsFinished()
        await writer.finishWriting()
    }
}
