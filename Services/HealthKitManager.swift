import Foundation
import HealthKit
import Combine

class HealthKitManager: ObservableObject {
    @Published var currentBPM: Int = 0
    @Published var isAuthorized: Bool = false
    @Published var dataSourceName: String = "Buscando fuente..."
    
    private let healthStore = HKHealthStore()
    private var anchor: HKQueryAnchor?
    
    func solicitarPermisoHealthKit() {
        guard HKHealthStore.isHealthDataAvailable() else {
            print("HealthKit no disponible en simulador o dispositivo sin soporte.")
            return
        }
        
        guard let heartRateType = HKObjectType.quantityType(forIdentifier: .heartRate) else { return }
        let typesToRead: Set<HKObjectType> = [heartRateType]
        
        healthStore.requestAuthorization(toShare: nil, read: typesToRead) { [weak self] success, error in
            DispatchQueue.main.async {
                if let error = error {
                    print("Error solicitando permisos: \(error.localizedDescription)")
                    self?.isAuthorized = false
                } else {
                    self?.isAuthorized = success
                    if success {
                        self?.iniciarObservacionInmediata()
                    }
                }
            }
        }
    }
    
    func iniciarObservacionInmediata() {
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
        obtenerUltimoBPM()
    }
    
    private func procesarMuestras(_ samples: [HKSample]?) {
        guard let quantitySamples = samples as? [HKQuantitySample] else { return }
        
        // Priorizar muestras cuya fuente sea AirPods
        let airPodsSample = quantitySamples.last(where: { $0.sourceRevision.source.name.localizedCaseInsensitiveContains("AirPods") })
        let sampleToUse = airPodsSample ?? quantitySamples.last
        
        guard let finalSample = sampleToUse else { return }
        
        let unit = HKUnit.count().unitDivided(by: HKUnit.minute())
        let bpm = Int(finalSample.quantity.doubleValue(for: unit))
        let sourceName = finalSample.sourceRevision.source.name
        
        DispatchQueue.main.async {
            if bpm > 0 {
                self.currentBPM = bpm
                self.dataSourceName = sourceName
            }
        }
    }
    
    func obtenerUltimoBPM() {
        guard let heartRateType = HKObjectType.quantityType(forIdentifier: .heartRate) else { return }
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)
        
        let query = HKSampleQuery(sampleType: heartRateType, predicate: nil, limit: 10, sortDescriptors: [sortDescriptor]) { [weak self] _, results, _ in
            self?.procesarMuestras(results)
        }
        healthStore.execute(query)
    }
}
