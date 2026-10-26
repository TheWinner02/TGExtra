import Foundation
import UIKit
import ObjectiveC
import tgapiC

private final class SpoilerNodeState: NSObject {
    var scheduled = false
}

@objc(TGExtraSpoilerController)
final class TGExtraSpoilerController: NSObject {
    private static let preference = "TGExtraRevealSpoilers"
    private static var stateKey: UInt8 = 0
    private static let nodes = NSHashTable<NSObject>.weakObjects()

    @objc(updateNode:)
    static func update(_ node: NSObject) {
        guard Thread.isMainThread else { return }
        // Called only for message text/media nodes, never for every UIView.
        nodes.add(node)
        guard UserDefaults.standard.bool(forKey: preference) else { return }
        let state: SpoilerNodeState
        if let current = objc_getAssociatedObject(node, &stateKey) as? SpoilerNodeState {
            state = current
        } else {
            state = SpoilerNodeState()
            objc_setAssociatedObject(node, &stateKey, state, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
        guard !state.scheduled else { return }
        state.scheduled = true
        // Native async layout must finish installing callbacks/overlays first.
        DispatchQueue.main.async { [weak node] in
            state.scheduled = false
            guard let node, UserDefaults.standard.bool(forKey: preference) else { return }
            reveal(node)
        }
    }

    @objc(refresh)
    static func refresh() {
        guard Thread.isMainThread else { return }
        for node in nodes.allObjects { update(node) }
    }

    private static func reveal(_ node: NSObject) {
        let name = SpoilerPolicy.name(node)
        if name == "ChatMessageTextBubbleContentNode" {
            guard let item = SpoilerPolicy.stored("item", in: node),
                  let message = SpoilerPolicy.stored("message", in: item),
                  SpoilerPolicy.hasTextSpoiler(message) else { return }
            if let display = SpoilerPolicy.stored("displayContentsUnderSpoilers", in: node),
               SpoilerPolicy.stored("value", in: display) as? Bool == true { return }
            if let wrapper = SpoilerPolicy.stored("textNode", in: node),
               let text = SpoilerPolicy.stored("textNode", in: wrapper),
               let request = SpoilerPolicy.stored("requestDisplayContentsUnderSpoilers", in: text) as? (CGPoint?) -> Void {
                request(nil)
            } else if let dust = SpoilerPolicy.stored("dustNode", in: node) as? NSObject,
                      SpoilerPolicy.stored("isRevealed", in: dust) as? Bool == false {
                _ = TGExtraSpoilerGestureBridge.revealDust(dust)
            }
        } else if name == "ChatMessageInteractiveMediaNode" {
            guard let message = SpoilerPolicy.stored("message", in: node),
                  SpoilerPolicy.canRevealMedia(message),
                  let overlay = SpoilerPolicy.stored("extendedMediaOverlayNode", in: node),
                  // Eye/lock overlays belong to sensitive/paid content.
                  let icon = SpoilerPolicy.stored("iconNode", in: overlay) as? NSObject,
                  TGExtraSpoilerGestureBridge.hasNoImage(icon),
                  let dust = SpoilerPolicy.stored("dustNode", in: overlay) as? NSObject,
                  SpoilerPolicy.stored("revealOnTap", in: dust) as? Bool == true,
                  SpoilerPolicy.stored("isRevealed", in: dust) as? Bool == false else { return }
            _ = TGExtraSpoilerGestureBridge.revealDust(dust)
        }
    }
}
