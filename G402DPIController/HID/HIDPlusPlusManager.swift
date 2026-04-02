import Foundation
import IOKit
import IOKit.hid
import Combine

@MainActor
final class HIDPlusPlusManager: ObservableObject {
    @Published private(set) var isConnected = false
    @Published private(set) var currentDPI: UInt16 = 0

    private var hidManager: IOHIDManager?
    private var device: IOHIDDevice?
    private var reportBuffer: UnsafeMutablePointer<UInt8>?
    private let featureCache = FeatureIndexCache()

    private var responseContinuation: CheckedContinuation<[UInt8]?, Never>?

    var onDeviceConnected: (() -> Void)?

    init() {}

    func start() {
        guard hidManager == nil else { return }

        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        hidManager = manager

        let matchDict: [String: Any] = [
            kIOHIDVendorIDKey as String: HIDPPConstants.logitechVID,
            kIOHIDProductIDKey as String: HIDPPConstants.g402PID,
            kIOHIDPrimaryUsageKey as String: HIDPPConstants.hidppPrimaryUsage
        ]
        IOHIDManagerSetDeviceMatching(manager, matchDict as CFDictionary)

        let context = Unmanaged.passUnretained(self).toOpaque()

        IOHIDManagerRegisterDeviceMatchingCallback(manager, { context, _, _, device in
            guard let context else { return }
            let self_ = Unmanaged<HIDPlusPlusManager>.fromOpaque(context).takeUnretainedValue()
            Task { @MainActor in
                self_.handleDeviceMatched(device)
            }
        }, context)

        IOHIDManagerRegisterDeviceRemovalCallback(manager, { context, _, _, device in
            guard let context else { return }
            let self_ = Unmanaged<HIDPlusPlusManager>.fromOpaque(context).takeUnretainedValue()
            Task { @MainActor in
                self_.handleDeviceRemoved(device)
            }
        }, context)

        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)

        let result = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        if result != kIOReturnSuccess {
            print("[HID] Failed to open HID Manager: 0x\(String(format: "%08X", result))")
        }
    }

    func stop() {
        if let device {
            IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone))
        }
        if let hidManager {
            IOHIDManagerClose(hidManager, IOOptionBits(kIOHIDOptionsTypeNone))
        }
        reportBuffer?.deallocate()
        reportBuffer = nil
        device = nil
        hidManager = nil
        isConnected = false
    }

    // MARK: - Device Lifecycle

    private func handleDeviceMatched(_ device: IOHIDDevice) {
        let result = IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone))
        if result != kIOReturnSuccess {
            print("[HID] Failed to open device: 0x\(String(format: "%08X", result))")
            return
        }

        self.device = device
        self.isConnected = true

        // Allocate report buffer and register callback
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: HIDPPConstants.longLength)
        self.reportBuffer = buffer
        let context = Unmanaged.passUnretained(self).toOpaque()

        IOHIDDeviceRegisterInputReportCallback(
            device, buffer, HIDPPConstants.longLength,
            { context, _, _, _, reportID, report, reportLength in
                guard let context else { return }
                let self_ = Unmanaged<HIDPlusPlusManager>.fromOpaque(context).takeUnretainedValue()
                let bytes = [UInt8(reportID)] + Array(UnsafeBufferPointer(start: report, count: reportLength))
                Task { @MainActor in
                    self_.handleInputReport(bytes)
                }
            },
            context
        )

        print("[HID] G402 connected")

        Task { @MainActor in
            await featureCache.clear()
            onDeviceConnected?()
        }
    }

    private func handleDeviceRemoved(_ removedDevice: IOHIDDevice) {
        guard device === removedDevice else { return }
        device = nil
        isConnected = false
        currentDPI = 0
        reportBuffer?.deallocate()
        reportBuffer = nil
        print("[HID] G402 disconnected")
    }

    private func handleInputReport(_ bytes: [UInt8]) {
        guard bytes.count >= HIDPPConstants.shortLength else { return }
        let reportID = bytes[0]
        let responseSWID = bytes[3] & 0x0F

        if (reportID == HIDPPConstants.shortReportID ||
            reportID == HIDPPConstants.longReportID ||
            reportID == HIDPPConstants.errorReportID) &&
            (responseSWID == HIDPPConstants.swID || reportID == HIDPPConstants.errorReportID) {
            responseContinuation?.resume(returning: bytes)
            responseContinuation = nil
        }
    }

    // MARK: - Send / Receive

    func sendMessage(_ message: HIDPPMessage, timeout: TimeInterval = 2.0) async -> [UInt8]? {
        guard let device else { return nil }

        let bytes = message.toBytes()
        let reportID = CFIndex(bytes[0])
        let reportData = Array(bytes.dropFirst())

        let sendResult = reportData.withUnsafeBufferPointer { buffer in
            IOHIDDeviceSetReport(device, kIOHIDReportTypeOutput, reportID, buffer.baseAddress!, buffer.count)
        }

        if sendResult != kIOReturnSuccess {
            print("[HID] SetReport failed: 0x\(String(format: "%08X", sendResult))")
            return nil
        }

        // Wait for response with timeout
        return await withCheckedContinuation { continuation in
            self.responseContinuation = continuation

            Task { @MainActor in
                try? await Task.sleep(for: .seconds(timeout))
                if self.responseContinuation != nil {
                    self.responseContinuation?.resume(returning: nil)
                    self.responseContinuation = nil
                }
            }
        }
    }

    // MARK: - Feature Discovery

    func discoverFeatureIndex(featureID: UInt16) async -> UInt8? {
        if let cached = await featureCache.get(featureID) {
            return cached
        }

        let hi = UInt8((featureID >> 8) & 0xFF)
        let lo = UInt8(featureID & 0xFF)

        let message = HIDPPMessage.shortReport(
            featureIndex: 0x00,  // IRoot is always at index 0
            functionID: 0,       // getFeature
            params: [hi, lo, 0]
        )

        guard let response = await sendMessage(message) else { return nil }

        if response[0] == HIDPPConstants.errorReportID {
            print("[HID] Feature 0x\(String(format: "%04X", featureID)) error — HID++ 1.0?")
            return nil
        }

        guard response.count > 4 else { return nil }
        let index = response[4]
        if index == 0 && featureID != HIDPPConstants.iRootFeatureID {
            print("[HID] Feature 0x\(String(format: "%04X", featureID)) not found")
            return nil
        }

        await featureCache.set(featureID, index: index)
        print("[HID] Feature 0x\(String(format: "%04X", featureID)) at index \(index)")
        return index
    }

    // MARK: - DPI Operations

    func readDPI() async -> UInt16? {
        guard let featureIndex = await discoverFeatureIndex(featureID: HIDPPConstants.adjustableDPIFeatureID) else {
            return nil
        }

        let message = HIDPPMessage.longReport(
            featureIndex: featureIndex,
            functionID: 1,  // getSensorDPI
            params: [0]     // sensor index 0
        )

        guard let response = await sendMessage(message),
              response.count >= 7 else { return nil }

        let dpi = (UInt16(response[5]) << 8) | UInt16(response[6])
        currentDPI = dpi
        return dpi
    }

    func setDPI(_ dpi: UInt16) async -> Bool {
        guard let featureIndex = await discoverFeatureIndex(featureID: HIDPPConstants.adjustableDPIFeatureID) else {
            return false
        }

        let hi = UInt8((dpi >> 8) & 0xFF)
        let lo = UInt8(dpi & 0xFF)

        let message = HIDPPMessage.longReport(
            featureIndex: featureIndex,
            functionID: 2,     // setSensorDPI
            params: [0, hi, lo]  // sensor index 0, DPI big-endian
        )

        guard let response = await sendMessage(message) else { return false }

        if response[0] == HIDPPConstants.errorReportID {
            print("[HID] Set DPI failed")
            return false
        }

        // Verify by reading back
        if let actual = await readDPI() {
            if actual != dpi {
                print("[HID] DPI mismatch: requested \(dpi), got \(actual)")
            }
            currentDPI = actual
            return actual == dpi
        }

        currentDPI = dpi
        return true
    }
}
