import UserNotifications

/// User notifications for background installs ("VM ready" / install failed).
enum InstallNotifier {
    static let categoryReady = "VM_READY"
    static let actionOpen = "OPEN_VM"
    static let vmIDKey = "vmID"

    static func requestAuthorization() {
        let center = UNUserNotificationCenter.current()
        let open = UNNotificationAction(identifier: actionOpen, title: "Open", options: [.foreground])
        center.setNotificationCategories([UNNotificationCategory(identifier: categoryReady, actions: [open],
                                                                 intentIdentifiers: [])])
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    static func postReady(vmName: String, vmID: UUID) {
        let content = UNMutableNotificationContent()
        content.title = "“\(vmName)” is ready"
        content.body = "macOS is installed. Open it to finish Setup Assistant."
        content.sound = .default
        content.categoryIdentifier = categoryReady
        content.userInfo = [vmIDKey: vmID.uuidString]
        post(content)
    }

    static func postFailed(vmName: String, message: String) {
        let content = UNMutableNotificationContent()
        content.title = "Couldn’t create “\(vmName)”"
        content.body = message
        post(content)
    }

    private static func post(_ content: UNNotificationContent) {
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString,
                                                                     content: content, trigger: nil))
    }
}
