import SwiftUI
import AppKit
import Carbon

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    static var launchedAtLogin = false
    static weak var store: AppStore?
    func applicationDidFinishLaunching(_ notification: Notification) {
        if let event = NSAppleEventManager.shared().currentAppleEvent {
            Self.launchedAtLogin = event.paramDescriptor(forKeyword: AEKeyword(keyAELaunchedAsLogInItem)) != nil
        }
        Self.store?.start(login: Self.launchedAtLogin)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if let window = sender.windows.first(where: { $0.identifier?.rawValue == "main" || $0.title == "KeyBridge" }) {
            window.makeKeyAndOrderFront(nil)
            sender.activate(ignoringOtherApps: true)
        }
        return true
    }
}

@main @MainActor struct KeyBridgeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var store = AppStore()
    init() {
        let model = AppStore()
        _store = StateObject(wrappedValue: model)
        AppDelegate.store = model
    }
    var body: some Scene {
        Window("KeyBridge", id: "main") {
            MainView().environmentObject(store)
                .frame(minWidth: 960, minHeight: 660)
        }.defaultSize(width: 1080, height: 740)
        MenuBarExtra {
            MenuContent().environmentObject(store)
        } label: {
            Image(nsImage: MenuBarIcon.image)
                .accessibilityLabel("KeyBridge · \(store.stateLabel) · \(store.appliedName)")
                .help("KeyBridge · \(store.stateLabel) · \(store.appliedName)")
        }
    }
}

@MainActor enum MenuBarIcon {
    static let image: NSImage = {
        let image = Bundle.main.resourceURL.flatMap { NSImage(contentsOf: $0.appendingPathComponent("MenuBarIcon.png")) }
            ?? NSImage(systemSymbolName: "key.horizontal", accessibilityDescription: "KeyBridge")!
        image.size = NSSize(width: 22, height: 18)
        image.isTemplate = true
        return image
    }()
}

struct MenuContent: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.openWindow) var openWindow
    var body: some View {
        Text("KeyBridge · \(store.stateLabel)")
        Text(store.appliedName)
        if store.demo { Text("デモモード") }
        Divider()
        Button("管理画面を開く") { openWindow(id: "main"); NSApp.activate(ignoringOtherApps: true) }
        Button("最新情報を取得") { Task { await store.perform { try await store.refresh() } } }.disabled(store.busy)
        Button("再適用") { if let id = store.applied?.setID { Task { await store.perform { try await store.apply(id) } } } }.disabled(store.busy || store.applied == nil)
        Button("適用を解除") { Task { await store.perform { try store.clear() } } }.disabled(store.busy || store.applied == nil)
        Divider()
        Button("終了（適用は維持）") { NSApp.terminate(nil) }
    }
}
