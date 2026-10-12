import SwiftUI

struct LibraryView: View {
    @Environment(VMLibrary.self) private var library
    @State private var selection: LibrarySelection?
    @State private var searchText = ""
    @State private var alert: CoveAlert?

    var body: some View {
        NavigationSplitView {
            LibrarySidebar(selection: $selection, alert: $alert, searchText: searchText)
                .navigationSplitViewColumnWidth(min: 220, ideal: 248, max: 320)
        } detail: {
            detail
        }
        .navigationSplitViewStyle(.balanced)
        .searchable(text: $searchText, placement: .toolbar, prompt: "Search")
        .background(Theme.windowBackground)
        .coveAlert($alert)
        .focusedSceneValue(\.focusedVMID, focusedVMID)
        .onAppear { ensureSelection() }
        .onChange(of: library.items.map(\.id)) { _, _ in ensureSelection() }
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
