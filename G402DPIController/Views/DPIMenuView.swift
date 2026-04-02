import SwiftUI

struct DPIMenuView: View {
    @ObservedObject var deviceState: DeviceState
    @ObservedObject var settings: DPISettings
    @State private var sliderDPI: Double = 1600

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Connection status
            HStack(spacing: 6) {
                Circle()
                    .fill(deviceState.isConnected ? .green : .red)
                    .frame(width: 8, height: 8)
                Text(deviceState.isConnected ? "G402 Connected" : "G402 Disconnected")
                    .font(.headline)
            }
            .padding(.bottom, 4)

            if deviceState.isConnected {
                // Current DPI
                HStack {
                    Text("Current DPI:")
                    Spacer()
                    Text("\(deviceState.currentDPI)")
                        .monospacedDigit()
                        .fontWeight(.semibold)
                }

                Divider()

                // Preset buttons
                Text("Presets")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                HStack(spacing: 6) {
                    ForEach(G402DPI.presets, id: \.self) { preset in
                        Button(String(preset)) {
                            Task {
                                await deviceState.setDPI(preset, settings: settings)
                                sliderDPI = Double(preset)
                            }
                        }
                        .buttonStyle(.bordered)
                        .tint(deviceState.currentDPI == preset ? .accentColor : nil)
                    }
                }

                Divider()

                // Custom slider
                Text("Custom DPI")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                HStack {
                    Text("\(Int(G402DPI.minDPI))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Slider(
                        value: $sliderDPI,
                        in: Double(G402DPI.minDPI)...Double(G402DPI.maxDPI),
                        step: Double(G402DPI.step)
                    ) {
                        Text("DPI")
                    } onEditingChanged: { editing in
                        if !editing {
                            let dpi = G402DPI.clamp(UInt16(sliderDPI))
                            Task {
                                await deviceState.setDPI(dpi, settings: settings)
                            }
                        }
                    }
                    Text("\(Int(G402DPI.maxDPI))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text("\(Int(sliderDPI)) DPI")
                    .monospacedDigit()
                    .frame(maxWidth: .infinity, alignment: .center)
                    .foregroundStyle(.secondary)
            }

            Divider()

            // Settings
            Toggle("Restore DPI on wake/unlock", isOn: $settings.restoreOnWake)
            Toggle("Launch at login", isOn: $settings.launchAtLogin)

            Divider()

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }
        .padding(12)
        .frame(width: 280)
        .onAppear {
            sliderDPI = Double(settings.preferredDPI)
        }
        .onChange(of: deviceState.currentDPI) { _, newValue in
            if newValue > 0 {
                sliderDPI = Double(newValue)
            }
        }
    }
}
