import Foundation

struct RetainedArchiveMessage: Equatable {
    let chatKey: String
    let chatTitle: String
    let id: Int32
    let timestamp: Int32?
    let text: String
    let kind: String
    let topic: Int64?
    let available: Bool
    var topicTitle: String? = nil
}

struct RetainedArchiveChat {
    let key: String
    let title: String
    let messages: [RetainedArchiveMessage]
}

enum RetainedMessageArchive {
    // Postbox may wrap a Swift Dictionary in SimpleDictionary storage.
    static func dictionary(in value: Any, depth: Int = 0) -> Any? {
        let mirror = Mirror(reflecting: value)
        if mirror.displayStyle == .dictionary { return value }
        guard depth < 4 else { return nil }
        for child in mirror.children.prefix(8) {
            if let dictionary = dictionary(in: child.value, depth: depth + 1) { return dictionary }
        }
        return nil
    }

    static func grouped(_ messages: [RetainedArchiveMessage]) -> [RetainedArchiveChat] {
        Dictionary(grouping: messages, by: { $0.chatKey }).map { key, items in
            let title = items.first(where: { !$0.chatTitle.isEmpty })?.chatTitle ?? ""
            let sorted = items.sorted {
                if ($0.timestamp ?? 0) != ($1.timestamp ?? 0) { return ($0.timestamp ?? 0) > ($1.timestamp ?? 0) }
                return $0.id > $1.id
            }
            return RetainedArchiveChat(key: key, title: title, messages: sorted)
        }.sorted {
            let comparison = $0.title.localizedCaseInsensitiveCompare($1.title)
            return comparison == .orderedSame ? $0.key < $1.key : comparison == .orderedAscending
        }
    }
}
