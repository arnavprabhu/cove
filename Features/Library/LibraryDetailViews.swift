import AppKit
import SwiftUI

/// Detail pane when a VM is selected.
struct VMDetailView: View {
    let item: VMItem
    @Binding var alert: CoveAlert?

    @Environment(VMLibrary.self) private var library
    @Environment(\.openWindow) private var openWindow

    @State private var snapshotName = ""
    @State private var showSnapshotPrompt = false
    @State private var renameText = ""
    @State private var showRename = false

    private var newestSnapshots: [Snapshot] {
        Array(item.snapshots.prefix(3))
    }

    private var showsOverlay: Bool {
        switch item.state {
        case .stopped, .suspended, .error: true
        default: false
        }
    }

    private var overlayLabel: String {
        switch item.state {
        case .suspended, .saving: "Suspended"
        case .stopped, .error: "Stopped"
        default: ""
        }
    }

    private var diskFraction: Double {
        let cap = item.bundle.diskCapacity
        guard cap > 0 else { return 0 }
        return Double(item.bundle.diskAllocated) / Double(cap)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack(alignment: .top, spacing: 26) {
                    preview
                        .frame(width: 528, height: 330)
                    sideColumn
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                snapshotsStrip
            }
            .padding(.horizontal, 30)
            .padding(.vertical, 26)
        }
        .background(Theme.windowBackground)
        .toolbar { detailToolbar }
        .alert("Take Snapshot", isPresented: $showSnapshotPrompt) {
            TextField("Name", text: $snapshotName)
            Button("Take Snapshot") {
                let name = snapshotName.trimmingCharacters(in: .whitespacesAndNewlines)
                VMActions.takeSnapshot(item: item, name: name.isEmpty ? "Snapshot" : name, alert: $alert)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Give this snapshot a short name you will recognize later.")
        }
        .alert("Rename Virtual Machine", isPresented: $showRename) {
            TextField("Name", text: $renameText)
            Button("Rename") {
                VMActions.rename(item: item, to: renameText, library: library, alert: $alert)
            }
            .disabled(renameText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            Button("Cancel", role: .cancel) {}
        }
        .background {
            Button("") {
                alert = .confirmDelete(vmID: item.id, name: item.name, snapshotCount: item.snapshots.count, bytes: item.bundle.totalAllocated)
            }
            .keyboardShortcut(.delete, modifiers: .command)
            .opacity(0)
            .accessibilityHidden(true)
        }
        .onReceive(NotificationCenter.default.publisher(for: .coveTakeSnapshot)) { note in
            guard (note.object as? UUID) == item.id else { return }
            snapshotName = LibraryFormatting.snapshotDay(Date())
            showSnapshotPrompt = true
        }
    }

    // MARK: - Preview

    private var preview: some View {
        ZStack {
            VMPreview(image: item.thumbnail)
            if showsOverlay {
                Color.black.opacity(0.72)
                VStack(spacing: 12) {
                    Button {
                        VMActions.performPrimary(for: item, library: library,
                                                 openWindow: openWindow, alert: $alert)
                    } label: {
                        Image(systemName: "play.fill")
                            .font(.system(size: 26))
                            .foregroundStyle(.white)
                            .frame(width: 64, height: 64)
                            .background(Color.white.opacity(0.14), in: Circle())
                    }
                    .buttonStyle(.coveplain)
                    .accessibilityLabel(LibraryFormatting.primaryActionTitle(for: item))
                    Text(overlayLabel)
                        .font(Theme.Font.body)
                        .foregroundStyle(Color(hex: 0xD1D1D6))
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius))
    }

    // MARK: - Side column

    private var sideColumn: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                StatusDot(color: item.state.color)
                Text(LibraryFormatting.statusLine(for: item))
                    .font(Theme.Font.body)
                    .foregroundStyle(Color(light: 0x6E6E73, dark: 0xD1D1D6))
            }
            .accessibilityElement(children: .combine)

            HStack(spacing: 8) {
                Button(LibraryFormatting.primaryActionTitle(for: item)) {
                    VMActions.performPrimary(for: item, library: library,
                                             openWindow: openWindow, alert: $alert)
                }
                .buttonStyle(.coveprimary)
                .keyboardShortcut("r", modifiers: .command)

                if item.state.isLive {
                    Button("Shut Down") {
                        VMActions.shutDown(item: item, alert: $alert)
                    }
                    .buttonStyle(.covesecondary)
                }
            }

            if item.state == .installing, let job = item.installJob {
                VStack(alignment: .leading, spacing: 8) {
                    ProgressView(value: job.overallProgress)
                        .accessibilityLabel("Installation progress")
                        .accessibilityValue("\(Int((job.overallProgress * 100).rounded()))%")
                    Text(job.stage.title)
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.textTertiary)
                }
            }

            GroupedCard {
                SpecRow("Processors", "\(item.config.cpuCount) cores")
                CardDivider()
                SpecRow("Memory", Bytes.formatMemory(item.config.memoryBytes))
                CardDivider()
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Disk").foregroundStyle(Theme.textSecondary)
                        Spacer()
                        Text("\(Bytes.formatDisk(item.bundle.diskAllocated)) of \(Bytes.formatDisk(item.bundle.diskCapacity))")
                    }
                    .font(Theme.Font.body)
                    UsageBar(fraction: diskFraction)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                CardDivider()
                SpecRow("Display", item.config.display.label)
                CardDivider()
                SpecRow("Network", item.config.network.label)
            }

            RemoteAccessCard(item: item)
        }
    }

    // MARK: - Snapshots strip

    private var snapshotsStrip: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Snapshots")
                    .font(Theme.Font.sectionTitle)
                Spacer()
                Button("Show All") {
                    openWindow(id: WindowID.snapshots, value: item.id)
                }
                .buttonStyle(.coveplain)
                .foregroundStyle(Theme.link)
                .font(Theme.Font.body)
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 4), spacing: 12) {
                ForEach(newestSnapshots) { snap in
                    Button {
                        openWindow(id: WindowID.snapshots, value: item.id)
                    } label: {
                        VStack(alignment: .leading, spacing: 8) {
                            snapshotThumb(snap)
                                .frame(height: 70)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                            Text(snap.name)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Theme.textPrimary)
                                .lineLimit(1)
                            Text(LibraryFormatting.snapshotDay(snap.createdAt))
                                .font(Theme.Font.caption)
                                .foregroundStyle(Theme.textTertiary)
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Theme.cell, in: RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.cellBorder))
                    }
                    .buttonStyle(.coveplain)
                }

                Button {
                    snapshotName = LibraryFormatting.snapshotDay(Date())
                    showSnapshotPrompt = true
                } label: {
                    VStack(spacing: 6) {
                        Image(systemName: "plus")
                            .font(.system(size: 18, weight: .medium))
                        Text("Take Snapshot")
                            .font(Theme.Font.small)
                    }
                    .foregroundStyle(Theme.textSecondary)
                    .frame(maxWidth: .infinity, minHeight: 120)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(Theme.control, style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                    )
                }
                .buttonStyle(.coveplain)
                .disabled(item.state == .installing)
            }
        }
    }

    private func snapshotThumb(_ snap: Snapshot) -> some View {
        let url = SnapshotStore.thumbnailURL(snap, of: item)
        let image = NSImage(contentsOf: url)
        return VMPreview(image: image, cornerRadius: 6)
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var detailToolbar: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            VStack(alignment: .leading, spacing: 1) {
                Text(item.name)
                    .font(.system(size: 15, weight: .bold))
                Text(item.osDescription)
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.textTertiary)
            }
        }
        ToolbarItemGroup(placement: .primaryAction) {
            Button {
                VMActions.performPrimary(for: item, library: library,
                                         openWindow: openWindow, alert: $alert)
            } label: {
                Image(systemName: "play.fill")
            }
            .help(LibraryFormatting.primaryActionTitle(for: item))
            .accessibilityLabel(LibraryFormatting.primaryActionTitle(for: item))
            .keyboardShortcut("r")

            Button {
                openWindow(id: WindowID.snapshots, value: item.id)
            } label: {
                Image(systemName: "camera")
            }
            .help("Show Snapshots")
            .accessibilityLabel("Snapshots")
            .keyboardShortcut("s", modifiers: [.command, .option])

            Button {
                openWindow(id: WindowID.vmSettings, value: item.id)
            } label: {
                Image(systemName: "slider.horizontal.3")
            }
            .help("Settings")
            .accessibilityLabel("Settings")
            .keyboardShortcut("i")

            Menu {
                VMContextMenu(
                    item: item,
                    alert: $alert,
                    onRename: {
                        renameText = item.name
                        showRename = true
                    },
                    onTakeSnapshot: {
                        snapshotName = LibraryFormatting.snapshotDay(Date())
                        showSnapshotPrompt = true
                    },
                    onDelete: {
                        alert = .confirmDelete(vmID: item.id, name: item.name,
                                               snapshotCount: item.snapshots.count, bytes: item.bundle.totalAllocated)
                    }
                )
            } label: {
                Image(systemName: "ellipsis")
            }
            .help("More")
            .accessibilityLabel("More")
        }
    }
}

// MARK: - Restore Images / Shared Folders

struct RestoreImagesDetailView: View {
    @Environment(VMLibrary.self) private var library
    @State private var alert: CoveAlert?
    @State private var images: [URL] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header("Restore Images", subtitle: "\(images.count) cached")
            if images.isEmpty {
                emptyState("No restore images",
                           "Downloaded macOS installers appear here so you can reuse them.")
            } else {
                List {
                    ForEach(images, id: \.path) { url in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(url.lastPathComponent)
                                    .font(Theme.Font.body)
                                Text(Bytes.format(fileSize(url)))
                                    .font(Theme.Font.caption)
                                    .foregroundStyle(Theme.textTertiary)
                            }
                            Spacer()
                            Button("Show in Finder") {
                                NSWorkspace.shared.activateFileViewerSelecting([url])
                            }
                            .buttonStyle(.covesecondary)
                            Button("Delete", role: .destructive) {
                                trash(url)
                            }
                            .buttonStyle(SecondaryButtonStyle(destructive: true))
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
        .background(Theme.windowBackground)
        .coveAlert($alert)
        .onAppear { images = library.restoreImages }
    }

    private func fileSize(_ url: URL) -> UInt64 {
        ((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map { UInt64($0) }) ?? 0
    }

    private func trash(_ url: URL) {
        do {
            try library.deleteRestoreImage(url)
            images = library.restoreImages
        } catch {
            alert = .from(error)
        }
    }
}

struct SharedFoldersDetailView: View {
    @Environment(VMLibrary.self) private var library

    private var rows: [(path: String, vms: [String])] {
        LibraryFormatting.sharedFolderUsage(in: library)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header("Shared Folders", subtitle: "\(rows.count) across your VMs")
            if rows.isEmpty {
                emptyState("No shared folders",
                           "Add folders in a VM’s settings to share them with the guest.")
            } else {
                List {
                    ForEach(rows, id: \.path) { row in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(row.path)
                                .font(Theme.Font.body)
                                .textSelection(.enabled)
                            Text("Used by \(row.vms.joined(separator: ", "))")
                                .font(Theme.Font.caption)
                                .foregroundStyle(Theme.textTertiary)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
        .background(Theme.windowBackground)
    }
}

private func header(_ title: String, subtitle: String) -> some View {
    VStack(alignment: .leading, spacing: 2) {
        Text(title).font(Theme.Font.sectionTitle)
        Text(subtitle).font(Theme.Font.caption).foregroundStyle(Theme.textTertiary)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.horizontal, 30)
    .padding(.vertical, 18)
}

private func emptyState(_ title: String, _ message: String) -> some View {
    VStack(spacing: 8) {
        Spacer()
        Text(title).font(Theme.Font.sectionTitle)
        Text(message)
            .font(Theme.Font.body)
            .foregroundStyle(Theme.textSecondary)
            .multilineTextAlignment(.center)
        Spacer()
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .padding(40)
}
