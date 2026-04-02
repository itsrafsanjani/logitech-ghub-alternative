import Foundation

// Feature 0x2201 — Adjustable DPI
// Functions:
//   0: getSensorCount() -> count
//   1: getSensorDPI(sensorIdx) -> dpi, defaultDpi
//   2: setSensorDPI(sensorIdx, dpi) -> sensorIdx, dpi

enum G402DPI {
    static let minDPI: UInt16 = 300
    static let maxDPI: UInt16 = 4000
    static let step: UInt16 = 50
    static let presets: [UInt16] = [400, 800, 1200, 1600, 3200]
    static let defaultDPI: UInt16 = 1600

    static func clamp(_ dpi: UInt16) -> UInt16 {
        let clamped = min(max(dpi, minDPI), maxDPI)
        return (clamped / step) * step  // Round to nearest step
    }

    static func isValid(_ dpi: UInt16) -> Bool {
        dpi >= minDPI && dpi <= maxDPI && dpi % step == 0
    }
}
