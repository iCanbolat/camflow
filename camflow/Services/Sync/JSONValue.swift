import Foundation

/// A dynamically-typed JSON value. The sync engine speaks the backend's generic
/// row shape — `/sync/pull` returns each entity as an arbitrary column→value map
/// (`rowToJson`) and `/sync/push` accepts an arbitrary `payload` object — so rows
/// and payloads are carried as `[String: JSONValue]` instead of a DTO per entity.
///
/// `nonisolated` + `Sendable` so it crosses the networking actors and the
/// `@ModelActor` sync context freely. Integers decode before doubles so whole
/// numbers (counts, sort orders) round-trip through JSON blob columns unchanged.
nonisolated enum JSONValue: Codable, Sendable, Equatable {
    case string(String)
    case int(Int)
    case number(Double)
    case bool(Bool)
    case array([JSONValue])
    case object([String: JSONValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let bool = try? container.decode(Bool.self) {
            self = .bool(bool)
        } else if let int = try? container.decode(Int.self) {
            self = .int(int)
        } else if let double = try? container.decode(Double.self) {
            self = .number(double)
        } else if let string = try? container.decode(String.self) {
            self = .string(string)
        } else if let array = try? container.decode([JSONValue].self) {
            self = .array(array)
        } else if let object = try? container.decode([String: JSONValue].self) {
            self = .object(object)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unsupported JSON value."
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case let .string(value): try container.encode(value)
        case let .int(value): try container.encode(value)
        case let .number(value): try container.encode(value)
        case let .bool(value): try container.encode(value)
        case let .array(value): try container.encode(value)
        case let .object(value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }

    /// Re-encodes a nested JSON value to raw `Data` for a SwiftData blob column
    /// (`Photo.annotationData`, `Page.contentData`, `Measurement.segmentsData`).
    init?(data: Data) {
        guard let value = try? JSONCoding.makeDecoder().decode(JSONValue.self, from: data) else {
            return nil
        }
        self = value
    }

    var data: Data? { try? JSONCoding.makeEncoder().encode(self) }
}

// MARK: - Typed accessors

nonisolated extension JSONValue {
    var stringValue: String? { if case let .string(value) = self { return value }; return nil }
    var boolValue: Bool? { if case let .bool(value) = self { return value }; return nil }
    var arrayValue: [JSONValue]? { if case let .array(value) = self { return value }; return nil }
    var objectValue: [String: JSONValue]? { if case let .object(value) = self { return value }; return nil }
    var isNull: Bool { if case .null = self { return true }; return false }

    var doubleValue: Double? {
        switch self {
        case let .number(value): return value
        case let .int(value): return Double(value)
        default: return nil
        }
    }

    var intValue: Int? {
        switch self {
        case let .int(value): return value
        case let .number(value): return Int(value)
        default: return nil
        }
    }
}

// MARK: - Row reader

/// One server row / one push payload: a column→value map. (`JSONValue` is
/// `Sendable`, so the dictionary is too — it crosses the sync actors freely.)
typealias SyncRow = [String: JSONValue]

/// Typed getters over a decoded sync row. `nonisolated` so the `@ModelActor`
/// mapper can read rows without hopping to the main actor.
nonisolated extension Dictionary where Key == String, Value == JSONValue {
    func string(_ key: String) -> String? { self[key]?.stringValue }
    func bool(_ key: String) -> Bool? { self[key]?.boolValue }
    func double(_ key: String) -> Double? { self[key]?.doubleValue }
    func int(_ key: String) -> Int? { self[key]?.intValue }

    func uuid(_ key: String) -> UUID? {
        self[key]?.stringValue.flatMap(UUID.init(uuidString:))
    }

    func date(_ key: String) -> Date? {
        self[key]?.stringValue.flatMap(JSONCoding.parseDate)
    }

    func uuids(_ key: String) -> [UUID] {
        (self[key]?.arrayValue ?? []).compactMap { $0.stringValue.flatMap(UUID.init(uuidString:)) }
    }

    func strings(_ key: String) -> [String] {
        (self[key]?.arrayValue ?? []).compactMap(\.stringValue)
    }

    /// A nested JSON value re-encoded to raw `Data` for a SwiftData blob column;
    /// nil when the column is absent or JSON `null`.
    func jsonData(_ key: String) -> Data? {
        guard let value = self[key], !value.isNull else { return nil }
        return value.data
    }

    /// A `{ "<uuid>": "<note>" }` object decoded into `[UUID: String]`
    /// (`Report.photoNotes`).
    func uuidStringMap(_ key: String) -> [UUID: String] {
        guard let object = self[key]?.objectValue else { return [:] }
        var result: [UUID: String] = [:]
        for (rawKey, value) in object {
            if let id = UUID(uuidString: rawKey), let text = value.stringValue {
                result[id] = text
            }
        }
        return result
    }
}
