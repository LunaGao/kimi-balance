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
        case .avatar: localized("status.avatar")
        case .text: localized("status.text")
        case .circularProgress: localized("status.circular_progress")
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
    @AppStorage(AppLanguage.storageKey) private var appLanguage = AppLanguage.preferred.rawValue
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
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            ?? localized("common.unknown")
    }

    private var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
            ?? localized("common.unknown")
    }

    private var formattedRefreshInterval: String {
        let seconds = Int(usageRefreshInterval)
        if seconds < 60 { return localized("settings.interval_seconds", seconds) }
        if seconds % 60 == 0 {
            let minutes = seconds / 60
            return minutes == 1
                ? localized("settings.interval_one_minute")
                : localized("settings.interval_minutes", minutes)
        }
        return localized("settings.interval_minutes_seconds", seconds / 60, seconds % 60)
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
                Picker(localized("settings.language"), selection: $appLanguage) {
                    ForEach(AppLanguage.allCases) { language in
                        Text(language.displayName).tag(language.rawValue)
                    }
                }

                Toggle(localized("settings.launch_at_login"), isOn: Binding(
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
                Text(localized("settings.launch_description"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Section {
                    LabeledContent(localized("settings.refresh_usage"), value: formattedRefreshInterval)
                    HStack(spacing: 8) {
                        Text(localized("settings.seconds_short"))
                        RefreshUsageSlider(value: $usageRefreshInterval)
                            .frame(height: 22)
                        Text(localized("settings.minutes_short"))
                    }
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                } footer: {
                    Text(localized("settings.refresh_footer"))
                }
            }
            .formStyle(.grouped)
            .tabItem {
                Label(localized("settings.general"), systemImage: "gear")
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
                    Text(localized("settings.content"))
                } footer: {
                    Text(localized("settings.content_footer"))
                }
            }
            .formStyle(.grouped)
            .tabItem {
                Label(localized("settings.menu_bar"), systemImage: "menubar.rectangle")
            }

            Form {
                InstructionStep(
                    number: 1,
                    title: localized("settings.step_1_title"),
                    description: localized("settings.step_1_description")
                )
                InstructionStep(
                    number: 2,
                    title: localized("settings.step_2_title"),
                    description: localized("settings.step_2_description")
                )
                InstructionStep(
                    number: 3,
                    title: localized("settings.step_3_title"),
                    description: localized("settings.step_3_description")
                )
                InstructionStep(
                    number: 4,
                    title: localized("settings.step_4_title"),
                    description: localized("settings.step_4_description")
                )
                InstructionStep(
                    number: 5,
                    title: localized("settings.step_5_title"),
                    description: localized("settings.step_5_description")
                )
            }
            .formStyle(.grouped)
            .tabItem {
                Label(localized("settings.how_to_use"), systemImage: "questionmark.circle")
            }

            Form {
                LabeledContent(localized("settings.application"), value: "Kimi Balance")
                LabeledContent(localized("settings.version"), value: version)
                LabeledContent(localized("settings.build"), value: build)
                LabeledContent("GitHub") {
                    Link("LunaGao/kimi-balance", destination: repositoryURL)
                }
                LabeledContent(localized("settings.data_source")) {
                    Link(localized("settings.subscription"), destination: subscriptionURL)
                }
                Text(localized("settings.about_description"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .formStyle(.grouped)
            .tabItem {
                Label(localized("settings.about"), systemImage: "info.circle")
            }
        }
        .frame(width: 600)
        .environment(\.locale, Locale(identifier: appLanguage))
        .alert(localized("settings.launch_at_login"), isPresented: Binding(
            get: { launchAtLoginError != nil },
            set: { if !$0 { launchAtLoginError = nil } }
        )) {
            Button(localized("common.ok")) { launchAtLoginError = nil }
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
