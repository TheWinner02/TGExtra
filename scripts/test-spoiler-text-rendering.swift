import Foundation

// Exercise Swift-to-Objective-C dispatch too: Telegram's formatter is Swift.
@main
private struct SwiftSpoilerRenderingTests {
    static func main() {
        let defaults = UserDefaults.standard
        let previous = defaults.object(forKey: "TGExtraRevealSpoilers")
        defer {
            if let previous { defaults.set(previous, forKey: "TGExtraRevealSpoilers") }
            else { defaults.removeObject(forKey: "TGExtraRevealSpoilers") }
        }
        defaults.set(true, forKey: "TGExtraRevealSpoilers")
        let rendered = NSAttributedString.Key("TelegramSpoiler")
        let composer = NSAttributedString.Key("Attribute__Spoiler")
        let text = NSMutableAttributedString(string: "Test")
        text.addAttribute(rendered, value: true as NSNumber, range: NSRange(location: 0, length: 4))
        text.addAttribute(composer, value: true as NSNumber, range: NSRange(location: 0, length: 4))
        precondition(text.attribute(rendered, at: 0, effectiveRange: nil) == nil)
        precondition((text.attribute(composer, at: 0, effectiveRange: nil) as? NSNumber)?.boolValue == true)
        defaults.set(false, forKey: "TGExtraRevealSpoilers")
        text.addAttribute(rendered, value: true as NSNumber, range: NSRange(location: 0, length: 4))
        precondition((text.attribute(rendered, at: 0, effectiveRange: nil) as? NSNumber)?.boolValue == true)
        print("Swift formatter dispatch and outgoing spoiler preservation passed")
    }
}
