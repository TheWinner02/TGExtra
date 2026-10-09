import Foundation

@main
struct RetainedMessageIdentityTests {
    static func main() {
        let first = RetainedMessageIdentity.channel(100, message: 42)!
        let second = RetainedMessageIdentity.channel(200, message: 42)!
        let record: [String: Any] = ["channel": NSNumber(value: 100), "id": NSNumber(value: 42)]
        precondition(first.matches(record: record))
        precondition(!second.matches(record: record), "Same raw ID in another group must not match")
        precondition(!first.matches(record: ["channel": NSNumber(value: 0), "id": NSNumber(value: 42)]))
        precondition(!first.matches(record: ["channel": NSNumber(value: 100), "id": NSNumber(value: 43)]))
        let complete: [String: Any] = ["peer": NSNumber(value: first.peer), "namespace": NSNumber(value: 0), "id": NSNumber(value: 42)]
        precondition(first.matches(record: complete))
        precondition(!second.matches(record: complete))
        precondition(!RetainedMessageIdentity(peer: first.peer, namespace: 1, id: 42).matches(record: complete))
        for namespace in 0...1 {
            let group = RetainedMessageIdentity(peer: Int64(100) | (Int64(namespace) << 32), namespace: 0, id: 42)
            precondition(group.matches(record: ["channel": NSNumber(value: 0), "id": NSNumber(value: 42)]))
        }
        for invalid in [Int64(-1), 0, Int64(1) << 56, Int64(1) << 61] {
            precondition(RetainedMessageIdentity.channel(invalid, message: 42) == nil)
        }
        precondition(RetainedMessageIdentity.channel(100, message: 0) == nil)
        precondition(RetainedMessageIdentity.channel(100, message: -1) == nil)
        let large = RetainedMessageIdentity.channel((Int64(1) << 40) + 123, message: 42)!
        precondition(large.matches(record: ["channel": NSNumber(value: (Int64(1) << 40) + 123), "id": NSNumber(value: 42)]))
        let bytes = Array(RetainedMessageIdentity.encoded([first, second]))
        precondition(bytes.count == 36)
        precondition(Array(bytes.prefix(4)) == [2, 0, 0, 0])
        precondition(Array(bytes[4..<12]) == [100, 0, 0, 0, 2, 0, 0, 0])
        precondition(Array(bytes[12..<20]) == [0, 0, 0, 0, 42, 0, 0, 0])
        precondition(Array(RetainedMessageIdentity.encoded([])) == [0, 0, 0, 0])
        print("Retained-message identity: all checks passed")
    }
}
