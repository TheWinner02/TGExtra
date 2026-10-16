import Foundation

@main
struct AccountAvatarTests {
    struct Namespace { let rawValue: UInt32 }
    struct Id { let rawValue: Int64 }
    struct PeerId { let namespace: Namespace; let id: Id }
    struct Params { let peerId: PeerId?; let resourceId: String? }
    enum Size { case small, fullSize }
    struct CloudPeerPhotoSizeMediaResource {
        let datacenterId: Int
        let photoId: Int64?
        let sizeSpec: Size
        let volumeId: Int64?
        let localId: Int32?
    }
    struct Representation { let resource: CloudPeerPhotoSizeMediaResource }
    struct User { let id: PeerId; let photo: [Representation] }
    enum State {
        case empty
        case peerAvatar(PeerId, Int?, [String], Representation?, Int, Int?)
    }
    struct Content { let params: Params?; let state: State }
    struct Avatar { let contentNode: Content }

    static func main() {
        let owner = PeerId(namespace: Namespace(rawValue: 0), id: Id(rawValue: 123))
        let other = PeerId(namespace: Namespace(rawValue: 0), id: Id(rawValue: 456))
        let channel = PeerId(namespace: Namespace(rawValue: 2), id: Id(rawValue: 123))
        let key = AccountAvatarPolicy.peerKey(owner)!
        let resource = "telegram-peer-photo-size-2-999-0-0-0"
        let params = Params(peerId: owner, resourceId: resource)
        precondition(AccountAvatarPolicy.rejectionReason(in: Content(params: Params(peerId: other, resourceId: resource), state: .empty), accountPeer: key) == "altri account/chat")
        precondition(AccountAvatarPolicy.rejectionReason(in: Content(params: Params(peerId: owner, resourceId: nil), state: .empty), accountPeer: key) == "foto propria assente nei parametri")
        precondition(AccountAvatarPolicy.rejectionReason(in: Content(params: Params(peerId: nil, resourceId: resource), state: .empty), accountPeer: key) == "proprietario illeggibile")
        precondition(AccountAvatarPolicy.rejectionReason(in: Content(params: nil, state: .empty), accountPeer: key) == "stato avatar assente/non supportato")
        precondition(AccountAvatarPolicy.resourceId(in: Avatar(contentNode: Content(params: params, state: .empty)), accountPeer: key) == resource)
        precondition(AccountAvatarPolicy.resourceId(in: Content(params: params, state: .empty), accountPeer: key) == resource)
        for peer in [other, channel] {
            precondition(AccountAvatarPolicy.resourceId(in: Content(params: Params(peerId: peer, resourceId: resource), state: .empty), accountPeer: key) == nil)
        }
        precondition(AccountAvatarPolicy.resourceId(in: Content(params: Params(peerId: nil, resourceId: resource), state: .empty), accountPeer: key) == nil)
        precondition(AccountAvatarPolicy.resourceId(in: Content(params: Params(peerId: owner, resourceId: nil), state: .empty), accountPeer: key) == nil)
        for invalid in ["../photo", "telegram-peer-photo-size-../../secret", "telegram-peer-photo-size-1\\secret", "telegram-peer-photo-size-1%2fsecret", "other-photo-1"] {
            precondition(!AccountAvatarPolicy.validResourceId(invalid))
        }
        let full = Representation(resource: CloudPeerPhotoSizeMediaResource(datacenterId: 2, photoId: 999, sizeSpec: .fullSize, volumeId: nil, localId: nil))
        precondition(AccountAvatarPolicy.encodedPeerIds("123") == Data([1, 0, 0, 0, 123, 0, 0, 0, 0, 0, 0, 0]))
        precondition(AccountAvatarPolicy.encodedPeerIds("0") == nil)
        precondition(AccountAvatarPolicy.encodedPeerIds("invalid") == nil)
        precondition(AccountAvatarPolicy.profileResourceIds(in: User(id: owner, photo: [full, full]), accountPeer: key) == ["telegram-peer-photo-size-2-999-1-0-0"])
        precondition(AccountAvatarPolicy.profileResourceIds(in: User(id: other, photo: [full]), accountPeer: key) == nil)
        precondition(AccountAvatarPolicy.profileResourceIds(in: User(id: owner, photo: []), accountPeer: key) == [])
        let state = State.peerAvatar(owner, nil, ["A"], full, 0, nil)
        precondition(AccountAvatarPolicy.resourceId(in: Content(params: nil, state: state), accountPeer: key) == "telegram-peer-photo-size-2-999-1-0-0")
        precondition(AccountAvatarPolicy.resourceId(in: Content(params: nil, state: .peerAvatar(other, nil, [], full, 0, nil)), accountPeer: key) == nil)
        precondition(AccountAvatarPolicy.resourceId(in: Content(params: nil, state: .peerAvatar(owner, nil, ["A"], nil, 0, nil)), accountPeer: key) == nil, "Initials are not a profile photo")
        precondition(AccountAvatarPolicy.resourceId(in: Content(params: Params(peerId: owner, resourceId: nil), state: state), accountPeer: key) == nil, "Removed photo must not reuse old state")
        let legacy = Representation(resource: CloudPeerPhotoSizeMediaResource(datacenterId: 2, photoId: nil, sizeSpec: .small, volumeId: 77, localId: 8))
        precondition(AccountAvatarPolicy.resourceId(in: Content(params: nil, state: .peerAvatar(owner, nil, [], legacy, 0, nil)), accountPeer: key) == "telegram-peer-photo-size-2-0-77-8")
        precondition(AccountAvatarPolicy.peerKey(PeerId(namespace: Namespace(rawValue: 0), id: Id(rawValue: 0))) == nil)
        print("Account avatar identity and fallback: all checks passed")
    }
}
