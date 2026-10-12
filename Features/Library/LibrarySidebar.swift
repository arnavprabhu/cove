import AppKit
import SwiftUI

struct LibrarySidebar: View {
    @Binding var selection: LibrarySelection?
    @Binding var alert: CoveAlert?
    var searchText: String

    @Environment(VMLibrary.self) private var library
    @State private var renameTarget: VMItem?
    @State private var renameText = ""
    @State private var snapshotTarget: VMItem?
    @State private var snapshotName = ""

    private var filteredVMs: [VMItem] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return library.items }
        return library.items.filter { $0.name.localizedCaseInsensitiveContains(q) }
    }

    private var sharedFolderCount: Int {
        LibraryFormatting.sharedFolderUsage(in: library).count
    }

    var body: some View {
        VStack(spacing: 0) {
            List(selection: $selection) {
                // Installs still downloading have no VM yet; once they do, the VM's own row shows progress.
                let pending = library.activeInstallJobs.filter { job in job.vmID.flatMap { library.item(id: $0) } == nil }
                if !pending.isEmpty {
                    Section {
                        ForEach(pending) { job in InstallActivityView(job: job, style: .row) }
                    } header: {
                        Text("Installing")
                    }
                }
                Section {
                    ForEach(filteredVMs) { item in
                        VMSidebarRow(item: item, selected: selection == .vm(item.id))
                            .tag(LibrarySelection.vm(item.id))
                            .listRowBackground(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(selection == .vm(item.id) ? Theme.sidebarSelection : Color.clear)
                                    .padding(.horizontal, 4)
                            )
                            .contextMenu {
                                VMContextMenu(
                                    item: item,
                                    alert: $alert,
                                    onRename: {
                                        renameText = item.name
                                        renameTarget = item
                                    },
                                    onTakeSnapshot: {
                                        snapshotName = defaultSnapshotName()
                                        snapshotTarget = item
                                    },
                                    onDelete: {
                                        alert = .confirmDelete(vmID: item.id, name: item.name,
                                                               snapshotCount: item.snapshots.count, bytes: item.bundle.totalAllocated)
                                    }
                                )
                            }
                    }
                } header: {
                    Text("Virtual Machines")
                }

                Section {
                    Label {
                        HStack {
                            Text("Restore Images")
                            Spacer()
                            Text("\(library.restoreImages.count)")
                                .foregroundStyle(Theme.textTertiary)
                        }
                    } icon: {
                        Image(systemName: "doc.badge.gearshape")
                            .foregroundStyle(Theme.accent)
                    }
                    .tag(LibrarySelection.restoreImages)

                    Label {
                        HStack {
                            Text("Shared Folders")
                            Spacer()
                            Text("\(sharedFolderCount)")
                                .foregroundStyle(Theme.textTertiary)
                        }
                    } icon: {
                        Image(systemName: "folder")
                            .foregroundStyle(Theme.accent)
                    }
                    .tag(LibrarySelection.sharedFolders)
                } header: {
                    Text("Library")
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)

            libraryUsageCard
                .padding(.horizontal, 10)
                .padding(.bottom, 10)

            Button {
                CoveActions.newVirtualMachine()
            } label: {
                Label("New Virtual Machine", systemImage: "plus.circle")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.coveplain)
            .padding(.horizontal, 10)
            .padding(.bottom, 12)
        }
        .background(Theme.sidebar)
        .alert("Rename Virtual Machine", isPresented: Binding(
            get: { renameTarget != nil },
            set: { if !$0 { renameTarget = nil } }
        )) {
            TextField("Name", text: $renameText)
            Button("Rename") {
                if let item = renameTarget {
                    VMActions.rename(item: item, to: renameText, library: library, alert: $alert)
                }
                renameTarget = nil
            }
            .disabled(renameText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            Button("Cancel", role: .cancel) { renameTarget = nil }
        } message: {
            Text("Enter a new name for this virtual machine.")
        }
        .alert("Take Snapshot", isPresented: Binding(
            get: { snapshotTarget != nil },
            set: { if !$0 { snapshotTarget = nil } }
        )) {
            TextField("Name", text: $snapshotName)
            Button("Take Snapshot") {
                if let item = snapshotTarget {
                    let name = snapshotName.trimmingCharacters(in: .whitespacesAndNewlines)
                    VMActions.takeSnapshot(item: item, name: name.isEmpty ? defaultSnapshotName() : name, alert: $alert)
                }
                snapshotTarget = nil
            }
            Button("Cancel", role: .cancel) { snapshotTarget = nil }
        } message: {
            Text("Give this snapshot a short name you will recognize later.")
        }
    }

    private var libraryUsageCard: some View {
        let used = library.totalAllocated
        let free = library.freeSpace
        let total = used + free
        let fraction = total > 0 ? Double(used) / Double(total) : 0
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Cove Library")
                Spacer()
                Text("\(Bytes.format(used)) used")
            }
            .font(Theme.Font.caption)
            .foregroundStyle(Theme.textSecondary)
            UsageBar(fraction: fraction, tint: Theme.textTertiary)
        }
        .padding(10)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Cove Library, \(Bytes.format(used)) used")
    }

    private func defaultSnapshotName() -> String {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f.string(from: Date())
    }
}

private struct VMSidebarRow: View {
    let item: VMItem
    var selected: Bool

    var body: some View {
        HStack(spacing: 10) {
            VMGlyph(isLive: item.state.isLive || item.state == .running, selected: selected)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.name)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(selected ? Color.white : Theme.textPrimary)
                    .lineLimit(1)
                HStack(spacing: 5) {
                    StatusDot(color: item.state.color, size: 6)
                    Text(LibraryFormatting.sidebarStatus(for: item))
                        .font(Theme.Font.caption)
                        .foregroundStyle(selected ? Color(hex: 0xDCE9FF) : Theme.textTertiary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(item.name), \(LibraryFormatting.sidebarStatus(for: item))")
    }
}
