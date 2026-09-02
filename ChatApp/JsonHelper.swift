import Foundation

/// Alias léger pour un objet JSON décodé, utilisé partout dans l'app à la
/// place d'un vrai modèle Codable (les réponses du serveur sont assez
/// variables — équivalent des JSONObject/JSONArray côté Android).
typealias JSONDict = [String: Any]

extension Dictionary where Key == String, Value == Any {

    func dict(_ key: String) -> JSONDict? {
        self[key] as? JSONDict
    }

    func array(_ key: String) -> [JSONDict] {
        (self[key] as? [JSONDict]) ?? []
    }

    func intArray(_ key: String) -> [Int] {
        guard let raw = self[key] as? [Any] else { return [] }
        return raw.compactMap { value in
            if let n = value as? Int { return n }
            if let n = value as? NSNumber { return n.intValue }
            if let s = value as? String { return Int(s) }
            return nil
        }
    }

    func int(_ key: String, _ defaultValue: Int = 0) -> Int {
        if let n = self[key] as? Int { return n }
        if let n = self[key] as? NSNumber { return n.intValue }
        if let s = self[key] as? String, let n = Int(s) { return n }
        return defaultValue
    }

    func int64(_ key: String, _ defaultValue: Int64 = 0) -> Int64 {
        if let n = self[key] as? Int64 { return n }
        if let n = self[key] as? NSNumber { return n.int64Value }
        if let s = self[key] as? String, let n = Int64(s) { return n }
        return defaultValue
    }

    func string(_ key: String, _ defaultValue: String = "") -> String {
        if let s = self[key] as? String { return s }
        if let n = self[key] as? NSNumber { return n.stringValue }
        return defaultValue
    }

    func optString(_ key: String) -> String? {
        self[key] as? String
    }

    func bool(_ key: String, _ defaultValue: Bool = false) -> Bool {
        if let b = self[key] as? Bool { return b }
        if let n = self[key] as? NSNumber { return n.boolValue }
        if let n = self[key] as? Int { return n != 0 }
        return defaultValue
    }

    func isNull(_ key: String) -> Bool {
        self[key] == nil || self[key] is NSNull
    }
}

/// Convertit du JSON brut (Data) en JSONDict / [JSONDict], en normalisant
/// NSNull -> valeurs manquantes pour que `isNull`/`optString` fonctionnent.
enum JSONParsing {
    static func dict(from data: Data) throws -> JSONDict {
        let obj = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        guard let d = obj as? JSONDict else {
            throw APIError.invalidResponse
        }
        return d
    }

    static func array(from data: Data) throws -> [JSONDict] {
        let obj = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        guard let arr = obj as? [JSONDict] else {
            throw APIError.invalidResponse
        }
        return arr
    }
}
