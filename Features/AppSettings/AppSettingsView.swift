import AppKit
import ServiceManagement
import SwiftUI

/// App-wide Settings scene (design/AppSettings.dc.html) — sidebar + detail panes.
struct AppSettingsView: View {
    private enum Pane: String, CaseIterable, Identifiable, Hashable {
        case general, defaults, storage, updates
        var id: String { rawValue }
        var title: String {
            switch self {
            case .general: "General"
            case .defaults: "New VM Defaults"
            case .storage: "Storage"
            case .updates: "Updates"
            }
        }
        var systemImage: String {
            switch self {
            case .general: "gearshape"
            case .defaults: "plus"
            case .storage: "internaldrive"
            case .updates: "arrow.down.circle"
            }
        }
        var iconColor: Color {
            switch self {
            case .general: Color(hex: 0x8E8E93)
            case .defaults: Theme.accent
            case .storage: Color(hex: 0x636366)
            case .updates: Color(hex: 0x30A14E)
            }
        }
    }

    @Environment(VMLibrary.self) private var library
    @State private var pane: Pane = .general
    @State private var alert: CoveAlert?
    @State private var confirmMove = false
    @State private var pendingMoveURL: URL?
    @State private var upToDateMessage: String?
    @State private var restoreListTick = 0

    @AppStorage(Pref.showMenuBarExtra) private var showMenuBarExtra = true
    @AppStorage(Pref.openAtLogin) private var openAtLogin = false
    @AppStorage(Pref.keepRunningInMenuBar) private var keepRunningInMenuBar = true
    @AppStorage(Pref.releaseShortcut) private var releaseShortcut = "ctrl-option"
    @AppStorage(Pref.defaultProfile) private var defaultProfile = ResourcePlanner.Profile.balanced.rawValue
    @AppStorage(Pref.defaultStartAfterInstall) private var defaultStartAfterInstall = true
    @AppStorage(Pref.defaultKeepRestoreImage) private var defaultKeepRestoreImage = true
    @AppStorage(Pref.snapshotAfterInstall) private var snapshotAfterInstall = true
    @AppStorage(Pref.keepRestoreImages) private var keepRestoreImages = true
    @AppStorage(Pref.checkForUpdates) private var checkForUpdates = true
    @AppStorage(Pref.suspendOnQuit) private var suspendOnQuit = true

    var body: some View {
        NavigationSplitView {
            List(Pane.allCases, selection: $pane) { item in
                Label {
                    Text(item.title)
                } icon: {
                    Image(systemName: item.systemImage)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 22, height: 22)
                        .background(item.iconColor, in: RoundedRectangle(cornerRadius: 6))
                }
                .tag(item)
                .listRowBackground(pane == item ? Theme.sidebarSelection : Color.clear)
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            .background(Theme.sidebar)
            .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 260)
            .accessibilityLabel("Settings")
        } detail: {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    switch pane {
                    case .general: generalPane
                    case .defaults: defaultsPane
                    case .storage: storagePane
                    case .updates: updatesPane
                    }
                }
                .frame(maxWidth: 620, alignment: .leading)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 26)
                .padding(.horizontal, 24)
            }
            .background(Theme.windowBackground)
            .navigationTitle(pane.title)
        }
        .frame(minWidth: 760, minHeight: 520)
        .frame(idealWidth: 760, idealHeight: 520)
        .coveAlert($alert)
        .alert("Move Cove Library?", isPresented: $confirmMove) {
            Button("Move", role: .destructive) {
                if let url = pendingMoveURL {
                    do {
                        try library.moveLibrary(to: url)
                    } catch {
                        alert = .from(error)
                    }
                }
                pendingMoveURL = nil
            }
            Button("Cancel", role: .cancel) { pendingMoveURL = nil }
        } message: {
            Text("All virtual machines must be stopped. Cove will move your VMs and restore images to the chosen folder.")
        }
        .onAppear { syncLoginStatus() }
    }

    // MARK: - General

    @ViewBuilder
    private var generalPane: some View {
        settingsBlock("Startup") {
            toggleRow("Open Cove at login", isOn: loginBinding)
            CardDivider()
            toggleRow("Show Cove in the menu bar", isOn: $showMenuBarExtra)
            CardDivider()
            toggleRow(
                "Keep running in the menu bar when windows close",
                subtitle: "Cove stays available from the menu bar extra",
                isOn: $keepRunningInMenuBar
            )
            CardDivider()
            toggleRow(
                "Suspend VMs on quit",
                subtitle: "Otherwise running VMs keep going until you stop them",
                isOn: $suspendOnQuit
            )
        }

        settingsBlock("Keyboard") {
            HStack(alignment: .center, spacing: 12) {
                Text("Release keyboard and pointer")
                    .foregroundStyle(Theme.textPrimary)
                Spacer(minLength: 12)
                Text(shortcutBadge)
                    .font(Theme.Font.mono)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Theme.control, in: RoundedRectangle(cornerRadius: 5))
                    .accessibilityLabel("Current shortcut \(shortcutBadge)")
                Picker("Release shortcut", selection: $releaseShortcut) {
                    Text("⌃ ⌥").tag("ctrl-option")
                    Text("⌃ ⌥ ⌘").tag("ctrl-option-cmd")
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .accessibilityLabel("Release keyboard and pointer shortcut")
            }
            .font(Theme.Font.body)
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
        }
    }

    // MARK: - Defaults

    @ViewBuilder
    private var defaultsPane: some View {
        let profile = ResourcePlanner.Profile(rawValue: defaultProfile) ?? .balanced
        let planner = HostInfo.planner(freeDiskAt: library.rootURL)
        let recommended = planner.recommended(profile)

        settingsBlock("Sizing for one-click VMs") {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Resource profile")
                    Text("How much of this Mac a new VM gets")
                        .font(Theme.Font.small)
                        .foregroundStyle(Theme.textTertiary)
                }
                Spacer(minLength: 12)
                Picker("Resource profile", selection: $defaultProfile) {
                    ForEach(ResourcePlanner.Profile.allCases) { p in
                        Text(profileMenuLabel(p)).tag(p.rawValue)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(maxWidth: 280)
            }
            .font(Theme.Font.body)
            .padding(.horizontal, 14)
            .padding(.vertical, 11)

            CardDivider()

            VStack(alignment: .leading, spacing: 8) {
                Text("Preview")
                    .font(Theme.Font.small)
                    .foregroundStyle(Theme.textTertiary)
                HStack(spacing: 16) {
                    previewStat("Processors", "\(recommended.cpu) cores")
                    previewStat("Memory", Bytes.formatMemory(recommended.memory))
                    previewStat("Disk", Bytes.formatDisk(recommended.disk))
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)

            CardDivider()
            toggleRow("Start after install", isOn: $defaultStartAfterInstall)
            CardDivider()
            toggleRow("Keep restore image after install", isOn: $defaultKeepRestoreImage)
            CardDivider()
            toggleRow(
                "Snapshot “Fresh install”",
                subtitle: "Take a snapshot right after installation finishes",
                isOn: $snapshotAfterInstall
            )
        }
    }

    // MARK: - Storage

    @ViewBuilder
    private var storagePane: some View {
        let allocated = library.totalAllocated
        let free = library.freeSpace
        let volumeTotal = max(allocated + free, 1)
        let _ = restoreListTick
        let images = library.restoreImages
        let imagesSize = images.reduce(UInt64(0)) { $0 + fileSize($1) }

        settingsBlock("Library") {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Cove Library")
                        Text(displayPath(library.rootURL))
                            .font(Theme.Font.mono)
                            .foregroundStyle(Theme.textTertiary)
                            .lineLimit(2)
                            .help(library.rootURL.path)
                    }
                    Spacer(minLength: 8)
                    Button("Show in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([library.rootURL])
                    }
                    .buttonStyle(.covesecondary)
                    Button("Move…") { chooseLibraryFolder() }
                        .buttonStyle(.covesecondary)
                }

                UsageBar(fraction: Double(allocated) / Double(volumeTotal))
                    .accessibilityLabel("Library disk usage")

                HStack(spacing: 16) {
                    legendDot(Theme.accent, "Used \(Bytes.format(allocated))")
                    legendDot(Theme.textTertiary, "Free \(Bytes.format(free))")
                    if imagesSize > 0 {
                        legendDot(Color(hex: 0xBF5AF2), "Restore images \(Bytes.format(imagesSize))")
                    }
                }
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.textSecondary)
            }
            .font(Theme.Font.body)
            .padding(14)
        }

        settingsBlock("Restore images") {
            if images.isEmpty {
                Text("No downloaded restore images")
                    .font(Theme.Font.body)
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 11)
                CardDivider()
            } else {
                ForEach(images, id: \.path) { url in
                    HStack(spacing: 12) {
                        Image(systemName: "doc.fill")
                            .foregroundStyle(Color(hex: 0xBF5AF2))
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(url.deletingPathExtension().lastPathComponent)
                            Text(Bytes.format(fileSize(url)))
                                .font(Theme.Font.small)
                                .foregroundStyle(Theme.textTertiary)
                        }
                        Spacer(minLength: 8)
                        Button("Remove") { removeRestoreImage(url) }
                            .buttonStyle(.covesecondary)
                            .accessibilityLabel("Remove \(url.lastPathComponent)")
                    }
                    .font(Theme.Font.body)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 11)
                    CardDivider()
                }
            }
            toggleRow("Keep downloaded restore images", isOn: $keepRestoreImages)
        }
    }

    // MARK: - Updates

    @ViewBuilder
    private var updatesPane: some View {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"

        settingsBlock("Cove") {
            HStack(alignment: .center, spacing: 12) {
                CoveLogo(size: 52)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Version \(version)")
                    Text(upToDateMessage ?? "Cove is up to date")
                        .font(Theme.Font.small)
                        .foregroundStyle(Theme.textTertiary)
                }
                Spacer(minLength: 12)
                Button("Check Now") {
                    upToDateMessage = "You’re up to date"
                }
                .buttonStyle(.covesecondary)
                .accessibilityLabel("Check for updates now")
            }
            .font(Theme.Font.body)
            .padding(.horizontal, 14)
            .padding(.vertical, 11)

            CardDivider()
            toggleRow("Automatically check for updates", isOn: $checkForUpdates)
        }
    }

    // MARK: - Helpers

    private var loginBinding: Binding<Bool> {
        Binding(
            get: { openAtLogin },
            set: { enabled in
                do {
                    if enabled {
                        try SMAppService.mainApp.register()
                    } else {
                        try SMAppService.mainApp.unregister()
                    }
                    openAtLogin = enabled
                } catch {
                    alert = .from(error)
                    syncLoginStatus()
                }
            }
        )
    }

    private var shortcutBadge: String {
        releaseShortcut == "ctrl-option-cmd" ? "⌃ ⌥ ⌘" : "⌃ ⌥"
    }

    private func syncLoginStatus() {
        openAtLogin = SMAppService.mainApp.status == .enabled
    }

    private func profileMenuLabel(_ profile: ResourcePlanner.Profile) -> String {
        switch profile {
        case .light: "Light — 2 cores, 4 GB"
        case .balanced: "Balanced — half the cores, a quarter of memory"
        case .performance: "Performance — most cores, half of memory"
        }
    }

    private func previewStat(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(Theme.Font.caption).foregroundStyle(Theme.textTertiary)
            Text(value).font(Theme.Font.body).foregroundStyle(Theme.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private func legendDot(_ color: Color, _ label: String) -> some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 8, height: 8)
            Text(label)
        }
    }

    private func settingsBlock<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionHeader(title: LocalizedStringKey(title))
                .padding(.leading, 4)
            GroupedCard { content() }
        }
    }

    private func toggleRow(_ title: String, subtitle: String? = nil, isOn: Binding<Bool>) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                if let subtitle {
                    Text(subtitle)
                        .font(Theme.Font.small)
                        .foregroundStyle(Theme.textTertiary)
                }
            }
            .foregroundStyle(Theme.textPrimary)
            Spacer(minLength: 12)
            Toggle(title, isOn: isOn)
                .labelsHidden()
                .toggleStyle(.switch)
        }
        .font(Theme.Font.body)
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }

    private func displayPath(_ url: URL) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let path = url.path
        if path.hasPrefix(home) {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }

    private func fileSize(_ url: URL) -> UInt64 {
        let v = try? url.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .fileSizeKey])
        if let alloc = v?.totalFileAllocatedSize { return UInt64(alloc) }
        if let size = v?.fileSize { return UInt64(size) }
        return 0
    }

    private func chooseLibraryFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.prompt = "Move"
        panel.message = "Choose a folder for the Cove library"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        pendingMoveURL = url
        confirmMove = true
    }

    private func removeRestoreImage(_ url: URL) {
        do {
            try library.deleteRestoreImage(url)
            restoreListTick += 1
        } catch {
            alert = .from(error)
        }
    }
}
