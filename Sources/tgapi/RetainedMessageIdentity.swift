import Foundation

// The archive captures this scope before showing the destructive confirmation.
// Both the original account/channel event and the resolved native ID must match.
struct RetainedChatCleanupScope {
    let peer: Int64
    let ids: Set<Int32>

    init?(chatKey: String, messageIds: [Int32]) {
        guard let peer = Int64(chatKey), peer > 0 else { return nil }
        let bits = UInt64(bitPattern: peer)
        let namespace = (bits >> 32) & 7
        let raw = (bits & 0xffffffff) | ((bits >> 35) << 32)
        let ids = Set(messageIds.filter { $0 > 0 })
        guard namespace < 3, raw > 0, raw < (UInt64(1) << 56), !ids.isEmpty else { return nil }
        self.peer = peer
        self.ids = ids
    }

    func contains(_ id: RetainedMessageIdentity) -> Bool {
        id.peer == peer && id.namespace == 0 && ids.contains(id.id)
    }

    func selects(_ record: [String: Any], account: String) -> Bool {
        guard record["account"] as? String == account,
              let id = (record["id"] as? NSNumber)?.int32Value, ids.contains(id) else { return false }
        var event = record
        event.removeValue(forKey: "peer")
        event.removeValue(forKey: "namespace")
        return RetainedMessageIdentity(peer: peer, namespace: 0, id: id).matches(record: event)
    }
}

// Primitive identifiers only. Native Postbox structs must not be fabricated
// using the scheduling stub's layout or scalar calling convention.
struct RetainedMessageIdentity: Equatable {
    let peer: Int64
    let namespace: Int32
    let id: Int32
    var key: String { "\(peer):\(namespace):\(id)" }

    static func channel(_ channel: Int64, message: Int32) -> Self? {
        // Native PeerId.Id admits at most 56 positive bits. Validate before
        // calling its decoder so malformed records cannot trigger an assertion.
        guard channel > 0, channel < (Int64(1) << 56), message > 0 else { return nil }
        let bits = UInt64(channel)
        let packed = (bits & 0xffffffff) | (UInt64(2) << 32) | ((bits >> 32) << 35)
        return Self(peer: Int64(bitPattern: packed), namespace: 0, id: message)
    }

    func matches(record: [String: Any]) -> Bool {
        guard id == (record["id"] as? NSNumber)?.int32Value, namespace == 0 else { return false }
        if let recordedPeer = (record["peer"] as? NSNumber)?.int64Value {
            return peer == recordedPeer && namespace == (record["namespace"] as? NSNumber)?.int32Value
        }
        let packed = UInt64(bitPattern: peer)
        let peerNamespace = (packed >> 32) & 7
        let channel = (record["channel"] as? NSNumber)?.int64Value ?? 0
        let rawPeer = (packed & 0xffffffff) | ((packed >> 35) << 32)
        return channel == 0 ? peerNamespace < 2 : channel > 0 && peerNamespace == 2 && rawPeer == UInt64(channel)
    }

    static func encoded(_ ids: [Self]) -> Data {
        precondition(ids.count <= Int(Int32.max))
        var data = Data()
        func append<T: FixedWidthInteger>(_ value: T) {
            var littleEndian = value.littleEndian
            withUnsafeBytes(of: &littleEndian) { data.append(contentsOf: $0) }
        }
        append(Int32(ids.count))
        for id in ids { append(id.peer); append(id.namespace); append(id.id) }
        return data
    }
}
