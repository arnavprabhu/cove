import SwiftUI
import UniformTypeIdentifiers

struct WelcomeView: View {
    @Environment(VMLibrary.self) private var library
    @State private var importError: String?

    private var freeSpace: UInt64 { HostInfo.freeDiskSpace(at: library.rootURL) }
    private var diskReady: Bool { freeSpace >= HostInfo.estimatedInstallFootprint }
    private var hostReady: Bool { HostInfo.isAppleSilicon && HostInfo.virtualizationSupported && diskReady }

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                Spacer()
                CoveLogo(size: 140)
                Text("Welcome to Cove")
                    .font(Theme.Font.largeTitle)
                    .padding(.top, 24)
                Text("Run macOS inside macOS. Cove downloads the right restore image from Apple, sizes the virtual machine for your Mac, and installs it — in one click.")
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 460)
                    .padding(.top, 10)
                Button(action: CoveActions.newVirtualMachine) {
                    Label("Create macOS Virtual Machine", systemImage: "plus")
                }
                .buttonStyle(.coveprimaryLarge)
                .disabled(!hostReady)
                .help(hostReady ? "Uses the latest macOS your Mac supports · about 20 minutes" : readinessExplanation)
                .padding(.top, 30)
                Text(hostReady ? "Uses the latest macOS your Mac supports · about 20 minutes" : readinessExplanation)
                    .font(Theme.Font.small)
                    .foregroundStyle(hostReady ? Theme.textTertiary : Theme.warning)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
                    .padding(.top, 9)

                VStack(spacing: 2) {
                    welcomeAction("square.and.arrow.down", title: "Import a virtual machine…", detail: "Open a .cove bundle or a VM from another app", action: importVM)
                    welcomeAction("doc", title: "Install from a restore image…", detail: "Use an .ipsw file you already have on this Mac") {
                        CoveActions.newVirtualMachine()
                    }
                    welcomeAction("gearshape", title: "Choose where VMs are stored…", detail: "Internal disk or a fast external SSD") {
                        AppRouter.shared.open(.library)
                        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                    }
                }
                .frame(maxWidth: 460)
                .padding(.top, 28)
                Spacer()
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 48)
            .background(Theme.windowBackground)

            readinessSidebar
                .frame(width: 340)
                .padding(.horizontal, 24)
                .padding(.top, 52)
                .padding(.bottom, 24)
                .background(Theme.sidebar)
        }
        .background(Theme.windowBackground)
        .alert("Couldn’t import virtual machine", isPresented: Binding(get: { importError != nil }, set: { if !$0 { importError = nil } })) {
            Button("OK", role: .cancel) { importError = nil }
        } message: { Text(importError ?? "") }
    }

    private var readinessExplanation: String {
        if !HostInfo.isAppleSilicon { return "Cove requires a Mac with Apple silicon." }
        if !HostInfo.virtualizationSupported { return "Virtualization is unavailable on this version of macOS." }
        return "Free up at least \(Bytes.format(HostInfo.estimatedInstallFootprint)) on the Cove library disk to continue."
    }

    private var readinessSidebar: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeader(title: "THIS MAC")
            HStack(spacing: 12) {
                Image(systemName: hostReady ? "checkmark" : "exclamationmark")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(hostReady ? Theme.running : Theme.warning)
                    .frame(width: 36, height: 36)
                    .background((hostReady ? Theme.running : Theme.warning).opacity(0.14), in: Circle())
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(hostReady ? "Ready for virtual machines" : "Setup needed")
                        .font(.system(size: 14, weight: .semibold))
                    Text(hostReady ? "All requirements met" : "Check the items below")
                        .font(Theme.Font.small).foregroundStyle(Theme.textSecondary)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.cell, in: RoundedRectangle(cornerRadius: Theme.cornerRadius))
            .accessibilityElement(children: .combine)

            GroupedCard {
                readinessRow("Apple silicon", detail: "\(HostInfo.chipName) · \(HostInfo.cpuCount) cores", state: HostInfo.isAppleSilicon ? .pass : .fail)
                CardDivider()
                readinessRow("Virtualization framework", detail: HostInfo.virtualizationSupported ? "Available on this version of macOS" : "Unavailable on this version of macOS", state: HostInfo.virtualizationSupported ? .pass : .fail)
                CardDivider()
                VStack(alignment: .leading, spacing: 7) {
                    readinessRow("Free disk space", detail: "\(Bytes.format(freeSpace)) free · a new VM uses about 40–80 GB", state: diskReady ? .pass : .warn)
                    UsageBar(fraction: min(1, Double(freeSpace) / Double(max(1, HostInfo.estimatedInstallFootprint))), tint: diskReady ? Theme.accent : Theme.warning)
                        .padding(.leading, 28)
                }
                .padding(12)
                CardDivider()
                readinessRow("Internet connection", detail: "Restore image comes directly from Apple", state: NetworkMonitor.shared.isReachable ? .pass : .warn)
            }
            Spacer(minLength: 12)
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "info.circle").font(.system(size: 15)).padding(.top, 1)
                    .accessibilityHidden(true)
                Text("Apple’s macOS license permits up to two additional copies of macOS running in virtual machines on each Mac.")
                    .font(Theme.Font.small).lineSpacing(3)
            }
            .foregroundStyle(Theme.textTertiary)
            .accessibilityElement(children: .combine)
        }
    }

    private enum CheckState { case pass, warn, fail }
    private func readinessRow(_ title: String, detail: String, state: CheckState) -> some View {
        HStack(alignment: .top, spacing: 11) {
            Image(systemName: state == .pass ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(state == .pass ? Theme.running : (state == .fail ? Theme.destructive : Theme.warning))
                .font(.system(size: 15))
                .frame(width: 17)
                .padding(.top, 1)
                .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(Theme.Font.body)
                    Text(detail).font(Theme.Font.small).foregroundStyle(Theme.textTertiary).fixedSize(horizontal: false, vertical: true)
                }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title). \(detail)")
        .accessibilityValue(state == .pass ? String(localized: "Passed") : (state == .fail ? String(localized: "Failed") : String(localized: "Warning")))
    }

    private func welcomeAction(_ symbol: String, title: String, detail: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: symbol).font(.system(size: 16)).foregroundStyle(Theme.accent)
                    .frame(width: 32, height: 32).background(Theme.control, in: RoundedRectangle(cornerRadius: 8))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.textPrimary)
                    Text(detail).font(Theme.Font.small).foregroundStyle(Theme.textTertiary)
                }
                Spacer(minLength: 0)
            }
            .padding(10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityHint(detail)
    }

    private func importVM() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.package]
        panel.allowsOtherFileTypes = true
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Import"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try library.importVM(from: url) }
        catch { importError = error.localizedDescription }
    }
}
