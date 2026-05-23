import SwiftUI
import AppKit
import LazyOSCore

@main
struct LazyOSApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup("LazyOS") {
            LibraryView()
                .environmentObject(appDelegate.sharedLibrary)
                .frame(minWidth: 760, minHeight: 520)
        }
        .windowStyle(.titleBar)
        .commands {
            CommandGroup(replacing: .newItem) { }
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    var menuBar: MenuBarController?
    let sharedLibrary = LibraryViewModel()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        ServiceManager.shared.bootstrapIfNeeded()
        sharedLibrary.refresh()
        sharedLibrary.startPolling()
        menuBar = MenuBarController(library: sharedLibrary)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            for window in NSApp.windows {
                window.makeKeyAndOrderFront(nil)
            }
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let running = ServiceManager.shared.library().filter {
            let s = ServiceManager.shared.status(slug: $0.slug)
            return s == .running || s == .starting
        }
        if running.isEmpty { return .terminateNow }

        let alert = NSAlert()
        alert.messageText = running.count == 1
            ? "Stop \(running[0].name) before quitting?"
            : "Stop \(running.count) running apps before quitting?"
        alert.informativeText = "Apps left running will keep using CPU and memory. You can quit and leave them on, or stop them first."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Stop and Quit")        // default
        alert.addButton(withTitle: "Quit, Leave Running")  // secondary
        alert.addButton(withTitle: "Cancel")               // cancel

        let response = alert.runModal()
        switch response {
        case .alertFirstButtonReturn:
            // Stop everything off-main, then terminate.
            DispatchQueue.global(qos: .userInitiated).async {
                for svc in running {
                    try? ServiceManager.shared.stop(slug: svc.slug)
                }
                DispatchQueue.main.async { NSApp.reply(toApplicationShouldTerminate: true) }
            }
            return .terminateLater
        case .alertSecondButtonReturn:
            return .terminateNow
        default:
            return .terminateCancel
        }
    }
}
