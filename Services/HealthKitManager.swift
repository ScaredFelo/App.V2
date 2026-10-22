import Foundation
import HealthKit
import Combine

class HealthKitManager: ObservableObject {
    @Published var currentBPM: Int = 0
    @Published var isAuthorized: Bool = false
    
    private let healthStore = HKHealthStore()
    private var anchor: HKQueryAnchor?
    private var activeQuery: HKAnchoredObjectQuery?
    
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
                    self?.iniciarRastrearteContinuo()
                }
                completion(success)
            }
        }
    }
    
    func iniciarRastrearteContinuo() {
        guard let tipoRitmoCardiaco = HKObjectType.quantityType(forIdentifier: .heartRate) else { return }
        
        // Habilitar la frecuencia de entrega inmediata
        healthStore.enableBackgroundDelivery(for: tipoRitmoCardiaco, frequency: .immediate) { _, _ in }
        
        // Predicado para tomar muestras desde hace 5 minutos en adelante
        let predicado = HKQuery.predicateForSamples(withStart: Date().addingTimeInterval(-300), end: nil, options: .strictStartDate)
        
        let query = HKAnchoredObjectQuery(
            type: tipoRitmoCardiaco,
            predicate: predicado,
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
        
        self.activeQuery = query
        healthStore.execute(query)
        obtenerUltimoBPM()
    }
    
    private func procesarMuestras(_ samples: [HKSample]?) {
        guard let muestras = samples as? [HKQuantitySample], let ultimaMuestra = muestras.last else { return }
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
