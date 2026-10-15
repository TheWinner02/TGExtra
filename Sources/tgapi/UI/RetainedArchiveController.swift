import UIKit

private func archiveChatTitle(_ chat: RetainedArchiveChat, strings: [String: String]) -> String {
    RetainedMessageArchive.displayTitle(chat, chatLabel: strings["chat"] ?? "Chat",
        unknownLabel: strings["unknown"] ?? "Unidentified chats")
}

private func archiveMetadata(_ message: RetainedArchiveMessage, strings: [String: String]) -> String {
    var parts = ["ID \(message.id)"]
    if let timestamp = message.timestamp {
        parts.append(DateFormatter.localizedString(from: Date(timeIntervalSince1970: TimeInterval(timestamp)),
            dateStyle: .medium, timeStyle: .short))
    }
    if let topic = message.topic {
        let label = message.topicTitle.flatMap { $0.isEmpty ? nil : $0 } ?? "#\(topic)"
        parts.append("\(strings["topic"] ?? "Topic"): \(label)")
    }
    if message.available && message.kind != "text" { parts.append(strings[message.kind] ?? strings["attachment"] ?? "Attachment") }
    return parts.joined(separator: " · ")
}

@objc(TGExtraRetainedArchiveController)
final class TGExtraRetainedArchiveController: UITableViewController {
    private weak var sourceUI: UIViewController?
    private var strings: [String: String] = [:]
    private var chats: [RetainedArchiveChat] = []
    private var allChats: [RetainedArchiveChat] = []
    private var showRecordsWithoutContent = false
    private var loadError = false
    private var refreshOnReturn = false
    private var request: RetainedArchiveLoad?
    private var loading = false

    @objc(presentFromUI:strings:)
    static func present(from ui: UIViewController, strings: [String: String]) {
        let controller = TGExtraRetainedArchiveController(style: .insetGrouped)
        controller.sourceUI = ui
        controller.strings = strings
        ui.present(UINavigationController(rootViewController: controller), animated: true)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = strings["title"]
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 72
        navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(close))
        navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .refresh, target: self, action: #selector(reloadArchive))
        reloadArchive()
    }

    deinit { request?.cancel() }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        if refreshOnReturn {
            refreshOnReturn = false
            reloadArchive()
        }
    }

    @objc private func close() {
        request?.cancel()
        dismiss(animated: true)
    }

    private func showBackground(_ text: String) {
        let label = UILabel()
        label.text = text
        label.textColor = .secondaryLabel
        label.textAlignment = .center
        label.numberOfLines = 0
        tableView.backgroundView = label
    }

    @objc private func reloadArchive() {
        request?.cancel()
        chats = []
        allChats = []
        loadError = false
        loading = true
        tableView.reloadData()
        showBackground(strings["loading"] ?? "Loading…")
        navigationItem.rightBarButtonItem?.isEnabled = false
        guard let ui = sourceUI else {
            loading = false
            loadError = true
            navigationItem.rightBarButtonItem?.isEnabled = true
            applyFilter()
            return
        }
        request = TGExtraDeletedMessageCleaner.loadArchive(ui) { [weak self] result, error in
            guard let self else { return }
            self.loading = false
            self.navigationItem.rightBarButtonItem?.isEnabled = true
            self.allChats = result ?? []
            self.loadError = error != nil
            self.applyFilter()
        }
    }

    private func applyFilter() {
        chats = RetainedMessageArchive.visibleChats(allChats, showRecordsWithoutContent: showRecordsWithoutContent)
        if loadError { showBackground(strings["account"] ?? "Open a chat and try again.") }
        else if allChats.isEmpty { showBackground(strings["empty"] ?? "No retained messages for this account.") }
        else if chats.isEmpty { showBackground(strings["noReadable"] ?? "No readable messages. Enable the filter to show records without content.") }
        else { tableView.backgroundView = nil }
        tableView.reloadData()
    }

    @objc private func filterChanged(_ sender: UISwitch) {
        showRecordsWithoutContent = sender.isOn
        if !loading { applyFilter() }
    }

    override func numberOfSections(in tableView: UITableView) -> Int { 2 }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        section == 0 ? 1 : chats.count
    }

    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        guard !loading else { return nil }
        if section == 0 {
            let hidden = allChats.reduce(0) { $0 + $1.messages.filter { !$0.available }.count }
            return !showRecordsWithoutContent && hidden > 0
                ? String(format: strings["hidden"] ?? "%ld records hidden; nothing has been deleted.", hidden) : nil
        }
        return strings["note"]
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if indexPath.section == 0 {
            let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
            cell.textLabel?.text = strings["showRecords"] ?? "Show records without content"
            cell.textLabel?.numberOfLines = 0
            cell.selectionStyle = .none
            let toggle = UISwitch()
            toggle.isOn = showRecordsWithoutContent
            toggle.isEnabled = !loading
            toggle.addTarget(self, action: #selector(filterChanged(_:)), for: .valueChanged)
            cell.accessoryView = toggle
            return cell
        }
        let cell = tableView.dequeueReusableCell(withIdentifier: "chat") ?? UITableViewCell(style: .subtitle, reuseIdentifier: "chat")
        let chat = chats[indexPath.row]
        cell.textLabel?.text = archiveChatTitle(chat, strings: strings)
        let missing = chat.messages.filter { !$0.available }.count
        let readable = chat.messages.count - missing
        var counts: [String] = []
        if readable > 0 { counts.append(String(format: strings[readable == 1 ? "countOne" : "count"] ?? "%ld readable messages", readable)) }
        if missing > 0 { counts.append(String(format: strings[missing == 1 ? "missingCountOne" : "missingCount"] ?? "%ld records without content", missing)) }
        cell.detailTextLabel?.text = counts.joined(separator: " · ")
        cell.textLabel?.numberOfLines = 0
        cell.detailTextLabel?.numberOfLines = 0
        cell.accessoryType = .disclosureIndicator
        cell.imageView?.image = UIImage(systemName: "bubble.left.and.text.bubble.right")
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard indexPath.section == 1 else { return }
        let selected = chats[indexPath.row]
        let fullChat = allChats.first { $0.key == selected.key } ?? selected
        let controller = RetainedArchiveMessagesController(chat: fullChat, strings: strings, sourceUI: sourceUI,
            showRecordsWithoutContent: showRecordsWithoutContent) { [weak self] in
                guard let self else { return }
                if self.navigationController?.topViewController === self, self.viewIfLoaded?.window != nil { self.reloadArchive() }
                else { self.refreshOnReturn = true }
            }
        navigationController?.pushViewController(controller, animated: true)
    }
}

private final class RetainedArchiveMessagesController: UITableViewController {
    private var chat: RetainedArchiveChat
    private var fullChat: RetainedArchiveChat
    private let strings: [String: String]
    private weak var sourceUI: UIViewController?
    private let showRecordsWithoutContent: Bool
    private let onChanged: () -> Void
    private var cleaning = false
    private var request: RetainedArchiveLoad?

    init(chat: RetainedArchiveChat, strings: [String: String], sourceUI: UIViewController?,
         showRecordsWithoutContent: Bool, onChanged: @escaping () -> Void) {
        self.fullChat = chat
        self.chat = RetainedMessageArchive.visibleChats([chat], showRecordsWithoutContent: showRecordsWithoutContent).first ??
            RetainedArchiveChat(key: chat.key, title: chat.title, messages: [])
        self.strings = strings
        self.sourceUI = sourceUI
        self.showRecordsWithoutContent = showRecordsWithoutContent
        self.onChanged = onChanged
        super.init(style: .insetGrouped)
        title = archiveChatTitle(chat, strings: strings)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    override func viewDidLoad() {
        super.viewDidLoad()
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 100
        let button = UIBarButtonItem(barButtonSystemItem: .trash, target: self, action: #selector(confirmCleanup))
        button.tintColor = .systemRed
        button.accessibilityLabel = strings["cleanChat"]
        navigationItem.rightBarButtonItem = button
        updateCleanupButton()
    }

    deinit { request?.cancel() }

    private var cleanupScope: RetainedChatCleanupScope? {
        RetainedChatCleanupScope(chatKey: fullChat.key, messageIds: fullChat.messages.map { $0.id })
    }

    private func updateCleanupButton() {
        navigationItem.rightBarButtonItem?.isEnabled = !cleaning && sourceUI != nil && cleanupScope != nil
    }

    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        fullChat.key == "unresolved" ? strings["cleanUnknown"] : nil
    }

    @objc private func confirmCleanup() {
        guard !cleaning, let ui = sourceUI, let scope = cleanupScope else { return }
        let alert = UIAlertController(title: strings["cleanChat"],
            message: String(format: strings["cleanConfirm"] ?? "Remove locally retained messages from %@? Unavailable records will be kept.",
                archiveChatTitle(fullChat, strings: strings)), preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: strings["cancel"] ?? "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: strings["cleanChat"] ?? "Clear retained messages", style: .destructive) { [weak self] _ in
            guard let self else { return }
            self.cleaning = true
            self.updateCleanupButton()
            let notify = self.onChanged
            TGExtraDeletedMessageCleaner.clearChat(ui, scope: scope) { [weak self] removed, remaining, error in
                notify()
                guard let self else { return }
                var result = String(format: self.strings["cleanResult"] ?? "%ld messages removed locally.", removed)
                if remaining > 0 {
                    result += "\n\n" + String(format: self.strings["cleanRemaining"] ?? "%ld records could not be removed and were kept.", remaining)
                } else if error != nil { result = self.strings["cleanFailed"] ?? "Cleanup could not run. Open a chat in this account and try again." }
                self.reloadChat(ui) { [weak self] in
                    guard let self else { return }
                    let message = UIAlertController(title: self.strings["cleanChat"], message: result, preferredStyle: .alert)
                    message.addAction(UIAlertAction(title: self.strings["ok"] ?? "OK", style: .default))
                    if self.viewIfLoaded?.window != nil { self.present(message, animated: true) }
                }
            }
        })
        present(alert, animated: true)
    }

    private func reloadChat(_ ui: UIViewController, completion: @escaping () -> Void) {
        request?.cancel()
        let key = fullChat.key
        request = TGExtraDeletedMessageCleaner.loadArchive(ui) { [weak self] chats, error in
            guard let self else { return }
            self.cleaning = false
            self.fullChat = chats?.first { $0.key == key } ?? RetainedArchiveChat(key: key, title: self.fullChat.title, messages: [])
            self.chat = RetainedMessageArchive.visibleChats([self.fullChat], showRecordsWithoutContent: self.showRecordsWithoutContent).first ??
                RetainedArchiveChat(key: key, title: self.fullChat.title, messages: [])
            self.updateCleanupButton()
            if error != nil || self.chat.messages.isEmpty {
                let label = UILabel()
                label.numberOfLines = 0
                label.textAlignment = .center
                label.textColor = .secondaryLabel
                label.text = error != nil ? self.strings["account"] : self.strings["cleanEmpty"]
                self.tableView.backgroundView = label
            } else { self.tableView.backgroundView = nil }
            self.tableView.reloadData()
            completion()
        }
    }
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { chat.messages.count }
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "message") ?? UITableViewCell(style: .subtitle, reuseIdentifier: "message")
        let message = chat.messages[indexPath.row]
        cell.textLabel?.text = !message.available ? (strings["registryOnly"] ?? "Record only") :
            (message.text.isEmpty ? (strings[message.kind] ?? strings["attachment"]) : message.text)
        cell.textLabel?.numberOfLines = 4
        cell.detailTextLabel?.text = archiveMetadata(message, strings: strings)
        cell.detailTextLabel?.numberOfLines = 0
        cell.accessoryType = .disclosureIndicator
        return cell
    }
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let message = chat.messages[indexPath.row]
        let controller = UIViewController()
        controller.title = "ID \(message.id)"
        controller.view.backgroundColor = .systemBackground
        let textView = UITextView()
        textView.isEditable = false
        textView.font = .preferredFont(forTextStyle: .body)
        textView.textColor = .label
        textView.backgroundColor = .systemBackground
        let body = !message.available ? (strings["unavailable"] ?? "Unavailable") :
            (message.text.isEmpty ? (strings[message.kind] ?? strings["attachment"] ?? "Message") : message.text)
        textView.text = archiveMetadata(message, strings: strings) + "\n\n" + body
        textView.translatesAutoresizingMaskIntoConstraints = false
        controller.view.addSubview(textView)
        NSLayoutConstraint.activate([
            textView.topAnchor.constraint(equalTo: controller.view.safeAreaLayoutGuide.topAnchor),
            textView.bottomAnchor.constraint(equalTo: controller.view.safeAreaLayoutGuide.bottomAnchor),
            textView.leadingAnchor.constraint(equalTo: controller.view.leadingAnchor, constant: 12),
            textView.trailingAnchor.constraint(equalTo: controller.view.trailingAnchor, constant: -12)
        ])
        navigationController?.pushViewController(controller, animated: true)
    }
}
