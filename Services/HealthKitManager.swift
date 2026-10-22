import Foundation
import HealthKit
import Combine

final class HealthKitManager: ObservableObject {
    @Published var currentBPM: Int = 0
    @Published var isAuthorized: Bool = false

    private let healthStore = HKHealthStore()
    private var heartRateQuery: HKQuery?

    func requestAuthorization(completion: @escaping (Bool) -> Void) {
        guard HKHealthStore.isHealthDataAvailable() else {
            completion(false)
            return
        }

        guard let heartRateType = HKObjectType.quantityType(forIdentifier: .heartRate) else {
            completion(false)
            return
        }

        healthStore.requestAuthorization(toShare: nil, read: [heartRateType]) { [weak self] success, _ in
            DispatchQueue.main.async {
                self?.isAuthorized = success
                if success {
                    self?.startHeartRateObserver()
                }
                completion(success)
            }
        }
    }

    func startHeartRateObserver() {
        guard let heartRateType = HKObjectType.quantityType(forIdentifier: .heartRate) else { return }

        let query = HKObserverQuery(sampleType: heartRateType, predicate: nil) { [weak self] _, _, error in
            if error == nil {
                self?.fetchLatestHeartRate()
            }
        }

        healthStore.execute(query)
        heartRateQuery = query
        healthStore.enableBackgroundDelivery(for: heartRateType, frequency: .immediate) { _, _ in }
        fetchLatestHeartRate()
    }

    private func fetchLatestHeartRate() {
        guard let heartRateType = HKObjectType.quantityType(forIdentifier: .heartRate) else { return }
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)

        let sampleQuery = HKSampleQuery(sampleType: heartRateType, predicate: nil, limit: 1, sortDescriptors: [sortDescriptor]) { [weak self] _, results, _ in
            guard let sample = results?.first as? HKQuantitySample else { return }
            let unit = HKUnit.count().unitDivided(by: HKUnit.minute())
            let bpm = Int(sample.quantity.doubleValue(for: unit))

            DispatchQueue.main.async {
                if bpm > 0 {
                    self?.currentBPM = bpm
                }
            }
        }
        healthStore.execute(sampleQuery)
    }
}
