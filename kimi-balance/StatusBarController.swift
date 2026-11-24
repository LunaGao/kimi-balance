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
    private var cancellables = Set<AnyCancellable>()
    private var totalUsageItem: NSMenuItem!
    private var totalResetItem: NSMenuItem!
    private var fiveHourUsageItem: NSMenuItem!
    private var fiveHourResetItem: NSMenuItem!
    private var avatarLoadTask: Task<Void, Never>?
    private var loadedAvatarURL: URL?
    private var avatarImage: NSImage?
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
        StatusBarDisplaySettings.migrateIfNeeded()
        setupStatusItem()
        setupMenu()
        updateContent()
        model.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.updateContent()
            }
            .store(in: &cancellables)
        NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.updateContent()
            }
            .store(in: &cancellables)
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

    private var displaySettings: (avatar: Bool, text: Bool, circularProgress: Bool) {
        let defaults = UserDefaults.standard
        func value(forKey key: String, default defaultValue: Bool) -> Bool {
            defaults.object(forKey: key) == nil ? defaultValue : defaults.bool(forKey: key)
        }

        let settings = (
            avatar: value(forKey: StatusBarDisplaySettings.showsAvatarKey, default: true),
            text: value(forKey: StatusBarDisplaySettings.showsTextKey, default: true),
            circularProgress: value(forKey: StatusBarDisplaySettings.showsCircularProgressKey, default: false)
        )
        return settings.avatar || settings.text || settings.circularProgress
            ? settings
            : (avatar: false, text: true, circularProgress: false)
    }

    private var placeholderAvatar: NSImage? {
        NSImage(systemSymbolName: "person.circle.fill", accessibilityDescription: "用户头像")
    }

    private func updateContent() {
        let settings = displaySettings
        statusItem.button?.title = settings.text
            ? model.isLoginRequired ? "请完成登录" : " 总\(model.totalUsage) 5小时\(model.fiveHourUsage)"
            : ""

        if model.isLoginRequired {
            avatarLoadTask?.cancel()
            loadedAvatarURL = nil
            avatarImage = settings.avatar ? placeholderAvatar : nil
        } else if settings.avatar {
            if loadedAvatarURL != model.avatarURL || avatarImage == nil {
                loadedAvatarURL = model.avatarURL
                loadAvatar()
            }
        } else {
            avatarLoadTask?.cancel()
            loadedAvatarURL = nil
            avatarImage = nil
        }
        updateStatusImage()
        totalUsageItem.title = "总使用量：\(model.totalUsage)"
        totalResetItem.title = "总使用量重置时间：\(model.totalResetTime)"
        fiveHourUsageItem.title = "5小时用量：\(model.fiveHourUsage)"
        fiveHourResetItem.title = "5小时用量重置时间：\(model.fiveHourResetTime)"
    }

    private func updateStatusImage() {
        let settings = displaySettings
        let avatar = settings.avatar ? avatarImage : nil
        guard settings.circularProgress else {
            statusItem.button?.image = avatar
            return
        }

        let progress = circularUsageImage(isTemplate: avatar == nil)
        statusItem.button?.image = if let avatar {
            combinedStatusImage(avatar: avatar, progress: progress)
        } else {
            progress
        }
    }

    private func loadAvatar() {
        avatarLoadTask?.cancel()
        avatarImage = placeholderAvatar
        guard let url = model.avatarURL else { return }

        avatarLoadTask = Task { [weak self] in
            guard let (data, _) = try? await URLSession.shared.data(from: url),
                  !Task.isCancelled,
                  let image = NSImage(data: data) else { return }
            self?.applyAvatar(image, for: url)
        }
    }

    private func applyAvatar(_ image: NSImage, for url: URL) {
        guard !model.isLoginRequired, displaySettings.avatar, model.avatarURL == url else { return }
        avatarImage = circularAvatar(from: image)
        updateStatusImage()
    }

    private var statusBarContentColor: NSColor {
        guard let appearance = statusItem.button?.effectiveAppearance else { return .labelColor }
        return appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? .white : .black
    }

    private func combinedStatusImage(avatar: NSImage, progress: NSImage) -> NSImage {
        let spacing: CGFloat = 4
        let size = NSSize(
            width: avatar.size.width + spacing + progress.size.width,
            height: max(avatar.size.height, progress.size.height)
        )
        let image = NSImage(size: size)
        image.lockFocus()
        avatar.draw(in: NSRect(
            x: 0,
            y: (size.height - avatar.size.height) / 2,
            width: avatar.size.width,
            height: avatar.size.height
        ))
        progress.draw(in: NSRect(
            x: avatar.size.width + spacing,
            y: (size.height - progress.size.height) / 2,
            width: progress.size.width,
            height: progress.size.height
        ))
        image.unlockFocus()
        image.isTemplate = false
        image.accessibilityDescription = "用户头像，\(progress.accessibilityDescription ?? "用量进度")"
        return image
    }

    private func circularUsageImage(isTemplate: Bool = true) -> NSImage {
        let color: NSColor = isTemplate ? .labelColor : statusBarContentColor
        let image = NSImage(size: NSSize(width: 40, height: 18))
        image.lockFocus()
        drawUsageProgress(
            usageProgress(model.totalUsage),
            in: NSRect(x: 0, y: 0, width: 18, height: 18),
            color: color
        )
        drawUsageProgress(
            usageProgress(model.fiveHourUsage),
            in: NSRect(x: 22, y: 0, width: 18, height: 18),
            color: color
        )
        image.unlockFocus()
        image.isTemplate = isTemplate
        image.accessibilityDescription = "总使用量：\(model.totalUsage)，5小时用量：\(model.fiveHourUsage)"
        return image
    }

    private func usageProgress(_ usage: String) -> Double {
        let value = usage.replacingOccurrences(of: "%", with: "")
        guard let percentage = Double(value) else { return 0 }
        return min(max(percentage / 100, 0), 1)
    }

    private func drawUsageProgress(_ progress: Double, in rect: NSRect, color: NSColor) {
        let track = NSBezierPath(ovalIn: rect.insetBy(dx: 2, dy: 2))
        track.lineWidth = 3
        color.withAlphaComponent(0.25).setStroke()
        track.stroke()
        guard progress > 0 else { return }

        let path = NSBezierPath()
        path.appendArc(
            withCenter: NSPoint(x: rect.midX, y: rect.midY),
            radius: min(rect.width, rect.height) / 2 - 2,
            startAngle: 90,
            endAngle: 90 - 360 * progress,
            clockwise: true
        )
        path.lineWidth = 3
        path.lineCapStyle = .round
        color.setStroke()
        path.stroke()
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
        image.accessibilityDescription = "用户头像"
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
