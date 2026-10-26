import Foundation
import UIKit
import ObjectiveC
import tgapiC

private final class SpoilerNodeState: NSObject {
    var scheduled = false
    var applying = false
    var retries = 0
    weak var renderedText: NSObject?
    weak var renderedLayout: AnyObject?
}

@objc(TGExtraSpoilerController)
final class TGExtraSpoilerController: NSObject {
    private static let preference = "TGExtraRevealSpoilers"
    private static var stateKey: UInt8 = 0
    private static let nodes = NSHashTable<NSObject>.weakObjects()

    @objc(didEnterVisibleNode:)
    static func didEnterVisible(_ node: NSObject) {
        guard Thread.isMainThread else { return }
        // Texture may discard backing contents outside the visible range while
        // retaining the same text and cached layout objects. Redraw once when
        // the cell re-enters, not only when those object identities change.
        if let state = objc_getAssociatedObject(node, &stateKey) as? SpoilerNodeState {
            state.renderedText = nil
            state.renderedLayout = nil
        }
        update(node)
    }

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
        guard !state.scheduled, !state.applying else { return }
        state.retries = 0
        schedule(node, state: state, delay: 0)
    }

    private static func schedule(_ node: NSObject, state: SpoilerNodeState, delay: TimeInterval) {
        state.scheduled = true
        // Native async layout must finish installing callbacks/overlays first.
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak node] in
            state.scheduled = false
            guard let node, UserDefaults.standard.bool(forKey: preference) else { return }
            state.applying = true
            let waitingForTextLayout = reveal(node, state: state)
            state.applying = false
            if waitingForTextLayout && state.retries < 6 {
                state.retries += 1
                schedule(node, state: state, delay: 0.05)
            }
        }
    }

    @objc(refresh)
    static func refresh() {
        guard Thread.isMainThread else { return }
        for node in nodes.allObjects { update(node) }
    }

    private static func reveal(_ node: NSObject, state: SpoilerNodeState) -> Bool {
        let name = SpoilerPolicy.name(node)
        if name == "ChatMessageTextBubbleContentNode" {
            guard let item = SpoilerPolicy.stored("item", in: node),
                  let message = SpoilerPolicy.stored("message", in: item),
                  SpoilerPolicy.hasTextSpoiler(message) else { return false }
            if let wrapper = SpoilerPolicy.stored("textNode", in: node),
               let text = SpoilerPolicy.stored("textNode", in: wrapper) as? NSObject,
               let request = SpoilerPolicy.stored("requestDisplayContentsUnderSpoilers", in: text) as? (CGPoint?) -> Void {
                let display = SpoilerPolicy.stored("displayContentsUnderSpoilers", in: node)
                if display.flatMap({ SpoilerPolicy.stored("value", in: $0) }) as? Bool != true {
                    request(nil)
                    return true
                }
                // The owner flag changes before the asynchronous text layout
                // is applied. It is not proof that the glyphs have been drawn.
                guard let layout = SpoilerPolicy.stored("cachedLayout", in: text),
                      SpoilerPolicy.stored("displayContentsUnderSpoilers", in: layout) as? Bool == true else { return true }
                finishText(text, layout: layout, state: state, restoreAlpha: false)
            } else if let dust = SpoilerPolicy.stored("dustNode", in: node) as? NSObject,
                      let text = SpoilerPolicy.stored("textNode", in: dust) as? NSObject,
                      let mask = SpoilerPolicy.stored("textMaskNode", in: dust) as? NSObject,
                      SpoilerPolicy.stored("currentParams", in: dust) != nil,
                      TGExtraSpoilerGestureBridge.revealTextDust(dust, content: text, mask: mask) {
                // Keep only this dust node's radial mask off its text. Native
                // delayed animation callbacks cannot conceal the text again.
                finishText(text, layout: SpoilerPolicy.stored("cachedLayout", in: text), state: state, restoreAlpha: true)
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
                  SpoilerPolicy.stored("isRevealed", in: dust) as? Bool == false else { return false }
            _ = TGExtraSpoilerGestureBridge.revealDust(dust)
        }
        return false
    }

    private static func finishText(_ text: NSObject, layout: Any?, state: SpoilerNodeState, restoreAlpha: Bool) {
        let reference: AnyObject? = layout.flatMap { Mirror(reflecting: $0).displayStyle == .class ? $0 as AnyObject : nil }
        let changed = state.renderedText !== text || state.renderedLayout !== reference
        guard changed || restoreAlpha else { return }
        state.renderedText = text
        state.renderedLayout = reference
        TGExtraSpoilerGestureBridge.finishTextDisplay(text, restoreAlpha: restoreAlpha, ensureDisplay: changed)
    }
}
