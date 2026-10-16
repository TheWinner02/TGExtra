import Foundation
import SwiftSignalKit

// Deliberately unlike the layout-only stub. The client must never construct,
// index, or pass a scalar PeerId; only native functions access array elements.
public struct PeerId {
    let padding: (Int64, Int64, Int64) = (91, 92, 93)
    let namespace: UInt32 = 0
    let id: Int64
    public static func decodeArrayFromBuffer(_ buffer: ReadBuffer) -> [PeerId] {
        precondition(buffer.data.count == 12)
        precondition(buffer.data.withUnsafeBytes { $0.loadUnaligned(as: Int32.self).littleEndian } == 1)
        let id = buffer.data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 4, as: Int64.self).littleEndian }
        return [PeerId(id: id)]
    }
}
public final class ReadBuffer {
    let data: Data
    public init(data: Data) { self.data = data }
}
private enum Size { case small }
private struct CloudPeerPhotoSizeMediaResource {
    let datacenterId = 2
    let photoId: Int64? = 999
    let sizeSpec = Size.small
    let volumeId: Int64? = nil
    let localId: Int32? = nil
}
private struct Representation { let resource = CloudPeerPhotoSizeMediaResource() }
private struct User { let id: PeerId; let photo = [Representation()] }
public final class MultiplePeersView {
    private let peers: [String: User]
    fileprivate init(id: PeerId) { peers = ["own": User(id: id)] }
}
public final class Postbox {
    public func multiplePeersView(_ ids: [PeerId]) -> Signal<MultiplePeersView, NoError> {
        precondition(ids.count == 1 && ids[0].padding.2 == 93)
        return Signal(MultiplePeersView(id: ids[0]))
    }
}
@_silgen_name("TGExtraAvatarFixturePostbox")
public func avatarFixturePostbox() -> Postbox { Postbox() }
