import Foundation

/// A JSON tree that is `Codable`, `Equatable` and `Sendable`: used for engine settings whose schema
/// belongs to the engine (e.g. LightCraft `DevelopSettings`), so the app never drops fields it does not know.
public enum JSONValue: Codable, Equatable, Hashable, Sendable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let b = try? c.decode(Bool.self) { self = .bool(b) }
        else if let n = try? c.decode(Double.self) { self = .number(n) }
        else if let s = try? c.decode(String.self) { self = .string(s) }
        else if let a = try? c.decode([JSONValue].self) { self = .array(a) }
        else { self = .object(try c.decode([String: JSONValue].self)) }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null: try c.encodeNil()
        case .bool(let b): try c.encode(b)
        case .number(let n):
            // integers stay integers (serde rejects 1.0 for u32 fields such as `version`)
            if n.rounded() == n, abs(n) < 1e15 { try c.encode(Int64(n)) } else { try c.encode(n) }
        case .string(let s): try c.encode(s)
        case .array(let a): try c.encode(a)
        case .object(let o): try c.encode(o)
        }
    }

    public static func parse(_ data: Data) throws -> JSONValue {
        try JSONDecoder().decode(JSONValue.self, from: data)
    }

    public static func parse(_ string: String) throws -> JSONValue {
        try parse(Data(string.utf8))
    }

    public func jsonString() -> String {
        let enc = JSONEncoder()
        enc.outputFormatting = [.sortedKeys]
        return (try? String(data: enc.encode(self), encoding: .utf8)) ?? "null"
    }

    public subscript(key: String) -> JSONValue? {
        get { if case .object(let o) = self { o[key] } else { nil } }
        set {
            guard case .object(var o) = self else { return }
            o[key] = newValue
            self = .object(o)
        }
    }

    /// Value at a dotted path such as `light.exposure`.
    public subscript(path path: String) -> JSONValue? {
        get {
            var cur: JSONValue? = self
            for k in path.split(separator: ".") { cur = cur?[String(k)] }
            return cur
        }
        set {
            let keys = path.split(separator: ".").map(String.init)
            self = Self.setting(self, keys[...], newValue ?? .null)
        }
    }

    private static func setting(_ node: JSONValue, _ keys: ArraySlice<String>, _ value: JSONValue) -> JSONValue {
        guard let first = keys.first else { return value }
        var obj: [String: JSONValue] = if case .object(let o) = node { o } else { [:] }
        obj[first] = setting(obj[first] ?? .null, keys.dropFirst(), value)
        return .object(obj)
    }

    public var doubleValue: Double? { if case .number(let n) = self { n } else { nil } }
    public var stringValue: String? { if case .string(let s) = self { s } else { nil } }
    public var boolValue: Bool? { if case .bool(let b) = self { b } else { nil } }
}
