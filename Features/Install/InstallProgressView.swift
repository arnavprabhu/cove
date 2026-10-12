import SwiftUI

struct InstallProgressView: View {
    var jobID: UUID
    @Environment(VMLibrary.self) private var library
    @Environment(\.dismiss) private var dismiss
    @State private var confirmsCancel = false

    private var job: VMInstallJob? { library.installJob(id: jobID) }
    private var itemName: String { job?.request.name ?? "macOS VM" }
    private var isFinished: Bool {
        guard let job else { return false }
        if case .finished = job.status { return true }
        return false
    }
    private var isFailed: Bool {
        guard let job else { return false }
        if case .failed = job.status { return true }
        return false
    }
    private var isCancelled: Bool {
        guard let job else { return false }
        if case .cancelled = job.status { return true }
        return false
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack { Spacer(); Text("Installing “\(itemName)”").font(.system(size: 13, weight: .semibold)); Spacer() }
                .frame(height: 44).background(Theme.toolbar)
                .overlay(alignment: .bottom) { Rectangle().fill(Theme.separator).frame(height: 1) }
            if let job {
                content(job)
            } else {
                ContentUnavailableView("Installation not found", systemImage: "exclamationmark.triangle", description: Text("This installation may have finished or been removed."))
            }
            footer
        }
        .background(Theme.windowBackground)
        .frame(minWidth: 820, minHeight: 560)
        .confirmationDialog("Cancel this installation?", isPresented: $confirmsCancel, titleVisibility: .visible) {
            Button("Cancel Installation", role: .destructive) { job?.cancel() }
            Button("Keep Installing", role: .cancel) {}
        } message: { Text("The virtual machine installation will stop. A partial download can be resumed later.") }
    }

    @ViewBuilder private func content(_ job: VMInstallJob) -> some View {
        HStack(alignment: .center, spacing: 36) {
            VStack(spacing: 20) {
                ZStack(alignment: .bottom) {
                    RoundedRectangle(cornerRadius: 18).fill(Color(hex: 0x141415))
                    Rectangle().fill(Theme.accent.opacity(0.22)).frame(height: 190 * min(1, max(0, job.stageProgress)))
                    VStack(spacing: 5) {
                        Text("\(Int((job.stageProgress * 100).rounded()))%")
                            .font(.system(size: 50, weight: .bold, design: .rounded)).monospacedDigit()
                        Text(stageShort(job)).font(Theme.Font.body).foregroundStyle(Theme.textSecondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .frame(width: 360, height: 230)
                .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Theme.textPrimary.opacity(0.3), lineWidth: 4))
                .accessibilityElement(children: .combine)
                .accessibilityLabel(headline(job))
                .accessibilityValue("\(Int((job.stageProgress * 100).rounded()))%")
                Capsule().fill(Theme.textPrimary.opacity(0.75)).frame(width: 65, height: 5)
                    .padding(.top, -12)
                    .accessibilityHidden(true)
                VStack(spacing: 6) {
                    Text(headline(job)).font(.system(size: 23, weight: .bold)).multilineTextAlignment(.center)
                    Text(detail(job)).font(.system(size: 13)).foregroundStyle(Theme.textSecondary).multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 4)
                UsageBar(fraction: job.overallProgress, tint: isFailed ? Theme.destructive : Theme.accent, height: 6).frame(width: 360)
            }
            .frame(maxWidth: .infinity)

            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "STEPS")
                GroupedCard {
                    ForEach(Array(VMInstallJob.Stage.allCases.prefix(4)), id: \.rawValue) { stage in
                        if stage.rawValue > 0 { CardDivider() }
                        stageRow(stage, current: job.stage)
                    }
                }
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "bell").padding(.top, 1)
                        .accessibilityHidden(true)
                    Text("You can close this window. Installation keeps going and Cove sends a notification when your VM is ready.")
                        .fixedSize(horizontal: false, vertical: true)
                }
                .font(Theme.Font.small).foregroundStyle(Theme.textSecondary)
                .padding(13).frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.cell, in: RoundedRectangle(cornerRadius: 12))
                .accessibilityElement(children: .combine)
            }
            .frame(width: 350)
        }
        .padding(.horizontal, 44).padding(.vertical, 30)
    }

    private func stageRow(_ stage: VMInstallJob.Stage, current: VMInstallJob.Stage) -> some View {
        let done = isFinished || stage < current
        let active = !isFinished && !isFailed && !isCancelled && stage == current
        let labelColor = done || active ? Theme.textPrimary : Theme.textTertiary
        return HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle().strokeBorder(done ? Theme.running : active ? Theme.accent : Theme.textTertiary.opacity(0.6), lineWidth: active ? 2.5 : 1.5)
                    .background(done ? Theme.running : .clear, in: Circle())
                if done { Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)).foregroundStyle(.white) }
                else if active { Circle().fill(Theme.accent).frame(width: 7, height: 7) }
            }.frame(width: 22, height: 22)
            VStack(alignment: .leading, spacing: 3) {
                Text(stage.title).font(.system(size: 13, weight: .semibold)).foregroundStyle(labelColor)
                Text(stageNote(stage)).font(Theme.Font.small).foregroundStyle(Theme.textTertiary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(stage.title), \(done ? "complete" : active ? "in progress" : "pending"). \(stageNote(stage))")
    }

    private func stageNote(_ stage: VMInstallJob.Stage) -> String {
        switch stage {
        case .check: "Apple silicon, disk space and macOS version"
        case .download: job?.request.keepRestoreImage == true ? "Signed by Apple · kept for future VMs" : "Signed by Apple"
        case .install: "Takes about 10 minutes"
        case .firstBoot: "You finish Setup Assistant in the VM window"
        case .done: "Ready to use"
        }
    }

    private func stageShort(_ job: VMInstallJob) -> String {
        if isFailed { return "Needs attention" }
        if isCancelled { return "Cancelled" }
        if isFinished { return "Done" }
        return switch job.stage {
        case .check: "Checking"
        case .download: "Restore image"
        case .install: "Installing"
        case .firstBoot: "First boot"
        case .done: "Done"
        }
    }

    private func headline(_ job: VMInstallJob) -> String {
        if isFailed { return "Installation couldn’t finish" }
        if isCancelled { return "Installation cancelled" }
        if isFinished { return "Your VM is ready" }
        return switch job.stage {
        case .check: "Checking this Mac"
        case .download: "Downloading macOS"
        case .install: "Installing macOS"
        case .firstBoot: "Starting for the first time"
        case .done: "Your VM is ready"
        }
    }

    private func detail(_ job: VMInstallJob) -> String {
        if case .failed(let message, _) = job.status { return message }
        if isCancelled { return "You can close this window." }
        if isFinished { return "macOS installed. Open it to finish Setup Assistant." }
        switch job.stage {
        case .check: return "Making sure this Mac is ready to install macOS"
        case .download:
            let got = ByteCountFormatter.string(fromByteCount: max(0, job.bytesReceived), countStyle: .file)
            let total = job.bytesExpected > 0 ? ByteCountFormatter.string(fromByteCount: job.bytesExpected, countStyle: .file) : "—"
            return "\(got) of \(total) · \(Durations.remaining(job.estimatedSecondsRemaining) ?? "calculating time remaining")"
        case .install:
            return "Writing macOS to the virtual disk" + (Durations.remaining(job.estimatedSecondsRemaining).map { " · \($0)" } ?? "")
        case .firstBoot: return "Booting into Setup Assistant"
        case .done: return "macOS installed. Open it to finish Setup Assistant."
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            if let job, !isFinished, !isCancelled {
                Button("Cancel Installation", role: .destructive) { confirmsCancel = true }.buttonStyle(.covesecondary)
            }
            Spacer()
            if let job, !isFinished, !isFailed, !isCancelled {
                Button("Continue in Background") { job.isInBackground = true; dismiss() }.buttonStyle(.covesecondary)
            }
            if let job, isFailed {
                Button(retryTitle(job)) { job.retry() }.buttonStyle(.coveprimary)
            }
            if let job, isFinished, let vmID = job.vmID {
                Button("Open VM") { AppRouter.shared.openConsole(vmID); dismiss() }.buttonStyle(.coveprimary)
            }
            if job == nil || isCancelled { Button("Close") { dismiss() }.buttonStyle(.covesecondary) }
        }
        .padding(.horizontal, 24).frame(height: 58)
        .background(Theme.toolbar)
        .overlay(alignment: .top) { Rectangle().fill(Theme.separator).frame(height: 1) }
    }

    private func retryTitle(_ job: VMInstallJob) -> String {
        if case .failed(_, let resumable) = job.status, resumable { return "Resume Download" }
        return "Try Again"
    }
}
