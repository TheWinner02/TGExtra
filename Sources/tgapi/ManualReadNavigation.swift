import Foundation

enum ManualReadNavigation {
    // Keep the latest native buttons and their original objects/action targets.
    // Repeated single/multiple/empty assignments must produce exactly one eye.
    static func items<Item: AnyObject>(_ proposed: [Item], eye: Item) -> [Item] {
        proposed.filter { $0 !== eye } + [eye]
    }
}
