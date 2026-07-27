import SwiftUI
import Foundation
@preconcurrency import CoreBluetooth
import Combine

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
