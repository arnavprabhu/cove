import SwiftUI

/// Scene identifiers for `openWindow(id:value:)`.
enum WindowID {
    static let library = "library"
    /// value: VMItem.id
    static let console = "console"
    /// value: VMItem.id
    static let vmSettings = "vm-settings"
    /// value: VMItem.id
    static let snapshots = "snapshots"
    /// value: VMItem.id
    static let remoteAccess = "remote-access"
    /// value: VMInstallJob.id
    static let install = "install"
}
