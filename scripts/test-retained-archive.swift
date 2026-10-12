import Foundation

@main
struct RetainedArchiveTests {
    static func main() {
        func item(_ chat: String, _ title: String, _ id: Int32, _ date: Int32?, _ available: Bool = true) -> RetainedArchiveMessage {
            RetainedArchiveMessage(chatKey: chat, chatTitle: title, id: id, timestamp: date,
                text: "text \(id)", kind: "text", topic: 7, available: available, topicTitle: "Topic example")
        }
        precondition(RetainedMessageArchive.grouped([]).isEmpty)
        let messages = [item("100", "Group", 42, 100), item("200", "Group", 42, 200),
            item("100", "", 43, nil, false), item("100", "Group", 44, 300),
            item("unresolved", "", 99, nil, false)]
        let chats = RetainedMessageArchive.grouped(messages)
        precondition(chats.count == 3, "Equal titles or raw IDs must not merge distinct peers")
        let group = chats.first { $0.key == "100" }!
        precondition(group.title == "Group")
        precondition(group.messages.map { $0.id } == [44, 42, 43])
        precondition(group.messages.last?.available == false, "Unavailable records must remain visible")
        precondition(group.messages.first?.text == "text 44")
        precondition(group.messages.first?.topic == 7)
        precondition(group.messages.first?.topicTitle == "Topic example")
        let zero = RetainedMessageArchive.grouped([item("100", "Group", 1, nil), item("100", "Group", 2, 0)])
        precondition(zero[0].messages.map { $0.id } == [2, 1])
        struct WrappedDictionary { let storage: [Int: String] }
        precondition(RetainedMessageArchive.dictionary(in: WrappedDictionary(storage: [1: "Chat"])) as? [Int: String] == [1: "Chat"])
        precondition(RetainedMessageArchive.dictionary(in: "not a dictionary") == nil)
        let many = (1...10_000).map { item(String($0 % 100), "Chat", Int32($0), Int32($0)) }
        let large = RetainedMessageArchive.grouped(many)
        precondition(large.count == 100)
        precondition(large.reduce(0) { $0 + $1.messages.count } == 10_000)
        print("Retained archive: all checks passed")
    }
}
