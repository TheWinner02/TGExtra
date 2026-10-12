import Foundation

// Rebuilt only when retained records change, never for each cell layout.
struct RetainedMessageIndex {
    private struct Entry {
        let record: [String: Any]
        let event: [String: Any]
    }
    private var accounts: [String: [Int32: [Entry]]] = [:]

    init(records: [[String: Any]]) {
        for record in records {
            guard let account = record["account"] as? String,
                  let id = (record["id"] as? NSNumber)?.int32Value else { continue }
            var event = record
            event.removeValue(forKey: "peer")
            event.removeValue(forKey: "namespace")
            accounts[account, default: [:]][id, default: []].append(Entry(record: record, event: event))
        }
    }

    func contains(_ id: RetainedMessageIdentity, account: String) -> Bool {
        accounts[account]?[id.id]?.contains { id.matches(record: $0.record) } ?? false
    }

    func hasRecords(account: String) -> Bool { accounts[account] != nil }

    // Original account/channel events also let cleanup repair stale metadata.
    func shouldObserve(_ id: RetainedMessageIdentity, account: String) -> Bool {
        accounts[account]?[id.id]?.contains { id.matches(record: $0.event) } ?? false
    }
}
