import Foundation

@MainActor
enum LibraryFormatting {
    private static let relative: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .full
        return f
    }()

    private static let snapshotDay: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        f.doesRelativeDateFormatting = true
        return f
    }()

    static func statusLine(for item: VMItem) -> String {
        switch item.state {
        case .running, .starting, .paused:
            if let started = item.session?.startedAt {
                return "Running for \(Durations.elapsed(since: started))"
            }
            return item.state.label
        case .saving, .suspended:
            return "Suspended — resumes where you left off"
        case .stopping:
            return "Shutting down…"
        case .installing:
            if let job = item.installJob {
                let pct = Int((job.overallProgress * 100).rounded())
                return "Installing · \(pct)% · \(job.stage.title)"
            }
            return "Installing"
        case .error(let message):
            return message
        case .stopped:
            if let last = item.config.lastUsedAt {
                return "Stopped · last used \(relative.localizedString(for: last, relativeTo: Date()))"
            }
            return "Stopped"
        }
    }

    static func primaryActionTitle(for item: VMItem) -> String {
        switch item.state {
        case .running, .starting, .paused, .saving, .stopping:
            return "Show Window"
        case .suspended:
            return "Resume"
        case .installing:
            return "Show Progress"
        case .stopped, .error:
            return "Start"
        }
    }

    static func sidebarStatus(for item: VMItem) -> String {
        if item.state == .installing, let job = item.installJob {
            let pct = Int((job.overallProgress * 100).rounded())
            return "Installing · \(pct)%"
        }
        return item.state.label
    }

    static func snapshotDay(_ date: Date) -> String { snapshotDay.string(from: date) }

    /// Distinct shared-folder paths across all VMs, with the VMs that use each path.
    static func sharedFolderUsage(in library: VMLibrary) -> [(path: String, vms: [String])] {
        var map: [String: [String]] = [:]
        for item in library.items {
            for share in item.config.shares where share.enabled {
                map[share.path, default: []].append(item.name)
            }
        }
        return map.keys.sorted().map { path in
            (path: path, vms: map[path]?.sorted() ?? [])
        }
    }
}
