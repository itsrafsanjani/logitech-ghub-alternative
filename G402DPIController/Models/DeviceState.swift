import Foundation
import Combine

@MainActor
final class DeviceState: ObservableObject {
    let hidManager = HIDPlusPlusManager()
    let wakeService = WakeEventService()

    @Published var isConnected = false
    @Published var currentDPI: UInt16 = 0

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
        let dpi = settings.preferredDPIValue
        print("[DPI] Applying preferred DPI: \(dpi)")
        let success = await hidManager.setDPI(dpi)
        if success {
            print("[DPI] Successfully set to \(dpi)")
        } else {
            print("[DPI] Failed to set DPI")
        }
    }

    func setDPI(_ dpi: UInt16, settings: DPISettings) async {
        settings.preferredDPIValue = dpi
        let _ = await hidManager.setDPI(dpi)
    }
}
