import Foundation
import HealthKit
import Combine

class HealthKitManager: ObservableObject {
    @Published var currentBPM: Int = 0
    @Published var isAuthorized: Bool = false
    
    private let healthStore = HKHealthStore()
    private var activeWorkoutBuilder: HKWorkoutBuilder?
    private var anchor: HKQueryAnchor?
    
    func solicitarPermisoHealthKit(completion: @escaping (Bool) -> Void) {
        guard HKHealthStore.isHealthDataAvailable() else {
            completion(false)
            return
        }
        
        guard let tipoRitmoCardiaco = HKObjectType.quantityType(forIdentifier: .heartRate) else {
            completion(false)
            return
        }
        
        // Solicitar permisos de ESCRITURA para registrar el entrenamiento fantasma que mantiene despierto el sensor
        let tiposACompartir: Set<HKSampleType> = [HKObjectType.workoutType()]
        let tiposAleer: Set<HKObjectType> = [tipoRitmoCardiaco]
        
        healthStore.requestAuthorization(toShare: tiposACompartir, read: tiposAleer) { [weak self] success, _ in
            DispatchQueue.main.async {
                self?.isAuthorized = success
                if success {
                    self?.iniciarSesionFantasmaAirPods()
                }
                completion(success)
            }
        }
    }
    
    func iniciarSesionFantasmaAirPods() {
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .traditionalStrengthTraining
        configuration.locationType = .indoor
        
        // HKWorkoutBuilder local para iOS 17+
        let builder = HKWorkoutBuilder(healthStore: healthStore, configuration: configuration, device: .local())
        self.activeWorkoutBuilder = builder
        
        builder.beginCollection(withStart: Date()) { [weak self] success, _ in
            if success {
                self?.iniciarObservacionInmediata()
            }
        }
    }
    
    func detenerSesion() {
        activeWorkoutBuilder?.endCollection(withEnd: Date()) { [weak self] _, _ in
            self?.activeWorkoutBuilder?.finishWorkout { _, _ in }
        }
    }
    
    func iniciarObservacionInmediata() {
        guard let tipoRitmoCardiaco = HKObjectType.quantityType(forIdentifier: .heartRate) else { return }
        
        healthStore.enableBackgroundDelivery(for: tipoRitmoCardiaco, frequency: .immediate) { _, _ in }
        
        let query = HKAnchoredObjectQuery(
            type: tipoRitmoCardiaco,
            predicate: nil,
            anchor: anchor,
            limit: HKObjectQueryNoLimit
        ) { [weak self] _, samples, _, newAnchor, _ in
            self?.anchor = newAnchor
            self?.extraerBPM(samples)
        }
        
        query.updateHandler = { [weak self] _, samples, _, newAnchor, _ in
            self?.anchor = newAnchor
            self?.extraerBPM(samples)
        }
        
        healthStore.execute(query)
    }
    
    private func extraerBPM(_ samples: [HKSample]?) {
        guard let muestras = samples as? [HKQuantitySample], let ultima = muestras.last else { return }
        let unidad = HKUnit.count().unitDivided(by: HKUnit.minute())
        let bpm = Int(ultima.quantity.doubleValue(for: unidad))
        
        DispatchQueue.main.async {
            if bpm > 0 {
                self.currentBPM = bpm
            }
        }
    }
}
