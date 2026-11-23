import AppKit
import Combine
import Sparkle
import SwiftUI

@MainActor
final class StatusBarController: NSObject {
    private let model: SubscriptionModel
    private let updaterController: SPUStandardUpdaterController
    private let openMainWindowAction: () -> Void
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private var cancellable: AnyCancellable?
    private var totalUsageItem: NSMenuItem!
    private var totalResetItem: NSMenuItem!
    private var fiveHourUsageItem: NSMenuItem!
    private var fiveHourResetItem: NSMenuItem!
    private var avatarLoadTask: Task<Void, Never>?
    private var loadedAvatarURL: URL?
    private var settingsWindow: NSWindow?

    init(
        model: SubscriptionModel,
        updaterController: SPUStandardUpdaterController,
        openMainWindow: @escaping () -> Void
    ) {
        self.model = model
        self.updaterController = updaterController
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

        let settingsItem = NSMenuItem(title: "设置…", action: #selector(showSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        let updateItem = NSMenuItem(
            title: "检查更新…",
            action: #selector(SPUStandardUpdaterController.checkForUpdates(_:)),
            keyEquivalent: ""
        )
        updateItem.target = updaterController
        menu.addItem(updateItem)
        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "退出 Kimi Balance", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        statusItem.menu = menu
    }

    private func updateContent() {
        if model.isLoginRequired {
            avatarLoadTask?.cancel()
            loadedAvatarURL = nil
            statusItem.button?.image = nil
            statusItem.button?.title = "请完成登录"
        } else {
            statusItem.button?.title = " 总\(model.totalUsage) 5小时\(model.fiveHourUsage)"
            if loadedAvatarURL != model.avatarURL {
                loadedAvatarURL = model.avatarURL
                loadAvatar()
            }
        }
        totalUsageItem.title = "总使用量：\(model.totalUsage)"
        totalResetItem.title = "总使用量重置时间：\(model.totalResetTime)"
        fiveHourUsageItem.title = "5小时用量：\(model.fiveHourUsage)"
        fiveHourResetItem.title = "5小时用量重置时间：\(model.fiveHourResetTime)"
    }

    private func loadAvatar() {
        avatarLoadTask?.cancel()
        statusItem.button?.image = NSImage(
            systemSymbolName: "person.circle.fill",
            accessibilityDescription: "用户头像"
        )
        guard let url = model.avatarURL else { return }

        avatarLoadTask = Task { [weak self] in
            guard let (data, _) = try? await URLSession.shared.data(from: url),
                  !Task.isCancelled,
                  let image = NSImage(data: data) else { return }
            self?.applyAvatar(image, for: url)
        }
    }

    private func applyAvatar(_ image: NSImage, for url: URL) {
        guard !model.isLoginRequired, model.avatarURL == url else { return }
        statusItem.button?.image = circularAvatar(from: image)
    }

    private func circularAvatar(from source: NSImage) -> NSImage {
        let size = NSSize(width: 18, height: 18)
        guard source.size.width > 0, source.size.height > 0 else { return source }

        let image = NSImage(size: size)
        image.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        NSBezierPath(ovalIn: NSRect(origin: .zero, size: size)).addClip()
        let scale = max(size.width / source.size.width, size.height / source.size.height)
        let drawSize = NSSize(width: source.size.width * scale, height: source.size.height * scale)
        let drawRect = NSRect(
            x: (size.width - drawSize.width) / 2,
            y: (size.height - drawSize.height) / 2,
            width: drawSize.width,
            height: drawSize.height
        )
        source.draw(in: drawRect, from: .zero, operation: .sourceOver, fraction: 1)
        image.unlockFocus()
        image.isTemplate = false
        return image
    }

    @objc private func refresh() {
        model.refresh()
    }

    @objc private func openMainWindow() {
        openMainWindowAction()
    }

    @objc private func showSettings() {
        if let settingsWindow {
            settingsWindow.makeKeyAndOrderFront(nil)
        } else {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 600, height: 700),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.title = "Kimi Balance Settings"
            window.contentView = NSHostingView(rootView: SettingsView())
            window.contentMinSize = NSSize(width: 600, height: 500)
            window.isReleasedWhenClosed = false
            window.center()
            window.makeKeyAndOrderFront(nil)
            settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
