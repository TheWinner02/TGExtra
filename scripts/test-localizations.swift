import Foundation

@main
private struct LocalizationTests {
    static func main() throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let bundle = root.appendingPathComponent("TGExtra.bundle")
        let manifest = try JSONSerialization.jsonObject(with: Data(contentsOf: bundle.appendingPathComponent("langs.json"))) as! [[String: String]]
        let languages = manifest.compactMap { $0["code"] }
        precondition(languages.count == manifest.count && Set(languages).count == languages.count)
        let keyExpression = try NSRegularExpression(pattern: #"(?m)^\s*"([^"]+)"\s*="#)
        let formatExpression = try NSRegularExpression(pattern: #"%%|%(?:\d+\$)?[-+ #0]*(?:\d+|\*)?(?:\.(?:\d+|\*))?(?:hh|ll|[hlLzjtq])?[diuoxXfFeEgGaAcCsSp@]"#)
        func formats(_ text: String) -> [String] {
            formatExpression.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap {
                guard let range = Range($0.range, in: text) else { return nil }
                let token = String(text[range])
                return token == "%%" ? nil : token
            }.sorted()
        }
        func read(_ language: String) throws -> [String: String] {
            let file = bundle.appendingPathComponent("\(language).lproj/Localizable.strings")
            let text = try String(contentsOf: file, encoding: .utf8)
            guard let values = NSDictionary(contentsOfFile: file.path) as? [String: String] else {
                fatalError("Invalid strings file: \(language)")
            }
            let matches = keyExpression.matches(in: text, range: NSRange(text.startIndex..., in: text))
            let keys = matches.map { String(text[Range($0.range(at: 1), in: text)!]) }
            precondition(Set(keys).count == keys.count, "Duplicate keys: \(language)")
            precondition(keys.count == values.count, "Unrecognized entries: \(language)")
            precondition(!values.values.contains(where: { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }), "Empty translations: \(language)")
            return values
        }
        let english = try read("en")
        for language in languages {
            let values = try read(language)
            let missing = Set(english.keys).subtracting(values.keys).sorted()
            let extra = Set(values.keys).subtracting(english.keys).sorted()
            precondition(missing.isEmpty && extra.isEmpty, "\(language): missing \(missing); extra \(extra)")
            for (key, value) in values {
                precondition(formats(value) == formats(english[key]!), "Format arguments differ: \(language)/\(key)")
            }
            print("\(language): \(values.count) nonempty translations; keys and format arguments OK")
        }
        // Keep every literal UI lookup backed by the English reference catalog.
        let lookup = try NSRegularExpression(pattern: #"(?:TGLoc\(@|localizedStringForKey:@|text\()"([A-Z][A-Z0-9_]+)""#)
        let sources = FileManager.default.enumerator(at: root.appendingPathComponent("Sources"), includingPropertiesForKeys: nil)!
        for case let file as URL in sources where ["m", "xm", "swift"].contains(file.pathExtension) {
            let text = try String(contentsOf: file, encoding: .utf8)
            for match in lookup.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                let key = String(text[Range(match.range(at: 1), in: text)!])
                precondition(english[key] != nil, "Unknown UI key: \(key) in \(file.lastPathComponent)")
            }
        }
        print("Localization coverage passed for all \(languages.count) supported languages")
    }
}
