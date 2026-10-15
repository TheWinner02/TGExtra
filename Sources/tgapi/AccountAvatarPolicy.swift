import Foundation

// Primitive reflection only: never call PeerId/resource getters through stubs.
enum AccountAvatarPolicy {
    static func stored(_ name: String, in value: Any) -> Any? {
        var mirror: Mirror? = Mirror(reflecting: value)
        while let current = mirror {
            for child in current.children where child.label == name {
                let optional = Mirror(reflecting: child.value)
                return optional.displayStyle == .optional ? optional.children.first?.value : child.value
            }
            mirror = current.superclassMirror
        }
        return nil
    }

    static func peerKey(_ peer: Any) -> String? {
        guard let nsValue = stored("namespace", in: peer), let idValue = stored("id", in: peer) else { return nil }
        let ns = (nsValue as? UInt32) ?? (stored("rawValue", in: nsValue) as? UInt32)
        let id = (idValue as? Int64) ?? (stored("rawValue", in: idValue) as? Int64)
        guard let ns, ns <= 7, let id, id > 0, UInt64(id) < (UInt64(1) << 56) else { return nil }
        let bits = UInt64(id)
        return String(Int64(bitPattern: (bits & 0xffffffff) | (UInt64(ns) << 32) | ((bits >> 32) << 35)))
    }

    static func validResourceId(_ id: String) -> Bool {
        id.hasPrefix("telegram-peer-photo-size-") && id.count < 200 && id.utf8.allSatisfy {
            (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || $0 == 45
        }
    }

    static func resourceId(in avatar: Any, accountPeer: String) -> String? {
        let content = stored("contentNode", in: avatar) ?? avatar
        if let params = stored("params", in: content) {
            guard let peer = stored("peerId", in: params), peerKey(peer) == accountPeer,
                  let resource = stored("resourceId", in: params) as? String, validResourceId(resource) else { return nil }
            return resource
        }
        // Older AvatarNode implementations keep the owner and representation in
        // peerAvatar state. Initials/custom placeholders must never be copied.
        guard let state = stored("state", in: content),
              let item = Mirror(reflecting: state).children.first, item.label == "peerAvatar" else { return nil }
        let fields = Array(Mirror(reflecting: item.value).children)
        guard fields.count >= 4, peerKey(fields[0].value) == accountPeer else { return nil }
        let optional = Mirror(reflecting: fields[3].value)
        let representation: Any? = optional.displayStyle == .optional ? optional.children.first?.value : fields[3].value
        guard let representation,
              let resource = stored("resource", in: representation),
              String(reflecting: type(of: resource)).contains("CloudPeerPhotoSizeMediaResource"),
              let dc = stored("datacenterId", in: resource) as? Int, dc > 0,
              let spec = stored("sizeSpec", in: resource) else { return nil }
        let size: Int
        switch String(describing: spec).lowercased() {
        case "small", "0": size = 0
        case "fullsize", "1": size = 1
        default: return nil
        }
        let photo = stored("photoId", in: resource) as? Int64
        let volume = stored("volumeId", in: resource) as? Int64 ?? 0
        let local = stored("localId", in: resource) as? Int32 ?? 0
        guard photo != nil || (volume != 0 && local != 0) else { return nil }
        let prefix = "telegram-peer-photo-size-\(dc)-"
        let id = photo.map { prefix + "\($0)-\(size)-\(volume)-\(local)" } ?? prefix + "\(size)-\(volume)-\(local)"
        return validResourceId(id) ? id : nil
    }
}
