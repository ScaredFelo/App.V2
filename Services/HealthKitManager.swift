import Foundation
import HealthKit
import Combine

final class HealthKitManager: NSObject, ObservableObject {
    static let shared = HealthKitManager()

    @Published var currentBPM: Int = 0
    @Published private(set) var isAuthorized: Bool = false
    @Published var debugMessage: String = "Pendiente de autorización"
    @Published private(set) var dataSourceName: String = "Buscando..."

    private let healthStore = HKHealthStore()
    private let heartRateType = HKObjectType.quantityType(forIdentifier: .heartRate)
    private var heartRateQuery: HKAnchoredObjectQuery?
    private var anchor: HKQueryAnchor?
    private var workoutSession: HKWorkoutSession?

    private var bpmUnit: HKUnit {
        HKUnit.count().unitDivided(by: HKUnit.minute())
    }

    private override init() {
        super.init()
    }

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

        let workoutType = HKObjectType.workoutType()

        healthStore.requestAuthorization(toShare: [workoutType], read: [heartRateType]) { [weak self] success, error in
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
                    self.startWorkoutSession()
                    self.startObservingHeartRate()
                } catch {
                    self.isAuthorized = false
                    self.debugMessage = error.localizedDescription
                    print("[HealthKit] Error de autorización: \(error.localizedDescription)")
                }
            }
        }
    }

    // MARK: - Workout Session

    private func startWorkoutSession() {
        guard workoutSession == nil else { return }

        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .traditionalStrengthTraining
        configuration.locationType = .indoor

        do {
            let session = try HKWorkoutSession(healthStore: healthStore, configuration: configuration)
            session.delegate = self
            workoutSession = session
            session.startActivity(with: Date())
            debugMessage = "Sesión de entrenamiento activa"
        } catch {
            debugMessage = error.localizedDescription
            print("[HealthKit] Error al iniciar HKWorkoutSession: \(error.localizedDescription)")
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

// MARK: - HKWorkoutSessionDelegate

extension HealthKitManager: HKWorkoutSessionDelegate {
    func workoutSession(
        _ workoutSession: HKWorkoutSession,
        didChangeTo toState: HKWorkoutSessionState,
        from fromState: HKWorkoutSessionState,
        date: Date
    ) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }

            switch toState {
            case .running:
                self.debugMessage = "Sesión de entrenamiento activa"
            case .ended:
                self.debugMessage = "Sesión de entrenamiento finalizada"
                self.workoutSession = nil
            default:
                break
            }
        }
    }

    func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.debugMessage = error.localizedDescription
            self.workoutSession = nil
            print("[HealthKit] Error en la sesión de entrenamiento: \(error.localizedDescription)")
        }
    }
}
