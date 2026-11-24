import AppKit
import Sparkle
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, SPUStandardUserDriverDelegate {
    private let subscriptionModel = SubscriptionModel()
    private lazy var updaterController = SPUStandardUpdaterController(
        startingUpdater: true,
        updaterDelegate: nil,
        userDriverDelegate: self
    )
    private var statusBarController: StatusBarController?
    private var mainWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        LaunchAtLoginSettings.applyPreference()
        NSApp.setActivationPolicy(.accessory)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowWillClose),
            name: NSWindow.willCloseNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(languageDidChange),
            name: UserDefaults.didChangeNotification,
            object: nil
        )
        statusBarController = StatusBarController(
            model: subscriptionModel,
            updaterController: updaterController,
            openMainWindow: showMainWindow
        )
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    var supportsGentleScheduledUpdateReminders: Bool {
        true
    }

    func standardUserDriverShouldHandleShowingScheduledUpdate(
        _ update: SUAppcastItem,
        andInImmediateFocus immediateFocus: Bool
    ) -> Bool {
        immediateFocus
    }

    func standardUserDriverWillHandleShowingUpdate(
        _ handleShowingUpdate: Bool,
        forUpdate update: SUAppcastItem,
        state: SPUUserUpdateState
    ) {
        if !state.userInitiated {
            statusBarController?.setUpdateAvailable(true)
        }
    }

    func standardUserDriverWillFinishUpdateSession() {
        statusBarController?.setUpdateAvailable(false)
    }

    @objc private func windowWillClose(_ notification: Notification) {
        DispatchQueue.main.async {
            let hasVisibleWindow = NSApp.windows.contains { $0.isVisible && $0.canBecomeKey }
            NSApp.setActivationPolicy(hasVisibleWindow ? .regular : .accessory)
        }
    }

    @objc private func languageDidChange() {
        mainWindow?.title = localized("app.title")
    }

    private func showMainWindow() {
        NSApp.setActivationPolicy(.regular)
        if let mainWindow {
            if mainWindow.isMiniaturized {
                mainWindow.deminiaturize(nil)
            }
            mainWindow.makeKeyAndOrderFront(nil)
            mainWindow.orderFrontRegardless()
        } else {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 900, height: 620),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.title = localized("app.title")
            window.contentView = NSHostingView(rootView: ContentView(model: subscriptionModel))
            window.isReleasedWhenClosed = false
            window.center()
            window.makeKeyAndOrderFront(nil)
            mainWindow = window
        }
        DispatchQueue.main.async {
            NSApp.activate()
        }
    }
}

@main
struct MyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            SettingsView()
        }
    }
}
