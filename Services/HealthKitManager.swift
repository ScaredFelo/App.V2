import Foundation
import HealthKit
import Combine

class HealthKitManager: ObservableObject {
    @Published var currentBPM: Int = 0
    @Published var isAuthorized: Bool = false
    @Published var statusMessage: String = "Iniciando..."
    
    private let healthStore = HKHealthStore()
    
    @available(iOS 26.0, *)
    private final class LiveWorkoutState {
        var session: HKWorkoutSession?
        var builder: HKLiveWorkoutBuilder?
    }
    
    @available(iOS 26.0, *)
    private var liveWorkoutState: LiveWorkoutState?
    
    func solicitarPermisoHealthKit() {
        guard HKHealthStore.isHealthDataAvailable() else {
            DispatchQueue.main.async { self.statusMessage = "HealthKit no disponible" }
            return
        }
        
        guard let heartRateType = HKObjectType.quantityType(forIdentifier: .heartRate) else { return }
        let workoutType = HKObjectType.workoutType()
        
        healthStore.requestAuthorization(toShare: [workoutType], read: [heartRateType]) { [weak self] success, error in
            DispatchQueue.main.async {
                if let error = error {
                    self?.statusMessage = "Error: \(error.localizedDescription)"
                    self?.isAuthorized = false
                } else {
                    self?.isAuthorized = success
                    if success {
                        self?.statusMessage = "Permiso concedido"
                        self?.iniciarWorkoutLiveBuilder()
                    } else {
                        self?.statusMessage = "Permiso denegado en Ajustes > Salud"
                    }
                }
            }
        }
    }
    
    private func iniciarWorkoutLiveBuilder() {
        guard #available(iOS 26.0, *) else {
            iniciarObservacion()
            return
        }
        
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .traditionalStrengthTraining
        configuration.locationType = .indoor
        
        do {
            let session = try HKWorkoutSession(healthStore: healthStore, configuration: configuration)
            let liveBuilder = session.associatedWorkoutBuilder()
            
            let state = LiveWorkoutState()
            state.session = session
            state.builder = liveBuilder
            self.liveWorkoutState = state
            
            liveBuilder.dataSource = HKLiveWorkoutDataSource(healthStore: healthStore, workoutConfiguration: configuration)
            
            session.startActivity(with: Date())
            liveBuilder.beginCollection(withStart: Date()) { [weak self] success, _ in
                if success {
                    self?.iniciarObservacion()
                }
            }
        } catch {
            iniciarObservacion()
        }
    }
    
    private func iniciarObservacion() {
        guard let heartRateType = HKObjectType.quantityType(forIdentifier: .heartRate) else { return }
        
        let query = HKAnchoredObjectQuery(
            type: heartRateType,
            predicate: nil,
            anchor: nil,
            limit: HKObjectQueryNoLimit
        ) { [weak self] _, samples, _, _, _ in
            self?.procesarMuestras(samples)
        }
        
        query.updateHandler = { [weak self] _, samples, _, _, _ in
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
