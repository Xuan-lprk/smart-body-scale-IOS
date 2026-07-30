import Foundation
import Combine

enum ReferenceType: String, Codable {
    case officialApp = "official_app"
}

enum ReferenceImportMethod: String, Codable {
    case manual
    case screenshotOCR = "screenshot_ocr"
}

struct OfficialReferenceRecord: Identifiable, Codable {
    let id: UUID
    let measurementID: UUID
    let measuredAt: Date
    let importedAt: Date
    let referenceType: ReferenceType
    let importMethod: ReferenceImportMethod
    let weight: Double
    let bodyFat: Double
    let waterPercent: Double?
    let musclePercent: Double?
    let proteinPercent: Double?
    let boneMass: Double?
    let skeletalMusclePercent: Double?
    let subcutaneousFatPercent: Double?
    let visceralFat: Double?
    let note: String?
}

struct OfficialReferenceDraft: Equatable {
    var measuredAt: Date?
    var weight: Double?
    var bodyFat: Double?
    var waterPercent: Double?
    var musclePercent: Double?
    var proteinPercent: Double?
    var boneMass: Double?
    var skeletalMusclePercent: Double?
    var subcutaneousFatPercent: Double?
    var visceralFat: Double?

    mutating func merge(_ other: OfficialReferenceDraft) {
        measuredAt = measuredAt ?? other.measuredAt
        weight = weight ?? other.weight
        bodyFat = bodyFat ?? other.bodyFat
        waterPercent = waterPercent ?? other.waterPercent
        musclePercent = musclePercent ?? other.musclePercent
        proteinPercent = proteinPercent ?? other.proteinPercent
        boneMass = boneMass ?? other.boneMass
        skeletalMusclePercent = skeletalMusclePercent ?? other.skeletalMusclePercent
        subcutaneousFatPercent = subcutaneousFatPercent ?? other.subcutaneousFatPercent
        visceralFat = visceralFat ?? other.visceralFat
    }
}

struct ADCComparison: Identifiable {
    let reference: OfficialReferenceRecord
    let measurement: BodyMeasurement
    let adc1Measurement: BodyMeasurement
    let adc2Measurement: BodyMeasurement
    let isQualified: Bool
    let qualityReason: String

    var id: UUID { reference.id }
    var adc1Error: Double { adc1Measurement.bodyFat - reference.bodyFat }
    var adc2Error: Double { adc2Measurement.bodyFat - reference.bodyFat }
    var timeDifferenceMinutes: Double {
        abs(reference.measuredAt.timeIntervalSince(measurement.date)) / 60
    }
    var weightDifference: Double { abs(reference.weight - measurement.weight) }
}

struct ADCErrorStatistics {
    let sampleCount: Int
    let meanBias: Double
    let medianBias: Double
    let mae: Double
    let rmse: Double
}

struct ComparisonSummary {
    let totalCount: Int
    let qualifiedCount: Int
    let distinctQualifiedDates: Int
    let adc1: ADCErrorStatistics?
    let adc2: ADCErrorStatistics?

    var recommendation: String {
        guard distinctQualifiedDates >= 10, let adc1, let adc2 else {
            return "还需 \(max(0, 10 - distinctQualifiedDates)) 个不同日期的合格对照，才给出 ADC 建议。"
        }
        if abs(adc1.mae - adc2.mae) < 0.1 {
            return "两路 ADC 的 MAE 很接近，暂不建议切换。"
        }
        return adc1.mae < adc2.mae
            ? "目前 ADC 1 更贴近阿福结果（按体脂 MAE 判断）。"
            : "目前 ADC 2 更贴近阿福结果（按体脂 MAE 判断）。"
    }
}

@MainActor
final class ComparisonStore: ObservableObject {
    private static let storageKey = "afu.official.references"

    @Published private(set) var references: [OfficialReferenceRecord] = []

    init() {
        load()
    }

    func upsert(_ reference: OfficialReferenceRecord) {
        references.removeAll {
            $0.id == reference.id
                || ($0.measurementID == reference.measurementID
                    && $0.referenceType == reference.referenceType)
        }
        references.append(reference)
        references.sort { $0.measuredAt > $1.measuredAt }
        save()
    }

    func remove(_ reference: OfficialReferenceRecord) {
        references.removeAll { $0.id == reference.id }
        save()
    }

    func removeReferences(for measurementID: UUID) {
        references.removeAll { $0.measurementID == measurementID }
        save()
    }

    func reference(for measurementID: UUID) -> OfficialReferenceRecord? {
        references.first { $0.measurementID == measurementID }
    }

    func comparison(
        for reference: OfficialReferenceRecord,
        history: [BodyMeasurement],
        fallbackMember: FamilyMember
    ) -> ADCComparison? {
        guard let measurement = history.first(where: { $0.id == reference.measurementID }),
              let impedances = measurement.normalizedImpedances,
              impedances.count >= 2,
              impedances.prefix(2).allSatisfy({ (100.0...1500.0).contains($0) }) else {
            return nil
        }

        let member = measurement.profileSnapshot?.member(
            id: measurement.memberID,
            name: measurement.memberName,
            referenceWeight: measurement.weight
        ) ?? fallbackMember
        let adc1 = BodyAlgorithm.measure(
            date: measurement.date,
            weight: measurement.weight,
            impedance: impedances[0],
            member: member,
            adcIndex: 0
        )
        let adc2 = BodyAlgorithm.measure(
            date: measurement.date,
            weight: measurement.weight,
            impedance: impedances[1],
            member: member,
            adcIndex: 1
        )

        let timeDifference = abs(reference.measuredAt.timeIntervalSince(measurement.date))
        let weightDifference = abs(reference.weight - measurement.weight)
        let isQualified = timeDifference <= 30 * 60 && weightDifference <= 0.2
        let reason: String
        if timeDifference > 30 * 60 {
            reason = "阿福与本地测量相隔超过 30 分钟"
        } else if weightDifference > 0.2 {
            reason = "两次体重相差超过 0.2 kg"
        } else {
            reason = "时间与体重差符合对照条件"
        }

        return ADCComparison(
            reference: reference,
            measurement: measurement,
            adc1Measurement: adc1,
            adc2Measurement: adc2,
            isQualified: isQualified,
            qualityReason: reason
        )
    }

    func comparisons(
        history: [BodyMeasurement],
        fallbackMember: FamilyMember
    ) -> [ADCComparison] {
        references.compactMap {
            comparison(for: $0, history: history, fallbackMember: fallbackMember)
        }
        .sorted { $0.reference.measuredAt > $1.reference.measuredAt }
    }

    func summary(for comparisons: [ADCComparison]) -> ComparisonSummary {
        let qualified = comparisons.filter(\.isQualified)
        let dates = Set(qualified.map {
            Calendar.current.startOfDay(for: $0.reference.measuredAt)
        })
        return ComparisonSummary(
            totalCount: references.count,
            qualifiedCount: qualified.count,
            distinctQualifiedDates: dates.count,
            adc1: statistics(for: qualified.map(\.adc1Error)),
            adc2: statistics(for: qualified.map(\.adc2Error))
        )
    }

    private func statistics(for errors: [Double]) -> ADCErrorStatistics? {
        guard !errors.isEmpty else { return nil }
        let sorted = errors.sorted()
        let median: Double
        if sorted.count.isMultiple(of: 2) {
            median = (sorted[sorted.count / 2 - 1] + sorted[sorted.count / 2]) / 2
        } else {
            median = sorted[sorted.count / 2]
        }
        let count = Double(errors.count)
        return ADCErrorStatistics(
            sampleCount: errors.count,
            meanBias: errors.reduce(0, +) / count,
            medianBias: median,
            mae: errors.map(abs).reduce(0, +) / count,
            rmse: sqrt(errors.map { $0 * $0 }.reduce(0, +) / count)
        )
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(references) else { return }
        UserDefaults.standard.set(data, forKey: Self.storageKey)
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: Self.storageKey),
              let saved = try? JSONDecoder().decode([OfficialReferenceRecord].self, from: data) else {
            return
        }
        references = saved.sorted { $0.measuredAt > $1.measuredAt }
    }
}
