import Foundation
import Darwin

enum NativePeerLookup {
    static let symbols = [
        "$s7Postbox6PeerIdV21decodeArrayFromBufferySayACGAA04ReadG0CFZ",
        "$s7Postbox10ReadBufferC4dataAC10Foundation4DataV_tcfC",
        "$s7Postbox17MultiplePeersViewCMa",
        "$s7PostboxAAC17multiplePeersViewy14SwiftSignalKit0F0CyAA08MultiplecD0CAD7NoErrorOGSayAA6PeerIdVGF"
    ]

    static func missing(in names: [String] = symbols) -> [Int] {
        // Darwin's default-search pseudo-handle is not nil. Use the same real
        // process handle as the working avatar lookup; balance our dlopen.
        guard let handle = dlopen(nil, RTLD_NOW) else { return Array(names.indices) }
        defer { dlclose(handle) }
        return names.indices.filter { dlsym(handle, names[$0]) == nil }
    }
}
