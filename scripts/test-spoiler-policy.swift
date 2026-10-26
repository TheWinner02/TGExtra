import Foundation

private final class MediaSpoilerMessageAttribute {}
private final class AutoclearTimeoutMessageAttribute {}
private final class AutoremoveTimeoutMessageAttribute {}
private final class RestrictedContentMessageAttribute {}
private final class PaidContentMessageAttribute {}
private final class TelegramMediaImage {}
private final class TelegramMediaFile {}
private final class TelegramMediaInvoice {}
private final class TelegramMediaPaidContent {}
private enum EntityType { case Spoiler, Bold, CustomEmoji(Int64) }
private struct Entity { let type: EntityType }
private final class TextEntitiesMessageAttribute {
    let entities: [Entity]
    init(_ types: [EntityType]) { entities = types.map { Entity(type: $0) } }
}
private final class Message {
    let attributes: [Any]
    let media: [Any]
    init(_ attributes: [Any], media: [Any] = []) { self.attributes = attributes; self.media = media }
}
private final class EngineMessage {
    private let impl: Message
    init(_ message: Message) { impl = message }
}
private class BaseNode { private let item = "inherited" }
private final class ChildNode: BaseNode { let missing: Int? = nil }
private struct TextCallbacks { let requestDisplayContentsUnderSpoilers: ((CGPoint?) -> Void)? }

@main
private struct Tests {
    static func main() {
        let spoiler = MediaSpoilerMessageAttribute()
        assert(SpoilerPolicy.hasTextSpoiler(Message([TextEntitiesMessageAttribute([.Bold, .Spoiler])])) )
        assert(SpoilerPolicy.hasTextSpoiler(EngineMessage(Message([TextEntitiesMessageAttribute([.Spoiler])]))))
        assert(!SpoilerPolicy.hasTextSpoiler(Message([TextEntitiesMessageAttribute([.Bold, .CustomEmoji(5)])])))
        assert(!SpoilerPolicy.hasTextSpoiler(Message([spoiler])))
        assert(!SpoilerPolicy.hasTextSpoiler("unknown"))
        assert(SpoilerPolicy.canRevealMedia(Message([spoiler], media: [TelegramMediaImage()])))
        assert(SpoilerPolicy.canRevealMedia(EngineMessage(Message([spoiler], media: [TelegramMediaFile()]))))
        assert(!SpoilerPolicy.canRevealMedia(Message([], media: [TelegramMediaImage()])))
        assert(!SpoilerPolicy.canRevealMedia(Message([spoiler])))
        for protected in [AutoclearTimeoutMessageAttribute() as Any, AutoremoveTimeoutMessageAttribute(),
                          RestrictedContentMessageAttribute(), PaidContentMessageAttribute()] {
            assert(!SpoilerPolicy.canRevealMedia(Message([spoiler, protected], media: [TelegramMediaImage()])))
        }
        for protected in [TelegramMediaInvoice() as Any, TelegramMediaPaidContent(), "unknown"] {
            assert(!SpoilerPolicy.canRevealMedia(Message([spoiler], media: [protected])))
            assert(!SpoilerPolicy.canRevealMedia(Message([spoiler], media: [TelegramMediaImage(), protected])))
        }
        assert(!SpoilerPolicy.canRevealMedia("unknown"))
        assert(SpoilerPolicy.stored("item", in: ChildNode()) as? String == "inherited")
        assert(SpoilerPolicy.stored("missing", in: ChildNode()) == nil)
        var requests = 0
        let callbacks = TextCallbacks(requestDisplayContentsUnderSpoilers: { point in
            assert(point == nil)
            requests += 1
        })
        let reveal = SpoilerPolicy.stored("requestDisplayContentsUnderSpoilers", in: callbacks) as? (CGPoint?) -> Void
        assert(reveal != nil)
        reveal?(nil)
        assert(requests == 1)
        assert(SpoilerPolicy.stored("requestDisplayContentsUnderSpoilers", in: TextCallbacks(requestDisplayContentsUnderSpoilers: nil)) == nil)
        print("Spoiler recognition and protected-media exclusions passed")
    }
}
