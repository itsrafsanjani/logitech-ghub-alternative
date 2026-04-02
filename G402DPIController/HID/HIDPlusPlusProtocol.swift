import Foundation

// MARK: - HID++ Constants

enum HIDPPConstants {
    static let shortReportID: UInt8 = 0x10
    static let longReportID: UInt8 = 0x11
    static let errorReportID: UInt8 = 0x8F
    static let shortLength = 7
    static let longLength = 20
    static let deviceIndex: UInt8 = 0xFF  // Direct USB (wired) — 0x01..0x06 is for Unifying receiver
    static let swID: UInt8 = 0x07

    // Well-known feature IDs
    static let iRootFeatureID: UInt16 = 0x0000
    static let adjustableDPIFeatureID: UInt16 = 0x2201
    static let onboardProfilesFeatureID: UInt16 = 0x8100

    // G402 USB identifiers
    static let logitechVID = 0x046d
    static let g402PID = 0xc07e
    static let hidppPrimaryUsage = 6  // Keyboard interface = HID++ control channel
}

// MARK: - HID++ Message

struct HIDPPMessage {
    let reportID: UInt8
    let deviceIndex: UInt8
    let featureIndex: UInt8
    let functionID: UInt8
    let swID: UInt8
    let params: [UInt8]

    var isLong: Bool { reportID == HIDPPConstants.longReportID }
    var isError: Bool { reportID == HIDPPConstants.errorReportID }

    func toBytes() -> [UInt8] {
        let length = isLong ? HIDPPConstants.longLength : HIDPPConstants.shortLength
        var report = [UInt8](repeating: 0, count: length)
        report[0] = reportID
        report[1] = deviceIndex
        report[2] = featureIndex
        report[3] = (functionID << 4) | (swID & 0x0F)
        for (i, p) in params.prefix(length - 4).enumerated() {
            report[4 + i] = p
        }
        return report
    }

    static func parse(_ data: [UInt8]) -> HIDPPMessage? {
        guard data.count >= HIDPPConstants.shortLength else { return nil }
        let reportID = data[0]
        guard reportID == HIDPPConstants.shortReportID ||
              reportID == HIDPPConstants.longReportID ||
              reportID == HIDPPConstants.errorReportID else { return nil }

        return HIDPPMessage(
            reportID: reportID,
            deviceIndex: data[1],
            featureIndex: data[2],
            functionID: (data[3] >> 4) & 0x0F,
            swID: data[3] & 0x0F,
            params: Array(data.dropFirst(4))
        )
    }

    static func shortReport(featureIndex: UInt8, functionID: UInt8, params: [UInt8] = []) -> HIDPPMessage {
        HIDPPMessage(
            reportID: HIDPPConstants.shortReportID,
            deviceIndex: HIDPPConstants.deviceIndex,
            featureIndex: featureIndex,
            functionID: functionID,
            swID: HIDPPConstants.swID,
            params: params
        )
    }

    static func longReport(featureIndex: UInt8, functionID: UInt8, params: [UInt8] = []) -> HIDPPMessage {
        HIDPPMessage(
            reportID: HIDPPConstants.longReportID,
            deviceIndex: HIDPPConstants.deviceIndex,
            featureIndex: featureIndex,
            functionID: functionID,
            swID: HIDPPConstants.swID,
            params: params
        )
    }
}

// MARK: - Feature Index Cache

actor FeatureIndexCache {
    private var cache: [UInt16: UInt8] = [:]

    func get(_ featureID: UInt16) -> UInt8? {
        cache[featureID]
    }

    func set(_ featureID: UInt16, index: UInt8) {
        cache[featureID] = index
    }

    func clear() {
        cache.removeAll()
    }
}
