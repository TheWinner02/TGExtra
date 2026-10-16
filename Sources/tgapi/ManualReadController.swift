import Foundation
import UIKit
import ObjectiveC
import Darwin
import Postbox
import TelegramCore
import tgapiC

private final class ManualReadButtonState: NSObject {
    weak var controller: UIViewController?
    var item: UIBarButtonItem!
    var load: RetainedArchiveLoad?
    var operation = UUID()
    var busy = false

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
    @objc private func tapped() {
        guard let controller, !busy else { return }
        TGExtraManualReadController.markRead(controller, state: self)
    }
}

@objc(TGExtraManualReadController)
final class TGExtraManualReadController: NSObject {
    private static var stateKey: UInt8 = 0
    private static let owners = NSHashTable<UIViewController>.weakObjects()
    private static let preference = "disableMessageReadReceipt"

    @objc(updateForController:)
    static func update(_ controller: UIViewController) {
        precondition(Thread.isMainThread)
        let old = objc_getAssociatedObject(controller, &stateKey) as? ManualReadButtonState
        if !UserDefaults.standard.bool(forKey: preference) {
            if let old {
                old.cancel()
                let items = controller.navigationItem.rightBarButtonItems ?? controller.navigationItem.rightBarButtonItem.map { [$0] } ?? []
                if items.contains(where: { $0 === old.item }) {
                    controller.navigationItem.rightBarButtonItems = items.filter { $0 !== old.item }
                }
            }
            return
        }
        guard controller.viewIfLoaded?.window != nil else { return }
        let state = old ?? ManualReadButtonState(controller: controller)
        if old == nil {
            objc_setAssociatedObject(controller, &stateKey, state, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
            owners.add(controller)
        }
        let items = controller.navigationItem.rightBarButtonItems ?? controller.navigationItem.rightBarButtonItem.map { [$0] } ?? []
        // Preserve the client's avatar, menus and action targets. This is also
        // the fast layout path: no chat/message reflection while scrolling.
        if !items.contains(where: { $0 === state.item }) {
            controller.navigationItem.rightBarButtonItems = items + [state.item]
        }
    }

    @objc(hideForController:)
    static func hide(_ controller: UIViewController) {
        (objc_getAssociatedObject(controller, &stateKey) as? ManualReadButtonState)?.cancel()
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
        func failure(_ key: String) {
            let message = TGExtraManualReadTransport.text(key)
            UserDefaults.standard.set(message, forKey: "TGExtraManualReadStatus")
            if controller.presentedViewController == nil {
                let alert = UIAlertController(title: TGExtraManualReadTransport.text("MANUAL_READ_TITLE"), message: message, preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: TGExtraManualReadTransport.text("OK"), style: .default))
                controller.present(alert, animated: true)
            }
        }
        guard let target = scope(controller),
              let context = nativeStoredValue(named: "context", in: controller),
              let account = nativeStoredValue(named: "account", in: context) as? Account,
              let postbox = nativeStoredValue(named: "postbox", in: account) as? Postbox,
              let network = nativeStoredValue(named: "network", in: account),
              let transport = nativeStoredValue(named: "mtProto", in: network),
              let path = nativeStoredValue(named: "basePath", in: network) as? String else {
            failure("MANUAL_READ_UNSUPPORTED"); return
        }
        let symbols = ["$s7Postbox6PeerIdV21decodeArrayFromBufferySayACGAA04ReadG0CFZ",
                       "$s7Postbox10ReadBufferC4dataAC10Foundation4DataV_tcfC",
                       "$s7Postbox17MultiplePeersViewCMa",
                       "$s7PostboxAAC17multiplePeersViewy14SwiftSignalKit0F0CyAA08MultiplecD0CAD7NoErrorOGSayAA6PeerIdVGF"]
        guard symbols.allSatisfy({ dlsym(nil, $0) != nil }),
              let data = AccountAvatarPolicy.encodedPeerIds(target.peerKey) else {
            failure("MANUAL_READ_UNSUPPORTED"); return
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
