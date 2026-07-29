import Foundation
import HealthKit
import Combine

enum HealthBodyMetric: String, CaseIterable, Hashable {
    case weight
    case bmi
    case bodyFat
    case leanBodyMass

    var title: String {
        switch self {
        case .weight: "体重"
        case .bmi: "BMI"
        case .bodyFat: "体脂率"
        case .leanBodyMass: "去脂体重"
        }
    }

    var typeIdentifier: HKQuantityTypeIdentifier {
        switch self {
        case .weight: .bodyMass
        case .bmi: .bodyMassIndex
        case .bodyFat: .bodyFatPercentage
        case .leanBodyMass: .leanBodyMass
        }
    }
}

struct HealthDataSourceSummary: Identifiable {
    let id: String
    let name: String
    let bundleIdentifier: String
    let providerName: String
    let isCurrentApp: Bool
    var metrics: Set<HealthBodyMetric>
    var latestDate: Date
    var sampleCount: Int

    var metricText: String {
        HealthBodyMetric.allCases
            .filter(metrics.contains)
            .map(\.title)
            .joined(separator: "、")
    }
}

@MainActor
final class HealthKitManager: ObservableObject {
    static let enabledKey = "afu.health.enabled"
    static let weightKey = "afu.health.weight"
    static let bmiKey = "afu.health.bmi"
    static let bodyFatKey = "afu.health.bodyFat"
    static let leanBodyMassKey = "afu.health.leanBodyMass"

    @Published private(set) var statusText = "尚未连接 Apple 健康"
    @Published private(set) var lastSyncText: String?
    @Published private(set) var sourceSummaries: [HealthDataSourceSummary] = []
    @Published private(set) var sourceStatusText = "尚未扫描 Apple 健康数据来源"
    @Published private(set) var isScanningSources = false

    private let healthStore = HKHealthStore()
    private let sourceSampleLimit = 200

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

        let writeTypes = enabledWriteTypes()
        guard !writeTypes.isEmpty else {
            statusText = "请至少选择一个同步项目"
            return
        }

        healthStore.requestAuthorization(toShare: writeTypes, read: readableBodyTypes()) { [weak self] success, error in
            guard let manager = self else { return }
            let message = success
                ? "已请求 Apple 健康写入权限"
                : (error?.localizedDescription ?? "未获得 Apple 健康权限")
            Task { @MainActor in
                manager.statusText = message
            }
        }
    }

    func requestDataSourceAccess() {
        guard isAvailable else {
            sourceStatusText = "此设备不支持 Apple 健康"
            return
        }

        healthStore.requestAuthorization(toShare: [], read: readableBodyTypes()) { [weak self] success, error in
            guard let manager = self else { return }
            Task { @MainActor in
                if success {
                    manager.refreshDataSources()
                } else {
                    manager.sourceStatusText = error?.localizedDescription ?? "未获得 Apple 健康读取权限"
                }
            }
        }
    }

    func refreshDataSources() {
        guard isAvailable, !isScanningSources else { return }

        isScanningSources = true
        sourceStatusText = "正在检查最近一年的身体测量记录…"

        Task { [weak self] in
            guard let manager = self else { return }
            do {
                var summaries: [String: HealthDataSourceSummary] = [:]

                for metric in HealthBodyMetric.allCases {
                    guard let type = HKQuantityType.quantityType(forIdentifier: metric.typeIdentifier) else {
                        continue
                    }
                    let samples = try await manager.recentSamples(for: type)
                    for sample in samples {
                        let source = sample.sourceRevision.source
                        let bundleIdentifier = source.bundleIdentifier
                        let key = bundleIdentifier
                        let currentBundleIdentifier = Bundle.main.bundleIdentifier

                        if var existing = summaries[key] {
                            existing.metrics.insert(metric)
                            existing.latestDate = max(existing.latestDate, sample.endDate)
                            existing.sampleCount += 1
                            summaries[key] = existing
                        } else {
                            summaries[key] = HealthDataSourceSummary(
                                id: key,
                                name: source.name,
                                bundleIdentifier: bundleIdentifier,
                                providerName: Self.providerName(
                                    sourceName: source.name,
                                    bundleIdentifier: bundleIdentifier
                                ),
                                isCurrentApp: bundleIdentifier == currentBundleIdentifier,
                                metrics: [metric],
                                latestDate: sample.endDate,
                                sampleCount: 1
                            )
                        }
                    }
                }

                manager.sourceSummaries = summaries.values.sorted {
                    if $0.isCurrentApp != $1.isCurrentApp {
                        return $0.isCurrentApp
                    }
                    return $0.latestDate > $1.latestDate
                }
                manager.sourceStatusText = manager.sourceSummaries.isEmpty
                    ? "没有读到记录。请在“健康”中确认已允许本 App 读取身体测量数据。"
                    : "发现 \(manager.sourceSummaries.count) 个数据来源"
            } catch {
                manager.sourceSummaries = []
                manager.sourceStatusText = "读取失败：\(error.localizedDescription)"
            }
            manager.isScanningSources = false
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

    private func readableBodyTypes() -> Set<HKObjectType> {
        Set(HealthBodyMetric.allCases.compactMap {
            HKQuantityType.quantityType(forIdentifier: $0.typeIdentifier)
        })
    }

    private func recentSamples(for type: HKQuantityType) async throws -> [HKQuantitySample] {
        let startDate = Calendar.current.date(byAdding: .year, value: -1, to: .now)
        let predicate = HKQuery.predicateForSamples(
            withStart: startDate,
            end: .now,
            options: .strictEndDate
        )
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: type,
                predicate: predicate,
                limit: sourceSampleLimit,
                sortDescriptors: [sort]
            ) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                continuation.resume(returning: samples as? [HKQuantitySample] ?? [])
            }
            healthStore.execute(query)
        }
    }

    private static func providerName(sourceName: String, bundleIdentifier: String) -> String {
        let value = "\(sourceName) \(bundleIdentifier)".lowercased()
        let providers: [(needles: [String], name: String)] = [
            (["huawei"], "华为"),
            (["xiaomi", "mijia", "mi home"], "小米"),
            (["withings", "health mate"], "Withings"),
            (["garmin"], "Garmin"),
            (["renpho"], "RENPHO"),
            (["eufy"], "Eufy"),
            (["inbody"], "InBody"),
            (["omron"], "欧姆龙"),
            (["fitbit", "google health"], "Fitbit / Google"),
            (["fitdays"], "Fitdays"),
            (["okok"], "OKOK"),
            (["feelfit"], "Feelfit"),
            (["ailink"], "AiLink")
        ]

        return providers.first(where: { provider in
            provider.needles.contains(where: value.contains)
        })?.name ?? sourceName
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
