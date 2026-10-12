import SwiftUI

/// A sheet because native alerts cannot accommodate a changing list of live VMs.
struct LicenseLimitView: View {
    var target: VMItem?
    var runningItems: [VMItem]
    var onCancel: () -> Void
    var onStart: (VMItem) async throws -> Void

    @State private var workingID: UUID?
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 28, weight: .medium))
                .foregroundStyle(Theme.warning)
                .frame(width: 56, height: 56)
                .background(Theme.warning.opacity(0.16), in: Circle())
                .accessibilityHidden(true)
            Text("Two macOS VMs are already running")
                .font(Theme.Font.sectionTitle)
            Text("Apple’s macOS license allows two macOS virtual machines at a time on one Mac. "
                 + (target.map { "Suspend one to start “\($0.name)”." } ?? "Suspend one, then try again."))
                .font(Theme.Font.small)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            if let target {
                ForEach(runningItems) { item in
                    Button {
                        workingID = item.id
                        errorMessage = nil
                        Task { @MainActor in
                            defer { workingID = nil }
                            do { try await onStart(item) }
                            catch { errorMessage = error.localizedDescription }
                        }
                    } label: {
                        HStack(spacing: 8) {
                            if workingID == item.id { ProgressView().controlSize(.small) }
                            Text("Suspend “\(item.name)” and Start")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(.coveprimary)
                    .disabled(workingID != nil || (item.state != .running && item.state != .paused))
                    .accessibilityLabel("Suspend \(item.name) and start \(target.name)")
                }
                if runningItems.isEmpty {
                    Text("The running VMs have stopped. Cancel and try starting your VM again.")
                        .font(Theme.Font.small).foregroundStyle(Theme.textSecondary)
                }
            }
            if let errorMessage {
                Text(errorMessage)
                    .font(Theme.Font.small).foregroundStyle(Theme.destructive)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
            Button(action: onCancel) { Text("Cancel").frame(maxWidth: .infinity) }
                .buttonStyle(.covesecondary)
                .keyboardShortcut(.cancelAction)
                .disabled(workingID != nil)
        }
        .multilineTextAlignment(.center)
        .foregroundStyle(Theme.textPrimary)
        .padding(24)
        .frame(width: 380)
        .background(Theme.windowBackground)
        .interactiveDismissDisabled(workingID != nil)
    }
}
