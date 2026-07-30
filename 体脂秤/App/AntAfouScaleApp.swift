import SwiftUI

@main struct AntAfouScaleApp: App {
    @StateObject private var scale = ScaleManager()
    @StateObject private var profile = UserProfile()
    @StateObject private var healthKit = HealthKitManager()
    @StateObject private var comparisonStore = ComparisonStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(scale)
                .environmentObject(profile)
                .environmentObject(healthKit)
                .environmentObject(comparisonStore)
        }
    }
}
