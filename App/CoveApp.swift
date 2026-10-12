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

        WindowGroup("SSH & Agent Access", id: WindowID.remoteAccess, for: UUID.self) { $vmID in
            if let vmID { RemoteAccessView(vmID: vmID).environment(library) }
        }
        .defaultSize(width: 760, height: 640)

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
    @State private var showNewVM = false
    @State private var newVMPurpose: VMPurpose = .everyday
    @State private var commandErrors = CommandErrorCenter.shared
    @State private var diskSpace = DiskSpaceMonitor.shared

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
        .coveAlert(Binding(
            get: { commandErrors.alert },
            set: { commandErrors.alert = $0 }
        ))
        .sheet(isPresented: $showNewVM) { NewVMView(initialPurpose: newVMPurpose, onDismiss: { showNewVM = false }) }
        .onAppear {
            diskSpace.startPolling(at: { library.rootURL })
            GuestAccessMonitor.shared.start(library: library)
        }
        // Warn once each time free space drops into the critical range while VMs are running.
        .onChange(of: diskSpace.criticalRevision) {
            guard !library.liveItems.isEmpty, let available = diskSpace.takeCriticalWarning() else { return }
            commandErrors.present(.lowDiskSpace(available: available))
        }
        .onReceive(NotificationCenter.default.publisher(for: .coveNewVM)) { note in
            newVMPurpose = note.object as? VMPurpose ?? .everyday
            showNewVM = true
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        UNUserNotificationCenter.current().delegate = self
        InstallNotifier.requestAuthorization()
        MainActor.assumeIsolated {
            #if DEBUG
            SmokeTest.runIfRequested()
            DebugRender.runIfRequested()
            #endif
        }
    }

    /// VMs run inside Cove's process, so they can't outlive it. On quit they're either suspended (default) or,
    /// with "Suspend VMs on quit" off, shut down after the user confirms. If anything fails, Cove stays open.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        MainActor.assumeIsolated {
            let library = VMLibrary.shared
            let live = library.liveItems
            guard !live.isEmpty else { return .terminateNow }
            let suspend = UserDefaults.standard.object(forKey: Pref.suspendOnQuit) as? Bool ?? true
            if !suspend {
                let alert = NSAlert()
                alert.messageText = live.count == 1 ? "Shut down “\(live[0].name)” and quit?" : "Shut down \(live.count) VMs and quit?"
                alert.informativeText = "Running VMs can’t keep going after Cove quits. Unsaved work inside them may be lost. "
                    + "To pick up where you left off instead, turn on Suspend VMs on quit in Settings."
                alert.addButton(withTitle: "Shut Down and Quit")
                alert.addButton(withTitle: "Cancel")
                guard alert.runModal() == .alertFirstButtonReturn else { return .terminateCancel }
            }
            Task { @MainActor in
                let failures = suspend ? await library.suspendAll() : await library.shutDownAll()
                if failures.isEmpty {
                    sender.reply(toApplicationShouldTerminate: true)
                } else {
                    sender.reply(toApplicationShouldTerminate: false)
                    let alert = NSAlert()
                    alert.alertStyle = .warning
                    alert.messageText = "Cove didn’t quit"
                    alert.informativeText = failures.map { "\($0.name): \($0.message)" }.joined(separator: "\n")
                        + "\n\nYour VMs are still running. Free up disk space or shut them down, then quit again."
                    alert.runModal()
                }
            }
            return .terminateLater
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        !(UserDefaults.standard.object(forKey: Pref.keepRunningInMenuBar) as? Bool ?? true)
    }

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
