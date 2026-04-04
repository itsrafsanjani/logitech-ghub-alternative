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
let DEVICE_INDEX: UInt8 = 0xFF  // Direct USB (wired) — 0x01..0x06 is for Unifying receiver
let SW_ID: UInt8 = 0x07         // Software ID for matching responses
let ADJUSTABLE_DPI_FEATURE_ID: UInt16 = 0x2201

// MARK: - Mutable state (single-threaded CLI, callbacks on same run loop)

nonisolated(unsafe) var g402Device: IOHIDDevice?
nonisolated(unsafe) var responseReceived = false
nonisolated(unsafe) var lastResponse = [UInt8]()
nonisolated(unsafe) var callbackFiredCount = 0

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
    callbackFiredCount += 1
    let bufferBytes = Array(UnsafeBufferPointer(start: report, count: reportLength))
    let reportIDParam = UInt8(reportID)

    // The buffer already contains the report ID as byte[0] on multi-report devices.
    // Use the buffer directly; the reportID parameter is redundant.
    let bytes: [UInt8]
    if !bufferBytes.isEmpty && bufferBytes[0] == reportIDParam {
        bytes = bufferBytes  // Buffer includes report ID
    } else {
        bytes = [reportIDParam] + bufferBytes  // Prepend if missing
    }

    // Debug: print ALL incoming reports
    print("  [CB#\(callbackFiredCount)] reportID=0x\(String(format: "%02X", reportIDParam)) len=\(reportLength) data=\(hexString(bytes))")

    guard bytes.count >= 4 else { return }
    let respReportID = bytes[0]

    guard respReportID == HIDPP_SHORT_REPORT_ID ||
          respReportID == HIDPP_LONG_REPORT_ID ||
          respReportID == 0x8F else { return }

    // HID++ 2.0 error responses (featureIndex=0xFF) have swID in byte[4], not byte[3]
    let isHIDPP2Error = bytes[2] == 0xFF
    let responseSWID = isHIDPP2Error ? (bytes[4] & 0x0F) : (bytes[3] & 0x0F)

    if responseSWID == SW_ID || respReportID == 0x8F {
        lastResponse = bytes
        responseReceived = true
    }
}

// MARK: - Send and Wait

func sendReport(_ report: [UInt8], timeout: TimeInterval = 3.0) -> [UInt8]? {
    guard let device = g402Device else {
        print("ERROR: No device")
        return nil
    }

    responseReceived = false
    lastResponse = []
    callbackFiredCount = 0

    let reportID = CFIndex(report[0])

    print("  TX: \(hexString(report))")

    // Try sending WITH report ID in buffer (Apple docs say to include it for multi-report devices)
    let result = report.withUnsafeBufferPointer { buffer in
        IOHIDDeviceSetReport(device, kIOHIDReportTypeOutput, reportID, buffer.baseAddress!, buffer.count)
    }

    if result != kIOReturnSuccess {
        print("  ERROR: IOHIDDeviceSetReport (with reportID in buffer) failed: 0x\(String(format: "%08X", result))")

        // Fallback: try sending WITHOUT report ID in buffer
        print("  Retrying without report ID in buffer...")
        let reportData = Array(report.dropFirst())
        let result2 = reportData.withUnsafeBufferPointer { buffer in
            IOHIDDeviceSetReport(device, kIOHIDReportTypeOutput, reportID, buffer.baseAddress!, buffer.count)
        }
        if result2 != kIOReturnSuccess {
            print("  ERROR: IOHIDDeviceSetReport (without reportID) also failed: 0x\(String(format: "%08X", result2))")
            return nil
        }
        print("  Send succeeded without report ID in buffer")
    }

    // Wait for response, pumping the run loop
    let deadline = Date().addingTimeInterval(timeout)
    while !responseReceived && Date() < deadline {
        RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.05))
    }

    if callbackFiredCount == 0 {
        print("  WARNING: Input report callback never fired (0 callbacks in \(timeout)s)")
    } else {
        print("  Callback fired \(callbackFiredCount) time(s)")
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

    // Check for error response (report ID 0x8F = HID++ 1.0 error)
    if response[0] == 0x8F {
        print("  Got HID++ 1.0 error response — this device may use HID++ 1.0, not 2.0")
        print("  Error code: 0x\(String(format: "%02X", response.count > 6 ? response[6] : 0))")
        return nil
    }

    // Check for HID++ 2.0 error (feature index 0xFF with error)
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
    let report = makeLongReport(featureIndex: featureIndex, functionID: 2, params: [sensorIndex])  // func 2 = getSensorDpi

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
    let report = makeLongReport(featureIndex: featureIndex, functionID: 3, params: [sensorIndex, hi, lo])  // func 3 = setSensorDpi

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

// MARK: - DPI Capabilities (mirrors SensorDPICapabilities in main app)

struct DPICapabilities {
    let validDPIs: [UInt16]
    let minDPI: UInt16
    let maxDPI: UInt16
    let step: UInt16

    func snap(_ requested: UInt16) -> UInt16 {
        let clamped = min(max(requested, minDPI), maxDPI)
        var best = validDPIs[0]
        var bestDiff = abs(Int(clamped) - Int(best))
        for dpi in validDPIs {
            let diff = abs(Int(clamped) - Int(dpi))
            if diff < bestDiff {
                best = dpi
                bestDiff = diff
            }
        }
        return best
    }
}

func getSensorDpiList(featureIndex: UInt8, sensorIndex: UInt8 = 0) -> DPICapabilities? {
    print("\n--- Reading sensor DPI list (sensor \(sensorIndex)) ---")
    let report = makeLongReport(featureIndex: featureIndex, functionID: 1, params: [sensorIndex])

    guard let response = sendReport(report) else { return nil }

    if response[0] == 0x8F {
        print("  ERROR: getSensorDpiList failed with error")
        return nil
    }

    // Byte 4 = sensorIdx, DPI list starts at byte 5
    let payload = Array(response[5...])

    // Read 16-bit big-endian entries until 0x0000 terminator
    var entries: [UInt16] = []
    var i = 0
    while i + 1 < payload.count {
        let value = (UInt16(payload[i]) << 8) | UInt16(payload[i + 1])
        if value == 0x0000 { break }
        entries.append(value)
        i += 2
    }

    print("  Raw entries: \(entries.map { String(format: "0x%04X", $0) }.joined(separator: ", "))")

    guard !entries.isEmpty else {
        print("  ERROR: No entries in DPI list")
        return nil
    }

    // Expand entries into flat list of valid DPIs
    // 0xE0xx (bits 15-13 = 111) = step marker for range between surrounding values
    var validDPIs: [UInt16] = []
    var idx = 0
    while idx < entries.count {
        let val = entries[idx]
        if idx + 1 < entries.count && (entries[idx + 1] & 0xE000) == 0xE000 {
            let stepSize = entries[idx + 1] & 0x1FFF
            let rangeStart = val
            guard idx + 2 < entries.count else {
                validDPIs.append(rangeStart)
                break
            }
            let rangeEnd = entries[idx + 2]
            print("  Range: \(rangeStart) to \(rangeEnd) step \(stepSize)")
            if stepSize > 0 {
                var d = rangeStart
                while d <= rangeEnd {
                    validDPIs.append(d)
                    d += stepSize
                }
            } else {
                validDPIs.append(rangeStart)
                validDPIs.append(rangeEnd)
            }
            idx += 3
        } else {
            validDPIs.append(val)
            idx += 1
        }
    }

    guard !validDPIs.isEmpty else {
        print("  ERROR: Could not expand DPI list")
        return nil
    }

    validDPIs = Array(Set(validDPIs)).sorted()

    let minDPI = validDPIs.first!
    let maxDPI = validDPIs.last!
    var smallestStep: UInt16 = maxDPI - minDPI
    for j in 1..<validDPIs.count {
        let diff = validDPIs[j] - validDPIs[j - 1]
        if diff > 0 && diff < smallestStep {
            smallestStep = diff
        }
    }

    print("  Sensor DPI: min=\(minDPI) max=\(maxDPI) step=\(smallestStep) (\(validDPIs.count) values)")
    print("  All valid DPIs: \(validDPIs)")

    return DPICapabilities(validDPIs: validDPIs, minDPI: minDPI, maxDPI: maxDPI, step: smallestStep)
}

// MARK: - Main

print("=== G402 DPI Controller - CLI Smoke Test ===")
print("Looking for Logitech G402 (VID=0x\(String(format: "%04X", LOGITECH_VID)), PID=0x\(String(format: "%04X", G402_PID)))...")

// Create HID Manager
let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))

// Match dictionary: G402 HID++ interface (PrimaryUsage=6)
let matchDict: [String: Any] = [
    kIOHIDVendorIDKey as String: LOGITECH_VID,
    kIOHIDProductIDKey as String: G402_PID,
    kIOHIDPrimaryUsageKey as String: 6  // Keyboard/HID++ control interface
]

IOHIDManagerSetDeviceMatching(manager, matchDict as CFDictionary)
IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)

let openResult = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
if openResult != kIOReturnSuccess {
    print("ERROR: Failed to open HID Manager (0x\(String(format: "%08X", openResult)))")
    print("Make sure Input Monitoring is enabled in System Settings > Privacy & Security")
    exit(1)
}

// Get matching devices
guard let deviceSet = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> else {
    print("ERROR: No devices found. Is the G402 plugged in?")
    print("Check: ioreg -p IOUSB | grep G402")
    exit(1)
}

print("Found \(deviceSet.count) matching HID interface(s)")

guard let device = deviceSet.first else {
    print("ERROR: No G402 HID++ interface found")
    exit(1)
}

g402Device = device

// Print device properties for debugging
func getDeviceProperty(_ device: IOHIDDevice, _ key: String) -> Any? {
    IOHIDDeviceGetProperty(device, key as CFString)
}
print("\nDevice properties:")
print("  Product:          \(getDeviceProperty(device, kIOHIDProductKey) ?? "?")")
print("  VendorID:         \(getDeviceProperty(device, kIOHIDVendorIDKey) ?? "?")")
print("  ProductID:        \(getDeviceProperty(device, kIOHIDProductIDKey) ?? "?")")
print("  PrimaryUsage:     \(getDeviceProperty(device, kIOHIDPrimaryUsageKey) ?? "?")")
print("  PrimaryUsagePage: \(getDeviceProperty(device, kIOHIDPrimaryUsagePageKey) ?? "?")")
print("  MaxInputReport:   \(getDeviceProperty(device, kIOHIDMaxInputReportSizeKey) ?? "?")")
print("  MaxOutputReport:  \(getDeviceProperty(device, kIOHIDMaxOutputReportSizeKey) ?? "?")")
print("  Transport:        \(getDeviceProperty(device, kIOHIDTransportKey) ?? "?")")

// Open the device
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

print("\nDevice opened successfully")

// Explicitly schedule device on current run loop (belt and suspenders)
IOHIDDeviceScheduleWithRunLoop(device, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)

// Register input report callback
let reportBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: HIDPP_LONG_LENGTH)
IOHIDDeviceRegisterInputReportCallback(device, reportBuffer, HIDPP_LONG_LENGTH, inputReportCallback, nil)

// First, pump the run loop briefly to process any pending events
print("\nWaiting 0.5s for device initialization...")
let initDeadline = Date().addingTimeInterval(0.5)
while Date() < initDeadline {
    RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.05))
}
if callbackFiredCount > 0 {
    print("Received \(callbackFiredCount) unsolicited report(s) during init")
    callbackFiredCount = 0
}

// Step 1: Discover feature indices
guard let dpiFeatureIndex = discoverFeatureIndex(featureID: ADJUSTABLE_DPI_FEATURE_ID) else {
    print("\nFATAL: Could not discover Adjustable DPI feature.")
    reportBuffer.deallocate()
    exit(1)
}

let profileFeatureIndex = discoverFeatureIndex(featureID: 0x8100)  // Onboard Profiles

// Step 2: Check current onboard profile mode
if let profIdx = profileFeatureIndex {
    print("\n--- Reading current profile mode (feature 0x8100, func 2 = getMode) ---")
    let getModeReport = makeLongReport(featureIndex: profIdx, functionID: 2, params: [])
    if let response = sendReport(getModeReport) {
        let mode = response.count > 4 ? response[4] : 0xFF
        print("  Current mode: 0x\(String(format: "%02X", mode)) (\(mode == 1 ? "HOST" : mode == 2 ? "ONBOARD" : "UNKNOWN"))")
    }

    // Step 3: Switch to HOST mode so we can control DPI from software
    print("\n--- Switching to HOST mode (feature 0x8100, func 1 = setMode, param 0x01) ---")
    let setModeReport = makeLongReport(featureIndex: profIdx, functionID: 1, params: [0x01])
    if let response = sendReport(setModeReport) {
        let newMode = response.count > 4 ? response[4] : 0xFF
        print("  Mode after set: 0x\(String(format: "%02X", newMode)) (\(newMode == 1 ? "HOST" : newMode == 2 ? "ONBOARD" : "UNKNOWN"))")
    }
} else {
    print("\n  Onboard Profiles feature not found — skipping mode switch")
}

// Step 4: Get sensor count
let _ = getSensorCount(featureIndex: dpiFeatureIndex)

// Step 5: Query sensor DPI list (hardware capabilities)
let capabilities = getSensorDpiList(featureIndex: dpiFeatureIndex, sensorIndex: 0)

// Step 6: Read current DPI
let currentDPI = getSensorDPI(featureIndex: dpiFeatureIndex, sensorIndex: 0)
print("\n  >>> Current DPI: \(currentDPI.map { String($0) } ?? "unknown")")

// Step 7: Set DPI to 1600 (snapped to nearest valid hardware DPI)
let requestedDPI: UInt16 = 1600
let targetDPI: UInt16 = capabilities?.snap(requestedDPI) ?? requestedDPI
if targetDPI != requestedDPI {
    print("\n  Snapped \(requestedDPI) → \(targetDPI) (nearest valid hardware DPI)")
}

if setSensorDPI(featureIndex: dpiFeatureIndex, sensorIndex: 0, dpi: targetDPI) {
    // Step 8: Read back to verify
    if let newDPI = getSensorDPI(featureIndex: dpiFeatureIndex, sensorIndex: 0) {
        let diff = abs(Int(newDPI) - Int(targetDPI))
        let tolerance = Int(capabilities?.step ?? 50)
        if diff <= tolerance {
            print("\n=== SUCCESS: DPI set to \(newDPI) (requested \(requestedDPI), snapped to \(targetDPI)) ===")
        } else {
            print("\n=== WARNING: DPI readback mismatch — sent \(targetDPI) but read \(newDPI) (tolerance: \(tolerance)) ===")
        }
    }
} else {
    print("\n=== FAILED: Could not set DPI ===")
}

// Step 9: Test all presets (snap and report)
if let caps = capabilities {
    print("\n--- Preset DPI snapping ---")
    for preset: UInt16 in [400, 800, 1200, 1600, 3200] {
        let snapped = caps.snap(preset)
        print("  \(preset) → \(snapped)")
    }
}

// Step 10: Verify mode is still host
if let profIdx = profileFeatureIndex {
    print("\n--- Verifying profile mode after DPI set ---")
    let getModeReport = makeLongReport(featureIndex: profIdx, functionID: 2, params: [])
    if let response = sendReport(getModeReport) {
        let mode = response.count > 4 ? response[4] : 0xFF
        print("  Mode: 0x\(String(format: "%02X", mode)) (\(mode == 1 ? "HOST" : mode == 2 ? "ONBOARD" : "UNKNOWN"))")
    }
}

// Cleanup
IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone))
reportBuffer.deallocate()

print("\n=== Smoke test complete ===")
