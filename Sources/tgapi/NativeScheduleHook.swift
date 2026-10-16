import Foundation
import Darwin
import UIKit
import ImageIO
import ObjectiveC
import Postbox
import SwiftSignalKit
import TelegramCore
import tgapiC

private let enqueueMessagesSymbol = "$s12TelegramCore15enqueueMessages7account6peerId8messages14SwiftSignalKit0J0CySay7Postbox07MessageG0VSgGAF7NoErrorOGAA7AccountC_AI04PeerG0VSayAA07EnqueueM0OGtF"
private let automaticScheduleDidEnqueueNotification = Notification.Name(
    "TGExtraAutomaticScheduleDidEnqueue"
)

private typealias EnqueueMessagesFunction = @convention(thin) (
    Account,
    PeerId,
    [EnqueueMessage]
) -> Signal<[MessageId?], NoError>

private typealias NativeScheduleMediaKind = AutomaticScheduleTiming.Kind

private struct NativeScheduleAnalysis {
    var kind: NativeScheduleMediaKind = .text
    var size: Int64 = 0
    var textLength: Int = 0
    var visitedNodes: Int = 0
    var correlationIds = Set<Int64>()
}

private struct NativeSchedulePlan {
    let delay: Int64
    let correlationIds: Set<Int64>
}

private var originalEnqueueMessages: EnqueueMessagesFunction?
private var telegramCoreHandle: UnsafeMutableRawPointer?

private enum NativeSendUICleanupResult {
    case restored(Int)
    case chatControllerWithoutAction(String)
    case chatControllerNotFound([String])

    var status: String {
        switch self {
        case let .restored(transitionCount):
            if transitionCount == 0 {
                return "Programmazione nativa completata; UI ripristinata"
            } else {
                return "Programmazione nativa completata; UI ripristinata con \(transitionCount) transizione/i"
            }
        case let .chatControllerWithoutAction(typeName):
            return "Pulizia fallback: azione assente in \(typeName)"
        case let .chatControllerNotFound(typeNames):
            let visibleTypes = typeNames.prefix(4).joined(separator: ", ")
            return visibleTypes.isEmpty
                ? "Pulizia fallback: nessun controller visibile"
                : "Pulizia fallback: chat non trovata (\(visibleTypes))"
        }
    }
}

private func nativeStoredValue(named name: String, in object: Any) -> Any? {
    var currentMirror: Mirror? = Mirror(reflecting: object)
    while let mirror = currentMirror {
        for child in mirror.children where child.label == name {
            let optionalMirror = Mirror(reflecting: child.value)
            if optionalMirror.displayStyle == .optional {
                return optionalMirror.children.first?.value
            }
            return child.value
        }
        currentMirror = mirror.superclassMirror
    }
    return nil
}

private func nativeStoredValue(typeNameContaining fragment: String,
                               in object: Any) -> Any? {
    var currentMirror: Mirror? = Mirror(reflecting: object)
    while let mirror = currentMirror {
        for child in mirror.children {
            let optionalMirror = Mirror(reflecting: child.value)
            let value: Any
            if optionalMirror.displayStyle == .optional {
                guard let unwrapped = optionalMirror.children.first?.value else {
                    continue
                }
                value = unwrapped
            } else {
                value = child.value
            }
            if String(reflecting: type(of: value)).contains(fragment) {
                return value
            }
        }
        currentMirror = mirror.superclassMirror
    }
    return nil
}

private func nativeVisibleControllers(from controller: UIViewController) -> [UIViewController] {
    var result: [UIViewController] = [controller]
    if let navigationController = controller as? UINavigationController {
        for child in navigationController.viewControllers {
            result.append(contentsOf: nativeVisibleControllers(from: child))
        }
    } else if let tabBarController = controller as? UITabBarController,
              let selectedController = tabBarController.selectedViewController {
        result.append(contentsOf: nativeVisibleControllers(from: selectedController))
    } else {
        for child in controller.children {
            result.append(contentsOf: nativeVisibleControllers(from: child))
        }
    }
    if let presentedController = controller.presentedViewController {
        result.append(contentsOf: nativeVisibleControllers(from: presentedController))
    }
    return result
}

private func nativeApplicationWindows() -> [UIWindow] {
    var result = UIApplication.shared.connectedScenes
        .compactMap { $0 as? UIWindowScene }
        .flatMap(\.windows)
    if let keyWindow = UIApplication.shared.keyWindow {
        result.append(keyWindow)
    }

    var seen = Set<ObjectIdentifier>()
    return result.filter { seen.insert(ObjectIdentifier($0)).inserted }
}

private func nativeControllersInViewHierarchy(of window: UIWindow) -> [UIViewController] {
    var result: [UIViewController] = []
    var seenControllers = Set<ObjectIdentifier>()
    var pendingViews: [UIView] = [window]
    var viewIndex = 0

    while viewIndex < pendingViews.count {
        let view = pendingViews[viewIndex]
        viewIndex += 1
        pendingViews.append(contentsOf: view.subviews)

        var responder: UIResponder? = view
        var responderDepth = 0
        while let currentResponder = responder, responderDepth < 12 {
            if let controller = currentResponder as? UIViewController,
               seenControllers.insert(ObjectIdentifier(controller)).inserted {
                result.append(controller)
            }
            responder = currentResponder.next
            responderDepth += 1
        }
    }
    return result
}

private func nativeAllVisibleControllers() -> [UIViewController] {
    var result: [UIViewController] = []
    var seenControllers = Set<ObjectIdentifier>()

    for window in nativeApplicationWindows() where !window.isHidden {
        var controllers = nativeControllersInViewHierarchy(of: window)
        if let rootController = window.rootViewController {
            controllers.append(contentsOf: nativeVisibleControllers(from: rootController))
        }
        for controller in controllers where
            seenControllers.insert(ObjectIdentifier(controller)).inserted {
            result.append(controller)
        }
    }
    return result
}

// Locate the actual account from the visible controller context. The network
// basePath scopes retained-message records to the account's local database.
private final class RetainedAccountReference {
    weak var account: Account?
    init(_ account: Account) { self.account = account }
}

private var retainedAccountReferences: [RetainedAccountReference] = []
private var retainedAccountPathKey: UInt8 = 0

// Account objects own immutable database paths. Cache per object, not globally
// by whichever account happened to be visible last.
private func retainedAccountPath(_ account: Account) -> String? {
    if let path = objc_getAssociatedObject(account, &retainedAccountPathKey) as? String { return path }
    guard let network = nativeStoredValue(named: "network", in: account),
          let path = nativeStoredValue(named: "basePath", in: network) as? String else { return nil }
    registerRetainedAccount(account)
    objc_setAssociatedObject(account, &retainedAccountPathKey, path, .OBJC_ASSOCIATION_COPY_NONATOMIC)
    return path
}

private func registerRetainedAccount(_ account: Account) {
    retainedAccountReferences.removeAll { $0.account == nil }
    if !retainedAccountReferences.contains(where: { $0.account === account }) {
        retainedAccountReferences.append(RetainedAccountReference(account))
    }
}

private func retainedMessageAccounts() -> [(Account, Postbox, String, AnyObject)] {
    var accounts = retainedAccountReferences.compactMap { $0.account }
    for controller in nativeAllVisibleControllers() {
        if let context = nativeStoredValue(named: "context", in: controller),
           let account = nativeStoredValue(named: "account", in: context) as? Account {
            registerRetainedAccount(account)
            accounts.removeAll { $0 === account }
            accounts.append(account)
        }
    }
    var result: [(Account, Postbox, String, AnyObject)] = []
    for account in accounts {
        guard let postbox = nativeStoredValue(named: "postbox", in: account) as? Postbox,
              let network = nativeStoredValue(named: "network", in: account),
              let path = nativeStoredValue(named: "basePath", in: network) as? String,
              let transport = nativeStoredValue(named: "mtProto", in: network) else { continue }
        if !result.contains(where: { $0.2 == path }) {
            result.append((account, postbox, path, transport as AnyObject))
        }
    }
    return result
}

private func retainedTransportContext(_ transport: AnyObject) -> AnyObject? {
    guard let object = transport as? NSObject,
          object.responds(to: NSSelectorFromString("context")) else { return nil }
    return object.value(forKey: "context") as AnyObject?
}

private func retainedTransportMatches(_ lhs: AnyObject, _ rhs: AnyObject) -> Bool {
    if lhs === rhs { return true }
    guard let leftContext = retainedTransportContext(lhs),
          let rightContext = retainedTransportContext(rhs) else { return false }
    return leftContext === rightContext
}

// Each archive screen owns its read-only request; dismissal/refresh cancels it.
final class RetainedArchiveLoad {
    private var disposables: [Disposable] = []
    private(set) var cancelled = false
    func track(_ disposable: Disposable) {
        if cancelled { disposable.dispose() } else { disposables.append(disposable) }
    }
    func cancel() {
        cancelled = true
        disposables.forEach { $0.dispose() }
        disposables.removeAll()
    }
    deinit { disposables.forEach { $0.dispose() } }
}

@objc(TGExtraDeletedMessageCleaner)
class TGExtraDeletedMessageCleaner: NSObject {
    private static let recordsKey = "TGExtraRetainedMessageRecords"
    private static var clearing = false
    private static var cleanupDisposable: Disposable?
    private static var uiAccountKey: UInt8 = 0
    // Full native IDs observed in chat, scoped by database, never by raw ID alone.
    private static var observedIds: [String: [String: MessageId]] = [:]
    private static var readStatus: [String: String] = [:]
    private static var markerIndex = RetainedMessageIndex(records:
        UserDefaults.standard.array(forKey: recordsKey) as? [[String: Any]] ?? [])

    private static func storeRecords(_ records: [[String: Any]]) {
        precondition(Thread.isMainThread)
        UserDefaults.standard.set(records, forKey: recordsKey)
        markerIndex = RetainedMessageIndex(records: records)
    }

    private typealias ReflectedId = RetainedMessageIdentity

    // Public native batch decoder: PeerId and MessageId are constructed inside
    // Postbox, not across the layout-only stub's incompatible scalar ABI.
    private static func decodedChannelIds(_ records: [[String: Any]]) -> [MessageId] {
        let fields = records.compactMap { record -> ReflectedId? in
            guard let channel = (record["channel"] as? NSNumber)?.int64Value,
                  let id = (record["id"] as? NSNumber)?.int32Value else { return nil }
            return ReflectedId.channel(channel, message: id)
        }
        guard !fields.isEmpty else { return [] }
        let symbols = [
            "$s7Postbox9MessageIdV19decodeArrayFromDataySayACG10Foundation0G0VFZ",
            "$s7Postbox9MessageIdV19decodeArrayFromDataySayACG10Foundation4DataVFZ"
        ]
        for symbol in symbols {
            guard dlsym(telegramCoreHandle, symbol) != nil || dlsym(nil, symbol) != nil else { continue }
            let result = MessageId.decodeArrayFromData(ReflectedId.encoded(fields))
            // Reject unfamiliar client layouts rather than deleting by a guess.
            guard result.count == fields.count,
                  zip(result, fields).allSatisfy({ components($0.0) == $0.1 }) else { return [] }
            return result
        }
        return []
    }

    // Do not invoke PeerId getters/toInt64 through the layout-only scheduling
    // stub. Real Postbox types are resilient and use a different getter ABI.
    private static func components(_ id: MessageId) -> ReflectedId? {
        guard let peer = nativeStoredValue(named: "peerId", in: id),
              let namespace = nativeStoredValue(named: "namespace", in: id) as? Int32,
              let rawId = nativeStoredValue(named: "id", in: id) as? Int32,
              let peerNamespace = nativeStoredValue(named: "namespace", in: peer),
              let peerId = nativeStoredValue(named: "id", in: peer) else { return nil }
        let ns = (peerNamespace as? UInt32) ?? (nativeStoredValue(named: "rawValue", in: peerNamespace) as? UInt32)
        let raw = (peerId as? Int64) ?? (nativeStoredValue(named: "rawValue", in: peerId) as? Int64)
        guard let ns, ns <= 7, let raw, raw >= 0, UInt64(raw) < (UInt64(1) << 61) else { return nil }
        let bits = UInt64(raw)
        let packed = (bits & 0xffffffff) | (UInt64(ns) << 32) | ((bits >> 32) << 35)
        return ReflectedId(peer: Int64(bitPattern: packed), namespace: namespace, id: rawId)
    }

    private static func matches(_ id: ReflectedId, record: [String: Any]) -> Bool {
        id.matches(record: record)
    }

    private static func messageIds(in value: Any, depth: Int = 0) -> [MessageId] {
        if let id = value as? MessageId { return [id] }
        if let id = nativeStoredValue(named: "id", in: value) as? MessageId { return [id] }
        guard depth < 12 else { return [] }
        let mirror = Mirror(reflecting: value)
        return mirror.children.prefix(100).flatMap { child -> [MessageId] in
            let structural = mirror.displayStyle == .enum || mirror.displayStyle == .tuple ||
                mirror.displayStyle == .collection || mirror.displayStyle == .optional
            guard structural || ["message", "firstMessage", "content", "messages", "_message", "_content", "_impl", "_value", "value", "_id"].contains(child.label ?? "") else { return [] }
            return messageIds(in: child.value, depth: depth + 1)
        }
    }

    @objc(bindUI:presenter:)
    static func bindUI(_ ui: UIViewController, presenter: UIViewController) {
        precondition(Thread.isMainThread)
        guard let window = presenter.view.window else { return }
        // Only controllers whose views are currently on screen, not cached
        // accounts or old navigation stacks from a different login.
        let controllers = nativeControllersInViewHierarchy(of: window)
        for controller in controllers.reversed() where !controller.view.isHidden {
            if let context = nativeStoredValue(named: "context", in: controller),
               let account = nativeStoredValue(named: "account", in: context) as? Account {
                registerRetainedAccount(account)
                if let entry = retainedMessageAccounts().first(where: { $0.0 === account }) {
                    objc_setAssociatedObject(ui, &uiAccountKey, entry.2, .OBJC_ASSOCIATION_COPY_NONATOMIC)
                    return
                }
            }
        }
    }

    @objc(statusForUI:)
    static func statusForUI(_ ui: UIViewController) -> String {
        guard let path = objc_getAssociatedObject(ui, &uiAccountKey) as? String else {
            return "Account aperto non identificato: apri una chat e riapri TGExtra."
        }
        let records = UserDefaults.standard.array(forKey: recordsKey) as? [[String: Any]] ?? []
        let count = records.filter { ($0["account"] as? String) == path }.count
        let observed = (observedIds[path] ?? [:]).count
        return "Account aperto: \(count) messaggi registrati; \(observed) ID completi letti dalle chat. " + (readStatus[path] ?? "Nessuna cella acquisita.")
    }

    @objc(loadAccountAvatarForUI:completion:)
    static func loadAccountAvatar(_ ui: UIViewController, completion: @escaping (UIImage?, String) -> Void) {
        precondition(Thread.isMainThread)
        // Diagnostics contain counts and failure stages only: no account IDs,
        // photo resource IDs, paths, or message contents.
        func finish(_ image: UIImage?, _ status: String) {
            NSLog("[TGExtra Avatar] %@", status)
            completion(image, status)
        }
        guard let path = objc_getAssociatedObject(ui, &uiAccountKey) as? String else {
            finish(nil, "Fallback: account del menu non identificato. Apri una chat e riapri TGExtra."); return
        }
        guard let account = retainedMessageAccounts().first(where: { $0.2 == path }) else {
            finish(nil, "Fallback: account associato non presente nel registro nativo."); return
        }
        guard let peer = nativeStoredValue(named: "peerId", in: account.0) else {
            finish(nil, "Fallback: campo account.peerId non leggibile."); return
        }
        guard let ownPeer = AccountAvatarPolicy.peerKey(peer) else {
            finish(nil, "Fallback: formato account.peerId non riconosciuto."); return
        }
        guard let mediaBox = nativeStoredValue(named: "mediaBox", in: account.1),
              let basePath = nativeStoredValue(named: "basePath", in: mediaBox) as? String else {
            finish(nil, "Fallback: percorso MediaBox non leggibile; account riconosciuto."); return
        }
        // Inspect already-loaded views only, once when the menu opens. No avatar
        // hooks, no global account image cache, and no arbitrary chat screenshots.
        var pending = nativeApplicationWindows().filter { !$0.isHidden }.map { $0 as UIView }
        var controllers = nativeAllVisibleControllers()
        var seenControllers = Set<ObjectIdentifier>()
        while let controller = controllers.popLast(), seenControllers.count < 200 {
            guard seenControllers.insert(ObjectIdentifier(controller)).inserted else { continue }
            if let view = controller.viewIfLoaded { pending.append(view) }
            controllers.append(contentsOf: controller.children)
            if let tabs = controller as? UITabBarController { controllers.append(contentsOf: tabs.viewControllers ?? []) }
            if let nav = controller as? UINavigationController { controllers.append(contentsOf: nav.viewControllers) }
        }
        let selector = NSSelectorFromString("asyncdisplaykit_node")
        var seen = Set<ObjectIdentifier>()
        var resources: [String] = []
        var nodes = 0
        var avatars = 0
        var rejected: [String: Int] = [:]
        while let view = pending.popLast(), seen.count < 4000 {
            guard seen.insert(ObjectIdentifier(view)).inserted else { continue }
            pending.append(contentsOf: view.subviews)
            guard view.responds(to: selector),
                  let node = view.perform(selector)?.takeUnretainedValue() else { continue }
            nodes += 1
            guard String(reflecting: type(of: node)).contains("AvatarNode") else { continue }
            avatars += 1
            if let id = AccountAvatarPolicy.resourceId(in: node, accountPeer: ownPeer) {
                if !resources.contains(id) { resources.append(id) }
            } else {
                let reason = AccountAvatarPolicy.rejectionReason(in: node, accountPeer: ownPeer)
                rejected[reason, default: 0] += 1
            }
        }
        let reasons = rejected.keys.sorted().map { "\($0): \(rejected[$0]!)" }.joined(separator: "; ")
        let scan = "Account riconosciuto. Viste: \(seen.count); nodi: \(nodes); avatar: \(avatars); risorse: \(resources.count)." +
            (pending.isEmpty ? "" : " Limite scansione raggiunto.") + (reasons.isEmpty ? "" : " \(reasons).")
        guard !resources.isEmpty else { finish(nil, "\(scan) Fallback: nessuna foto propria recuperabile dalle viste caricate."); return }
        let resourceIds = resources
        DispatchQueue.global(qos: .utility).async {
            let directory = URL(fileURLWithPath: basePath, isDirectory: true).resolvingSymlinksInPath()
            var image: UIImage?
            var missing = 0
            var invalid = 0
            var unreadable = 0
            for id in resourceIds {
                let file = directory.appendingPathComponent(id).resolvingSymlinksInPath()
                guard file.deletingLastPathComponent().path == directory.path else { invalid += 1; continue }
                guard let attributes = try? FileManager.default.attributesOfItem(atPath: file.path) else { missing += 1; continue }
                guard let size = attributes[.size] as? NSNumber, size.intValue > 0, size.intValue <= 4 * 1024 * 1024 else { invalid += 1; continue }
                guard let source = CGImageSourceCreateWithURL(file as CFURL, nil) else { unreadable += 1; continue }
                let options: [String: Any] = [
                    kCGImageSourceCreateThumbnailFromImageAlways as String: true,
                    kCGImageSourceCreateThumbnailWithTransform as String: true,
                    kCGImageSourceThumbnailMaxPixelSize as String: 400,
                    kCGImageSourceShouldCacheImmediately as String: true
                ]
                if let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) {
                    image = UIImage(cgImage: thumbnail)
                    break
                }
                unreadable += 1
            }
            let result = image
            let status = scan + (image != nil ? " Foto caricata dalla cache." : " Fallback cache: assenti/inaccessibili \(missing); file non validi \(invalid); immagini non decodificabili \(unreadable).")
            DispatchQueue.main.async { [weak ui] in
                guard let ui, objc_getAssociatedObject(ui, &uiAccountKey) as? String == path else { return }
                finish(result, status)
            }
        }
    }

    private static func archiveTitle(_ message: Any, fields: ReflectedId) -> String {
        guard let storage = nativeStoredValue(named: "peers", in: message) else { return "" }
        for peer in RetainedMessageArchive.peerValues(in: storage) {
            guard let peerId = nativeStoredValue(named: "id", in: peer),
                  let nsValue = nativeStoredValue(named: "namespace", in: peerId),
                  let idValue = nativeStoredValue(named: "id", in: peerId) else { continue }
            let ns = (nsValue as? UInt32) ?? (nativeStoredValue(named: "rawValue", in: nsValue) as? UInt32)
            let raw = (idValue as? Int64) ?? (nativeStoredValue(named: "rawValue", in: idValue) as? Int64)
            guard let ns, ns <= 7, let raw, raw >= 0, UInt64(raw) < (UInt64(1) << 61) else { continue }
            let bits = UInt64(raw)
            let packed = (bits & 0xffffffff) | (UInt64(ns) << 32) | ((bits >> 32) << 35)
            guard Int64(bitPattern: packed) == fields.peer else { continue }
            if let title = nativeStoredValue(named: "title", in: peer) as? String, !title.isEmpty { return title }
            let names = ["firstName", "lastName"].compactMap { nativeStoredValue(named: $0, in: peer) as? String }
            return names.filter { !$0.isEmpty }.joined(separator: " ")
        }
        return ""
    }

    private static func archiveKind(_ message: Any) -> String {
        guard let media = nativeStoredValue(named: "media", in: message) else { return "text" }
        for child in Mirror(reflecting: media).children {
            let name = String(reflecting: type(of: child.value))
            if name.contains("TelegramMediaImage") { return "photo" }
            if name.contains("TelegramMediaContact") { return "contact" }
            if name.contains("TelegramMediaMap") { return "location" }
            if name.contains("TelegramMediaPoll") { return "poll" }
            if name.contains("TelegramMediaFile") {
                if let attributes = nativeStoredValue(named: "attributes", in: child.value) {
                    for attribute in Mirror(reflecting: attributes).children {
                        let label = Mirror(reflecting: attribute.value).children.first?.label?.lowercased() ?? ""
                        if label.contains("audio") { return "audio" }
                        if label.contains("video") { return "video" }
                        if label.contains("sticker") { return "sticker" }
                    }
                }
                return "file"
            }
        }
        return Mirror(reflecting: media).children.isEmpty ? "text" : "attachment"
    }

    static func loadArchive(_ ui: UIViewController,
                            completion: @escaping ([RetainedArchiveChat]?, String?) -> Void) -> RetainedArchiveLoad {
        precondition(Thread.isMainThread)
        let load = RetainedArchiveLoad()
        guard let path = objc_getAssociatedObject(ui, &uiAccountKey) as? String,
              let account = retainedMessageAccounts().first(where: { $0.2 == path }) else {
            completion(nil, "account"); return load
        }
        // Snapshot this account only. No persistence, media download or mutation.
        let records = (UserDefaults.standard.array(forKey: recordsKey) as? [[String: Any]] ?? [])
            .filter { ($0["account"] as? String) == path }.map { record -> [String: Any] in
                var event = record
                event.removeValue(forKey: "peer")
                event.removeValue(forKey: "namespace")
                return event
            }
        guard !records.isEmpty else { completion([], nil); return load }
        let observed = Array((observedIds[path] ?? [:]).values)
        let archiveIndex = RetainedMessageIndex(records: records)
        let observedFields = observed.compactMap { id -> (MessageId, ReflectedId)? in
            components(id).map { (id, $0) }
        }
        let observedById = Dictionary(grouping: observedFields, by: { $0.1.id })
        let decoded = decodedChannelIds(records)
        let transaction = account.1.transaction(userInteractive: true, ignoreDisabled: false, { transaction -> [MessageId] in
            let globalIds = records.filter { ($0["channel"] as? NSNumber)?.int64Value == 0 }
                .compactMap { ($0["id"] as? NSNumber)?.int32Value }
            var ids = transaction.messageIdsForGlobalIds(globalIds) + decoded
            for record in records {
                guard let id = (record["id"] as? NSNumber)?.int32Value else { continue }
                let candidates = (observedById[id] ?? []).filter { matches($0.1, record: record) }
                if candidates.count == 1 { ids.append(candidates[0].0) }
            }
            var seen = Set<String>()
            return ids.filter { id in
                guard let fields = components(id), archiveIndex.contains(fields, account: path) else { return false }
                return seen.insert(fields.key).inserted
            }
        }, file: #file, line: #line)
        load.track(transaction.start(next: { ids in
            DispatchQueue.main.async {
                guard !load.cancelled else { return }
                var found: [(ReflectedId, RetainedArchiveMessage)] = []
                func finish() {
                    var items = found.map { $0.1 }
                    let foundById = Dictionary(grouping: found.map { $0.0 }, by: { $0.id })
                    for record in records {
                        guard let id = (record["id"] as? NSNumber)?.int32Value else { continue }
                        if foundById[id]?.contains(where: { matches($0, record: record) }) == true { continue }
                        let channel = (record["channel"] as? NSNumber)?.int64Value ?? 0
                        let key = ReflectedId.channel(channel, message: id).map { String($0.peer) } ?? "unresolved"
                        items.append(RetainedArchiveMessage(chatKey: key, chatTitle: "", id: id,
                            timestamp: nil, text: "", kind: "unavailable", topic: nil, available: false))
                    }
                    load.cancel()
                    completion(RetainedMessageArchive.grouped(items), nil)
                }
                // Small native batches; never keep complete media/message objects
                // after extracting the transient archive display model.
                func readBatch(_ offset: Int) {
                    guard !load.cancelled else { return }
                    guard offset < ids.count else { finish(); return }
                    let end = min(offset + 200, ids.count)
                    load.track(account.1.messagesAtIds(Array(ids[offset..<end])).start(next: { messages in
                        DispatchQueue.main.async {
                            guard !load.cancelled else { return }
                            for message in messages {
                                guard let id = messageIds(in: message).first,
                                      let fields = components(id), archiveIndex.contains(fields, account: path) else { continue }
                                let text = nativeStoredValue(named: "text", in: message) as? String ?? ""
                                let timestamp = nativeStoredValue(named: "timestamp", in: message) as? Int32
                                let topic = nativeStoredValue(named: "threadId", in: message) as? Int64
                                let topicTitle = nativeStoredValue(named: "associatedThreadInfo", in: message)
                                    .flatMap { nativeStoredValue(named: "title", in: $0) as? String }
                                found.append((fields, RetainedArchiveMessage(chatKey: String(fields.peer),
                                    chatTitle: archiveTitle(message, fields: fields), id: fields.id,
                                    timestamp: timestamp, text: text, kind: archiveKind(message), topic: topic, available: true,
                                    topicTitle: topicTitle)))
                            }
                            readBatch(end)
                        }
                    }, error: nil, completed: nil))
                }
                readBatch(0)
            }
        }, error: nil, completed: nil))
        return load
    }

    @objc(registerNode:)
    static func registerNode(_ node: AnyObject) -> Bool {
        guard Thread.isMainThread,
              let item = nativeStoredValue(named: "item", in: node) else { return false }
        let context = nativeStoredValue(named: "context", in: node) ??
            nativeStoredValue(named: "context", in: item)
        guard let context,
              let account = nativeStoredValue(named: "account", in: context) as? Account,
              let path = retainedAccountPath(account) else { return false }
        guard markerIndex.hasRecords(account: path) else { return false }
        var deleted = false
        var acquired = 0
        for id in messageIds(in: item) {
            guard let fields = components(id) else { continue }
            if markerIndex.contains(fields, account: path) { deleted = true }
            if markerIndex.shouldObserve(fields, account: path), observedIds[path]?[fields.key] == nil {
                observedIds[path, default: [:]][fields.key] = id
                acquired += 1
            }
        }
        if acquired > 0 { readStatus[path] = "Ultima cella: \(acquired) nuovi ID conservati acquisiti." }
        return deleted
    }

    private static func enrichRecords(path: String) {
        var records = UserDefaults.standard.array(forKey: recordsKey) as? [[String: Any]] ?? []
        var changed = false
        let observedFields = (observedIds[path] ?? [:]).values.compactMap { components($0) }
        for index in records.indices where (records[index]["account"] as? String) == path {
            // Revalidate metadata saved by earlier builds against the original
            // account/channel deletion event, not an old derived peer value.
            var event = records[index]
            event.removeValue(forKey: "peer")
            event.removeValue(forKey: "namespace")
            let matches = observedFields.filter { id in
                Self.matches(id, record: event)
            }
            if matches.count == 1, let id = matches.first,
               (records[index]["peer"] as? NSNumber)?.int64Value != id.peer ||
               (records[index]["namespace"] as? NSNumber)?.int32Value != id.namespace {
                records[index]["peer"] = NSNumber(value: id.peer)
                records[index]["namespace"] = NSNumber(value: id.namespace)
                changed = true
            }
        }
        if changed { storeRecords(records) }
    }

    @objc(recordIds:channelId:transport:)
    static func recordIds(_ ids: [NSNumber], channelId: NSNumber, transport: AnyObject) {
        DispatchQueue.main.async {
            guard let account = retainedMessageAccounts().first(where: {
                retainedTransportMatches($0.3, transport)
            }) else {
                // Older/unknown records remain in the existing cache; do not
                // guess an account for a destructive operation.
                UserDefaults.standard.set("Eliminazione intercettata: account della connessione non trovato",
                    forKey: "TGExtraRetainedMessageStatus")
                return
            }
            var records = UserDefaults.standard.array(forKey: recordsKey) as? [[String: Any]] ?? []
            for id in ids {
                let record: [String: Any] = ["account": account.2,
                    "channel": channelId, "id": id, "token": UUID().uuidString]
                if !records.contains(where: {
                    ($0["account"] as? String) == account.2 &&
                    ($0["channel"] as? NSNumber) == channelId &&
                    ($0["id"] as? NSNumber) == id
                }) { records.append(record) }
            }
            storeRecords(records)
            enrichRecords(path: account.2)
            UserDefaults.standard.set("Eliminazione registrata: \(ids.count) messaggi associati all'account",
                forKey: "TGExtraRetainedMessageStatus")
        }
    }

    @objc(clearForUI:completion:)
    static func clear(_ ui: UIViewController, completion: @escaping (Int, Int, String?) -> Void) {
        clear(ui, scope: nil, completion: completion)
    }

    static func clearChat(_ ui: UIViewController, scope: RetainedChatCleanupScope,
                          completion: @escaping (Int, Int, String?) -> Void) {
        clear(ui, scope: scope, completion: completion)
    }

    private static func clear(_ ui: UIViewController, scope: RetainedChatCleanupScope?,
                              completion: @escaping (Int, Int, String?) -> Void) {
        precondition(Thread.isMainThread)
        guard !clearing else { completion(0, 0, "Pulizia già in corso."); return }
        guard let path = objc_getAssociatedObject(ui, &uiAccountKey) as? String,
              let account = retainedMessageAccounts().first(where: { $0.2 == path }) else {
            completion(0, 0, "Apri una chat dell'account da pulire e riprova."); return
        }
        enrichRecords(path: path)
        let allRecords = UserDefaults.standard.array(forKey: recordsKey) as? [[String: Any]] ?? []
        let records = allRecords.filter { record in
            if let scope { return scope.selects(record, account: account.2) }
            return record["account"] as? String == account.2
        }
        let legacyIds = UserDefaults.standard.array(forKey: "TGExtraDeletedMessageIds") as? [NSNumber] ?? []
        let knownIds = Set(allRecords.compactMap { ($0["id"] as? NSNumber)?.int32Value })
        let unresolved = scope == nil ? legacyIds.filter { !knownIds.contains($0.int32Value) }.count : 0
        guard !records.isEmpty else {
            if scope != nil { completion(0, 0, nil); return }
            let status = UserDefaults.standard.string(forKey: "TGExtraRetainedMessageStatus")
            let error = status?.contains("non trovato") == true ? status : nil
            completion(0, unresolved, error)
            return
        }
        clearing = true
        // Capture on the main queue; never access the UI registry on Postbox's queue.
        let observed = Array((observedIds[path] ?? [:]).values)
        let decoded = decodedChannelIds(records)
        let cellStatus = readStatus[path] ?? "Nessuna cella acquisita."
        let signal = account.1.transaction(userInteractive: true, ignoreDisabled: false, { transaction -> ([MessageId], String) in
            let globalIds = records.filter { ($0["channel"] as? NSNumber)?.int64Value == 0 }
                .compactMap { ($0["id"] as? NSNumber)?.int32Value }
            var ids = transaction.messageIdsForGlobalIds(globalIds)
            let globalCount = ids.count
            ids.append(contentsOf: decoded)
            for record in records {
                let candidates = observed.filter { id in
                    guard let fields = components(id) else { return false }
                    return matches(fields, record: record)
                }
                if candidates.count == 1 { ids.append(contentsOf: candidates) }
            }
            let candidateCount = ids.count
            var seen = Set<String>()
            ids = ids.filter {
                guard let fields = components($0), records.contains(where: { matches(fields, record: $0) }) else { return false }
                if let scope, !scope.contains(fields) { return false }
                return seen.insert(fields.key).inserted
            }
            return (ids, "ID chat: \(observed.count); ID canali nativi: \(decoded.count); lookup globale: \(globalCount); candidati: \(candidateCount); ID validati: \(ids.count). \(cellStatus)")
        }, file: #file, line: #line)
        func finish(removedTokens: [String], diagnostic: String) {
                precondition(Thread.isMainThread)
                let tokens = Set(removedTokens)
                let current = UserDefaults.standard.array(forKey: recordsKey) as? [[String: Any]] ?? []
                let remaining = current.filter { !tokens.contains($0["token"] as? String ?? "") }
                storeRecords(remaining)
                // Drop only IDs that no longer belong to a retained event.
                for path in Array(observedIds.keys) {
                    observedIds[path] = observedIds[path]?.filter { _, id in
                        guard let fields = components(id) else { return false }
                        return markerIndex.shouldObserve(fields, account: path)
                    }
                }
                let retainedIds = Set(remaining.compactMap { ($0["id"] as? NSNumber)?.int32Value })
                let clearedIds = records.filter { tokens.contains($0["token"] as? String ?? "") }
                    .compactMap { ($0["id"] as? NSNumber)?.int32Value }
                    .filter { !retainedIds.contains($0) }
                TLParser.forgetDeletedMessageIds(clearedIds.map { NSNumber(value: $0) })
                clearing = false
                let notFound = records.count - tokens.count
                let error = notFound > 0
                    ? "Rimossi \(tokens.count) messaggi. Altri \(notFound) non individuati: registro e icone conservati.\n\nDiagnostica: \(diagnostic)"
                    : nil
                cleanupDisposable = nil
                completion(tokens.count, scope == nil ? unresolved : notFound, error)
        }
        cleanupDisposable = signal.start(next: { result in
            DispatchQueue.main.async {
                let candidates = result.0
                guard !candidates.isEmpty else {
                    finish(removedTokens: [], diagnostic: result.1)
                    return
                }
                // Batch array API: native Postbox performs the per-MessageId
                // lookup internally, avoiding the layout-only stub's scalar ABI.
                cleanupDisposable = account.1.messagesAtIds(candidates).start(next: { messages in
                    DispatchQueue.main.async {
                        let existing = messages.flatMap { messageIds(in: $0) }.filter { id in
                            guard let fields = components(id) else { return false }
                            if let scope, !scope.contains(fields) { return false }
                            return records.contains { matches(fields, record: $0) }
                        }
                        let diagnostic = result.1 + " Trovati via batch: \(existing.count)."
                        guard !existing.isEmpty else {
                            finish(removedTokens: [], diagnostic: diagnostic)
                            return
                        }
                        let deletion = account.1.transaction(userInteractive: true, ignoreDisabled: false, { transaction -> Bool in
                            transaction.deleteMessages(existing, forEachMedia: nil)
                            return true
                        }, file: #file, line: #line)
                        cleanupDisposable = deletion.start(next: { _ in
                            DispatchQueue.main.async {
                                // Clear cache markers only after an independent
                                // DB read confirms that the messages are gone.
                                cleanupDisposable = account.1.messagesAtIds(existing).start(next: { remainingMessages in
                                    DispatchQueue.main.async {
                                        let remainingFields = remainingMessages.flatMap { messageIds(in: $0) }.compactMap { components($0) }
                                        guard remainingFields.count == remainingMessages.count else {
                                            finish(removedTokens: [], diagnostic: diagnostic + " Verifica finale non leggibile: contrassegni conservati.")
                                            return
                                        }
                                        let removed = existing.compactMap { components($0) }.filter { fields in
                                            !remainingFields.contains { $0.key == fields.key }
                                        }
                                        let tokens = records.compactMap { record -> String? in
                                            removed.contains { matches($0, record: record) } ? record["token"] as? String : nil
                                        }
                                        finish(removedTokens: tokens, diagnostic: diagnostic + " Rimasti dopo pulizia: \(remainingMessages.count).")
                                    }
                                }, error: nil, completed: nil)
                            }
                        }, error: nil, completed: nil)
                    }
                }, error: nil, completed: nil)
            }
        }, error: nil, completed: nil)
    }
}

private func invokeNativePendingTransitions(_ pendingItems: Any,
                                            correlationIds: Set<Int64>) -> Int {
    let dictionaryMirror = Mirror(reflecting: pendingItems)
    guard dictionaryMirror.displayStyle == .dictionary else { return 0 }

    var matchingActions: [() -> Void] = []
    var allActions: [() -> Void] = []
    for entry in dictionaryMirror.children {
        let entryFields = Array(Mirror(reflecting: entry.value).children)
        guard entryFields.count >= 2 else { continue }
        let pendingValueFields = Array(Mirror(reflecting: entryFields[1].value).children)
        guard pendingValueFields.count >= 2,
              let action = pendingValueFields[1].value as? () -> Void else {
            continue
        }
        allActions.append(action)
        if let correlationId = entryFields[0].value as? Int64,
           correlationIds.contains(correlationId) {
            matchingActions.append(action)
        }
    }

    // Optimized Swift builds may omit the EnqueueMessage tuple labels used to
    // recover correlationId. currentPendingItems belongs to the active send and
    // is replaced on every non-grouped transition, so falling back to all of its
    // native completions is both scoped and preferable to leaving the composer
    // stuck forever for a scheduled message that never enters normal history.
    let actions = matchingActions.isEmpty ? allActions : matchingActions

    // Copy the closures before invoking them: the native completion can mutate
    // the transition node (and therefore currentPendingItems) while it runs.
    for action in actions {
        action()
    }
    return actions.count
}

private func finishNativeSendUIAction(
    correlationIds: Set<Int64>
) -> NativeSendUICleanupResult {
    var visibleControllerTypes: [String] = []
    var chatControllerType: String?

    for controller in nativeAllVisibleControllers().reversed() {
        let controllerType = String(reflecting: type(of: controller))
        if visibleControllerTypes.count < 8 {
            visibleControllerTypes.append(controllerType)
        }
        guard controllerType.contains("ChatController") else { continue }
        chatControllerType = controllerType

        var transitionCount = 0
        if let chatDisplayNode = nativeStoredValue(named: "chatDisplayNode", in: controller) ??
                nativeStoredValue(typeNameContaining: "ChatControllerNode", in: controller),
           let messageTransitionNode = nativeStoredValue(named: "messageTransitionNode", in: chatDisplayNode) ??
                nativeStoredValue(typeNameContaining: "ChatMessageTransitionNode", in: chatDisplayNode),
           let pendingItems = nativeStoredValue(
               named: "currentPendingItems",
               in: messageTransitionNode
           ) {
            transitionCount = invokeNativePendingTransitions(
                pendingItems,
                correlationIds: correlationIds
            )
        }

        guard let action = nativeStoredValue(
            named: "layoutActionOnViewTransitionAction",
            in: controller
        ) as? () -> Void else {
            if transitionCount > 0 {
                return .restored(transitionCount)
            }
            continue
        }

        action()

        if let chatDisplayNode = nativeStoredValue(named: "chatDisplayNode", in: controller),
           let replaceAction = nativeStoredValue(
               named: "setupSendActionOnViewUpdate",
               in: chatDisplayNode
           ) as? ((() -> Void), Int64?) -> Void {
            replaceAction({}, nil)
        }
        return .restored(transitionCount)
    }
    if let chatControllerType {
        return .chatControllerWithoutAction(chatControllerType)
    }
    return .chatControllerNotFound(visibleControllerTypes)
}

private func nativeAttributeHasTypeName(_ attribute: MessageAttribute,
                                        _ typeName: String) -> Bool {
    let reflectedName = String(reflecting: type(of: attribute))
    return reflectedName == typeName || reflectedName.hasSuffix(".\(typeName)")
}

private func attributesWithDefaultSilentMode(
    _ attributes: [MessageAttribute]
) -> [MessageAttribute] {
    var updatedAttributes = attributes
    for index in updatedAttributes.indices {
        guard let notificationInfo = updatedAttributes[index]
            as? NotificationInfoMessageAttribute else {
            continue
        }
        if notificationInfo.flags.contains(.muted) {
            return updatedAttributes
        }
        updatedAttributes[index] = NotificationInfoMessageAttribute(
            flags: notificationInfo.flags.union(.muted)
        )
        return updatedAttributes
    }
    updatedAttributes.append(NotificationInfoMessageAttribute(flags: .muted))
    return updatedAttributes
}

private func raiseKind(_ candidate: NativeScheduleMediaKind,
                       analysis: inout NativeScheduleAnalysis) {
    func priority(_ kind: NativeScheduleMediaKind) -> Int {
        switch kind {
        case .text: return 0
        case .lightweight: return 1
        case .photo: return 2
        case .audio: return 3
        case .file: return 4
        case .video: return 5
        }
    }
    if priority(candidate) > priority(analysis.kind) {
        analysis.kind = candidate
    }
}

private func inspectScheduleValue(_ value: Any,
                                  label: String?,
                                  depth: Int,
                                  analysis: inout NativeScheduleAnalysis) {
    guard depth <= 9, analysis.visitedNodes < 700 else { return }
    analysis.visitedNodes += 1

    let loweredLabel = (label ?? "").lowercased()
    let typeName = String(reflecting: type(of: value)).lowercased()

    if typeName.contains("telegrammediacontact") || typeName.contains("telegrammediamap") {
        raiseKind(.lightweight, analysis: &analysis)
    }

    if typeName.contains("telegrammediaimage") {
        raiseKind(.photo, analysis: &analysis)
    }
    if typeName.contains("telegrammediafile") {
        raiseKind(.file, analysis: &analysis)
    }
    if typeName.contains("video") {
        raiseKind(.video, analysis: &analysis)
    } else if typeName.contains("audio") || typeName.contains("voice") {
        raiseKind(.audio, analysis: &analysis)
    }

    if let string = value as? String {
        if loweredLabel == "text" || loweredLabel.contains("caption") {
            analysis.textLength = max(analysis.textLength, string.count)
        }
        let mime = string.lowercased()
        if loweredLabel.contains("mime") {
            if mime.hasPrefix("video/") {
                raiseKind(.video, analysis: &analysis)
            } else if mime.hasPrefix("audio/") {
                raiseKind(.audio, analysis: &analysis)
            } else if mime.hasPrefix("image/") {
                raiseKind(.photo, analysis: &analysis)
            } else {
                raiseKind(.file, analysis: &analysis)
            }
        }
    }

    if loweredLabel.contains("size") {
        if let number = value as? Int64 {
            analysis.size = max(analysis.size, number)
        } else if let number = value as? Int32 {
            analysis.size = max(analysis.size, Int64(number))
        } else if let number = value as? Int {
            analysis.size = max(analysis.size, Int64(number))
        }
    }

    if loweredLabel == "correlationid", let correlationId = value as? Int64 {
        analysis.correlationIds.insert(correlationId)
    }

    let mirror = Mirror(reflecting: value)
    for child in mirror.children {
        let childLabel = child.label == "some" ? label : child.label
        inspectScheduleValue(child.value,
                             label: childLabel,
                             depth: depth + 1,
                             analysis: &analysis)
    }
}

private func automaticNativePlan(
    for messages: [EnqueueMessage]
) -> NativeSchedulePlan {
    var analysis = NativeScheduleAnalysis()
    for message in messages {
        inspectScheduleValue(message, label: nil, depth: 0, analysis: &analysis)
    }

    let delay = AutomaticScheduleTiming.delay(kind: analysis.kind,
        textLength: analysis.textLength, size: analysis.size)
    return NativeSchedulePlan(
        delay: delay,
        correlationIds: analysis.correlationIds
    )
}

private func nativeEnqueueMessagesHook(_ account: Account,
                                       _ peerId: PeerId,
                                       _ messages: [EnqueueMessage]) -> Signal<[MessageId?], NoError> {
    guard let original = originalEnqueueMessages else {
        fatalError("TGExtra native scheduler original function is unavailable")
    }
    DispatchQueue.main.async { registerRetainedAccount(account) }
    let automaticScheduleEnabled = UserDefaults.standard.bool(
        forKey: "TGExtraAutomaticSchedule"
    )
    let defaultSilentEnabled = UserDefaults.standard.bool(
        forKey: "TGExtraDefaultSilentMessages"
    )
    guard !messages.isEmpty,
          automaticScheduleEnabled || defaultSilentEnabled else {
        return original(account, peerId, messages)
    }

    let alreadyScheduled = messages.contains { message in
        message.attributes.contains {
            nativeAttributeHasTypeName($0, "OutgoingScheduleInfoMessageAttribute")
        }
    }
    let hasQuickReply = messages.contains { message in
        message.attributes.contains {
            nativeAttributeHasTypeName($0, "OutgoingQuickReplyMessageAttribute")
        }
    }
    let shouldSchedule = automaticScheduleEnabled && !alreadyScheduled && !hasQuickReply
    let plan = shouldSchedule ? automaticNativePlan(for: messages) : nil
    let scheduleTime = plan.map {
        Int32(clamping: Int64(Date().timeIntervalSince1970) + $0.delay)
    }
    let transformedMessages = messages.map { message in
        message.withUpdatedAttributes { attributes in
            var attributes = attributes
            if defaultSilentEnabled {
                attributes = attributesWithDefaultSilentMode(attributes)
            }
            if let scheduleTime {
                attributes.append(OutgoingScheduleInfoMessageAttribute(
                    scheduleTime: scheduleTime,
                    repeatPeriod: nil
                ))
            }
            return attributes
        }
    }

    guard let plan, let scheduleTime else {
        return original(account, peerId, transformedMessages)
    }
    UserDefaults.standard.set(
        "Programmazione nativa: \(messages.count) messaggi, ritardo \(plan.delay)s, data \(scheduleTime)",
        forKey: "TGExtraAutomaticScheduleStatus"
    )
    let signal = original(account, peerId, transformedMessages)
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
        let cleanupResult = finishNativeSendUIAction(
            correlationIds: plan.correlationIds
        )
        UserDefaults.standard.set(
            cleanupResult.status,
            forKey: "TGExtraAutomaticScheduleStatus"
        )
        NotificationCenter.default.post(
            name: automaticScheduleDidEnqueueNotification,
            object: nil
        )
    }
    return signal
}

@_cdecl("TGExtraInstallNativeScheduleHook")
public func TGExtraInstallNativeScheduleHook() {
    guard originalEnqueueMessages == nil else { return }

    let replacement: EnqueueMessagesFunction = nativeEnqueueMessagesHook
    let replacementPointer = unsafeBitCast(replacement, to: UnsafeMutableRawPointer.self)
    telegramCoreHandle = dlopen(nil, RTLD_NOW)
    var originalPointer = enqueueMessagesSymbol.withCString { symbolName in
        dlsym(telegramCoreHandle, symbolName)
    }
    let rebound = enqueueMessagesSymbol.withCString { symbolName in
        TGExtraRebindSymbol(symbolName, replacementPointer, &originalPointer)
    }
    var interposed: Int32 = 0
    if rebound == 0, let originalPointer {
        interposed = TGExtraDynamicInterpose(originalPointer, replacementPointer)
    }
    if (rebound > 0 || interposed > 0), let originalPointer {
        originalEnqueueMessages = unsafeBitCast(originalPointer, to: EnqueueMessagesFunction.self)
        let hookMode = rebound > 0 ? "binding" : "interpose"
        UserDefaults.standard.set(
            "Hook nativo attivo (\(hookMode)); in attesa del prossimo invio",
            forKey: "TGExtraAutomaticScheduleStatus"
        )
    } else if originalPointer != nil {
        UserDefaults.standard.set(
            "Simbolo TelegramCore trovato, ma nessun metodo di hook compatibile",
            forKey: "TGExtraAutomaticScheduleStatus"
        )
    } else {
        UserDefaults.standard.set(
            "Simbolo enqueueMessages assente: ABI TelegramCore differente",
            forKey: "TGExtraAutomaticScheduleStatus"
        )
    }
}
