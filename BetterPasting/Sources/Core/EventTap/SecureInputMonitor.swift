import AppKit
import Carbon
import Combine

/// Watches macOS Secure Keyboard Entry, which blocks keyboard CGEvent taps
/// system-wide and silently disables the global CMD+SHIFT+V hotkey.
/// Polls IsSecureEventInputEnabled() and, when enabled, does a best-effort
/// lookup of the process holding secure input so the UI can name it.
@MainActor
final class SecureInputMonitor {
    static let shared = SecureInputMonitor()

    private var timer: Timer?
    private var lastEnabled = false

    private init() {}

    func startMonitoring() {
        guard timer == nil else { return }
        check()
        let timer = Timer(timeInterval: 3.0, repeats: true) { _ in
            Task { @MainActor in
                SecureInputMonitor.shared.check()
            }
        }
        // .common so the check keeps running while menus are open
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        print("[SecureInputMonitor] Started")
    }

    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
    }

    private func check() {
        let enabled = IsSecureEventInputEnabled()
        guard enabled != lastEnabled else { return }
        lastEnabled = enabled

        if enabled {
            print("[SecureInputMonitor] Secure Keyboard Entry enabled — hotkey blocked")
            // Show a generic warning immediately; refine with the app name async
            AppState.shared.secureInputHolderName = "another app"
            Task.detached(priority: .utility) {
                let name = Self.findSecureInputHolderName()
                await MainActor.run {
                    // Only update if the warning is still active
                    if AppState.shared.secureInputHolderName != nil {
                        AppState.shared.secureInputHolderName = name ?? "another app"
                    }
                }
            }
        } else {
            print("[SecureInputMonitor] Secure Keyboard Entry released")
            AppState.shared.secureInputHolderName = nil
        }
    }

    /// Best-effort: parse kCGSSessionSecureInputPID out of ioreg output and
    /// map the pid to a running application name.
    nonisolated private static func findSecureInputHolderName() -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/ioreg")
        process.arguments = ["-l", "-w", "0"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            print("[SecureInputMonitor] ioreg failed: \(error)")
            return nil
        }
        // Read before waiting so the pipe can't fill up and deadlock
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard let output = String(data: data, encoding: .utf8),
              let range = output.range(of: "\"kCGSSessionSecureInputPID\"=") else {
            return nil
        }
        let digits = output[range.upperBound...].prefix(while: { $0.isNumber })
        guard let pid = Int32(digits) else { return nil }

        if let app = NSRunningApplication(processIdentifier: pid),
           let name = app.localizedName {
            return name
        }
        return "process \(pid)"
    }
}
