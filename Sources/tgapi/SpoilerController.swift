import Foundation
import UIKit
import ObjectiveC
import tgapiC

// Text is handled before layout by SpoilerTextRendering.m. This coordinator is
// only for media overlays; it must never tap, mask or redraw a text bubble.
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
        guard Thread.isMainThread,
              SpoilerPolicy.name(node) == "ChatMessageInteractiveMediaNode" else { return }
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
        DispatchQueue.main.async { [weak node] in
            state.scheduled = false
            guard let node, UserDefaults.standard.bool(forKey: preference),
                  let message = SpoilerPolicy.stored("message", in: node),
                  SpoilerPolicy.canRevealMedia(message),
                  let overlay = SpoilerPolicy.stored("extendedMediaOverlayNode", in: node),
                  let icon = SpoilerPolicy.stored("iconNode", in: overlay) as? NSObject,
                  TGExtraSpoilerGestureBridge.hasNoImage(icon),
                  let dust = SpoilerPolicy.stored("dustNode", in: overlay) as? NSObject,
                  SpoilerPolicy.stored("revealOnTap", in: dust) as? Bool == true,
                  SpoilerPolicy.stored("isRevealed", in: dust) as? Bool == false else { return }
            _ = TGExtraSpoilerGestureBridge.revealDust(dust)
        }
    }

    @objc(refresh)
    static func refresh() {
        guard Thread.isMainThread else { return }
        for node in nodes.allObjects { update(node) }
    }
}
