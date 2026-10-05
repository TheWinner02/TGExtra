import Foundation

// Shared by the native scheduler and the legacy, currently unused RPC fallback.
enum AutomaticScheduleTiming {
    enum Kind {
        case text, photo, video, audio, file, lightweight
    }

    static let minimumDelay: Int64 = 15

    static func delay(kind: Kind, textLength: Int = 0, size: Int64 = 0) -> Int64 {
        let megabytes = Double(max(0, size)) / 1_048_576.0
        switch kind {
        case .text:
            return min(60, minimumDelay + Int64(max(0, textLength) / 200))
        case .photo:
            return min(300, 30 + Int64(ceil(min(270, megabytes))))
        case .video:
            return min(1_800, 45 + Int64(ceil(min(1_755, megabytes * 3))))
        case .audio, .file:
            return min(1_800, 30 + Int64(ceil(min(1_770, megabytes * 2))))
        case .lightweight:
            return minimumDelay
        }
    }
}
