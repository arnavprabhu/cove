import Foundation
import Virtualization

/// A live `VZVirtualMachine` for one VM. All calls happen on the main queue (the VM's queue).
@MainActor @Observable
final class VMSession: NSObject {
    let bundle: VMBundle
    private(set) var virtualMachine: VZVirtualMachine
    private(set) var state: VMState = .stopped
    private(set) var startedAt: Date?
    private(set) var lastError: String?
    /// Snapshot of the hardware config the VM was started with (for the "applies after shutdown" banner).
    let startedHardware: VMConfig.HardwareFingerprint
    let cpuCount: Int
    let memoryBytes: UInt64
    let displayDescription: String
    /// The configuration this VM is actually running with, display resolved to real pixels — what a saved state
    /// taken now must be resumed with.
    let runningConfig: VMConfig

    /// Called once when the guest has fully stopped (shut down, crashed, or suspended to disk).
    var onStop: ((VMSession) -> Void)?

    private let built: ConfigurationBuilder.Result
    private var stateObservation: NSKeyValueObservation?
    private var transitional: VMState?

    init(bundle: VMBundle, config: VMConfig) throws {
        self.bundle = bundle
        built = try ConfigurationBuilder.build(bundle: bundle, config: config)
        virtualMachine = VZVirtualMachine(configuration: built.configuration)
        startedHardware = config.hardwareFingerprint
        cpuCount = built.configuration.cpuCount
        memoryBytes = built.configuration.memorySize
        let d = (built.configuration.graphicsDevices.first as? VZMacGraphicsDeviceConfiguration)?.displays.first
        displayDescription = d.map { "\($0.widthInPixels) × \($0.heightInPixels)" } ?? ""
        var running = config
        if let d {
            running.display = DisplaySettings(widthInPixels: d.widthInPixels, heightInPixels: d.heightInPixels,
                                              pixelsPerInch: d.pixelsPerInch, matchesHost: false)
        }
        runningConfig = running
        super.init()
        virtualMachine.delegate = self
        stateObservation = virtualMachine.observe(\.state, options: [.new]) { [weak self] _, _ in
            MainActor.assumeIsolated { self?.syncState() }
        }
    }

    // MARK: Lifecycle

    /// Starts the VM. If a saved state exists (and we're not booting Recovery) it resumes from it instead.
    func start(recovery: Bool = false) async throws {
        transitional = .starting
        syncState()
        defer { transitional = nil; syncState() }
        do {
            if !recovery, bundle.hasSaveState {
                do {
                    try await virtualMachine.restoreMachineStateFrom(url: bundle.saveStateURL)
                    bundle.removeSaveState()
                    try await virtualMachine.resume()
                    startedAt = Date()
                    return
                } catch {
                    // Saved state can't be restored (e.g. made by another macOS version): discard it and cold boot.
                    bundle.removeSaveState()
                    if virtualMachine.state != .stopped { throw error }
                }
            }
            let options = VZMacOSVirtualMachineStartOptions()
            options.startUpFromMacOSRecovery = recovery
            try await virtualMachine.start(options: options)
            startedAt = Date()
        } catch {
            lastError = error.localizedDescription
            throw error
        }
    }

    func pause() async throws { try await virtualMachine.pause() }

    func resume() async throws { try await virtualMachine.resume() }

    /// Asks the guest to shut down (like pressing the power button). Returns immediately.
    func requestShutDown() throws {
        transitional = .stopping
        syncState()
        do { try virtualMachine.requestStop() } catch { transitional = nil; syncState(); throw error }
    }

    /// Pulls the plug. Unsaved guest data is lost.
    func forceStop() async throws {
        try await virtualMachine.stop()
        didStop()
    }

    func restart() async throws {
        try await forceStop()
        // A VZVirtualMachine can't be reused after stopping on every OS version; callers should
        // create a fresh session. VMLibrary.restart handles this.
    }

    /// Pause → save machine state into the bundle → stop. The VM shows as Suspended afterwards.
    func suspend() async throws {
        transitional = .saving
        syncState()
        defer { transitional = nil; syncState() }
        if virtualMachine.state == .running { try await virtualMachine.pause() }
        do {
            try await virtualMachine.saveMachineStateTo(url: bundle.saveStateURL)
            try bundle.writeSaveStateConfig(runningConfig)
        } catch {
            bundle.removeSaveState()
            try? await virtualMachine.resume()
            throw error
        }
        try await virtualMachine.stop()
        didStop()
    }

    /// Pauses, writes the machine state to `url`, then runs `body` (e.g. disk clones) and resumes.
    func withPausedState(saveTo url: URL?, _ body: () throws -> Void) async throws {
        let wasRunning = virtualMachine.state == .running
        if wasRunning { try await virtualMachine.pause() }
        defer { if wasRunning { Task { try? await self.virtualMachine.resume() } } }
        if let url { try await virtualMachine.saveMachineStateTo(url: url) }
        try body()
    }

    // MARK: State

    private func syncState() {
        if let transitional { state = transitional; return }
        switch virtualMachine.state {
        case .stopped, .error: state = bundle.hasSaveState ? .suspended : .stopped
        case .running: state = .running
        case .paused: state = .paused
        case .starting, .resuming, .restoring: state = .starting
        case .pausing, .saving: state = .saving
        case .stopping: state = .stopping
        @unknown default: state = .stopped
        }
    }

    private var stopped = false

    private func didStop() {
        guard !stopped else { return }
        stopped = true
        transitional = nil
        syncState()
        built.stopAccessing()
        onStop?(self)
    }
}

extension VMSession: VZVirtualMachineDelegate {
    nonisolated func guestDidStop(_ virtualMachine: VZVirtualMachine) {
        MainActor.assumeIsolated { didStop() }
    }

    nonisolated func virtualMachine(_ virtualMachine: VZVirtualMachine, didStopWithError error: Error) {
        MainActor.assumeIsolated {
            lastError = error.localizedDescription
            didStop()
        }
    }
}
