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
    private let contentStackView = NSStackView()
    private var cancellables = Set<AnyCancellable>()
    private var totalUsageItem: NSMenuItem!
    private var totalResetItem: NSMenuItem!
    private var fiveHourUsageItem: NSMenuItem!
    private var fiveHourResetItem: NSMenuItem!
    private var refreshItem: NSMenuItem!
    private var mainWindowItem: NSMenuItem!
    private var settingsItem: NSMenuItem!
    private var updateItem: NSMenuItem!
    private var quitItem: NSMenuItem!
    private var isUpdateAvailable = false
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
        button.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        button.toolTip = localized("app.title")

        contentStackView.orientation = .horizontal
        contentStackView.alignment = .centerY
        contentStackView.distribution = .gravityAreas
        contentStackView.spacing = 4
        contentStackView.translatesAutoresizingMaskIntoConstraints = false
        button.addSubview(contentStackView)
        NSLayoutConstraint.activate([
            contentStackView.centerXAnchor.constraint(equalTo: button.centerXAnchor),
            contentStackView.centerYAnchor.constraint(equalTo: button.centerYAnchor),
            contentStackView.leadingAnchor.constraint(greaterThanOrEqualTo: button.leadingAnchor, constant: 4),
            contentStackView.trailingAnchor.constraint(lessThanOrEqualTo: button.trailingAnchor, constant: -4)
        ])
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

        refreshItem = NSMenuItem(
            title: localized("menu.refresh_now"),
            action: #selector(refresh),
            keyEquivalent: "r"
        )
        refreshItem.target = self
        menu.addItem(refreshItem)
        menu.addItem(.separator())

        mainWindowItem = NSMenuItem(
            title: localized("menu.show_main_window"),
            action: #selector(openMainWindow),
            keyEquivalent: "o"
        )
        mainWindowItem.target = self
        menu.addItem(mainWindowItem)

        settingsItem = NSMenuItem(
            title: localized("menu.settings"),
            action: #selector(showSettings),
            keyEquivalent: ","
        )
        settingsItem.target = self
        menu.addItem(settingsItem)

        updateItem = NSMenuItem(
            title: localized("menu.check_updates"),
            action: #selector(SPUStandardUpdaterController.checkForUpdates(_:)),
            keyEquivalent: ""
        )
        updateItem.target = updaterController
        menu.addItem(updateItem)
        menu.addItem(.separator())

        quitItem = NSMenuItem(
            title: localized("menu.quit"),
            action: #selector(quit),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)
        statusItem.menu = menu
    }

    private var displaySettings: (
        avatar: Bool,
        text: Bool,
        circularProgress: Bool,
        contentOrder: [StatusBarContentItem]
    ) {
        let defaults = UserDefaults.standard
        func value(forKey key: String, default defaultValue: Bool) -> Bool {
            defaults.object(forKey: key) == nil ? defaultValue : defaults.bool(forKey: key)
        }

        let settings = (
            avatar: value(forKey: StatusBarDisplaySettings.showsAvatarKey, default: true),
            text: value(forKey: StatusBarDisplaySettings.showsTextKey, default: true),
            circularProgress: value(forKey: StatusBarDisplaySettings.showsCircularProgressKey, default: false),
            contentOrder: StatusBarDisplaySettings.contentOrder
        )
        return settings.avatar || settings.text || settings.circularProgress
            ? settings
            : (avatar: false, text: true, circularProgress: false, contentOrder: settings.contentOrder)
    }

    private var placeholderAvatar: NSImage? {
        NSImage(
            systemSymbolName: "person.circle.fill",
            accessibilityDescription: localized("accessibility.avatar")
        )
    }

    private func updateContent() {
        let settings = displaySettings

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
        updateStatusContent()
        updateLocalizedContent()
    }

    private func updateLocalizedContent() {
        statusItem.button?.toolTip = localized("app.title")
        totalUsageItem.title = localized("menu.total_usage", model.totalUsage)
        totalResetItem.title = localized(
            "menu.total_reset",
            localizedResetTime(model.totalResetTime)
        )
        fiveHourUsageItem.title = localized("menu.five_hour_usage", model.fiveHourUsage)
        fiveHourResetItem.title = localized(
            "menu.five_hour_reset",
            localizedResetTime(model.fiveHourResetTime)
        )
        refreshItem.title = localized("menu.refresh_now")
        mainWindowItem.title = localized("menu.show_main_window")
        settingsItem.title = localized("menu.settings")
        updateItem.title = localized(isUpdateAvailable ? "menu.update_available" : "menu.check_updates")
        quitItem.title = localized("menu.quit")
        avatarImage?.accessibilityDescription = localized("accessibility.avatar")
        settingsWindow?.title = localized("settings.window_title")
    }

    private func updateStatusContent() {
        let settings = displaySettings
        for view in contentStackView.arrangedSubviews {
            contentStackView.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        for item in settings.contentOrder {
            switch item {
            case .avatar:
                guard settings.avatar, let avatarImage else { continue }
                contentStackView.addArrangedSubview(NSImageView(image: avatarImage))
            case .text:
                guard settings.text else { continue }
                let text = model.isLoginRequired
                    ? localized("status.sign_in_required")
                    : localized("status.usage_summary", model.totalUsage, model.fiveHourUsage)
                let textField = NSTextField(labelWithString: text)
                textField.font = statusItem.button?.font
                textField.textColor = statusBarContentColor
                contentStackView.addArrangedSubview(textField)
            case .circularProgress:
                guard settings.circularProgress else { continue }
                let isTemplate = !settings.avatar || avatarImage == nil
                contentStackView.addArrangedSubview(NSImageView(
                    image: circularUsageImage(isTemplate: isTemplate)
                ))
            }
        }
        statusItem.length = max(20, ceil(contentStackView.fittingSize.width + 8))
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
        updateStatusContent()
    }

    private var statusBarContentColor: NSColor {
        guard let appearance = statusItem.button?.effectiveAppearance else { return .labelColor }
        return appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? .white : .black
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
        image.accessibilityDescription = localized(
            "accessibility.usage",
            model.totalUsage,
            model.fiveHourUsage
        )
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
        image.accessibilityDescription = localized("accessibility.avatar")
        return image
    }

    func setUpdateAvailable(_ available: Bool) {
        isUpdateAvailable = available
        updateItem.title = localized(available ? "menu.update_available" : "menu.check_updates")
    }

    @objc private func refresh() {
        model.refresh()
    }

    @objc private func openMainWindow() {
        openMainWindowAction()
    }

    @objc private func showSettings() {
        NSApp.setActivationPolicy(.regular)
        let settingsWindowTitles: Set<String> = [
            localized("settings.general"),
            localized("settings.menu_bar"),
            localized("settings.how_to_use"),
            localized("settings.about"),
            localized("settings.window_title")
        ]
        if let settingsWindow = settingsWindow ?? NSApp.windows.first(where: {
            settingsWindowTitles.contains($0.title)
        }) {
            self.settingsWindow = settingsWindow
            if settingsWindow.isMiniaturized {
                settingsWindow.deminiaturize(nil)
            }
            settingsWindow.makeKeyAndOrderFront(nil)
            settingsWindow.orderFrontRegardless()
        } else {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 600, height: 700),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.title = localized("settings.window_title")
            window.contentView = NSHostingView(rootView: SettingsView())
            window.contentMinSize = NSSize(width: 600, height: 500)
            window.isReleasedWhenClosed = false
            window.center()
            window.makeKeyAndOrderFront(nil)
            settingsWindow = window
        }
        DispatchQueue.main.async {
            NSApp.activate()
        }
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
