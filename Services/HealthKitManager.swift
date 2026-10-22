import Foundation
import HealthKit
import Combine

final class HealthKitManager: ObservableObject {
    @Published var currentBPM: Int = 0
    @Published var isAuthorized: Bool = false

    private let healthStore = HKHealthStore()
    private var anchor: HKQueryAnchor?
    private var isQueryRunning = false

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
                    self?.startLiveHeartRateQuery()
                }
                completion(success)
            }
        }
    }

    func startLiveHeartRateQuery() {
        guard !isQueryRunning else { return }
        guard let heartRateType = HKObjectType.quantityType(forIdentifier: .heartRate) else { return }
        isQueryRunning = true

        let samplePredicate = HKQuery.predicateForSamples(
            withStart: Date().addingTimeInterval(-3600),
            end: nil,
            options: .strictStartDate
        )

        let query = HKAnchoredObjectQuery(
            type: heartRateType,
            predicate: samplePredicate,
            anchor: anchor,
            limit: HKObjectQueryNoLimit
        ) { [weak self] _, samples, _, newAnchor, _ in
            self?.anchor = newAnchor
            self?.processHeartRateSamples(samples)
        }

        query.updateHandler = { [weak self] _, samples, _, newAnchor, _ in
            self?.anchor = newAnchor
            self?.processHeartRateSamples(samples)
        }

        healthStore.execute(query)
    }

    private func processHeartRateSamples(_ samples: [HKSample]?) {
        guard let quantitySamples = samples as? [HKQuantitySample],
              let latestSample = quantitySamples.max(by: { $0.startDate < $1.startDate }) else { return }

        let unit = HKUnit.count().unitDivided(by: HKUnit.minute())
        let bpm = Int(latestSample.quantity.doubleValue(for: unit))

        DispatchQueue.main.async {
            if bpm > 0 {
                self.currentBPM = bpm
            }
        }
    }
}
