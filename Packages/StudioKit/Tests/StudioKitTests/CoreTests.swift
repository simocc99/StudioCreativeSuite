@testable import StudioCore
import XCTest

struct DummyPayload: ProjectPayload {
    static let kind = StudioModule.layout
    static let formatVersion = 2
    var title = "x"
    var count = 0
    init() {}
}

final class CoreTests: XCTestCase {
    func testJSONValuePaths() throws {
        var v = try JSONValue.parse(#"{"light":{"exposure":0,"contrast":10},"version":1}"#)
        v[path: "light.exposure"] = .number(0.5)
        v[path: "new.deep.key"] = .string("a")
        check("json.path", v[path: "light.exposure"]?.doubleValue == 0.5 && v[path: "new.deep.key"]?.stringValue == "a" && v[path: "light.contrast"]?.doubleValue == 10,
              expected: "set/get nested keeps siblings", observed: v.jsonString())
        // integers stay integers (serde u32 fields)
        check("json.int", v.jsonString().contains(#""version":1"#), expected: "\"version\":1", observed: v.jsonString())
    }

    func testUndoHistory() {
        var h = UndoHistory<Int>()
        h.record(0, label: "a")
        h.record(1, label: "b")
        var cur = 2
        cur = h.undo(current: cur)!
        cur = h.undo(current: cur)!
        XCTAssertEqual(cur, 0)
        cur = h.redo(current: cur)!
        XCTAssertEqual(cur, 1)
        h.beginCoalescing()
        h.record(1, label: "drag"); h.record(5, label: "drag"); h.record(9, label: "drag")
        h.endCoalescing()
        check("undo.coalesce", h.past.count == 2, expected: "a drag is one undo step", observed: "\(h.past.count) steps")
    }

    func testProjectRoundTripAndMigration() throws {
        let store = ProjectStore(root: Fixtures.tempDir("store"))
        ProjectMigrations.register(.layout, from: 1) { p in
            var p = p
            p["count"] = .number(42)
            return p
        }
        let url = try store.create(DummyPayload.self, name: "Prova")
        var f = try store.load(DummyPayload.self, from: url)
        f.payload.title = "salvato"
        try store.write(f, to: url)
        let back = try store.load(DummyPayload.self, from: url)
        check("project.roundtrip", back.payload.title == "salvato", expected: "salvato", observed: back.payload.title)

        // an older file is migrated on load
        let file = url.appendingPathComponent(ProjectStore.fileName)
        var tree = try JSONValue.parse(Data(contentsOf: file))
        tree[path: "header.formatVersion"] = .number(1)
        tree[path: "payload.count"] = nil
        try JSONEncoder().encode(tree).write(to: file)
        let migrated = try store.load(DummyPayload.self, from: url)
        check("project.migration", migrated.payload.count == 42 && migrated.header.formatVersion == 2, expected: "count 42, v2",
              observed: "count \(migrated.payload.count), v\(migrated.header.formatVersion)")

        // a newer file is refused, not misread
        tree[path: "header.formatVersion"] = .number(99)
        try JSONEncoder().encode(tree).write(to: file)
        XCTAssertThrowsError(try store.load(DummyPayload.self, from: url)) { e in
            check("project.newer", (e as? StudioError).map { if case .newerFormat = $0 { true } else { false } } ?? false,
                  expected: "newerFormat error", observed: "\(e)")
        }

        // corrupt JSON is reported
        try Data("{not json".utf8).write(to: file)
        XCTAssertThrowsError(try store.load(DummyPayload.self, from: url))

        // delete moves, never erases
        try store.moveToDeleted(url)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    func testImportMediaNeverOverwrites() throws {
        let store = ProjectStore(root: Fixtures.tempDir("media"))
        let url = try store.create(DummyPayload.self, name: "M")
        let src = Fixtures.tempDir("src").appendingPathComponent("a.png")
        Fixtures.png(src, width: 4, height: 4, color: .black)
        let a = try store.importMedia(src, into: url)
        let b = try store.importMedia(src, into: url)
        check("media.unique", a != b && FileManager.default.fileExists(atPath: src.path), expected: "two distinct copies, original kept", observed: "\(a), \(b)")
    }
}
