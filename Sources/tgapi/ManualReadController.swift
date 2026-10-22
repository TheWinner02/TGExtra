import Foundation
import UIKit
import ObjectiveC
import Postbox
import TelegramCore
import tgapiC

private final class ManualReadButtonState: NSObject {
    weak var controller: UIViewController?
    var item: UIBarButtonItem!
    var load: RetainedArchiveLoad?
    var operation = UUID()
    var busy = false
    var navigationPending = ManualReadNavigation.Pending<UIBarButtonItem>()
    var navigationScheduled = false
    var navigationApplying = false
    var navigationGeneration: UInt = 0

    init(controller: UIViewController) {
        self.controller = controller
        super.init()
        item = UIBarButtonItem(image: UIImage(systemName: "eye"), style: .plain, target: self, action: #selector(tapped))
        item.accessibilityLabel = TGExtraManualReadTransport.text("MANUAL_READ_ACTION")
    }
    func cancel() {
        operation = UUID()
        load?.cancel()
        load = nil
        busy = false
        item.isEnabled = true
        item.image = UIImage(systemName: "eye")
    }
    func cancelNavigation() {
        navigationGeneration &+= 1
        navigationPending.cancel()
        navigationScheduled = false
    }
    @objc private func tapped() {
        guard let controller, !busy else { return }
        TGExtraManualReadController.markRead(controller, state: self)
    }
}

@objc(TGExtraManualReadController)
final class TGExtraManualReadController: NSObject {
    private static var stateKey: UInt8 = 0
    private static var navigationStateKey: UInt8 = 0
    private static let owners = NSHashTable<UIViewController>.weakObjects()
    private static let preference = "disableMessageReadReceipt"

    @objc(updateForController:)
    static func update(_ controller: UIViewController) {
        precondition(Thread.isMainThread)
        let old = objc_getAssociatedObject(controller, &stateKey) as? ManualReadButtonState
        if !UserDefaults.standard.bool(forKey: preference) {
            if let old {
                old.cancel()
                old.cancelNavigation()
                // Detach first, otherwise the setter hook would restore the eye.
                objc_setAssociatedObject(controller.navigationItem, &navigationStateKey, nil, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
                let items = controller.navigationItem.rightBarButtonItems ?? controller.navigationItem.rightBarButtonItem.map { [$0] } ?? []
                if items.contains(where: { $0 === old.item }) {
                    controller.navigationItem.rightBarButtonItems = items.filter { $0 !== old.item }
                }
            }
            return
        }
        guard controller.viewIfLoaded != nil else { return }
        let state = old ?? ManualReadButtonState(controller: controller)
        if old == nil {
            objc_setAssociatedObject(controller, &stateKey, state, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
            owners.add(controller)
        }
        objc_setAssociatedObject(controller.navigationItem, &navigationStateKey, state, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        let items = controller.navigationItem.rightBarButtonItems ?? controller.navigationItem.rightBarButtonItem.map { [$0] } ?? []
        // Install once on appearance; subsequent native updates are merged in
        // the navigation-item setters, not repaired after every layout.
        if !items.contains(where: { $0 === state.item }) {
            controller.navigationItem.rightBarButtonItems = ManualReadNavigation.items(items, eye: state.item)
        }
    }

    @objc(queueRightItemsForNavigationItem:proposedItems:)
    static func queueRightItems(_ item: UINavigationItem, proposedItems: [UIBarButtonItem]) -> Bool {
        guard Thread.isMainThread,
              let state = objc_getAssociatedObject(item, &navigationStateKey) as? ManualReadButtonState,
              state.controller?.navigationItem === item,
              UserDefaults.standard.bool(forKey: preference), !state.navigationApplying else { return false }
        let merged = ManualReadNavigation.items(proposedItems, eye: state.item)
        let current = item.rightBarButtonItems ?? item.rightBarButtonItem.map { [$0] } ?? []
        if !state.navigationScheduled && ManualReadNavigation.identical(current, merged) { return true }
        state.navigationPending.stage(merged)
        if state.navigationScheduled { return true }
        state.navigationScheduled = true
        let generation = state.navigationGeneration
        // Native typing updates may clear the array and set the avatar again in
        // the same turn. Render only the final list, without fading the island.
        DispatchQueue.main.async { [weak item, weak state] in
            guard let item, let state, state.navigationGeneration == generation else { return }
            state.navigationScheduled = false
            guard let latest = state.navigationPending.take(),
                  state.controller?.navigationItem === item,
                  objc_getAssociatedObject(item, &navigationStateKey) as? ManualReadButtonState === state,
                  UserDefaults.standard.bool(forKey: preference) else { return }
            let current = item.rightBarButtonItems ?? item.rightBarButtonItem.map { [$0] } ?? []
            guard !ManualReadNavigation.identical(current, latest) else { return }
            state.navigationApplying = true
            defer { state.navigationApplying = false }
            UIView.performWithoutAnimation {
                item.setRightBarButtonItems(latest, animated: false)
            }
        }
        return true
    }

    @objc(hideForController:)
    static func hide(_ controller: UIViewController) {
        if let state = objc_getAssociatedObject(controller, &stateKey) as? ManualReadButtonState {
            state.cancel()
            state.cancelNavigation()
        }
    }

    @objc(refreshButtons)
    static func refreshButtons() {
        for controller in owners.allObjects { update(controller) }
    }

    private static func scope(_ controller: UIViewController) -> ManualReadScope? {
        guard let location = nativeStoredValue(named: "chatLocation", in: controller) else { return nil }
        return ManualReadScope(location: location)
    }

    fileprivate static func markRead(_ controller: UIViewController, state: ManualReadButtonState) {
        guard UserDefaults.standard.bool(forKey: preference) else { update(controller); return }
        func failure(_ key: String, diagnostic: String? = nil) {
            var message = TGExtraManualReadTransport.text(key)
            if let diagnostic {
                message += "\n\n" + TGExtraManualReadTransport.text("MANUAL_READ_DIAGNOSTIC") + ": " + diagnostic
            }
            NSLog("[TGExtra Manual Read] %@", message)
            UserDefaults.standard.set(message, forKey: "TGExtraManualReadStatus")
            if controller.presentedViewController == nil {
                let alert = UIAlertController(title: TGExtraManualReadTransport.text("MANUAL_READ_TITLE"), message: message, preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: TGExtraManualReadTransport.text("OK"), style: .default))
                controller.present(alert, animated: true)
            }
        }
        guard let target = scope(controller) else {
            // Type/case names only, never peer IDs, paths or message contents.
            let detail: String
            if let location = nativeStoredValue(named: "chatLocation", in: controller) {
                detail = "scope: \(String(reflecting: type(of: location))); case: \(Mirror(reflecting: location).children.first?.label ?? "none")"
            } else { detail = "scope: chatLocation missing" }
            failure("MANUAL_READ_UNSUPPORTED", diagnostic: detail); return
        }
        guard let context = nativeStoredValue(named: "context", in: controller) else {
            failure("MANUAL_READ_ACCOUNT_UNAVAILABLE", diagnostic: "context missing"); return
        }
        guard let account = nativeStoredValue(named: "account", in: context) as? Account else {
            failure("MANUAL_READ_ACCOUNT_UNAVAILABLE", diagnostic: "context.account missing/incompatible"); return
        }
        guard let postbox = nativeStoredValue(named: "postbox", in: account) as? Postbox else {
            failure("MANUAL_READ_ACCOUNT_UNAVAILABLE", diagnostic: "account.postbox missing/incompatible"); return
        }
        guard let network = nativeStoredValue(named: "network", in: account) else {
            failure("MANUAL_READ_ACCOUNT_UNAVAILABLE", diagnostic: "account.network missing"); return
        }
        guard let transport = nativeStoredValue(named: "mtProto", in: network) else {
            failure("MANUAL_READ_ACCOUNT_UNAVAILABLE", diagnostic: "network.mtProto missing"); return
        }
        guard let path = nativeStoredValue(named: "basePath", in: network) as? String else {
            failure("MANUAL_READ_ACCOUNT_UNAVAILABLE", diagnostic: "network.basePath missing"); return
        }
        let missing = NativePeerLookup.missing()
        guard missing.isEmpty else {
            failure("MANUAL_READ_API_UNAVAILABLE", diagnostic: "native API unavailable: \(missing.map(String.init).joined(separator: ", "))"); return
        }
        guard let data = AccountAvatarPolicy.encodedPeerIds(target.peerKey) else {
            failure("MANUAL_READ_UNSUPPORTED", diagnostic: "peer ID encoding rejected"); return
        }
        let ownKey = nativeStoredValue(named: "peerId", in: account).flatMap(AccountAvatarPolicy.peerKey)
        state.cancel()
        state.busy = true
        state.item.isEnabled = false
        let operation = state.operation
        let load = RetainedArchiveLoad()
        state.load = load
        UserDefaults.standard.set(TGExtraManualReadTransport.text("MANUAL_READ_PENDING"), forKey: "TGExtraManualReadStatus")
        let signal = postbox.multiplePeersView(PeerId.decodeArrayFromBuffer(ReadBuffer(data: data)))
        load.track(signal.start(next: { [weak controller, weak state, weak load] view in
            DispatchQueue.main.async {
                guard let controller, let state, let load, !load.cancelled, state.operation == operation else { return }
                load.cancel()
                state.load = nil
                guard UserDefaults.standard.bool(forKey: preference), scope(controller) == target,
                      let currentContext = nativeStoredValue(named: "context", in: controller),
                      let currentAccount = nativeStoredValue(named: "account", in: currentContext) as? Account,
                      currentAccount === account,
                      let currentNetwork = nativeStoredValue(named: "network", in: currentAccount),
                      nativeStoredValue(named: "basePath", in: currentNetwork) as? String == path else {
                    state.cancel(); return
                }
                guard let peers = nativeStoredValue(named: "peers", in: view),
                      let profile = RetainedMessageArchive.peerValues(in: peers).first(where: {
                          guard let id = nativeStoredValue(named: "id", in: $0) else { return false }
                          return AccountAvatarPolicy.peerKey(id) == target.peerKey
                      }), let payload = ManualReadPolicy.payload(scope: target, profile: profile, ownPeerKey: ownKey) else {
                    state.cancel(); failure("MANUAL_READ_LOOKUP_ERROR"); return
                }
                TGExtraManualReadTransport.send(payload, transport: transport as AnyObject) { [weak controller, weak state] error in
                    guard let controller, let state, state.operation == operation else { return }
                    state.busy = false
                    state.item.isEnabled = true
                    let message = error ?? TGExtraManualReadTransport.text("MANUAL_READ_DONE")
                    UserDefaults.standard.set(message, forKey: "TGExtraManualReadStatus")
                    NSLog("[TGExtra Manual Read] %@", message)
                    guard scope(controller) == target else { return }
                    if let error {
                        let alert = UIAlertController(title: TGExtraManualReadTransport.text("MANUAL_READ_TITLE"), message: error, preferredStyle: .alert)
                        alert.addAction(UIAlertAction(title: TGExtraManualReadTransport.text("OK"), style: .default))
                        if controller.presentedViewController == nil { controller.present(alert, animated: true) }
                    } else {
                        state.item.image = UIImage(systemName: "checkmark.circle")
                        UIAccessibility.post(notification: .announcement, argument: message)
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak state] in
                            guard let state, state.operation == operation else { return }
                            state.item.image = UIImage(systemName: "eye")
                        }
                    }
                }
            }
        }, error: nil, completed: nil))
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak state, weak load] in
            guard let state, let load, !load.cancelled, state.operation == operation else { return }
            state.cancel()
            failure("MANUAL_READ_LOOKUP_ERROR")
        }
    }
}
