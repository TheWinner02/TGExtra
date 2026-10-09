import Foundation

// Primitive identifiers only. Native Postbox structs must not be fabricated
// using the scheduling stub's layout or scalar calling convention.
struct RetainedMessageIdentity: Equatable {
    let peer: Int64
    let namespace: Int32
    let id: Int32
    var key: String { "\(peer):\(namespace):\(id)" }

    static func channel(_ channel: Int64, message: Int32) -> Self? {
        guard channel > 0, channel < (Int64(1) << 61), message > 0 else { return nil }
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
