import CoreGraphics
import AppKit
import ApplicationServices

actor PermissionManager {
    static let shared = PermissionManager()

    enum Permission: String, CaseIterable {
        case inputMonitoring = "Input Monitoring"
        case accessibility = "Accessibility"
    }

    struct Status {
        var inputMonitoring: Bool
        var accessibility: Bool

        var allGranted: Bool {
            inputMonitoring && accessibility
        }

        var description: String {
            """
            Input Monitoring: \(inputMonitoring ? "granted" : "denied")
            Accessibility: \(accessibility ? "granted" : "denied")
            """
        }
    }

    func checkStatus() -> Status {
        Status(
            inputMonitoring: checkInputMonitoring(),
            accessibility: checkAccessibility()
        )
    }

    func requestPermissions() async {
        let status = checkStatus()

        if !status.inputMonitoring {
            requestInputMonitoring()
        }

        if !status.accessibility {
            requestAccessibility()
        }
    }

    // MARK: - Input Monitoring

    private func checkInputMonitoring() -> Bool {
        return CGPreflightListenEventAccess()
    }

    private func requestInputMonitoring() {
        let granted = CGRequestListenEventAccess()
        print("[PermissionManager] Input Monitoring request result: \(granted)")
    }

    // MARK: - Accessibility

    private func checkAccessibility() -> Bool {
        return AXIsProcessTrusted()
    }

    private func requestAccessibility() {
        let promptKey = "AXTrustedCheckOptionPrompt" as CFString
        let options = [promptKey: true] as CFDictionary
        let _ = AXIsProcessTrustedWithOptions(options)
        print("[PermissionManager] Accessibility permission requested")
    }

    // MARK: - Open System Preferences

    func openSystemPreferences(for permission: Permission) {
        let urlString: String
        switch permission {
        case .inputMonitoring:
            urlString = "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent"
        case .accessibility:
            urlString = "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        }

        if let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        }
    }
}
