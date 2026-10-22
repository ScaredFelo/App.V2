import Foundation
import HealthKit
import Combine

class HealthKitManager: ObservableObject {
    @Published var currentBPM: Int = 0
    @Published var isAuthorized: Bool = false
    
    private let healthStore = HKHealthStore()
    private var anchor: HKQueryAnchor?
    
    func solicitarPermisoHealthKit() {
        guard HKHealthStore.isHealthDataAvailable() else {
            print("HealthKit no está disponible en este dispositivo.")
            return
        }
        
        guard let heartRateType = HKObjectType.quantityType(forIdentifier: .heartRate) else { return }
        let workoutType = HKObjectType.workoutType()
        
        let typesToRead: Set<HKObjectType> = [heartRateType]
        let typesToShare: Set<HKSampleType> = [workoutType]
        
        healthStore.requestAuthorization(toShare: typesToShare, read: typesToRead) { [weak self] success, error in
            DispatchQueue.main.async {
                if let error = error {
                    print("Error al solicitar autorización de HealthKit: \(error.localizedDescription)")
                    self?.isAuthorized = false
                } else {
                    self?.isAuthorized = success
                    if success {
                        self?.iniciarObservacionBPM()
                    }
                }
            }
        }
    }
    
    func iniciarObservacionBPM() {
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
        guard let quantitySamples = samples as? [HKQuantitySample], let lastSample = quantitySamples.last else { return }
        
        let unit = HKUnit.count().unitDivided(by: HKUnit.minute())
        let bpm = Int(lastSample.quantity.doubleValue(for: unit))
        
        DispatchQueue.main.async {
            if bpm > 0 {
                self.currentBPM = bpm
            }
        }
    }
    
    func obtenerUltimoBPM() {
        guard let heartRateType = HKObjectType.quantityType(forIdentifier: .heartRate) else { return }
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)
        
        let query = HKSampleQuery(sampleType: heartRateType, predicate: nil, limit: 1, sortDescriptors: [sortDescriptor]) { [weak self] _, results, _ in
            guard let sample = results?.first as? HKQuantitySample else { return }
            let unit = HKUnit.count().unitDivided(by: HKUnit.minute())
            let bpm = Int(sample.quantity.doubleValue(for: unit))
            
            DispatchQueue.main.async {
                if bpm > 0 {
                    self?.currentBPM = bpm
                }
            }
        }
        healthStore.execute(query)
    }
}
