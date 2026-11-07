import Foundation
import Darwin

/// Read before starting a guest: normal sessions keep renderer diagnostics off.
enum GPUDiagnostics {
    static let enabledKey = "henge.gpu.diagnostics"

    static func configure() {
        let enabled = UserDefaults.standard.bool(forKey: enabledKey)
        if enabled {
            setenv("HV_PVG_DIAGNOSTICS", "1", 1)
        } else {
            unsetenv("HV_PVG_DIAGNOSTICS")
        }
        HengeLog.log("graphics", "GPU diagnostics \(enabled ? "on (bounded metadata only)" : "off")")
    }
}
