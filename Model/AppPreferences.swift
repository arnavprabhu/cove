import SwiftUI

/// Keys for `@AppStorage`, shared by App Settings and the rest of the app.
enum Pref {
    static let showMenuBarExtra = "showMenuBarExtra"
    static let openAtLogin = "openAtLogin"
    static let keepRunningInMenuBar = "keepRunningInMenuBar"
    static let releaseShortcut = "releaseShortcut"          // "ctrl-option" | "ctrl-option-cmd"
    static let defaultProfile = "defaultProfile"            // ResourcePlanner.Profile raw value
    static let defaultStartAfterInstall = "defaultStartAfterInstall"
    static let defaultKeepRestoreImage = "defaultKeepRestoreImage"
    static let snapshotAfterInstall = "snapshotAfterInstall"
    static let libraryBookmark = "libraryBookmark"          // Data: security-scoped bookmark
    static let keepRestoreImages = "keepRestoreImages"
    static let checkForUpdates = "checkForUpdates"
    static let suspendOnQuit = "suspendOnQuit"
}
