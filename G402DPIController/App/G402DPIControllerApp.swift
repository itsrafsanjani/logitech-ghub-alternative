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
            Image(systemName: deviceState.isConnected ? "computermouse.fill" : "computermouse")
        }
        .menuBarExtraStyle(.window)
    }
}
