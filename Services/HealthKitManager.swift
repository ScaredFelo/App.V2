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
    private var latestSampleBPM = 0
    private var latestSampleDate: Date?
    private var bpmHeartbeatCancellable: AnyCancellable?

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

        startBPMHeartbeat()

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
        stopBPMHeartbeat()

        if let query = heartRateQuery {
            healthStore.stop(query)
            heartRateQuery = nil
        }

        if let heartRateType {
            healthStore.disableBackgroundDelivery(for: heartRateType) { _, _ in }
        }

        anchor = nil
        latestSampleBPM = 0
        latestSampleDate = nil
        currentBPM = 0
    }

    // MARK: - Heart Rate Publishing

    private func startBPMHeartbeat() {
        guard bpmHeartbeatCancellable == nil else { return }

        bpmHeartbeatCancellable = Timer.publish(every: 0.25, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.publishLatestBPMIfRecent()
            }
    }

    private func stopBPMHeartbeat() {
        bpmHeartbeatCancellable?.cancel()
        bpmHeartbeatCancellable = nil
    }

    private func publishLatestBPMIfRecent() {
        guard latestSampleBPM > 0, let latestSampleDate else { return }
        guard Date().timeIntervalSince(latestSampleDate) <= 5 else { return }

        publishBPM(latestSampleBPM)
    }

    private func publishBPM(_ bpm: Int) {
        let value = max(0, bpm)

        if currentBPM != value {
            currentBPM = value
        }

        LiveActivityManager.shared.setBPM(value)
    }

    // MARK: - Workout Session

    func startWorkoutSession() {
        wantsWorkoutSession = true
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

        #if compiler(>=6.2)
        guard #available(iOS 26.0, *) else {
            debugMessage = "Workout session nativa disponible desde iOS 26"
            return
        }

        guard HKHealthStore.isHealthDataAvailable() else { return }

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
            session.prepare()
            session.startActivity(with: Date())
            debugMessage = "Sesión de entrenamiento HealthKit activa"
        } catch {
            workoutSession = nil
            debugMessage = "No se pudo iniciar la sesión de entrenamiento: \(error.localizedDescription)"
            print("[HealthKit] Error al iniciar HKWorkoutSession: \(error.localizedDescription)")
        }
        #else
        debugMessage = "Workout session nativa no disponible en este SDK"
        #endif
    }

    func workoutSession(
        _ workoutSession: HKWorkoutSession,
        didChangeTo toState: HKWorkoutSessionState,
        from fromState: HKWorkoutSessionState,
        date: Date
    ) {
        guard toState == .ended || toState == .stopped else { return }

        DispatchQueue.main.async { [weak self] in
            guard let self, self.workoutSession === workoutSession else { return }
            self.workoutSession = nil
        }
    }

    func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        print("[HealthKit] Error en HKWorkoutSession: \(error.localizedDescription)")

        DispatchQueue.main.async { [weak self] in
            guard let self, self.workoutSession === workoutSession else { return }
            self.workoutSession = nil
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

            self.latestSampleBPM = bpm
            self.latestSampleDate = Date()
            self.dataSourceName = sourceName
            self.debugMessage = "Leyendo pulsaciones de \(sourceName)"
            self.publishBPM(bpm)
        }
    }
}
