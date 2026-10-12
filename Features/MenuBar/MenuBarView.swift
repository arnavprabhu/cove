import AppKit
import SwiftUI

struct MenuBarView: View {
    @Environment(VMLibrary.self) private var library
    @Environment(\.openWindow) private var openWindow
    @State private var alert: CoveAlert?
    @State private var stoppingItem: VMItem?

    private var liveItems: [VMItem] { library.liveItems }
    private var allocatedCores: Int { liveItems.reduce(0) { $0 + $1.config.cpuCount } }
    private var allocatedMemory: UInt64 { liveItems.reduce(0) { $0 + $1.config.memoryBytes } }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(Theme.separator).padding(.horizontal, 10).padding(.bottom, 5)
            Text("Virtual Machines")
                .font(Theme.Font.captionStrong).foregroundStyle(Theme.textTertiary)
                .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 12).padding(.vertical, 5)

            if library.items.isEmpty {
                Text("No virtual machines yet").font(Theme.Font.small).foregroundStyle(Theme.textSecondary)
                    .frame(maxWidth: .infinity, minHeight: 70)
            } else {
                ForEach(library.items) { item in vmRow(item) }
            }

            if !library.canStartAnother {
                Text("Two macOS VMs are already running — the most Apple’s license allows on one Mac. Stop or suspend one first.")
                    .font(.system(size: 11)).lineSpacing(2).foregroundStyle(Color(light: 0x805000, dark: 0xFFD18A))
                    .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.warning.opacity(0.14), in: RoundedRectangle(cornerRadius: 8))
                    .padding(.horizontal, 10).padding(.top, 5)
            }

            Spacer(minLength: 8)
            Divider().overlay(Theme.separator).padding(.horizontal, 10).padding(.vertical, 6)

            Button { CoveActions.newVirtualMachine() } label: { menuRow("New Virtual Machine…") }
                .buttonStyle(MenuRowButtonStyle())
            Button { openWindow(id: WindowID.library) } label: { menuRow("Open Cove") }
                .buttonStyle(MenuRowButtonStyle())
            SettingsLink { menuRow("Settings…") }.buttonStyle(MenuRowButtonStyle())
            Divider().overlay(Theme.separator).padding(.horizontal, 10).padding(.vertical, 6)
            Button { NSApp.terminate(nil) } label: { menuRow("Quit Cove", shortcut: "⌘Q") }
                .buttonStyle(MenuRowButtonStyle())
        }
        .padding(6)
        .frame(width: 360).frame(minHeight: 280, maxHeight: 600)
        .background(Theme.sidebar)
        .coveAlert($alert)
        .confirmationDialog("Shut Down \(stoppingItem?.name ?? "Virtual Machine")?", isPresented: Binding(
            get: { stoppingItem != nil }, set: { if !$0 { stoppingItem = nil } }), titleVisibility: .visible) {
                Button("Shut Down") {
                    if let item = stoppingItem { run { try item.session?.requestShutDown() } }
                    stoppingItem = nil
                }
                Button("Suspend") {
                    if let item = stoppingItem { runAsync { try await item.session?.suspend() } }
                    stoppingItem = nil
                }
                Button("Cancel", role: .cancel) { stoppingItem = nil }
            } message: { Text("Shut down the guest or suspend it to disk.") }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "macwindow.on.rectangle")
                .font(.system(size: 18, weight: .medium)).foregroundStyle(Theme.accent)
                .frame(width: 30, height: 30).background(Theme.control, in: RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 2) {
                Text("Cove").font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.textPrimary)
                Text(summary).font(Theme.Font.caption).foregroundStyle(Theme.textSecondary)
            }
            Spacer(minLength: 4)
            if !liveItems.isEmpty {
                Text("\(allocatedCores) cores · \(Bytes.formatMemory(allocatedMemory))")
                    .font(.system(size: 10, design: .rounded).monospacedDigit())
                    .foregroundStyle(Theme.textSecondary).lineLimit(1)
            }
        }
        .padding(.horizontal, 7).padding(.vertical, 7)
    }

    private var summary: String {
        let count = liveItems.count
        return count == 0 ? "No VMs running" : "\(count) running · \(allocatedCores) cores · \(Bytes.formatMemory(allocatedMemory))"
    }

    private func vmRow(_ item: VMItem) -> some View {
        HStack(spacing: 9) {
            ZStack {
                RoundedRectangle(cornerRadius: 4).strokeBorder(Theme.textTertiary, lineWidth: 1.4)
                    .frame(width: 30, height: 20)
                RoundedRectangle(cornerRadius: 2).fill(item.state.isLive ? Theme.accent.opacity(0.75) : Theme.control)
                    .frame(width: 18, height: 10)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name).font(Theme.Font.body).foregroundStyle(Theme.textPrimary).lineLimit(1)
                HStack(spacing: 5) {
                    StatusDot(color: item.state.color, size: 6)
                    Text(item.state.label).font(Theme.Font.caption).foregroundStyle(Theme.textSecondary)
                }
            }
            Spacer(minLength: 2)

            if item.state == .running || item.state == .paused {
                Button("Show Window") { openWindow(id: WindowID.console, value: item.id) }
                    .font(.system(size: 11)).buttonStyle(.plain).foregroundStyle(Theme.link)
                    .help("Show \(item.name) window")
            }

            if item.state == .running || item.state == .paused {
                Button(item.state == .paused ? "Resume" : "Suspend") {
                    if item.state == .paused { runAsync { try await item.session?.resume() } }
                    else { runAsync { try await item.session?.suspend() } }
                }
                .font(.system(size: 11, weight: .medium)).buttonStyle(.bordered).controlSize(.small)
                .help(item.state == .paused ? "Resume \(item.name)" : "Suspend \(item.name) to disk")
                Button { stoppingItem = item } label: { Image(systemName: "power") }
                    .font(.system(size: 11)).buttonStyle(.bordered).controlSize(.small)
                    .help("Shut Down \(item.name)").accessibilityLabel("Shut Down \(item.name)")
            } else if item.state == .stopped || item.state == .suspended {
                Button(item.state == .suspended ? "Resume" : "Start") {
                    runAsync { try await library.start(item) }
                }
                .font(.system(size: 11, weight: .medium)).buttonStyle(.borderedProminent).controlSize(.small)
                .disabled(!library.canStartAnother)
                .help("\(item.state == .suspended ? "Resume" : "Start") \(item.name)")
            } else {
                ProgressView().controlSize(.small).frame(width: 32)
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 6)
        .background(Color.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 6))
    }

    private func menuRow(_ title: String, shortcut: String? = nil) -> some View {
        HStack {
            Text(title)
            Spacer()
            if let shortcut { Text(shortcut).foregroundStyle(Theme.textTertiary) }
        }
        .font(Theme.Font.body).foregroundStyle(Theme.textPrimary)
        .padding(.horizontal, 10).frame(height: 26)
        .contentShape(RoundedRectangle(cornerRadius: 5))
    }

    private func run(_ action: () throws -> Void) {
        do { try action() } catch { alert = .from(error) }
    }

    private func runAsync(_ action: @escaping () async throws -> Void) {
        Task { @MainActor in
            do { try await action() } catch { alert = .from(error) }
        }
    }
}

private struct MenuRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? Theme.accentFill : .clear, in: RoundedRectangle(cornerRadius: 5))
    }
}
