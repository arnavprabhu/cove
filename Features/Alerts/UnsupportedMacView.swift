import SwiftUI

/// Full-window gate when Apple silicon or Virtualization.framework is unavailable (States.dc.html).
struct UnsupportedMacView: View {
    private var isIntel: Bool { !HostInfo.isAppleSilicon }
    private var chipLabel: String {
        let chip = HostInfo.chipName.trimmingCharacters(in: .whitespacesAndNewlines)
        return chip.isEmpty ? HostInfo.modelIdentifier : chip
    }

    var body: some View {
        ZStack {
            Theme.windowBackground.ignoresSafeArea()
            VStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(Color.primary.opacity(0.08))
                        .frame(width: 72, height: 72)
                    Image(systemName: "cpu")
                        .font(.system(size: 30, weight: .regular))
                        .foregroundStyle(Theme.textPrimary)
                }
                .accessibilityHidden(true)

                Text(title)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)

                Text(message)
                    .font(Theme.Font.body)
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
                    .fixedSize(horizontal: false, vertical: true)

                Text(chipLabel)
                    .font(Theme.Font.mono)
                    .foregroundStyle(Theme.textTertiary)
                    .accessibilityLabel("Processor \(chipLabel)")

                HStack(spacing: 10) {
                    Button("Learn More") {
                        if let url = URL(string: "https://support.apple.com/en-us/116943") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    .buttonStyle(.covesecondary)
                    .accessibilityHint("Opens Apple support in your browser")

                    Button("Quit") {
                        NSApplication.shared.terminate(nil)
                    }
                    .buttonStyle(.coveprimary)
                    .keyboardShortcut(.defaultAction)
                }
                .padding(.top, 8)
            }
            .padding(40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
    }

    private var title: String {
        if isIntel {
            return "Cove needs a Mac with Apple silicon"
        }
        return "Virtualization isn’t available on this Mac"
    }

    private var message: String {
        if isIntel {
            return "macOS virtual machines rely on Apple silicon. This Mac has an Intel processor, so Cove can’t create or run macOS VMs here."
        }
        return "Apple’s Virtualization framework isn’t available here — for example when Cove is running inside another virtual machine. Cove needs a Mac with Apple silicon running macOS directly."
    }
}
