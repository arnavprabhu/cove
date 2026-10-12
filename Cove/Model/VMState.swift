import SwiftUI

/// Library-level lifecycle state for a VM (combines persisted + runtime state).
enum VMState: Equatable {
    case stopped
    case starting
    case running
    case paused
    case saving
    case suspended
    case stopping
    case installing
    case error(String)

    var label: String {
        switch self {
        case .stopped: "Stopped"
        case .starting: "Starting"
        case .running: "Running"
        case .paused: "Paused"
        case .saving: "Suspending"
        case .suspended: "Suspended"
        case .stopping: "Shutting Down"
        case .installing: "Installing"
        case .error: "Error"
        }
    }

    var color: Color {
        switch self {
        case .running, .starting: Theme.running
        case .paused, .suspended, .saving: Theme.suspended
        case .error: Theme.destructive
        default: Theme.stopped
        }
    }

    /// True when a VZVirtualMachine instance is alive (counts against the 2-guest limit).
    var isLive: Bool {
        switch self {
        case .starting, .running, .paused, .saving, .stopping: true
        default: false
        }
    }
}
