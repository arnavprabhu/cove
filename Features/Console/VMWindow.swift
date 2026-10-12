import AppKit
import CoreImage
import IOSurface
import SwiftUI
import Virtualization

struct VMWindow: View {
    var vmID: UUID

    @Environment(VMLibrary.self) private var library
    @Environment(\.openWindow) private var openWindow
    @AppStorage(Pref.releaseShortcut) private var releaseShortcut = "ctrl-option"
    @State private var captureKeyboard = false
    @State private var showCaptureToast = false
    @State private var showStopMenu = false
    @State private var confirmForceStop = false
    @State private var confirmRestart = false
    @State private var showSnapshotPrompt = false
    @State private var snapshotName = ""
    @State private var showShares = false
    @State private var showDisplay = false
    @State private var alert: CoveAlert?

    private var item: VMItem? { library.item(id: vmID) }
    private var session: VMSession? { item?.session }
    private var state: VMState { item?.state ?? .stopped }

    var body: some View {
        Group {
            if let item {
                VStack(spacing: 0) {
                    ZStack {
                        Theme.windowBackground
                        // Keep the display up while starting, saving and shutting down so guest dialogs stay visible.
                        if let session, session.state.isLive {
                            VMHostView(session: session, item: item, state: session.state,
                                       capturesKeys: $captureKeyboard, releaseShortcut: releaseShortcut)
                                .background(Color.black)
                            if session.state == .paused { pausedOverlay(session) }
                            if showCaptureToast && captureKeyboard { captureToast }
                        } else {
                            stoppedState(item)
                        }
                    }
                    statusBar(item)
                }
                .navigationTitle(item.name)
                .background(WindowTitleConfigurator(subtitle: state.label).frame(width: 0, height: 0))
                .toolbar { consoleToolbar(item) }
                .confirmationDialog("Shut Down \(item.name)?", isPresented: $showStopMenu, titleVisibility: .visible) {
                    Button("Shut Down") { run { try session?.requestShutDown() } }
                    Button("Force Stop", role: .destructive) { confirmForceStop = true }
                    Button("Suspend") { runAsync { try await session?.suspend() } }
                    Button("Cancel", role: .cancel) {}
                } message: { Text("Shut down the guest, suspend it to disk, or force it to stop.") }
                .confirmationDialog("Force Stop \(item.name)?", isPresented: $confirmForceStop, titleVisibility: .visible) {
                    Button("Force Stop", role: .destructive) { runAsync { try await session?.forceStop() } }
                    Button("Cancel", role: .cancel) {}
                } message: { Text("Unsaved work in the guest may be lost.") }
                .confirmationDialog("Restart \(item.name)?", isPresented: $confirmRestart, titleVisibility: .visible) {
                    Button("Restart", role: .destructive) { runAsync(starting: item) { try await library.restart(item) } }
                    Button("Cancel", role: .cancel) {}
                } message: { Text("The virtual machine will shut down and start again.") }
                .alert("Take Snapshot", isPresented: $showSnapshotPrompt) {
                    TextField("Snapshot name", text: $snapshotName)
                    Button("Take Snapshot") {
                        let name = snapshotName.trimmingCharacters(in: .whitespacesAndNewlines)
                        runAsync { _ = try await SnapshotStore.take(item, name: name.isEmpty ? defaultSnapshotName : name) }
                    }
                    Button("Cancel", role: .cancel) {}
                } message: { Text("Save the current VM state as a snapshot.") }
                .coveAlert($alert)
                .onChange(of: state) { oldValue, newValue in
                    if oldValue.isLive && !newValue.isLive { captureKeyboard = false }
                }
            } else {
                ContentUnavailableView("VM Not Found", systemImage: "macwindow", description: Text("This virtual machine is no longer in the library."))
            }
        }
        .frame(minWidth: 800, minHeight: 560)
    }

    @ToolbarContentBuilder
    private func consoleToolbar(_ item: VMItem) -> some ToolbarContent {
        ToolbarItemGroup(placement: .principal) {
            HStack(spacing: 2) {
                Button {
                    if state == .paused { runAsync { try await session?.resume() } }
                    else if state == .running { runAsync { try await session?.pause() } }
                } label: { Image(systemName: state == .paused ? "play.fill" : "pause.fill") }
                    .help(state == .paused ? "Resume virtual machine" : "Pause virtual machine")
                    .accessibilityLabel(state == .paused ? "Resume" : "Pause")
                    .disabled(state != .paused && state != .running)

                Button { showStopMenu = true } label: { Image(systemName: "power") }
                    .help("Shut down, suspend, or force stop")
                    .accessibilityLabel("Shut Down")
                    .disabled(!state.isLive)

                Button { confirmRestart = true } label: { Image(systemName: "arrow.clockwise") }
                    .help("Restart virtual machine")
                    .accessibilityLabel("Restart")
                    .disabled(!state.isLive)

                Divider().frame(height: 20).padding(.horizontal, 5)

                Button {
                    snapshotName = defaultSnapshotName
                    showSnapshotPrompt = true
                } label: { Image(systemName: "camera") }
                    .help("Take a snapshot")
                    .accessibilityLabel("Take Snapshot")
                    .disabled(state == .starting || state == .saving || state == .stopping)

                Button { showShares.toggle() } label: { Image(systemName: "folder") }
                    .popover(isPresented: $showShares, arrowEdge: .bottom) { sharesPopover(item).frame(width: 330) }
                    .help("Shared folders")
                    .accessibilityLabel("Shared Folders")

                Button { showDisplay.toggle() } label: { Image(systemName: "display") }
                    .popover(isPresented: $showDisplay, arrowEdge: .bottom) { displayPopover(item).padding(16).frame(width: 280) }
                    .help("Display resolution and resize behavior")
                    .accessibilityLabel("Display")

                Button {
                    captureKeyboard.toggle()
                    if captureKeyboard {
                        showCaptureToast = true
                        Task { @MainActor in
                            try? await Task.sleep(for: .seconds(3))
                            showCaptureToast = false
                        }
                    } else { showCaptureToast = false }
                } label: { Image(systemName: "keyboard") }
                    .tint(captureKeyboard ? Theme.accent : nil)
                    .help(captureKeyboard ? "Release keyboard and pointer capture" : "Capture keyboard and pointer")
                    .accessibilityLabel(captureKeyboard ? "Release Keyboard Capture" : "Capture Keyboard and Pointer")
                    .disabled(!state.isLive)

                Button { openWindow(id: WindowID.vmSettings, value: vmID) } label: { Image(systemName: "slider.horizontal.3") }
                    .help("Virtual machine settings")
                    .accessibilityLabel("VM Settings")

                Button { NSApp.keyWindow?.toggleFullScreen(nil) } label: { Image(systemName: "arrow.up.left.and.arrow.down.right") }
                    .help("Enter or exit full screen")
                    .accessibilityLabel("Toggle Full Screen")
            }
            .buttonStyle(.plain)
        }
    }

    private var defaultSnapshotName: String { "Snapshot \(Date.now.formatted(date: .abbreviated, time: .shortened))" }

    private func stoppedState(_ item: VMItem) -> some View {
        VStack(spacing: 12) {
            Image(systemName: item.state == .suspended ? "pause.circle" : "macwindow")
                .font(.system(size: 38, weight: .light)).foregroundStyle(Theme.textSecondary)
            Text(item.state == .suspended ? "Suspended" : item.state.label)
                .font(.system(size: 16, weight: .semibold)).foregroundStyle(Theme.textPrimary)
            if let message = session?.lastError { Text(message).font(Theme.Font.small).foregroundStyle(Theme.destructive).multilineTextAlignment(.center).frame(maxWidth: 420) }
            Button(item.state == .suspended ? "Resume" : "Start") { runAsync(starting: item) { try await library.start(item) } }
                .buttonStyle(.coveprimary)
                .disabled(item.installJob != nil)
            if !library.canStartAnother {
                Text("Two macOS VMs are already running. Start to choose a VM to suspend.")
                    .font(Theme.Font.small).foregroundStyle(Theme.textSecondary).multilineTextAlignment(.center).frame(maxWidth: 430)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func pausedOverlay(_ session: VMSession) -> some View {
        VStack(spacing: 14) {
            Button { runAsync { try await session.resume() } } label: {
                Image(systemName: "play.fill").font(.system(size: 25, weight: .semibold)).foregroundStyle(.white)
                    .frame(width: 76, height: 76).background(.white.opacity(0.16), in: Circle())
            }.buttonStyle(.plain).help("Resume the virtual machine").accessibilityLabel("Resume")
            Text("Paused").font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
            Text("The VM is frozen in memory. Resume to continue exactly where you were.")
                .font(Theme.Font.small).foregroundStyle(Color(hex: 0xA1A1A6))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(hex: 0x0E0E10, opacity: 0.7))
    }

    private var captureToast: some View {
        HStack(spacing: 10) {
            Image(systemName: "keyboard")
            Text("Keyboard and pointer are in the VM · press")
            Text(releaseShortcut == "ctrl-option-cmd" ? "⌃ ⌥ ⌘" : "⌃ ⌥")
                .font(Theme.Font.mono).padding(.horizontal, 6).padding(.vertical, 2)
                .background(Theme.control, in: RoundedRectangle(cornerRadius: 4))
            Text("to release")
        }
        .font(Theme.Font.small).foregroundStyle(Theme.textPrimary)
        .padding(.horizontal, 14).padding(.vertical, 8)
        .background(Theme.field.opacity(0.96), in: Capsule())
        .overlay(Capsule().strokeBorder(Color.primary.opacity(0.14)))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.top, 18)
        .allowsHitTesting(false)
    }

    private func statusBar(_ item: VMItem) -> some View {
        HStack(spacing: 18) {
            Label("CPU \(item.config.cpuCount) cores", systemImage: "cpu")
            Label("Memory \(Bytes.formatMemory(item.config.memoryBytes))", systemImage: "memorychip")
            Label("Disk \(Bytes.formatDisk(item.bundle.diskAllocated)) / \(Bytes.formatDisk(item.bundle.diskCapacity))", systemImage: "internaldrive")
            Label(item.config.network.label, systemImage: "network")
            Spacer(minLength: 0)
            Label("\(item.config.shares.filter(\.enabled).count) shared folders", systemImage: "folder")
            Text(session?.displayDescription.isEmpty == false ? session!.displayDescription : item.config.display.label)
            if let startedAt = session?.startedAt, state.isLive {
                TimelineView(.periodic(from: .now, by: 60)) { _ in Text("Uptime \(Durations.elapsed(since: startedAt))") }
            } else { Text("Uptime —") }
        }
        .font(.system(size: 10.5, design: .rounded).monospacedDigit())
        .foregroundStyle(Theme.textSecondary)
        .padding(.horizontal, 14).frame(height: 30)
        .background(Theme.toolbar)
        .overlay(alignment: .top) { Rectangle().fill(Theme.separator).frame(height: 1) }
        .lineLimit(1)
    }

    private func sharesPopover(_ item: VMItem) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Shared Folders").font(.headline)
            Text("Guest path: /Volumes/My Shared Files").font(Theme.Font.caption).foregroundStyle(Theme.textSecondary)
            if item.config.shares.isEmpty { Text("No shared folders").font(Theme.Font.small).foregroundStyle(Theme.textSecondary) }
            ForEach(item.config.shares) { share in
                HStack {
                    Image(systemName: "folder.fill").foregroundStyle(Theme.accent)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(share.name).font(Theme.Font.body)
                        Text(share.path).font(Theme.Font.caption).foregroundStyle(Theme.textSecondary).lineLimit(1)
                    }
                    Spacer()
                    Text(share.readOnly ? "Read Only" : "Read & Write").font(Theme.Font.caption).foregroundStyle(Theme.textSecondary)
                    Button(role: .destructive) {
                        do { try updateShares(item) { $0.removeAll { $0.id == share.id } } }
                        catch { alert = .from(error) }
                    } label: { Image(systemName: "minus.circle") }
                        .buttonStyle(.plain).help("Remove shared folder").accessibilityLabel("Remove \(share.name)")
                }
            }
            Button { addFolder(to: item) } label: { Label("Add Folder…", systemImage: "plus") }
                .buttonStyle(.coveprimary).frame(maxWidth: .infinity, alignment: .leading)
            Text("Changes apply after restart.").font(Theme.Font.caption).foregroundStyle(Theme.textSecondary)
        }
        .padding(16)
    }

    private func displayPopover(_ item: VMItem) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Display").font(.headline)
            Text(session?.displayDescription.isEmpty == false ? session!.displayDescription : item.config.display.label)
                .font(Theme.Font.body)
            Label("Resize to window is automatic", systemImage: "arrow.up.left.and.arrow.down.right")
                .font(Theme.Font.small).foregroundStyle(Theme.textSecondary)
        }
    }

    private func addFolder(to item: VMItem) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Share Folder"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let share = try ConfigurationBuilder.makeShare(for: url)
            try updateShares(item) { $0.append(share) }
        } catch { alert = .from(error) }
    }

    private func updateShares(_ item: VMItem, mutate: (inout [SharedFolder]) -> Void) throws {
        var config = item.config
        mutate(&config.shares)
        try library.update(item, config: config)
    }

    private func run(_ action: () throws -> Void) {
        do { try action() } catch { alert = .from(error) }
    }

    private func runAsync(starting item: VMItem? = nil, _ action: @escaping () async throws -> Void) {
        Task { @MainActor in
            do { try await action() } catch { alert = .from(error, starting: item) }
        }
    }
}

private struct VMHostView: NSViewRepresentable {
    var session: VMSession
    var item: VMItem
    var state: VMState
    @Binding var capturesKeys: Bool
    var releaseShortcut: String

    func makeCoordinator() -> Coordinator { Coordinator(item: item) }

    func makeNSView(context: Context) -> HostContainer {
        let container = HostContainer()
        let virtualMachineView = VZVirtualMachineView()
        virtualMachineView.virtualMachine = session.virtualMachine
        virtualMachineView.capturesSystemKeys = capturesKeys
        virtualMachineView.automaticallyReconfiguresDisplay = true
        virtualMachineView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(virtualMachineView)
        NSLayoutConstraint.activate([
            virtualMachineView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            virtualMachineView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            virtualMachineView.topAnchor.constraint(equalTo: container.topAnchor),
            virtualMachineView.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])
        context.coordinator.host = container
        context.coordinator.vmView = virtualMachineView
        context.coordinator.release = { [weak virtualMachineView] in
            virtualMachineView?.window?.makeFirstResponder(nil)
            capturesKeys = false
        }
        context.coordinator.beginMonitoring(enabled: capturesKeys, shortcut: releaseShortcut)
        return container
    }

    func updateNSView(_ nsView: HostContainer, context: Context) {
        let coordinator = context.coordinator
        coordinator.item = item
        // Grab the last frame as the guest leaves the running state (suspend / shut down), while it's still on screen.
        if coordinator.lastState == .running, state == .saving || state == .stopping || state == .paused {
            coordinator.captureThumbnail()
        }
        coordinator.lastState = state
        coordinator.vmView?.capturesSystemKeys = capturesKeys
        if capturesKeys, let vmView = coordinator.vmView {
            DispatchQueue.main.async { vmView.window?.makeFirstResponder(vmView) }
        }
        coordinator.beginMonitoring(enabled: capturesKeys, shortcut: releaseShortcut)
    }

    static func dismantleNSView(_ nsView: HostContainer, coordinator: Coordinator) {
        if coordinator.vmView?.virtualMachine?.state == .running { coordinator.captureThumbnail() }
        coordinator.endMonitoring()
    }

    final class HostContainer: NSView {
        override func viewWillMove(toWindow newWindow: NSWindow?) {
            if newWindow == nil { capture?() }
            super.viewWillMove(toWindow: newWindow)
        }
        /// Runs when the window closes while the guest is still running.
        var capture: (() -> Void)?
    }

    @MainActor final class Coordinator {
        var item: VMItem
        weak var host: HostContainer? {
            didSet {
                host?.capture = { [weak self] in
                    if self?.vmView?.virtualMachine?.state == .running { self?.captureThumbnail() }
                }
            }
        }
        var lastState: VMState = .stopped
        weak var vmView: VZVirtualMachineView?
        var release: (() -> Void)?
        private var monitor: Any?
        private var shortcut = "ctrl-option"
        private var isMonitoring = false

        init(item: VMItem) { self.item = item }

        func beginMonitoring(enabled: Bool, shortcut: String) {
            self.shortcut = shortcut
            guard enabled, !isMonitoring else { if !enabled { endMonitoring() }; return }
            isMonitoring = true
            monitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
                guard let self else { return event }
                let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
                let required: NSEvent.ModifierFlags = self.shortcut == "ctrl-option-cmd" ? [.control, .option, .command] : [.control, .option]
                if flags.isSuperset(of: required) { self.release?() }
                return event
            }
        }

        func endMonitoring() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
            isMonitoring = false
        }

        func captureThumbnail() {
            guard let view = vmView, view.window != nil else { return }
            var image = Self.surfaceImage(in: view)
            if image == nil, view.bounds.width > 0, view.bounds.height > 0,
               let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                view.cacheDisplay(in: view.bounds, to: rep)
                if rep.pixelsWide > 0, rep.pixelsHigh > 0, !Self.isBlank(rep) {
                    let candidate = NSImage(size: view.bounds.size)
                    candidate.addRepresentation(rep)
                    image = candidate
                }
            }
            guard let image else { return }
            item.bundle.writeThumbnail(Self.downscaled(image, maxWidth: 1280))
            item.refresh()
        }

        /// VZVirtualMachineView draws into an IOSurface-backed layer; `cacheDisplay` can't see it, so read the surface.
        private static func surfaceImage(in view: NSView) -> NSImage? {
            var queue = [view.layer].compactMap { $0 }
            while !queue.isEmpty {
                let layer = queue.removeFirst()
                if let contents = layer.contents, CFGetTypeID(contents as CFTypeRef) == IOSurfaceGetTypeID() {
                    let surface = unsafeBitCast(contents as AnyObject, to: IOSurface.self)
                    let ci = CIImage(ioSurface: surface)
                    if let cg = CIContext().createCGImage(ci, from: ci.extent) {
                        return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
                    }
                }
                queue += layer.sublayers ?? []
            }
            return nil
        }

        private static func downscaled(_ image: NSImage, maxWidth: CGFloat) -> NSImage {
            guard image.size.width > maxWidth else { return image }
            let size = NSSize(width: maxWidth, height: (image.size.height * maxWidth / image.size.width).rounded())
            return NSImage(size: size, flipped: false) { rect in
                image.draw(in: rect)
                return true
            }
        }

        private static func isBlank(_ rep: NSBitmapImageRep) -> Bool {
            let xSamples = stride(from: 0, to: rep.pixelsWide, by: max(1, rep.pixelsWide / 12))
            let ySamples = stride(from: 0, to: rep.pixelsHigh, by: max(1, rep.pixelsHigh / 12))
            for y in ySamples {
                for x in xSamples {
                    guard let color = rep.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                    if color.alphaComponent > 0.05 && (color.redComponent > 0.04 || color.greenComponent > 0.04 || color.blueComponent > 0.04) {
                        return false
                    }
                }
            }
            return true
        }
    }
}

private struct WindowTitleConfigurator: NSViewRepresentable {
    var subtitle: String
    func makeNSView(context: Context) -> NSView { let view = NSView(); DispatchQueue.main.async { view.window?.subtitle = subtitle }; return view }
    func updateNSView(_ view: NSView, context: Context) { DispatchQueue.main.async { view.window?.subtitle = subtitle } }
}
