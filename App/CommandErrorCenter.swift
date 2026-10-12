import SwiftUI

/// Surfaces errors from menu commands (which can’t present alerts themselves).
/// Observed by the main window via `.coveAlert`.
@MainActor @Observable
final class CommandErrorCenter {
    static let shared = CommandErrorCenter()

    var alert: CoveAlert?

    func present(_ error: Error) {
        alert = CoveAlert.from(error)
        AppRouter.shared.open(.library)
    }

    func present(_ alert: CoveAlert) {
        self.alert = alert
        AppRouter.shared.open(.library)
    }
}

/// Focused virtual machine for the Virtual Machine menu and related shortcuts.
private struct FocusedVMIDKey: FocusedValueKey {
    typealias Value = UUID
}

extension FocusedValues {
    var focusedVMID: UUID? {
        get { self[FocusedVMIDKey.self] }
        set { self[FocusedVMIDKey.self] = newValue }
    }
}
