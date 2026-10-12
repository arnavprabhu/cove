import AppKit
import SwiftUI
import UniformTypeIdentifiers
import Virtualization

/// Per-VM settings window with seven tabs (design/VMSettings.dc.html).
struct VMSettingsView: View {
    var vmID: UUID

    private enum Tab: String, CaseIterable, Identifiable {
        case general, hardware, display, storage, network, sharing, advanced
        var id: String { rawValue }
        var title: String {
            switch self {
            case .general: "General"
            case .hardware: "Hardware"
            case .display: "Display"
            case .storage: "Storage"
            case .network: "Network"
            case .sharing: "Sharing"
            case .advanced: "Advanced"
            }
        }
        var systemImage: String {
            switch self {
            case .general: "gearshape"
            case .hardware: "cpu"
            case .display: "display"
            case .storage: "internaldrive"
            case .network: "network"
            case .sharing: "folder"
            case .advanced: "slider.horizontal.3"
            }
        }
    }

    @Environment(VMLibrary.self) private var library
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openWindow) private var openWindow

    @State private var tab: Tab = .general
    @State private var draft: VMConfig?
    @State private var alert: CoveAlert?
    @State private var confirmRegenerateID = false
    @State private var confirmClone = false
    @State private var cloneName = ""
    @State private var isSaving = false

    var body: some View {
        Group {
            if let item = library.item(id: vmID), let draft {
                content(item: item, draft: draftBinding(for: item))
            } else {
                Text("This virtual machine is no longer in the library.")
                    .foregroundStyle(Theme.textSecondary)
                    .frame(width: 720, height: 480)
            }
        }
        .onAppear { loadDraft() }
        .onChange(of: vmID) { _, _ in loadDraft() }
        .coveAlert($alert)
        .onChange(of: library.items.map(\.id)) { _, ids in
            if !ids.contains(vmID) { dismissWindow() }
        }
    }

    // MARK: - Shell

    @ViewBuilder
    private func content(item: VMItem, draft: Binding<VMConfig>) -> some View {
        let isLive = item.state.isLive
        VStack(spacing: 0) {
            tabBar
                .background(Theme.toolbar)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(Theme.cellBorder).frame(height: 1)
                }

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if isLive {
                        runningBanner(item: item)
                    }

                    switch tab {
                    case .general: generalTab(item: item, draft: draft)
                    case .hardware: hardwareTab(item: item, draft: draft, isLive: isLive)
                    case .display: displayTab(draft: draft)
                    case .storage: storageTab(item: item, draft: draft, isLive: isLive)
                    case .network: networkTab(item: item, draft: draft, isLive: isLive)
                    case .sharing: sharingTab(draft: draft)
                    case .advanced: advancedTab(item: item, isLive: isLive)
                    }
                }
                .frame(maxWidth: 640, alignment: .leading)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 26)
                .padding(.horizontal, 24)
            }
            .background(Theme.windowBackground)

            divider
            footer(item: item, draft: draft.wrappedValue)
        }
        .frame(width: 720, height: 560)
        .navigationTitle("\(item.name) Settings")
        .background(WindowTitleSetter(title: "\(item.name) Settings"))
    }

    private var tabBar: some View {
        HStack(spacing: 4) {
            ForEach(Tab.allCases) { t in
                Button {
                    tab = t
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: t.systemImage)
                            .font(.system(size: 16, weight: .regular))
                        Text(t.title)
                            .font(.system(size: 11))
                    }
                    .foregroundStyle(tab == t ? Theme.link : Theme.textSecondary)
                    .frame(width: 78, height: 56)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(tab == t ? Color.primary.opacity(0.10) : .clear)
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(t.title)
                .accessibilityAddTraits(tab == t ? .isSelected : [])
            }
        }
        .padding(.top, 2)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Settings sections")
    }

    private func runningBanner(item: VMItem) -> some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: "info.circle")
                .foregroundStyle(Theme.link)
                .accessibilityHidden(true)
            Text("\(item.name) is running. Hardware, storage and network changes apply after it shuts down.")
                .font(Theme.Font.small)
                .foregroundStyle(Color(light: 0x0066CC, dark: 0xB9DAFF))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            Button("Shut Down") {
                Task {
                    do { try item.session?.requestShutDown() }
                    catch { alert = .from(error) }
                }
            }
            .buttonStyle(.covesecondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Theme.accent.opacity(0.12))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.accent.opacity(0.3)))
        )
        .accessibilityElement(children: .combine)
    }

    private var divider: some View {
        Rectangle().fill(Theme.separator).frame(height: 1)
    }

    private func footer(item: VMItem, draft: VMConfig) -> some View {
        HStack {
            if draft != item.config {
                Text("Unsaved changes")
                    .font(Theme.Font.small)
                    .foregroundStyle(Theme.textTertiary)
            }
            Spacer()
            Button("Revert") { self.draft = item.config }
                .buttonStyle(.covesecondary)
                .disabled(draft == item.config || isSaving)
            Button("Save") { save(item: item, draft: draft) }
                .buttonStyle(.coveprimary)
                .disabled(draft == item.config || isSaving || draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(Theme.toolbar)
    }

    // MARK: - Tabs

    @ViewBuilder
    private func generalTab(item: VMItem, draft: Binding<VMConfig>) -> some View {
        block("Identity") {
            row {
                Text("Name")
                Spacer()
                TextField("Name", text: draft.name)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 220)
                    .accessibilityLabel("Name")
            }
            CardDivider()
            row {
                Text("Notes")
                Spacer()
                TextField("Notes", text: draft.notes, axis: .vertical)
                    .lineLimit(2...4)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 280)
                    .accessibilityLabel("Notes")
            }
            CardDivider()
            SpecRow("macOS", osLabel(item.config))
            CardDivider()
            SpecRow("Created", createdLabel(item.config.createdAt))
            CardDivider()
            row {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Stored at")
                    Text(item.bundle.url.path)
                        .font(Theme.Font.mono)
                        .foregroundStyle(Theme.textTertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer(minLength: 8)
                Button("Show in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([item.bundle.url])
                }
                .buttonStyle(.covesecondary)
            }
        }
    }

    @ViewBuilder
    private func hardwareTab(item: VMItem, draft: Binding<VMConfig>, isLive: Bool) -> some View {
        let planner = HostInfo.planner(freeDiskAt: library.rootURL)
        let limits = planner.limits
        let remainder = planner.hostRemainder(cpu: draft.wrappedValue.cpuCount, memory: draft.wrappedValue.memoryBytes)

        block("Hardware") {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Processors")
                    Spacer()
                    Text("\(draft.wrappedValue.cpuCount) cores")
                        .monospacedDigit()
                        .foregroundStyle(Theme.textSecondary)
                }
                Slider(
                    value: Binding(
                        get: { Double(draft.wrappedValue.cpuCount) },
                        set: { draft.wrappedValue.cpuCount = planner.clampCPU(Int($0.rounded())) }
                    ),
                    in: Double(limits.minCPU)...Double(max(limits.minCPU, limits.maxCPU)),
                    step: 1
                )
                .disabled(isLive)
                .accessibilityLabel("Processors")
                .accessibilityValue("\(draft.wrappedValue.cpuCount) cores")
            }
            .font(Theme.Font.body)
            .padding(.horizontal, 14)
            .padding(.vertical, 11)

            CardDivider()

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Memory")
                    Spacer()
                    Text(Bytes.formatMemory(draft.wrappedValue.memoryBytes))
                        .monospacedDigit()
                        .foregroundStyle(Theme.textSecondary)
                }
                memorySlider(draft: draft, planner: planner, enabled: !isLive)
            }
            .font(Theme.Font.body)
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            CardDivider()
            Text(remainderNote(remainder))
                .font(Theme.Font.small)
                .foregroundStyle(remainder.tight ? Theme.warning : Theme.textTertiary)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
        }

        block("Audio") {
            toggleRow("Sound output", isOn: draft.audioEnabled)
        }
    }

    @ViewBuilder
    private func displayTab(draft: Binding<VMConfig>) -> some View {
        block("Display") {
            row {
                Text("Resolution")
                Spacer()
                Picker("Resolution", selection: displaySelection(draft)) {
                    Text("Match this Mac’s display").tag(DisplayChoice.matchHost)
                    ForEach(DisplaySettings.presets, id: \.self) { preset in
                        Text(preset.label).tag(DisplayChoice.preset(preset))
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(maxWidth: 260)
            }
        }
    }

    @ViewBuilder
    private func storageTab(item: VMItem, draft: Binding<VMConfig>, isLive: Bool) -> some View {
        let planner = HostInfo.planner(freeDiskAt: library.rootURL)
        let capacity = max(item.bundle.diskCapacity, draft.wrappedValue.diskBytes)
        let used = item.bundle.diskAllocated
        let minDisk = max(capacity, planner.limits.minDisk)
        let maxDisk = max(minDisk, planner.limits.maxDisk)
        let snapshotBytes = snapshotSpace(item)

        block("Disks") {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Macintosh HD").fontWeight(.semibold)
                    Spacer()
                    Text("\(Bytes.format(used)) used of \(Bytes.format(capacity))")
                        .foregroundStyle(Theme.textSecondary)
                }
                UsageBar(fraction: capacity == 0 ? 0 : Double(used) / Double(capacity))
                HStack {
                    Text("Capacity")
                    Spacer()
                    Stepper(value: Binding(
                        get: { Bytes.toGB(draft.wrappedValue.diskBytes) },
                        set: { gb in
                            let bytes = Bytes.gb(gb)
                            draft.wrappedValue.diskBytes = planner.clampDisk(max(bytes, minDisk))
                        }
                    ), in: Bytes.toGB(minDisk)...max(Bytes.toGB(minDisk), Bytes.toGB(maxDisk)), step: 8) {
                        Text("\(Bytes.toGB(draft.wrappedValue.diskBytes)) GB")
                            .monospacedDigit()
                            .frame(minWidth: 64, alignment: .trailing)
                    }
                    .disabled(isLive)
                    .accessibilityLabel("Disk capacity")
                }
                Text("Virtual disks can only grow. Shrinking would corrupt the guest file system.")
                    .font(Theme.Font.small)
                    .foregroundStyle(Theme.textTertiary)
            }
            .font(Theme.Font.body)
            .padding(14)

            CardDivider()
            row {
                Text("Snapshots")
                Spacer()
                Text("\(item.snapshots.count) · \(Bytes.format(snapshotBytes))")
                    .foregroundStyle(Theme.textSecondary)
                Button("Manage…") {
                    openWindow(id: WindowID.snapshots, value: item.id)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.link)
            }
        }
    }

    @ViewBuilder
    private func networkTab(item: VMItem, draft: Binding<VMConfig>, isLive: Bool) -> some View {
        block("Network") {
            row {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Mode")
                    Text("Shared uses your Mac’s connection. Bridged puts the VM on your local network.")
                        .font(Theme.Font.small)
                        .foregroundStyle(Theme.textTertiary)
                }
                Spacer(minLength: 12)
                Picker("Network mode", selection: networkSelection(draft)) {
                    Text("Shared (NAT)").tag(NetworkChoice.nat)
                    if NetworkMode.bridgedAvailable {
                        Text("Bridged").tag(NetworkChoice.bridged)
                    } else {
                        Text("Bridged (unavailable)").tag(NetworkChoice.bridged)
                    }
                    Text("Disconnected").tag(NetworkChoice.none)
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .disabled(isLive)
                .frame(maxWidth: 200)
            }
            if !NetworkMode.bridgedAvailable {
                Text("Requires the com.apple.vm.networking entitlement.")
                    .font(Theme.Font.small)
                    .foregroundStyle(Theme.textTertiary)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 8)
            }
            CardDivider()
            row {
                Text("MAC address")
                Spacer()
                Text(draft.wrappedValue.macAddress ?? "—")
                    .font(Theme.Font.mono)
                    .foregroundStyle(Theme.textSecondary)
                    .textSelection(.enabled)
                Button("Copy") {
                    if let mac = draft.wrappedValue.macAddress {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(mac, forType: .string)
                    }
                }
                .buttonStyle(.covesecondary)
                .disabled(draft.wrappedValue.macAddress == nil)
                Button("Regenerate") {
                    draft.wrappedValue.macAddress = VZMACAddress.randomLocallyAdministered().string
                }
                .buttonStyle(.covesecondary)
                .disabled(isLive)
                .accessibilityLabel("Regenerate MAC address")
            }
        }
    }

    @ViewBuilder
    private func sharingTab(draft: Binding<VMConfig>) -> some View {
        block("Shared folders") {
            if draft.wrappedValue.shares.isEmpty {
                Text("No shared folders")
                    .font(Theme.Font.body)
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 11)
                CardDivider()
            } else {
                ForEach(Array(draft.wrappedValue.shares.enumerated()), id: \.element.id) { index, share in
                    HStack(spacing: 12) {
                        Image(systemName: "folder.fill")
                            .foregroundStyle(Theme.accent)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(share.name)
                            Text(share.path)
                                .font(Theme.Font.small)
                                .foregroundStyle(Theme.textTertiary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        Spacer(minLength: 8)
                        Toggle("Enabled", isOn: Binding(
                            get: { draft.wrappedValue.shares[index].enabled },
                            set: { draft.wrappedValue.shares[index].enabled = $0 }
                        ))
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .accessibilityLabel("Enabled")
                        Picker("Access", selection: Binding(
                            get: { draft.wrappedValue.shares[index].readOnly },
                            set: { draft.wrappedValue.shares[index].readOnly = $0 }
                        )) {
                            Text("Read & write").tag(false)
                            Text("Read only").tag(true)
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .frame(width: 120)
                        Button("Remove") {
                            draft.wrappedValue.shares.removeAll { $0.id == share.id }
                        }
                        .buttonStyle(.covesecondary)
                        .accessibilityLabel("Remove \(share.name)")
                    }
                    .font(Theme.Font.body)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 11)
                    CardDivider()
                }
            }
            Button {
                addSharedFolder(draft: draft)
            } label: {
                Label("Add folder…", systemImage: "plus")
                    .foregroundStyle(Theme.link)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .accessibilityLabel("Add folder")
        }

        Text("In the VM, shared folders appear under /Volumes/My Shared Files. Requires macOS 13 or later in the VM.")
            .font(Theme.Font.small)
            .foregroundStyle(Theme.textTertiary)
            .padding(.horizontal, 4)
    }

    @ViewBuilder
    private func advancedTab(item: VMItem, isLive: Bool) -> some View {
        block("Startup") {
            row {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Start in macOS Recovery")
                    Text("For Disk Utility, reinstalling, or changing security settings")
                        .font(Theme.Font.small)
                        .foregroundStyle(Theme.textTertiary)
                }
                Spacer()
                Button("Start in Recovery") {
                    Task {
                        do { try await library.start(item, recovery: true) }
                        catch { alert = .from(error) }
                    }
                }
                .buttonStyle(.covesecondary)
                .disabled(isLive)
            }
        }

        block("Identity") {
            row {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Machine identifier")
                    Text("Regenerating makes macOS treat the VM as a different Mac")
                        .font(Theme.Font.small)
                        .foregroundStyle(Theme.textTertiary)
                }
                Spacer()
                Button("Regenerate…") { confirmRegenerateID = true }
                    .buttonStyle(.covesecondary)
                    .disabled(isLive)
            }
        }

        block("Manage") {
            row {
                Text("Duplicate this VM")
                Spacer()
                Button("Clone…") {
                    cloneName = library.uniqueName("\(item.name) Copy")
                    confirmClone = true
                }
                .buttonStyle(.covesecondary)
                .disabled(isLive)
            }
            CardDivider()
            row {
                Text("Save as a single file to move or back up")
                Spacer()
                Button("Export…") { exportVM(item) }
                    .buttonStyle(.covesecondary)
                    .disabled(isLive)
            }
            CardDivider()
            row {
                Text("Delete this VM and its snapshots")
                Spacer()
                Button("Delete…") {
                    alert = .confirmDelete(vmID: item.id, name: item.name, snapshotCount: item.snapshots.count)
                }
                .buttonStyle(SecondaryButtonStyle(destructive: true))
                .disabled(isLive)
            }
        }
        .alert("Regenerate machine identifier?", isPresented: $confirmRegenerateID) {
            Button("Regenerate", role: .destructive) {
                do {
                    try item.bundle.regenerateMachineIdentifier()
                    item.refresh()
                } catch {
                    alert = .from(error)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("macOS will treat this VM as a different Mac. The VM must be shut down. Any suspended state will be discarded.")
        }
        .alert("Clone “\(item.name)”?", isPresented: $confirmClone) {
            TextField("Name", text: $cloneName)
            Button("Clone") {
                do {
                    _ = try library.clone(item, name: cloneName)
                } catch {
                    alert = .from(error)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Creates a copy with a new machine identity and MAC address.")
        }
    }

    // MARK: - Bindings & actions

    private func draftBinding(for item: VMItem) -> Binding<VMConfig> {
        Binding(
            get: { draft ?? item.config },
            set: { draft = $0 }
        )
    }

    private func loadDraft() {
        guard let item = library.item(id: vmID) else {
            draft = nil
            return
        }
        if draft == nil || draft?.id != item.config.id {
            draft = item.config
        }
    }

    private func save(item: VMItem, draft: VMConfig) {
        isSaving = true
        defer { isSaving = false }
        var next = draft
        next.name = next.name.trimmingCharacters(in: .whitespacesAndNewlines)
        next.cpuCount = HostInfo.planner(freeDiskAt: library.rootURL).clampCPU(next.cpuCount)
        next.memoryBytes = HostInfo.planner(freeDiskAt: library.rootURL).clampMemory(next.memoryBytes)
        if next.diskBytes < item.bundle.diskCapacity {
            next.diskBytes = item.bundle.diskCapacity
        }
        do {
            try library.update(item, config: next)
            self.draft = item.config
        } catch {
            alert = .from(error)
        }
    }

    private func addSharedFolder(draft: Binding<VMConfig>) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Add"
        panel.message = "Choose a folder to share with the virtual machine"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let share = try ConfigurationBuilder.makeShare(for: url, readOnly: false)
            draft.wrappedValue.shares.append(share)
        } catch {
            alert = .from(error)
        }
    }

    private func exportVM(_ item: VMItem) {
        let panel = NSSavePanel()
        if let type = UTType(filenameExtension: VMBundle.pathExtension) {
            panel.allowedContentTypes = [type]
        }
        panel.allowsOtherFileTypes = true
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = "\(item.name).\(VMBundle.pathExtension)"
        panel.prompt = "Export"
        panel.message = "Export a copy of this virtual machine package"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try library.export(item, to: url)
        } catch {
            alert = .from(error)
        }
    }

    private func dismissWindow() {
        dismiss()
        NSApp.keyWindow?.close()
    }

    // MARK: - Small UI helpers

    private func block<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionHeader(title: LocalizedStringKey(title))
                .padding(.leading, 4)
            GroupedCard { content() }
        }
    }

    private func row<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .center, spacing: 12) {
            content()
        }
        .font(Theme.Font.body)
        .foregroundStyle(Theme.textPrimary)
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }

    private func toggleRow(_ title: String, isOn: Binding<Bool>) -> some View {
        row {
            Text(title)
            Spacer()
            Toggle(title, isOn: isOn)
                .labelsHidden()
                .toggleStyle(.switch)
        }
    }

    private func memorySlider(draft: Binding<VMConfig>, planner: ResourcePlanner, enabled: Bool) -> some View {
        let minGB = Double(Bytes.toGB(planner.limits.minMemory))
        let maxGB = Double(max(Bytes.toGB(planner.limits.minMemory), Bytes.toGB(planner.limits.maxMemory)))
        return Slider(
            value: Binding(
                get: { Double(Bytes.toGB(draft.wrappedValue.memoryBytes)) },
                set: { draft.wrappedValue.memoryBytes = planner.clampMemory(Bytes.gb(Int($0.rounded()))) }
            ),
            in: minGB...max(minGB, maxGB),
            step: 1
        )
        .disabled(!enabled)
        .accessibilityLabel("Memory")
        .accessibilityValue(Bytes.formatMemory(draft.wrappedValue.memoryBytes))
    }

    private func remainderNote(_ rem: (cores: Int, memoryGB: Int, tight: Bool)) -> String {
        var note = "Your Mac keeps \(rem.cores) core\(rem.cores == 1 ? "" : "s") and \(rem.memoryGB) GB"
        if rem.tight { note += " — that’s tight for this Mac" }
        return note
    }

    private func osLabel(_ config: VMConfig) -> String {
        var parts: [String] = []
        if let v = config.osVersion {
            parts.append(MacOSNames.describe(version: v))
        } else {
            parts.append("macOS")
        }
        if let build = config.osBuild, !build.isEmpty {
            parts.append("(\(build))")
        }
        return parts.joined(separator: " ")
    }

    private func createdLabel(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .shortened)
    }

    private func snapshotSpace(_ item: VMItem) -> UInt64 {
        FileClone.allocatedSize(of: item.bundle.snapshotsURL)
    }

    // MARK: - Network / display choice wrappers

    private enum NetworkChoice: Hashable {
        case nat, bridged, none
    }

    private func networkSelection(_ draft: Binding<VMConfig>) -> Binding<NetworkChoice> {
        Binding(
            get: {
                switch draft.wrappedValue.network {
                case .nat: .nat
                case .bridged: .bridged
                case .none: .none
                }
            },
            set: { choice in
                switch choice {
                case .nat:
                    draft.wrappedValue.network = .nat
                case .bridged:
                    if NetworkMode.bridgedAvailable {
                        draft.wrappedValue.network = .bridged(interface: "en0")
                    }
                    // Keep previous selection when entitlement is missing.
                case .none:
                    draft.wrappedValue.network = .none
                }
            }
        )
    }

    private enum DisplayChoice: Hashable {
        case matchHost
        case preset(DisplaySettings)
    }

    private func displaySelection(_ draft: Binding<VMConfig>) -> Binding<DisplayChoice> {
        Binding(
            get: {
                if draft.wrappedValue.display.matchesHost { return .matchHost }
                if let match = DisplaySettings.presets.first(where: { $0 == draft.wrappedValue.display }) {
                    return .preset(match)
                }
                return .preset(draft.wrappedValue.display)
            },
            set: { choice in
                switch choice {
                case .matchHost:
                    draft.wrappedValue.display = .matchHost
                case .preset(let settings):
                    draft.wrappedValue.display = settings
                }
            }
        )
    }
}

/// Sets the NSWindow title for WindowGroup scenes that don't pick up navigationTitle alone.
private struct WindowTitleSetter: NSViewRepresentable {
    var title: String

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { view.window?.title = title }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { nsView.window?.title = title }
    }
}
