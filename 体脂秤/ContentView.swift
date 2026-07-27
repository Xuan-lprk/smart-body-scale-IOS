import SwiftUI
import Foundation
@preconcurrency import CoreBluetooth
import Combine

@main struct AntAfouScaleApp: App {
    @StateObject private var scale = ScaleManager()
    @StateObject private var profile = UserProfile()
    @StateObject private var healthKit = HealthKitManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(scale)
                .environmentObject(profile)
                .environmentObject(healthKit)
        }
    }
}

struct ContentView: View {
    @EnvironmentObject private var scale: ScaleManager
    @EnvironmentObject private var profile: UserProfile
    @EnvironmentObject private var healthKit: HealthKitManager
    @State private var tab = 0
    @AppStorage("afu.hasPairedScale") private var hasPairedScale = false
    @AppStorage("afu.family.hasPromptedInitial") private var hasPromptedInitial = false
    @State private var showingMemberSheet = false
    @State private var showingInitialPrompt = false
    @State private var showingUnknownMember = false
    @State private var suggestedWeight: Double?

    var body: some View {
        Group {
            if hasPairedScale {
                TabView(selection: $tab) {
                    DashboardView().tabItem { Label("测量", systemImage: "waveform.path.ecg") }.tag(0)
                    HistoryView().tabItem { Label("历史", systemImage: "chart.line.uptrend.xyaxis") }.tag(1)
                    ProfileView().tabItem { Label("我的", systemImage: "person.crop.circle") }.tag(2)
                }
            } else {
                PairingView()
            }
        }
        .tint(.teal)
        .onAppear {
            scale.profile = profile
            scale.healthKit = healthKit
        }
        .onAppear { promptForInitialMemberIfNeeded() }
        .onChange(of: hasPairedScale) { _ in promptForInitialMemberIfNeeded() }
        .onChange(of: scale.unrecognizedWeight) { weight in
            guard let weight else { return }
            suggestedWeight = weight
            showingUnknownMember = true
        }
        .alert("添加家庭成员", isPresented: $showingInitialPrompt) {
            Button("暂不添加", role: .cancel) { hasPromptedInitial = true }
            Button("添加成员") { hasPromptedInitial = true; suggestedWeight = nil; showingMemberSheet = true }
        } message: {
            Text("首次使用时添加家庭成员，之后体脂秤会自动识别并归属测量记录。")
        }
        .alert("可能是新成员", isPresented: $showingUnknownMember) {
            Button("暂不添加", role: .cancel) { scale.clearUnrecognizedWeight() }
            Button("添加成员") { showingMemberSheet = true }
        } message: {
            Text("检测到 \(suggestedWeight ?? 0, specifier: "%.2f") kg 的体重与现有成员差异较大，是否添加新成员？")
        }
        .sheet(isPresented: $showingMemberSheet) {
            AddFamilyMemberView(referenceWeight: suggestedWeight) { member in
                profile.addMember(member)
                scale.assignUnrecognizedMeasurement(to: member)
                scale.clearUnrecognizedWeight()
                hasPromptedInitial = true
            }
        }
    }

    private func promptForInitialMemberIfNeeded() {
        if hasPairedScale && !hasPromptedInitial { showingInitialPrompt = true }
    }
}

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

struct EmptyStateView: View {
    let title: String
    let icon: String
    let message: String
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: icon).font(.system(size: 34)).foregroundStyle(.teal)
            Text(title).font(.headline)
            Text(message).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 32)
    }
}

struct MetricTile: View {
    let title: String; let valueString: String; let icon: String
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon).foregroundStyle(.teal)
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(valueString).font(.headline).fontWeight(.bold)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(15).background(.background, in: RoundedRectangle(cornerRadius: 16)).overlay(RoundedRectangle(cornerRadius: 16).stroke(.teal.opacity(0.12)))
    }
}

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

struct PairingView: View {
    @EnvironmentObject private var scale: ScaleManager
    @AppStorage("afu.hasPairedScale") private var hasPairedScale = false
    
    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(spacing: 12) {
                        Image(systemName: "scalemass").font(.system(size: 48)).foregroundStyle(.teal)
                        Text("连接你的体脂秤").font(.title2).fontWeight(.bold)
                        Text("请打开手机蓝牙，并让体脂秤保持在附近。首次使用需先完成设备连接。")
                            .multilineTextAlignment(.center).font(.subheadline).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 18)
                    .listRowBackground(Color.clear)
                }
                
                Section { Button { scale.startScan() } label: { Label(scale.isScanning ? "正在搜索体脂秤…" : "重新搜索", systemImage: "magnifyingglass") } } footer: { Text("会像 CLI 一样扫描全部蓝牙广播，再筛选名称以 AFU-WL 开头、且符合协议特征的设备。") }
                if !scale.discoveredDevices.isEmpty { Section("发现的设备") { ForEach(scale.discoveredDevices) { d in Button { scale.connect(d) } label: { HStack { VStack(alignment: .leading) { Text(d.name); Text(d.identifier).font(.caption).foregroundStyle(.secondary) }; Spacer(); Text("\(d.rssi) dBm").font(.caption) } } } } }
            }
            .navigationTitle("设备配对")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("跳过") { hasPairedScale = true }
                }
            }
            .task { scale.startScan() }
        }
    }
}

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
                Text("秤每次会发送两个 ADC。其物理含义仍未确认；选择只影响之后的新测量，不会改写历史记录。当前一次官方对照中 ADC 2 更接近阿福结果，但这不代表它一定更准确。")
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

#Preview("主界面") {
    ContentView()
        .environmentObject(ScaleManager())
        .environmentObject(UserProfile())
        .environmentObject(HealthKitManager())
}

enum Sex: String, CaseIterable, Codable { case female, male }

enum ImpedanceADCChoice: Int {
    static let storageKey = "afu.algorithm.adcIndex"
    case first = 0
    case second = 1
}

struct FamilyMember: Identifiable, Codable {
    let id: UUID
    var name: String
    var sex: Sex
    var height: Double
    var birthDate: Date
    var referenceWeight: Double
    init(id: UUID = UUID(), name: String, sex: Sex, height: Double, birthDate: Date, referenceWeight: Double) { self.id = id; self.name = name; self.sex = sex; self.height = height; self.birthDate = birthDate; self.referenceWeight = referenceWeight }
    var age: Int { Calendar.current.dateComponents([.year], from: birthDate, to: .now).year ?? 28 }
}

@MainActor final class UserProfile: ObservableObject {
    @Published var sex: Sex = .female { didSet { savePrimaryProfile() } }
    @Published var height: Double = 165 { didSet { savePrimaryProfile() } }
    @Published var birthDate = Calendar.current.date(byAdding: .year, value: -28, to: .now) ?? .now { didSet { savePrimaryProfile() } }
    @Published var members: [FamilyMember] = []
    var age: Int { Calendar.current.dateComponents([.year], from: birthDate, to: .now).year ?? 28 }
    private let primaryID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    init() {
        if let data = UserDefaults.standard.data(forKey: "afu.primary.profile"),
           let saved = try? JSONDecoder().decode(StoredPrimaryProfile.self, from: data) {
            sex = saved.sex
            height = saved.height
            birthDate = saved.birthDate
        }
        if let data = UserDefaults.standard.data(forKey: "afu.family.members"),
           let saved = try? JSONDecoder().decode([FamilyMember].self, from: data) {
            members = saved
        }
    }
    var primaryMember: FamilyMember { FamilyMember(id: primaryID, name: "本人", sex: sex, height: height, birthDate: birthDate, referenceWeight: 60) }
    func addMember(_ member: FamilyMember) { members.append(member); saveMembers() }
    func removeMembers(at offsets: IndexSet) { members.remove(atOffsets: offsets); saveMembers() }
    func matchedMember(for weight: Double, history: [BodyMeasurement]) -> FamilyMember {
        let candidates = [primaryMember] + members
        let ranked = candidates.map { member -> (FamilyMember, Double) in
            let records = history.filter { $0.memberID == member.id }.prefix(3)
            let reference = records.isEmpty ? member.referenceWeight : records.map(\.weight).reduce(0, +) / Double(records.count)
            return (member, abs(reference - weight))
        }
        return ranked.min(by: { $0.1 < $1.1 })?.0 ?? primaryMember
    }
    func shouldSuggestNewMember(for weight: Double, history: [BodyMeasurement]) -> Bool {
        let candidates = [primaryMember] + members
        let smallestDifference = candidates.map { member -> Double in
            let records = history.filter { $0.memberID == member.id }.prefix(3)
            let reference = records.isEmpty ? member.referenceWeight : records.map(\.weight).reduce(0, +) / Double(records.count)
            return abs(reference - weight)
        }.min() ?? 0
        return smallestDifference > 7
    }
    private func saveMembers() { if let data = try? JSONEncoder().encode(members) { UserDefaults.standard.set(data, forKey: "afu.family.members") } }
    private func savePrimaryProfile() {
        let profile = StoredPrimaryProfile(sex: sex, height: height, birthDate: birthDate)
        if let data = try? JSONEncoder().encode(profile) {
            UserDefaults.standard.set(data, forKey: "afu.primary.profile")
        }
    }

    private struct StoredPrimaryProfile: Codable {
        let sex: Sex
        let height: Double
        let birthDate: Date
    }
}

struct BodyMeasurement: Identifiable, Codable {
    let id: UUID; let date: Date; let weight: Double; let impedance: Double; let bmi: Double; let bodyFat: Double; let muscle: Double; let water: Double; let protein: Double; let boneMass: Double; let memberID: UUID?; let memberName: String?
    var adcIndex: Int? = nil
    
    // Computed Properties for UI to show all required metrics (both percentage and mass)
    var bodyFatMass: Double { weight * (bodyFat / 100.0) }
    var musclePercent: Double { weight > 0 ? (muscle / weight) * 100.0 : 0.0 }
    var skeletalMusclePercent: Double { musclePercent * 0.527 }
    var skeletalMuscleMass: Double { muscle * 0.527 }
    var waterMass: Double { weight * (water / 100.0) }
    var proteinMass: Double { weight * (protein / 100.0) }
    var boneMassPercent: Double { weight > 0 ? (boneMass / weight) * 100.0 : 0.0 }
    var subcutaneousFatPercent: Double { bodyFat * 0.72 }
    var subcutaneousFatMass: Double { weight * (subcutaneousFatPercent / 100.0) }
}

struct DiscoveredScale: Identifiable { let peripheral: CBPeripheral; let name: String; let identifier: String; let rssi: Int; var id: UUID { peripheral.identifier } }

enum ConnectionState: Equatable { case bluetoothOff, idle, scanning, connecting, connected, measuring
    var title: String { switch self { case .bluetoothOff: "蓝牙未开启"; case .idle: "等待连接"; case .scanning: "正在搜索体脂秤"; case .connecting: "正在连接"; case .connected: "已连接，等待上秤"; case .measuring: "正在测量" } }
    var shortTitle: String { self == .connected || self == .measuring ? "已连接" : "未连接" }
    var detail: String { self == .bluetoothOff ? "请在系统设置中开启蓝牙" : "AFU Welland BLE" }
    var icon: String { self == .bluetoothOff ? "bluetooth.slash" : "dot.radiowaves.left.and.right" }
    var color: Color { self == .bluetoothOff ? .red : (self == .connected || self == .measuring ? .green : .orange) }
}

@MainActor final class ScaleManager: NSObject, ObservableObject {
    private static let pairedPeripheralIDKey = "afu.pairedPeripheralID"
    private let serviceUUID = CBUUID(string: "0000FFB0-0000-1000-8000-00805F9B34FB")
    private var central: CBCentralManager!
    private var activePeripheral: CBPeripheral?
    weak var profile: UserProfile?
    weak var healthKit: HealthKitManager?
    @Published var connectionState: ConnectionState = .idle
    @Published var discoveredDevices: [DiscoveredScale] = []
    @Published var liveWeight = 0.0
    @Published var impedance = 0.0
    @Published var selectedADCIndex: Int?
    @Published var currentMeasurement: BodyMeasurement?
    @Published var history: [BodyMeasurement] = []
    @Published var deviceName: String?
    @Published var isScanning = false
    @Published var isMeasuring = false
    @Published var isStable = false
    @Published var unrecognizedWeight: Double?
    @Published var debugLogs: [String] = []
    private var hasSavedMeasurement = false

    func log(_ message: String) {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        let timestamp = formatter.string(from: Date())
        debugLogs.insert("[\(timestamp)] \(message)", at: 0)
        if debugLogs.count > 100 {
            debugLogs.removeLast()
        }
        print("[ScaleManager] \(message)")
    }
    
    func clearDebugLogs() {
        debugLogs = []
    }

    override init() { super.init(); central = CBCentralManager(delegate: self, queue: .main); loadHistory(); log("ScaleManager initialized") }
    func startScan() {
        discoveredDevices = []
        isScanning = true
        guard central.state == .poweredOn else {
            if central.state == .unknown {
                connectionState = .scanning
            } else {
                connectionState = .bluetoothOff
            }
            return
        }
        connectionState = .scanning
        // 与 CLI/Bleak 一致：先接收全部广播，再在 didDiscover 中解析并筛选。
        // 这台秤的 0xAC 协议数据可能放在 0x27AC Service Data 中；
        // 若只按 FFB0 服务扫描，部分 iOS/iPadOS 设备可能收不到完整广播。
        central.scanForPeripherals(
            withServices: nil,
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: true]
        )
    }
    func connect(_ device: DiscoveredScale) {
        guard connectionState != .connecting, activePeripheral == nil else { return }
        central.stopScan()
        isScanning = false
        connectionState = .connecting
        activePeripheral = device.peripheral
        deviceName = device.name
        central.connect(device.peripheral)
    }
    func forgetPairedScale() {
        UserDefaults.standard.set(false, forKey: "afu.hasPairedScale")
        UserDefaults.standard.removeObject(forKey: Self.pairedPeripheralIDKey)
        if let activePeripheral {
            central.cancelPeripheralConnection(activePeripheral)
        } else {
            connectionState = .idle
        }
        deviceName = nil
        discoveredDevices = []
    }
    func removeHistory(at offsets: IndexSet) { history.remove(atOffsets: offsets); saveHistory() }
    private func finishMeasurement() {
        guard liveWeight > 0, let profile else { return }
        guard !hasSavedMeasurement else { return }
        hasSavedMeasurement = true
        let isNewMember = profile.shouldSuggestNewMember(for: liveWeight, history: history)
        let member = profile.matchedMember(for: liveWeight, history: history)
        let measurement = BodyAlgorithm.measure(
            weight: liveWeight,
            impedance: impedance,
            member: member,
            adcIndex: selectedADCIndex
        )
        currentMeasurement = measurement
        history.insert(measurement, at: 0)
        if isNewMember && unrecognizedWeight == nil { unrecognizedWeight = liveWeight }
        saveHistory()
        let isPrimaryMember = member.id == profile.primaryMember.id
        if isPrimaryMember && (!isNewMember || profile.members.isEmpty) {
            healthKit?.save(measurement)
        }
        log("[BLE] Stored stable measurement: weight=\(liveWeight) kg, impedance=\(impedance) Ohm")
    }
    func clearUnrecognizedWeight() { unrecognizedWeight = nil }
    func assignUnrecognizedMeasurement(to member: FamilyMember) {
        guard let measurement = currentMeasurement, let index = history.firstIndex(where: { $0.id == measurement.id }) else { return }
        let updated = BodyMeasurement(id: measurement.id, date: measurement.date, weight: measurement.weight, impedance: measurement.impedance, bmi: measurement.bmi, bodyFat: measurement.bodyFat, muscle: measurement.muscle, water: measurement.water, protein: measurement.protein, boneMass: measurement.boneMass, memberID: member.id, memberName: member.name, adcIndex: measurement.adcIndex)
        currentMeasurement = updated; history[index] = updated; saveHistory()
    }
    private func saveHistory() { if let data = try? JSONEncoder().encode(history) { UserDefaults.standard.set(data, forKey: "afu.scale.history") } }
    private func loadHistory() { if let data = UserDefaults.standard.data(forKey: "afu.scale.history"), let saved = try? JSONDecoder().decode([BodyMeasurement].self, from: data) { history = saved } }
}

extension ScaleManager: @preconcurrency CBCentralManagerDelegate, @preconcurrency CBPeripheralDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        log("[BLE] Central manager state updated: \(central.state.rawValue)")
        if central.state == .poweredOn {
            if isScanning {
                connectionState = .scanning
                central.scanForPeripherals(
                    withServices: nil,
                    options: [CBCentralManagerScanOptionAllowDuplicatesKey: true]
                )
            } else {
                connectionState = .idle
            }
        } else {
            connectionState = .bluetoothOff
            isScanning = false
        }
    }
    
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        let name = advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? peripheral.name ?? "未知设备"
        let manufacturerData = advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data
        let serviceData = advertisementData[CBAdvertisementDataServiceDataKey] as? [CBUUID: Data]
        let afuData = Self.afuAdvertisementData(
            manufacturerData: manufacturerData,
            serviceData: serviceData
        )
        let isAFU = afuData != nil
        let matchesPrefix = name.uppercased().hasPrefix("AFU-WL")
        
        guard matchesPrefix, isAFU else { return }

        log("[BLE] Discovered supported scale: \(name) (\(peripheral.identifier.uuidString)), RSSI: \(RSSI), serviceData: \(serviceData?.keys.map(\.uuidString) ?? [])")
        
        let discoveredMac = Self.macAddress(from: afuData)
        log("[BLE] Discovered scale MAC: \(discoveredMac ?? "nil")")
        
        // QR Scanner auto-connection removed
        
        let pairedID = UserDefaults.standard.string(forKey: Self.pairedPeripheralIDKey)
        let isLegacyPairing = UserDefaults.standard.bool(forKey: "afu.hasPairedScale") && pairedID == nil
        let isKnownPeripheral = pairedID == peripheral.identifier.uuidString
        if isLegacyPairing || isKnownPeripheral {
            log("[BLE] Auto-connecting to paired scale: \(name)")
            connect(DiscoveredScale(peripheral: peripheral, name: name, identifier: peripheral.identifier.uuidString, rssi: RSSI.intValue))
            return
        }
        
        if !discoveredDevices.contains(where: { $0.id == peripheral.identifier }) {
            log("[BLE] Adding device to list: \(name)")
            discoveredDevices.append(DiscoveredScale(peripheral: peripheral, name: name, identifier: peripheral.identifier.uuidString, rssi: RSSI.intValue))
        }
    }
    
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        log("[BLE] Connected to: \(peripheral.name ?? "nil") (\(peripheral.identifier.uuidString))")
        deviceName = peripheral.name ?? deviceName
        UserDefaults.standard.set(true, forKey: "afu.hasPairedScale")
        UserDefaults.standard.set(peripheral.identifier.uuidString, forKey: Self.pairedPeripheralIDKey)
        connectionState = .connected
        peripheral.delegate = self
        // targetMacAddress reset removed
        log("[BLE] Discovering services for: \(serviceUUID)")
        peripheral.discoverServices([serviceUUID])
    }
    
    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        log("[BLE] Failed to connect to \(peripheral.name ?? "nil"), error: \(String(describing: error))")
        activePeripheral = nil
        connectionState = .idle
        if UserDefaults.standard.bool(forKey: "afu.hasPairedScale") {
            startScan()
        }
    }
    
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        log("[BLE] Disconnected from: \(peripheral.name ?? "nil"), error: \(String(describing: error))")
        connectionState = .idle
        activePeripheral = nil
        liveWeight = 0.0
        impedance = 0.0
        selectedADCIndex = nil
        isStable = false
        isMeasuring = false
        hasSavedMeasurement = false
        if UserDefaults.standard.bool(forKey: "afu.hasPairedScale") {
            log("[BLE] Restarting scan after disconnection...")
            startScan()
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error = error {
            log("[BLE] Service discovery error: \(error.localizedDescription)")
            return
        }
        guard let services = peripheral.services else {
            log("[BLE] No services discovered")
            return
        }
        log("[BLE] Discovered \(services.count) services: \(services.map { $0.uuid.uuidString })")
        services.forEach { service in
            log("[BLE] Discovering characteristics for service: \(service.uuid)")
            peripheral.discoverCharacteristics(nil, for: service)
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if let error = error {
            log("[BLE] Characteristics discovery error: \(error.localizedDescription)")
            return
        }
        guard let characteristics = service.characteristics else {
            log("[BLE] No characteristics discovered for service: \(service.uuid)")
            return
        }
        log("[BLE] Discovered \(characteristics.count) characteristics for service \(service.uuid): \(characteristics.map { "\($0.uuid.uuidString) (prop: \($0.properties.rawValue))" })")
        
        characteristics.filter { $0.properties.contains(.notify) || $0.properties.contains(.indicate) }.forEach { characteristic in
            log("[BLE] Subscribing to notifications for characteristic: \(characteristic.uuid)")
            peripheral.setNotifyValue(true, for: characteristic)
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error = error {
            log("[BLE] Error updating value for characteristic \(characteristic.uuid): \(error.localizedDescription)")
            return
        }
        guard let data = characteristic.value else {
            log("[BLE] Characteristic \(characteristic.uuid) value is empty")
            return
        }
        let hexString = data.map { String(format: "%02hhX", $0) }.joined(separator: " ")
        log("[BLE] Received raw data on \(characteristic.uuid): [\(hexString)] (\(data.count) bytes)")
        
        receive(data)
    }
    
    private static func afuAdvertisementData(
        manufacturerData: Data?,
        serviceData: [CBUUID: Data]?
    ) -> Data? {
        var candidates: [Data] = []

        if let manufacturerData {
            candidates.append(manufacturerData)
        }

        for (uuid, payload) in serviceData ?? [:] {
            guard let uuid16 = uuid16(from: uuid), String(format: "%04X", uuid16).contains("AC") else {
                continue
            }
            var reconstructed = Data([
                UInt8(uuid16 & 0x00FF),
                UInt8((uuid16 >> 8) & 0x00FF)
            ])
            reconstructed.append(payload)
            candidates.append(reconstructed)
        }

        // 与 CLI 相同：0x27 的 flags 表示连接型、体脂秤 category=2、subtype=7。
        return candidates.first { data in
            guard data.count >= 2, data[0] == 0xAC else { return false }
            let flags = data[1]
            let category = (flags & 0x70) >> 4
            let subtype = flags & 0x0F
            return category == 2 && subtype == 7
        }
    }

    private static func uuid16(from uuid: CBUUID) -> UInt16? {
        let value = uuid.uuidString.uppercased()
        let shortValue: String
        if value.count == 4 {
            shortValue = value
        } else if value.hasPrefix("0000"), value.hasSuffix("-0000-1000-8000-00805F9B34FB") {
            shortValue = String(value.dropFirst(4).prefix(4))
        } else {
            return nil
        }
        return UInt16(shortValue, radix: 16)
    }
    
    private static func macAddress(from advertisementData: Data?) -> String? {
        guard let advertisementData, advertisementData.count >= 8, advertisementData[0] == 0xAC else { return nil }
        let macBytes = advertisementData[2..<8].reversed()
        return macBytes.map { String(format: "%02X", $0) }.joined(separator: ":")
    }
    
    private func receive(_ data: Data) {
        guard let packet = AFUPacket(data: data) else {
            let hexString = data.map { String(format: "%02hhX", $0) }.joined(separator: " ")
            log("[BLE] Failed to parse raw data packet: [\(hexString)]")
            return
        }
        log("[BLE] Successfully parsed packet of type: \(packet.type)")
        switch packet.type {
        case .weight:
            let wasMeasuring = isMeasuring
            liveWeight = packet.weight
            isStable = packet.stable
            isMeasuring = !packet.stable
            connectionState = packet.stable ? .connected : .measuring
            log("[BLE] Weight packet - liveWeight: \(liveWeight), stable: \(isStable)")
            
            if liveWeight < 1.0 || (!wasMeasuring && isMeasuring && !hasSavedMeasurement) {
                impedance = 0
                selectedADCIndex = nil
            }
            // 稳定包之后的短暂波动仍属于同一次上秤；只有离秤才解锁下一条记录。
            if liveWeight < 1.0 {
                hasSavedMeasurement = false
            }
            if isMeasuring && liveWeight > 3.0 {
                currentMeasurement = nil
            }
            
            if packet.stable && impedance > 0 { finishMeasurement() }
        case .impedance:
            let packetWeight = packet.adcWeight > 0 ? packet.adcWeight : liveWeight
            let normalized = AFUPacket.normalizeImpedances(packet.adcs, weight: packetWeight)
            let preferredIndex = UserDefaults.standard.integer(forKey: ImpedanceADCChoice.storageKey)
            let preferredValue = normalized.indices.contains(preferredIndex) ? normalized[preferredIndex] : nil
            if let preferredValue, (100.0...1500.0).contains(preferredValue) {
                impedance = preferredValue
                selectedADCIndex = preferredIndex
            } else if let fallback = normalized.enumerated().first(where: { (100.0...1500.0).contains($0.element) }) {
                impedance = fallback.element
                selectedADCIndex = fallback.offset
            } else {
                impedance = 0
                selectedADCIndex = nil
            }
            let selectedLabel = selectedADCIndex.map { "ADC \($0 + 1)" } ?? "none"
            log("[BLE] Impedance packet - raw ADCs: \(packet.adcs), normalized: \(normalized), selected: \(selectedLabel) = \(impedance)")
            if isStable { finishMeasurement() }
        case .history:
            if let item = packet.historyMeasurement(profile: profile, history: history) {
                history.insert(item, at: 0)
                saveHistory()
                log("[BLE] History packet - added measurement: \(item)")
            } else {
                log("[BLE] History packet - failed to build history measurement")
            }
        case .settings:
            log("[BLE] Settings packet - ignored")
            break
        }
    }
}

struct AFUPacket {
    enum Kind { case weight, impedance, history, settings }
    let type: Kind; let raw: Data
    
    init?(data: Data) {
        guard data.count >= 20, data.first == 0xAC else {
            // Fallback for original standard AFU packets (without wrapper)
            guard let first = data.first else { return nil }
            raw = data
            switch first {
            case 0xD5: type = .weight
            case 0xD6: type = .impedance
            case 0xD8: type = .history
            case 0xDF: type = .settings
            default: return nil
            }
            return
        }
        
        raw = data
        let opcode = data[18]
        switch opcode {
        case 0xD5: type = .weight
        case 0xD6: type = .impedance
        case 0xD8: type = .history
        case 0xDF: type = .settings
        default: return nil
        }
    }
    
    private var payload32: UInt32 {
        guard raw.count >= 5 else { return 0 }
        return UInt32(raw[1]) | UInt32(raw[2]) << 8 | UInt32(raw[3]) << 16 | UInt32(raw[4]) << 24
    }
    
    var stable: Bool {
        if raw.first == 0xAC {
            // Status byte at index 6: 0x02 indicates stable
            return raw.count >= 7 && raw[6] == 0x02 && weight > 0
        } else {
            return payload32 & 0x8000_0000 != 0
        }
    }
    
    var weight: Double {
        if raw.first == 0xAC {
            // 3-byte weight encoding: rawVal = (raw[3] - 0x68) * 65536 + raw[4] * 256 + raw[5]
            // weight(kg) = rawVal / 1000
            // e.g. 82.05kg → raw[3]=0x69, raw[4]=0x40, raw[5]=0x82 → (1*65536+0x4082)/1000=82.05
            guard raw.count >= 6, raw[3] >= 0x68 else { return 0.0 }
            let base = UInt32(raw[3] - 0x68)
            let rawVal = (base << 16) | (UInt32(raw[4]) << 8) | UInt32(raw[5])
            return Double(rawVal) / 1000.0
        } else {
            return Double(payload32 & 0x0003_FFFF) / 1000.0
        }
    }
    
    var adcs: [Double] {
        if raw.first == 0xAC {
            guard raw.count >= 19, raw[18] == 0xD6 else { return [] }
            let count = Int(raw[2])
            let start = 4
            guard count > 0, start + count * 2 <= raw.count else { return [] }
            return (0..<count).map { index in
                let offset = start + index * 2
                return Double(UInt16(raw[offset]) << 8 | UInt16(raw[offset + 1]))
            }
        }

        guard raw.first == 0xD6, raw.count >= 3 else { return [] }
        return [Double(UInt16(raw[1]) << 8 | UInt16(raw[2]))]
    }

    var adcWeight: Double {
        guard raw.first == 0xAC, raw.count >= 13, raw[18] == 0xD6 else { return 0 }
        let encoded = UInt32(raw[9]) << 24
            | UInt32(raw[10]) << 16
            | UInt32(raw[11]) << 8
            | UInt32(raw[12])
        return Double(encoded & 0x0003_FFFF) / 1000.0
    }

    static func normalizeImpedances(_ adcs: [Double], weight: Double) -> [Double] {
        if adcs.count == 5 {
            return [adcs[4], adcs[0], adcs[1], adcs[2], adcs[3]].map(roundToTwoPlaces)
        }
        return adcs.map { adc in
            let normalized: Double
            if adc >= 1500, weight > 0 {
                normalized = (((adc - 1000) + ((weight * 10) * -0.4)) / 0.6) / 10
            } else {
                normalized = adc
            }
            return roundToTwoPlaces(normalized)
        }
    }

    nonisolated private static func roundToTwoPlaces(_ value: Double) -> Double {
        (value * 100).rounded() / 100
    }
    
    @MainActor func historyMeasurement(profile: UserProfile?, history: [BodyMeasurement]) -> BodyMeasurement? {
        guard let profile else { return nil }
        let kg = weight
        guard kg > 0 else { return nil }
        let member = profile.matchedMember(for: kg, history: history)
        
        let imp: Double
        if raw.first == 0xAC {
            imp = raw.count >= 10 ? Double(UInt16(raw[9]) | UInt16(raw[8]) << 8) : 0
        } else {
            imp = raw.count >= 7 ? Double(UInt16(raw[5]) | UInt16(raw[6]) << 8) : 0
        }
        return BodyAlgorithm.measure(weight: kg, impedance: imp, member: member)
    }
}

@MainActor enum BodyAlgorithm {
    static func measure(
        weight: Double,
        impedance: Double,
        member: FamilyMember,
        adcIndex: Int? = nil
    ) -> BodyMeasurement {
        let heightM = member.height / 100
        let bmi = weight / (heightM * heightM)
        let age = Double(member.age)
        let validResistance = (100.0...1500.0).contains(impedance) ? impedance : nil

        let baseBodyFat: Double
        if let resistance = validResistance {
            let heightSquared = member.height * member.height
            var fatFreeMass: Double

            if member.sex == .male {
                fatFreeMass = 9.33285
                    + 0.00066360 * heightSquared
                    - 0.02117 * resistance
                    + 0.62854 * weight
                    - 0.12380 * age
                let initialBodyFat = 100 * (weight - fatFreeMass) / weight
                if initialBodyFat >= 20 {
                    fatFreeMass = 14.52435
                        + 0.00088580 * heightSquared
                        - 0.02999 * resistance
                        + 0.42688 * weight
                        - 0.07002 * age
                }
            } else {
                fatFreeMass = 10.43485
                    + 0.00064602 * heightSquared
                    - 0.01397 * resistance
                    + 0.42087 * weight
                let initialBodyFat = 100 * (weight - fatFreeMass) / weight
                if initialBodyFat >= 30 {
                    fatFreeMass = 9.37938
                        + 0.00091186 * heightSquared
                        - 0.01466 * resistance
                        + 0.29990 * weight
                        - 0.07012 * age
                }
            }

            fatFreeMass = clamp(fatFreeMass, weight * 0.35, weight * 0.97)
            baseBodyFat = 100 * (weight - fatFreeMass) / weight
        } else {
            let sexValue = member.sex == .male ? 1.0 : 0.0
            baseBodyFat = 1.20 * bmi + 0.23 * age - 10.8 * sexValue - 5.4
        }

        let minimumBodyFat = member.sex == .male ? 3.0 : 8.0
        let fat = clamp(baseBodyFat, minimumBodyFat, 60.0)
        let bonePercent = member.sex == .male ? 4.5 : 4.0
        let musclePercent = clamp(100.0 - fat - bonePercent, 20.0, 95.0)
        let water = clamp((100.0 - fat) * 0.70, 25.0, 80.0)
        let protein = clamp((100.0 - fat) * 0.238, 5.0, 35.0)
        let bone = weight * bonePercent / 100.0
        let muscle = weight * musclePercent / 100.0
        return BodyMeasurement(id: UUID(), date: .now, weight: weight, impedance: impedance, bmi: bmi, bodyFat: fat, muscle: muscle, water: water, protein: protein, boneMass: bone, memberID: member.id, memberName: member.name, adcIndex: adcIndex)
    }

    private static func clamp(_ value: Double, _ lowerBound: Double, _ upperBound: Double) -> Double {
        min(max(value, lowerBound), upperBound)
    }
}
