import Foundation

@objc(TGExtraAdFilter)
class TGExtraAdFilter: NSObject {
    @objc(nodeIsAdvertisement:)
    static func nodeIsAdvertisement(_ node: Any) -> Bool {
        var budget = 400
        return containsAdAttribute(node, depth: 0, budget: &budget)
    }

    private static func containsAdAttribute(_ value: Any, depth: Int, budget: inout Int) -> Bool {
        guard depth <= 12, budget > 0 else { return false }
        budget -= 1
        let typeName = String(reflecting: type(of: value))
        if typeName == "AdMessageAttribute" || typeName.hasSuffix(".AdMessageAttribute") {
            return true
        }
        // Inspect only the cell's message/attributes path, not text, links,
        // reply previews or the broader account/controller object graph.
        let labels: Set<String> = ["item", "_item", "content", "_content",
            "message", "_message", "firstMessage", "messages", "attributes",
            "_attributes", "_impl", "_value", "value"]
        var current: Mirror? = Mirror(reflecting: value)
        while let mirror = current {
            let structural = mirror.displayStyle == .optional || mirror.displayStyle == .enum ||
                mirror.displayStyle == .tuple || mirror.displayStyle == .collection
            for child in mirror.children.prefix(100) where structural || labels.contains(child.label ?? "") {
                if containsAdAttribute(child.value, depth: depth + 1, budget: &budget) { return true }
            }
            current = mirror.superclassMirror
        }
        return false
    }
}
