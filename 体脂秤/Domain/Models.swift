import Foundation

enum Sex: String, CaseIterable, Codable { case female, male }

enum ImpedanceADCChoice: Int {
    static let storageKey = "afu.algorithm.adcIndex"
    case first = 0
    case second = 1
}

struct FamilyMember: Identifiable, Codable {
    let id: UUID
    var name: String
    var sex: Sex
    var height: Double
    var birthDate: Date
    var referenceWeight: Double
    init(id: UUID = UUID(), name: String, sex: Sex, height: Double, birthDate: Date, referenceWeight: Double) { self.id = id; self.name = name; self.sex = sex; self.height = height; self.birthDate = birthDate; self.referenceWeight = referenceWeight }
    var age: Int { Calendar.current.dateComponents([.year], from: birthDate, to: .now).year ?? 28 }
}

struct BodyMeasurement: Identifiable, Codable {
    let id: UUID; let date: Date; let weight: Double; let impedance: Double; let bmi: Double; let bodyFat: Double; let muscle: Double; let water: Double; let protein: Double; let boneMass: Double; let memberID: UUID?; let memberName: String?
    var adcIndex: Int? = nil
    
    // Computed Properties for UI to show all required metrics (both percentage and mass)
    var bodyFatMass: Double { weight * (bodyFat / 100.0) }
    var musclePercent: Double { weight > 0 ? (muscle / weight) * 100.0 : 0.0 }
    var skeletalMusclePercent: Double { musclePercent * 0.527 }
    var skeletalMuscleMass: Double { muscle * 0.527 }
    var waterMass: Double { weight * (water / 100.0) }
    var proteinMass: Double { weight * (protein / 100.0) }
    var boneMassPercent: Double { weight > 0 ? (boneMass / weight) * 100.0 : 0.0 }
    var subcutaneousFatPercent: Double { bodyFat * 0.72 }
    var subcutaneousFatMass: Double { weight * (subcutaneousFatPercent / 100.0) }
}
