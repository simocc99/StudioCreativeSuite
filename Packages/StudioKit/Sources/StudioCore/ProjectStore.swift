import Foundation

/// Header written at the top of every `project.json`. See docs/PROJECT_FORMAT.md.
public struct ProjectHeader: Codable, Hashable, Sendable {
    public var kind: StudioModule
    public var formatVersion: Int
    public var name: String
    public var created: Date
    public var modified: Date
    public var appVersion: String

    public init(kind: StudioModule, formatVersion: Int, name: String, created: Date = .now, modified: Date = .now, appVersion: String = StudioInfo.appVersion) {
        self.kind = kind
        self.formatVersion = formatVersion
        self.name = name
        self.created = created
        self.modified = modified
        self.appVersion = appVersion
    }
}

public struct ProjectFile<Payload: Codable>: Codable {
    public var header: ProjectHeader
    public var payload: Payload
}

/// A document payload stored in a Studio project.
public protocol ProjectPayload: Codable, Equatable {
    static var kind: StudioModule { get }
    /// Current format version written by this build. Bump it and register a migration when the payload changes shape.
    static var formatVersion: Int { get }
    init()
}

public struct ProjectSummary: Identifiable, Hashable, Sendable {
    public var id: URL { url }
    public let url: URL
    public let header: ProjectHeader
}

public enum StudioInfo {
    public static var appVersion: String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "dev"
    }
}

/// Migrations from older `project.json` payloads, applied in order on the raw JSON tree.
public enum ProjectMigrations {
    public typealias Step = @Sendable (JSONValue) throws -> JSONValue
    nonisolated(unsafe) private static var steps: [String: Step] = [:]
    private static let lock = NSLock()

    /// Registers the step that turns a `kind` payload of version `from` into version `from + 1`.
    public static func register(_ kind: StudioModule, from: Int, _ step: @escaping Step) {
        lock.lock(); defer { lock.unlock() }
        steps["\(kind.rawValue)#\(from)"] = step
    }

    static func migrate(_ payload: JSONValue, kind: StudioModule, from: Int, to: Int) throws -> JSONValue {
        var p = payload
        for v in from ..< to {
            lock.lock()
            let step = steps["\(kind.rawValue)#\(v)"]
            lock.unlock()
            guard let step else {
                throw StudioError.corruptProject("nessuna migrazione \(kind.rawValue) v\(v) → v\(v + 1)")
            }
            p = try step(p)
        }
        return p
    }
}

/// Projects live in `Documents/Projects/<name>.studio/` (a folder): `project.json` plus `Media/` for
/// copies of imported originals. Originals outside the project are never modified.
public final class ProjectStore: @unchecked Sendable {
    public static let shared = ProjectStore(root: StudioPaths.documents.appendingPathComponent("Projects", isDirectory: true))

    public let root: URL
    private let fm = FileManager.default

    public init(root: URL) {
        self.root = root
        try? fm.createDirectory(at: root, withIntermediateDirectories: true)
    }

    public static let fileName = "project.json"
    public static let mediaFolder = "Media"

    public func list() -> [ProjectSummary] {
        let items = (try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
        return items.filter { $0.pathExtension == "studio" }.compactMap { url in
            guard let h = try? readHeader(url) else { return nil }
            return ProjectSummary(url: url, header: h)
        }.sorted { $0.header.modified > $1.header.modified }
    }

    public func readHeader(_ url: URL) throws -> ProjectHeader {
        let data = try Data(contentsOf: url.appendingPathComponent(Self.fileName))
        struct Head: Decodable { var header: ProjectHeader }
        return try Self.decoder.decode(Head.self, from: data).header
    }

    /// Creates an empty project and returns its folder.
    public func create<P: ProjectPayload>(_ type: P.Type, name: String) throws -> URL {
        let url = uniqueURL(for: name)
        try fm.createDirectory(at: url.appendingPathComponent(Self.mediaFolder), withIntermediateDirectories: true)
        let file = ProjectFile(header: ProjectHeader(kind: P.kind, formatVersion: P.formatVersion, name: name), payload: P())
        try write(file, to: url)
        return url
    }

    public func load<P: ProjectPayload>(_ type: P.Type, from url: URL) throws -> ProjectFile<P> {
        let data: Data
        do { data = try Data(contentsOf: url.appendingPathComponent(Self.fileName)) } catch {
            throw StudioError.io(error.localizedDescription)
        }
        let tree: JSONValue
        do { tree = try JSONValue.parse(data) } catch { throw StudioError.corruptProject("JSON non valido") }
        guard let headerTree = tree["header"], var payload = tree["payload"] else {
            throw StudioError.corruptProject("intestazione o contenuto mancante")
        }
        let header: ProjectHeader
        do { header = try Self.decoder.decode(ProjectHeader.self, from: JSONEncoder().encode(headerTree)) } catch {
            throw StudioError.corruptProject("intestazione: \(error.localizedDescription)")
        }
        guard header.kind == P.kind else {
            throw StudioError.unsupportedFile("progetto \(header.kind.rawValue), atteso \(P.kind.rawValue)")
        }
        if header.formatVersion > P.formatVersion {
            throw StudioError.newerFormat(kind: P.kind.rawValue, found: header.formatVersion, supported: P.formatVersion)
        }
        if header.formatVersion < P.formatVersion {
            payload = try ProjectMigrations.migrate(payload, kind: P.kind, from: header.formatVersion, to: P.formatVersion)
        }
        do {
            let p = try Self.decoder.decode(P.self, from: JSONEncoder().encode(payload))
            var h = header
            h.formatVersion = P.formatVersion
            return ProjectFile(header: h, payload: p)
        } catch {
            throw StudioError.corruptProject("contenuto: \(error.localizedDescription)")
        }
    }

    /// Atomic write (temp file + replace), so a crash never leaves half a project.
    public func write<P: ProjectPayload>(_ file: ProjectFile<P>, to url: URL) throws {
        var f = file
        f.header.modified = .now
        f.header.formatVersion = P.formatVersion
        f.header.appVersion = StudioInfo.appVersion
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        enc.dateEncodingStrategy = .iso8601
        let data = try enc.encode(f)
        try fm.createDirectory(at: url, withIntermediateDirectories: true)
        try data.write(to: url.appendingPathComponent(Self.fileName), options: .atomic)
    }

    public func mediaURL(_ project: URL) -> URL {
        let m = project.appendingPathComponent(Self.mediaFolder, isDirectory: true)
        try? fm.createDirectory(at: m, withIntermediateDirectories: true)
        return m
    }

    /// Copies an external file into the project's Media folder (originals stay untouched) and
    /// returns the path relative to the project folder.
    public func importMedia(_ source: URL, into project: URL) throws -> String {
        let scoped = source.startAccessingSecurityScopedResource()
        defer { if scoped { source.stopAccessingSecurityScopedResource() } }
        let dir = mediaURL(project)
        var dest = dir.appendingPathComponent(source.lastPathComponent)
        var n = 2
        while fm.fileExists(atPath: dest.path) {
            dest = dir.appendingPathComponent("\(source.deletingPathExtension().lastPathComponent)-\(n).\(source.pathExtension)")
            n += 1
        }
        do { try fm.copyItem(at: source, to: dest) } catch { throw StudioError.io(error.localizedDescription) }
        return "\(Self.mediaFolder)/\(dest.lastPathComponent)"
    }

    public func resolve(_ relative: String, in project: URL) -> URL {
        project.appendingPathComponent(relative)
    }

    public func rename(_ url: URL, to name: String) throws -> URL {
        let dest = uniqueURL(for: name)
        try fm.moveItem(at: url, to: dest)
        let data = try Data(contentsOf: dest.appendingPathComponent(Self.fileName))
        if var tree = try? JSONValue.parse(data) {
            tree[path: "header.name"] = .string(name)
            let enc = JSONEncoder()
            enc.outputFormatting = [.prettyPrinted, .sortedKeys]
            try enc.encode(tree).write(to: dest.appendingPathComponent(Self.fileName), options: .atomic)
        }
        return dest
    }

    public func duplicate(_ url: URL) throws -> URL {
        let h = try readHeader(url)
        let dest = uniqueURL(for: h.name + " copia")
        try fm.copyItem(at: url, to: dest)
        return dest
    }

    /// Moves a project to `Documents/Deleted Projects` instead of erasing it.
    public func moveToDeleted(_ url: URL) throws {
        let bin = StudioPaths.documents.appendingPathComponent("Deleted Projects", isDirectory: true)
        try fm.createDirectory(at: bin, withIntermediateDirectories: true)
        var dest = bin.appendingPathComponent(url.lastPathComponent)
        if fm.fileExists(atPath: dest.path) {
            dest = bin.appendingPathComponent("\(UUID().uuidString.prefix(6))-\(url.lastPathComponent)")
        }
        try fm.moveItem(at: url, to: dest)
    }

    private func uniqueURL(for name: String) -> URL {
        let safe = name.replacingOccurrences(of: "/", with: "-").trimmingCharacters(in: .whitespaces)
        let base = safe.isEmpty ? "Senza titolo" : safe
        var url = root.appendingPathComponent(base + ".studio", isDirectory: true)
        var n = 2
        while fm.fileExists(atPath: url.path) {
            url = root.appendingPathComponent("\(base) \(n).studio", isDirectory: true)
            n += 1
        }
        return url
    }

    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}

public enum StudioPaths {
    public static var documents: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    public static var exports: URL {
        let u = documents.appendingPathComponent("Exports", isDirectory: true)
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }

    public static var caches: URL {
        let u = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("Studio", isDirectory: true)
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }

    public static func temporaryFile(_ ext: String) -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension(ext)
    }

    /// A non-clobbering file URL in Exports.
    public static func exportURL(name: String, ext: String) -> URL {
        let base = name.replacingOccurrences(of: "/", with: "-")
        var url = exports.appendingPathComponent(base).appendingPathExtension(ext)
        var n = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = exports.appendingPathComponent("\(base) \(n)").appendingPathExtension(ext)
            n += 1
        }
        return url
    }
}
