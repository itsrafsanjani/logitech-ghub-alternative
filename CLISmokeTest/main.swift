// G402 DPI Controller - CLI Smoke Test
// Validates HID++ 2.0 communication with the Logitech G402 Hyperion Fury
//
// Prerequisites:
// - G Hub's HID filter dext must be removed
// - Input Monitoring permission must be granted (System Settings > Privacy & Security)

import Foundation
import IOKit
import IOKit.hid

// MARK: - Constants

let LOGITECH_VID: Int = 0x046d
let G402_PID: Int = 0xc07e
let HIDPP_SHORT_REPORT_ID: UInt8 = 0x10
let HIDPP_LONG_REPORT_ID: UInt8 = 0x11
let HIDPP_SHORT_LENGTH = 7
let HIDPP_LONG_LENGTH = 20
let DEVICE_INDEX: UInt8 = 0x01
let SW_ID: UInt8 = 0x07
let ADJUSTABLE_DPI_FEATURE_ID: UInt16 = 0x2201

// MARK: - Mutable state (single-threaded CLI, callbacks on same run loop)

nonisolated(unsafe) var g402Device: IOHIDDevice?
nonisolated(unsafe) var responseReceived = false
nonisolated(unsafe) var lastResponse = [UInt8]()

// MARK: - HID Report Helpers

func makeShortReport(featureIndex: UInt8, functionID: UInt8, params: [UInt8] = []) -> [UInt8] {
    var report = [UInt8](repeating: 0, count: HIDPP_SHORT_LENGTH)
    report[0] = HIDPP_SHORT_REPORT_ID
    report[1] = DEVICE_INDEX
    report[2] = featureIndex
    report[3] = (functionID << 4) | SW_ID
    for (i, p) in params.prefix(3).enumerated() {
        report[4 + i] = p
    }
    return report
}

func makeLongReport(featureIndex: UInt8, functionID: UInt8, params: [UInt8] = []) -> [UInt8] {
    var report = [UInt8](repeating: 0, count: HIDPP_LONG_LENGTH)
    report[0] = HIDPP_LONG_REPORT_ID
    report[1] = DEVICE_INDEX
    report[2] = featureIndex
    report[3] = (functionID << 4) | SW_ID
    for (i, p) in params.prefix(16).enumerated() {
        report[4 + i] = p
    }
    return report
}

func hexString(_ bytes: [UInt8]) -> String {
    bytes.map { String(format: "%02X", $0) }.joined(separator: " ")
}

// MARK: - Input Report Callback

func inputReportCallback(
    context: UnsafeMutableRawPointer?,
    result: IOReturn,
    sender: UnsafeMutableRawPointer?,
    type: IOHIDReportType,
    reportID: UInt32,
    report: UnsafeMutablePointer<UInt8>,
    reportLength: CFIndex
) {
    let bytes = Array(UnsafeBufferPointer(start: report, count: reportLength))

    if bytes.count >= 4 {
        let responseSWID = bytes[3] & 0x0F
        let responseReportID = UInt8(reportID)

        if (responseReportID == HIDPP_SHORT_REPORT_ID ||
            responseReportID == HIDPP_LONG_REPORT_ID ||
            responseReportID == 0x8F) &&
            (responseSWID == SW_ID || responseReportID == 0x8F) {
            lastResponse = [responseReportID] + bytes
            responseReceived = true
        }
    }
}

// MARK: - Send and Wait

func sendReport(_ report: [UInt8], timeout: TimeInterval = 2.0) -> [UInt8]? {
    guard let device = g402Device else {
        print("ERROR: No device")
        return nil
    }

    responseReceived = false
    lastResponse = []

    let reportID = CFIndex(report[0])
    let reportData = Array(report.dropFirst())

    print("  TX: \(hexString(report))")

    let result = reportData.withUnsafeBufferPointer { buffer in
        IOHIDDeviceSetReport(device, kIOHIDReportTypeOutput, reportID, buffer.baseAddress!, buffer.count)
    }

    if result != kIOReturnSuccess {
        print("  ERROR: IOHIDDeviceSetReport failed with 0x\(String(format: "%08X", result))")
        return nil
    }

    let deadline = Date().addingTimeInterval(timeout)
    while !responseReceived && Date() < deadline {
        RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.01))
    }

    if responseReceived {
        print("  RX: \(hexString(lastResponse))")
        return lastResponse
    } else {
        print("  ERROR: Timeout waiting for response")
        return nil
    }
}

// MARK: - HID++ Operations

func discoverFeatureIndex(featureID: UInt16) -> UInt8? {
    let hi = UInt8((featureID >> 8) & 0xFF)
    let lo = UInt8(featureID & 0xFF)

    print("\n--- Discovering feature index for 0x\(String(format: "%04X", featureID)) ---")
    let report = makeShortReport(featureIndex: 0x00, functionID: 0, params: [hi, lo, 0])

    guard let response = sendReport(report) else { return nil }

    if response[0] == 0x8F {
        print("  Got HID++ 1.0 error response — this device may use HID++ 1.0, not 2.0")
        print("  Error code: 0x\(String(format: "%02X", response.count > 6 ? response[6] : 0))")
        return nil
    }

    if response.count > 4 && response[4] == 0x00 && response.count > 5 && response[5] == 0x00 {
        print("  Feature 0x\(String(format: "%04X", featureID)) not found on this device")
        return nil
    }

    let featureIndex = response.count > 4 ? response[4] : 0
    let featureType = response.count > 5 ? response[5] : 0
    print("  Feature 0x\(String(format: "%04X", featureID)) is at index \(featureIndex) (type: \(featureType))")
    return featureIndex
}

func getSensorDPI(featureIndex: UInt8, sensorIndex: UInt8 = 0) -> UInt16? {
    print("\n--- Reading current DPI (sensor \(sensorIndex)) ---")
    let report = makeLongReport(featureIndex: featureIndex, functionID: 1, params: [sensorIndex])

    guard let response = sendReport(report) else { return nil }

    if response.count >= 7 {
        let dpi = (UInt16(response[5]) << 8) | UInt16(response[6])
        print("  Current DPI: \(dpi)")
        return dpi
    }
    print("  ERROR: Response too short to read DPI")
    return nil
}

func setSensorDPI(featureIndex: UInt8, sensorIndex: UInt8 = 0, dpi: UInt16) -> Bool {
    print("\n--- Setting DPI to \(dpi) (sensor \(sensorIndex)) ---")
    let hi = UInt8((dpi >> 8) & 0xFF)
    let lo = UInt8(dpi & 0xFF)
    let report = makeLongReport(featureIndex: featureIndex, functionID: 2, params: [sensorIndex, hi, lo])

    guard let response = sendReport(report) else { return false }

    if response[0] == 0x8F {
        print("  ERROR: Set DPI failed with error")
        return false
    }

    print("  DPI set command sent successfully")
    return true
}

func getSensorCount(featureIndex: UInt8) -> UInt8? {
    print("\n--- Getting sensor count ---")
    let report = makeLongReport(featureIndex: featureIndex, functionID: 0, params: [])

    guard let response = sendReport(report) else { return nil }

    if response.count >= 5 {
        let count = response[4]
        print("  Sensor count: \(count)")
        return count
    }
    return nil
}

// MARK: - Main

print("=== G402 DPI Controller - CLI Smoke Test ===")
print("Looking for Logitech G402 (VID=0x\(String(format: "%04X", LOGITECH_VID)), PID=0x\(String(format: "%04X", G402_PID)))...")

let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))

let matchDict: [String: Any] = [
    kIOHIDVendorIDKey as String: LOGITECH_VID,
    kIOHIDProductIDKey as String: G402_PID,
    kIOHIDPrimaryUsageKey as String: 6
]

IOHIDManagerSetDeviceMatching(manager, matchDict as CFDictionary)
IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)

let openResult = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
if openResult != kIOReturnSuccess {
    print("ERROR: Failed to open HID Manager (0x\(String(format: "%08X", openResult)))")
    print("Make sure Input Monitoring is enabled in System Settings > Privacy & Security")
    exit(1)
}

guard let deviceSet = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> else {
    print("ERROR: No devices found. Is the G402 plugged in?")
    exit(1)
}

print("Found \(deviceSet.count) matching HID interface(s)")

guard let device = deviceSet.first else {
    print("ERROR: No G402 HID++ interface found")
    exit(1)
}

g402Device = device

let deviceOpenResult = IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone))
if deviceOpenResult != kIOReturnSuccess {
    print("ERROR: Failed to open device (0x\(String(format: "%08X", deviceOpenResult)))")
    let exclusiveAccess: IOReturn = -536870715  // 0xE00002C5
    if deviceOpenResult == exclusiveAccess {
        print("Another process has exclusive access. Is G Hub still running?")
        print("Check: systemextensionsctl list")
    }
    exit(1)
}

print("Device opened successfully")

let reportBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: HIDPP_LONG_LENGTH)
IOHIDDeviceRegisterInputReportCallback(device, reportBuffer, HIDPP_LONG_LENGTH, inputReportCallback, nil)

// Step 1: Discover feature index for Adjustable DPI (0x2201)
guard let dpiFeatureIndex = discoverFeatureIndex(featureID: ADJUSTABLE_DPI_FEATURE_ID) else {
    print("\nFATAL: Could not discover Adjustable DPI feature.")
    print("The G402 may use HID++ 1.0. Try register-based protocol instead.")

    print("\n--- Attempting HID++ 1.0 fallback (register 0x63) ---")
    let fallbackReport = makeShortReport(featureIndex: 0x00, functionID: 0x08, params: [0x63, 0x00, 0x00])
    if let response = sendReport(fallbackReport) {
        print("  HID++ 1.0 response: \(hexString(response))")
    }

    reportBuffer.deallocate()
    exit(1)
}

// Step 2: Get sensor count
let _ = getSensorCount(featureIndex: dpiFeatureIndex)

// Step 3: Read current DPI
let currentDPI = getSensorDPI(featureIndex: dpiFeatureIndex, sensorIndex: 0)
print("\n  >>> Current DPI: \(currentDPI.map { String($0) } ?? "unknown")")

// Step 4: Set DPI to 1600
let targetDPI: UInt16 = 1600
if setSensorDPI(featureIndex: dpiFeatureIndex, sensorIndex: 0, dpi: targetDPI) {
    if let newDPI = getSensorDPI(featureIndex: dpiFeatureIndex, sensorIndex: 0) {
        if newDPI == targetDPI {
            print("\n=== SUCCESS: DPI set to \(targetDPI) and verified ===")
        } else {
            print("\n=== WARNING: DPI readback mismatch — set \(targetDPI) but read \(newDPI) ===")
        }
    }
} else {
    print("\n=== FAILED: Could not set DPI ===")
}

// Check for onboard profiles feature (0x8100)
print("\n--- Checking for Onboard Profiles feature (0x8100) ---")
if let profileFeatureIndex = discoverFeatureIndex(featureID: 0x8100) {
    print("  Onboard Profiles feature found at index \(profileFeatureIndex)")
    print("  This means we can switch between host/onboard mode")
} else {
    print("  Onboard Profiles feature not found — will rely on re-sending DPI on wake")
}

IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone))
reportBuffer.deallocate()

print("\n=== Smoke test complete ===")
