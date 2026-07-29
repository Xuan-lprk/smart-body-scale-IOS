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
                Text("只检查最近一年、每项最多 200 条身体测量记录。数据来源分析在本机完成，不会上传健康数据。")
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
