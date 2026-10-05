import Foundation

@objc(TGExtraStoryFilter)
class TGExtraStoryFilter: NSObject {
    @objc(isStoryDecorationClass:)
    static func isStoryDecorationClass(_ name: String) -> Bool {
        // Never hide the full-screen viewer, its content or its interaction UI.
        guard !name.contains("StoryContainer"), !name.contains("StoryItemSet") else { return false }
        return ["StoryPeerListComponent", "StoryPeerListNode", "StoryPeerListItemComponent",
            "StorySetIndicatorComponent", "StorySetIndicatorNode",
            "AvatarStoryIndicatorComponent", "AvatarStoryIndicatorNode"].contains { name.contains($0) }
    }
}
