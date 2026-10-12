import AppKit
import SwiftUI

/// The step state also gates commands, so a stale probe never makes a stopped VM look ready.
struct RemoteAccessProgress {
    var enabled: Bool
    var isLive: Bool
    var needsRestart: Bool
    var status: GuestAccessMonitor.Status
    var hostInstalled: Bool

    var ready: Bool { enabled && isLive && !needsRestart && status.sshReachable && status.ip != nil && status.guestUser != nil }
    var completed: [Bool] {
        [enabled && !needsRestart, enabled && isLive && !needsRestart,
         enabled && status.guestUser != nil, ready, enabled && hostInstalled]
    }
    var currentStep: Int { (completed.firstIndex(of: false) ?? 4) + 1 }
}

@MainActor
extension VMItem {
    var remoteAccessProgress: RemoteAccessProgress {
        RemoteAccessProgress(enabled: config.access.enabled, isLive: state.isLive,
                             needsRestart: config.access.enabled && session?.startedHardware.remoteAccessEnabled == false,
                             status: GuestAccessMonitor.shared.status(for: id),
                             hostInstalled: GuestAccessMonitor.shared.hostInstalled)
    }

    func remoteSSHCommand(library: VMLibrary) -> String {
        let status = GuestAccessMonitor.shared.status(for: id)
        return GuestAccess.sshCommand(alias: GuestAccess.alias(for: name), user: status.guestUser,
                                     ip: status.ip, keyPath: GuestAccess.keyURL(in: library).path,
                                     hostInstalled: GuestAccessMonitor.shared.hostInstalled)
    }
}

/// Shared copy control for commands and addresses, with a short, accessible confirmation.
struct RemoteCopyButton: View {
    var text: String
    var label = "Copy"
    @State private var copied = false

    var body: some View {
        Button(copied ? "Copied" : label) {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            copied = true
        }
        .buttonStyle(.covesecondary)
        .accessibilityLabel(copied ? "Copied" : label)
        .task(id: copied) {
            guard copied else { return }
            try? await Task.sleep(for: .seconds(2))
            if !Task.isCancelled { copied = false }
        }
    }
}

struct RemoteAccessView: View {
    var vmID: UUID
    @Environment(VMLibrary.self) private var library
    @Environment(\.openWindow) private var openWindow
    @State private var monitor = GuestAccessMonitor.shared
    @State private var alert: CoveAlert?
    @State private var expandedStep: Int?
    @State private var busy = false
    @State private var rerunSetup = false
    @State private var setupDateBeforeChange: Date?
    @State private var snapshotTaken = false

    #if DEBUG
    var sampleProgress: RemoteAccessProgress?
    #endif

    init(vmID: UUID) { self.vmID = vmID }

    #if DEBUG
    init(vmID: UUID, sampleProgress: RemoteAccessProgress, expandedStep: Int? = nil) {
        self.vmID = vmID
        self.sampleProgress = sampleProgress
        _expandedStep = State(initialValue: expandedStep)
    }
    #endif

    private let titles = ["Turn on SSH access", "Start the VM and finish Setup Assistant",
                          "Run the setup command in the VM", "Connect from your Mac",
                          "Let Terminal and your agents use it"]

    private func progress(_ item: VMItem) -> RemoteAccessProgress {
        #if DEBUG
        if let sampleProgress { return sampleProgress }
        #endif
        return item.remoteAccessProgress
    }

    var body: some View {
        Group {
            if let item = library.item(id: vmID) {
                walkthrough(item, progress: progress(item))
            } else {
                ContentUnavailableView("Virtual machine unavailable", systemImage: "macwindow",
                                       description: Text("This virtual machine is no longer in the library."))
            }
        }
        .frame(minWidth: 700, minHeight: 600)
        .background(Theme.windowBackground)
        .foregroundStyle(Theme.textPrimary)
        .font(Theme.Font.body)
        .navigationTitle("SSH & Agent Access")
        .focusedSceneValue(\.focusedVMID, vmID)
        .coveAlert($alert)
        .onAppear { refresh() }
    }

    private func walkthrough(_ item: VMItem, progress: RemoteAccessProgress) -> some View {
        VStack(spacing: 0) {
            header(item, progress: progress)
            CardDivider()
            ScrollView {
                VStack(spacing: 10) {
                    ForEach(1...5, id: \.self) { step in
                        stepCard(step, item: item, progress: progress)
                    }
                }
                .padding(24)
            }
        }
        .onChange(of: progress.currentStep) { _, _ in expandedStep = nil }
        .onChange(of: item.state) { _, _ in refresh() }
        .onChange(of: progress.status.lastChecked) { _, _ in
            if rerunSetup, setupDate(item) != setupDateBeforeChange { rerunSetup = false }
        }
    }

    private func header(_ item: VMItem, progress: RemoteAccessProgress) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(item.name).font(Theme.Font.title).lineLimit(1)
                Text(GuestAccess.alias(for: item.name))
                    .font(Theme.Font.mono).foregroundStyle(Theme.textSecondary)
                    .lineLimit(1).truncationMode(.middle)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(Theme.control, in: Capsule())
                Spacer(minLength: 12)
                HStack(spacing: 6) {
                    StatusDot(color: progress.ready ? Theme.running : progress.enabled ? Theme.warning : Theme.stopped)
                    Text(progress.ready ? "Ready" : progress.enabled ? "Needs setup" : "Off")
                        .foregroundStyle(Theme.textSecondary)
                }
                .accessibilityElement(children: .combine)
            }
            Text("Connect from your Mac, then give your agents a Mac of their own to work in.")
                .foregroundStyle(Theme.textSecondary)
        }
        .padding(24)
    }

    private func stepCard(_ step: Int, item: VMItem, progress: RemoteAccessProgress) -> some View {
        let done = progress.completed[step - 1]
        let current = step == progress.currentStep
        let expanded = step == (expandedStep ?? progress.currentStep)
        return GroupedCard {
            Button { expandedStep = expanded ? 0 : step } label: {
                HStack(spacing: 12) {
                    ZStack {
                        Circle().fill(done ? Theme.running : current ? Theme.accentFill : Theme.control)
                        if done {
                            Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)).foregroundStyle(.white)
                        } else {
                            Text("\(step)").font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(current ? .white : Theme.textSecondary)
                        }
                    }
                    .frame(width: 26, height: 26).accessibilityHidden(true)
                    Text("Step \(step) · \(titles[step - 1])").fontWeight(.semibold)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(done ? "Done" : current ? "Next" : "Pending")
                        .font(Theme.Font.caption).foregroundStyle(done ? Theme.running : Theme.textTertiary)
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10, weight: .semibold)).foregroundStyle(Theme.textTertiary)
                }
                .padding(14)
            }
            .buttonStyle(.coveplain)
            .accessibilityLabel("Step \(step), \(titles[step - 1]), \(done ? "complete" : current ? "current" : "pending")")
            .accessibilityValue(expanded ? "Expanded" : "Collapsed")
            if expanded {
                CardDivider()
                VStack(alignment: .leading, spacing: 12) {
                    stepContent(step, item: item, progress: progress)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
            }
        }
    }

    @ViewBuilder
    private func stepContent(_ step: Int, item: VMItem, progress: RemoteAccessProgress) -> some View {
        switch step {
        case 1:
            Toggle("SSH & agent access", isOn: accessBinding(item, sudo: false))
                .toggleStyle(.switch).disabled(busy || item.installJob != nil)
            note("Adds a small “Cove” shared folder with a setup script and Cove’s SSH key.")
            if progress.needsRestart {
                HStack(spacing: 12) {
                    Label("Restart the VM to connect the Cove folder", systemImage: "arrow.clockwise")
                        .foregroundStyle(Theme.warning)
                    Spacer(minLength: 0)
                    Button("Restart") { start(item, restart: true) }
                        .buttonStyle(.covesecondary).disabled(busy || !canAct(item))
                }
                .padding(12).background(Theme.warning.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
                note("Restart closes the current session. Save your work in the VM first.")
            } else if !progress.isLive {
                note(progress.enabled ? "The Cove folder connects on the next start." : "Turn this on before starting the VM to connect the Cove folder.")
            } else if !item.config.access.enabled {
                note("The Cove folder is removed after the VM shuts down.")
            }
        case 2:
            note("Start the VM, finish macOS Setup Assistant, and sign in to your account inside the VM.")
            Button(progress.isLive ? "Open VM Window" : item.state == .suspended ? "Resume VM" : "Start VM") {
                if progress.isLive { openWindow(id: WindowID.console, value: item.id) }
                else { start(item) }
            }
            .buttonStyle(.coveprimary).disabled(busy || !canAct(item) || !progress.enabled)
            if progress.isLive { note("The VM is live. Finish Setup Assistant before continuing.") }
        case 3:
            Text("Open Terminal in the VM and type:")
            commandBox(GuestAccess.setupCommand, large: true)
            Label("You must type this inside the VM. macOS VMs don’t support clipboard sharing.", systemImage: "keyboard")
                .font(Theme.Font.small).foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            note("Press Return, then enter your VM account password when macOS asks.")
            Toggle("Let agents use sudo without a password", isOn: accessBinding(item, sudo: true))
                .toggleStyle(.checkbox).disabled(busy || !progress.enabled)
            note("Allows agents to make administrator changes inside this VM.")
            if let user = progress.status.guestUser {
                Label { Text("Set up for user **\(user)**") } icon: { Image(systemName: "checkmark.circle.fill") }
                    .foregroundStyle(Theme.running)
                note(rerunSetup ? "Your sudo choice changed. Re-run the command in the VM to apply it." : "If you change the sudo choice, re-run this command in the VM.")
            }
        case 4:
            connectionRows(progress)
            commandBox(sshCommand(item, progress: progress))
            Button("Open in Terminal") { openTerminal(item, progress: progress) }
                .buttonStyle(.coveprimary).disabled(!progress.ready)
            if !progress.hostInstalled { note("Until Step 5 is complete, use the full command above for Cove’s SSH key.") }
            if item.config.network == .none { note("Networking is disconnected. Enable Shared (NAT) in VM Settings → Network.") }
        default:
            if progress.hostInstalled {
                Label("Cove is added to your Mac’s SSH config", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(Theme.running)
                Text("`ssh \(GuestAccess.alias(for: item.name))` works in Terminal and in your agents while this VM is running.")
            } else {
                note("Make the short SSH name work from Terminal, Claude Code, Codex, and other agents on your Mac.")
                Button("Add Cove to ~/.ssh/config…") { installHostSSH() }
                    .buttonStyle(.coveprimary).disabled(busy || !progress.enabled)
                note("Choose your .ssh folder or home folder. Cove adds an Include line and its key under ~/.ssh/cove/.")
            }
            CardDivider()
            HStack {
                Text("Agent instructions").fontWeight(.semibold)
                Spacer()
                RemoteCopyButton(text: agentInstructions(item, progress: progress), label: "Copy Instructions")
                    .disabled(!progress.ready || !progress.hostInstalled || rerunSetup)
            }
            ScrollView {
                Text(agentInstructions(item, progress: progress)).font(Theme.Font.mono)
                    .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding(12)
            }
            .frame(height: 160)
            .background(Theme.field, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.cellBorder))
            note("Paste into CLAUDE.md or AGENTS.md in your project.")
            if !progress.hostInstalled { note("Complete host setup before using these instructions.") }
            if rerunSetup { note("Re-run setup in the VM, then check Step 3 before copying instructions.") }
            CardDivider()
            HStack(alignment: .center, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Before letting an agent loose").fontWeight(.semibold)
                    note("Restore it from Snapshots to reset the VM. Shared folders on your Mac aren’t reset.")
                }
                Spacer(minLength: 0)
                Button(snapshotTaken ? "Snapshot Taken" : "Take Snapshot") {
                    run(item) {
                        _ = try await SnapshotStore.take(item, name: "Before agent run")
                        snapshotTaken = true
                    }
                }
                .buttonStyle(.covesecondary).disabled(busy || !canAct(item))
            }
        }
    }

    private func connectionRows(_ progress: RemoteAccessProgress) -> some View {
        VStack(spacing: 10) {
            HStack {
                Text("IP address").foregroundStyle(Theme.textSecondary)
                Spacer()
                Text(progress.status.ip ?? "Waiting for an address…").font(Theme.Font.mono)
                if let ip = progress.status.ip { RemoteCopyButton(text: ip, label: "Copy IP") }
            }
            HStack(alignment: .firstTextBaseline) {
                Text("SSH").foregroundStyle(Theme.textSecondary)
                Spacer()
                StatusDot(color: progress.ready ? Theme.running : Theme.warning)
                Text(progress.ready ? "Reachable" : "Not reachable yet — Remote Login may be off")
                    .foregroundStyle(progress.ready ? Theme.running : Theme.warning)
            }
            HStack {
                Text("User").foregroundStyle(Theme.textSecondary)
                Spacer()
                Text(progress.status.guestUser ?? "Waiting for setup…").font(Theme.Font.mono)
            }
        }
    }

    private func commandBox(_ command: String, large: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(command).font(.system(size: large ? 17 : 13, design: .monospaced))
                .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            RemoteCopyButton(text: command, label: "Copy Command")
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(14).background(Theme.field, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.cellBorder))
    }

    private func note(_ text: String) -> some View {
        Text(text).foregroundStyle(Theme.textSecondary).fixedSize(horizontal: false, vertical: true)
    }

    private func sshCommand(_ item: VMItem, progress: RemoteAccessProgress) -> String {
        GuestAccess.sshCommand(alias: GuestAccess.alias(for: item.name), user: progress.status.guestUser,
                               ip: progress.status.ip, keyPath: GuestAccess.keyURL(in: library).path,
                               hostInstalled: progress.hostInstalled)
    }

    private func agentInstructions(_ item: VMItem, progress: RemoteAccessProgress) -> String {
        GuestAccess.agentInstructions(vmName: item.name, alias: GuestAccess.alias(for: item.name),
                                      osDescription: item.osDescription, user: progress.status.guestUser,
                                      passwordlessSudo: item.config.access.passwordlessSudo, shares: item.config.shares)
    }

    private func accessBinding(_ item: VMItem, sudo: Bool) -> Binding<Bool> {
        Binding(get: { sudo ? item.config.access.passwordlessSudo : item.config.access.enabled }, set: { value in
            var config = item.config
            if sudo { config.access.passwordlessSudo = value } else { config.access.enabled = value }
            do {
                try library.update(item, config: config)
                if config.access.enabled { try GuestAccess.prepareGuestFolder(for: item, library: library) }
                if sudo, monitor.status(for: item.id).guestUser != nil {
                    setupDateBeforeChange = setupDate(item)
                    rerunSetup = true
                }
                GuestAccess.refreshHostConfig(library: library)
                refresh()
            } catch { alert = .from(error) }
        })
    }

    private func setupDate(_ item: VMItem) -> Date? {
        let path = item.bundle.guestFolderURL.appending(path: "status/configured").path
        return (try? FileManager.default.attributesOfItem(atPath: path))?[.modificationDate] as? Date
    }

    private func canAct(_ item: VMItem) -> Bool {
        item.installJob == nil && item.state != .starting && item.state != .saving && item.state != .stopping
    }

    private func start(_ item: VMItem, restart: Bool = false) {
        run(item) {
            if restart { try await library.restart(item) } else { try await library.start(item) }
            openWindow(id: WindowID.console, value: item.id)
        }
    }

    private func run(_ item: VMItem, action: @escaping () async throws -> Void) {
        busy = true
        Task { @MainActor in
            defer { busy = false; refresh() }
            do { try await action() } catch { alert = .from(error, starting: item) }
        }
    }

    private func installHostSSH() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.showsHiddenFiles = true
        if let home = NSHomeDirectoryForUser(NSUserName()) {
            panel.directoryURL = URL(fileURLWithPath: home).appending(path: ".ssh", directoryHint: .isDirectory)
        }
        panel.prompt = "Add Cove"
        panel.message = "Choose ~/.ssh or your home folder. Cove adds an Include ~/.ssh/cove/config line to ~/.ssh/config and installs its SSH key under ~/.ssh/cove/."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try GuestAccess.installHostSSH(pickedFolder: url, library: library)
            refresh()
        } catch { alert = .from(error) }
    }

    private func openTerminal(_ item: VMItem, progress: RemoteAccessProgress) {
        var url = URLComponents()
        url.scheme = "ssh"
        url.host = progress.hostInstalled ? GuestAccess.alias(for: item.name) : progress.status.ip
        if !progress.hostInstalled { url.user = progress.status.guestUser }
        guard let target = url.url, NSWorkspace.shared.open(target) else {
            alert = .error(title: "Couldn’t open Terminal", message: "Copy the SSH command and run it in Terminal on your Mac.")
            return
        }
    }

    private func refresh() {
        #if DEBUG
        if sampleProgress != nil { return }
        #endif
        monitor.refresh(library: library)
    }
}
