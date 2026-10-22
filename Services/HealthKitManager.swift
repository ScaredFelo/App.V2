import Foundation
import HealthKit
import Combine

class HealthKitManager: ObservableObject {
    @Published var currentBPM: Int = 0
    @Published var isAuthorized: Bool = false
    
    private let healthStore = HKHealthStore()
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
        
        let tiposACompartir: Set<HKSampleType> = [HKObjectType.workoutType()]
        let tiposAleer: Set<HKObjectType> = [tipoRitmoCardiaco]
        
        healthStore.requestAuthorization(toShare: tiposACompartir, read: tiposAleer) { [weak self] success, error in
            DispatchQueue.main.async {
                self?.isAuthorized = success
                if success {
                    self?.iniciarObservacionBPM()
                }
                completion(success)
            }
        }
    }
    
    func iniciarObservacionBPM() {
        guard let tipoRitmoCardiaco = HKObjectType.quantityType(forIdentifier: .heartRate) else { return }
        
        // Habilitar entrega inmediata en segundo plano
        healthStore.enableBackgroundDelivery(for: tipoRitmoCardiaco, frequency: .immediate) { _, _ in }
        
        // Consulta anclada para recibir cambios continuos
        let samplePredicate = HKQuery.predicateForSamples(withStart: Date().addingTimeInterval(-3600), end: nil, options: .strictStartDate)
        
        let query = HKAnchoredObjectQuery(
            type: tipoRitmoCardiaco,
            predicate: samplePredicate,
            anchor: anchor,
            limit: HKObjectQueryNoLimit
        ) { [weak self] _, samples, _, newAnchor, _ in
            self?.anchor = newAnchor
            self?.procesarMuestrasBPM(samples)
        }
        
        query.updateHandler = { [weak self] _, samples, _, newAnchor, _ in
            self?.anchor = newAnchor
            self?.procesarMuestrasBPM(samples)
        }
        
        healthStore.execute(query)
        obtenerUltimoBPM()
    }
    
    private func procesarMuestrasBPM(_ samples: [HKSample]?) {
        guard let quantitySamples = samples as? [HKQuantitySample], let ultimaMuestra = quantitySamples.last else { return }
        
        let unidadBPM = HKUnit.count().unitDivided(by: HKUnit.minute())
        let valorBPM = Int(ultimaMuestra.quantity.doubleValue(for: unidadBPM))
        
        DispatchQueue.main.async {
            if valorBPM > 0 {
                self.currentBPM = valorBPM
            }
        }
    }
    
    func obtenerUltimoBPM() {
        guard let tipoRitmoCardiaco = HKObjectType.quantityType(forIdentifier: .heartRate) else { return }
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)
        
        let query = HKSampleQuery(sampleType: tipoRitmoCardiaco, predicate: nil, limit: 1, sortDescriptors: [sortDescriptor]) { [weak self] _, results, _ in
            guard let muestra = results?.first as? HKQuantitySample else { return }
            let unidadBPM = HKUnit.count().unitDivided(by: HKUnit.minute())
            let valorBPM = Int(muestra.quantity.doubleValue(for: unidadBPM))
            
            DispatchQueue.main.async {
                if valorBPM > 0 {
                    self?.currentBPM = valorBPM
                }
            }
        }
        healthStore.execute(query)
    }
}
