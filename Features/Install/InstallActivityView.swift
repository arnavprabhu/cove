import AppKit
import SwiftUI

/// Shows that an install is running when its window is closed ("Continue in Background").
/// `.card` for the Welcome screen, `.row` for the sidebar and menu bar.
struct InstallActivityView: View {
    enum Style { case card, row }

    var job: VMInstallJob
    var style: Style = .card

    private var failed: Bool { if case .failed = job.status { true } else { false } }
    private var name: String { job.request.name.isEmpty ? "macOS" : job.request.name }

    var body: some View {
        switch style {
        case .card: card
        case .row: row
        }
    }

    private var card: some View {
        HStack(spacing: 14) {
            indicator(size: 20)
            VStack(alignment: .leading, spacing: 6) {
                Text("Installing “\(name)”").font(.system(size: 13, weight: .semibold))
                Text(job.statusLine).font(Theme.Font.small).monospacedDigit()
                    .foregroundStyle(failed ? Theme.warning : Theme.textSecondary)
                UsageBar(fraction: job.overallProgress, tint: failed ? Theme.warning : Theme.accent, height: 5)
            }
            Button("Show Progress") { AppRouter.shared.openInstall(job.id) }
                .buttonStyle(.covesecondary)
        }
        .padding(14)
        .frame(maxWidth: 560)
        .background(Theme.cell, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.cellBorder))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Installing \(name). \(job.statusLine)")
    }

    private var row: some View {
        Button { AppRouter.shared.openInstall(job.id) } label: {
            HStack(spacing: 10) {
                indicator(size: 14)
                VStack(alignment: .leading, spacing: 3) {
                    Text(name).font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.textPrimary).lineLimit(1)
                    Text(job.shortStatusLine).font(Theme.Font.caption).monospacedDigit()
                        .foregroundStyle(failed ? Theme.warning : Theme.textTertiary).lineLimit(1)
                    UsageBar(fraction: job.overallProgress, tint: failed ? Theme.warning : Theme.accent, height: 3)
                }
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.coveplain)
        .help("Show installation progress")
        .accessibilityLabel("Installing \(name). \(job.statusLine)")
    }

    @ViewBuilder private func indicator(size: CGFloat) -> some View {
        if failed {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.warning)
                .font(.system(size: size * 0.8)).frame(width: size, height: size)
        } else {
            ProgressView().controlSize(size > 16 ? .small : .mini).frame(width: size, height: size)
        }
    }
}

/// Puts install progress on Cove's Dock icon ("42%"), so it's visible with every window closed.
@MainActor
enum InstallDockBadge {
    static func start(library: VMLibrary) {
        Task { @MainActor in
            while !Task.isCancelled {
                let label: String? = library.activeInstallJobs.first.map { job in
                    if case .failed = job.status { return "!" }
                    return "\(Int((job.overallProgress * 100).rounded()))%"
                }
                if NSApp.dockTile.badgeLabel != label { NSApp.dockTile.badgeLabel = label }
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }
}
