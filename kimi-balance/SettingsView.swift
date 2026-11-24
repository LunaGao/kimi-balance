import AppKit
import ServiceManagement
import SwiftUI

enum LaunchAtLoginSettings {
    static let isEnabledKey = "launchAtLogin"

    static func applyPreference() {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: isEnabledKey) == nil {
            defaults.set(true, forKey: isEnabledKey)
        }
        if defaults.bool(forKey: isEnabledKey) {
            do {
                try SMAppService.mainApp.register()
            } catch {
                NSLog("Launch at login registration failed: %@", error as NSError)
            }
        } else {
            SMAppService.mainApp.unregister { error in
                if let error {
                    NSLog("Launch at login unregistration failed: %@", error as NSError)
                }
            }
        }
    }

    static func setEnabled(_ isEnabled: Bool) async throws {
        if isEnabled {
            try SMAppService.mainApp.register()
        } else {
            try await SMAppService.mainApp.unregister()
        }
    }
}

enum UsageRefreshSettings {
    static let intervalKey = "usageRefreshInterval"
    static let defaultInterval: TimeInterval = 60
    static let minimumInterval: TimeInterval = 30
    static let maximumInterval: TimeInterval = 1_800
    static let intervalStep: TimeInterval = 30

    static var interval: TimeInterval {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: intervalKey) != nil else { return defaultInterval }
        return min(max(defaults.double(forKey: intervalKey), minimumInterval), maximumInterval)
    }
}

enum StatusBarContentItem: String, CaseIterable, Identifiable {
    case avatar
    case text
    case circularProgress

    var id: String { rawValue }

    var title: String {
        switch self {
        case .avatar: "Avatar"
        case .text: "Text"
        case .circularProgress: "Circular Progress"
        }
    }

    var systemImage: String {
        switch self {
        case .avatar: "person.circle"
        case .text: "textformat"
        case .circularProgress: "circle.dotted.circle"
        }
    }
}

enum StatusBarDisplaySettings {
    static let showsAvatarKey = "statusBarShowsAvatar"
    static let showsTextKey = "statusBarShowsText"
    static let showsCircularProgressKey = "statusBarShowsCircularProgress"
    static let contentOrderKey = "statusBarContentOrder"
    static let defaultContentOrder = StatusBarContentItem.allCases
    static let defaultContentOrderValue = "avatar,text,circularProgress"

    static var contentOrder: [StatusBarContentItem] {
        contentOrder(from: UserDefaults.standard.string(forKey: contentOrderKey))
    }

    static func contentOrder(from rawValue: String?) -> [StatusBarContentItem] {
        let storedItems = rawValue?
            .split(separator: ",")
            .compactMap { StatusBarContentItem(rawValue: String($0)) } ?? []
        let uniqueItems = storedItems.reduce(into: [StatusBarContentItem]()) { items, item in
            if !items.contains(item) { items.append(item) }
        }
        return uniqueItems + defaultContentOrder.filter { !uniqueItems.contains($0) }
    }

    static func rawValue(for contentOrder: [StatusBarContentItem]) -> String {
        contentOrder.map(\.rawValue).joined(separator: ",")
    }

    static func migrateIfNeeded() {
        let defaults = UserDefaults.standard
        let newKeys = [showsAvatarKey, showsTextKey, showsCircularProgressKey]
        guard newKeys.allSatisfy({ defaults.object(forKey: $0) == nil }),
              let rawValue = defaults.string(forKey: "statusBarDisplayMode"),
              let legacyMode = LegacyStatusBarDisplayMode(rawValue: rawValue) else { return }

        defaults.set(legacyMode == .avatarAndText || legacyMode == .avatarOnly, forKey: showsAvatarKey)
        defaults.set(legacyMode == .avatarAndText || legacyMode == .textOnly, forKey: showsTextKey)
        defaults.set(legacyMode == .circularProgress, forKey: showsCircularProgressKey)
    }
}

private enum LegacyStatusBarDisplayMode: String {
    case avatarAndText
    case avatarOnly
    case textOnly
    case circularProgress
}

struct SettingsView: View {
    @AppStorage(LaunchAtLoginSettings.isEnabledKey) private var launchAtLogin = true
    @AppStorage(UsageRefreshSettings.intervalKey) private var usageRefreshInterval = UsageRefreshSettings.defaultInterval
    @AppStorage(StatusBarDisplaySettings.showsAvatarKey) private var showsAvatar = true
    @AppStorage(StatusBarDisplaySettings.showsTextKey) private var showsText = true
    @AppStorage(StatusBarDisplaySettings.showsCircularProgressKey) private var showsCircularProgress = false
    @AppStorage(StatusBarDisplaySettings.contentOrderKey) private var contentOrder = StatusBarDisplaySettings.defaultContentOrderValue
    @State private var isUpdatingLaunchAtLogin = false
    @State private var launchAtLoginError: String?

    init() {
        StatusBarDisplaySettings.migrateIfNeeded()
    }

    private let repositoryURL = URL(string: "https://github.com/LunaGao/kimi-balance")!
    private let subscriptionURL = URL(string: "https://www.kimi.com/settings/subscription")!

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown"
    }

    private var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "Unknown"
    }

    private var formattedRefreshInterval: String {
        let seconds = Int(usageRefreshInterval)
        if seconds < 60 { return "\(seconds) seconds" }
        if seconds % 60 == 0 {
            let minutes = seconds / 60
            return "\(minutes) \(minutes == 1 ? "minute" : "minutes")"
        }
        return "\(seconds / 60) min \(seconds % 60) sec"
    }

    private func visibilityBinding(for item: StatusBarContentItem) -> Binding<Bool> {
        switch item {
        case .avatar: $showsAvatar
        case .text: $showsText
        case .circularProgress: $showsCircularProgress
        }
    }

    private func isOnlyVisibleItem(_ item: StatusBarContentItem) -> Bool {
        let visibleCount = [showsAvatar, showsText, showsCircularProgress].filter { $0 }.count
        return visibleCount == 1 && visibilityBinding(for: item).wrappedValue
    }

    private func moveContentItem(_ draggedIDs: [String], to target: StatusBarContentItem) {
        guard let draggedID = draggedIDs.first, draggedID != target.id else { return }
        var items = StatusBarDisplaySettings.contentOrder(from: contentOrder)
        guard let source = items.firstIndex(where: { $0.id == draggedID }),
              let destination = items.firstIndex(of: target) else { return }
        items.move(
            fromOffsets: IndexSet(integer: source),
            toOffset: destination > source ? destination + 1 : destination
        )
        contentOrder = StatusBarDisplaySettings.rawValue(for: items)
    }

    var body: some View {
        TabView {
            Form {
                Toggle("Launch at Login", isOn: Binding(
                    get: { launchAtLogin },
                    set: { isEnabled in
                        Task {
                            isUpdatingLaunchAtLogin = true
                            do {
                                try await LaunchAtLoginSettings.setEnabled(isEnabled)
                                launchAtLogin = isEnabled
                                launchAtLoginError = nil
                            } catch {
                                launchAtLoginError = error.localizedDescription
                            }
                            isUpdatingLaunchAtLogin = false
                        }
                    }
                ))
                .disabled(isUpdatingLaunchAtLogin)
                Text("Automatically open Kimi Balance when you log in to your Mac.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Section {
                    LabeledContent("Refresh Usage", value: formattedRefreshInterval)
                    HStack(spacing: 8) {
                        Text("30 sec")
                        RefreshUsageSlider(value: $usageRefreshInterval)
                            .frame(height: 22)
                        Text("30 min")
                    }
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                } footer: {
                    Text("How often Kimi Balance refreshes your usage in the background.")
                }
            }
            .formStyle(.grouped)
            .tabItem {
                Label("General", systemImage: "gear")
            }

            Form {
                Section {
                    List {
                        ForEach(StatusBarDisplaySettings.contentOrder(from: contentOrder)) { item in
                            HStack(spacing: 8) {
                                Image(systemName: "line.3.horizontal")
                                    .foregroundStyle(.secondary)
                                Label(item.title, systemImage: item.systemImage)
                                Spacer()
                                Toggle("", isOn: visibilityBinding(for: item))
                                    .labelsHidden()
                                    .disabled(isOnlyVisibleItem(item))
                            }
                            .padding(.vertical, 2)
                            .draggable(item.id)
                            .dropDestination(for: String.self) { draggedIDs, _ in
                                moveContentItem(draggedIDs, to: item)
                            }
                        }
                    }
                    .listStyle(.bordered)
                    .scrollDisabled(true)
                    .frame(height: 150)
                } header: {
                    Text("Content")
                } footer: {
                    Text("Drag items to change their order in the menu bar.")
                }
            }
            .formStyle(.grouped)
            .tabItem {
                Label("Menu Bar", systemImage: "menubar.rectangle")
            }

            Form {
                InstructionStep(
                    number: 1,
                    title: "Launch Kimi Balance",
                    description: "The app appears in the macOS menu bar. It does not open the main window automatically."
                )
                InstructionStep(
                    number: 2,
                    title: "Sign in to Kimi",
                    description: "Open the menu bar menu and choose “Show Main Window” (显示主窗口), then sign in on the kimi.com page."
                )
                InstructionStep(
                    number: 3,
                    title: "Load your usage",
                    description: "After signing in, choose “Login Completed” (登录完成，查看用量). Your login is reused while its cookie remains valid."
                )
                InstructionStep(
                    number: 4,
                    title: "Check your subscription",
                    description: "The menu bar shows total and 5-hour usage. Open its menu to see reset times and more details."
                )
                InstructionStep(
                    number: 5,
                    title: "Refresh when needed",
                    description: "Usage refreshes every 60 seconds. Choose “Refresh Now” (立即刷新) for an immediate update. Closing the main window does not stop background refreshes."
                )
            }
            .formStyle(.grouped)
            .tabItem {
                Label("How to Use", systemImage: "questionmark.circle")
            }

            Form {
                LabeledContent("Application", value: "Kimi Balance")
                LabeledContent("Version", value: version)
                LabeledContent("Build", value: build)
                LabeledContent("GitHub") {
                    Link("LunaGao/kimi-balance", destination: repositoryURL)
                }
                LabeledContent("Data Source") {
                    Link("Kimi Subscription", destination: subscriptionURL)
                }
                Text("Usage data is read from your Kimi subscription page. Login cookies are stored only in the app's local WebView data store.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .formStyle(.grouped)
            .tabItem {
                Label("About", systemImage: "info.circle")
            }
        }
        .frame(width: 600)
        .alert("Launch at Login", isPresented: Binding(
            get: { launchAtLoginError != nil },
            set: { if !$0 { launchAtLoginError = nil } }
        )) {
            Button("OK") { launchAtLoginError = nil }
        } message: {
            Text(launchAtLoginError ?? "")
        }
    }
}

private struct RefreshUsageSlider: NSViewRepresentable {
    @Binding var value: TimeInterval

    func makeCoordinator() -> Coordinator {
        Coordinator(value: $value)
    }

    func makeNSView(context: Context) -> NSSlider {
        let slider = NSSlider(
            value: value,
            minValue: UsageRefreshSettings.minimumInterval,
            maxValue: UsageRefreshSettings.maximumInterval,
            target: context.coordinator,
            action: #selector(Coordinator.valueChanged(_:))
        )
        slider.isContinuous = true
        slider.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return slider
    }

    func updateNSView(_ slider: NSSlider, context: Context) {
        context.coordinator.value = $value
        if slider.doubleValue != value {
            slider.doubleValue = value
        }
    }

    final class Coordinator: NSObject {
        var value: Binding<TimeInterval>

        init(value: Binding<TimeInterval>) {
            self.value = value
        }

        @objc func valueChanged(_ slider: NSSlider) {
            let step = UsageRefreshSettings.intervalStep
            let steppedValue = (slider.doubleValue / step).rounded() * step
            slider.doubleValue = steppedValue
            value.wrappedValue = steppedValue
        }
    }
}

private struct InstructionStep: View {
    let number: Int
    let title: String
    let description: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(number, format: .number)
                .font(.headline)
                .foregroundStyle(Color.accentColor)
                .frame(width: 26, height: 26)
                .background(Color.accentColor.opacity(0.12), in: Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(description)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    SettingsView()
}
