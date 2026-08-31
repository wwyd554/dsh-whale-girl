import AppKit
import Foundation
import QuartzCore

private struct PetSnapshot: Decodable {
    var balance: Double?
    var currency: String?
    var todayUsage: Double?
    var contextPct: Double?
    var contextTokens: Int?
    var contextLimit: Int?
    var peakLow: String?
    var subagentRunning: Int?
    var workState: String?
    var model: String?
    var updatedAt: String?
}

private enum VisualState: String {
    case idle, closed
}

private enum DeepSeekPricing {
    // DeepSeek V4 官方价格，USD / 1M tokens，2026-08-17 起生效。
    static func isPeak(_ date: Date = Date()) -> Bool {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        let weekday = calendar.component(.weekday, from: date)
        if weekday == 1 || weekday == 7 { return false }
        let hour = calendar.component(.hour, from: date)
        return (hour >= 9 && hour < 12) || (hour >= 14 && hour < 18)
    }

}

private final class BubbleView: NSView {
    private let titleLabel = NSTextField(labelWithString: "")
    private let valueLabel = NSTextField(wrappingLabelWithString: "")
    private let detailLabel = NSTextField(labelWithString: "")
    private let outline = NSColor(calibratedRed: 0.23, green: 0.39, blue: 0.78, alpha: 1)

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = 0.18
        layer?.shadowRadius = 9
        layer?.shadowOffset = CGSize(width: 0, height: -3)

        titleLabel.font = .systemFont(ofSize: 16, weight: .semibold)
        titleLabel.textColor = outline
        titleLabel.alignment = .center
        titleLabel.frame = NSRect(x: 18, y: 79, width: frameRect.width - 36, height: 22)
        addSubview(titleLabel)

        valueLabel.font = .systemFont(ofSize: 30, weight: .bold)
        valueLabel.textColor = outline
        valueLabel.alignment = .center
        valueLabel.maximumNumberOfLines = 2
        valueLabel.lineBreakMode = .byWordWrapping
        valueLabel.frame = NSRect(x: 16, y: 44, width: frameRect.width - 32, height: 38)
        addSubview(valueLabel)

        detailLabel.font = .systemFont(ofSize: 12.5, weight: .regular)
        detailLabel.textColor = NSColor(calibratedWhite: 0.42, alpha: 1)
        detailLabel.alignment = .center
        detailLabel.lineBreakMode = .byTruncatingTail
        detailLabel.frame = NSRect(x: 18, y: 24, width: frameRect.width - 36, height: 18)
        addSubview(detailLabel)
    }

    required init?(coder: NSCoder) { nil }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let body = NSBezierPath(roundedRect: NSRect(x: 3, y: 14, width: bounds.width - 6, height: bounds.height - 17), xRadius: 38, yRadius: 38)
        let tail = NSBezierPath()
        tail.move(to: NSPoint(x: bounds.width * 0.44, y: 14))
        tail.line(to: NSPoint(x: bounds.width * 0.52, y: 2))
        tail.line(to: NSPoint(x: bounds.width * 0.60, y: 14))
        tail.close()

        NSColor.white.withAlphaComponent(0.98).setFill()
        outline.setStroke()
        body.lineWidth = 3.5
        body.fill()
        body.stroke()

        // 尾巴覆盖气泡底边，只描两侧，不绘制顶部闭合线。
        NSColor.white.withAlphaComponent(0.98).setStroke()
        let opening = NSBezierPath()
        opening.move(to: NSPoint(x: bounds.width * 0.44, y: 14))
        opening.line(to: NSPoint(x: bounds.width * 0.60, y: 14))
        opening.lineWidth = 4.5
        opening.stroke()

        tail.fill()
        outline.setStroke()
        let tailSides = NSBezierPath()
        tailSides.move(to: NSPoint(x: bounds.width * 0.44, y: 14))
        tailSides.line(to: NSPoint(x: bounds.width * 0.52, y: 2))
        tailSides.line(to: NSPoint(x: bounds.width * 0.60, y: 14))
        tailSides.lineWidth = 3.5
        tailSides.stroke()
    }

    func update(title: String, value: String, detail: String, valueColor: NSColor? = nil) {
        titleLabel.isHidden = false
        valueLabel.font = .systemFont(ofSize: 30, weight: .bold)
        valueLabel.textColor = valueColor ?? outline
        valueLabel.maximumNumberOfLines = 1
        valueLabel.lineBreakMode = .byTruncatingTail
        titleLabel.stringValue = title
        valueLabel.stringValue = value
        detailLabel.stringValue = detail
        detailLabel.isHidden = detail.isEmpty
        if detail.isEmpty {
            titleLabel.frame.origin.y = 75
            valueLabel.frame = NSRect(x: 16, y: 31, width: bounds.width - 32, height: 44)
        } else {
            titleLabel.frame.origin.y = 81
            valueLabel.frame = NSRect(x: 16, y: 45, width: bounds.width - 32, height: 34)
        }
    }

    func updateMessage(_ message: String) {
        titleLabel.isHidden = true
        detailLabel.isHidden = true
        valueLabel.font = .systemFont(ofSize: 19, weight: .semibold)
        valueLabel.textColor = outline
        valueLabel.maximumNumberOfLines = 2
        valueLabel.lineBreakMode = .byWordWrapping
        valueLabel.stringValue = message
        valueLabel.frame = NSRect(x: 25, y: 32, width: bounds.width - 50, height: 60)
    }
}

private final class PetView: NSView {
    private let imageView = NSImageView(frame: NSRect(x: 54, y: 0, width: 192, height: 192))
    private let bubbleView = BubbleView(frame: NSRect(x: 5, y: 188, width: 290, height: 112))
    private var snapshot: PetSnapshot?
    private var cardIndex = -1
    private var dragStart: NSPoint?
    private var windowStart: NSPoint?
    private var didDrag = false
    private var pollTimer: Timer?
    private var accountTimer: Timer?
    private var interactionReset: Timer?
    private var bubbleHideTimer: Timer?
    private var accountBalance: Double?
    private var accountCurrency: String?
    private var currentSnark = ""

    private let snarks = [
        "不知道用户有什么用，先赶走吧～",
        "你点得这么勤，是怕我睡着吗？",
        "余额还在，焦虑已经先到账了。",
        "别催啦，鱼鳍都快敲出火星了。",
        "再点一下，也不会凭空长出 Token 哦。",
        "模型在认真思考，我在认真摸鱼。",
        "今天也在努力把 Token 吃成小鱼干。",
        "看什么看，我只是长得比较像插件。",
        "这个需求不难，难的是假装很难。",
        "先说好，摸一下也是要消耗 Token 的。",
        "工作可以稍后，摸鱼必须准时。",
        "你负责提需求，我负责露出智慧的眼神。"
    ]

    private let stateURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".dsh/.whale-girl-state.json")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        imageView.wantsLayer = true
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.animates = true
        addSubview(imageView)
        bubbleView.isHidden = true
        addSubview(bubbleView)
        updateImage(.idle)
        NotificationCenter.default.addObserver(self, selector: #selector(accountBalanceUpdated(_:)), name: .deepSeekBalanceUpdated, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(accountLoggedOut), name: .deepSeekLoggedOut, object: nil)
        loadSnapshot()
        DeepSeekAccount.shared.refreshBalance()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            self?.loadSnapshot()
        }
        accountTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { _ in
            DeepSeekAccount.shared.refreshBalance()
        }
    }

    required init?(coder: NSCoder) { nil }

    deinit {
        pollTimer?.invalidate()
        accountTimer?.invalidate()
        interactionReset?.invalidate()
        bubbleHideTimer?.invalidate()
        NotificationCenter.default.removeObserver(self)
    }

    private func assetName(for state: VisualState) -> String {
        switch state {
        case .idle: return "whale-girl"
        case .closed: return "whale-girl-closed"
        }
    }

    private func updateImage(_ state: VisualState) {
        guard let url = Bundle.main.url(forResource: assetName(for: state), withExtension: "png") else { return }
        imageView.image = NSImage(contentsOf: url)
    }

    private func loadSnapshot() {
        guard let data = try? Data(contentsOf: stateURL),
              let decoded = try? JSONDecoder().decode(PetSnapshot.self, from: data) else { return }
        snapshot = decoded
        if cardIndex >= 0 { updateCard() }
    }

    private func currencyText(_ value: Double?, currency: String?) -> String {
        guard let value else { return "暂无数据" }
        let code = currency ?? "CNY"
        let symbol = code == "CNY" ? "¥" : code == "USD" ? "$" : "\(code) "
        return String(format: "%@%.2f", symbol, value)
    }

    private func updateCard() {
        switch cardIndex {
        case 0:
            let peak = DeepSeekPricing.isPeak()
            let model = snapshot?.model ?? "deepseek-v4-flash"
            let modelName = model.lowercased().contains("pro") ? "V4 Pro" : "V4 Flash"
            bubbleView.update(
                title: "DeepSeek \(modelName) 计价",
                value: peak ? "高峰时期" : "低谷时期",
                detail: "",
                valueColor: peak ? .systemRed : .systemGreen
            )
        case 1:
            bubbleView.update(
                title: "DeepSeek 余额",
                value: currencyText(accountBalance ?? snapshot?.balance, currency: accountCurrency ?? snapshot?.currency),
                detail: "今日已用 \(currencyText(snapshot?.todayUsage, currency: accountCurrency ?? snapshot?.currency))"
            )
        default:
            bubbleView.updateMessage(currentSnark)
        }
    }

    private func pickSnark() {
        let choices = snarks.filter { $0 != currentSnark }
        currentSnark = choices.randomElement() ?? snarks[0]
    }

    private func playDuang() {
        updateImage(.closed)
        imageView.layer?.removeAnimation(forKey: "duang")

        let animation = CAKeyframeAnimation(keyPath: "transform")
        animation.values = [
            CATransform3DMakeScale(1.00, 1.00, 1),
            CATransform3DMakeScale(1.10, 0.88, 1),
            CATransform3DMakeScale(0.95, 1.07, 1),
            CATransform3DMakeScale(1.04, 0.97, 1),
            CATransform3DMakeScale(0.99, 1.02, 1),
            CATransform3DMakeScale(1.00, 1.00, 1)
        ]
        animation.keyTimes = [0, 0.18, 0.38, 0.58, 0.78, 1]
        animation.duration = 0.38
        animation.timingFunctions = Array(repeating: CAMediaTimingFunction(name: .easeInEaseOut), count: 5)
        imageView.layer?.add(animation, forKey: "duang")

        interactionReset?.invalidate()
        interactionReset = Timer.scheduledTimer(withTimeInterval: 0.41, repeats: false) { [weak self] _ in
            self?.updateImage(.idle)
        }
    }

    private func cycleCard() {
        cardIndex = (cardIndex + 1) % 3
        if cardIndex == 2 { pickSnark() }
        bubbleView.isHidden = false
        updateCard()
        playDuang()
        scheduleBubbleHide()
    }

    private func scheduleBubbleHide() {
        bubbleHideTimer?.invalidate()
        bubbleHideTimer = Timer.scheduledTimer(withTimeInterval: 4, repeats: false) { [weak self] _ in
            self?.bubbleView.isHidden = true
        }
    }

    override func mouseDown(with event: NSEvent) {
        dragStart = NSEvent.mouseLocation
        windowStart = window?.frame.origin
        didDrag = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard let dragStart, let windowStart, let window else { return }
        let now = NSEvent.mouseLocation
        let dx = now.x - dragStart.x
        let dy = now.y - dragStart.y
        if hypot(dx, dy) > 4 { didDrag = true }
        let targetScreen = NSScreen.screens.first(where: { NSMouseInRect(now, $0.frame, false) }) ?? window.screen ?? NSScreen.main
        let visible = targetScreen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
        // The panel is deliberately larger than the fish so the speech bubble has
        // somewhere to draw. Clamp the visible fish, not that transparent canvas,
        // otherwise the unused margins feel like an invisible wall at the screen edge.
        let petFrame = imageView.frame
        let minX = visible.minX - petFrame.minX
        let minY = visible.minY - petFrame.minY
        let maxX = visible.maxX - petFrame.maxX
        let maxY = visible.maxY - petFrame.maxY
        let origin = NSPoint(
            x: min(max(windowStart.x + dx, minX), maxX),
            y: min(max(windowStart.y + dy, minY), maxY)
        )
        window.setFrameOrigin(origin)
    }

    override func mouseUp(with event: NSEvent) {
        if !didDrag { cycleCard() }
        dragStart = nil
        windowStart = nil
    }

    override func rightMouseDown(with event: NSEvent) {
        let menu = NSMenu()
        menu.addItem(withTitle: DeepSeekAccount.shared.hasKey ? "DeepSeek 账号设置…" : "连接 DeepSeek…", action: #selector(openAccount), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: bubbleView.isHidden ? "显示信息卡" : "隐藏信息卡", action: #selector(toggleBubble), keyEquivalent: "")
        menu.addItem(withTitle: "立即刷新", action: #selector(refreshNow), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "退出大肥鱼", action: #selector(quitApp), keyEquivalent: "q")
        for item in menu.items { item.target = self }
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    @objc private func toggleBubble() {
        if bubbleView.isHidden {
            if cardIndex < 0 { cardIndex = 0 }
            updateCard()
            scheduleBubbleHide()
        } else {
            bubbleHideTimer?.invalidate()
        }
        bubbleView.isHidden.toggle()
    }

    @objc private func refreshNow() {
        loadSnapshot()
        DeepSeekAccount.shared.refreshBalance()
    }
    @objc private func openAccount() {
        NotificationCenter.default.post(name: .openDeepSeekAccount, object: nil)
    }
    @objc private func accountBalanceUpdated(_ note: Notification) {
        accountBalance = note.userInfo?["balance"] as? Double
        accountCurrency = note.userInfo?["currency"] as? String
        if cardIndex == 1 { updateCard() }
    }
    @objc private func accountLoggedOut() {
        accountBalance = nil
        accountCurrency = nil
        if cardIndex == 1 { updateCard() }
    }
    @objc private func quitApp() { NSApp.terminate(nil) }
}

private final class AppDelegate: NSObject, NSApplicationDelegate {
    private var panel: NSPanel?
    private let accountWindow = AccountWindowController()
    private let markerURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".dsh/.whale-girl-desktop-active")

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        NotificationCenter.default.addObserver(self, selector: #selector(openAccountWindow), name: .openDeepSeekAccount, object: nil)
        try? FileManager.default.createDirectory(at: markerURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: markerURL.path, contents: Data())

        let size = NSSize(width: 300, height: 304)
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1200, height: 800)
        let origin = NSPoint(x: screen.maxX - size.width - 24, y: screen.minY + 32)
        let panel = NSPanel(
            contentRect: NSRect(origin: origin, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = PetView(frame: NSRect(origin: .zero, size: size))
        panel.orderFrontRegardless()
        self.panel = panel

        if !DeepSeekAccount.shared.hasKey {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                self?.accountWindow.show()
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        try? FileManager.default.removeItem(at: markerURL)
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func openAccountWindow() { accountWindow.show() }
}

private let app = NSApplication.shared
private let delegate = AppDelegate()
app.delegate = delegate
app.run()
