import Foundation
import HealthKit
import Combine

class HealthKitManager: ObservableObject {
    @Published var currentBPM: Int = 0
    @Published var isAuthorized: Bool = false
    @Published var dataSourceName: String = "Buscando..."
    
    private let healthStore = HKHealthStore()
    private var activeWorkoutBuilder: HKWorkoutBuilder?
    private var anchor: HKQueryAnchor?
    
    func solicitarPermisoHealthKit() {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        
        guard let heartRateType = HKObjectType.quantityType(forIdentifier: .heartRate) else { return }
        let workoutType = HKObjectType.workoutType()
        
        healthStore.requestAuthorization(toShare: [workoutType], read: [heartRateType]) { [weak self] success, error in
            DispatchQueue.main.async {
                self?.isAuthorized = success
                if success {
                    self?.iniciarSesioniOS()
                }
            }
        }
    }
    
    private func iniciarSesioniOS() {
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .traditionalStrengthTraining
        configuration.locationType = .indoor
        
        // HKWorkoutBuilder local para iOS 17+ (compatible con compilación iPhone)
        let builder = HKWorkoutBuilder(healthStore: healthStore, configuration: configuration, device: .local())
        self.activeWorkoutBuilder = builder
        
        builder.beginCollection(withStart: Date()) { [weak self] success, _ in
            if success {
                self?.iniciarObservacion()
            }
        }
    }
    
    private func iniciarObservacion() {
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
        guard let quantitySamples = samples as? [HKQuantitySample] else { return }
        
        // Priorizar lecturas de los AirPods si están presentes
        let airPodsSample = quantitySamples.last(where: { $0.sourceRevision.source.name.localizedCaseInsensitiveContains("AirPods") })
        let sampleToUse = airPodsSample ?? quantitySamples.last
        
        guard let finalSample = sampleToUse else { return }
        
        let unit = HKUnit.count().unitDivided(by: HKUnit.minute())
        let bpm = Int(finalSample.quantity.doubleValue(for: unit))
        let name = finalSample.sourceRevision.source.name
        
        DispatchQueue.main.async {
            if bpm > 0 {
                self.currentBPM = bpm
                self.dataSourceName = name
            }
        }
    }
}
