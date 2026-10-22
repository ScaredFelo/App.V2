import Foundation
import HealthKit
import Combine

class HealthKitManager: ObservableObject {
    @Published var currentBPM: Int = 0
    @Published var isAuthorized: Bool = false
    
    private let healthStore = HKHealthStore()
    private var workoutSession: HKWorkoutSession?
    
    func solicitarPermisoHealthKit(completion: @escaping (Bool) -> Void) {
        guard HKHealthStore.isHealthDataAvailable() else {
            completion(false)
            return
        }
        
        guard let tipoRitmoCardiaco = HKObjectType.quantityType(forIdentifier: .heartRate) else {
            completion(false)
            return
        }
        
        let tiposACompartir: Set<HKSampleType> = [HKObjectType.workoutType()]
        let tiposAleer: Set<HKObjectType> = [tipoRitmoCardiaco]
        
        healthStore.requestAuthorization(toShare: tiposACompartir, read: tiposAleer) { [weak self] success, error in
            DispatchQueue.main.async {
                self?.isAuthorized = success
                if success {
                    self?.iniciarWorkoutSessionIOS()
                }
                completion(success)
            }
        }
    }
    
    func iniciarWorkoutSessionIOS() {
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .traditionalStrengthTraining
        configuration.locationType = .indoor
        
        do {
            // Inicializador compatible con iOS 17+
            workoutSession = try HKWorkoutSession(healthStore: healthStore, configuration: configuration)
            workoutSession?.startActivity(with: Date())
            
            self.iniciarObservacionBPM()
        } catch {
            print("Error al iniciar HKWorkoutSession en iOS: \(error.localizedDescription)")
            iniciarObservacionBPM()
        }
    }
    
    func detenerWorkoutSession() {
        workoutSession?.end()
    }
    
    func iniciarObservacionBPM() {
        guard let tipoRitmoCardiaco = HKObjectType.quantityType(forIdentifier: .heartRate) else { return }
        
        let query = HKObserverQuery(sampleType: tipoRitmoCardiaco, predicate: nil) { [weak self] _, completionHandler, error in
            if error != nil {
                completionHandler()
                return
            }
            
            self?.obtenerUltimoBPM { bpm in
                DispatchQueue.main.async {
                    if bpm > 0 {
                        self?.currentBPM = Int(bpm)
                    }
                }
                completionHandler()
            }
        }
        
        healthStore.execute(query)
        healthStore.enableBackgroundDelivery(for: tipoRitmoCardiaco, frequency: .immediate) { _, _ in }
        
        obtenerUltimoBPM { [weak self] bpm in
            DispatchQueue.main.async {
                if bpm > 0 {
                    self?.currentBPM = Int(bpm)
                }
            }
        }
    }
    
    func obtenerUltimoBPM(completion: @escaping (Double) -> Void) {
        guard let tipoRitmoCardiaco = HKObjectType.quantityType(forIdentifier: .heartRate) else { return }
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)
        
        let query = HKSampleQuery(sampleType: tipoRitmoCardiaco, predicate: nil, limit: 1, sortDescriptors: [sortDescriptor]) { _, results, _ in
            guard let muestra = results?.first as? HKQuantitySample else {
                completion(0)
                return
            }
            let unidadBPM = HKUnit.count().unitDivided(by: HKUnit.minute())
            completion(muestra.quantity.doubleValue(for: unidadBPM))
        }
        healthStore.execute(query)
    }
}
