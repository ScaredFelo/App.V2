import ActivityKit
import Foundation
import HealthKit
import Combine

final class HealthKitManager: ObservableObject {
    static let shared = HealthKitManager()

    struct LiveActivitySnapshot {
        var exerciseName: String
        var currentSet: Int
        var totalSets: Int
        var timerText: String
        var totalSessionTime: String
    }

    @Published var currentBPM: Int = 0
    @Published private(set) var isAuthorized: Bool = false
    @Published var debugMessage: String = "Pendiente de autorización"
    @Published private(set) var dataSourceName: String = "Buscando..."

    private let healthStore = HKHealthStore()
    private let heartRateType = HKObjectType.quantityType(forIdentifier: .heartRate)
    private var heartRateQuery: HKAnchoredObjectQuery?
    private var anchor: HKQueryAnchor?

    private var liveActivitySnapshot = LiveActivitySnapshot(
        exerciseName: "",
        currentSet: 0,
        totalSets: 0,
        timerText: "0:00",
        totalSessionTime: "0:00"
    )
    private var lastLiveActivityState: WorkoutActivityAttributes.ContentState?
    private var isWorkoutLiveActivityActive = false

    private var bpmUnit: HKUnit {
        HKUnit.count().unitDivided(by: HKUnit.minute())
    }

    private init() {}

    private enum HealthKitRequestError: LocalizedError {
        case healthDataUnavailable
        case heartRateTypeUnavailable

        var errorDescription: String? {
            switch self {
            case .healthDataUnavailable:
                return "HealthKit no está disponible en este dispositivo."
            case .heartRateTypeUnavailable:
                return "No se pudo acceder al tipo de frecuencia cardíaca."
            }
        }
    }

    // MARK: - Authorization

    func solicitarPermisoHealthKit() {
        requestAuthorization()
    }

    func requestAuthorization() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }

            do {
                try self.performAuthorizationRequest()
            } catch {
                self.debugMessage = error.localizedDescription
                print("[HealthKit] Error: \(error.localizedDescription)")
            }
        }
    }

    private func performAuthorizationRequest() throws {
        guard HKHealthStore.isHealthDataAvailable() else {
            throw HealthKitRequestError.healthDataUnavailable
        }

        guard let heartRateType else {
            throw HealthKitRequestError.heartRateTypeUnavailable
        }

        healthStore.requestAuthorization(toShare: [], read: [heartRateType]) { [weak self] success, error in
            print("[HealthKit] Autorización completada")

            DispatchQueue.main.async {
                guard let self else { return }

                do {
                    if let error {
                        throw error
                    }

                    self.isAuthorized = success

                    guard success else {
                        self.debugMessage = "Permisos denegados por el usuario"
                        return
                    }

                    self.debugMessage = "Autorizado. Esperando lecturas de BPM..."
                    self.startHeartRateQuery()
                } catch {
                    self.isAuthorized = false
                    self.debugMessage = error.localizedDescription
                    print("[HealthKit] Error de autorización: \(error.localizedDescription)")
                }
            }
        }
    }

    // MARK: - Live Activity

    func startWorkoutLiveActivity(
        workoutName: String,
        snapshot: LiveActivitySnapshot,
        bpm: Int
    ) {
        liveActivitySnapshot = snapshot
        lastLiveActivityState = nil
        isWorkoutLiveActivityActive = true

        let existingActivities = Activity<WorkoutActivityAttributes>.activities
        if !existingActivities.isEmpty {
            Task {
                for activity in existingActivities {
                    await activity.end(nil, dismissalPolicy: .immediate)
                }
            }
        }

        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        let attributes = WorkoutActivityAttributes(workoutName: workoutName)
        let state = makeLiveActivityState(bpm: bpm)

        do {
            _ = try Activity<WorkoutActivityAttributes>.request(
                attributes: attributes,
                content: ActivityContent(state: state, staleDate: nil),
                pushType: nil
            )
            lastLiveActivityState = state
        } catch {
            print("Error iniciando Live Activity: \(error.localizedDescription)")
        }
    }

    func updateLiveActivitySnapshot(_ snapshot: LiveActivitySnapshot, bpm: Int? = nil) {
        liveActivitySnapshot = snapshot
        pushLiveActivityUpdate(bpm: bpm)
    }

    func endWorkoutLiveActivity() {
        let activities = Activity<WorkoutActivityAttributes>.activities
        lastLiveActivityState = nil
        isWorkoutLiveActivityActive = false
        guard !activities.isEmpty else { return }

        Task {
            for activity in activities {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }
    }

    private func pushLiveActivityUpdate(bpm: Int? = nil) {
        guard isWorkoutLiveActivityActive else { return }
        let activities = Activity<WorkoutActivityAttributes>.activities
        guard !activities.isEmpty else { return }

        let state = makeLiveActivityState(bpm: bpm ?? currentBPM)
        if let lastLiveActivityState, lastLiveActivityState == state { return }
        lastLiveActivityState = state

        Task {
            for activity in activities {
                await activity.update(ActivityContent(state: state, staleDate: nil))
            }
        }
    }

    private func makeLiveActivityState(bpm: Int) -> WorkoutActivityAttributes.ContentState {
        WorkoutActivityAttributes.ContentState(
            exerciseName: liveActivitySnapshot.exerciseName,
            currentSet: liveActivitySnapshot.currentSet,
            totalSets: liveActivitySnapshot.totalSets,
            timerText: liveActivitySnapshot.timerText,
            totalSessionTime: liveActivitySnapshot.totalSessionTime,
            currentBPM: max(0, bpm)
        )
    }

    // MARK: - Heart Rate Query

    func startHeartRateQuery() {
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

    func stopHeartRateQuery() {
        guard let query = heartRateQuery else { return }
        healthStore.stop(query)
        heartRateQuery = nil
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
            self.debugMessage = "Leyendo pulsaciones de \(sourceName)"
            self.pushLiveActivityUpdate(bpm: bpm)
        }
    }
}
