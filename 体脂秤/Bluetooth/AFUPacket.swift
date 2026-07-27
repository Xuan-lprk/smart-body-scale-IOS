import Foundation

struct AFUPacket {
    enum Kind { case weight, impedance, history, settings }
    let type: Kind; let raw: Data
    
    init?(data: Data) {
        guard data.count >= 20, data.first == 0xAC else {
            // Fallback for original standard AFU packets (without wrapper)
            guard let first = data.first else { return nil }
            raw = data
            switch first {
            case 0xD5: type = .weight
            case 0xD6: type = .impedance
            case 0xD8: type = .history
            case 0xDF: type = .settings
            default: return nil
            }
            return
        }
        
        raw = data
        let opcode = data[18]
        switch opcode {
        case 0xD5: type = .weight
        case 0xD6: type = .impedance
        case 0xD8: type = .history
        case 0xDF: type = .settings
        default: return nil
        }
    }
    
    private var payload32: UInt32 {
        guard raw.count >= 5 else { return 0 }
        return UInt32(raw[1]) | UInt32(raw[2]) << 8 | UInt32(raw[3]) << 16 | UInt32(raw[4]) << 24
    }
    
    var stable: Bool {
        if raw.first == 0xAC {
            // Status byte at index 6: 0x02 indicates stable
            return raw.count >= 7 && raw[6] == 0x02 && weight > 0
        } else {
            return payload32 & 0x8000_0000 != 0
        }
    }
    
    var weight: Double {
        if raw.first == 0xAC {
            // 3-byte weight encoding: rawVal = (raw[3] - 0x68) * 65536 + raw[4] * 256 + raw[5]
            // weight(kg) = rawVal / 1000
            // e.g. 82.05kg → raw[3]=0x69, raw[4]=0x40, raw[5]=0x82 → (1*65536+0x4082)/1000=82.05
            guard raw.count >= 6, raw[3] >= 0x68 else { return 0.0 }
            let base = UInt32(raw[3] - 0x68)
            let rawVal = (base << 16) | (UInt32(raw[4]) << 8) | UInt32(raw[5])
            return Double(rawVal) / 1000.0
        } else {
            return Double(payload32 & 0x0003_FFFF) / 1000.0
        }
    }
    
    var adcs: [Double] {
        if raw.first == 0xAC {
            guard raw.count >= 19, raw[18] == 0xD6 else { return [] }
            let count = Int(raw[2])
            let start = 4
            guard count > 0, start + count * 2 <= raw.count else { return [] }
            return (0..<count).map { index in
                let offset = start + index * 2
                return Double(UInt16(raw[offset]) << 8 | UInt16(raw[offset + 1]))
            }
        }

        guard raw.first == 0xD6, raw.count >= 3 else { return [] }
        return [Double(UInt16(raw[1]) << 8 | UInt16(raw[2]))]
    }

    var adcWeight: Double {
        guard raw.first == 0xAC, raw.count >= 13, raw[18] == 0xD6 else { return 0 }
        let encoded = UInt32(raw[9]) << 24
            | UInt32(raw[10]) << 16
            | UInt32(raw[11]) << 8
            | UInt32(raw[12])
        return Double(encoded & 0x0003_FFFF) / 1000.0
    }

    static func normalizeImpedances(_ adcs: [Double], weight: Double) -> [Double] {
        if adcs.count == 5 {
            return [adcs[4], adcs[0], adcs[1], adcs[2], adcs[3]].map(roundToTwoPlaces)
        }
        return adcs.map { adc in
            let normalized: Double
            if adc >= 1500, weight > 0 {
                normalized = (((adc - 1000) + ((weight * 10) * -0.4)) / 0.6) / 10
            } else {
                normalized = adc
            }
            return roundToTwoPlaces(normalized)
        }
    }

    nonisolated private static func roundToTwoPlaces(_ value: Double) -> Double {
        (value * 100).rounded() / 100
    }
    
    @MainActor func historyMeasurement(profile: UserProfile?, history: [BodyMeasurement]) -> BodyMeasurement? {
        guard let profile else { return nil }
        let kg = weight
        guard kg > 0 else { return nil }
        let member = profile.matchedMember(for: kg, history: history)
        
        let imp: Double
        if raw.first == 0xAC {
            imp = raw.count >= 10 ? Double(UInt16(raw[9]) | UInt16(raw[8]) << 8) : 0
        } else {
            imp = raw.count >= 7 ? Double(UInt16(raw[5]) | UInt16(raw[6]) << 8) : 0
        }
        return BodyAlgorithm.measure(weight: kg, impedance: imp, member: member)
    }
}
