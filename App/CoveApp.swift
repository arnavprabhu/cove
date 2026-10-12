import SwiftUI
import UserNotifications

@main
struct CoveApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var library = VMLibrary.shared
    @AppStorage(Pref.showMenuBarExtra) private var showMenuBarExtra = true

    var body: some Scene {
        Window("Cove", id: WindowID.library) {
            RootView()
                .environment(library)
        }
        .defaultSize(width: 1200, height: 760)
        .commands { CoveCommands(library: library) }

        WindowGroup("Virtual Machine", id: WindowID.console, for: UUID.self) { $vmID in
            if let vmID { VMWindow(vmID: vmID).environment(library) }
        }
        .defaultSize(width: 1280, height: 860)
        .windowToolbarStyle(.unified(showsTitle: true))

        WindowGroup("Snapshots", id: WindowID.snapshots, for: UUID.self) { $vmID in
            if let vmID { SnapshotsView(vmID: vmID).environment(library) }
        }
        .defaultSize(width: 1200, height: 760)

        WindowGroup("Settings", id: WindowID.vmSettings, for: UUID.self) { $vmID in
            if let vmID { VMSettingsView(vmID: vmID).environment(library) }
        }
        .windowResizability(.contentSize)

        WindowGroup("Installing macOS", id: WindowID.install, for: UUID.self) { $jobID in
            if let jobID { InstallProgressView(jobID: jobID).environment(library) }
        }
        .defaultSize(width: 1200, height: 760)

        Settings {
            AppSettingsView().environment(library)
        }

        MenuBarExtra(isInserted: $showMenuBarExtra) {
            MenuBarView().environment(library)
        } label: {
            Image(systemName: library.liveItems.isEmpty ? "macwindow" : "macwindow.badge.plus")
        }
        .menuBarExtraStyle(.window)
    }
}

/// Main window: Unsupported Mac → Welcome (empty library) → Library.
struct RootView: View {
    @Environment(VMLibrary.self) private var library

    var body: some View {
        Group {
            if !HostInfo.isAppleSilicon || !HostInfo.virtualizationSupported {
                UnsupportedMacView()
            } else if library.items.isEmpty {
                WelcomeView()
            } else {
                LibraryView()
            }
        }
        .frame(minWidth: 900, minHeight: 600)
        .modifier(AppRouterModifier())
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        UNUserNotificationCenter.current().delegate = self
        InstallNotifier.requestAuthorization()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let library = MainActor.assumeIsolated { VMLibrary.shared }
        guard MainActor.assumeIsolated({ !library.liveItems.isEmpty }) else { return .terminateNow }
        // Suspend running VMs so they resume where they left off next launch.
        Task { @MainActor in
            await library.suspendAll()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        if let s = response.notification.request.content.userInfo[InstallNotifier.vmIDKey] as? String,
           let id = UUID(uuidString: s) {
            Task { @MainActor in AppRouter.shared.openConsole(id) }
        }
        completionHandler()
    }
}
