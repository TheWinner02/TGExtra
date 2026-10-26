import Foundation

// Read stored primitives only. Never mutate message attributes or use Telegram
// Swift value types through layout-only compatibility stubs.
enum SpoilerPolicy {
    static func stored(_ name: String, in value: Any) -> Any? {
        var mirror: Mirror? = Mirror(reflecting: value)
        while let current = mirror {
            if let field = current.children.first(where: { $0.label == name }) {
                let optional = Mirror(reflecting: field.value)
                return optional.displayStyle == .optional ? optional.children.first?.value : field.value
            }
            mirror = current.superclassMirror
        }
        return nil
    }

    static func name(_ value: Any) -> String {
        String(reflecting: type(of: value)).split(separator: ".").last.map(String.init) ?? ""
    }

    static func message(_ value: Any) -> Any { stored("impl", in: value) ?? value }

    private static func elements(_ name: String, in value: Any) -> [Any]? {
        guard let field = stored(name, in: value) else { return nil }
        let mirror = Mirror(reflecting: field)
        guard mirror.displayStyle == .collection else { return nil }
        return mirror.children.map { $0.value }
    }

    static func hasTextSpoiler(_ value: Any) -> Bool {
        guard let attributes = elements("attributes", in: message(value)) else { return false }
        for attribute in attributes where name(attribute) == "TextEntitiesMessageAttribute" {
            guard let entities = elements("entities", in: attribute) else { continue }
            for entity in entities {
                if let type = stored("type", in: entity),
                   Mirror(reflecting: type).displayStyle == .enum,
                   String(describing: type) == "Spoiler" { return true }
            }
        }
        return false
    }

    static func canRevealMedia(_ value: Any) -> Bool {
        let value = message(value)
        guard let attributes = elements("attributes", in: value),
              attributes.contains(where: { name($0) == "MediaSpoilerMessageAttribute" }),
              let media = elements("media", in: value), !media.isEmpty else { return false }
        // These overlays share the dust renderer but are NOT ordinary spoilers.
        let protectedAttributes: Set<String> = ["AutoclearTimeoutMessageAttribute",
            "AutoremoveTimeoutMessageAttribute", "RestrictedContentMessageAttribute",
            "PaidContentMessageAttribute"]
        guard !attributes.contains(where: { protectedAttributes.contains(name($0)) }) else { return false }
        return media.allSatisfy { ["TelegramMediaImage", "TelegramMediaFile"].contains(name($0)) }
    }
}
