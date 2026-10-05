import Foundation

@main
struct StoryVisibilityTests {
    static func main() {
        let cases: [(String, Bool)] = [
            ("StoryPeerListComponent.StoryPeerListComponent.View", true),
            ("TelegramUI.StoryPeerListNode", true),
            ("StoryPeerListComponent.StoryPeerListItemComponent.View", true),
            ("AvatarStoryIndicatorComponent.AvatarStoryIndicatorComponent.View", true),
            ("StorySetIndicatorComponent.StorySetIndicatorComponent.View", true),
            ("TelegramUI.AvatarStoryIndicatorNode", true),
            ("StoryContainerScreen.StoryContainerScreen.View", false),
            ("StoryContainerScreen.StoryAvatarStoryIndicatorComponent.View", false),
            ("StoryItemSetContainerComponent.View", false),
            ("TelegramUI.ChatMessageBubbleItemNode", false),
            ("AvatarNode.AvatarNode", false), ("UIKit.UIView", false)
        ]
        for (name, expected) in cases {
            precondition(TGExtraStoryFilter.isStoryDecorationClass(name) == expected, name)
        }
        print("Story visibility: \(cases.count) tests passed")
    }
}
