import Foundation
import Darwin
import UIKit
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
