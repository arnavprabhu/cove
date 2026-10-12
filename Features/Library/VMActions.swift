import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Shared start / window / destructive actions used by the library sidebar and detail.
@MainActor
enum VMActions {
    static func performPrimary(for item: VMItem, library: VMLibrary, openWindow: OpenWindowAction,
                               alert: Binding<CoveAlert?>) {
        switch item.state {
        case .running, .starting, .paused, .saving, .stopping:
            openWindow(id: WindowID.console, value: item.id)
        case .installing:
            if let job = item.installJob {
                openWindow(id: WindowID.install, value: job.id)
            }
        case .suspended, .stopped, .error:
            Task {
                do {
                    try await library.start(item)
                    openWindow(id: WindowID.console, value: item.id)
                } catch {
                    alert.wrappedValue = .from(error, starting: item)
                }
            }
        }
    }

    static func start(item: VMItem, library: VMLibrary, recovery: Bool = false,
                      openWindow: OpenWindowAction, alert: Binding<CoveAlert?>) {
        Task {
            do {
                try await library.start(item, recovery: recovery)
                openWindow(id: WindowID.console, value: item.id)
            } catch {
                alert.wrappedValue = .from(error, starting: item)
            }
        }
    }

    static func suspend(item: VMItem, alert: Binding<CoveAlert?>) {
        guard let session = item.session else { return }
        Task {
            do { try await session.suspend() }
            catch { alert.wrappedValue = .from(error) }
        }
    }

    static func shutDown(item: VMItem, alert: Binding<CoveAlert?>) {
        guard let session = item.session else { return }
        do { try session.requestShutDown() }
        catch { alert.wrappedValue = .from(error) }
    }

    static func showInFinder(_ item: VMItem) {
        NSWorkspace.shared.activateFileViewerSelecting([item.bundle.url])
    }

    static func clone(item: VMItem, library: VMLibrary, alert: Binding<CoveAlert?>) {
        do {
            _ = try library.clone(item)
        } catch {
            alert.wrappedValue = .from(error)
        }
    }

    static func export(item: VMItem, library: VMLibrary, alert: Binding<CoveAlert?>) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: VMBundle.pathExtension) ?? .package]
        panel.nameFieldStringValue = "\(item.name).\(VMBundle.pathExtension)"
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try library.export(item, to: url)
        } catch {
            alert.wrappedValue = .from(error)
        }
    }

    static func rename(item: VMItem, to name: String, library: VMLibrary, alert: Binding<CoveAlert?>) {
        var config = item.config
        config.name = name
        do {
            try library.update(item, config: config)
        } catch {
            alert.wrappedValue = .from(error)
        }
    }

    static func takeSnapshot(item: VMItem, name: String, alert: Binding<CoveAlert?>) {
        Task {
            do { _ = try await SnapshotStore.take(item, name: name) }
            catch { alert.wrappedValue = .from(error) }
        }
    }
}

/// Context menu for a VM in the sidebar.
struct VMContextMenu: View {
    let item: VMItem
    @Binding var alert: CoveAlert?
    var onRename: () -> Void
    var onTakeSnapshot: () -> Void
    var onDelete: () -> Void

    @Environment(VMLibrary.self) private var library
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Group {
            if item.state == .installing {
                Button("Show Progress") {
                    if let job = item.installJob {
                        openWindow(id: WindowID.install, value: job.id)
                    }
                }
            } else if item.state.isLive {
                Button("Show Window") {
                    openWindow(id: WindowID.console, value: item.id)
                }
                Button("Suspend") {
                    VMActions.suspend(item: item, alert: $alert)
                }
                Button("Shut Down") {
                    VMActions.shutDown(item: item, alert: $alert)
                }
            } else if item.state == .suspended {
                Button("Resume") {
                    VMActions.start(item: item, library: library, openWindow: openWindow, alert: $alert)
                }
            } else {
                Button("Start") {
                    VMActions.start(item: item, library: library, openWindow: openWindow, alert: $alert)
                }
                Button("Start in Recovery") {
                    VMActions.start(item: item, library: library, recovery: true,
                                    openWindow: openWindow, alert: $alert)
                }
            }

            Divider()

            Button("SSH & Agent Access…") {
                openWindow(id: WindowID.remoteAccess, value: item.id)
            }
            Button("Copy SSH Command") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(item.remoteSSHCommand(library: library), forType: .string)
                NotificationCenter.default.post(name: .coveCopiedSSHCommand, object: item.id)
            }
            .disabled(!item.remoteAccessProgress.ready)

            Divider()

            Button("Snapshots") {
                openWindow(id: WindowID.snapshots, value: item.id)
            }
            Button("Take Snapshot…") { onTakeSnapshot() }
                .keyboardShortcut("s", modifiers: [.command, .shift])
            Button("Clone…") {
                VMActions.clone(item: item, library: library, alert: $alert)
            }
            .disabled(item.state.isLive || item.state == .installing)
            Button("Rename…") { onRename() }
                .disabled(item.state.isLive)

            Divider()

            Button("Show in Finder") { VMActions.showInFinder(item) }
            Button("Export…") {
                VMActions.export(item: item, library: library, alert: $alert)
            }
            .disabled(item.state.isLive || item.state == .installing)
            Button("Settings…") {
                openWindow(id: WindowID.vmSettings, value: item.id)
            }
            .keyboardShortcut("i", modifiers: .command)

            Divider()

            Button("Delete…", role: .destructive) { onDelete() }
        }
    }
}

extension Notification.Name {
    static let coveCopiedSSHCommand = Notification.Name("CoveCopiedSSHCommand")
}
