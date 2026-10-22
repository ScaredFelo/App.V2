import Foundation
import HealthKit
import Combine

class HealthKitManager: ObservableObject {
    @Published var currentBPM: Int = 0
    @Published var isAuthorized: Bool = false
    
    private let healthStore = HKHealthStore()
    
    func solicitarPermisoHealthKit() {
        guard HKHealthStore.isHealthDataAvailable() else {
            print("❌ HealthKit no está disponible en este dispositivo.")
            return
        }
        
        guard let heartRateType = HKObjectType.quantityType(forIdentifier: .heartRate) else { return }
        let workoutType = HKObjectType.workoutType()
        
        print("🚀 Iniciando solicitud explícita de HealthKit al sistema iOS...")
        
        healthStore.requestAuthorization(toShare: [workoutType], read: [heartRateType]) { success, error in
            DispatchQueue.main.async {
                if let error = error {
                    print("❌ Error de permisos HealthKit: \(error.localizedDescription)")
                } else {
                    print("✅ Respuesta de HealthKit: \(success)")
                    self.isAuthorized = success
                }
            }
        }
    }
}
