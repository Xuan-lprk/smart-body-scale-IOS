import SwiftUI

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
