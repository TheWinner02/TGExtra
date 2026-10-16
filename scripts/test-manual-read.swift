import Foundation

@main
struct ManualReadTests {
    struct Namespace { let rawValue: UInt32 }
    struct Id { let rawValue: Int64 }
    struct PeerId { let namespace: Namespace; let id: Id }
    struct Thread { let peerId: PeerId; let threadId: Int64; var isMonoforumPost = false }
    enum Location { case peer(id: PeerId), replyThread(message: Thread), customChatContents }
    enum Hash { case personal(Int64), genericPublic(Int64), unsupported(Int64) }
    struct User { let id: PeerId; let accessHash: Hash? }
    static func peer(_ ns: UInt32, _ id: Int64) -> PeerId { PeerId(namespace: Namespace(rawValue: ns), id: Id(rawValue: id)) }
    static func u32(_ data: Data, _ offset: Int) -> UInt32 {
        data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset, as: UInt32.self).littleEndian }
    }
    static func i64(_ data: Data, _ offset: Int) -> Int64 {
        data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset, as: Int64.self).littleEndian }
    }
    static func main() {
        let user = peer(0, 123), group = peer(1, 456), channel = peer(2, 789)
        let userScope = ManualReadScope(location: Location.peer(id: user))!
        let groupScope = ManualReadScope(location: Location.peer(id: group))!
        let channelScope = ManualReadScope(location: Location.peer(id: channel))!
        precondition(userScope.peerKey == "123" && userScope.topic == nil)
        precondition(ManualReadScope(location: Location.customChatContents) == nil)
        precondition(ManualReadScope(location: Location.peer(id: peer(3, 123))) == nil)
        precondition(ManualReadScope(peerKey: "0") == nil)
        precondition(ManualReadScope(peerKey: "123", topic: 0) == nil)
        precondition(ManualReadScope(location: Location.replyThread(message: Thread(peerId: channel, threadId: 0))) == nil)
        precondition(ManualReadScope(location: Location.replyThread(message: Thread(peerId: channel, threadId: Int64(Int32.max) + 1))) == nil)
        precondition(ManualReadScope(location: Location.replyThread(message: Thread(peerId: channel, threadId: 77, isMonoforumPost: true))) == nil)
        let userData = ManualReadPolicy.payload(scope: userScope, profile: User(id: user, accessHash: .personal(-999)), ownPeerKey: nil)!
        precondition(userData.count == 28 && u32(userData, 0) == 0x0e306d3a && u32(userData, 4) == 0xdde8a54c)
        precondition(i64(userData, 8) == 123 && i64(userData, 16) == -999)
        precondition(u32(userData, 24) == UInt32(Int32.max - 1))
        let groupData = ManualReadPolicy.payload(scope: groupScope, profile: User(id: group, accessHash: nil), ownPeerKey: nil)!
        precondition(groupData.count == 20 && u32(groupData, 4) == 0x35a95cb9 && i64(groupData, 8) == 456)
        let channelData = ManualReadPolicy.payload(scope: channelScope, profile: User(id: channel, accessHash: .genericPublic(55)), ownPeerKey: nil)!
        precondition(channelData.count == 28 && u32(channelData, 0) == 0xcc104937 && u32(channelData, 4) == 0xf35aec28)
        precondition(i64(channelData, 8) == 789 && i64(channelData, 16) == 55)
        let topicScope = ManualReadScope(location: Location.replyThread(message: Thread(peerId: channel, threadId: 77)))!
        let topicData = ManualReadPolicy.payload(scope: topicScope, profile: User(id: channel, accessHash: .personal(55)), ownPeerKey: nil)!
        precondition(topicData.count == 32 && u32(topicData, 0) == 0xf731a9f4 && u32(topicData, 4) == 0x27bcbbfc)
        precondition(u32(topicData, 24) == 77 && u32(topicData, 28) == UInt32(Int32.max - 1))
        let botTopic = ManualReadScope(location: Location.replyThread(message: Thread(peerId: user, threadId: 1)))!
        precondition(u32(ManualReadPolicy.payload(scope: botTopic, profile: User(id: user, accessHash: .personal(42)), ownPeerKey: nil)!, 0) == 0xf731a9f4)
        precondition(ManualReadPolicy.payload(scope: userScope, profile: User(id: peer(0, 999), accessHash: .personal(55)), ownPeerKey: nil) == nil)
        precondition(ManualReadPolicy.payload(scope: userScope, profile: User(id: user, accessHash: nil), ownPeerKey: nil) == nil)
        precondition(ManualReadPolicy.payload(scope: userScope, profile: User(id: user, accessHash: .unsupported(55)), ownPeerKey: nil) == nil)
        let selfData = ManualReadPolicy.payload(scope: userScope, profile: User(id: user, accessHash: nil), ownPeerKey: "123")!
        precondition(selfData.count == 12 && u32(selfData, 4) == 0x7da07ec9)
        // Large user IDs must retain their high bits, not alias another account.
        let large = peer(0, 0x123456789)
        let largeScope = ManualReadScope(location: Location.peer(id: large))!
        let largeData = ManualReadPolicy.payload(scope: largeScope, profile: User(id: large, accessHash: .personal(8)), ownPeerKey: nil)!
        precondition(i64(largeData, 8) == 0x123456789)
        print("Manual read: peer types, topic isolation, ownership, access hashes and TL payloads passed")
    }
}
