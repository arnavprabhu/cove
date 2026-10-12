import Foundation

enum CoveError: LocalizedError, Equatable {
    case unsupportedHost
    case hardwareModelUnsupported
    case restoreImageUnsupported
    case corruptBundle(String)
    case alreadyExists(String)
    case cannotShrinkDisk
    case io(String)
    case licenseLimit
    case notEnoughDiskSpace(needed: UInt64, available: UInt64)
    case vmIsRunning
    case downloadFailed(String, resumable: Bool)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .unsupportedHost: "This Mac can’t run macOS virtual machines."
        case .hardwareModelUnsupported: "This virtual machine needs a newer version of macOS on this Mac."
        case .restoreImageUnsupported: "This restore image can’t be installed on this Mac."
        case .corruptBundle(let part): "The virtual machine is damaged (\(part) is missing or unreadable)."
        case .alreadyExists(let name): "“\(name)” already exists."
        case .cannotShrinkDisk: "A virtual disk can’t be made smaller."
        case .io(let msg): msg
        case .licenseLimit: "macOS allows up to two macOS virtual machines to run at the same time."
        case .notEnoughDiskSpace(let needed, let available):
            "Not enough disk space. \(Bytes.format(needed)) needed, \(Bytes.format(available)) available."
        case .vmIsRunning: "Shut down the virtual machine first."
        case .downloadFailed(let msg, _): "The download failed. \(msg)"
        case .cancelled: "Cancelled."
        }
    }
}
