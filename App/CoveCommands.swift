import SwiftUI

struct CoveCommands: Commands {
    var library: VMLibrary

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Virtual Machine…") { NotificationCenter.default.post(name: .coveNewVM, object: nil) }
                .keyboardShortcut("n")
        }
    }
}

extension Notification.Name {
    /// Asks the main window to present the New VM sheet.
    static let coveNewVM = Notification.Name("CoveNewVM")
}
