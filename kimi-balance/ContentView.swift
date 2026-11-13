import Combine
import Playgrounds
import SwiftUI
import WebKit

@MainActor
final class SubscriptionModel: NSObject, ObservableObject, WKNavigationDelegate {
    @Published private(set) var isLoading = true
    @Published private(set) var isLoginRequired = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var totalUsage = "--"
    @Published private(set) var totalResetTime = "--"
    @Published private(set) var fiveHourUsage = "--"
    @Published private(set) var fiveHourResetTime = "--"

    private let subscriptionURL = URL(string: "https://www.kimi.com/settings/subscription")!
    private var backgroundWebView: WKWebView!
    private var refreshCancellable: AnyCancellable?
    private var loadGeneration = 0

    override init() {
        super.init()

        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        backgroundWebView = WKWebView(
            frame: CGRect(x: 0, y: 0, width: 1280, height: 800),
            configuration: configuration
        )
        backgroundWebView.navigationDelegate = self
        refreshCancellable = Timer.publish(every: 60, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.refresh()
            }
        refresh()
    }

    func loginCompleted() {
        refresh()
    }

    func refresh() {
        Task {
            guard await hasValidKimiCookie() else {
                showLogin()
                return
            }
            openSubscriptionInBackground()
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard webView === backgroundWebView else { return }
        isLoading = false
        errorMessage = nil

        guard let url = webView.url, url.path.contains("/settings/subscription") else {
            showLogin()
            return
        }
        isLoginRequired = false
        readUsageWhenReady(generation: loadGeneration)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        navigationDidFail(error)
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        navigationDidFail(error)
    }

    private func navigationDidFail(_ error: Error) {
        guard (error as NSError).code != NSURLErrorCancelled else { return }
        isLoading = false
        errorMessage = error.localizedDescription
    }

    private func openSubscriptionInBackground() {
        loadGeneration += 1
        isLoginRequired = false
        isLoading = true
        errorMessage = nil
        backgroundWebView.load(URLRequest(url: subscriptionURL))
    }

    private func showLogin() {
        loadGeneration += 1
        isLoginRequired = true
        isLoading = false
        errorMessage = nil
        totalUsage = "--"
        totalResetTime = "--"
        fiveHourUsage = "--"
        fiveHourResetTime = "--"
    }

    private func hasValidKimiCookie() async -> Bool {
        let store = backgroundWebView.configuration.websiteDataStore.httpCookieStore
        let cookies: [HTTPCookie] = await withCheckedContinuation { continuation in
            store.getAllCookies { continuation.resume(returning: $0) }
        }
        return cookies.contains { cookie in
            let isKimiDomain = cookie.domain == "kimi.com" || cookie.domain.hasSuffix(".kimi.com")
            let isValid = cookie.expiresDate.map { $0 > Date() } ?? true
            return isKimiDomain && isValid
        }
    }

    private func readUsageWhenReady(generation: Int) {
        Task {
            for attempt in 0..<4 {
                let delay: UInt64 = attempt == 0 ? 1_500_000_000 : 1_000_000_000
                try? await Task.sleep(nanoseconds: delay)
                guard generation == loadGeneration else { return }

                let script = """
                    (() => {
                        const lines = (document.body?.innerText || "")
                            .split("\\n")
                            .map(line => line.trim())
                            .filter(line => line.length > 0);

                        function sectionFor(pattern) {
                            const index = lines.findIndex(line => pattern.test(line));
                            if (index < 0) return [];
                            const nextSection = lines.slice(index + 1).findIndex(line =>
                                /5\\s*小时|7\\s*天|总使用量/.test(line)
                            );
                            const end = nextSection < 0
                                ? Math.min(lines.length, index + 12)
                                : index + 1 + nextSection;
                            return lines.slice(index, end);
                        }

                        function usageIn(section) {
                            const match = section.join(" ").match(/(\\d+(?:\\.\\d+)?)\\s*%/);
                            return match ? `${match[1]}%` : null;
                        }

                        function resetIn(section) {
                            return section.find(line => /重置|重设|Reset/i.test(line)) || null;
                        }

                        const totalSection = sectionFor(/总使用量/);
                        const fiveHourSection = sectionFor(/5\\s*小时/);
                        return {
                            total: usageIn(totalSection),
                            totalReset: resetIn(totalSection),
                            fiveHour: usageIn(fiveHourSection),
                            fiveHourReset: resetIn(fiveHourSection)
                        };
                    })()
                    """

                guard let result = try? await backgroundWebView.evaluateJavaScript(script),
                      let values = result as? [String: Any] else { continue }
                let total = values["total"] as? String
                let fiveHour = values["fiveHour"] as? String
                if let total { totalUsage = total }
                if let fiveHour { fiveHourUsage = fiveHour }
                if let reset = values["totalReset"] as? String { totalResetTime = reset }
                if let reset = values["fiveHourReset"] as? String { fiveHourResetTime = reset }
                if total != nil && fiveHour != nil { return }
            }
            if generation == loadGeneration {
                showLogin()
            }
        }
    }
}

struct LoginWebView: NSViewRepresentable {
    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.allowsBackForwardNavigationGestures = true
        webView.load(URLRequest(url: URL(string: "https://www.kimi.com/")!))
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {}
}

struct ContentView: View {
    @ObservedObject var model: SubscriptionModel

    var body: some View {
        ZStack {
            if model.isLoginRequired {
                LoginWebView()

                VStack {
                    Spacer()
                    HStack(spacing: 16) {
                        Text("请在页面中登录 Kimi")
                        Button("登录完成，查看用量", action: model.loginCompleted)
                    }
                    .padding(16)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                    .padding(.bottom, 20)
                }
            } else {
                VStack(spacing: 24) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(.green)
                    Text("订阅用量正在后台自动更新")
                        .font(.title2)
                    HStack(spacing: 40) {
                        VStack {
                            Text("总使用量")
                                .foregroundStyle(.secondary)
                            Text(model.totalUsage)
                                .font(.title)
                            Text(model.totalResetTime)
                                .foregroundStyle(.secondary)
                        }
                        VStack {
                            Text("5小时用量")
                                .foregroundStyle(.secondary)
                            Text(model.fiveHourUsage)
                                .font(.title)
                            Text(model.fiveHourResetTime)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Button("立即刷新", action: model.refresh)
                }
            }

            if model.isLoading, !model.isLoginRequired {
                ProgressView()
                    .padding(24)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            }

            if let errorMessage = model.errorMessage {
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                    Text(errorMessage)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 420)
                    Button("重试", action: model.refresh)
                        .keyboardShortcut("r")
                }
                .padding(32)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
            }
        }
        .frame(minWidth: 900, minHeight: 620)
    }
}

#Preview {
    ContentView(model: SubscriptionModel())
}

#Playground {
    _ = 1 + 2
}
