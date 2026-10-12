import SwiftUI

struct RemoteAccessCard: View {
    var item: VMItem
    @Environment(VMLibrary.self) private var library
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        let progress = item.remoteAccessProgress
        GroupedCard {
            VStack(alignment: .leading, spacing: 10) {
                Label("SSH & Agent Access", systemImage: "terminal").fontWeight(.semibold)
                HStack(spacing: 6) {
                    StatusDot(color: progress.ready ? Theme.running : progress.enabled ? Theme.warning : Theme.stopped)
                    Text(progress.ready ? "Ready · ssh \(GuestAccess.alias(for: item.name))" : progress.enabled ? "Needs setup" : "Off")
                        .font(progress.ready ? Theme.Font.mono : Theme.Font.body)
                        .foregroundStyle(Theme.textSecondary).textSelection(.enabled)
                }
                Button(progress.enabled ? "Open Walkthrough" : "Set Up…") {
                    openWindow(id: WindowID.remoteAccess, value: item.id)
                }
                .buttonStyle(.covesecondary)
                if progress.ready {
                    RemoteCopyButton(text: item.remoteSSHCommand(library: library), label: "Copy SSH Command")
                }
            }
            .font(Theme.Font.body).padding(14).frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
