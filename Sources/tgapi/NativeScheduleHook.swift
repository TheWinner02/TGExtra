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

private enum NativeScheduleMediaKind {
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
}

private var originalEnqueueMessages: EnqueueMessagesFunction?
private var telegramCoreHandle: UnsafeMutableRawPointer?

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

private func finishNativeSendUIAction() -> Bool {
    let windows = UIApplication.shared.connectedScenes
        .compactMap { $0 as? UIWindowScene }
        .flatMap(\.windows)
    for window in windows where !window.isHidden {
        guard let rootController = window.rootViewController else { continue }
        for controller in nativeVisibleControllers(from: rootController).reversed() {
            let controllerType = String(reflecting: type(of: controller))
            guard controllerType.contains("ChatControllerImpl") else { continue }
            guard let action = nativeStoredValue(
                named: "layoutActionOnViewTransitionAction",
                in: controller
            ) as? () -> Void else {
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
            return true
        }
    }
    return false
}

private func nativeAttributeHasTypeName(_ attribute: MessageAttribute,
                                        _ typeName: String) -> Bool {
    let reflectedName = String(reflecting: type(of: attribute))
    return reflectedName == typeName || reflectedName.hasSuffix(".\(typeName)")
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

    let mirror = Mirror(reflecting: value)
    for child in mirror.children {
        let childLabel = child.label == "some" ? label : child.label
        inspectScheduleValue(child.value,
                             label: childLabel,
                             depth: depth + 1,
                             analysis: &analysis)
    }
}

private func automaticNativeDelay(for messages: [EnqueueMessage]) -> Int64 {
    var analysis = NativeScheduleAnalysis()
    for message in messages {
        inspectScheduleValue(message, label: nil, depth: 0, analysis: &analysis)
    }

    let megabytes = Double(analysis.size) / 1_048_576.0
    switch analysis.kind {
    case .text:
        return min(180, 60 + Int64(analysis.textLength / 200))
    case .photo:
        return min(600, 120 + Int64(ceil(megabytes)))
    case .video:
        return min(3_600, 120 + Int64(ceil(megabytes * 3.0)))
    case .audio, .file:
        return min(3_600, 120 + Int64(ceil(megabytes * 2.0)))
    }
}

private func nativeEnqueueMessagesHook(_ account: Account,
                                       _ peerId: PeerId,
                                       _ messages: [EnqueueMessage]) -> Signal<[MessageId?], NoError> {
    guard let original = originalEnqueueMessages else {
        fatalError("TGExtra native scheduler original function is unavailable")
    }
    guard UserDefaults.standard.bool(forKey: "TGExtraAutomaticSchedule"), !messages.isEmpty else {
        return original(account, peerId, messages)
    }

    UserDefaults.standard.set(
        "Hook nativo: controllo attributi",
        forKey: "TGExtraAutomaticScheduleStatus"
    )
    let alreadyScheduled = messages.contains { message in
        message.attributes.contains {
            nativeAttributeHasTypeName($0, "OutgoingScheduleInfoMessageAttribute")
        }
    }
    if alreadyScheduled {
        return original(account, peerId, messages)
    }

    let hasQuickReply = messages.contains { message in
        message.attributes.contains {
            nativeAttributeHasTypeName($0, "OutgoingQuickReplyMessageAttribute")
        }
    }
    if hasQuickReply {
        return original(account, peerId, messages)
    }

    UserDefaults.standard.set(
        "Hook nativo: analisi contenuto",
        forKey: "TGExtraAutomaticScheduleStatus"
    )
    let delay = automaticNativeDelay(for: messages)
    let scheduleTime = Int32(clamping: Int64(Date().timeIntervalSince1970) + delay)
    let transformedMessages = messages.map { message in
        message.withUpdatedAttributes { attributes in
            var attributes = attributes
            attributes.append(OutgoingScheduleInfoMessageAttribute(
                scheduleTime: scheduleTime,
                repeatPeriod: nil
            ))
            return attributes
        }
    }

    UserDefaults.standard.set(
        "Programmazione nativa: \(messages.count) messaggi, ritardo \(delay)s, data \(scheduleTime)",
        forKey: "TGExtraAutomaticScheduleStatus"
    )
    let signal = original(account, peerId, transformedMessages)
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
        let usedNativeCleanup = finishNativeSendUIAction()
        UserDefaults.standard.set(
            usedNativeCleanup
                ? "Programmazione nativa completata; UI ripristinata"
                : "Programmazione nativa completata; pulizia UI di fallback",
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
    if rebound > 0, let originalPointer {
        originalEnqueueMessages = unsafeBitCast(originalPointer, to: EnqueueMessagesFunction.self)
        UserDefaults.standard.set(
            "Hook nativo attivo; in attesa del prossimo invio",
            forKey: "TGExtraAutomaticScheduleStatus"
        )
    } else {
        UserDefaults.standard.set(
            "Hook nativo non trovato: TelegramCore incompatibile",
            forKey: "TGExtraAutomaticScheduleStatus"
        )
    }
}
