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
                    Text("\(deviceState.displayDPI)")
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
                        .tint(isPresetActive(preset) ? .accentColor : nil)
                    }
                }

                Divider()

                // Custom slider
                Text("Custom DPI")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                HStack {
                    Text("\(Int(sliderMin))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Slider(
                        value: $sliderDPI,
                        in: Double(sliderMin)...Double(sliderMax),
                        step: Double(sliderStep)
                    ) {
                        Text("DPI")
                    } onEditingChanged: { editing in
                        if !editing {
                            let caps = deviceState.sensorCapabilities ?? G402DPI.fallbackCapabilities
                            let dpi = caps.snap(UInt16(sliderDPI))
                            Task {
                                await deviceState.setDPI(dpi, settings: settings)
                            }
                        }
                    }
                    Text("\(Int(sliderMax))")
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
        .onChange(of: deviceState.displayDPI) { _, newValue in
            if newValue > 0 {
                sliderDPI = Double(newValue)
            }
        }
    }

    // MARK: - Helpers

    private var sliderMin: UInt16 {
        deviceState.sensorCapabilities?.minDPI ?? G402DPI.minDPI
    }

    private var sliderMax: UInt16 {
        deviceState.sensorCapabilities?.maxDPI ?? G402DPI.maxDPI
    }

    private var sliderStep: UInt16 {
        deviceState.sensorCapabilities?.step ?? G402DPI.step
    }

    private func isPresetActive(_ preset: UInt16) -> Bool {
        deviceState.isConnected && deviceState.displayDPI == preset
    }
}
