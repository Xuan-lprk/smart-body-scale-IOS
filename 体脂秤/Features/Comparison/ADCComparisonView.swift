import SwiftUI
import PhotosUI

struct ADCComparisonView: View {
    @EnvironmentObject private var scale: ScaleManager
    @EnvironmentObject private var profile: UserProfile
    @EnvironmentObject private var comparisonStore: ComparisonStore
    @State private var showingImporter = false

    private var comparisons: [ADCComparison] {
        comparisonStore.comparisons(
            history: scale.history,
            fallbackMember: profile.primaryMember
        )
    }

    private var summary: ComparisonSummary {
        comparisonStore.summary(for: comparisons)
    }

    var body: some View {
        List {
            Section {
                Text("把同一次称重的阿福结果与本 App 的 ADC 1、ADC 2 分别计算后对照。阿福结果只是厂商参考，不代表医学真实值。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Section("对照概况") {
                LabeledContent("已导入", value: "\(summary.totalCount) 次")
                LabeledContent("合格对照", value: "\(summary.qualifiedCount) 次")
                LabeledContent("合格日期", value: "\(summary.distinctQualifiedDates) 天")
                Text(summary.recommendation)
                    .font(.callout)
                    .foregroundStyle(.teal)
            }

            if let adc1 = summary.adc1, let adc2 = summary.adc2 {
                Section("体脂误差统计（本地 − 阿福）") {
                    StatisticsRow(title: "ADC 1", statistics: adc1)
                    StatisticsRow(title: "ADC 2", statistics: adc2)
                }
            }

            Section {
                if comparisons.isEmpty {
                    ContentUnavailableView(
                        "还没有可用对照",
                        systemImage: "arrow.left.arrow.right",
                        description: Text("请先完成一次保存了双 ADC 的新测量，再导入同一次的阿福结果。")
                    )
                } else {
                    ForEach(comparisons) { comparison in
                        NavigationLink {
                            ADCComparisonDetailView(comparison: comparison)
                        } label: {
                            ComparisonRow(comparison: comparison)
                        }
                        .swipeActions {
                            Button(role: .destructive) {
                                comparisonStore.remove(comparison.reference)
                            } label: {
                                Label("删除参考", systemImage: "trash")
                            }
                        }
                    }
                }
            } header: {
                Text("逐次对照")
            } footer: {
                let unavailableCount = summary.totalCount - comparisons.count
                if unavailableCount > 0 {
                    Text("另有 \(unavailableCount) 条参考因本地记录被删除或旧记录未保存双 ADC，暂时无法计算。")
                }
            }
        }
        .navigationTitle("ADC 对比")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingImporter = true
                } label: {
                    Label("导入阿福数据", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $showingImporter) {
            NavigationStack {
                OfficialReferenceImportView()
            }
        }
    }
}

private struct StatisticsRow: View {
    let title: String
    let statistics: ADCErrorStatistics

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title).fontWeight(.semibold)
                Spacer()
                Text("MAE \(statistics.mae, specifier: "%.2f") 个百分点")
                    .foregroundStyle(.teal)
            }
            Text(verbatim: String(
                format: "平均偏差 %@ · 中位偏差 %@ · RMSE %.2f",
                signed(statistics.meanBias),
                signed(statistics.medianBias),
                statistics.rmse
            ))
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 3)
    }

    private func signed(_ value: Double) -> String {
        String(format: "%+.2f", value)
    }
}

private struct ComparisonRow: View {
    let comparison: ADCComparison

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(comparison.reference.measuredAt, format: .dateTime.year().month().day().hour().minute())
                    .fontWeight(.semibold)
                Spacer()
                Label(
                    comparison.isQualified ? "合格" : "仅保存",
                    systemImage: comparison.isQualified ? "checkmark.circle.fill" : "exclamationmark.circle.fill"
                )
                .font(.caption)
                .foregroundStyle(comparison.isQualified ? .green : .orange)
            }
            Text(verbatim: String(
                format: "阿福 %.1f%% · ADC 1 %.1f%% · ADC 2 %.1f%%",
                comparison.reference.bodyFat,
                comparison.adc1Measurement.bodyFat,
                comparison.adc2Measurement.bodyFat
            ))
            .font(.callout)
            Text(verbatim: String(
                format: "差值：ADC 1 %@ · ADC 2 %@ 个百分点",
                signed(comparison.adc1Error),
                signed(comparison.adc2Error)
            ))
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 3)
    }

    private func signed(_ value: Double) -> String {
        String(format: "%+.1f", value)
    }
}

struct ADCComparisonDetailView: View {
    let comparison: ADCComparison

    var body: some View {
        List {
            Section("对照条件") {
                LabeledContent("本地测量") {
                    Text("\(comparison.measurement.weight, specifier: "%.2f") kg")
                }
                LabeledContent("阿福参考") {
                    Text("\(comparison.reference.weight, specifier: "%.2f") kg")
                }
                LabeledContent("体重差") {
                    Text("\(comparison.weightDifference, specifier: "%.2f") kg")
                }
                LabeledContent("时间差") {
                    Text("\(comparison.timeDifferenceMinutes, specifier: "%.1f") 分钟")
                }
                Label(
                    comparison.qualityReason,
                    systemImage: comparison.isQualified ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
                )
                .foregroundStyle(comparison.isQualified ? .green : .orange)
            }

            Section("双 ADC") {
                ComparisonMetricRow(
                    title: "体脂率",
                    official: comparison.reference.bodyFat,
                    adc1: comparison.adc1Measurement.bodyFat,
                    adc2: comparison.adc2Measurement.bodyFat,
                    unit: "%"
                )
                LabeledContent("换算阻抗") {
                    Text(verbatim: String(
                        format: "ADC 1 %.0f Ω · ADC 2 %.0f Ω",
                        comparison.adc1Measurement.impedance,
                        comparison.adc2Measurement.impedance
                    ))
                }
            }

            Section("阿福扩展指标") {
                optionalMetric(
                    title: "肌肉率",
                    official: comparison.reference.musclePercent,
                    adc1: comparison.adc1Measurement.musclePercent,
                    adc2: comparison.adc2Measurement.musclePercent,
                    unit: "%"
                )
                optionalMetric(
                    title: "体水分率",
                    official: comparison.reference.waterPercent,
                    adc1: comparison.adc1Measurement.water,
                    adc2: comparison.adc2Measurement.water,
                    unit: "%"
                )
                optionalMetric(
                    title: "蛋白质率",
                    official: comparison.reference.proteinPercent,
                    adc1: comparison.adc1Measurement.protein,
                    adc2: comparison.adc2Measurement.protein,
                    unit: "%"
                )
                optionalMetric(
                    title: "骨量",
                    official: comparison.reference.boneMass,
                    adc1: comparison.adc1Measurement.boneMass,
                    adc2: comparison.adc2Measurement.boneMass,
                    unit: "kg"
                )
                optionalMetric(
                    title: "骨骼肌率",
                    official: comparison.reference.skeletalMusclePercent,
                    adc1: comparison.adc1Measurement.skeletalMusclePercent,
                    adc2: comparison.adc2Measurement.skeletalMusclePercent,
                    unit: "%"
                )
                optionalMetric(
                    title: "皮下脂肪率",
                    official: comparison.reference.subcutaneousFatPercent,
                    adc1: comparison.adc1Measurement.subcutaneousFatPercent,
                    adc2: comparison.adc2Measurement.subcutaneousFatPercent,
                    unit: "%"
                )
                if let visceralFat = comparison.reference.visceralFat {
                    LabeledContent("内脏脂肪") {
                        Text("阿福 \(visceralFat, specifier: "%.1f")")
                    }
                }
            }

            Section {
                Text("本地水分、肌肉、蛋白质、骨量等由体脂按固定关系粗略推算；这里展示差异是为了审计算法，不代表这些项目由秤独立测得。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("单次对照")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func optionalMetric(
        title: String,
        official: Double?,
        adc1: Double,
        adc2: Double,
        unit: String
    ) -> some View {
        if let official {
            ComparisonMetricRow(
                title: title,
                official: official,
                adc1: adc1,
                adc2: adc2,
                unit: unit
            )
        }
    }
}

private struct ComparisonMetricRow: View {
    let title: String
    let official: Double
    let adc1: Double
    let adc2: Double
    let unit: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).fontWeight(.semibold)
            HStack {
                value("阿福", official, color: .primary)
                Spacer()
                value("ADC 1", adc1, color: .teal)
                Spacer()
                value("ADC 2", adc2, color: .blue)
            }
        }
        .padding(.vertical, 3)
    }

    private func value(_ label: String, _ value: Double, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption2).foregroundStyle(.secondary)
            Text("\(value, specifier: "%.1f")\(unit)")
                .font(.callout)
                .fontWeight(.medium)
                .foregroundStyle(color)
        }
    }
}

struct OfficialReferenceImportView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var scale: ScaleManager
    @EnvironmentObject private var comparisonStore: ComparisonStore

    @State private var selectedPhotos: [PhotosPickerItem] = []
    @State private var selectedMeasurementID: UUID?
    @State private var measuredAt = Date()
    @State private var officialWeight: Double?
    @State private var bodyFat: Double?
    @State private var waterPercent: Double?
    @State private var musclePercent: Double?
    @State private var proteinPercent: Double?
    @State private var boneMass: Double?
    @State private var skeletalMusclePercent: Double?
    @State private var subcutaneousFatPercent: Double?
    @State private var visceralFat: Double?
    @State private var note = ""
    @State private var isReadingScreenshots = false
    @State private var ocrStatus: String?
    @State private var usedOCR = false

    private var eligibleMeasurements: [BodyMeasurement] {
        scale.history.filter(\.hasDualADC)
    }

    private var selectedMeasurement: BodyMeasurement? {
        eligibleMeasurements.first { $0.id == selectedMeasurementID }
    }

    var body: some View {
        Form {
            Section {
                PhotosPicker(
                    selection: $selectedPhotos,
                    maxSelectionCount: 4,
                    matching: .images
                ) {
                    Label("选择阿福截图（可多选）", systemImage: "photo.on.rectangle.angled")
                }
                if isReadingScreenshots {
                    HStack {
                        ProgressView()
                        Text("正在本机识别截图…")
                    }
                }
                if let ocrStatus {
                    Text(ocrStatus)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("截图识别")
            } footer: {
                Text("使用系统图片选择器和 Vision 在设备本地识别，不上传图片。OCR 只负责填表，保存前请逐项核对。")
            }

            Section("对应的本地称重") {
                if eligibleMeasurements.isEmpty {
                    Text("没有保存双 ADC 的新测量。请先用本 App 重新称一次。")
                        .foregroundStyle(.orange)
                } else {
                    Picker("本地记录", selection: $selectedMeasurementID) {
                        Text("请选择").tag(UUID?.none)
                        ForEach(eligibleMeasurements) { measurement in
                            Text(verbatim: measurementLabel(measurement))
                            .tag(Optional(measurement.id))
                        }
                    }
                }
            }

            Section("阿福必填数据") {
                DatePicker("测量时间", selection: $measuredAt)
                TextField("体重（kg）", value: $officialWeight, format: .number)
                    .keyboardType(.decimalPad)
                TextField("体脂率（%）", value: $bodyFat, format: .number)
                    .keyboardType(.decimalPad)
            }

            Section("阿福可选数据") {
                optionalNumberField("肌肉率（%）", value: $musclePercent)
                optionalNumberField("体水分率（%）", value: $waterPercent)
                optionalNumberField("蛋白质率（%）", value: $proteinPercent)
                optionalNumberField("骨量（kg）", value: $boneMass)
                optionalNumberField("骨骼肌率（%）", value: $skeletalMusclePercent)
                optionalNumberField("皮下脂肪率（%）", value: $subcutaneousFatPercent)
                optionalNumberField("内脏脂肪", value: $visceralFat)
                TextField("备注（可选）", text: $note, axis: .vertical)
            }

            if let selectedMeasurement, let officialWeight {
                Section("对照质量预览") {
                    let weightDifference = abs(selectedMeasurement.weight - officialWeight)
                    let minutes = abs(selectedMeasurement.date.timeIntervalSince(measuredAt)) / 60
                    LabeledContent("体重差", value: String(format: "%.2f kg", weightDifference))
                    LabeledContent("时间差", value: String(format: "%.1f 分钟", minutes))
                    Label(
                        weightDifference <= 0.2 && minutes <= 30
                            ? "将作为合格样本参与统计"
                            : "仍会保存，但不参与 ADC 推荐",
                        systemImage: weightDifference <= 0.2 && minutes <= 30
                            ? "checkmark.circle.fill"
                            : "exclamationmark.triangle.fill"
                    )
                    .foregroundStyle(
                        weightDifference <= 0.2 && minutes <= 30 ? .green : .orange
                    )
                }
            }
        }
        .navigationTitle("导入阿福结果")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("取消") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("保存") { save() }
                    .disabled(!canSave)
            }
        }
        .onAppear {
            if let latest = eligibleMeasurements.first {
                selectedMeasurementID = latest.id
                measuredAt = latest.date
                officialWeight = latest.weight
            }
        }
        .onChange(of: selectedPhotos) { _, items in
            guard !items.isEmpty else { return }
            Task { await importScreenshots(items) }
        }
    }

    @ViewBuilder
    private func optionalNumberField(
        _ title: String,
        value: Binding<Double?>
    ) -> some View {
        TextField(title, value: value, format: .number)
            .keyboardType(.decimalPad)
    }

    private var canSave: Bool {
        selectedMeasurementID != nil
            && officialWeight.map { (1...500).contains($0) } == true
            && bodyFat.map { (0...100).contains($0) } == true
            && validPercent(musclePercent)
            && validPercent(waterPercent)
            && validPercent(proteinPercent)
            && validPercent(skeletalMusclePercent)
            && validPercent(subcutaneousFatPercent)
            && boneMass.map { (0...20).contains($0) } != false
            && visceralFat.map { (0...100).contains($0) } != false
    }

    private func validPercent(_ value: Double?) -> Bool {
        value.map { (0...100).contains($0) } != false
    }

    private func importScreenshots(_ items: [PhotosPickerItem]) async {
        isReadingScreenshots = true
        ocrStatus = nil
        var allLines: [String] = []
        var failedImageCount = 0
        for item in items {
            do {
                guard let data = try await item.loadTransferable(type: Data.self) else {
                    failedImageCount += 1
                    continue
                }
                let lines = try await Task.detached(priority: .userInitiated) {
                    try ReferenceOCRParser.recognizeText(in: data)
                }.value
                allLines.append(contentsOf: lines)
            } catch {
                failedImageCount += 1
            }
        }
        guard !allLines.isEmpty else {
            ocrStatus = "没有从所选图片读到文字，仍可手动填写。"
            isReadingScreenshots = false
            return
        }
        let draft = ReferenceOCRParser.parse(lines: allLines)
        apply(draft)
        usedOCR = true
        let found = [
            draft.weight != nil,
            draft.bodyFat != nil,
            draft.waterPercent != nil,
            draft.musclePercent != nil,
            draft.boneMass != nil
        ].filter { $0 }.count
        let failureSuffix = failedImageCount > 0
            ? "；有 \(failedImageCount) 张图片识别失败，可重新选择"
            : ""
        ocrStatus = "已识别并填入 \(found) 个主要字段\(failureSuffix)，请核对小数和测量时间。"
        isReadingScreenshots = false
    }

    private func apply(_ draft: OfficialReferenceDraft) {
        measuredAt = draft.measuredAt ?? measuredAt
        officialWeight = draft.weight ?? officialWeight
        bodyFat = draft.bodyFat ?? bodyFat
        waterPercent = draft.waterPercent ?? waterPercent
        musclePercent = draft.musclePercent ?? musclePercent
        proteinPercent = draft.proteinPercent ?? proteinPercent
        boneMass = draft.boneMass ?? boneMass
        skeletalMusclePercent = draft.skeletalMusclePercent ?? skeletalMusclePercent
        subcutaneousFatPercent = draft.subcutaneousFatPercent ?? subcutaneousFatPercent
        visceralFat = draft.visceralFat ?? visceralFat

        if let bestMatch = bestMeasurement(weight: officialWeight, date: measuredAt) {
            selectedMeasurementID = bestMatch.id
        }
    }

    private func bestMeasurement(weight: Double?, date: Date) -> BodyMeasurement? {
        eligibleMeasurements.min { lhs, rhs in
            matchScore(lhs, weight: weight, date: date) < matchScore(rhs, weight: weight, date: date)
        }
    }

    private func measurementLabel(_ measurement: BodyMeasurement) -> String {
        String(
            format: "%@ · %.2f kg",
            measurement.date.formatted(date: .numeric, time: .shortened),
            measurement.weight
        )
    }

    private func matchScore(
        _ measurement: BodyMeasurement,
        weight: Double?,
        date: Date
    ) -> Double {
        let minutes = abs(measurement.date.timeIntervalSince(date)) / 60
        let weightPenalty = weight.map { abs(measurement.weight - $0) * 100 } ?? 0
        return minutes + weightPenalty
    }

    private func save() {
        guard let selectedMeasurementID,
              let officialWeight,
              let bodyFat else {
            return
        }
        comparisonStore.upsert(OfficialReferenceRecord(
            id: UUID(),
            measurementID: selectedMeasurementID,
            measuredAt: measuredAt,
            importedAt: .now,
            referenceType: .officialApp,
            importMethod: usedOCR ? .screenshotOCR : .manual,
            weight: officialWeight,
            bodyFat: bodyFat,
            waterPercent: waterPercent,
            musclePercent: musclePercent,
            proteinPercent: proteinPercent,
            boneMass: boneMass,
            skeletalMusclePercent: skeletalMusclePercent,
            subcutaneousFatPercent: subcutaneousFatPercent,
            visceralFat: visceralFat,
            note: note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : note
        ))
        dismiss()
    }
}
