import CoreGraphics
import Foundation
import ImageIO
import os
import UniformTypeIdentifiers
import StudioCore
import StudioPhotoEngineFFI

/// Facts about an opened source, from the engine.
public struct PhotoSourceInfo: Codable, Equatable, Sendable {
    public var rawFormat: String?
    public var rawSupported: Bool?
    public var isRaw: Bool
    public var asShotTemp: Double
    public var asShotTint: Double
    public var relativeWB: Bool
    public var previewWidth: Int
    public var previewHeight: Int
    /// Developed size of the original (raw: from the headers; rendered: preview size).
    public var fullWidth: Int?
    public var fullHeight: Int?
}

public struct RawProbe: Codable, Equatable, Sendable {
    public var format: String?
    public var supported: Bool?
    public var headerReadable: Bool?
}

public struct PhotoExportResult: Codable, Equatable, Sendable {
    public var width: Int
    public var height: Int
    public var bytes: Int
}

public enum PhotoExportFormat: String, CaseIterable, Identifiable, Sendable {
    case jpg, png, tif, webp, avif, dng
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .jpg: "JPEG"
        case .png: "PNG"
        case .tif: "TIFF 16 bit"
        case .webp: "WebP"
        case .avif: "AVIF"
        case .dng: "DNG"
        }
    }
}

private func takeString(_ p: UnsafeMutablePointer<CChar>?) -> String? {
    guard let p else { return nil }
    defer { sc_string_free(p) }
    return String(cString: p)
}

/// A photo opened in the LightCraft engine (Rust). All calls run on a private serial queue: the
/// engine handle is not thread-safe, and nothing here blocks the main thread.
public final class PhotoEngine: @unchecked Sendable {
    private let handle: OpaquePointer
    private let queue = DispatchQueue(label: "studio.photo.engine", qos: .userInitiated)
    public let info: PhotoSourceInfo
    public let defaultSettings: JSONValue

    public static var version: String { takeString(sc_engine_version()) ?? "?" }

    private init(handle: OpaquePointer, info: PhotoSourceInfo, defaults: JSONValue) {
        self.handle = handle
        self.info = info
        defaultSettings = defaults
    }

    deinit { sc_photo_free(handle) }

    /// Opens and decodes `url` (raw sensor data for raw files) at preview resolution.
    public static func open(_ url: URL, previewEdge: Int = 2400) async throws -> PhotoEngine {
        try await withCheckedThrowingContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                var err: UnsafeMutablePointer<CChar>?
                guard let h = url.path.withCString({ sc_photo_open($0, UInt32(previewEdge), &err) }) else {
                    cont.resume(throwing: StudioError.engine(takeString(err) ?? "apertura non riuscita"))
                    return
                }
                do {
                    let infoJSON = takeString(sc_photo_info_json(h)) ?? "{}"
                    let info = try JSONDecoder().decode(PhotoSourceInfo.self, from: Data(infoJSON.utf8))
                    let defaults = try JSONValue.parse(takeString(sc_photo_default_settings_json(h)) ?? "{}")
                    cont.resume(returning: PhotoEngine(handle: h, info: info, defaults: defaults))
                } catch {
                    sc_photo_free(h)
                    cont.resume(throwing: StudioError.engine("risposta del motore non valida: \(error)"))
                }
            }
        }
    }

    /// Renders the preview with `settings` into a CGImage fitting `maxSize` pixels.
    public func render(_ settings: JSONValue, maxSize: CGSize, draft: Bool = false) async throws -> CGImage {
        let json = settings.jsonString()
        return try await withCheckedThrowingContinuation { cont in
            queue.async { [self] in
                var err: UnsafeMutablePointer<CChar>?
                let img = json.withCString { sc_photo_render(handle, $0, UInt32(max(1, maxSize.width)), UInt32(max(1, maxSize.height)), draft, &err) }
                guard let img else {
                    cont.resume(throwing: StudioError.engine(takeString(err) ?? "render non riuscito"))
                    return
                }
                defer { sc_image_free(img) }
                let w = Int(img.pointee.width), h = Int(img.pointee.height)
                let data = Data(bytes: img.pointee.data, count: img.pointee.len)
                guard let provider = CGDataProvider(data: data as CFData),
                      let cg = CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: w * 4,
                                       space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                                       provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
                else {
                    cont.resume(throwing: StudioError.engine("immagine non valida"))
                    return
                }
                cont.resume(returning: cg)
            }
        }
    }

    /// Exports the full-resolution original (re-decoded by the engine) with `settings`.
    public func export(_ settings: JSONValue, to url: URL, format: PhotoExportFormat, quality: Int = 92, longEdge: Int = 0) async throws -> PhotoExportResult {
        let json = settings.jsonString()
        return try await withCheckedThrowingContinuation { cont in
            queue.async { [self] in
                var err: UnsafeMutablePointer<CChar>?
                let r = json.withCString { s in
                    url.path.withCString { o in
                        format.rawValue.withCString { f in
                            sc_photo_export(handle, s, o, f, UInt8(clamping: quality), UInt32(max(0, longEdge)), &err)
                        }
                    }
                }
                guard let r = takeString(r) else {
                    cont.resume(throwing: StudioError.engine(takeString(err) ?? "esportazione non riuscita"))
                    return
                }
                do { cont.resume(returning: try JSONDecoder().decode(PhotoExportResult.self, from: Data(r.utf8))) } catch {
                    cont.resume(throwing: StudioError.engine("risposta non valida"))
                }
            }
        }
    }

    /// Full-resolution render of the original, tile by tile (pixel-identical to a whole-frame render,
    /// a fraction of the export pipeline's memory). `longEdge` 0 = full size.
    public func renderTiled(_ settings: JSONValue, longEdge: Int = 0) async throws -> CGImage {
        let json = settings.jsonString()
        return try await withCheckedThrowingContinuation { cont in
            queue.async { [self] in
                var err: UnsafeMutablePointer<CChar>?
                guard let img = json.withCString({ sc_photo_render_tiled(handle, $0, UInt32(max(0, longEdge)), 1024, &err) }) else {
                    cont.resume(throwing: StudioError.engine(takeString(err) ?? "render a tasselli non riuscito"))
                    return
                }
                let w = Int(img.pointee.width), h = Int(img.pointee.height)
                // hand the Rust buffer to Core Graphics without copying; freed when the CGImage goes away
                let release: CGDataProviderReleaseDataCallback = { info, _, _ in
                    sc_image_free(info?.assumingMemoryBound(to: ScImage.self))
                }
                guard let provider = CGDataProvider(dataInfo: img, data: img.pointee.data, size: img.pointee.len, releaseData: release),
                      let cg = CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: w * 4,
                                       space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
                else {
                    cont.resume(throwing: StudioError.engine("immagine non valida"))
                    return
                }
                cont.resume(returning: cg)
            }
        }
    }

    /// Estimated peak memory (bytes) of `export` for an output whose long edge is `longEdge` (0 = full).
    /// Measured on device: about 150 bytes per output pixel for the full-frame export pipeline.
    public func estimatedExportBytes(longEdge: Int) -> UInt64 {
        let w = Double(info.fullWidth ?? info.previewWidth), h = Double(info.fullHeight ?? info.previewHeight)
        var px = w * h
        if longEdge > 0, max(w, h) > Double(longEdge) { px *= pow(Double(longEdge) / max(w, h), 2) }
        return UInt64(px * 150)
    }

    /// Exports choosing the pipeline by memory: the engine's own export when it fits in the memory
    /// the system grants, otherwise (JPEG/PNG/HEIC) the tiled render encoded with ImageIO, with the
    /// original's EXIF/TIFF/GPS metadata. Formats only the engine writes fail with a clear message.
    public func exportAdaptive(_ settings: JSONValue, to url: URL, format: PhotoExportFormat, quality: Int = 92, longEdge: Int = 0,
                               sourceURL: URL) async throws -> (PhotoExportResult, tiled: Bool) {
        let available = UInt64(os_proc_available_memory())
        let need = estimatedExportBytes(longEdge: longEdge)
        if need < available / 10 * 8 {
            return (try await export(settings, to: url, format: format, quality: quality, longEdge: longEdge), false)
        }
        let type: UTType
        switch format {
        case .jpg: type = .jpeg
        case .png: type = .png
        default:
            let maxEdge = Int(Double(max(info.fullWidth ?? 1, info.fullHeight ?? 1)) * sqrt(Double(available) * 0.8 / Double(max(need, 1))))
            throw StudioError.notAvailable("\(format.title) a questa dimensione richiede circa \(need >> 20) MB, il sistema ne concede \(available >> 20). Esporta in JPEG/PNG a piena risoluzione oppure \(format.title) con lato lungo ≤ \(maxEdge) px.")
        }
        let img = try await renderTiled(settings, longEdge: longEdge)
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil) else { throw StudioError.io("destinazione") }
        var props: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: Double(quality) / 100]
        if let src = CGImageSourceCreateWithURL(sourceURL as CFURL, nil),
           let meta = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any] {
            for k in [kCGImagePropertyExifDictionary, kCGImagePropertyTIFFDictionary, kCGImagePropertyGPSDictionary] { if let v = meta[k] { props[k] = v } }
        }
        props[kCGImagePropertyOrientation] = 1 // pixels are already upright
        CGImageDestinationAddImage(dest, img, props as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { throw StudioError.io("scrittura \(url.lastPathComponent) non riuscita") }
        let bytes = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
        return (PhotoExportResult(width: img.width, height: img.height, bytes: bytes), true)
    }

    /// Recognises a raw container without decoding the samples.
    public static func probe(_ url: URL) throws -> RawProbe {
        var err: UnsafeMutablePointer<CChar>?
        guard let s = takeString(url.path.withCString { sc_raw_probe($0, &err) }) else {
            throw StudioError.engine(takeString(err) ?? "probe non riuscito")
        }
        return try JSONDecoder().decode(RawProbe.self, from: Data(s.utf8))
    }

    /// File extensions the importer offers. Rendered formats go through the engine's codecs.
    public static let rawExtensions = ["dng", "cr2", "cr3", "nef", "nrw", "arw", "raf", "rw2", "pef", "srw", "orf", "3fr", "fff"]
    public static let imageExtensions = ["jpg", "jpeg", "png", "tif", "tiff", "webp", "heic", "heif", "avif", "jxl"]
}
