import SwiftUI

/// Alerts from States.dc.html. Present with `.coveAlert($alert)`; any screen can use these.
enum CoveAlert: Identifiable, Equatable {
    /// Third macOS VM start attempted while two are running.
    case licenseLimit(startingVMID: UUID?)
    /// Confirm moving a VM to the Trash.
    case confirmDelete(vmID: UUID, name: String, snapshotCount: Int, bytes: UInt64)
    /// Library volume is low on space.
    case lowDiskSpace(available: UInt64)
    /// Restore image download failed; `resumable` offers "Resume Download".
    case downloadFailed(jobID: UUID, message: String, resumable: Bool)
    /// Generic error.
    case error(title: String, message: String)

    var id: String {
        switch self {
        case .licenseLimit: "license"
        case .confirmDelete(let id, _, _, _): "delete-\(id)"
        case .lowDiskSpace: "lowdisk"
        case .downloadFailed(let id, _, _): "download-\(id)"
        case .error(let t, let m): "error-\(t)-\(m)"
        }
    }

    @MainActor
    static func from(_ error: Error, starting item: VMItem? = nil) -> CoveAlert {
        if case CoveError.licenseLimit = error { return .licenseLimit(startingVMID: item?.id) }
        if case CoveError.notEnoughDiskSpace(_, let available) = error { return .lowDiskSpace(available: available) }
        return .error(title: "Something went wrong", message: error.localizedDescription)
    }
}

extension View {
    /// Presents `CoveAlert`s and performs their actions against the shared library.
    func coveAlert(_ alert: Binding<CoveAlert?>) -> some View {
        modifier(CoveAlertModifier(alert: alert))
    }
}

private struct CoveAlertModifier: ViewModifier {
    @Binding var alert: CoveAlert?
    @State private var pendingAlert: CoveAlert?
    @State private var diskSpace = DiskSpaceMonitor.shared
    @Environment(VMLibrary.self) private var library

    func body(content: Content) -> some View {
        content
        .onChange(of: diskSpace.criticalRevision, initial: true) { _, _ in
            guard alert == nil, let available = diskSpace.takeCriticalWarning() else { return }
            if !library.liveItems.isEmpty { alert = .lowDiskSpace(available: available) }
        }
        .alert(alert?.title ?? "", isPresented: Binding(get: { alert != nil && !isLicenseLimit }, set: { if !$0 && !isLicenseLimit { alert = nil } }),
                      presenting: alert) { a in
            switch a {
            case .licenseLimit:
                Button("OK", role: .cancel) {}
            case .confirmDelete(let id, _, _, _):
                Button("Move to Trash", role: .destructive) {
                    if let item = library.item(id: id) {
                        do { try library.delete(item) } catch { DispatchQueue.main.async { alert = .from(error) } }
                    }
                }
                Button("Cancel", role: .cancel) {}
            case .lowDiskSpace:
                Button("OK", role: .cancel) {}
            case .downloadFailed(let jobID, _, let resumable):
                if resumable {
                    Button("Resume Download") { retryInstall(id: jobID) }
                } else {
                    Button("Try Again") { retryInstall(id: jobID) }
                }
                Button("Cancel", role: .cancel) { library.installJob(id: jobID)?.cancel() }
            case .error:
                Button("OK", role: .cancel) {}
            }
        } message: { a in
            Text(a.message)
        }
        .sheet(isPresented: Binding(get: { isLicenseLimit }, set: { if !$0 && isLicenseLimit { alert = nil } }), onDismiss: {
            if let pendingAlert {
                alert = pendingAlert
                self.pendingAlert = nil
            }
        }) {
            if case .licenseLimit(let id) = alert {
                LicenseLimitView(targetName: id.flatMap { library.item(id: $0)?.name }, runningItems: library.liveItems.map {
                    .init(id: $0.id, name: $0.name, canSuspend: $0.state == .running || $0.state == .paused)
                },
                                 onCancel: { alert = nil }) { runningID in
                    guard let id, let target = library.item(id: id) else {
                        throw CoveError.io("The virtual machine is no longer in the library.")
                    }
                    let available = library.freeSpace
                    guard available >= HostInfo.minimumVMStartFreeSpace else {
                        pendingAlert = .lowDiskSpace(available: available)
                        alert = nil
                        return
                    }
                    guard let session = library.item(id: runningID)?.session else {
                        throw CoveError.io("This virtual machine has already stopped. Try starting your VM again.")
                    }
                    try await session.suspend()
                    do { try await library.start(target) }
                    catch CoveError.notEnoughDiskSpace(_, let available) {
                        pendingAlert = .lowDiskSpace(available: available)
                        alert = nil
                        return
                    }
                    AppRouter.shared.openConsole(target.id)
                    alert = nil
                }
            }
        }
    }

    private func retryInstall(id: UUID) {
        let available = library.freeSpace
        if available < HostInfo.minimumVMStartFreeSpace {
            DispatchQueue.main.async { alert = .lowDiskSpace(available: available) }
        } else {
            library.installJob(id: id)?.retry()
        }
    }

    private var isLicenseLimit: Bool {
        if case .licenseLimit = alert { return true }
        return false
    }
}

extension CoveAlert {
    var title: String {
        switch self {
        case .licenseLimit: "Two macOS VMs are already running"
        case .confirmDelete(_, let name, _, _): "Delete “\(name)”?"
        case .lowDiskSpace: "Not enough disk space"
        case .downloadFailed: "Couldn’t finish downloading macOS"
        case .error(let title, _): title
        }
    }

    var message: String {
        switch self {
        case .licenseLimit:
            "Apple’s macOS license allows two macOS virtual machines at a time on one Mac. Suspend one, then try again."
        case .confirmDelete(_, _, let count, let bytes):
            "Its virtual disk" + (count > 0 ? " and \(count) snapshot\(count == 1 ? "" : "s")" : "")
                + " (\(Bytes.format(bytes))) will be moved to the Trash. Files in shared folders on your Mac aren’t affected."
        case .lowDiskSpace(let available):
            "Your library disk has \(Bytes.format(available)) available. Free up space before starting a VM. Cove needs about \(Bytes.format(HostInfo.estimatedInstallFootprint)) free to download and install macOS."
        case .downloadFailed(_, let message, let resumable):
            message + (resumable ? " Cove kept what was downloaded and will pick up from there." : "")
        case .error(_, let message): message
        }
    }
}

/// Opens the New Virtual Machine sheet in the main window (from any window, menu, or the menu bar extra).
@MainActor
enum CoveActions {
    static func newVirtualMachine() {
        AppRouter.shared.open(.library)
        NotificationCenter.default.post(name: .coveNewVM, object: nil)
    }
}
