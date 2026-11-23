import SwiftUI

struct SettingsView: View {
    private let repositoryURL = URL(string: "https://github.com/LunaGao/kimi-balance")!
    private let subscriptionURL = URL(string: "https://www.kimi.com/settings/subscription")!

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown"
    }

    private var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "Unknown"
    }

    var body: some View {
        Form {
            Section("How to Use") {
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

            Section("About") {
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
        }
        .formStyle(.grouped)
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
