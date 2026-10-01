import Foundation
import Darwin
import Postbox
import SwiftSignalKit
import TelegramCore

private let enqueueMessagesSymbol = "$s12TelegramCore15enqueueMessages7account6peerId8messages14SwiftSignalKit0J0CySay7Postbox07MessageG0VSgGAF7NoErrorOGAA7AccountC_AI04PeerG0VSayAA07EnqueueM0OGtF"

private typealias EnqueueMessagesFunction = @convention(thin) (
    Account,
    PeerId,
    [EnqueueMessage]
) -> Signal<[MessageId?], NoError>

@_silgen_name("MSHookFunction")
private func MSHookFunction(
    _ symbol: UnsafeMutableRawPointer,
    _ replacement: UnsafeMutableRawPointer,
    _ original: UnsafeMutablePointer<UnsafeMutableRawPointer?>
)

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

    let alreadyScheduled = messages.contains { message in
        message.attributes.contains { $0 is OutgoingScheduleInfoMessageAttribute }
    }
    if alreadyScheduled {
        return original(account, peerId, messages)
    }

    let hasQuickReply = messages.contains { message in
        message.attributes.contains {
            String(reflecting: type(of: $0)).contains("OutgoingQuickReplyMessageAttribute")
        }
    }
    if hasQuickReply {
        return original(account, peerId, messages)
    }

    let delay = automaticNativeDelay(for: messages)
    let scheduleTime = Int32(clamping: Int64(Date().timeIntervalSince1970) + delay)
    let transformedMessages = messages.map { message in
        message.withUpdatedAttributes { attributes in
            var attributes = attributes
            attributes.removeAll { $0 is OutgoingScheduleInfoMessageAttribute }
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
    return original(account, peerId, transformedMessages)
}

@_cdecl("TGExtraInstallNativeScheduleHook")
public func TGExtraInstallNativeScheduleHook() {
    guard originalEnqueueMessages == nil else { return }

    telegramCoreHandle = dlopen(nil, RTLD_NOW)
    let symbol = enqueueMessagesSymbol.withCString { name in
        dlsym(telegramCoreHandle, name)
    }
    guard let symbol else {
        UserDefaults.standard.set(
            "Hook nativo non trovato: TelegramCore incompatibile",
            forKey: "TGExtraAutomaticScheduleStatus"
        )
        return
    }

    let replacement: EnqueueMessagesFunction = nativeEnqueueMessagesHook
    let replacementPointer = unsafeBitCast(replacement, to: UnsafeMutableRawPointer.self)
    var originalPointer: UnsafeMutableRawPointer?
    MSHookFunction(symbol, replacementPointer, &originalPointer)
    if let originalPointer {
        originalEnqueueMessages = unsafeBitCast(originalPointer, to: EnqueueMessagesFunction.self)
        UserDefaults.standard.set(
            "Hook nativo attivo; in attesa del prossimo invio",
            forKey: "TGExtraAutomaticScheduleStatus"
        )
    } else {
        UserDefaults.standard.set(
            "Hook nativo non installato",
            forKey: "TGExtraAutomaticScheduleStatus"
        )
    }
}
