import SwiftUI

struct LibraryView: View {
    @Environment(VMLibrary.self) private var library
    @State private var selection: LibrarySelection?
    @State private var searchText = ""
    @State private var alert: CoveAlert?
    @State private var copiedSSH = false
    @State var diskSpace = DiskSpaceMonitor.shared

    var body: some View {
        NavigationSplitView {
            LibrarySidebar(selection: $selection, alert: $alert, searchText: searchText)
                .navigationSplitViewColumnWidth(min: 220, ideal: 248, max: 320)
        } detail: {
            detail.safeAreaInset(edge: .top, spacing: 0) {
                if diskSpace.level != .normal, let available = diskSpace.available {
                    LowDiskSpaceBanner(available: available).padding(16)
                }
            }
        }
        .navigationSplitViewStyle(.balanced)
        .searchable(text: $searchText, placement: .toolbar, prompt: "Search")
        .background(Theme.windowBackground)
        .coveAlert($alert)
        .focusedSceneValue(\.focusedVMID, focusedVMID)
        .onAppear { ensureSelection() }
        .onChange(of: library.items.map(\.id)) { _, _ in ensureSelection() }
        .onReceive(NotificationCenter.default.publisher(for: .coveCopiedSSHCommand)) { _ in copiedSSH = true }
        .overlay(alignment: .bottom) {
            if copiedSSH {
                Label("Copied SSH command", systemImage: "checkmark.circle.fill")
                    .font(Theme.Font.body).foregroundStyle(Theme.textPrimary)
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(Theme.cell, in: Capsule())
                    .overlay(Capsule().strokeBorder(Theme.cellBorder))
                    .padding(.bottom, 20).allowsHitTesting(false)
            }
        }
        .task(id: copiedSSH) {
            guard copiedSSH else { return }
            try? await Task.sleep(for: .seconds(2))
            if !Task.isCancelled { copiedSSH = false }
        }
    }

    private var focusedVMID: UUID? {
        if case .vm(let id) = selection { return id }
        return nil
    }

    @ViewBuilder
    private var detail: some View {
        switch selection {
        case .vm(let id):
            if let item = library.item(id: id) {
                VMDetailView(item: item, alert: $alert)
            } else {
                ContentUnavailableView("Virtual Machine Missing", systemImage: "macwindow",
                                       description: Text("This virtual machine is no longer in the library."))
            }
        case .restoreImages:
            RestoreImagesDetailView()
        case .sharedFolders:
            SharedFoldersDetailView()
        case nil:
            ContentUnavailableView("Select a Virtual Machine", systemImage: "macwindow",
                                   description: Text("Choose a VM from the sidebar to see its details."))
        }
    }

    private func ensureSelection() {
        if case .vm(let id) = selection, library.item(id: id) != nil { return }
        if selection == .restoreImages || selection == .sharedFolders { return }
        if let first = library.items.first {
            selection = .vm(first.id)
        } else {
            selection = nil
        }
    }
}
