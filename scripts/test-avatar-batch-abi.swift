import Foundation
import Postbox
import SwiftSignalKit

@_silgen_name("TGExtraAvatarFixturePostbox")
func avatarFixturePostbox() -> Postbox

@main
struct AvatarBatchABITests {
    static func main() {
        let data = AccountAvatarPolicy.encodedPeerIds("123")!
        let ids = PeerId.decodeArrayFromBuffer(ReadBuffer(data: data))
        // Opaque native array: no element reads on this side of the stub.
        let signal = avatarFixturePostbox().multiplePeersView(ids)
        var received = false
        let disposable = signal.start(next: { view in
            let peers = AccountAvatarPolicy.stored("peers", in: view)!
            let profile = RetainedMessageArchive.peerValues(in: peers).first!
            precondition(AccountAvatarPolicy.profileResourceIds(in: profile, accountPeer: "123") == ["telegram-peer-photo-size-2-999-0-0-0"])
            precondition(AccountAvatarPolicy.profileResourceIds(in: profile, accountPeer: "456") == nil)
            received = true
        }, error: nil, completed: nil)
        precondition(received)
        disposable.dispose()
        print("Avatar native batch ABI: opaque ID array, profile read and signal dispatch passed")
    }
}
