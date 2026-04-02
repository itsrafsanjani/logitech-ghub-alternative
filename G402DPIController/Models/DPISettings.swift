import SwiftUI

@MainActor
final class DPISettings: ObservableObject {
    @AppStorage("preferredDPI") var preferredDPI: Int = Int(G402DPI.defaultDPI)
    @AppStorage("restoreOnWake") var restoreOnWake: Bool = true
    @AppStorage("launchAtLogin") var launchAtLogin: Bool = false {
        didSet { LaunchAtLoginService.setEnabled(launchAtLogin) }
    }

    var preferredDPIValue: UInt16 {
        get { G402DPI.clamp(UInt16(clamping: preferredDPI)) }
        set { preferredDPI = Int(G402DPI.clamp(newValue)) }
    }
}
