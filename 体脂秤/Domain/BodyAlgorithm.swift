import Foundation

@MainActor enum BodyAlgorithm {
    static func measure(
        weight: Double,
        impedance: Double,
        member: FamilyMember,
        adcIndex: Int? = nil
    ) -> BodyMeasurement {
        let heightM = member.height / 100
        let bmi = weight / (heightM * heightM)
        let age = Double(member.age)
        let validResistance = (100.0...1500.0).contains(impedance) ? impedance : nil

        let baseBodyFat: Double
        if let resistance = validResistance {
            let heightSquared = member.height * member.height
            var fatFreeMass: Double

            if member.sex == .male {
                fatFreeMass = 9.33285
                    + 0.00066360 * heightSquared
                    - 0.02117 * resistance
                    + 0.62854 * weight
                    - 0.12380 * age
                let initialBodyFat = 100 * (weight - fatFreeMass) / weight
                if initialBodyFat >= 20 {
                    fatFreeMass = 14.52435
                        + 0.00088580 * heightSquared
                        - 0.02999 * resistance
                        + 0.42688 * weight
                        - 0.07002 * age
                }
            } else {
                fatFreeMass = 10.43485
                    + 0.00064602 * heightSquared
                    - 0.01397 * resistance
                    + 0.42087 * weight
                let initialBodyFat = 100 * (weight - fatFreeMass) / weight
                if initialBodyFat >= 30 {
                    fatFreeMass = 9.37938
                        + 0.00091186 * heightSquared
                        - 0.01466 * resistance
                        + 0.29990 * weight
                        - 0.07012 * age
                }
            }

            fatFreeMass = clamp(fatFreeMass, weight * 0.35, weight * 0.97)
            baseBodyFat = 100 * (weight - fatFreeMass) / weight
        } else {
            let sexValue = member.sex == .male ? 1.0 : 0.0
            baseBodyFat = 1.20 * bmi + 0.23 * age - 10.8 * sexValue - 5.4
        }

        let minimumBodyFat = member.sex == .male ? 3.0 : 8.0
        let fat = clamp(baseBodyFat, minimumBodyFat, 60.0)
        let bonePercent = member.sex == .male ? 4.5 : 4.0
        let musclePercent = clamp(100.0 - fat - bonePercent, 20.0, 95.0)
        let water = clamp((100.0 - fat) * 0.70, 25.0, 80.0)
        let protein = clamp((100.0 - fat) * 0.238, 5.0, 35.0)
        let bone = weight * bonePercent / 100.0
        let muscle = weight * musclePercent / 100.0
        return BodyMeasurement(id: UUID(), date: .now, weight: weight, impedance: impedance, bmi: bmi, bodyFat: fat, muscle: muscle, water: water, protein: protein, boneMass: bone, memberID: member.id, memberName: member.name, adcIndex: adcIndex)
    }

    private static func clamp(_ value: Double, _ lowerBound: Double, _ upperBound: Double) -> Double {
        min(max(value, lowerBound), upperBound)
    }
}
