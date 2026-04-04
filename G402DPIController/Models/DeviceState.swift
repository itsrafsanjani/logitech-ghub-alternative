import Foundation
import Combine

@MainActor
final class DeviceState: ObservableObject {
    let hidManager = HIDPlusPlusManager()
    let wakeService = WakeEventService()

    @Published var isConnected = false
    @Published var currentDPI: UInt16 = 0
    @Published var displayDPI: UInt16 = 0  // User-friendly value shown in UI
    @Published var sensorCapabilities: SensorDPICapabilities?

    private var cancellables = Set<AnyCancellable>()
    private var started = false

    func start(settings: DPISettings) {
        guard !started else { return }
        started = true
        // Bind HID manager state to our published properties
        hidManager.$isConnected
            .receive(on: DispatchQueue.main)
            .assign(to: &$isConnected)

        hidManager.$currentDPI
            .receive(on: DispatchQueue.main)
            .assign(to: &$currentDPI)

        hidManager.$sensorCapabilities
            .receive(on: DispatchQueue.main)
            .assign(to: &$sensorCapabilities)

        // On device connect: apply preferred DPI
        hidManager.onDeviceConnected = { [weak self] in
            guard let self else { return }
            Task { @MainActor in
                await self.applyPreferredDPI(settings: settings)
            }
        }

        // On wake/unlock: re-apply preferred DPI
        wakeService.startListening { [weak self] in
            guard let self, settings.restoreOnWake else { return }
            Task { @MainActor in
                await self.applyPreferredDPI(settings: settings)
            }
        }

        hidManager.start()
    }

    func applyPreferredDPI(settings: DPISettings) async {
        // Must switch to host mode first — the G402 boots into onboard mode
        // and ignores DPI commands until switched. This is the root cause of
        // the original G Hub bug (it fails to re-set host mode after wake).
        let _ = await hidManager.switchToHostMode()

        // Query hardware DPI capabilities (best-effort; fallback to hardcoded)
        let _ = await hidManager.getSensorDpiList()

        let caps = hidManager.sensorCapabilities ?? G402DPI.fallbackCapabilities
        let requestedDPI = settings.preferredDPIValue
        let snappedDPI = caps.snap(requestedDPI)
        print("[DPI] Applying preferred DPI: \(requestedDPI) → snapped to \(snappedDPI)")
        let success = await hidManager.setDPI(snappedDPI)
        if success {
            displayDPI = requestedDPI
            print("[DPI] Successfully set to \(hidManager.currentDPI)")
        } else {
            print("[DPI] Failed to set DPI")
        }
    }

    func setDPI(_ dpi: UInt16, settings: DPISettings) async {
        settings.preferredDPIValue = dpi
        let caps = hidManager.sensorCapabilities ?? G402DPI.fallbackCapabilities
        let snapped = caps.snap(dpi)
        let success = await hidManager.setDPI(snapped)
        if success {
            displayDPI = dpi
        }
    }
}
