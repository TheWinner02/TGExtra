import Foundation

@objc(TLParser)
class TLParser: NSObject {
	private static let deletedIdsQueue = DispatchQueue(label: "com.tgextra.deletedIds",
	                                                    attributes: .concurrent)
	private static var deletedIds = Set<Int32>(
		(UserDefaults.standard.array(forKey: "TGExtraDeletedMessageIds") as? [NSNumber] ?? [])
			.map { $0.int32Value }
	)

    private enum AutomaticMediaKind: Equatable {
        case photo
        case video
        case audio
        case file
        case other
    }

    private struct UploadRecord {
        var startedAt: TimeInterval
        var partSizes: [Int32: Int]

        var totalSize: Int64 {
            partSizes.values.reduce(0) { $0 + Int64($1) }
        }
    }

    private struct AutomaticMediaInfo {
        var kind: AutomaticMediaKind
        var size: Int64
        var startedAt: TimeInterval?
        var fileIds: [Int64]
    }

    private static let automaticScheduleQueue = DispatchQueue(label: "com.tgextra.automaticSchedule")
    private static var outgoingUploads: [Int64: UploadRecord] = [:]
    private static var lastScheduledDateByPeer: [String: Int64] = [:]

    private static let uploadSaveBigFilePart: Int32 = -562337987
    private static let uploadSaveFilePart: Int32 = -1291540959
    private static let messagesSendMediaIds: Set<Int32> = [
        -1521431176, // a550cd78
        -1403659839, // ac55d9c1
        53536639     // 0330e77f
    ]
    private static let messagesSendMessageIds: Set<Int32> = [
        -68013046,   // fbf234ea
        -33170278,   // fe05dc9a
        1376532592,  // 520c3870
        1415369050   // 545cd15a
    ]
    private static let messagesSendMultiMedia: Int32 = 469278068
    private static let vectorConstructor: Int32 = 481674261

    private static let automaticScheduleStatusKey = "TGExtraAutomaticScheduleStatus"
    private static let automaticScheduleRecentIdsKey = "TGExtraAutomaticScheduleRecentIds"

    private static func setAutomaticScheduleStatus(_ value: String) {
        UserDefaults.standard.set(value, forKey: automaticScheduleStatusKey)
    }

    private static func recordAutomaticScheduleFunctionId(_ functionId: Int32) {
        automaticScheduleQueue.sync {
            var ids = UserDefaults.standard.array(forKey: automaticScheduleRecentIdsKey) as? [NSNumber] ?? []
            if !ids.contains(where: { $0.int32Value == functionId }) {
                ids.append(NSNumber(value: functionId))
                if ids.count > 12 {
                    ids.removeFirst(ids.count - 12)
                }
                UserDefaults.standard.set(ids, forKey: automaticScheduleRecentIdsKey)
            }
        }
    }

	@objc static func handleResponse(_ data: NSData, functionID : NSNumber) -> NSData? {
		
		let buffer1 = Buffer(nsData: data)
		let reader = BufferReader(buffer1)
		let signature = reader.readInt32()
		
		if (signature == 481674261) { // Vector
			return data
			
			/*
			if (functionID == -1299661699) { // Get All Secure Values
				return Api.parseVector(reader, elementSignature: 0, elementType: Api.SecureValue.self)
			}
			else if (functionID == 1705865692) { // Get Multi Wallpaper
				return Api.parseVector(reader, elementSignature: 0, elementType: Api.WallPaper.self)
			}
			else if (functionID == 1936088002) { // Get Secure Value
				return Api.parseVector(reader, elementSignature: 0, elementType: Api.SecureValue.self)
			}
			else if (functionID == -1334764157) { // Get Admin Bots
				return Api.parseVector(reader, elementSignature: 0, elementType: Api.User.self)
			}
			else if (functionID == -481554986) { // Get Bot commands
				return Api.parseVector(reader, elementSignature: 0, elementType: Api.BotCommand.self)
			}
			else if (functionID == -1566222003) { // Get Preview Media
				return Api.parseVector(reader, elementSignature: 0, elementType: Api.BotPreviewMedia.self)
			}
			else if (functionID == -37955820) { // Get Chat Levae Suggestions
				return Api.parseVector(reader, elementSignature: 0, elementType: Api.Peer.self)
			}
			else if (functionID == 2061264541) { // Get Contact ids
				return data
			}
			else if (functionID == -2098076769) { // Get Saved contact
				return Api.parseVector(reader, elementSignature: 0, elementType: Api.SavedContact.self)
			}
			else if (functionID == -995929106) { // Get Statuses
				return Api.parseVector(reader, elementSignature: 0, elementType: Api.ContactStatus.self)
			} 
			else if (functionID == 1120311183) { // Get Language packs
				return Api.parseVector(reader, elementSignature: 0, elementType: Api.LangPackLanguage.self)
			}
			else if (functionID == -269862909) { // Get Lang pack Strings
				return Api.parseVector(reader, elementSignature: 0, elementType: Api.LangPackString.self)
			}
			else if (functionID == -866424884) { // Get Attachted Stickers
				return Api.parseVector(reader, elementSignature: 0, elementType: Api.StickerSetCovered.self)
			}
			else if (functionID == -643100844) { // Get Emoji Documents
				return Api.parseVector(reader, elementSignature: 0, elementType: Api.Document.self)
			}
			else if (functionID == 585256482) { // Get Dialog Unread Marks
				return Api.parseVector(reader, elementSignature: 0, elementType: Api.DialogPeer.self)
			}
			else if (functionID == 1318675378) { // Emoji Language 
				return Api.parseVector(reader, elementSignature: 0, elementType: Api.EmojiLanguage.self)
			}
			else if (functionID == -1177696786) { // Get Fact Check
				return Api.parseVector(reader, elementSignature: 0, elementType: Api.FactCheck.self)
			}
			else if (functionID == 834782287) { // Message read Receipiend
				return Api.parseVector(reader, elementSignature: 0, elementType: Api.ReadParticipantDate.self)
			}
			else if (functionID == 465367808) { // Get search Counters
				return Api.parseVector(reader, elementSignature: 0, elementType: Api.messages.SearchCounter.self)
			}
			else if (functionID == 486505992) { // Get Split Range
				return Api.parseVector(reader, elementSignature: 0, elementType: Api.MessageRange.self)
			}
			else if (functionID == -1566780372) { // Get Suggested Dialong Filters
				return Api.parseVector(reader, elementSignature: 0, elementType: Api.DialogFilterSuggested.self)
			}
			else if (functionID == 94983360) { // Received Notify Message
				return Api.parseVector(reader, elementSignature: 0, elementType: Api.ReceivedNotifyMessage.self)
			}
			else if (functionID == 1436924774) { // Received Queue
				return data
			}
			else if (functionID == 660060756) { // Premum Gift options
				return Api.parseVector(reader, elementSignature: 0, elementType: Api.PremiumGiftCodeOption.self)
			}
			else if (functionID == -741774392) { // Stars gift optioms
				return Api.parseVector(reader, elementSignature: 0, elementType: Api.StarsGiftOption.self)
			}
			else if (functionID == -1122042562) { // Stars giveaway options
				return Api.parseVector(reader, elementSignature: 0, elementType: Api.StarsGiveawayOption.self)
			}
			else if (functionID == -1072773165) { // Stars topup options
				return Api.parseVector(reader, elementSignature: 0, elementType: Api.StarsTopupOption.self)
			}
			else if (functionID == -1248003721) { // CHECK GROUP CALL
				return data
			}
			else if (functionID == -2016444625) { 
				return data
			}
			else if (functionID == -1369842849) { 
				return data
			}
			else if (functionID == 1398375363) { 
				return data
			}
			else if (functionID == -1521034552) { 
				return data
			}
			else if (functionID == -1703566865) { 
				return data
			}
			else if (functionID == -1847836879) { // Get CDN File hashes
				return Api.parseVector(reader, elementSignature: 0, elementType: Api.FileHash.self)
			}
			else if (functionID == -1856595926) { // Get file hashes
				return Api.parseVector(reader, elementSignature: 0, elementType: Api.FileHash.self)
			}
			else if (functionID == -1691921240) { // Reuppload CDN File
				return Api.parseVector(reader, elementSignature: 0, elementType: Api.FileHash.self)
			}
			else if (functionID == -660962397) { // Requiremntes to cintact
				return Api.parseVector(reader, elementSignature: 0, elementType: Api.RequirementToContact.self)
			}
			else if (functionID == 227648840) { // Get users
				return Api.parseVector(reader, elementSignature: 0, elementType: Api.User.self)
			}
			*/
		}
		
	    let buffer = Buffer(nsData: data)
		guard let result = Api.parse(buffer) else {
			return nil
		}
		
		let outputBuffer = Buffer()
		Api.serializeObject(result, buffer: outputBuffer, boxed: true)
		
		return outputBuffer.makeData() as NSData
	}

    private static func messageId(from item: Any) -> NSNumber? {
        let description = String(describing: item)
        let patterns = [
            "MessageId\\(peerId: [^,]+, namespace: [^,]+, id: (\\d+)\\)",
            "rawValue: \\d+\\):\\d+_(\\d+)",
            "messageId: (\\d+)"
        ]

        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(description.startIndex..<description.endIndex, in: description)
            guard let match = regex.firstMatch(in: description, range: range),
                  let idRange = Range(match.range(at: 1), in: description),
                  let value = Int32(description[idRange]) else { continue }
            return NSNumber(value: value)
        }

        let mirror = Mirror(reflecting: item)
        for child in mirror.children {
            guard child.label == "message" || child.label == "firstMessage" || child.label == "content" else {
                continue
            }

            if child.label == "content" {
                for contentChild in Mirror(reflecting: child.value).children {
                    if contentChild.label == "message" || contentChild.label == "firstMessage",
                       let value = messageId(fromMessage: contentChild.value) {
                        return value
                    }
                }
            }

            if let value = messageId(fromMessage: child.value) {
                return value
            }
        }

        return nil
    }

    private static func messageId(fromMessage message: Any) -> NSNumber? {
        for child in Mirror(reflecting: message).children where child.label == "id" {
            for idChild in Mirror(reflecting: child.value).children where idChild.label == "id" {
                if let value = idChild.value as? Int32 {
                    return NSNumber(value: value)
                }
            }
        }
        return nil
    }

    @objc static func getMessageIdFromNode(_ node: Any) -> NSNumber? {
        var currentMirror: Mirror? = Mirror(reflecting: node)
        while let mirror = currentMirror {
            for child in mirror.children where child.label == "item" {
                if let value = messageId(from: child.value) {
                    return value
                }
            }
            currentMirror = mirror.superclassMirror
        }

        return messageId(from: node)
    }

    @objc static func isDeleted(_ messageId: NSNumber) -> Bool {
        deletedIdsQueue.sync {
            deletedIds.contains(messageId.int32Value)
        }
    }

    @objc static func rememberDeletedMessageIds(_ messageIds: [NSNumber]) {
        deletedIdsQueue.sync(flags: .barrier) {
            deletedIds.formUnion(messageIds.map { $0.int32Value })
        }
    }

    private static func readObject<T>(_ reader: BufferReader, as type: T.Type) -> T? {
        guard let signature = reader.readInt32() else { return nil }
        return Api.parse(reader, signature: signature) as? T
    }

    private static func skipEntities(_ reader: BufferReader) -> Bool {
        guard reader.readInt32() == vectorConstructor,
              let count = reader.readInt32(), count >= 0, count <= 4096 else {
            return false
        }

        for _ in 0..<count {
            guard let _: Api.MessageEntity = readObject(reader, as: Api.MessageEntity.self) else {
                return false
            }
        }
        return true
    }

    private static func recordUploadPart(_ reader: BufferReader, isBig: Bool) {
        guard let fileId = reader.readInt64(), let part = reader.readInt32() else { return }
        if isBig && reader.readInt32() == nil { return }
        guard let bytes = parseBytes(reader) else { return }

        automaticScheduleQueue.sync {
            var record = outgoingUploads[fileId] ?? UploadRecord(
                startedAt: Date().timeIntervalSince1970,
                partSizes: [:]
            )
            record.partSizes[part] = bytes.size
            outgoingUploads[fileId] = record

            if outgoingUploads.count > 128,
               let oldest = outgoingUploads.min(by: { $0.value.startedAt < $1.value.startedAt })?.key,
               oldest != fileId {
                outgoingUploads.removeValue(forKey: oldest)
            }
        }
    }

    private static func inputFileId(_ file: Api.InputFile) -> Int64? {
        switch file {
        case let .inputFile(id, _, _, _):
            return id
        case let .inputFileBig(id, _, _):
            return id
        case .inputFileStoryDocument(_):
            return nil
        }
    }

    private static func uploadInfo(for file: Api.InputFile) -> (Int64, Int64, TimeInterval?)? {
        guard let fileId = inputFileId(file) else { return nil }
        return automaticScheduleQueue.sync {
            let record = outgoingUploads[fileId]
            return (fileId, record?.totalSize ?? 0, record?.startedAt)
        }
    }

    private static func mediaInfo(_ media: Api.InputMedia) -> AutomaticMediaInfo {
        switch media {
        case let .inputMediaUploadedPhoto(_, file, _, _):
            let upload = uploadInfo(for: file)
            return AutomaticMediaInfo(kind: .photo,
                                      size: upload?.1 ?? 0,
                                      startedAt: upload?.2,
                                      fileIds: upload.map { [$0.0] } ?? [])

        case let .inputMediaUploadedDocument(_, file, _, mimeType, _, _, _, _, _):
            let upload = uploadInfo(for: file)
            let kind: AutomaticMediaKind
            if mimeType.hasPrefix("video/") {
                kind = .video
            } else if mimeType.hasPrefix("audio/") {
                kind = .audio
            } else if mimeType.hasPrefix("image/") {
                kind = .photo
            } else {
                kind = .file
            }
            return AutomaticMediaInfo(kind: kind,
                                      size: upload?.1 ?? 0,
                                      startedAt: upload?.2,
                                      fileIds: upload.map { [$0.0] } ?? [])

        case .inputMediaPhoto(_, _, _), .inputMediaPhotoExternal(_, _, _):
            return AutomaticMediaInfo(kind: .photo, size: 0, startedAt: nil, fileIds: [])
        case .inputMediaDocument(_, _, _, _, _, _), .inputMediaDocumentExternal(_, _, _, _, _):
            return AutomaticMediaInfo(kind: .file, size: 0, startedAt: nil, fileIds: [])
        default:
            return AutomaticMediaInfo(kind: .other, size: 0, startedAt: nil, fileIds: [])
        }
    }

    private static func combinedMediaInfo(_ items: [Api.InputSingleMedia]) -> AutomaticMediaInfo {
        var infos: [AutomaticMediaInfo] = []
        for item in items {
            if case let .inputSingleMedia(_, media, _, _, _) = item {
                infos.append(mediaInfo(media))
            }
        }

        let kind: AutomaticMediaKind
        if infos.contains(where: { $0.kind == .video }) {
            kind = .video
        } else if infos.contains(where: { $0.kind == .file }) {
            kind = .file
        } else if infos.contains(where: { $0.kind == .audio }) {
            kind = .audio
        } else if infos.contains(where: { $0.kind == .photo }) {
            kind = .photo
        } else {
            kind = .other
        }

        return AutomaticMediaInfo(
            kind: kind,
            size: infos.reduce(0) { $0 + $1.size },
            startedAt: infos.compactMap { $0.startedAt }.min(),
            fileIds: infos.flatMap { $0.fileIds }
        )
    }

    private static func automaticDelay(kind: AutomaticMediaKind, size: Int64) -> Int64 {
        let megabytes = Double(size) / 1_048_576.0
        switch kind {
        case .photo:
            return min(300, 20 + Int64(ceil(megabytes)))
        case .video:
            return min(1_800, 30 + Int64(ceil(megabytes * 3.0)))
        case .audio, .file:
            return min(1_800, 20 + Int64(ceil(megabytes * 2.0)))
        case .other:
            return 20
        }
    }

    private static func scheduledDate(peerKey: String,
                                      delay: Int64,
                                      startedAt: TimeInterval? = nil) -> Int32 {
        let now = Int64(Date().timeIntervalSince1970)
        let origin = Int64(startedAt ?? Double(now))

        return automaticScheduleQueue.sync {
            let previous = lastScheduledDateByPeer[peerKey] ?? 0
            let value = max(max(now + 11, origin + delay), previous + 5)
            lastScheduledDateByPeer[peerKey] = value
            return Int32(clamping: value)
        }
    }

    private static func scheduledDate(peer: Api.InputPeer,
                                      delay: Int64,
                                      startedAt: TimeInterval? = nil) -> Int32 {
        return scheduledDate(peerKey: String(describing: peer), delay: delay, startedAt: startedAt)
    }

    // Read only the stable wire representation needed to locate schedule_date.
    // This avoids depending on TGExtra's generated API layer, which predates Telegram 12.9.x.
    private static func readRawPeerKey(_ reader: BufferReader) -> String? {
        guard let signature = reader.readInt32() else { return nil }
        switch signature {
        case 666680316: // inputPeerChannel
            guard let id = reader.readInt64(), reader.readInt64() != nil else { return nil }
            return "channel:\(id)"
        case -1121318848: // inputPeerChannelFromMessage
            guard readRawPeerKey(reader) != nil,
                  reader.readInt32() != nil,
                  let id = reader.readInt64() else { return nil }
            return "channelFromMessage:\(id)"
        case 900291769: // inputPeerChat
            guard let id = reader.readInt64() else { return nil }
            return "chat:\(id)"
        case 2134579434:
            return "empty"
        case 2107670217:
            return "self"
        case -571955892: // inputPeerUser
            guard let id = reader.readInt64(), reader.readInt64() != nil else { return nil }
            return "user:\(id)"
        case -1468331492: // inputPeerUserFromMessage
            guard readRawPeerKey(reader) != nil,
                  reader.readInt32() != nil,
                  let id = reader.readInt64() else { return nil }
            return "userFromMessage:\(id)"
        default:
            return nil
        }
    }

    private static func skipRawReplyTo(_ reader: BufferReader) -> Bool {
        guard let signature = reader.readInt32() else { return false }
        switch signature {
        case 583071445, 1003796418: // old and current inputReplyToMessage
            guard let flags = reader.readInt32(), reader.readInt32() != nil else { return false }
            if flags & (1 << 0) != 0 && reader.readInt32() == nil { return false }
            if flags & (1 << 1) != 0 && readRawPeerKey(reader) == nil { return false }
            if flags & (1 << 2) != 0 && parseString(reader) == nil { return false }
            if flags & (1 << 3) != 0 && !skipEntities(reader) { return false }
            if flags & (1 << 4) != 0 && reader.readInt32() == nil { return false }
            if signature == 1003796418 {
                if flags & (1 << 5) != 0 && readRawPeerKey(reader) == nil { return false }
                if flags & (1 << 6) != 0 && reader.readInt32() == nil { return false }
                if flags & (1 << 7) != 0 && parseBytes(reader) == nil { return false }
            }
            return true
        case 1484862010: // inputReplyToStory
            return readRawPeerKey(reader) != nil && reader.readInt32() != nil
        case 1775660101: // inputReplyToMonoForum
            return readRawPeerKey(reader) != nil
        default:
            return false
        }
    }

    private static func prepareRawTextSchedule(_ data: NSData,
                                               functionId: Int32,
                                               flags: Int32) -> NSData? {
        let reader = BufferReader(Buffer(nsData: data))
        guard reader.readInt32() == functionId, reader.readInt32() == flags,
              let peerKey = readRawPeerKey(reader) else {
            setAutomaticScheduleStatus("Testo riconosciuto, lettura destinatario fallita")
            return nil
        }

        if flags & (1 << 0) != 0 && !skipRawReplyTo(reader) {
            setAutomaticScheduleStatus("Testo riconosciuto, lettura risposta fallita")
            return nil
        }

        guard let message = parseString(reader), reader.readInt64() != nil else {
            setAutomaticScheduleStatus("Testo riconosciuto, lettura messaggio fallita")
            return nil
        }
        if flags & (1 << 2) != 0 {
            guard let _: Api.ReplyMarkup = readObject(reader, as: Api.ReplyMarkup.self) else {
                setAutomaticScheduleStatus("Testo riconosciuto, lettura tastiera fallita")
                return nil
            }
        }
        if flags & (1 << 3) != 0 && !skipEntities(reader) {
            setAutomaticScheduleStatus("Testo riconosciuto, lettura formattazione fallita")
            return nil
        }

        let delay = min(60, 15 + Int64(message.count / 200))
        let date = scheduledDate(peerKey: peerKey, delay: delay)
        guard let result = patchedPayload(data,
                                          flags: flags,
                                          insertionOffset: reader.offset,
                                          scheduleDate: date) else {
            setAutomaticScheduleStatus("Testo riconosciuto, modifica payload fallita")
            return nil
        }
        setAutomaticScheduleStatus("Testo programmato: ritardo \(delay)s, data \(date)")
        return result
    }

    private static func patchedPayload(_ data: NSData,
                                       flags: Int32,
                                       insertionOffset: UInt,
                                       scheduleDate: Int32) -> NSData? {
        guard insertionOffset <= UInt(data.length), data.length >= 8 else { return nil }
        let result = NSMutableData(data: data as Data)
        var updatedFlags = flags | (1 << 10)
        var date = scheduleDate
        result.replaceBytes(in: NSRange(location: 4, length: 4),
                            withBytes: &updatedFlags,
                            length: MemoryLayout<Int32>.size)
        result.replaceBytes(in: NSRange(location: Int(insertionOffset), length: 0),
                            withBytes: &date,
                            length: MemoryLayout<Int32>.size)
        return result
    }

    @objc static func prepareAutomaticSchedule(_ data: NSData) -> NSData? {
        guard UserDefaults.standard.bool(forKey: "TGExtraAutomaticSchedule") else { return data }

        let reader = BufferReader(Buffer(nsData: data))
        guard let functionId = reader.readInt32() else { return data }
        recordAutomaticScheduleFunctionId(functionId)

        if functionId == uploadSaveFilePart || functionId == uploadSaveBigFilePart {
            recordUploadPart(reader, isBig: functionId == uploadSaveBigFilePart)
            return data
        }

        guard messagesSendMessageIds.contains(functionId) ||
              messagesSendMediaIds.contains(functionId) ||
              functionId == messagesSendMultiMedia else {
            return data
        }

        setAutomaticScheduleStatus("RPC riconosciuta: \(functionId)")
        guard let flags = reader.readInt32() else {
            setAutomaticScheduleStatus("RPC riconosciuta, flags mancanti")
            return data
        }
        if flags & (1 << 10) != 0 {
            setAutomaticScheduleStatus("Messaggio gia programmato da Telegram")
            return data
        }
        if flags & (1 << 17) != 0 {
            setAutomaticScheduleStatus("Invio rapido escluso dalla programmazione")
            return data
        }

        if messagesSendMessageIds.contains(functionId) {
            return prepareRawTextSchedule(data, functionId: functionId, flags: flags) ?? data
        }

        guard let peer: Api.InputPeer = readObject(reader, as: Api.InputPeer.self) else {
            setAutomaticScheduleStatus("RPC riconosciuta, lettura destinatario fallita")
            return data
        }

        if flags & (1 << 0) != 0 {
            guard let _: Api.InputReplyTo = readObject(reader, as: Api.InputReplyTo.self) else {
                return data
            }
        }

        var delay: Int64 = 15
        var startedAt: TimeInterval?
        var usedFileIds: [Int64] = []

        if messagesSendMediaIds.contains(functionId) {
            guard let media: Api.InputMedia = readObject(reader, as: Api.InputMedia.self),
                  parseString(reader) != nil,
                  reader.readInt64() != nil else {
                return data
            }
            let info = mediaInfo(media)
            delay = automaticDelay(kind: info.kind, size: info.size)
            startedAt = info.startedAt
            usedFileIds = info.fileIds

            if flags & (1 << 2) != 0 {
                guard let _: Api.ReplyMarkup = readObject(reader, as: Api.ReplyMarkup.self) else {
                    return data
                }
            }
            if flags & (1 << 3) != 0 && !skipEntities(reader) { return data }
        } else {
            guard reader.readInt32() == vectorConstructor,
                  let count = reader.readInt32(), count > 0, count <= 100 else {
                return data
            }

            var items: [Api.InputSingleMedia] = []
            for _ in 0..<count {
                guard let item: Api.InputSingleMedia = readObject(reader, as: Api.InputSingleMedia.self) else {
                    return data
                }
                items.append(item)
            }

            let info = combinedMediaInfo(items)
            delay = automaticDelay(kind: info.kind, size: info.size)
            startedAt = info.startedAt
            usedFileIds = info.fileIds
        }

        let date = scheduledDate(peer: peer, delay: delay, startedAt: startedAt)
        guard let result = patchedPayload(data,
                                          flags: flags,
                                          insertionOffset: reader.offset,
                                          scheduleDate: date) else {
            return data
        }

        setAutomaticScheduleStatus("Media programmato: ritardo \(delay)s, data \(date)")

        if !usedFileIds.isEmpty {
            automaticScheduleQueue.sync {
                usedFileIds.forEach { _ = outgoingUploads.removeValue(forKey: $0) }
            }
        }
        return result
    }
}
