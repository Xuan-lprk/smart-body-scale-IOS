import Foundation
import HealthKit
import Combine

@MainActor
final class HealthKitManager: ObservableObject {
    static let enabledKey = "afu.health.enabled"
    static let weightKey = "afu.health.weight"
    static let bmiKey = "afu.health.bmi"
    static let bodyFatKey = "afu.health.bodyFat"
    static let leanBodyMassKey = "afu.health.leanBodyMass"

    @Published private(set) var statusText = "尚未连接 Apple 健康"
    @Published private(set) var lastSyncText: String?

    private let healthStore = HKHealthStore()

    init() {
        UserDefaults.standard.register(defaults: [
            Self.enabledKey: false,
            Self.weightKey: true,
            Self.bmiKey: true,
            Self.bodyFatKey: true,
            Self.leanBodyMassKey: true
        ])
        refreshStatus()
    }

    var isAvailable: Bool {
        HKHealthStore.isHealthDataAvailable()
    }

    func requestAuthorization() {
        guard isAvailable else {
            statusText = "此设备不支持 Apple 健康"
            return
        }

        let types = enabledWriteTypes()
        guard !types.isEmpty else {
            statusText = "请至少选择一个同步项目"
            return
        }

        healthStore.requestAuthorization(toShare: types, read: []) { [weak self] success, error in
            guard let manager = self else { return }
            let message = success
                ? "已请求 Apple 健康写入权限"
                : (error?.localizedDescription ?? "未获得 Apple 健康权限")
            Task { @MainActor in
                manager.statusText = message
            }
        }
    }

    func save(_ measurement: BodyMeasurement) {
        guard UserDefaults.standard.bool(forKey: Self.enabledKey), isAvailable else { return }

        let samples = makeSamples(for: measurement)
        guard !samples.isEmpty else {
            statusText = "没有选择需要同步的项目"
            return
        }

        let syncDate = measurement.date
        healthStore.save(samples) { [weak self] success, error in
            guard let manager = self else { return }
            let errorMessage = error?.localizedDescription ?? "写入 Apple 健康失败"
            Task { @MainActor in
                if success {
                    let formatter = DateFormatter()
                    formatter.dateFormat = "MM-dd HH:mm"
                    manager.lastSyncText = "最近同步：\(formatter.string(from: syncDate))"
                    manager.statusText = "已写入 Apple 健康"
                } else {
                    manager.statusText = errorMessage
                }
            }
        }
    }

    func refreshStatus() {
        guard isAvailable else {
            statusText = "此设备不支持 Apple 健康"
            return
        }
        if !UserDefaults.standard.bool(forKey: Self.enabledKey) {
            statusText = "同步尚未开启"
            return
        }

        let statuses = enabledWriteTypes().map { healthStore.authorizationStatus(for: $0) }
        if statuses.contains(.sharingDenied) {
            statusText = "部分项目未获写入权限"
        } else if !statuses.isEmpty && statuses.allSatisfy({ $0 == .sharingAuthorized }) {
            statusText = "已连接 Apple 健康"
        } else {
            statusText = "等待 Apple 健康授权"
        }
    }

    private func enabledWriteTypes() -> Set<HKSampleType> {
        var types = Set<HKSampleType>()
        let defaults = UserDefaults.standard

        if defaults.bool(forKey: Self.weightKey),
           let type = HKQuantityType.quantityType(forIdentifier: .bodyMass) {
            types.insert(type)
        }
        if defaults.bool(forKey: Self.bmiKey),
           let type = HKQuantityType.quantityType(forIdentifier: .bodyMassIndex) {
            types.insert(type)
        }
        if defaults.bool(forKey: Self.bodyFatKey),
           let type = HKQuantityType.quantityType(forIdentifier: .bodyFatPercentage) {
            types.insert(type)
        }
        if defaults.bool(forKey: Self.leanBodyMassKey),
           let type = HKQuantityType.quantityType(forIdentifier: .leanBodyMass) {
            types.insert(type)
        }
        return types
    }

    private func makeSamples(for measurement: BodyMeasurement) -> [HKQuantitySample] {
        let defaults = UserDefaults.standard
        var samples: [HKQuantitySample] = []

        if defaults.bool(forKey: Self.weightKey),
           let type = HKQuantityType.quantityType(forIdentifier: .bodyMass) {
            samples.append(sample(
                type: type,
                unit: .gramUnit(with: .kilo),
                value: measurement.weight,
                measurement: measurement,
                metadata: metadata(for: measurement, metric: "weight")
            ))
        }

        if defaults.bool(forKey: Self.bmiKey),
           let type = HKQuantityType.quantityType(forIdentifier: .bodyMassIndex) {
            samples.append(sample(
                type: type,
                unit: .count(),
                value: measurement.bmi,
                measurement: measurement,
                metadata: metadata(for: measurement, metric: "bmi")
            ))
        }

        if defaults.bool(forKey: Self.bodyFatKey),
           let type = HKQuantityType.quantityType(forIdentifier: .bodyFatPercentage) {
            samples.append(sample(
                type: type,
                unit: .percent(),
                value: measurement.bodyFat / 100.0,
                measurement: measurement,
                metadata: metadata(for: measurement, metric: "body-fat")
            ))
        }

        if defaults.bool(forKey: Self.leanBodyMassKey),
           let type = HKQuantityType.quantityType(forIdentifier: .leanBodyMass) {
            let leanBodyMass = measurement.weight * (1.0 - measurement.bodyFat / 100.0)
            samples.append(sample(
                type: type,
                unit: .gramUnit(with: .kilo),
                value: leanBodyMass,
                measurement: measurement,
                metadata: metadata(for: measurement, metric: "lean-body-mass")
            ))
        }

        return samples
    }

    private func metadata(for measurement: BodyMeasurement, metric: String) -> [String: Any] {
        let algorithm = (100.0...1500.0).contains(measurement.impedance)
            ? "segal_1988_v1"
            : "deurenberg_bmi_fallback_v1"
        var metadata: [String: Any] = [
            HKMetadataKeySyncIdentifier: "afu-scale-\(measurement.id.uuidString)-\(metric)",
            HKMetadataKeySyncVersion: 1,
            "tizhicheng.bodyAlgorithm": algorithm,
            "tizhicheng.impedanceOhm": measurement.impedance
        ]
        if let adcIndex = measurement.adcIndex {
            metadata["tizhicheng.adcNumber"] = adcIndex + 1
        }
        return metadata
    }

    private func sample(
        type: HKQuantityType,
        unit: HKUnit,
        value: Double,
        measurement: BodyMeasurement,
        metadata: [String: Any]
    ) -> HKQuantitySample {
        HKQuantitySample(
            type: type,
            quantity: HKQuantity(unit: unit, doubleValue: value),
            start: measurement.date,
            end: measurement.date,
            metadata: metadata
        )
    }
}
