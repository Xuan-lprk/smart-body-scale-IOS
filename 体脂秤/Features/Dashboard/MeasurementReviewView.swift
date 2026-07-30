import SwiftUI

struct MeasurementReviewView: View {
    @EnvironmentObject private var scale: ScaleManager
    @EnvironmentObject private var profile: UserProfile
    @AppStorage(HealthKitManager.enabledKey) private var healthSyncEnabled = false

    let measurement: BodyMeasurement

    @State private var showingDeleteConfirmation = false
    @State private var isDeleting = false
    @State private var deletionError: String?

    private var member: FamilyMember {
        measurement.profileSnapshot?.member(
            id: measurement.memberID,
            name: measurement.memberName,
            referenceWeight: measurement.weight
        ) ?? profile.primaryMember
    }

    private var adcMeasurements: [BodyMeasurement] {
        guard let impedances = measurement.normalizedImpedances else { return [] }
        return impedances.prefix(2).enumerated().compactMap { index, impedance in
            guard (100.0...1500.0).contains(impedance) else { return nil }
            return BodyAlgorithm.measure(
                date: measurement.date,
                weight: measurement.weight,
                impedance: impedance,
                member: member,
                adcIndex: index
            )
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    VStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 42))
                            .foregroundStyle(.green)
                        Text("测量成功")
                            .font(.title2)
                            .fontWeight(.bold)
                        Text(measurement.date, format: .dateTime.year().month().day().hour().minute())
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    VStack(spacing: 4) {
                        HStack(alignment: .firstTextBaseline, spacing: 5) {
                            Text(measurement.weight, format: .number.precision(.fractionLength(2)))
                                .font(.system(size: 52, weight: .bold, design: .rounded))
                            Text("kg")
                                .font(.title3)
                                .fontWeight(.semibold)
                        }
                        Text("BMI \(measurement.bmi, specifier: "%.2f")")
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(
                        LinearGradient(
                            colors: [.teal.opacity(0.18), .mint.opacity(0.05)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        in: RoundedRectangle(cornerRadius: 22)
                    )

                    if adcMeasurements.count == 2 {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("双 ADC 预览")
                                .font(.headline)
                            HStack(spacing: 10) {
                                ADCReviewCard(
                                    measurement: adcMeasurements[0],
                                    selected: measurement.adcIndex == 0
                                )
                                ADCReviewCard(
                                    measurement: adcMeasurements[1],
                                    selected: measurement.adcIndex == 1
                                )
                            }
                            Text("两路都使用同一次体重和同一份个人资料计算；这里只切换阻抗。")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    LazyVGrid(
                        columns: [GridItem(.flexible()), GridItem(.flexible())],
                        spacing: 10
                    ) {
                        MetricTile(
                            title: "采用的体脂率",
                            valueString: String(format: "%.1f%%", measurement.bodyFat),
                            icon: "drop.fill"
                        )
                        MetricTile(
                            title: "采用的阻抗",
                            valueString: String(format: "%.0f Ω", measurement.impedance),
                            icon: "bolt.heart"
                        )
                        MetricTile(
                            title: "肌肉率",
                            valueString: String(format: "%.1f%%", measurement.musclePercent),
                            icon: "figure.strengthtraining.traditional"
                        )
                        MetricTile(
                            title: "体水分率",
                            valueString: String(format: "%.1f%%", measurement.water),
                            icon: "water.waves"
                        )
                    }

                    VStack(spacing: 10) {
                        Label(
                            healthSyncEnabled
                                ? "本地记录已保存；Apple 健康同步按当前权限执行"
                                : "本次已保存为 App 本地记录",
                            systemImage: healthSyncEnabled ? "heart.text.square" : "internaldrive"
                        )
                        .font(.callout)
                        .foregroundStyle(.secondary)

                        Button {
                            scale.dismissReview(for: measurement.id)
                        } label: {
                            Text("保留本次测量")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.teal)

                        Button(role: .destructive) {
                            showingDeleteConfirmation = true
                        } label: {
                            if isDeleting {
                                ProgressView()
                                    .frame(maxWidth: .infinity)
                            } else {
                                Label("删除本次测量", systemImage: "trash")
                                    .frame(maxWidth: .infinity)
                            }
                        }
                        .buttonStyle(.bordered)
                        .disabled(isDeleting)
                    }
                }
                .padding()
            }
            .navigationTitle("本次结果")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") {
                        scale.dismissReview(for: measurement.id)
                    }
                    .disabled(isDeleting)
                }
            }
            .confirmationDialog(
                "确定删除这次测量？",
                isPresented: $showingDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button("同时删除本地与 Apple 健康数据", role: .destructive) {
                    Task { await deleteMeasurement() }
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("会删除本地记录、对应的阿福对照，以及本 App 为这次测量写入 Apple 健康的关联样本。")
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
            .interactiveDismissDisabled(isDeleting)
        }
    }

    private func deleteMeasurement() async {
        isDeleting = true
        deletionError = await scale.deleteMeasurement(measurement)
        isDeleting = false
    }
}

private struct ADCReviewCard: View {
    let measurement: BodyMeasurement
    let selected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("ADC \((measurement.adcIndex ?? 0) + 1)")
                    .fontWeight(.semibold)
                Spacer()
                if selected {
                    Text("已采用")
                        .font(.caption2)
                        .foregroundStyle(.teal)
                }
            }
            Text("\(measurement.bodyFat, specifier: "%.1f")%")
                .font(.title2)
                .fontWeight(.bold)
            Text("\(measurement.impedance, specifier: "%.0f") Ω")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            selected ? Color.teal.opacity(0.15) : Color.secondary.opacity(0.08),
            in: RoundedRectangle(cornerRadius: 15)
        )
        .overlay {
            if selected {
                RoundedRectangle(cornerRadius: 15)
                    .stroke(Color.teal.opacity(0.5), lineWidth: 1)
            }
        }
    }
}
