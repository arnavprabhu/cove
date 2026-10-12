import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct CoveCommands: Commands {
    var library: VMLibrary

    @FocusedValue(\.focusedVMID) private var focusedVMID

    private var focusedItem: VMItem? {
        focusedVMID.flatMap { library.item(id: $0) }
    }

    private var state: VMState { focusedItem?.state ?? .stopped }

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Virtual Machine…") {
                CoveActions.newVirtualMachine()
            }
            .keyboardShortcut("n")

            Button("Import Virtual Machine…") {
                importVM()
            }
            .keyboardShortcut("o", modifiers: [.command, .shift])
        }

        CommandGroup(after: .sidebar) {
            Button("Show Library") {
                AppRouter.shared.open(.library)
            }
            .keyboardShortcut("0")
        }

        CommandMenu("Virtual Machine") {
            Button(startResumeTitle) {
                guard let item = focusedItem else { return }
                Task { @MainActor in
                    do {
                        try await library.start(item)
                        AppRouter.shared.openConsole(item.id)
                    } catch {
                        CommandErrorCenter.shared.present(error)
                    }
                }
            }
            .keyboardShortcut("r")
            .disabled(!canStartOrResume)

            Button("Pause") {
                guard let session = focusedItem?.session else { return }
                Task { @MainActor in
                    do { try await session.pause() }
                    catch { CommandErrorCenter.shared.present(error) }
                }
            }
            .keyboardShortcut("p", modifiers: [.command, .option])
            .disabled(state != .running)

            Button("Suspend") {
                guard let session = focusedItem?.session else { return }
                Task { @MainActor in
                    do { try await session.suspend() }
                    catch { CommandErrorCenter.shared.present(error) }
                }
            }
            .keyboardShortcut("u", modifiers: [.command, .option])
            .disabled(!state.isLive)

            Button("Shut Down") {
                guard let session = focusedItem?.session else { return }
                do { try session.requestShutDown() }
                catch { CommandErrorCenter.shared.present(error) }
            }
            .keyboardShortcut(".", modifiers: [.command, .option])
            .disabled(!state.isLive)

            Button("Restart") {
                guard let item = focusedItem else { return }
                Task { @MainActor in
                    do {
                        try await library.restart(item)
                        AppRouter.shared.openConsole(item.id)
                    } catch {
                        CommandErrorCenter.shared.present(error)
                    }
                }
            }
            .keyboardShortcut("r", modifiers: [.command, .option])
            .disabled(!state.isLive)

            Button("Start in Recovery") {
                guard let item = focusedItem else { return }
                Task { @MainActor in
                    do {
                        try await library.start(item, recovery: true)
                        AppRouter.shared.openConsole(item.id)
                    } catch {
                        CommandErrorCenter.shared.present(error)
                    }
                }
            }
            .disabled(!canStartInRecovery)

            Divider()

            Button("Take Snapshot…") {
                guard let id = focusedVMID else { return }
                NotificationCenter.default.post(name: .coveTakeSnapshot, object: id)
            }
            .keyboardShortcut("s", modifiers: [.command, .shift])
            .disabled(!canTakeSnapshot)

            Button("Show Snapshots") {
                guard let id = focusedVMID else { return }
                AppRouter.shared.open(.snapshots(id))
            }
            .keyboardShortcut("s", modifiers: [.command, .option])
            .disabled(focusedVMID == nil)

            Divider()

            Button("Settings…") {
                guard let id = focusedVMID else { return }
                AppRouter.shared.open(.vmSettings(id))
            }
            .keyboardShortcut("i")
            .disabled(focusedVMID == nil)

            Button("Show in Finder") {
                guard let item = focusedItem else { return }
                VMActions.showInFinder(item)
            }
            .keyboardShortcut("r", modifiers: [.command, .shift])
            .disabled(focusedItem == nil)
        }
    }

    private var startResumeTitle: LocalizedStringKey {
        switch state {
        case .paused, .suspended: "Resume"
        default: "Start"
        }
    }

    private var canStartOrResume: Bool {
        guard let item = focusedItem, item.installJob == nil else { return false }
        switch state {
        case .stopped, .suspended, .paused, .error: return true
        default: return false
        }
    }

    private var canStartInRecovery: Bool {
        guard let item = focusedItem, item.installJob == nil else { return false }
        return !state.isLive
    }

    private var canTakeSnapshot: Bool {
        guard focusedItem != nil else { return false }
        switch state {
        case .installing, .starting, .saving, .stopping: return false
        default: return true
        }
    }

    private func importVM() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [UTType(filenameExtension: VMBundle.pathExtension) ?? .package]
        panel.message = String(localized: "Choose a Cove virtual machine package to import.")
        panel.prompt = String(localized: "Import")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let item = try library.importVM(from: url)
            AppRouter.shared.open(.library)
            _ = item
        } catch {
            CommandErrorCenter.shared.present(error)
        }
    }
}

extension Notification.Name {
    /// Asks the main window to present the New VM sheet.
    static let coveNewVM = Notification.Name("CoveNewVM")
    /// Asks the focused VM’s window to present the Take Snapshot name prompt. `object` is the VM `UUID`.
    static let coveTakeSnapshot = Notification.Name("CoveTakeSnapshot")
}
