import SwiftUI

struct HistoryView: View {
    @EnvironmentObject private var scale: ScaleManager
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
                            }
                            Spacer()
                            Text("\(item.weight, specifier: "%.2f") kg")
                                .fontWeight(.semibold)
                        }
                    }
                }.onDelete { scale.removeHistory(at: $0) }
            }.navigationTitle("测量历史")
        }
    }
}

struct MeasurementDetailView: View {
    let measurement: BodyMeasurement
    
    var body: some View {
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
            Spacer()
        }
        .padding()
        .navigationTitle("测量详情")
        .navigationBarTitleDisplayMode(.inline)
    }
}
