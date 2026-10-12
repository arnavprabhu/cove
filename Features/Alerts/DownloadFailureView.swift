import SwiftUI

struct DownloadFailureView: View {
    var progress: Double?
    var onUseFile: () -> Void
    var onResume: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "icloud.slash")
                .font(.system(size: 28, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
                .frame(width: 56, height: 56)
                .background(Theme.control.opacity(0.6), in: Circle())
                .accessibilityHidden(true)
            Text("Couldn’t finish downloading macOS")
                .font(Theme.Font.sectionTitle)
                .foregroundStyle(Theme.textPrimary)
            Text(message)
                .font(Theme.Font.small).foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                Button("Use a File…", action: onUseFile).buttonStyle(.covesecondary)
                Button("Resume Download", action: onResume).buttonStyle(.coveprimary)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.top, 6)
        }
        .multilineTextAlignment(.center)
        .padding(24)
        .frame(width: 390)
        .background(Theme.cell, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Theme.cellBorder))
        .padding(24)
    }

    private var message: String {
        let point = progress.map { " at \(Int((min(1, max(0, $0)) * 100).rounded()))%" } ?? ""
        return "The connection to Apple was lost\(point). Cove kept what was downloaded and will pick up from there."
    }
}
