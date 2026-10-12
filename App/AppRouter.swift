import SwiftUI

/// Lets non-view code (notifications, install jobs, menu bar) ask the UI to open windows.
@MainActor @Observable
final class AppRouter {
    static let shared = AppRouter()

    enum Request: Equatable {
        case console(UUID)
        case install(UUID)
        case vmSettings(UUID)
        case snapshots(UUID)
        case library
    }

    fileprivate(set) var pending: Request?

    func openConsole(_ id: UUID) { pending = .console(id) }
    func openInstall(_ id: UUID) { pending = .install(id) }
    func open(_ r: Request) { pending = r }
}

/// Attached to the main window; performs pending router requests with `openWindow`.
struct AppRouterModifier: ViewModifier {
    @Environment(\.openWindow) private var openWindow
    @State private var router = AppRouter.shared

    func body(content: Content) -> some View {
        content.onChange(of: router.pending, initial: true) { _, request in
            guard let request else { return }
            router.pending = nil
            switch request {
            case .console(let id): openWindow(id: WindowID.console, value: id)
            case .install(let id): openWindow(id: WindowID.install, value: id)
            case .vmSettings(let id): openWindow(id: WindowID.vmSettings, value: id)
            case .snapshots(let id): openWindow(id: WindowID.snapshots, value: id)
            case .library: openWindow(id: WindowID.library)
            }
            NSApp.activate()
        }
    }
}
