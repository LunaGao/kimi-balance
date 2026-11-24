import SwiftUI

enum StatusBarDisplaySettings {
    static let showsAvatarKey = "statusBarShowsAvatar"
    static let showsTextKey = "statusBarShowsText"
    static let showsCircularProgressKey = "statusBarShowsCircularProgress"

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
    @AppStorage(StatusBarDisplaySettings.showsAvatarKey) private var showsAvatar = true
    @AppStorage(StatusBarDisplaySettings.showsTextKey) private var showsText = true
    @AppStorage(StatusBarDisplaySettings.showsCircularProgressKey) private var showsCircularProgress = false

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

    var body: some View {
        TabView {
            Form {
                Toggle("Avatar", isOn: $showsAvatar)
                    .disabled(showsAvatar && !showsText && !showsCircularProgress)
                Toggle("Text", isOn: $showsText)
                    .disabled(showsText && !showsAvatar && !showsCircularProgress)
                Toggle("Circular Progress", isOn: $showsCircularProgress)
                    .disabled(showsCircularProgress && !showsAvatar && !showsText)
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
