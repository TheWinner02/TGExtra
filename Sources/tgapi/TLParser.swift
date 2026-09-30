import Foundation

@objc(TLParser)
class TLParser: NSObject {
	private static let deletedIdsQueue = DispatchQueue(label: "com.tgextra.deletedIds",
	                                                    attributes: .concurrent)
	private static var deletedIds = Set<Int32>(
		(UserDefaults.standard.array(forKey: "TGExtraDeletedMessageIds") as? [NSNumber] ?? [])
			.map { $0.int32Value }
	)

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
}
