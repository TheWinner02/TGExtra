import Foundation

// Primitive reflection only: never call PeerId/resource getters through stubs.
enum AccountAvatarPolicy {
    // Pass opaque arrays between native APIs, never construct/index scalar
    // PeerId values using the layout-only compatibility stub.
    static func encodedPeerIds(_ key: String) -> Data? {
        guard let packed = Int64(key), packed > 0 else { return nil }
        let bits = UInt64(packed)
        let raw = (bits & 0xffffffff) | ((bits >> 35) << 32)
        guard raw > 0, raw < (UInt64(1) << 56) else { return nil }
        var count = Int32(1).littleEndian
        var id = packed.littleEndian
        var data = Data()
        withUnsafeBytes(of: &count) { data.append(contentsOf: $0) }
        withUnsafeBytes(of: &id) { data.append(contentsOf: $0) }
        return data
    }

    static func profileResourceIds(in profile: Any, accountPeer: String) -> [String]? {
        guard let id = stored("id", in: profile), peerKey(id) == accountPeer,
              let photo = stored("photo", in: profile),
              Mirror(reflecting: photo).displayStyle == .collection else { return nil }
        var result: [String] = []
        for item in Mirror(reflecting: photo).children.prefix(16) {
            if let id = resourceId(forRepresentation: item.value), !result.contains(id) { result.append(id) }
        }
        return result
    }
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

    static func rejectionReason(in avatar: Any, accountPeer: String) -> String {
        let content = stored("contentNode", in: avatar) ?? avatar
        if let params = stored("params", in: content) {
            guard let peer = stored("peerId", in: params), let key = peerKey(peer) else { return "proprietario illeggibile" }
            guard key == accountPeer else { return "altri account/chat" }
            guard let id = stored("resourceId", in: params) as? String else { return "foto propria assente nei parametri" }
            return validResourceId(id) ? "risorsa propria riconosciuta" : "formato risorsa non supportato"
        }
        guard let state = stored("state", in: content),
              let item = Mirror(reflecting: state).children.first,
              item.label == "peerAvatar" else { return "stato avatar assente/non supportato" }
        let fields = Array(Mirror(reflecting: item.value).children)
        guard fields.count >= 4, let key = peerKey(fields[0].value) else { return "formato stato non supportato" }
        guard key == accountPeer else { return "altri account/chat" }
        let representation = Mirror(reflecting: fields[3].value)
        if representation.displayStyle == .optional && representation.children.isEmpty { return "foto propria assente nello stato" }
        return "risorsa stato non supportata"
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
        guard let representation else { return nil }
        return resourceId(forRepresentation: representation)
    }

    static func resourceId(forRepresentation representation: Any) -> String? {
        guard let resource = stored("resource", in: representation),
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
