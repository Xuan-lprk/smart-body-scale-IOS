import SwiftUI
import Foundation

struct ProfileView: View {
    @EnvironmentObject private var profile: UserProfile
    @EnvironmentObject private var scale: ScaleManager
    @EnvironmentObject private var healthKit: HealthKitManager
    @AppStorage(HealthKitManager.enabledKey) private var healthSyncEnabled = false
    @AppStorage(HealthKitManager.weightKey) private var syncWeight = true
    @AppStorage(HealthKitManager.bmiKey) private var syncBMI = true
    @AppStorage(HealthKitManager.bodyFatKey) private var syncBodyFat = true
    @AppStorage(HealthKitManager.leanBodyMassKey) private var syncLeanBodyMass = true
    @AppStorage(ImpedanceADCChoice.storageKey) private var selectedADCIndex = ImpedanceADCChoice.first.rawValue
    @State private var showingAddMember = false
    var body: some View {
        NavigationStack { Form {
            Section("我的设备") {
                HStack { Image(systemName: "scalemass").foregroundStyle(.teal); VStack(alignment: .leading) { Text(scale.deviceName ?? "AFU Welland 体脂秤"); Text(scale.connectionState.title).font(.caption).foregroundStyle(.secondary) }; Spacer(); Circle().fill(scale.connectionState.color).frame(width: 9, height: 9) }
                Button { scale.startScan() } label: { Label("重新连接", systemImage: "arrow.clockwise") }
                Button(role: .destructive) { scale.forgetPairedScale() } label: { Label("更换体脂秤", systemImage: "arrow.triangle.2.circlepath") }
            }
            Section("个人资料") { Picker("性别", selection: $profile.sex) { Text("女").tag(Sex.female); Text("男").tag(Sex.male) }; DatePicker("出生日期", selection: $profile.birthDate, displayedComponents: .date); Stepper("身高 \(Int(profile.height)) cm", value: $profile.height, in: 100...230) }
            Section {
                Picker("用于体脂计算", selection: $selectedADCIndex) {
                    Text("ADC 1").tag(ImpedanceADCChoice.first.rawValue)
                    Text("ADC 2").tag(ImpedanceADCChoice.second.rawValue)
                }
                .pickerStyle(.segmented)
            } header: {
                Text("阻抗选择")
            } footer: {
                Text("秤每次会发送两个 ADC，其物理含义尚未确认。所选 ADC 会影响阻抗、体脂及由体脂推算的身体指标，但不影响体重、BMI 和骨量。若希望结果更接近蚂蚁阿福，可选择对照差值较小的；更接近官方结果不代表医学上更准确。选择仅影响之后的新测量，不会改写历史记录。")
            }
            Section {
                Toggle("自动写入 Apple 健康", isOn: $healthSyncEnabled)
                    .onChange(of: healthSyncEnabled) { enabled in
                        if enabled {
                            healthKit.requestAuthorization()
                        } else {
                            healthKit.refreshStatus()
                        }
                    }
                Toggle("体重（秤直接测量）", isOn: $syncWeight)
                    .disabled(!healthSyncEnabled)
                Toggle("BMI（计算值）", isOn: $syncBMI)
                    .disabled(!healthSyncEnabled)
                Toggle("体脂率（BIA 估算）", isOn: $syncBodyFat)
                    .disabled(!healthSyncEnabled)
                Toggle("去脂体重（由体脂计算）", isOn: $syncLeanBodyMass)
                    .disabled(!healthSyncEnabled)
                Button("检查或重新申请权限") {
                    healthKit.requestAuthorization()
                }
                .disabled(!healthSyncEnabled)
                Label(healthKit.statusText, systemImage: "heart.text.square")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let lastSyncText = healthKit.lastSyncText {
                    Text(lastSyncText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Apple 健康")
            } footer: {
                Text("只自动同步归属于“本人”的实时测量。体重为直接测量；BMI、体脂率和去脂体重包含公式估算。历史包和家庭成员不会自动写入。")
            }
            .onChange(of: syncWeight) { _ in refreshHealthAuthorization() }
            .onChange(of: syncBMI) { _ in refreshHealthAuthorization() }
            .onChange(of: syncBodyFat) { _ in refreshHealthAuthorization() }
            .onChange(of: syncLeanBodyMass) { _ in refreshHealthAuthorization() }
            Section {
                ForEach(profile.members) { member in
                    HStack { Image(systemName: "person.crop.circle").foregroundStyle(.teal); Text(member.name); Spacer(); Text(member.sex == .female ? "女" : "男").font(.caption).foregroundStyle(.secondary) }
                }
                .onDelete { profile.removeMembers(at: $0) }
                Button { showingAddMember = true } label: { Label("添加家庭成员", systemImage: "person.badge.plus") }
            } header: {
                Text("家庭成员")
            } footer: {
                Text("测量完成后会按成员近期体重和参考体重自动归属记录。")
            }
            Section("说明") { Text("所有测量记录仅保存在本机。体脂率为健康参考数据，不替代医疗诊断。") }
            Section("调试日志") {
                Button("清空日志", role: .destructive) { scale.clearDebugLogs() }
                if scale.debugLogs.isEmpty {
                    Text("暂无日志").font(.caption).foregroundStyle(.secondary)
                } else {
                    ForEach(scale.debugLogs, id: \.self) { log in
                        Text(log)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                    }
                }
            }
        }.navigationTitle("我的资料")
            .sheet(isPresented: $showingAddMember) { AddFamilyMemberView { profile.addMember($0) } }
            .onAppear { healthKit.refreshStatus() }
        }
    }

    private func refreshHealthAuthorization() {
        guard healthSyncEnabled else { return }
        healthKit.requestAuthorization()
    }
}

struct AddFamilyMemberView: View {
    @Environment(\.dismiss) private var dismiss
    let onSave: (FamilyMember) -> Void
    @State private var name = ""
    @State private var sex: Sex = .female
    @State private var height = 165.0
    private let referenceWeight: Double
    @State private var birthDate = Calendar.current.date(byAdding: .year, value: -28, to: .now) ?? .now
    init(referenceWeight: Double? = nil, onSave: @escaping (FamilyMember) -> Void) {
        self.onSave = onSave
        self.referenceWeight = referenceWeight ?? 0
    }
    var body: some View {
        NavigationStack { Form {
            TextField("称呼", text: $name)
            Picker("性别", selection: $sex) { Text("女").tag(Sex.female); Text("男").tag(Sex.male) }
            DatePicker("出生日期", selection: $birthDate, displayedComponents: .date)
            Stepper("身高 \(Int(height)) cm", value: $height, in: 100...230)
        }
        .navigationTitle("添加成员")
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }; ToolbarItem(placement: .confirmationAction) { Button("保存") { onSave(FamilyMember(name: name.isEmpty ? "家庭成员" : name, sex: sex, height: height, birthDate: birthDate, referenceWeight: referenceWeight)); dismiss() }.disabled(name.trimmingCharacters(in: .whitespaces).isEmpty) } }
        }
    }
}
