import Foundation

struct ManualReadScope: Equatable {
    let peerKey: String
    let topic: Int32?

    init?(peerKey: String, topic: Int32? = nil) {
        guard let packed = Int64(peerKey), packed > 0 else { return nil }
        let bits = UInt64(packed)
        let namespace = UInt32((bits >> 32) & 7)
        let raw = (bits & 0xffffffff) | ((bits >> 35) << 32)
        guard namespace <= 2, raw > 0, raw < (1 << 56), topic == nil || topic! > 0 else { return nil }
        self.peerKey = peerKey
        self.topic = topic
    }

    init?(location: Any) {
        guard let item = Mirror(reflecting: location).children.first else { return nil }
        let value = ManualReadPolicy.singleValue(item.value)
        switch item.label {
        case "peer":
            guard let key = AccountAvatarPolicy.peerKey(value) else { return nil }
            self.init(peerKey: key)
        case "replyThread":
            guard AccountAvatarPolicy.stored("isMonoforumPost", in: value) as? Bool != true,
                  let peer = AccountAvatarPolicy.stored("peerId", in: value),
                  let key = AccountAvatarPolicy.peerKey(peer),
                  let thread = AccountAvatarPolicy.stored("threadId", in: value) as? Int64,
                  thread > 0, thread <= Int64(Int32.max) else { return nil }
            self.init(peerKey: key, topic: Int32(thread))
        default: return nil
        }
    }
}

enum ManualReadPolicy {
    // Telegram's own mark-all-read implementation uses this upper bound.
    static let maxReadId = Int32.max - 1

    static func singleValue(_ value: Any) -> Any {
        var result = value
        for _ in 0..<4 {
            let mirror = Mirror(reflecting: result)
            guard mirror.displayStyle == .tuple, mirror.children.count == 1,
                  let first = mirror.children.first else { break }
            result = first.value
        }
        return result
    }

    static func payload(scope: ManualReadScope, profile: Any, ownPeerKey: String?) -> Data? {
        guard let peer = AccountAvatarPolicy.stored("id", in: profile),
              AccountAvatarPolicy.peerKey(peer) == scope.peerKey,
              let packed = Int64(scope.peerKey) else { return nil }
        let bits = UInt64(packed)
        let namespace = UInt32((bits >> 32) & 7)
        let id = Int64((bits & 0xffffffff) | ((bits >> 35) << 32))
        var hash: Int64?
        if let value = AccountAvatarPolicy.stored("accessHash", in: profile) {
            if let plain = value as? Int64 { hash = plain }
            else if let entry = Mirror(reflecting: value).children.first,
                    ["personal", "genericPublic"].contains(entry.label ?? "") {
                hash = singleValue(entry.value) as? Int64
            }
        }
        var data = Data()
        func int32(_ value: UInt32) {
            var value = value.littleEndian
            withUnsafeBytes(of: &value) { data.append(contentsOf: $0) }
        }
        func int64(_ value: Int64) {
            var value = value.littleEndian
            withUnsafeBytes(of: &value) { data.append(contentsOf: $0) }
        }
        if let topic = scope.topic {
            int32(0xf731a9f4) // messages.readDiscussion: only the open thread.
            switch namespace {
            case 0:
                guard let hash else { return nil }
                int32(0xdde8a54c); int64(id); int64(hash)
            case 1: int32(0x35a95cb9); int64(id)
            case 2:
                guard let hash else { return nil }
                int32(0x27bcbbfc); int64(id); int64(hash)
            default: return nil
            }
            int32(UInt32(bitPattern: topic))
        } else if namespace == 2 {
            guard let hash else { return nil }
            int32(0xcc104937) // channels.readHistory
            int32(0xf35aec28); int64(id); int64(hash)
        } else {
            int32(0x0e306d3a) // messages.readHistory: users, bots, basic groups.
            if namespace == 1 { int32(0x35a95cb9); int64(id) }
            else if scope.peerKey == ownPeerKey { int32(0x7da07ec9) }
            else {
                guard let hash else { return nil }
                int32(0xdde8a54c); int64(id); int64(hash)
            }
        }
        int32(UInt32(bitPattern: maxReadId))
        return data
    }
}
