import Foundation

/// Sidebar selection in the library window.
enum LibrarySelection: Hashable {
    case vm(UUID)
    case restoreImages
    case sharedFolders
}
