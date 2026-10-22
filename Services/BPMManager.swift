import Foundation
import HealthKit
import CoreBluetooth

public enum BPMDataSource: String, CaseIterable, Identifiable, Sendable {
    case healthKit = "Apple Health (Apple Watch / AirPods)"
    case bluetooth = "Bluetooth BLE (HR Monitor)"
    
    public var id: String { rawValue }
}

@Observable
@MainActor
public final class BPMManager: NSObject {
    public static let shared = BPMManager()

    public var currentBPM: Int?
    public var dataSource: BPMDataSource = .healthKit {
        didSet {
            switchDataSource(to: dataSource)
        }
    }
    public var isScanning = false
    public var isConnected = false
    public var peripheralName: String?

    // HealthKit
    private let healthStore = HKHealthStore()
    private var heartRateQuery: HKQuery?

    // CoreBluetooth
    private var centralManager: CBCentralManager!
    private var connectedPeripheral: CBPeripheral?
    private let heartRateServiceUUID = CBUUID(string: "180D")
    private let heartRateMeasurementCharacteristicUUID = CBUUID(string: "2A37")

    override private init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: nil)
    }

    public func requestPermissions() {
        if HKHealthStore.isHealthDataAvailable() {
            let heartRateType = HKQuantityType.quantityType(forIdentifier: .heartRate)!
            let typesToRead: Set<HKObjectType> = [heartRateType]

            healthStore.requestAuthorization(toShare: [], read: typesToRead) { [weak self] success, _ in
                Task { @MainActor in
                    if success, self?.dataSource == .healthKit {
                        self?.startHealthKitQuery()
                    }
                }
            }
        }
    }

    public func reconnect() {
        stopAll()
        if dataSource == .bluetooth {
            startBluetoothScanning()
        } else {
            startHealthKitQuery()
        }
    }

    private func switchDataSource(to source: BPMDataSource) {
        stopAll()
        switch source {
        case .healthKit:
            startHealthKitQuery()
        case .bluetooth:
            startBluetoothScanning()
        }
    }

    public func stopAll() {
        if let query = heartRateQuery {
            healthStore.stop(query)
            heartRateQuery = nil
        }
        if centralManager.isScanning {
            centralManager.stopScan()
        }
        if let peripheral = connectedPeripheral {
            centralManager.cancelPeripheralConnection(peripheral)
            connectedPeripheral = nil
        }
        isScanning = false
        isConnected = false
        currentBPM = nil
        peripheralName = nil
    }

    // MARK: - HealthKit Integration
    private func startHealthKitQuery() {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        let heartRateType = HKQuantityType.quantityType(forIdentifier: .heartRate)!

        let query = HKObserverQuery(sampleType: heartRateType, predicate: nil) { [weak self] _, completionHandler, error in
            guard error == nil else {
                completionHandler()
                return
            }
            self?.fetchLatestHeartRateSample {
                completionHandler()
            }
        }

        healthStore.execute(query)
        heartRateQuery = query
        fetchLatestHeartRateSample {}
    }

    private func fetchLatestHeartRateSample(completion: @escaping () -> Void) {
        let heartRateType = HKQuantityType.quantityType(forIdentifier: .heartRate)!
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
        let query = HKSampleQuery(sampleType: heartRateType, predicate: nil, limit: 1, sortDescriptors: [sortDescriptor]) { [weak self] _, results, error in
            defer { completion() }
            guard error == nil, let sample = results?.first as? HKQuantitySample else { return }
            let bpm = Int(sample.quantity.doubleValue(for: HKUnit.count().unitDivided(by: .minute())))
            Task { @MainActor in
                self?.currentBPM = bpm
            }
        }
        healthStore.execute(query)
    }

    // MARK: - CoreBluetooth Integration
    public func startBluetoothScanning() {
        guard centralManager.state == .poweredOn else {
            isScanning = false
            return
        }
        isScanning = true
        centralManager.scanForPeripherals(withServices: [heartRateServiceUUID], options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
    }
}

// MARK: - CBCentralManagerDelegate & CBPeripheralDelegate
extension BPMManager: CBCentralManagerDelegate, CBPeripheralDelegate {
    nonisolated public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        Task { @MainActor in
            if central.state == .poweredOn, dataSource == .bluetooth {
                startBluetoothScanning()
            }
        }
    }

    nonisolated public func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        Task { @MainActor in
            centralManager.stopScan()
            isScanning = false
            connectedPeripheral = peripheral
            peripheral.delegate = self
            centralManager.connect(peripheral, options: nil)
            peripheralName = peripheral.name ?? "Dispositivo HR"
        }
    }

    nonisolated public func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        Task { @MainActor in
            isConnected = true
            peripheral.discoverServices([heartRateServiceUUID])
        }
    }

    nonisolated public func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        Task { @MainActor in
            isConnected = false
            currentBPM = nil
            if dataSource == .bluetooth {
                startBluetoothScanning()
            }
        }
    }

    nonisolated public func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let services = peripheral.services else { return }
        for service in services where service.uuid == heartRateServiceUUID {
            peripheral.discoverCharacteristics([heartRateMeasurementCharacteristicUUID], for: service)
        }
    }

    nonisolated public func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard let characteristics = service.characteristics else { return }
        for characteristic in characteristics where characteristic.uuid == heartRateMeasurementCharacteristicUUID {
            peripheral.setNotifyValue(true, for: characteristic)
        }
    }

    nonisolated public func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard characteristic.uuid == heartRateMeasurementCharacteristicUUID, let data = characteristic.value else { return }
        let bpm = parseHeartRate(from: data)
        Task { @MainActor in
            self.currentBPM = bpm
        }
    }

    private nonisolated func parseHeartRate(from data: Data) -> Int {
        let pointer = (data as NSData).bytes.assumingMemoryBound(to: UInt8.self)
        let flags = pointer.pointee
        let is16Bit = (flags & 0x01) != 0
        if is16Bit {
            let bpm16 = UnsafeRawPointer(pointer.advanced(by: 1)).load(as: UInt16.self)
            return Int(UInt16(littleEndian: bpm16))
        } else {
            return Int(pointer.advanced(by: 1).pointee)
        }
    }
}
