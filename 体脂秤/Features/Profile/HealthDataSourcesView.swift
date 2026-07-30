import SwiftUI

struct HealthDataSourcesView: View {
    @EnvironmentObject private var healthKit: HealthKitManager

    var body: some View {
        List {
            Section {
                Button {
                    healthKit.requestDataSourceAccess()
                } label: {
                    Label("允许读取并扫描", systemImage: "waveform.path.ecg.rectangle")
                }
                .disabled(healthKit.isScanningSources)

                if healthKit.isScanningSources {
                    HStack {
                        ProgressView()
                        Text(healthKit.sourceStatusText)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Label(
                        healthKit.sourceStatusText,
                        systemImage: healthKit.sourceSummaries.isEmpty
                            ? "info.circle"
                            : "checkmark.circle.fill"
                    )
                    .font(.callout)
                    .foregroundStyle(healthKit.sourceSummaries.isEmpty ? Color.secondary : Color.green)
                }
            } footer: {
                Text("只检查最近一年、每项最多 200 条身体测量记录。来源识别和重复检测均在本机完成，不会上传健康数据。")
            }

            if !healthKit.duplicateWeightGroups.isEmpty {
                Section {
                    ForEach(healthKit.duplicateWeightGroups.prefix(10)) { group in
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Label(
                                    "\(group.averageWeightKilograms, specifier: "%.2f") kg",
                                    systemImage: "exclamationmark.triangle.fill"
                                )
                                .fontWeight(.semibold)
                                .foregroundStyle(.orange)
                                Spacer()
                                Text(group.date, format: .dateTime.month().day().hour().minute())
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Text(group.sourceText)
                                .font(.callout)

                            ForEach(group.samples) { sample in
                                HStack {
                                    Circle()
                                        .fill(.blue.opacity(0.7))
                                        .frame(width: 6, height: 6)
                                    Text(sample.sourceName)
                                        .lineLimit(1)
                                    Spacer()
                                    Text("\(sample.weightKilograms, specifier: "%.2f") kg")
                                    Text(sample.date, format: .dateTime.hour().minute().second())
                                }
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            }

                            Text("时间跨度 \(group.timeSpanMinutes, specifier: "%.1f") 分钟 · 体重范围 \(group.weightSpreadKilograms, specifier: "%.2f") kg")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                        }
                        .padding(.vertical, 4)
                    }
                } header: {
                    Text("可能重复的称重")
                } footer: {
                    Text("判定规则：不同 App 在 5 分钟内写入、体重相差不超过 0.1 kg。这里只提示，不会删除或修改 Apple 健康记录。最多显示最近 10 组。")
                }
            }

            if !healthKit.sourceSummaries.isEmpty {
                Section("最近的数据来源") {
                    ForEach(healthKit.sourceSummaries) { source in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Image(systemName: source.isCurrentApp ? "scalemass.fill" : "app.badge")
                                    .foregroundStyle(source.isCurrentApp ? .teal : .blue)
                                    .frame(width: 24)
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack {
                                        Text(source.name)
                                            .fontWeight(.semibold)
                                        if source.isCurrentApp {
                                            Text("本 App")
                                                .font(.caption2)
                                                .foregroundStyle(.teal)
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 2)
                                                .background(.teal.opacity(0.12), in: Capsule())
                                        }
                                    }
                                    Text(source.providerName)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(source.latestDate, format: .dateTime.month().day())
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Text(source.metricText)
                                .font(.callout)

                            HStack {
                                Text("扫描到 \(source.sampleCount) 条样本")
                                Spacer()
                                Text(source.bundleIdentifier)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                            .font(.caption2.monospaced())
                            .foregroundStyle(.tertiary)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }

            Section {
                ForEach(HealthBodyMetric.allCases, id: \.self) { metric in
                    Label(metric.title, systemImage: icon(for: metric))
                }
            } header: {
                Text("目前可统一管理的指标")
            } footer: {
                Text("水分、肌肉、骨量、内脏脂肪等没有对应的通用 Apple 健康类型，后续会继续保存在 App 本地，并明确标记来源和算法。")
            }
        }
        .navigationTitle("健康数据来源")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable {
            healthKit.refreshDataSources()
        }
    }

    private func icon(for metric: HealthBodyMetric) -> String {
        switch metric {
        case .weight: "scalemass"
        case .bmi: "number"
        case .bodyFat: "percent"
        case .leanBodyMass: "figure.strengthtraining.traditional"
        }
    }
}
