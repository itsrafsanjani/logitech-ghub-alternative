import Foundation

// Feature 0x2201 — Adjustable DPI
// Functions:
//   0: getSensorCount() -> count
//   1: getSensorDpiList(sensorIdx) -> dpi list (range or discrete)
//   2: getSensorDpi(sensorIdx) -> dpi, defaultDpi
//   3: setSensorDpi(sensorIdx, dpi) -> sensorIdx, dpi

// MARK: - Hardware DPI Capabilities (queried at runtime)

struct SensorDPICapabilities {
    let validDPIs: [UInt16]
    let minDPI: UInt16
    let maxDPI: UInt16
    let step: UInt16

    /// Parse a getSensorDpiList response payload (bytes after the 4-byte header).
    /// Format: sequence of big-endian 16-bit values:
    ///   - 0x0000 = terminator
    ///   - 0xE0xx (bits 15-13 = 111) = step marker for preceding range
    ///   - other = literal DPI value or range boundary
    static func parse(payload: [UInt8]) -> SensorDPICapabilities? {
        var entries: [UInt16] = []
        var i = 0
        while i + 1 < payload.count {
            let value = (UInt16(payload[i]) << 8) | UInt16(payload[i + 1])
            if value == 0x0000 { break }
            entries.append(value)
            i += 2
        }
        guard !entries.isEmpty else { return nil }

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

        guard !validDPIs.isEmpty else { return nil }
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

        return SensorDPICapabilities(
            validDPIs: validDPIs,
            minDPI: minDPI,
            maxDPI: maxDPI,
            step: smallestStep
        )
    }

    /// Snap a requested DPI to the nearest valid hardware DPI.
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

// MARK: - Hardcoded Defaults (fallback)

enum G402DPI {
    static let minDPI: UInt16 = 300
    static let maxDPI: UInt16 = 4000
    static let step: UInt16 = 50
    static let presets: [UInt16] = [400, 800, 1200, 1600, 3200]
    static let defaultDPI: UInt16 = 1600

    static func clamp(_ dpi: UInt16) -> UInt16 {
        let clamped = min(max(dpi, minDPI), maxDPI)
        return (clamped / step) * step
    }

    static func isValid(_ dpi: UInt16) -> Bool {
        dpi >= minDPI && dpi <= maxDPI && dpi % step == 0
    }

    static var fallbackCapabilities: SensorDPICapabilities {
        var dpis: [UInt16] = []
        var d = minDPI
        while d <= maxDPI {
            dpis.append(d)
            d += step
        }
        return SensorDPICapabilities(validDPIs: dpis, minDPI: minDPI, maxDPI: maxDPI, step: step)
    }
}
