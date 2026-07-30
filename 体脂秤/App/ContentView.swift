import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var scale: ScaleManager
    @EnvironmentObject private var profile: UserProfile
    @EnvironmentObject private var healthKit: HealthKitManager
    @EnvironmentObject private var comparisonStore: ComparisonStore
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
            scale.comparisonStore = comparisonStore
            healthKit.onMeasurementsRecovered = { measurements in
                scale.mergeRestoredHistory(measurements)
            }
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
        .sheet(item: $scale.reviewMeasurement) { measurement in
            MeasurementReviewView(measurement: measurement)
        }
    }

    private func promptForInitialMemberIfNeeded() {
        if hasPairedScale && !hasPromptedInitial { showingInitialPrompt = true }
    }
}

#Preview("主界面") {
    ContentView()
        .environmentObject(ScaleManager())
        .environmentObject(UserProfile())
        .environmentObject(HealthKitManager())
        .environmentObject(ComparisonStore())
}
