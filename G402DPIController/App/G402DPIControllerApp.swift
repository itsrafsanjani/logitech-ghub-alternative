import SwiftUI

@main
struct G402DPIControllerApp: App {
    @StateObject private var deviceState = DeviceState()
    @StateObject private var settings = DPISettings()

    var body: some Scene {
        MenuBarExtra {
            DPIMenuView(deviceState: deviceState, settings: settings)
                .onAppear {
                    deviceState.start(settings: settings)
                }
        } label: {
            if deviceState.isConnected && deviceState.displayDPI > 0 {
                Text("DPI: \(deviceState.displayDPI)")
                    .monospacedDigit()
            } else {
                Image(systemName: "computermouse")
            }
        }
        .menuBarExtraStyle(.window)
    }
}
