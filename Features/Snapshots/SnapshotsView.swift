import AppKit
import SwiftUI

struct SnapshotsView: View {
    var vmID: UUID

    @Environment(VMLibrary.self) private var library
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismiss) private var dismiss

    @State private var selectedID: SnapshotSelection = .now
    @State private var alert: CoveAlert?
    @State private var showTakePrompt = false
    @State private var takeName = ""
    @State private var showRenamePrompt = false
    @State private var renameText = ""
    @State private var showClonePrompt = false
    @State private var cloneName = ""
    @State private var showRestoreConfirm = false
    @State private var showDeleteConfirm = false
    @State private var busy = false

    private var item: VMItem? { library.item(id: vmID) }

    private var snapshots: [Snapshot] { item?.snapshots ?? [] }

    private var totalSnapshotBytes: UInt64 {
        guard let item else { return 0 }
        return snapshots.reduce(0) { $0 + snapshotBytes(item, $1) }
    }

    var body: some View {
        Group {
            if let item {
                content(item)
            } else {
                ContentUnavailableView("Virtual Machine Missing", systemImage: "camera",
                                       description: Text("This virtual machine is no longer in the library."))
            }
        }
        .frame(minWidth: 900, minHeight: 560)
        .background(Theme.windowBackground)
        .coveAlert($alert)
        .focusedSceneValue(\.focusedVMID, vmID)
        .onAppear { ensureSelection() }
        .onChange(of: snapshots.map(\.id)) { _, _ in ensureSelection() }
        .onReceive(NotificationCenter.default.publisher(for: .coveTakeSnapshot)) { note in
            guard (note.object as? UUID) == vmID else { return }
            takeName = defaultName()
            showTakePrompt = true
        }
    }

    @ViewBuilder
    private func content(_ item: VMItem) -> some View {
        VStack(spacing: 0) {
            headerBar(item)
            HStack(spacing: 0) {
                timeline(item)
                    .frame(width: 400)
                Divider()
                detailPane(item)
            }
        }
        .alert("Take Snapshot", isPresented: $showTakePrompt) {
            TextField("Name", text: $takeName)
            Button("Take Snapshot") { takeSnapshot(item) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Give this snapshot a short name you will recognize later.")
        }
        .alert("Rename Snapshot", isPresented: $showRenamePrompt) {
            TextField("Name", text: $renameText)
            Button("Rename") { renameSelected(item) }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Clone to New VM", isPresented: $showClonePrompt) {
            TextField("Name", text: $cloneName)
            Button("Clone") { cloneSelected(item) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Creates a new virtual machine from this snapshot.")
        }
        .confirmationDialog("Restore this snapshot?", isPresented: $showRestoreConfirm, titleVisibility: .visible) {
            Button("Restore") { restoreSelected(item) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Restoring replaces the current state. Cove takes an automatic snapshot of “Now” first, so you can come back.")
        }
        .confirmationDialog("Delete this snapshot?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { deleteSelected(item) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This snapshot will be moved to the Trash. The virtual machine itself is not affected.")
        }
    }

    // MARK: - Header

    private func headerBar(_ item: VMItem) -> some View {
        HStack(spacing: 10) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(.borderless).pointingHandCursor()
            .help("Back")
            .accessibilityLabel("Back")

            VStack(alignment: .leading, spacing: 1) {
                Text("Snapshots")
                    .font(.system(size: 15, weight: .bold))
                Text("\(item.name) · \(snapshots.count) snapshot\(snapshots.count == 1 ? "" : "s") · \(Bytes.format(totalSnapshotBytes))")
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.textTertiary)
            }
            Spacer()
            Button {
                takeName = defaultName()
                showTakePrompt = true
            } label: {
                Label("Take Snapshot", systemImage: "camera")
            }
            .buttonStyle(.coveprimary)
            .disabled(item.state == .installing || busy)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Theme.toolbar)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.primary.opacity(0.08)).frame(height: 1)
        }
    }

    // MARK: - Timeline

    private func timeline(_ item: VMItem) -> some View {
        ZStack(alignment: .topLeading) {
            Rectangle()
                .fill(Theme.control)
                .frame(width: 2)
                .padding(.leading, 24)
                .padding(.top, 36)
                .padding(.bottom, 100)

            VStack(spacing: 4) {
                timelineRow(
                    title: "Now",
                    subtitle: nowSubtitle(item),
                    size: nil,
                    includesMemory: false,
                    automatic: false,
                    isNow: true,
                    selected: selectedID == .now
                ) {
                    selectedID = .now
                }

                ForEach(snapshots) { snap in
                    timelineRow(
                        title: snap.name,
                        subtitle: SnapshotsFormatting.fullDate(snap.createdAt),
                        size: Bytes.format(snapshotBytes(item, snap)),
                        includesMemory: snap.includesMemory,
                        automatic: snap.automatic,
                        isNow: false,
                        selected: selectedID == .snapshot(snap.id)
                    ) {
                        selectedID = .snapshot(snap.id)
                    }
                }

                Spacer(minLength: 12)

                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 14))
                        .accessibilityHidden(true)
                    Text("Snapshots are instant APFS clones, so each one only stores what changed after it.")
                        .font(Theme.Font.small)
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(12)
                .background(Theme.cell, in: RoundedRectangle(cornerRadius: 10))
                .accessibilityElement(children: .combine)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 20)
        }
        .background(Theme.windowBackground)
    }

    private func timelineRow(title: String, subtitle: String, size: String?, includesMemory: Bool,
                             automatic: Bool, isNow: Bool, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 14) {
                timelineNode(isNow: isNow, selected: selected)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(title)
                            .font(.system(size: 14, weight: .semibold))
                            .opacity(automatic && !selected ? 0.75 : 1)
                        if includesMemory {
                            Text("+ memory")
                                .font(.system(size: 10, weight: .semibold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 1)
                                .background(Color.primary.opacity(0.10), in: Capsule())
                                .foregroundStyle(Color(light: 0x6E6E73, dark: 0xD1D1D6))
                        }
                        if automatic {
                            Text("Automatic")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(selected ? Color(hex: 0xDCE9FF).opacity(0.8) : Theme.textTertiary)
                        }
                    }
                    Text(subtitle)
                        .font(Theme.Font.small)
                        .foregroundStyle(selected ? Color(hex: 0xDCE9FF) : Theme.textTertiary)
                }
                Spacer(minLength: 8)
                if let size {
                    Text(size)
                        .font(Theme.Font.small)
                        .foregroundStyle(selected ? Color(hex: 0xDCE9FF) : Theme.textTertiary)
                        .monospacedDigit()
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(selected ? Theme.sidebarSelection : Color.clear)
            )
            .foregroundStyle(Theme.textPrimary)
        }
        .buttonStyle(.coveplain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityLabel(timelineAccessibilityLabel(title: title, subtitle: subtitle, size: size,
                                                       includesMemory: includesMemory, automatic: automatic))
    }

    private func timelineAccessibilityLabel(title: String, subtitle: String, size: String?,
                                            includesMemory: Bool, automatic: Bool) -> String {
        var parts = [title, subtitle]
        if includesMemory { parts.append(String(localized: "includes memory")) }
        if automatic { parts.append(String(localized: "automatic")) }
        if let size { parts.append(size) }
        return parts.joined(separator: ", ")
    }

    private func timelineNode(isNow: Bool, selected: Bool) -> some View {
        ZStack {
            Circle()
                .fill(isNow ? Theme.running : Theme.windowBackground)
                .overlay(
                    Circle().strokeBorder(
                        isNow ? Theme.running : (selected ? Color.white : Color(hex: 0x636366)),
                        lineWidth: 2
                    )
                )
            Circle()
                .fill(isNow ? Color(hex: 0x0B3D1A) : (selected ? Color.white : Color(hex: 0x636366)))
                .frame(width: 8, height: 8)
        }
        .frame(width: 22, height: 22)
        .accessibilityHidden(true)
    }

    // MARK: - Detail

    @ViewBuilder
    private func detailPane(_ item: VMItem) -> some View {
        let selectedSnap = selectedSnapshot(in: item)
        VStack(alignment: .leading, spacing: 18) {
            ZStack(alignment: .bottomLeading) {
                VMPreview(image: detailThumbnail(item, snap: selectedSnap))
                    .frame(height: 340)
                Text(detailWhen(item, snap: selectedSnap))
                    .font(Theme.Font.caption)
                    .foregroundStyle(Color(hex: 0xD1D1D6))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.black.opacity(0.75), in: RoundedRectangle(cornerRadius: 8))
                    .padding(12)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Name")
                    .font(Theme.Font.small)
                    .foregroundStyle(Theme.textSecondary)
                Text(selectedSnap?.name ?? "Now")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10)
                    .frame(height: 32)
                    .background(Theme.field, in: RoundedRectangle(cornerRadius: 7))
                    .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Theme.control))
                Text(detailBlurb(item, snap: selectedSnap))
                    .font(Theme.Font.small)
                    .foregroundStyle(Theme.textTertiary)
                    .padding(.top, 4)
            }

            Spacer(minLength: 0)

            if selectedSnap != nil {
                if item.state.isLive {
                    warningBanner("Shut down or suspend this VM before restoring a snapshot.")
                } else {
                    warningBanner("Restoring replaces the current state. Cove takes an automatic snapshot of “Now” first, so you can come back.")
                }
            }

            HStack(spacing: 8) {
                if selectedSnap != nil {
                    Button("Delete") { showDeleteConfirm = true }
                        .buttonStyle(SecondaryButtonStyle(destructive: true))
                        .disabled(busy)
                }
                Spacer()
                if selectedSnap != nil {
                    Button("Rename…") {
                        renameText = selectedSnap?.name ?? ""
                        showRenamePrompt = true
                    }
                    .buttonStyle(.covesecondary)
                    .disabled(busy)

                    Button("Clone to New VM…") {
                        cloneName = library.uniqueName("\(item.name) Copy")
                        showClonePrompt = true
                    }
                    .buttonStyle(.covesecondary)
                    .disabled(busy)

                    Button("Restore") { showRestoreConfirm = true }
                        .buttonStyle(.coveprimary)
                        .disabled(item.state.isLive || busy)
                } else {
                    Button(LibraryFormatting.primaryActionTitle(for: item)) {
                        VMActions.performPrimary(for: item, library: library,
                                                 openWindow: openWindow, alert: $alert)
                    }
                    .buttonStyle(.coveprimary)
                }
            }
        }
        .padding(.horizontal, 36)
        .padding(.vertical, 28)
        .background(Theme.windowBackground)
    }

    private func warningBanner(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(Theme.warning)
                .accessibilityHidden(true)
            Text(text)
                .font(Theme.Font.small)
                .foregroundStyle(Color(light: 0x9A6700, dark: 0xFFD18A))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.warning.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.warning.opacity(0.3)))
        .accessibilityElement(children: .combine)
    }

    // MARK: - Actions

    private func takeSnapshot(_ item: VMItem) {
        let name = takeName.trimmingCharacters(in: .whitespacesAndNewlines)
        busy = true
        Task {
            defer { busy = false }
            do {
                let snap = try await SnapshotStore.take(item, name: name.isEmpty ? defaultName() : name)
                selectedID = .snapshot(snap.id)
            } catch {
                alert = .from(error)
            }
        }
    }

    private func restoreSelected(_ item: VMItem) {
        guard let snap = selectedSnapshot(in: item) else { return }
        busy = true
        Task {
            defer { busy = false }
            do {
                try await SnapshotStore.restore(item, to: snap, library: library)
                selectedID = .now
            } catch {
                alert = .from(error)
            }
        }
    }

    private func deleteSelected(_ item: VMItem) {
        guard let snap = selectedSnapshot(in: item) else { return }
        do {
            try SnapshotStore.delete(snap, of: item)
            selectedID = .now
        } catch {
            alert = .from(error)
        }
    }

    private func renameSelected(_ item: VMItem) {
        guard let snap = selectedSnapshot(in: item) else { return }
        let name = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        do {
            try SnapshotStore.rename(snap, of: item, to: name)
        } catch {
            alert = .from(error)
        }
    }

    private func cloneSelected(_ item: VMItem) {
        guard let snap = selectedSnapshot(in: item) else { return }
        let name = cloneName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        do {
            _ = try SnapshotStore.cloneToNewVM(snap, of: item, name: name, library: library)
        } catch {
            alert = .from(error)
        }
    }

    // MARK: - Helpers

    private func ensureSelection() {
        if case .snapshot(let id) = selectedID, snapshots.contains(where: { $0.id == id }) { return }
        if selectedID == .now { return }
        selectedID = .now
    }

    private func selectedSnapshot(in item: VMItem) -> Snapshot? {
        guard case .snapshot(let id) = selectedID else { return nil }
        return item.snapshots.first { $0.id == id }
    }

    private func nowSubtitle(_ item: VMItem) -> String {
        if item.state.isLive { return "Current state · running" }
        if item.state == .suspended { return "Current state · suspended" }
        return "Current state · stopped"
    }

    private func detailWhen(_ item: VMItem, snap: Snapshot?) -> String {
        if let snap { return SnapshotsFormatting.fullDate(snap.createdAt) }
        return nowSubtitle(item)
    }

    private func detailBlurb(_ item: VMItem, snap: Snapshot?) -> String {
        if let snap {
            if snap.automatic {
                return "Automatic snapshot · \(SnapshotsFormatting.detail(for: snap))"
            }
            return SnapshotsFormatting.detail(for: snap)
        }
        if let newest = item.snapshots.first {
            return "Everything since “\(newest.name)”."
        }
        return item.osDescription
    }

    private func detailThumbnail(_ item: VMItem, snap: Snapshot?) -> NSImage? {
        if let snap {
            return NSImage(contentsOf: SnapshotStore.thumbnailURL(snap, of: item)) ?? item.thumbnail
        }
        return item.thumbnail
    }

    private func snapshotBytes(_ item: VMItem, _ snap: Snapshot) -> UInt64 {
        FileClone.allocatedSize(of: item.bundle.snapshotsURL.appending(path: snap.id.uuidString))
    }

    private func defaultName() -> String {
        SnapshotsFormatting.fullDate(Date())
    }
}

private enum SnapshotSelection: Hashable {
    case now
    case snapshot(UUID)
}

private enum SnapshotsFormatting {
    private static let full: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        f.doesRelativeDateFormatting = true
        return f
    }()

    static func fullDate(_ date: Date) -> String { full.string(from: date) }

    static func detail(for snapshot: Snapshot) -> String {
        if snapshot.includesMemory {
            return "Taken while running · includes memory, so it resumes with apps open."
        }
        return "Taken while shut down · starts with a normal boot."
    }
}
