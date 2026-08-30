import AppKit
import Foundation
import Security

extension Notification.Name {
    static let openDeepSeekAccount = Notification.Name("WhaleGirlOpenDeepSeekAccount")
    static let deepSeekBalanceUpdated = Notification.Name("WhaleGirlDeepSeekBalanceUpdated")
    static let deepSeekLoggedOut = Notification.Name("WhaleGirlDeepSeekLoggedOut")
}

private struct BalanceResponse: Decodable {
    struct Info: Decodable {
        let currency: String
        let total_balance: String
    }
    let balance_infos: [Info]
}

private enum AccountError: LocalizedError {
    case invalidKey
    case invalidResponse
    case server(Int)
    case keychain(OSStatus)

    var errorDescription: String? {
        switch self {
        case .invalidKey: return "请输入有效的 DeepSeek API Key"
        case .invalidResponse: return "DeepSeek 返回了无法识别的数据"
        case .server(401): return "API Key 无效，请重新检查"
        case .server(402): return "账号余额不足"
        case .server(let code): return "连接失败（HTTP \(code)）"
        case .keychain(let status): return "无法写入 macOS 钥匙串（\(status)）"
        }
    }
}

final class DeepSeekAccount {
    static let shared = DeepSeekAccount()

    private let service = "local.dsh.whalegirl.desktop"
    private let account = "DeepSeekAPIKey"

    var hasKey: Bool { loadKey() != nil }

    func loadKey() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func saveKey(_ key: String) throws {
        let data = Data(key.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var add = query
            add[kSecValueData as String] = data
            let addStatus = SecItemAdd(add as CFDictionary, nil)
            guard addStatus == errSecSuccess else { throw AccountError.keychain(addStatus) }
        } else if status != errSecSuccess {
            throw AccountError.keychain(status)
        }
    }

    func removeKey() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
        NotificationCenter.default.post(name: .deepSeekLoggedOut, object: nil)
    }

    func verify(_ rawKey: String, completion: @escaping (Result<(Double, String), Error>) -> Void) {
        let key = rawKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else {
            completion(.failure(AccountError.invalidKey))
            return
        }

        var request = URLRequest(url: URL(string: "https://api.deepseek.com/user/balance")!)
        request.httpMethod = "GET"
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15

        URLSession.shared.dataTask(with: request) { data, response, error in
            let result: Result<(Double, String), Error>
            if let error {
                result = .failure(error)
            } else if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                result = .failure(AccountError.server(http.statusCode))
            } else if let data,
                      let decoded = try? JSONDecoder().decode(BalanceResponse.self, from: data),
                      let info = decoded.balance_infos.first(where: { $0.currency == "CNY" }) ?? decoded.balance_infos.first,
                      let balance = Double(info.total_balance) {
                result = .success((balance, info.currency))
            } else {
                result = .failure(AccountError.invalidResponse)
            }
            DispatchQueue.main.async { completion(result) }
        }.resume()
    }

    func refreshBalance() {
        guard let key = loadKey() else { return }
        verify(key) { result in
            guard case let .success((balance, currency)) = result else { return }
            NotificationCenter.default.post(
                name: .deepSeekBalanceUpdated,
                object: nil,
                userInfo: ["balance": balance, "currency": currency]
            )
        }
    }
}

final class AccountWindowController: NSWindowController, NSWindowDelegate {
    private let headingLabel = NSTextField(labelWithString: "")
    private let noteLabel = NSTextField(wrappingLabelWithString: "")
    private let keyField = NSSecureTextField(frame: NSRect(x: 28, y: 120, width: 286, height: 28))
    private let statusLabel = NSTextField(labelWithString: "")
    private let connectButton = NSButton(title: "验证并保存", target: nil, action: nil)
    private let logoutButton = NSButton(title: "断开连接", target: nil, action: nil)
    private let replaceButton = NSButton(title: "替换 Key", target: nil, action: nil)
    private let pasteButton = NSButton(title: "粘贴", target: nil, action: nil)
    private let apiKeyButton = NSButton(title: "获取 API Key", target: nil, action: nil)
    private let spinner = NSProgressIndicator(frame: NSRect(x: 28, y: 73, width: 18, height: 18))

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 260),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "连接 DeepSeek"
        window.isReleasedWhenClosed = false
        window.center()
        super.init(window: window)
        window.delegate = self

        guard let view = window.contentView else { return }
        headingLabel.font = .systemFont(ofSize: 20, weight: .bold)
        headingLabel.frame = NSRect(x: 28, y: 205, width: 364, height: 28)
        view.addSubview(headingLabel)

        noteLabel.textColor = .secondaryLabelColor
        noteLabel.font = .systemFont(ofSize: 12.5)
        noteLabel.frame = NSRect(x: 28, y: 158, width: 364, height: 42)
        view.addSubview(noteLabel)

        keyField.placeholderString = DeepSeekAccount.shared.hasKey ? "已保存；输入新 Key 可替换" : "sk-..."
        keyField.target = self
        keyField.action = #selector(connect)
        view.addSubview(keyField)

        pasteButton.target = self
        pasteButton.action = #selector(pasteKey)
        pasteButton.bezelStyle = .rounded
        pasteButton.frame = NSRect(x: 320, y: 118, width: 72, height: 32)
        view.addSubview(pasteButton)

        spinner.style = .spinning
        spinner.isDisplayedWhenStopped = false
        view.addSubview(spinner)

        statusLabel.font = .systemFont(ofSize: 12.5)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.frame = NSRect(x: 52, y: 72, width: 340, height: 20)
        view.addSubview(statusLabel)

        apiKeyButton.target = self
        apiKeyButton.action = #selector(openAPIKeys)
        apiKeyButton.bezelStyle = .inline
        apiKeyButton.frame = NSRect(x: 24, y: 25, width: 104, height: 32)
        view.addSubview(apiKeyButton)

        logoutButton.target = self
        logoutButton.action = #selector(logout)
        logoutButton.frame = NSRect(x: 205, y: 25, width: 94, height: 32)
        view.addSubview(logoutButton)

        replaceButton.target = self
        replaceButton.action = #selector(beginReplacingKey)
        replaceButton.bezelStyle = .rounded
        replaceButton.frame = NSRect(x: 298, y: 25, width: 104, height: 32)
        view.addSubview(replaceButton)

        connectButton.target = self
        connectButton.action = #selector(connect)
        connectButton.keyEquivalent = "\r"
        connectButton.bezelStyle = .rounded
        connectButton.frame = NSRect(x: 298, y: 25, width: 104, height: 32)
        view.addSubview(connectButton)
        refreshStatus()
    }

    required init?(coder: NSCoder) { nil }

    func show() {
        refreshStatus()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func refreshStatus() {
        let connected = DeepSeekAccount.shared.hasKey
        if connected {
            showConnectedState()
        } else {
            showKeyEditor(replacing: false)
        }
    }

    private func showConnectedState() {
        headingLabel.stringValue = "DeepSeek 已连接"
        noteLabel.stringValue = "API Key 已安全保存在 macOS 钥匙串。桌宠会在后台自动刷新账户余额。"
        keyField.isHidden = true
        pasteButton.isHidden = true
        connectButton.isHidden = true
        apiKeyButton.isHidden = true
        replaceButton.isHidden = false
        logoutButton.isHidden = false
        logoutButton.isEnabled = true
        statusLabel.stringValue = "连接正常"
        statusLabel.textColor = .systemGreen
    }

    private func showKeyEditor(replacing: Bool) {
        headingLabel.stringValue = replacing ? "替换 DeepSeek API Key" : "使用 DeepSeek API Key 登录"
        noteLabel.stringValue = "API Key 仅保存在本机 macOS 钥匙串，用于验证账号和读取余额，不会写入项目文件。"
        keyField.stringValue = ""
        keyField.placeholderString = replacing ? "粘贴新的 API Key" : "sk-..."
        keyField.isHidden = false
        pasteButton.isHidden = false
        connectButton.isHidden = false
        apiKeyButton.isHidden = false
        replaceButton.isHidden = true
        logoutButton.isHidden = !replacing
        logoutButton.isEnabled = replacing
        statusLabel.stringValue = replacing ? "原 Key 会保留到新 Key 验证成功" : "尚未连接"
        statusLabel.textColor = .secondaryLabelColor
        window?.makeFirstResponder(keyField)
    }

    private func setBusy(_ busy: Bool) {
        keyField.isEnabled = !busy
        connectButton.isEnabled = !busy
        logoutButton.isEnabled = !busy && DeepSeekAccount.shared.hasKey
        busy ? spinner.startAnimation(nil) : spinner.stopAnimation(nil)
    }

    @objc private func connect() {
        let typed = keyField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = typed.isEmpty ? (DeepSeekAccount.shared.loadKey() ?? "") : typed
        setBusy(true)
        statusLabel.stringValue = "正在验证…"
        statusLabel.textColor = .secondaryLabelColor
        DeepSeekAccount.shared.verify(key) { [weak self] result in
            guard let self else { return }
            self.setBusy(false)
            switch result {
            case let .success((balance, currency)):
                do {
                    try DeepSeekAccount.shared.saveKey(key)
                    self.keyField.stringValue = ""
                    self.keyField.placeholderString = "已保存；输入新 Key 可替换"
                    self.statusLabel.stringValue = String(format: "连接成功 · %@ %.2f", currency, balance)
                    self.statusLabel.textColor = .systemGreen
                    NotificationCenter.default.post(
                        name: .deepSeekBalanceUpdated,
                        object: nil,
                        userInfo: ["balance": balance, "currency": currency]
                    )
                    self.window?.close()
                } catch {
                    self.statusLabel.stringValue = error.localizedDescription
                    self.statusLabel.textColor = .systemRed
                }
            case let .failure(error):
                self.statusLabel.stringValue = error.localizedDescription
                self.statusLabel.textColor = .systemRed
            }
            self.logoutButton.isEnabled = DeepSeekAccount.shared.hasKey
        }
    }

    @objc private func beginReplacingKey() {
        showKeyEditor(replacing: true)
    }

    @objc private func logout() {
        DeepSeekAccount.shared.removeKey()
        keyField.stringValue = ""
        keyField.placeholderString = "sk-..."
        refreshStatus()
    }

    @objc private func pasteKey() {
        guard let value = NSPasteboard.general.string(forType: .string) else {
            statusLabel.stringValue = "剪贴板中没有可粘贴的文字"
            statusLabel.textColor = .systemOrange
            return
        }
        keyField.stringValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        statusLabel.stringValue = "已从剪贴板粘贴，请验证并保存"
        statusLabel.textColor = .secondaryLabelColor
        window?.makeFirstResponder(keyField)
    }

    @objc private func openAPIKeys() {
        NSWorkspace.shared.open(URL(string: "https://platform.deepseek.com/api_keys")!)
    }
}
