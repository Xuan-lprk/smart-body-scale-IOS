import SwiftUI

struct HistoryView: View {
    @EnvironmentObject private var scale: ScaleManager
    @EnvironmentObject private var comparisonStore: ComparisonStore
    @State private var deletionError: String?

    var body: some View {
        NavigationStack {
            List {
                if scale.history.isEmpty { EmptyStateView(title: "还没有测量记录", icon: "calendar.badge.clock", message: "完成首次测量后，记录将保存在这里。") }
                ForEach(scale.history) { item in
                    NavigationLink(destination: MeasurementDetailView(measurement: item)) {
                        HStack {
                            VStack(alignment: .leading) {
                                Text(item.memberName ?? "本人").fontWeight(.semibold)
                                Text(item.date, format: .dateTime.year().month().day().hour().minute())
                                Text("BMI \(item.bmi, specifier: "%.2f") · 体脂 \(item.bodyFat, specifier: "%.1f")%")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                HStack(spacing: 8) {
                                    if item.hasDualADC {
                                        Label("双 ADC", systemImage: "arrow.left.arrow.right")
                                    }
                                    if comparisonStore.reference(for: item.id) != nil {
                                        Label("已对照阿福", systemImage: "checkmark.seal")
                                    }
                                }
                                .font(.caption2)
                                .foregroundStyle(.teal)
                            }
                            Spacer()
                            Text("\(item.weight, specifier: "%.2f") kg")
                                .fontWeight(.semibold)
                        }
                    }
                }.onDelete { offsets in
                    let measurements = offsets.compactMap { index in
                        scale.history.indices.contains(index) ? scale.history[index] : nil
                    }
                    Task {
                        for measurement in measurements {
                            if let error = await scale.deleteMeasurement(measurement) {
                                deletionError = error
                                break
                            }
                        }
                    }
                }
            }
            .navigationTitle("测量历史")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        ADCComparisonView()
                    } label: {
                        Label("ADC 对比", systemImage: "arrow.left.arrow.right")
                    }
                }
            }
            .alert(
                "删除失败",
                isPresented: Binding(
                    get: { deletionError != nil },
                    set: { if !$0 { deletionError = nil } }
                )
            ) {
                Button("知道了", role: .cancel) {
                    deletionError = nil
                }
            } message: {
                Text(deletionError ?? "")
            }
        }
    }
}

struct MeasurementDetailView: View {
    @EnvironmentObject private var scale: ScaleManager
    @EnvironmentObject private var profile: UserProfile
    @EnvironmentObject private var comparisonStore: ComparisonStore
    let measurement: BodyMeasurement

    private var comparison: ADCComparison? {
        guard let reference = comparisonStore.reference(for: measurement.id) else { return nil }
        return comparisonStore.comparison(
            for: reference,
            history: scale.history,
            fallbackMember: profile.primaryMember
        )
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
            // Combined Header, Weight, BMI, and Impedance Card
            VStack(spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(measurement.memberName ?? "本人")
                            .font(.title3)
                            .fontWeight(.bold)
                        Text(measurement.date, format: .dateTime.year().month().day().hour().minute())
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if measurement.impedance > 0 {
                        Label(
                            measurement.adcIndex.map { "ADC \($0 + 1) · \(Int(measurement.impedance)) Ω" }
                                ?? "\(Int(measurement.impedance)) Ω",
                            systemImage: "bolt.heart"
                        )
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(.teal)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(.teal.opacity(0.12), in: Capsule())
                    }
                }
                
                Divider().padding(.vertical, 2)
                
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("测量体重").font(.caption).foregroundStyle(.secondary)
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text(String(format: "%.2f", measurement.weight))
                                .font(.system(size: 34, weight: .bold, design: .rounded))
                            Text("kg").font(.subheadline).fontWeight(.semibold)
                        }
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("身体质量指数").font(.caption).foregroundStyle(.secondary)
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text(String(format: "%.2f", measurement.bmi))
                                .font(.system(size: 34, weight: .bold, design: .rounded))
                            Text("BMI").font(.subheadline).fontWeight(.semibold)
                        }
                    }
                }
            }
            .padding()
            .background(LinearGradient(colors: [.teal.opacity(0.15), .mint.opacity(0.05)], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 20))

            if let impedances = measurement.normalizedImpedances, impedances.count >= 2 {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("双 ADC 原始档案")
                            .font(.headline)
                        Spacer()
                        Text(measurement.algorithmVersion ?? "旧算法")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        ADCValueTile(
                            title: "ADC 1",
                            raw: measurement.rawADCs?.first,
                            impedance: impedances[0],
                            selected: measurement.adcIndex == 0
                        )
                        ADCValueTile(
                            title: "ADC 2",
                            raw: measurement.rawADCs.flatMap { $0.count > 1 ? $0[1] : nil },
                            impedance: impedances[1],
                            selected: measurement.adcIndex == 1
                        )
                    }
                    if let comparison {
                        NavigationLink {
                            ADCComparisonDetailView(comparison: comparison)
                        } label: {
                            Label("查看这次与阿福的详细对比", systemImage: "chart.bar.xaxis")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.teal)
                    } else {
                        Text("可在“ADC 对比”中导入同一次阿福结果。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding()
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18))
            } else {
                Text("这是一条旧记录，只保存了当时选中的 ADC，无法还原另一条进行公平对比。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 14))
            }
            
            // Grid of metrics (compact)
            VStack(alignment: .leading, spacing: 8) {
                Text("身体指标详情").font(.headline).foregroundStyle(.secondary).padding(.leading, 4)
                
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    MetricTile(title: "体脂率/量", valueString: String(format: "%.1f%% / %.1f kg", measurement.bodyFat, measurement.bodyFatMass), icon: "drop.fill")
                    MetricTile(title: "肌肉率/量", valueString: String(format: "%.1f%% / %.1f kg", measurement.musclePercent, measurement.muscle), icon: "figure.strengthtraining.traditional")
                    MetricTile(title: "骨骼肌率/量", valueString: String(format: "%.1f%% / %.1f kg", measurement.skeletalMusclePercent, measurement.skeletalMuscleMass), icon: "figure.core.training")
                    MetricTile(title: "体水分率/量", valueString: String(format: "%.1f%% / %.1f kg", measurement.water, measurement.waterMass), icon: "water.waves")
                    MetricTile(title: "蛋白质率/量", valueString: String(format: "%.1f%% / %.1f kg", measurement.protein, measurement.proteinMass), icon: "leaf.fill")
                    MetricTile(title: "骨量率/量", valueString: String(format: "%.1f%% / %.1f kg", measurement.boneMassPercent, measurement.boneMass), icon: "shield.fill")
                    MetricTile(title: "皮下脂肪率/量", valueString: String(format: "%.1f%% / %.1f kg", measurement.subcutaneousFatPercent, measurement.subcutaneousFatMass), icon: "drop.triangle.fill")
                }
            }
            }
        }
        .padding()
        .navigationTitle("测量详情")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct ADCValueTile: View {
    let title: String
    let raw: Double?
    let impedance: Double
    let selected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title).fontWeight(.semibold)
                if selected {
                    Text("当时采用")
                        .font(.caption2)
                        .foregroundStyle(.teal)
                }
            }
            Text("\(impedance, specifier: "%.0f") Ω")
                .font(.title3)
                .fontWeight(.bold)
            if let raw {
                Text("原始值 \(raw, specifier: "%.0f")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            selected ? Color.teal.opacity(0.12) : Color.secondary.opacity(0.08),
            in: RoundedRectangle(cornerRadius: 14)
        )
    }
}
