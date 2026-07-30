import SwiftUI

struct DashboardView: View {
    @EnvironmentObject private var scale: ScaleManager
    @EnvironmentObject private var profile: UserProfile

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                weightCard
                
                if let measurement = scale.currentMeasurement {
                    metricGrid(measurement)
                } else {
                    measuringHint
                }
                Spacer()
            }
            .padding()
            .onAppear {
                scale.startScan()
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { scale.startScan() } label: {
                        Image(systemName: "antenna.radiowaves.left.and.right")
                    }
                }
            }
        }
    }

    private var weightCard: some View {
        VStack(spacing: 12) {
            // Status bar inside card
            HStack {
                Label(scale.connectionState.title, systemImage: scale.connectionState.icon)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(scale.connectionState.color)
                Spacer()
                if scale.isMeasuring {
                    ProgressView().tint(.teal)
                } else if scale.normalizedImpedances.count >= 2 {
                    Text(verbatim: String(
                        format: "ADC 1 %.0f Ω · ADC 2 %.0f Ω",
                        scale.normalizedImpedances[0],
                        scale.normalizedImpedances[1]
                    ))
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.teal)
                } else if scale.impedance > 0 {
                    Label(
                        scale.selectedADCIndex.map { "ADC \($0 + 1) · \(Int(scale.impedance)) Ω" }
                            ?? "\(Int(scale.impedance)) Ω",
                        systemImage: "bolt.heart"
                    )
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.teal)
                }
            }
            .padding(.bottom, 2)
            
            Divider()
            
            // Weight display
            VStack(spacing: 4) {
                Text(scale.isStable ? "测量完成" : (scale.liveWeight > 0 ? "正在测量..." : "请赤脚站上体脂秤"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(String(format: "%.2f", scale.liveWeight))
                        .font(.system(size: 48, weight: .bold, design: .rounded))
                    Text("kg").font(.title3).fontWeight(.semibold)
                }
            }
            .padding(.vertical, 4)
        }
        .padding()
        .background(LinearGradient(colors: [.teal.opacity(0.18), .mint.opacity(0.05)], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 22))
    }

    private func metricGrid(_ m: BodyMeasurement) -> some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            MetricTile(title: "BMI", valueString: String(format: "%.2f", m.bmi), icon: "figure.stand")
            MetricTile(title: "体脂率/量", valueString: String(format: "%.1f%% / %.1f kg", m.bodyFat, m.bodyFatMass), icon: "drop.fill")
            MetricTile(title: "肌肉率/量", valueString: String(format: "%.1f%% / %.1f kg", m.musclePercent, m.muscle), icon: "figure.strengthtraining.traditional")
            MetricTile(title: "骨骼肌率/量", valueString: String(format: "%.1f%% / %.1f kg", m.skeletalMusclePercent, m.skeletalMuscleMass), icon: "figure.core.training")
            MetricTile(title: "体水分率/量", valueString: String(format: "%.1f%% / %.1f kg", m.water, m.waterMass), icon: "water.waves")
            MetricTile(title: "蛋白质率/量", valueString: String(format: "%.1f%% / %.1f kg", m.protein, m.proteinMass), icon: "leaf.fill")
            MetricTile(title: "骨量率/量", valueString: String(format: "%.1f%% / %.1f kg", m.boneMassPercent, m.boneMass), icon: "shield.fill")
            MetricTile(title: "皮下脂肪率/量", valueString: String(format: "%.1f%% / %.1f kg", m.subcutaneousFatPercent, m.subcutaneousFatMass), icon: "drop.triangle.fill")
        }
    }

    private var measuringHint: some View {
        EmptyStateView(title: "等待测量数据", icon: "figure.walk", message: "连接体脂秤后，赤脚站稳即可自动计算身体指标。")
            .frame(maxHeight: .infinity)
    }
}
