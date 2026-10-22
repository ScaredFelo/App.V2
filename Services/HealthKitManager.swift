import Foundation
import HealthKit
import Combine

class HealthKitManager: ObservableObject {
    @Published var currentBPM: Int = 0
    @Published var isAuthorized: Bool = false
    @Published var authorizationStatusText: String = "Pendiente de permiso"
    
    private let healthStore = HKHealthStore()
    private var activeWorkoutBuilder: HKWorkoutBuilder?
    private var anchor: HKQueryAnchor?
    
    func solicitarPermisoHealthKit() {
        guard activeWorkoutBuilder == nil else { return }
        
        guard HKHealthStore.isHealthDataAvailable() else {
            DispatchQueue.main.async {
                self.authorizationStatusText = "HealthKit no disponible en este dispositivo"
            }
            return
        }
        
        guard let heartRateType = HKObjectType.quantityType(forIdentifier: .heartRate) else { return }
        let workoutType = HKObjectType.workoutType()
        
        let typesToRead: Set<HKObjectType> = [heartRateType]
        let typesToShare: Set<HKSampleType> = [workoutType]
        
        print("Solicitando autorización de HealthKit...")
        
        healthStore.requestAuthorization(toShare: typesToShare, read: typesToRead) { [weak self] success, error in
            DispatchQueue.main.async {
                if let error = error {
                    print("Error al solicitar permisos: \(error.localizedDescription)")
                    self?.authorizationStatusText = "Error de permisos: \(error.localizedDescription)"
                    self?.isAuthorized = false
                    return
                }
                
                self?.isAuthorized = success
                if success {
                    print("Permiso concedido con éxito.")
                    self?.authorizationStatusText = "Permiso concedido"
                    self?.iniciarSesionFantasma()
                } else {
                    print("El usuario denegó los permisos de HealthKit.")
                    self?.authorizationStatusText = "Permiso denegado por el usuario"
                }
            }
        }
    }
    
    func iniciarSesionFantasma() {
        guard activeWorkoutBuilder == nil else { return }
        
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .traditionalStrengthTraining
        configuration.locationType = .indoor
        
        let builder = HKWorkoutBuilder(healthStore: healthStore, configuration: configuration, device: .local())
        self.activeWorkoutBuilder = builder
        
        builder.beginCollection(withStart: Date()) { [weak self] success, _ in
            if success {
                self?.iniciarObservadorInmediato()
            }
        }
    }
    
    func iniciarObservadorInmediato() {
        guard let heartRateType = HKObjectType.quantityType(forIdentifier: .heartRate) else { return }
        
        healthStore.enableBackgroundDelivery(for: heartRateType, frequency: .immediate) { _, _ in }
        
        let query = HKAnchoredObjectQuery(
            type: heartRateType,
            predicate: nil,
            anchor: anchor,
            limit: HKObjectQueryNoLimit
        ) { [weak self] _, samples, _, newAnchor, _ in
            self?.anchor = newAnchor
            self?.procesarMuestras(samples)
        }
        
        query.updateHandler = { [weak self] _, samples, _, newAnchor, _ in
            self?.anchor = newAnchor
            self?.procesarMuestras(samples)
        }
        
        healthStore.execute(query)
    }
    
    private func procesarMuestras(_ samples: [HKSample]?) {
        guard let quantitySamples = samples as? [HKQuantitySample], let lastSample = quantitySamples.last else { return }
        
        let unit = HKUnit.count().unitDivided(by: HKUnit.minute())
        let bpm = Int(lastSample.quantity.doubleValue(for: unit))
        
        DispatchQueue.main.async {
            if bpm > 0 {
                self.currentBPM = bpm
            }
        }
    }
}
