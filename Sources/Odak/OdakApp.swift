import AppKit
import OdakCore
import SwiftUI

@main
struct OdakApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var model = AppModel.shared

    var body: some Scene {
        Window("Odak", id: "main") {
            ContentView()
                .environment(model)
                .frame(minWidth: 560, minHeight: 380)
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(after: .appSettings) {
                Button("Reading Statistics…") { model.isStatsPresented = true }
                    .keyboardShortcut("y")
            }
            CommandGroup(replacing: .newItem) {
                Button("Open File…") { model.isImporterPresented = true }
                    .keyboardShortcut("o")
            }
            CommandGroup(after: .pasteboard) {
                Button("Paste & Read") { model.pasteAndRead() }
                    .keyboardShortcut("v", modifiers: [.command, .shift])
            }
        }

        Settings { SettingsView() }
    }
}

/// Entry point for macOS Services and Finder "Open With" / Dock drops.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.servicesProvider = self
        NSUpdateDynamicServices()
    }

    func applicationWillTerminate(_ notification: Notification) { AppModel.shared.saveProgress() }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func application(_ application: NSApplication, open urls: [URL]) {
        guard let url = urls.first, url.isFileURL else { return }
        bringToFront()
        AppModel.shared.open(url)
    }

    /// NSServices handler, see NSMessage in Info.plist.
    @objc func readSelection(_ pboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString>) {
        guard let text = pboard.string(forType: .string), !text.allSatisfy(\.isWhitespace) else {
            error.pointee = String(localized: "No text was selected.") as NSString
            return
        }
        bringToFront()
        AppModel.shared.read(text)
    }

    /// The user just asked for Odak from another app, so it must come forward. Plain `NSApp.activate()`
    /// is only a request since macOS 14 and is refused while e.g. Chrome stays active.
    private func bringToFront() {
        NSApp.unhide(nil)
        NSApp.windows.first { $0.canBecomeMain }?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
