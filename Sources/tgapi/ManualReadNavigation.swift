import Foundation

enum ManualReadNavigation {
    struct Pending<Item: AnyObject> {
        private var latest: [Item]?
        mutating func stage(_ items: [Item]) { latest = items }
        mutating func take() -> [Item]? {
            let result = latest
            latest = nil
            return result
        }
        mutating func cancel() { latest = nil }
    }

    static func identical<Item: AnyObject>(_ lhs: [Item], _ rhs: [Item]) -> Bool {
        lhs.count == rhs.count && zip(lhs, rhs).allSatisfy { $0.0 === $0.1 }
    }

    // Keep the latest native buttons and their original objects/action targets.
    // Repeated single/multiple/empty assignments must produce exactly one eye.
    static func items<Item: AnyObject>(_ proposed: [Item], eye: Item) -> [Item] {
        proposed.filter { $0 !== eye } + [eye]
    }
}
