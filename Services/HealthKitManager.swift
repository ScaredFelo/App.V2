import Foundation
import HealthKit
import Combine

class HealthKitManager: ObservableObject {
    @Published var currentBPM: Int = 0
    @Published var isAuthorized: Bool = false
    
    private let healthStore = HKHealthStore()
    
    func solicitarPermisoHealthKit(completion: @escaping (Bool) -> Void) {
        guard HKHealthStore.isHealthDataAvailable() else {
            completion(false)
            return
        }
        
        guard let tipoRitmoCardiaco = HKObjectType.quantityType(forIdentifier: .heartRate) else {
            completion(false)
            return
        }
        
        let tiposAleer: Set<HKObjectType> = [tipoRitmoCardiaco]
        
        healthStore.requestAuthorization(toShare: nil, read: tiposAleer) { [weak self] success, error in
            DispatchQueue.main.async {
                self?.isAuthorized = success
                if success {
                    print("Permiso concedido por el usuario.")
                    self?.iniciarObservacionBPM()
                } else {
                    print("Permiso denegado o error: \(String(describing: error))")
                }
                completion(success)
            }
        }
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
        
        // Primera lectura inmediata al iniciar
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
        
        let query = HKSampleQuery(sampleType: tipoRitmoCardiaco, predicate: nil, limit: 1, sortDescriptors: [sortDescriptor]) { _, results, error in
            guard let muestra = results?.first as? HKQuantitySample else {
                completion(0)
                return
            }
            
            let unidadBPM = HKUnit.count().unitDivided(by: HKUnit.minute())
            let valorBPM = muestra.quantity.doubleValue(for: unidadBPM)
            completion(valorBPM)
        }
        
        healthStore.execute(query)
    }
}
