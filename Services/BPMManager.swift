import Foundation
import CoreBluetooth
import Combine

final class BPMManager: NSObject, ObservableObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    static let shared = BPMManager()

    @Published var currentBPM: Int = 0
    @Published var isConnected: Bool = false
    @Published var statusText: String = "Sin pulso"

    private var centralManager: CBCentralManager?
    private var heartRatePeripheral: CBPeripheral?

    private let healthKitManager = HealthKitManager()
    private var cancellables = Set<AnyCancellable>()

    override init() {
        super.init()

        // HealthKit (AirPods / Apple Watch)
        healthKitManager.$currentBPM
            .receive(on: DispatchQueue.main)
            .sink { [weak self] bpm in
                guard let self, bpm > 0 else { return }
                // Priorizamos el pulsómetro BLE mientras esté conectado
                if self.heartRatePeripheral == nil {
                    self.currentBPM = bpm
                    self.isConnected = true
                    self.statusText = "\(bpm) BPM"
                }
            }
            .store(in: &cancellables)

        requestHealthKitAccess()

        // Inicialización tardía para asegurar permisos
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.centralManager = CBCentralManager(delegate: self, queue: nil)
        }
    }

    func requestHealthKitAccess() {
        healthKitManager.requestAuthorization { [weak self] success in
            DispatchQueue.main.async {
                guard let self, self.currentBPM == 0 else { return }
                self.statusText = success ? "HealthKit listo" : "Sin acceso a Salud"
            }
        }
    }

    func startScanning() {
        guard let cm = centralManager else {
            statusText = "Iniciando Bluetooth..."
            return
        }
        switch cm.state {
        case .poweredOn:
            statusText = "Buscando..."
            cm.scanForPeripherals(
                withServices: [CBUUID(string: "180D")],
                options: [CBCentralManagerScanOptionAllowDuplicatesKey: true]
            )
        case .unauthorized:
            statusText = "Sin Permiso BT"
        default:
            statusText = "Bluetooth no listo"
        }
    }

    // Alias de compatibilidad con llamadas existentes
    func startBluetoothScanning() {
        startScanning()
    }

    func reconnect() {
        centralManager?.stopScan()
        if let peripheral = heartRatePeripheral {
            centralManager?.cancelPeripheralConnection(peripheral)
            heartRatePeripheral = nil
        }
        isConnected = false
        currentBPM = 0
        statusText = "Sin pulso"
        startScanning()
    }

    func stopScanning() {
        centralManager?.stopScan()
        statusText = "Sin pulso"
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            switch central.state {
            case .poweredOn:
                self.startScanning()
            case .unauthorized:
                self.statusText = "Sin Permiso BT"
            case .poweredOff:
                self.statusText = "BT Apagado"
            default:
                self.statusText = "Bluetooth no listo"
            }
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        heartRatePeripheral = peripheral
        heartRatePeripheral?.delegate = self
        central.stopScan()
        central.connect(peripheral, options: nil)
        DispatchQueue.main.async { [weak self] in
            self?.statusText = "Conectando..."
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        DispatchQueue.main.async { [weak self] in
            self?.isConnected = true
            self?.statusText = "Conectado"
        }
        peripheral.discoverServices([CBUUID(string: "180D")])
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.isConnected = false
            self.currentBPM = 0
            self.statusText = "Sin pulso"
        }
        heartRatePeripheral = nil
        startScanning()
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let services = peripheral.services else { return }
        for service in services where service.uuid == CBUUID(string: "180D") {
            peripheral.discoverCharacteristics([CBUUID(string: "2A37")], for: service)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard let characteristics = service.characteristics else { return }
        for characteristic in characteristics where characteristic.uuid == CBUUID(string: "2A37") {
            peripheral.setNotifyValue(true, for: characteristic)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard let data = characteristic.value, !data.isEmpty else { return }
        let buffer = [UInt8](data)
        let flags = buffer[0]
        let is16Bit = (flags & 0x01) != 0

        var bpm: Int = 0
        if is16Bit {
            if buffer.count >= 3 {
                bpm = Int(buffer[1]) | (Int(buffer[2]) << 8)
            }
        } else {
            if buffer.count >= 2 {
                bpm = Int(buffer[1])
            }
        }

        if bpm > 0 {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.currentBPM = bpm
                self.isConnected = true
                self.statusText = "\(bpm) BPM"
            }
        }
    }
}
