import AppKit
import SwiftUI

@main
struct MyApp: App {
    @StateObject private var subscriptionModel = SubscriptionModel()
    @State private var statusBarController: StatusBarController?
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        WindowGroup(id: "main") {
            ContentView(model: subscriptionModel)
                .onAppear {
                    installStatusItem()
                }
        }
    }

    private func installStatusItem() {
        guard statusBarController == nil else { return }
        statusBarController = StatusBarController(
            model: subscriptionModel,
            openMainWindow: showMainWindow
        )
    }

    private func showMainWindow() {
        openWindow(id: "main")
        NSApp.activate(ignoringOtherApps: true)
    }
}
