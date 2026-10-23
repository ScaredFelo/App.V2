import Foundation
import HealthKit
import Combine

final class HealthKitManager: ObservableObject {
    static let shared = HealthKitManager()

    @Published var currentBPM: Int = 0
    @Published private(set) var isAuthorized: Bool = false
    @Published private(set) var dataSourceName: String = "Buscando..."

    private let healthStore = HKHealthStore()
    private let heartRateType = HKObjectType.quantityType(forIdentifier: .heartRate)
    private var heartRateQuery: HKAnchoredObjectQuery?
    private var anchor: HKQueryAnchor?

    private var bpmUnit: HKUnit {
        HKUnit.count().unitDivided(by: HKUnit.minute())
    }

    private init() {}

    // MARK: - Authorization

    func solicitarPermisoHealthKit() {
        requestAuthorization()
    }

    func requestAuthorization() {
        guard HKHealthStore.isHealthDataAvailable(), let heartRateType else {
            DispatchQueue.main.async { [weak self] in
                self?.dataSourceName = "HealthKit no disponible"
            }
            return
        }

        let workoutType = HKObjectType.workoutType()

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }

            self.healthStore.requestAuthorization(toShare: [workoutType], read: [heartRateType]) { [weak self] success, error in
                print("[HealthKit] Autorización completada")

                DispatchQueue.main.async {
                    guard let self else { return }
                    self.isAuthorized = success

                    if let error {
                        self.dataSourceName = "Error de permisos"
                        print("HealthKit error de autorización: \(error.localizedDescription)")
                        return
                    }

                    guard success else {
                        self.dataSourceName = "Permiso denegado"
                        return
                    }

                    self.startObservingHeartRate()
                }
            }
        }
    }

    // MARK: - Heart Rate Observation

    func startObservingHeartRate() {
        guard heartRateQuery == nil, let heartRateType else { return }

        healthStore.enableBackgroundDelivery(for: heartRateType, frequency: .immediate) { success, error in
            if let error {
                print("HealthKit error en background delivery: \(error.localizedDescription)")
            } else if !success {
                print("HealthKit no pudo habilitar background delivery")
            }
        }

        let predicate = HKQuery.predicateForSamples(
            withStart: Date().addingTimeInterval(-120),
            end: nil,
            options: .strictStartDate
        )

        let query = HKAnchoredObjectQuery(
            type: heartRateType,
            predicate: predicate,
            anchor: anchor,
            limit: HKObjectQueryNoLimit
        ) { [weak self] _, samples, _, newAnchor, error in
            self?.handleHeartRateSamples(samples, newAnchor: newAnchor, error: error)
        }

        query.updateHandler = { [weak self] _, samples, _, newAnchor, error in
            self?.handleHeartRateSamples(samples, newAnchor: newAnchor, error: error)
        }

        heartRateQuery = query
        healthStore.execute(query)
    }

    private func handleHeartRateSamples(_ samples: [HKSample]?, newAnchor: HKQueryAnchor?, error: Error?) {
        if let error {
            print("HealthKit error leyendo frecuencia cardíaca: \(error.localizedDescription)")
            return
        }

        anchor = newAnchor
        guard let quantitySamples = samples as? [HKQuantitySample],
              let latestSample = quantitySamples.max(by: { $0.endDate < $1.endDate }) else {
            return
        }

        let bpm = Int(latestSample.quantity.doubleValue(for: bpmUnit).rounded())
        guard bpm > 0 else { return }

        let sourceName = latestSample.sourceRevision.source.name

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.currentBPM = bpm
            self.dataSourceName = sourceName
        }
    }
}
