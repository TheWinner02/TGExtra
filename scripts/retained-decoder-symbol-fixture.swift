import Foundation

// Compile as module Postbox in CI to verify the exact Swift symbol spelling.
// This fixture is never linked into the tweak.
public struct MessageId {
    public static func decodeArrayFromData(_ data: Data) -> [MessageId] { [] }
}
