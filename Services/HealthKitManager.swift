import Foundation
import HealthKit
import Combine

final class HealthKitManager: NSObject, ObservableObject, HKWorkoutSessionDelegate {
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
    private var wantsWorkoutSession = false
    private var workoutSessionRetryCount = 0
    private static let maxWorkoutSessionRetries = 10

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

                    if self.wantsWorkoutSession {
                        self.startWorkoutSessionIfAvailable()
                    }
                } catch {
                    self.isAuthorized = false
                    self.debugMessage = error.localizedDescription
                    print("[HealthKit] Error de autorización: \(error.localizedDescription)")
                }
            }
        }
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
        if let query = heartRateQuery {
            healthStore.stop(query)
            heartRateQuery = nil
        }

        if let heartRateType {
            healthStore.disableBackgroundDelivery(for: heartRateType) { _, _ in }
        }

        anchor = nil
        currentBPM = 0
    }

    // MARK: - Workout Session

    func startWorkoutSession() {
        wantsWorkoutSession = true
        workoutSessionRetryCount = 0
        startWorkoutSessionIfAvailable()
    }

    func stopWorkoutSession() {
        wantsWorkoutSession = false

        guard let session = workoutSession else { return }

        session.stopActivity(with: Date())
        session.end()
        workoutSession = nil
    }

    private func startWorkoutSessionIfAvailable() {
        guard wantsWorkoutSession, workoutSession == nil else { return }
        guard HKHealthStore.isHealthDataAvailable() else { return }

        // La creación de sesiones de entrenamiento desde el iPhone solo está
        // disponible a partir de iOS 26. En versiones anteriores no hay forma
        // de mantener una HKWorkoutSession propia, así que no reintentamos.
        guard #available(iOS 26.0, *) else {
            wantsWorkoutSession = false
            debugMessage = "La sesión nativa de entrenamiento requiere iOS 26 o superior"
            return
        }

        #if compiler(>=6.2)
        do {
            let configuration = HKWorkoutConfiguration()
            configuration.activityType = .traditionalStrengthTraining
            configuration.locationType = .unknown

            let session = try HKWorkoutSession(
                healthStore: healthStore,
                configuration: configuration
            )
            session.delegate = self
            workoutSession = session
            workoutSessionRetryCount = 0
            session.prepare()
            session.startActivity(with: Date())
            debugMessage = "Sesión de entrenamiento HealthKit activa"
        } catch {
            workoutSession = nil
            debugMessage = "No se pudo iniciar la sesión de entrenamiento: \(error.localizedDescription)"
            print("[HealthKit] Error al iniciar HKWorkoutSession: \(error.localizedDescription)")
            scheduleWorkoutSessionRetry()
        }
        #else
        wantsWorkoutSession = false
        debugMessage = "La sesión de entrenamiento nativa no está disponible en este SDK"
        #endif
    }

    /// Mantiene la sesión de HealthKit viva durante todo el entrenamiento.
    /// Si iOS la finaliza o falla, la recreamos mientras el entrenamiento siga activo.
    private func scheduleWorkoutSessionRetry() {
        guard wantsWorkoutSession, workoutSessionRetryCount < Self.maxWorkoutSessionRetries else { return }

        workoutSessionRetryCount += 1
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            guard let self, self.wantsWorkoutSession, self.workoutSession == nil else { return }
            self.startWorkoutSessionIfAvailable()
        }
    }

    func workoutSession(
        _ workoutSession: HKWorkoutSession,
        didChangeTo toState: HKWorkoutSessionState,
        from fromState: HKWorkoutSessionState,
        date: Date
    ) {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.workoutSession === workoutSession else { return }

            switch toState {
            case .ended, .stopped:
                self.workoutSession = nil
                if self.wantsWorkoutSession {
                    self.scheduleWorkoutSessionRetry()
                }
            default:
                break
            }
        }
    }

    func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        print("[HealthKit] Error en HKWorkoutSession: \(error.localizedDescription)")

        DispatchQueue.main.async { [weak self] in
            guard let self, self.workoutSession === workoutSession else { return }
            self.workoutSession = nil
            self.debugMessage = "Sesión de entrenamiento interrumpida; reintentando..."
            self.scheduleWorkoutSessionRetry()
        }
    }

    private func handleHeartRateSamples(_ samples: [HKSample]?, newAnchor: HKQueryAnchor?, error: Error?) {
        if let error {
            print("HealthKit error leyendo frecuencia cardíaca: \(error.localizedDescription)")
            return
        }

        let latestSample = (samples as? [HKQuantitySample])?
            .max(by: { $0.endDate < $1.endDate })

        let bpm = latestSample.map {
            Int($0.quantity.doubleValue(for: bpmUnit).rounded())
        }
        let sourceName = latestSample?.sourceRevision.source.name

        DispatchQueue.main.async { [weak self] in
            guard let self, self.heartRateQuery != nil else { return }

            self.anchor = newAnchor

            guard let bpm, bpm > 0, let sourceName else { return }

            self.currentBPM = bpm
            self.dataSourceName = sourceName
            self.debugMessage = "Leyendo pulsaciones de \(sourceName)"
            LiveActivityManager.shared.setBPM(bpm)
        }
    }
}
