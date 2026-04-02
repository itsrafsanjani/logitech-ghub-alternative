import Foundation
import AppKit

@MainActor
final class WakeEventService {
    private var onWake: (() -> Void)?
    private var observers: [Any] = []
    private var started = false

    func startListening(onWake: @escaping () -> Void) {
        guard !started else { return }
        started = true
        self.onWake = onWake

        observers.append(
            NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.didWakeNotification,
                object: nil, queue: .main
            ) { [weak self] _ in
                print("[Wake] System woke from sleep")
                Task { @MainActor [weak self] in
                    self?.scheduleRestore()
                }
            }
        )

        observers.append(
            DistributedNotificationCenter.default().addObserver(
                forName: NSNotification.Name("com.apple.screenIsUnlocked"),
                object: nil, queue: .main
            ) { [weak self] _ in
                print("[Wake] Screen unlocked")
                Task { @MainActor [weak self] in
                    self?.scheduleRestore()
                }
            }
        )

        observers.append(
            DistributedNotificationCenter.default().addObserver(
                forName: NSNotification.Name("com.apple.screensaver.didStop"),
                object: nil, queue: .main
            ) { [weak self] _ in
                print("[Wake] Screen saver stopped")
                Task { @MainActor [weak self] in
                    self?.scheduleRestore()
                }
            }
        )
    }

    private func scheduleRestore() {
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.5))
            onWake?()
        }
    }

    func stopListening() {
        for observer in observers {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            DistributedNotificationCenter.default().removeObserver(observer)
        }
        observers.removeAll()
        started = false
    }
}
