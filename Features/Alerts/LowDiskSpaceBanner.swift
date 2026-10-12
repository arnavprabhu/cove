import SwiftUI

/// Compact warning banner other screens can embed when free space is low.
struct LowDiskSpaceBanner: View {
    var available: UInt64

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: "externaldrive.fill.badge.exclamationmark")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.warning)
                .accessibilityHidden(true)

            Text("Only \(Bytes.format(available)) free on your library disk. Cove needs about \(Bytes.format(HostInfo.estimatedInstallFootprint)) to download and install macOS.")
                .font(Theme.Font.small)
                .foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Theme.warning.opacity(0.12))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(Theme.warning.opacity(0.35))
                )
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Low disk space. Only \(Bytes.format(available)) available.")
    }
}
