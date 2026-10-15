import AVFoundation
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Writes frames drawn with Core Graphics to a movie (H.264 / HEVC / ProRes 422) with AVAssetWriter.
public enum FrameVideoWriter {
    public enum Codec: String, CaseIterable, Identifiable, Sendable {
        case h264, hevc, prores
        public var id: String { rawValue }
        public var title: String {
            switch self {
            case .h264: "H.264 (.mp4)"
            case .hevc: "HEVC (.mov)"
            case .prores: "ProRes 422 (.mov)"
            }
        }
        var avCodec: AVVideoCodecType {
            switch self {
            case .h264: .h264
            case .hevc: .hevc
            case .prores: .proRes422
            }
        }
        public var fileType: AVFileType { self == .h264 ? .mp4 : .mov }
        public var ext: String { self == .h264 ? "mp4" : "mov" }
    }

    /// Renders `frameCount` frames at `fps`; `draw` paints frame i into a top-left-origin context.
    public static func write(to url: URL, width: Int, height: Int, fps: Int, frameCount: Int, codec: Codec = .h264,
                             progress: (@Sendable (Double) -> Void)? = nil,
                             draw: (Int, CGContext) -> Void) async throws {
        try? FileManager.default.removeItem(at: url)
        let w = width / 2 * 2, h = height / 2 * 2 // encoders want even sizes
        let writer = try AVAssetWriter(outputURL: url, fileType: codec.fileType)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: codec.avCodec, AVVideoWidthKey: w, AVVideoHeightKey: h,
        ])
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: w, kCVPixelBufferHeightKey as String: h,
        ])
        guard writer.canAdd(input) else { throw StudioError.notAvailable("codec \(codec.title) per \(w)×\(h)") }
        writer.add(input)
        guard writer.startWriting() else { throw StudioError.engine(writer.error?.localizedDescription ?? "scrittura video") }
        writer.startSession(atSourceTime: .zero)
        for i in 0 ..< frameCount {
            try Task.checkCancellation()
            while !input.isReadyForMoreMediaData { try await Task.sleep(for: .milliseconds(5)) }
            guard let pool = adaptor.pixelBufferPool else { throw StudioError.engine("pool di pixel buffer non disponibile") }
            var pb: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, pool, &pb)
            guard let pb else { throw StudioError.engine("pixel buffer") }
            CVPixelBufferLockBaseAddress(pb, [])
            if let ctx = CGContext(data: CVPixelBufferGetBaseAddress(pb), width: w, height: h, bitsPerComponent: 8,
                                   bytesPerRow: CVPixelBufferGetBytesPerRow(pb), space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                   bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue) {
                ctx.translateBy(x: 0, y: CGFloat(h))
                ctx.scaleBy(x: 1, y: -1)
                ctx.scaleBy(x: CGFloat(w) / CGFloat(width), y: CGFloat(h) / CGFloat(height))
                draw(i, ctx)
            }
            CVPixelBufferUnlockBaseAddress(pb, [])
            adaptor.append(pb, withPresentationTime: CMTime(value: CMTimeValue(i), timescale: CMTimeScale(fps)))
            progress?(Double(i + 1) / Double(frameCount))
        }
        input.markAsFinished()
        await writer.finishWriting()
        if writer.status != .completed { throw StudioError.engine(writer.error?.localizedDescription ?? "video non completato") }
    }

    /// Writes numbered PNG frames into a new folder; returns the folder.
    public static func writePNGSequence(to folder: URL, width: Int, height: Int, frameCount: Int, draw: (Int, CGContext) -> Void) throws -> URL {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for i in 0 ..< frameCount {
            guard let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { continue }
            ctx.translateBy(x: 0, y: CGFloat(height))
            ctx.scaleBy(x: 1, y: -1)
            draw(i, ctx)
            guard let img = ctx.makeImage(),
                  let dest = CGImageDestinationCreateWithURL(folder.appendingPathComponent(String(format: "frame_%05d.png", i)) as CFURL,
                                                             UTType.png.identifier as CFString, 1, nil) else { continue }
            CGImageDestinationAddImage(dest, img, nil)
            CGImageDestinationFinalize(dest)
        }
        return folder
    }

    /// Animated GIF (looping).
    public static func writeGIF(to url: URL, width: Int, height: Int, fps: Int, frameCount: Int, draw: (Int, CGContext) -> Void) throws {
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.gif.identifier as CFString, frameCount, nil) else {
            throw StudioError.io("GIF")
        }
        CGImageDestinationSetProperties(dest, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
        let props = [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 1.0 / Double(fps)]] as CFDictionary
        for i in 0 ..< frameCount {
            guard let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { continue }
            ctx.translateBy(x: 0, y: CGFloat(height))
            ctx.scaleBy(x: 1, y: -1)
            draw(i, ctx)
            if let img = ctx.makeImage() { CGImageDestinationAddImage(dest, img, props) }
        }
        guard CGImageDestinationFinalize(dest) else { throw StudioError.io("GIF non completata") }
    }
}
