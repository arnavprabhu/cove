import SwiftUI

/// Alerts from States.dc.html. Present with `.coveAlert($alert)`; any screen can use these.
enum CoveAlert: Identifiable, Equatable {
    /// Third macOS VM start attempted while two are running.
    case licenseLimit
    /// Confirm moving a VM to the Trash.
    case confirmDelete(vmID: UUID, name: String, snapshotCount: Int)
    /// Library volume is low on space.
    case lowDiskSpace(available: UInt64)
    /// Restore image download failed; `resumable` offers "Resume Download".
    case downloadFailed(jobID: UUID, message: String, resumable: Bool)
    /// Generic error.
    case error(title: String, message: String)

    var id: String {
        switch self {
        case .licenseLimit: "license"
        case .confirmDelete(let id, _, _): "delete-\(id)"
        case .lowDiskSpace: "lowdisk"
        case .downloadFailed(let id, _, _): "download-\(id)"
        case .error(let t, let m): "error-\(t)-\(m)"
        }
    }

    static func from(_ error: Error) -> CoveAlert {
        if case CoveError.licenseLimit = error { return .licenseLimit }
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
    @Environment(VMLibrary.self) private var library

    func body(content: Content) -> some View {
        content.alert(title, isPresented: Binding(get: { alert != nil }, set: { if !$0 { alert = nil } }),
                      presenting: alert) { a in
            switch a {
            case .licenseLimit:
                Button("OK", role: .cancel) {}
            case .confirmDelete(let id, _, _):
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
                    Button("Resume Download") { library.installJob(id: jobID)?.retry() }
                } else {
                    Button("Try Again") { library.installJob(id: jobID)?.retry() }
                }
                Button("Cancel", role: .cancel) { library.installJob(id: jobID)?.cancel() }
            case .error:
                Button("OK", role: .cancel) {}
            }
        } message: { a in
            Text(message(a))
        }
    }

    private var title: String {
        switch alert {
        case .licenseLimit: "Two macOS VMs are already running"
        case .confirmDelete(_, let name, _): "Delete “\(name)”?"
        case .lowDiskSpace: "Not enough space for a new VM"
        case .downloadFailed: "Couldn’t finish downloading macOS"
        case .error(let t, _): t
        case nil: ""
        }
    }

    private func message(_ a: CoveAlert) -> String {
        switch a {
        case .licenseLimit:
            "Apple’s macOS license allows two macOS virtual machines at a time on one Mac. Suspend one, then try again."
        case .confirmDelete(_, _, let n):
            "The VM’s disk" + (n > 0 ? " and its \(n) snapshot\(n == 1 ? "" : "s")" : "")
                + " will be moved to the Trash. Files in shared folders on your Mac aren’t affected."
        case .lowDiskSpace(let available):
            "Cove needs about \(Bytes.format(HostInfo.estimatedInstallFootprint)) free to download and install macOS. Your Mac has \(Bytes.format(available)) available."
        case .downloadFailed(_, let message, let resumable):
            message + (resumable ? " Cove kept what was downloaded and will pick up from there." : "")
        case .error(_, let m):
            m
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
