import SwiftUI
import UniformTypeIdentifiers

struct NewVMView: View {
    var initialPurpose: VMPurpose = .everyday
    var onDismiss: () -> Void = {}
    @Environment(VMLibrary.self) private var library
    @AppStorage(Pref.defaultProfile) private var defaultProfile = ResourcePlanner.Profile.balanced.rawValue
    @AppStorage(Pref.defaultStartAfterInstall) private var defaultStart = true
    @AppStorage(Pref.defaultKeepRestoreImage) private var defaultKeepImage = true
    @AppStorage(Pref.snapshotAfterInstall) private var snapshotAfterInstall = true

    @State private var step = 1
    @State private var source: SourceChoice = .latest
    @State private var selectedCachedImage: URL?
    @State private var name = ""
    @State private var startAfterInstall = true
    @State private var keepRestoreImage = true
    @State private var cpu = 4
    @State private var memory: UInt64 = Bytes.gb(8)
    @State private var disk: UInt64 = Bytes.gb(80)
    @State private var display = DisplaySettings.matchHost
    @State private var network: NetworkMode = .nat
    @State private var shares: [SharedFolder] = []
    @State private var alert: CoveAlert?
    @State private var purpose: VMPurpose = .everyday
    /// Set once the user types their own name, so switching purpose doesn't overwrite it.
    @State private var nameEdited = false
    @State var diskSpace = DiskSpaceMonitor.shared

    private var planner: ResourcePlanner { HostInfo.planner(freeDiskAt: library.rootURL) }
    private var profile: ResourcePlanner.Profile { ResourcePlanner.Profile(rawValue: defaultProfile) ?? .balanced }
    private var recommended: (cpu: Int, memory: UInt64, disk: UInt64) { planner.recommended(profile) }
    private var cachedImages: [URL] { library.restoreImages }
    private var chosenSource: VMInstallJob.Source {
        switch source {
        case .latest: .latest
        case .version: .file(selectedCachedImage ?? cachedImages.first ?? URL(fileURLWithPath: "/"))
        case .file: .file(selectedFileURL ?? URL(fileURLWithPath: "/"))
        }
    }
    private var canCreate: Bool { !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && sourceIsValid }
    private var sourceIsValid: Bool {
        switch source {
        case .latest: true
        case .file: selectedFileURL != nil
        case .version: selectedCachedImage != nil || !cachedImages.isEmpty
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Text("New Virtual Machine").font(.system(size: 13, weight: .semibold))
                Spacer()
            }
            .padding(.horizontal, 24).frame(height: 44)
            .background(Theme.toolbar)
            .overlay(alignment: .bottom) { Rectangle().fill(Theme.separator).frame(height: 1) }

            if diskSpace.level != .normal, let available = diskSpace.available {
                LowDiskSpaceBanner(available: available).padding(.horizontal, 24).padding(.top, 14)
            }
            stepIndicator.padding(.top, 18)
            // Scrolls when the window is short, so the title and buttons are never pushed out of view.
            ScrollView {
                Group {
                    if step == 1 { sourceStep } else { customizeStep }
                }
                .frame(maxWidth: .infinity, alignment: .top)
                .padding(.horizontal, 32)
                .padding(.vertical, 20)
            }
            .scrollBounceBehavior(.basedOnSize)

            footer
        }
        .background(Theme.windowBackground)
        .frame(minWidth: 860, idealWidth: 900, minHeight: 420, idealHeight: 700)
        .onAppear {
            purpose = initialPurpose
            if name.isEmpty { name = library.uniqueName(purpose.defaultName) }
            startAfterInstall = defaultStart
            keepRestoreImage = defaultKeepImage
            resetResources()
        }
        .coveAlert($alert)
    }

    private var stepIndicator: some View {
        HStack(spacing: 12) {
            stepPill(1, "macOS")
            Rectangle().fill(Theme.control).frame(width: 42, height: 1)
            stepPill(2, "Resources")
            Rectangle().fill(Theme.control).frame(width: 42, height: 1)
            HStack(spacing: 7) { Circle().stroke(Theme.textTertiary, lineWidth: 1).frame(width: 22, height: 22).overlay(Text("3").font(Theme.Font.small)); Text("Install") }
                .foregroundStyle(Theme.textTertiary)
        }
        .font(Theme.Font.body)
    }

    private func stepPill(_ number: Int, _ title: String) -> some View {
        HStack(spacing: 7) {
            Circle().fill(step >= number ? Theme.accent : .clear).frame(width: 22, height: 22)
                .overlay(Circle().stroke(step >= number ? Theme.accent : Theme.textTertiary, lineWidth: 1))
                .overlay(Text("\(number)").font(Theme.Font.small).foregroundStyle(step >= number ? .white : Theme.textSecondary))
            Text(title).fontWeight(step == number ? .semibold : .regular)
        }
        .foregroundStyle(step >= number ? Theme.textPrimary : Theme.textSecondary)
    }

    private var sourceStep: some View {
        HStack(alignment: .top, spacing: 24) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Which macOS do you want?").font(Theme.Font.title).padding(.bottom, 4)
                sourceCard(.latest, title: "Latest from Apple", subtitle: "Cove asks Apple for the newest macOS this Mac can run and downloads the signed restore image. Nothing to find or pick.", trailing: "≈ 25 GB download", recommended: true)
                versionCard
                fileCard
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .leading, spacing: 15) {
                purposePicker
                GroupedCard {
                    VStack(alignment: .leading, spacing: 14) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Name").font(Theme.Font.small).foregroundStyle(Theme.textSecondary)
                            TextField("Virtual machine name", text: Binding(get: { name }, set: { new in
                                if new != name { name = new; nameEdited = true }
                            }))
                                .textFieldStyle(.roundedBorder)
                        }
                        HStack {
                            Text("Sized for your Mac").font(.system(size: 13, weight: .semibold))
                            Spacer()
                            Button("Customize…") { step = 2 }.buttonStyle(.link)
                        }
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                            summaryCell("CPU", "\(cpu) cores")
                            summaryCell("Memory", Bytes.formatMemory(memory))
                            summaryCell("Disk", Bytes.formatMemory(disk))
                            summaryCell("Display", display.matchesHost ? "Retina" : display.label)
                        }
                        Text("Sized so your Mac stays fast. The disk only uses space as macOS fills it.")
                            .font(Theme.Font.small).foregroundStyle(Theme.textTertiary).fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(16)
                }
                Toggle("Start the VM when installation finishes", isOn: $startAfterInstall)
                    .font(Theme.Font.body).toggleStyle(.checkbox)
                Toggle("Keep the restore image for future VMs", isOn: $keepRestoreImage)
                    .font(Theme.Font.body).toggleStyle(.checkbox)
            }
            .frame(width: 320)
        }
    }

    private var purposePicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("What’s it for?").font(Theme.Font.small).foregroundStyle(Theme.textSecondary)
            VStack(spacing: 0) {
                ForEach(Array(VMPurpose.allCases.enumerated()), id: \.element) { index, p in
                    if index > 0 { CardDivider() }
                    Button { choose(p) } label: {
                        HStack(spacing: 10) {
                            Image(systemName: p.systemImage)
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(purpose == p ? Theme.accent : Theme.textSecondary)
                                .frame(width: 22)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(p.title).font(.system(size: 13, weight: .semibold))
                                if purpose == p {
                                    Text(p.summary).font(Theme.Font.caption).foregroundStyle(Theme.textTertiary)
                                        .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                                }
                            }
                            Spacer(minLength: 4)
                            Image(systemName: purpose == p ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(purpose == p ? Theme.accent : Theme.textTertiary.opacity(0.6))
                        }
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(purpose == p ? Theme.accent.opacity(0.10) : .clear)
                    }
                    .buttonStyle(.coveplain)
                    .accessibilityLabel(p.title)
                    .accessibilityHint(p.summary)
                    .accessibilityAddTraits(purpose == p ? .isSelected : [])
                }
            }
            .background(Theme.cell, in: RoundedRectangle(cornerRadius: 12))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.cellBorder))
            if purpose == .agentSandbox {
                Label("SSH access and passwordless sudo are turned on. After installing, finish setup in SSH & Agent Access.",
                      systemImage: "key")
                    .font(Theme.Font.caption).foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func choose(_ p: VMPurpose) {
        purpose = p
        if !nameEdited { name = library.uniqueName(p.defaultName) }
        resetResources()
    }

    private func sourceCard(_ kind: SourceKind, title: String, subtitle: String, trailing: String? = nil, recommended: Bool = false) -> some View {
        Button { source = .latest } label: {
            HStack(alignment: .top, spacing: 13) {
                Image(systemName: sourceSelection(kind) ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: 16)).foregroundStyle(sourceSelection(kind) ? Theme.accent : Theme.textTertiary).padding(.top, 2)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(title).font(.system(size: 15, weight: .semibold))
                        if recommended { Text("Recommended").font(Theme.Font.captionStrong).padding(.horizontal, 7).padding(.vertical, 3).background(Theme.accent.opacity(0.16), in: Capsule()).foregroundStyle(Theme.link) }
                    }
                    Text(subtitle).font(Theme.Font.body).foregroundStyle(Theme.textSecondary).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 4)
                if let trailing { Text(trailing).font(Theme.Font.small).foregroundStyle(Theme.textTertiary).fixedSize() }
            }
            .padding(.horizontal, 16).padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(sourceSelection(kind) ? Theme.accent.opacity(0.10) : Theme.cell, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(sourceSelection(kind) ? Theme.accent : Theme.cellBorder, lineWidth: sourceSelection(kind) ? 1.5 : 1))
            .contentShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.coveplain)
    }

    private enum SourceChoice { case latest, version, file }
    private typealias SourceKind = SourceChoice
    private func sourceSelection(_ kind: SourceKind) -> Bool {
        switch (kind, source) {
        case (.latest, .latest), (.version, .version), (.file, .file): true
        default: false
        }
    }

    private var versionCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button { source = .version; if selectedCachedImage == nil { selectedCachedImage = cachedImages.first } } label: {
                HStack(spacing: 13) {
                    Image(systemName: sourceSelection(.version) ? "largecircle.fill.circle" : "circle").font(.system(size: 16)).foregroundStyle(sourceSelection(.version) ? Theme.accent : Theme.textTertiary)
                    Text("A specific version").font(.system(size: 15, weight: .semibold))
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.coveplain)
            if cachedImages.isEmpty {
                Text("No cached restore images yet. Choose a local .ipsw file below to install a specific version.")
                    .font(Theme.Font.body).foregroundStyle(Theme.textSecondary).padding(.leading, 29)
            } else {
                HStack(spacing: 8) {
                    Picker("Cached restore image", selection: $selectedCachedImage) {
                        ForEach(cachedImages, id: \.self) { url in Text(url.deletingPathExtension().lastPathComponent).tag(Optional(url)) }
                    }.labelsHidden().frame(maxWidth: 280)
                    Text("Cached restore images").font(Theme.Font.small).foregroundStyle(Theme.textTertiary)
                }.padding(.leading, 29)
                Text("Good for installing a previously downloaded macOS release.").font(Theme.Font.small).foregroundStyle(Theme.textTertiary).padding(.leading, 29)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(sourceSelection(.version) ? Theme.accent.opacity(0.10) : Theme.cell, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(sourceSelection(.version) ? Theme.accent : Theme.cellBorder, lineWidth: sourceSelection(.version) ? 1.5 : 1))
    }

    private var fileCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button { source = .file } label: {
                HStack(spacing: 13) {
                    Image(systemName: sourceSelection(.file) ? "largecircle.fill.circle" : "circle").font(.system(size: 16)).foregroundStyle(sourceSelection(.file) ? Theme.accent : Theme.textTertiary)
                    Text("A restore image on this Mac").font(.system(size: 15, weight: .semibold))
                    Spacer()
                }
                .contentShape(Rectangle())
            }.buttonStyle(.coveplain)
            HStack(spacing: 12) {
                Image(systemName: "doc.badge.arrow.down").font(.system(size: 20)).foregroundStyle(Theme.textSecondary)
                Text(selectedFileURL?.lastPathComponent ?? "Drop an .ipsw file here")
                    .font(Theme.Font.body).foregroundStyle(Theme.textSecondary).lineLimit(1)
                Spacer(minLength: 0)
                Button("Choose File…", action: chooseIPSW).buttonStyle(.covesecondary)
            }
            .padding(13)
            .background(Theme.field, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.textTertiary.opacity(0.6), style: StrokeStyle(lineWidth: 1, dash: [5])))
            .padding(.leading, 29)
        }
        .padding(16)
        .background(sourceSelection(.file) ? Theme.accent.opacity(0.10) : Theme.cell, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(sourceSelection(.file) ? Theme.accent : Theme.cellBorder, lineWidth: sourceSelection(.file) ? 1.5 : 1))
    }

    @State private var selectedFileURL: URL?
    private func chooseIPSW() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "ipsw") ?? .data]
        panel.allowsOtherFileTypes = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        selectedFileURL = url
        source = .file
    }

    private func summaryCell(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).font(Theme.Font.caption).foregroundStyle(Theme.textTertiary)
            Text(value).font(.system(size: 14, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(10).background(Theme.sidebar, in: RoundedRectangle(cornerRadius: 9))
    }

    private var customizeStep: some View {
        HStack(alignment: .top, spacing: 24) {
            VStack(alignment: .leading, spacing: 16) {
                Text("Customize Resources").font(Theme.Font.title)
                settingsGroup("Hardware") {
                    sliderRow("Processors", value: Binding(get: { Double(cpu) }, set: { cpu = planner.clampCPU(Int($0)) }), range: Double(planner.limits.minCPU)...Double(planner.limits.maxCPU), valueText: "\(cpu) cores", ends: ["\(planner.limits.minCPU)", "\(planner.limits.maxCPU)"])
                    sliderRow("Memory", value: Binding(get: { Double(memory / Bytes.gib) }, set: { memory = planner.clampMemory(UInt64($0) * Bytes.gib) }), range: Double(max(1, planner.limits.minMemory / Bytes.gib))...Double(max(planner.limits.minMemory, planner.limits.maxMemory) / Bytes.gib), valueText: Bytes.formatMemory(memory), ends: [Bytes.formatMemory(planner.limits.minMemory), Bytes.formatMemory(planner.limits.maxMemory)])
                    let remainder = planner.hostRemainder(cpu: cpu, memory: memory)
                    Label(remainder.tight ? "Your Mac keeps only \(remainder.cores) cores and \(remainder.memoryGB) GB. It may feel slow while the VM runs." : "Your Mac keeps \(remainder.cores) cores and \(remainder.memoryGB) GB of memory.", systemImage: "desktopcomputer")
                        .font(Theme.Font.small).foregroundStyle(remainder.tight ? Theme.warning : Theme.textSecondary).fixedSize(horizontal: false, vertical: true)
                }
                settingsGroup("Storage") {
                    sliderRow("Disk size", value: Binding(get: { Double(disk / Bytes.gib) }, set: { disk = planner.clampDisk(UInt64($0) * Bytes.gib) }), range: Double(planner.limits.minDisk / Bytes.gib)...Double(max(planner.limits.minDisk, planner.limits.maxDisk) / Bytes.gib), valueText: Bytes.formatMemory(disk), ends: [Bytes.formatMemory(planner.limits.minDisk), Bytes.formatMemory(planner.limits.maxDisk)])
                    Text("Space is used only as the VM fills it. You can grow the disk later.").font(Theme.Font.small).foregroundStyle(Theme.textTertiary)
                    HStack { Text("Location"); Spacer(); Text("Cove Library").foregroundStyle(Theme.textSecondary) }.font(Theme.Font.body)
                }
            }
            .frame(maxWidth: .infinity)
            VStack(alignment: .leading, spacing: 16) {
                settingsGroup("Display") {
                    Picker("Resolution", selection: $display) {
                        Text("Match this Mac’s display").tag(DisplaySettings.matchHost)
                        ForEach(DisplaySettings.presets, id: \.self) { Text($0.label).tag($0) }
                    }
                }
                settingsGroup("Network") {
                    Picker("Mode", selection: $network) {
                        Text("Shared (NAT)").tag(NetworkMode.nat)
                        if NetworkMode.bridgedAvailable { Text("Bridged").tag(NetworkMode.bridged(interface: "en0")) }
                        else { Text("Bridged · Requires approval from Apple").tag(NetworkMode.nat).disabled(true) }
                        Text("Disconnected").tag(NetworkMode.none)
                    }
                    Text("MAC address · Generated automatically").font(Theme.Font.small).foregroundStyle(Theme.textSecondary)
                }
                settingsGroup("Shared folders") {
                    if shares.isEmpty { Text("No shared folders").font(Theme.Font.body).foregroundStyle(Theme.textTertiary) }
                    ForEach($shares) { $share in
                        HStack(spacing: 8) {
                            Image(systemName: "folder.fill").foregroundStyle(Theme.accent)
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(share.name).font(Theme.Font.body)
                                Text(share.path).font(Theme.Font.caption).foregroundStyle(Theme.textTertiary).lineLimit(1)
                            }
                            Spacer(minLength: 0)
                            Toggle("Read only", isOn: $share.readOnly).labelsHidden().help("Read only")
                            Button { shares.removeAll { $0.id == share.id } } label: { Image(systemName: "minus.circle") }
                                .buttonStyle(.coveplain).foregroundStyle(Theme.destructive).accessibilityLabel("Remove shared folder \(share.name)")
                        }
                    }
                    Button { addFolder() } label: { Label("Add folder…", systemImage: "plus") }.buttonStyle(.link)
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func settingsGroup<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionHeader(title: LocalizedStringKey(title.uppercased()))
            VStack(alignment: .leading, spacing: 12) { content() }
                .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.cell, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.cellBorder))
        }
    }

    private func sliderRow(_ label: String, value: Binding<Double>, range: ClosedRange<Double>, valueText: String, ends: [String]) -> some View {
        VStack(spacing: 5) {
            HStack { Text(label); Spacer(); Text(valueText).fontWeight(.semibold).monospacedDigit() }.font(Theme.Font.body)
            Slider(value: value, in: range, step: label == "Processors" ? 1 : 1)
            HStack { Text(ends[0]); Spacer(); Text(ends[1]) }.font(Theme.Font.caption).foregroundStyle(Theme.textTertiary)
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            if step == 2 {
                Button("Restore recommended") { resetResources() }.buttonStyle(.link)
            } else {
                Text(footerText).font(Theme.Font.small).foregroundStyle(Theme.textTertiary).lineLimit(2)
            }
            Spacer(minLength: 8)
            Button("Cancel", action: onDismiss).buttonStyle(.covesecondary)
            if step == 2 {
                Button("Back") { step = 1 }.buttonStyle(.covesecondary)
            }
            Button("Create & Install", action: createInstall).buttonStyle(.coveprimary).disabled(!canCreate)
        }
        .padding(.horizontal, 24).frame(height: 58)
        .background(Theme.toolbar)
        .overlay(alignment: .top) { Rectangle().fill(Theme.separator).frame(height: 1) }
    }

    private var footerText: String {
        switch source {
        case .latest: "Cove will download macOS from Apple, then install it. You can keep using your Mac."
        case .version: "Cove verifies the selected restore image, then installs it."
        case .file: "Cove verifies the restore image before installing."
        }
    }

    private func resetResources() {
        cpu = recommended.cpu
        memory = recommended.memory
        disk = planner.clampDisk(purpose.defaultDisk)
    }

    private func addFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.prompt = "Add Shared Folder"
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            do { shares.append(try ConfigurationBuilder.makeShare(for: url)) }
            catch { alert = .error(title: "Couldn’t share folder", message: error.localizedDescription) }
        }
    }

    private func createInstall() {
        let available = library.freeSpace
        guard available >= HostInfo.minimumVMStartFreeSpace else {
            alert = .lowDiskSpace(available: available)
            return
        }
        guard canCreate else { return }
        let request = VMInstallJob.Request(name: name.trimmingCharacters(in: .whitespacesAndNewlines), source: chosenSource,
                                           cpuCount: planner.clampCPU(cpu), memoryBytes: planner.clampMemory(memory), diskBytes: planner.clampDisk(disk),
                                           display: display, network: network, shares: shares, startAfterInstall: startAfterInstall,
                                           keepRestoreImage: keepRestoreImage,
                                           snapshotAfterInstall: snapshotAfterInstall || purpose == .agentSandbox,
                                           purpose: purpose, remoteAccess: purpose.defaultRemoteAccess)
        let job = library.beginInstall(request)
        AppRouter.shared.openInstall(job.id)
        onDismiss()
    }
}
