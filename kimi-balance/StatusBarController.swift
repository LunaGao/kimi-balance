import AppKit
import Combine

@MainActor
final class StatusBarController: NSObject {
    private let model: SubscriptionModel
    private let openMainWindowAction: () -> Void
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private var cancellable: AnyCancellable?
    private var totalUsageItem: NSMenuItem!
    private var totalResetItem: NSMenuItem!
    private var fiveHourUsageItem: NSMenuItem!
    private var fiveHourResetItem: NSMenuItem!

    init(model: SubscriptionModel, openMainWindow: @escaping () -> Void) {
        self.model = model
        openMainWindowAction = openMainWindow
        super.init()
        setupStatusItem()
        setupMenu()
        updateContent()
        cancellable = model.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.updateContent()
            }
    }

    private func setupStatusItem() {
        guard let button = statusItem.button else { return }
        button.image = NSImage(
            systemSymbolName: "chart.bar.fill",
            accessibilityDescription: "Kimi 订阅用量"
        )
        button.image?.isTemplate = true
        button.imagePosition = .imageLeading
        button.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        button.toolTip = "Kimi 订阅用量"
    }

    private func setupMenu() {
        let menu = NSMenu()
        totalUsageItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        totalResetItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        fiveHourUsageItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        fiveHourResetItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        menu.addItem(totalUsageItem)
        menu.addItem(totalResetItem)
        menu.addItem(fiveHourUsageItem)
        menu.addItem(fiveHourResetItem)

        let refreshItem = NSMenuItem(title: "立即刷新", action: #selector(refresh), keyEquivalent: "r")
        refreshItem.target = self
        menu.addItem(refreshItem)
        menu.addItem(.separator())

        let mainWindowItem = NSMenuItem(title: "显示主窗口", action: #selector(openMainWindow), keyEquivalent: "o")
        mainWindowItem.target = self
        menu.addItem(mainWindowItem)
        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "退出 kimi-balance", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        statusItem.menu = menu
    }

    private func updateContent() {
        statusItem.button?.title = "总 \(model.totalUsage)   5小时 \(model.fiveHourUsage)"
        totalUsageItem.title = "总使用量：\(model.totalUsage)"
        totalResetItem.title = "总使用量重置时间：\(model.totalResetTime)"
        fiveHourUsageItem.title = "5小时用量：\(model.fiveHourUsage)"
        fiveHourResetItem.title = "5小时用量重置时间：\(model.fiveHourResetTime)"
    }

    @objc private func refresh() {
        model.refresh()
    }

    @objc private func openMainWindow() {
        openMainWindowAction()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
