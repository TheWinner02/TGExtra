import Foundation
import Darwin
import UIKit
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

private enum NativeScheduleMediaKind: Equatable {
    case text
    case photo
    case video
    case audio
    case file
}

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

@objc(TGExtraDeletedMessageCleaner)
class TGExtraDeletedMessageCleaner: NSObject {
    private static let recordsKey = "TGExtraRetainedMessageRecords"
    private static var clearing = false
    private static var cleanupDisposable: Disposable?
    private static var uiAccountKey: UInt8 = 0
    // Full native IDs observed in chat, scoped by database, never by raw ID alone.
    private static var observedIds: [String: [String: MessageId]] = [:]
    private static var readStatus: [String: String] = [:]

    private struct ReflectedId {
        let peer: Int64
        let namespace: Int32
        let id: Int32
        var key: String { "\(peer):\(namespace):\(id)" }
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
        guard id.id == (record["id"] as? NSNumber)?.int32Value, id.namespace == 0 else { return false }
        if let peer = (record["peer"] as? NSNumber)?.int64Value {
            return id.peer == peer && id.namespace == (record["namespace"] as? NSNumber)?.int32Value
        }
        let packed = UInt64(bitPattern: id.peer)
        let namespace = (packed >> 32) & 7
        let channel = (record["channel"] as? NSNumber)?.int64Value ?? 0
        let peer = (packed & 0xffffffff) | ((packed >> 35) << 32)
        return channel == 0 ? namespace < 2 : channel > 0 && namespace == 2 && peer == UInt64(channel)
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

    @objc(registerNode:)
    static func registerNode(_ node: AnyObject) {
        guard Thread.isMainThread else { return }
        let item = nativeStoredValue(named: "item", in: node)
        let context = nativeStoredValue(named: "context", in: node) ??
            item.flatMap { nativeStoredValue(named: "context", in: $0) }
        if let context,
           let account = nativeStoredValue(named: "account", in: context) as? Account {
            registerRetainedAccount(account)
            if let item,
               let entry = retainedMessageAccounts().first(where: { $0.0 === account }) {
                let ids = messageIds(in: item)
                var readable = 0
                for id in ids {
                    if let fields = components(id) {
                        observedIds[entry.2, default: [:]][fields.key] = id
                        readable += 1
                    }
                }
                if readable > 0 {
                    readStatus[entry.2] = "Ultima cella: \(readable) ID acquisiti."
                } else if let id = ids.first {
                    // Field names/types only: never include message text or media.
                    let fields = Mirror(reflecting: id).children.map { "\($0.label ?? "?"):\(type(of: $0.value))" }.joined(separator: ",")
                    let peer = nativeStoredValue(named: "peerId", in: id)
                    let peerFields = peer.map { Mirror(reflecting: $0).children.map { "\($0.label ?? "?"):\(type(of: $0.value))" }.joined(separator: ",") } ?? "assente"
                    readStatus[entry.2] = "ID non leggibile [\(fields)]; peer [\(peerFields)]."
                } else {
                    let fields = Mirror(reflecting: item).children.map { $0.label ?? "?" }.joined(separator: ",")
                    readStatus[entry.2] = "ID non acquisito: \(type(of: item)) [\(fields)]."
                }
                enrichRecords(path: entry.2)
            }
        }
    }

    private static func enrichRecords(path: String) {
        var records = UserDefaults.standard.array(forKey: recordsKey) as? [[String: Any]] ?? []
        var changed = false
        for index in records.indices where (records[index]["account"] as? String) == path {
            // Revalidate metadata saved by earlier builds against the original
            // account/channel deletion event, not an old derived peer value.
            var event = records[index]
            event.removeValue(forKey: "peer")
            event.removeValue(forKey: "namespace")
            let matches = (observedIds[path] ?? [:]).values.compactMap { components($0) }.filter { id in
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
        if changed { UserDefaults.standard.set(records, forKey: recordsKey) }
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
            UserDefaults.standard.set(records, forKey: recordsKey)
            enrichRecords(path: account.2)
            UserDefaults.standard.set("Eliminazione registrata: \(ids.count) messaggi associati all'account",
                forKey: "TGExtraRetainedMessageStatus")
        }
    }

    @objc(clearForUI:completion:)
    static func clear(_ ui: UIViewController, completion: @escaping (Int, Int, String?) -> Void) {
        precondition(Thread.isMainThread)
        guard !clearing else { completion(0, 0, "Pulizia già in corso."); return }
        guard let path = objc_getAssociatedObject(ui, &uiAccountKey) as? String,
              let account = retainedMessageAccounts().first(where: { $0.2 == path }) else {
            completion(0, 0, "Apri una chat dell'account da pulire e riprova."); return
        }
        enrichRecords(path: path)
        let allRecords = UserDefaults.standard.array(forKey: recordsKey) as? [[String: Any]] ?? []
        let records = allRecords.filter { ($0["account"] as? String) == account.2 }
        let legacyIds = UserDefaults.standard.array(forKey: "TGExtraDeletedMessageIds") as? [NSNumber] ?? []
        let knownIds = Set(allRecords.compactMap { ($0["id"] as? NSNumber)?.int32Value })
        let unresolved = legacyIds.filter { !knownIds.contains($0.int32Value) }.count
        guard !records.isEmpty else {
            let status = UserDefaults.standard.string(forKey: "TGExtraRetainedMessageStatus")
            let error = status?.contains("non trovato") == true ? status : nil
            completion(0, unresolved, error)
            return
        }
        clearing = true
        // Capture on the main queue; never access the UI registry on Postbox's queue.
        let observed = Array((observedIds[path] ?? [:]).values)
        let cellStatus = readStatus[path] ?? "Nessuna cella acquisita."
        let signal = account.1.transaction(userInteractive: true, ignoreDisabled: false, { transaction -> ([MessageId], String) in
            let globalIds = records.filter { ($0["channel"] as? NSNumber)?.int64Value == 0 }
                .compactMap { ($0["id"] as? NSNumber)?.int32Value }
            var ids = transaction.messageIdsForGlobalIds(globalIds)
            let globalCount = ids.count
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
                return seen.insert(fields.key).inserted
            }
            return (ids, "ID chat: \(observed.count); lookup globale: \(globalCount); candidati: \(candidateCount); ID validati: \(ids.count). \(cellStatus)")
        }, file: #file, line: #line)
        func finish(removedTokens: [String], diagnostic: String) {
                precondition(Thread.isMainThread)
                let tokens = Set(removedTokens)
                let current = UserDefaults.standard.array(forKey: recordsKey) as? [[String: Any]] ?? []
                let remaining = current.filter { !tokens.contains($0["token"] as? String ?? "") }
                UserDefaults.standard.set(remaining, forKey: recordsKey)
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
                completion(tokens.count, unresolved, error)
                cleanupDisposable = nil
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
        case .photo: return 1
        case .audio: return 2
        case .file: return 3
        case .video: return 4
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

    let megabytes = Double(analysis.size) / 1_048_576.0
    let delay: Int64
    switch analysis.kind {
    case .text:
        delay = min(180, 60 + Int64(analysis.textLength / 200))
    case .photo:
        delay = min(600, 120 + Int64(ceil(megabytes)))
    case .video:
        delay = min(3_600, 120 + Int64(ceil(megabytes * 3.0)))
    case .audio, .file:
        delay = min(3_600, 120 + Int64(ceil(megabytes * 2.0)))
    }
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
