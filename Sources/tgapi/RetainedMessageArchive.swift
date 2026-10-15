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
    // View-only filtering: never remove unresolved records from the registry.
    static func visibleChats(_ chats: [RetainedArchiveChat], showRecordsWithoutContent: Bool = false) -> [RetainedArchiveChat] {
        chats.enumerated().compactMap { offset, chat -> (Int, RetainedArchiveChat)? in
            let messages = chat.messages.filter { showRecordsWithoutContent || $0.available }.sorted {
                if $0.available != $1.available { return $0.available }
                if ($0.timestamp ?? 0) != ($1.timestamp ?? 0) { return ($0.timestamp ?? 0) > ($1.timestamp ?? 0) }
                return $0.id > $1.id
            }
            guard !messages.isEmpty else { return nil }
            return (offset, RetainedArchiveChat(key: chat.key, title: chat.title, messages: messages))
        }.sorted {
            let left = $0.1.messages.contains { $0.available }
            let right = $1.1.messages.contains { $0.available }
            return left == right ? $0.0 < $1.0 : left
        }.map { $0.1 }
    }

    // SimpleDictionary can store entries as a flat tuple array rather than a
    // native Dictionary. Walk storage only; stop at identifiable peer values.
    static func peerValues(in storage: Any) -> [Any] {
        var budget = 4096
        func visit(_ value: Any, depth: Int) -> [Any] {
            guard depth <= 8, budget > 0 else { return [] }
            budget -= 1
            let mirror = Mirror(reflecting: value)
            var current: Mirror? = mirror
            while let fields = current {
                if fields.children.contains(where: { $0.label == "id" }) { return [value] }
                current = fields.superclassMirror
            }
            return mirror.children.prefix(512).flatMap { visit($0.value, depth: depth + 1) }
        }
        return visit(storage, depth: 0)
    }

    static func displayTitle(_ chat: RetainedArchiveChat, chatLabel: String, unknownLabel: String) -> String {
        guard let packed = Int64(chat.key) else { return unknownLabel }
        let bits = UInt64(bitPattern: packed)
        let raw = (bits & 0xffffffff) | ((bits >> 35) << 32)
        let title = chat.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? "\(chatLabel) \(raw)" : "\(title) (ID \(raw))"
    }

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
