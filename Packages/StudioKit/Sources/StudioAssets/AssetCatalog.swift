import AVFoundation
import CryptoKit
import Foundation
import ImageIO
import QuickLookThumbnailing
import StudioCore
import UIKit
import UniformTypeIdentifiers

public enum AssetKind: String, Codable, CaseIterable, Sendable {
    case photo, raw, video, audio, document, font, preset, other

    public var title: String {
        switch self {
        case .photo: "Immagini"
        case .raw: "RAW"
        case .video: "Video"
        case .audio: "Audio"
        case .document: "Documenti"
        case .font: "Font"
        case .preset: "Preset"
        case .other: "Altro"
        }
    }

    public var icon: String {
        switch self {
        case .photo: "photo"
        case .raw: "camera.aperture"
        case .video: "film"
        case .audio: "waveform"
        case .document: "doc"
        case .font: "textformat"
        case .preset: "slider.horizontal.3"
        case .other: "questionmark.square"
        }
    }

    static let rawExt: Set<String> = ["dng", "cr2", "cr3", "nef", "nrw", "arw", "raf", "rw2", "orf", "pef", "srw", "3fr", "fff"]

    public static func of(_ url: URL) -> AssetKind {
        let ext = url.pathExtension.lowercased()
        if rawExt.contains(ext) { return .raw }
        if ["json", "xmp", "lut", "cube"].contains(ext) { return .preset }
        guard let t = UTType(filenameExtension: ext) else { return .other }
        if t.conforms(to: .image) { return .photo }
        if t.conforms(to: .movie) || t.conforms(to: .video) { return .video }
        if t.conforms(to: .audio) { return .audio }
        if t.conforms(to: .font) { return .font }
        if t.conforms(to: .pdf) || t.conforms(to: .text) || t.conforms(to: .svg) { return .document }
        return .other
    }
}

public struct Asset: Codable, Hashable, Identifiable, Sendable {
    public var id = UUID()
    /// Relative to the catalog's Files folder.
    public var file: String
    public var name: String
    public var kind: AssetKind
    public var bytes: Int64
    public var sha256: String
    public var added: Date
    public var tags: [String] = []
    public var favorite = false
    public var rating = 0
    public var metadata: [String: String] = [:]
}

/// The shared asset library: `Documents/Library/catalog.json` + `Documents/Library/Files/`.
/// Imports are de-duplicated by content hash, so the same file is stored once.
public final class AssetCatalog: @unchecked Sendable {
    public static let shared = AssetCatalog(root: StudioPaths.documents.appendingPathComponent("Library", isDirectory: true))

    public let root: URL
    public private(set) var assets: [Asset] = []
    private let lock = NSLock()

    public init(root: URL) {
        self.root = root
        try? FileManager.default.createDirectory(at: filesURL, withIntermediateDirectories: true)
        load()
    }

    public var filesURL: URL { root.appendingPathComponent("Files", isDirectory: true) }
    var catalogURL: URL { root.appendingPathComponent("catalog.json") }

    public func url(of a: Asset) -> URL { filesURL.appendingPathComponent(a.file) }

    func load() {
        guard let d = try? Data(contentsOf: catalogURL) else { return }
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        assets = (try? dec.decode([Asset].self, from: d)) ?? []
    }

    public func save() throws {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        enc.dateEncodingStrategy = .iso8601
        lock.lock()
        let snapshot = assets
        lock.unlock()
        try enc.encode(snapshot).write(to: catalogURL, options: .atomic)
    }

    public static func sha256(of url: URL) throws -> String {
        let h = FileHandle(forReadingAtPath: url.path)
        guard let h else { throw StudioError.io("\(url.lastPathComponent) non leggibile") }
        defer { try? h.close() }
        var hasher = SHA256()
        while let chunk = try h.read(upToCount: 4 << 20), !chunk.isEmpty { hasher.update(data: chunk) }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    public struct ImportResult: Sendable {
        public var added: [Asset] = []
        public var duplicates: [Asset] = []
    }

    /// Imports files (copying each unique content once). Returns new and already-present assets.
    public func importFiles(_ urls: [URL]) async throws -> ImportResult {
        var r = ImportResult()
        for src in urls {
            let scoped = src.startAccessingSecurityScopedResource()
            defer { if scoped { src.stopAccessingSecurityScopedResource() } }
            let hash = try Self.sha256(of: src)
            if let existing = assets.first(where: { $0.sha256 == hash }) {
                r.duplicates.append(existing)
                continue
            }
            let name = "\(hash.prefix(12))-\(src.lastPathComponent)"
            let dest = filesURL.appendingPathComponent(name)
            if !FileManager.default.fileExists(atPath: dest.path) { try FileManager.default.copyItem(at: src, to: dest) }
            let size = (try? FileManager.default.attributesOfItem(atPath: dest.path)[.size] as? NSNumber)?.int64Value ?? 0
            var a = Asset(file: name, name: src.lastPathComponent, kind: AssetKind.of(src), bytes: size, sha256: hash, added: .now)
            a.metadata = await Self.metadata(dest, kind: a.kind)
            lock.withLock { assets.append(a) }
            r.added.append(a)
        }
        try save()
        return r
    }

    public func update(_ id: UUID, _ f: (inout Asset) -> Void) {
        lock.lock()
        if let i = assets.firstIndex(where: { $0.id == id }) { f(&assets[i]) }
        lock.unlock()
        try? save()
    }

    /// Removes the catalog entry and its stored copy (the user confirms in the UI first).
    public func remove(_ id: UUID) throws {
        lock.lock()
        let a = assets.first { $0.id == id }
        assets.removeAll { $0.id == id }
        lock.unlock()
        if let a { try? FileManager.default.removeItem(at: url(of: a)) }
        try save()
    }

    public func search(_ text: String, kind: AssetKind?, favoritesOnly: Bool, tag: String?) -> [Asset] {
        let q = text.lowercased().trimmingCharacters(in: .whitespaces)
        return assets.filter { a in
            (kind == nil || a.kind == kind) && (!favoritesOnly || a.favorite) && (tag == nil || a.tags.contains(tag!))
                && (q.isEmpty || a.name.lowercased().contains(q) || a.tags.contains { $0.lowercased().contains(q) }
                    || a.metadata.values.contains { $0.lowercased().contains(q) })
        }.sorted { $0.added > $1.added }
    }

    public var allTags: [String] { Array(Set(assets.flatMap(\.tags))).sorted() }

    static func metadata(_ url: URL, kind: AssetKind) async -> [String: String] {
        var m: [String: String] = [:]
        switch kind {
        case .photo, .raw:
            if let src = CGImageSourceCreateWithURL(url as CFURL, nil),
               let p = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any] {
                if let w = p[kCGImagePropertyPixelWidth], let h = p[kCGImagePropertyPixelHeight] { m["Dimensioni"] = "\(w)×\(h)" }
                if let tiff = p[kCGImagePropertyTIFFDictionary] as? [CFString: Any] {
                    if let make = tiff[kCGImagePropertyTIFFMake] as? String { m["Fotocamera"] = make.trimmingCharacters(in: .whitespaces) }
                    if let model = tiff[kCGImagePropertyTIFFModel] as? String { m["Modello"] = model.trimmingCharacters(in: .whitespaces) }
                }
                if let exif = p[kCGImagePropertyExifDictionary] as? [CFString: Any] {
                    if let iso = (exif[kCGImagePropertyExifISOSpeedRatings] as? [Int])?.first { m["ISO"] = "\(iso)" }
                    if let d = exif[kCGImagePropertyExifDateTimeOriginal] as? String { m["Data scatto"] = d }
                    if let f = exif[kCGImagePropertyExifFNumber] as? Double { m["Diaframma"] = String(format: "f/%.1f", f) }
                    if let e = exif[kCGImagePropertyExifExposureTime] as? Double { m["Tempo"] = e < 1 ? "1/\(Int((1 / e).rounded())) s" : "\(e) s" }
                    if let fl = exif[kCGImagePropertyExifFocalLength] as? Double { m["Focale"] = "\(Int(fl)) mm" }
                }
            }
        case .video, .audio:
            let a = AVURLAsset(url: url)
            if let d = try? await a.load(.duration).seconds, d.isFinite { m["Durata"] = String(format: "%.1f s", d) }
            if let v = try? await a.loadTracks(withMediaType: .video).first, let s = try? await v.load(.naturalSize) {
                m["Dimensioni"] = "\(Int(s.width))×\(Int(s.height))"
            }
        default: break
        }
        return m
    }

    public func thumbnail(_ a: Asset, size: CGSize) async -> UIImage? {
        let req = QLThumbnailGenerator.Request(fileAt: url(of: a), size: size, scale: 2, representationTypes: .thumbnail)
        return try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: req).uiImage
    }
}
