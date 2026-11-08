import SwiftUI
import SwiftData
import Charts

public struct AnalyticsView: View {
    @Query private var sets: [WorkoutSetLog]
    @Query private var sessions: [WorkoutSession]
    @Query private var exercises: [Exercise]

    @State private var showingPersonalRecords = false
    @State private var showingWorkoutHistory = false

    public var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 24) {
                        // Weekly Volume Chart
                        weeklyVolumeChartSection

                        // Monthly Workout Calendar
                        monthlyCalendarSection

                        // Personal Records (PRs) - desplegable
                        DisclosureGroup("Récords Personales (PRs)", isExpanded: $showingPersonalRecords) {
                            personalRecordsSectionContent
                        }

                        // Workout History & Total Volume - desplegable
                        DisclosureGroup("Historial de Sesiones", isExpanded: $showingWorkoutHistory) {
                            workoutHistorySectionContent
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 20)
                }
            }
            .navigationTitle("Estadísticas")
        }
    }

    // MARK: - Weekly Volume Chart
    private var weeklyVolumeChartSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Volumen de Series (Últimos 7 días)")
                .font(.headline)
                .foregroundStyle(.white)

            let weeklyData = computeWeeklyMuscleVolume()

            if weeklyData.isEmpty {
                Text("No hay suficientes datos esta semana.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(height: 150)
                    .frame(maxWidth: .infinity, alignment: .center)
            } else {
                Chart(weeklyData) { item in
                    BarMark(
                        x: .value("Grupo", item.muscleGroup),
                        y: .value("Series", item.setsCount)
                    )
                    .foregroundStyle(by: .value("Grupo", item.muscleGroup))
                    .cornerRadius(8)
                }
                .chartXAxis {
                    AxisMarks { value in
                        AxisValueLabel()
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .chartYAxis {
                    AxisMarks { value in
                        AxisValueLabel()
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(height: 220)
            }
        }
        .padding(16)
        .background(Color(.systemGray6).opacity(0.1))
        .cornerRadius(16)
    }

    struct MuscleVolumeItem: Identifiable {
        let id = UUID()
        let muscleGroup: String
        let setsCount: Int
    }

    private func computeWeeklyMuscleVolume() -> [MuscleVolumeItem] {
        let calendar = Calendar.current
        let oneWeekAgo = calendar.date(byAdding: .day, value: -7, to: Date()) ?? Date()

        // La serie computa en la fecha en la que empezó la rutina, no en la
        // fecha/hora exacta en la que se marcó (puede ser pasada la medianoche).
        let recentSets = sets.filter { setLog in
            guard setLog.isCompleted else { return false }
            let logDate = setLog.workoutStartDate ?? setLog.session?.startDate ?? setLog.date
            return logDate >= oneWeekAgo
        }
        var counts: [String: Int] = [:]

        for setLog in recentSets {
            if let muscle = setLog.exercise?.muscleGroup.rawValue {
                counts[muscle, default: 0] += 1
            }
        }

        return counts.map { MuscleVolumeItem(muscleGroup: $0.key, setsCount: $0.value) }
            .sorted { $0.setsCount > $1.setsCount }
    }

    // MARK: - Monthly Workout Calendar

    /// Calendario mensual con los días del mes actual. Los días en los que se
    /// inició una rutina (`startDate`) se resaltan con un borde circular verde.
    /// La fecha de referencia es exclusivamente `startDate` de cada sesión.
    private var monthlyCalendarSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Calendario de Entrenamientos")
                .font(.headline)
                .foregroundStyle(.white)

            var calendar: Calendar = Calendar.current
            calendar.firstWeekday = 2 // 1 = Domingo, 2 = Lunes
            let now: Date = Date()
            let year: Int = calendar.component(.year, from: now)
            let month: Int = calendar.component(.month, from: now)
            let daysInMonth: Int = calendar.range(of: .day, in: .month, for: now)?.count ?? 0
            let firstOfMonth: Date = calendar.date(
                from: DateComponents(year: year, month: month, day: 1)
            ) ?? now
            let firstWeekday: Int = calendar.component(.weekday, from: firstOfMonth)
            // Con firstWeekday = 2 (Lunes): 1=Domingo, 2=Lunes, ..., 7=Sábado.
            // Offset de celdas vacías para alinear el primer día del mes en su columna de Lunes.
            let weekdayOffset: Int = (firstWeekday - 2 + 7) % 7
            let weekdaySymbols: [String] = ["L", "M", "X", "J", "V", "S", "D"]

            VStack(spacing: 8) {
                // Encabezado de días de la semana (7 columnas)
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7),
                    spacing: 4
                ) {
                    ForEach(weekdaySymbols, id: \.self) { symbol in
                        Text(symbol)
                            .font(.caption2.bold())
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                    }
                }

                // Días del mes
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7),
                    spacing: 4
                ) {
                    // Celdas vacías antes del primer día del mes (alineado a Lunes)
                    ForEach(0 ..< weekdayOffset, id: \.self) { _ in
                        Color.clear
                            .frame(maxWidth: .infinity)
                    }

                    // Días numerados del mes actual
                    ForEach(1 ... daysInMonth, id: \.self) { day in
                        let dayDate: Date = calendar.date(
                            from: DateComponents(year: year, month: month, day: day)
                        ) ?? now
                        let hasWorkout: Bool = sessions.contains { (session: WorkoutSession) -> Bool in
                            calendar.isDate(session.startDate, inSameDayAs: dayDate)
                        }

                        ZStack {
                            Text("\(day)")
                                .font(.caption.bold())
                                .foregroundStyle(hasWorkout ? Color.green : Color.white)
                                .frame(maxWidth: .infinity)

                            if hasWorkout {
                                Circle()
                                    .stroke(Color.green, lineWidth: 2)
                                    .padding(2)
                            }
                        }
                        .frame(height: 32)
                    }
                }
            }
        }
        .padding(16)
        .background(Color(.systemGray6).opacity(0.1))
        .cornerRadius(16)
    }

    // MARK: - Personal Records (PRs) - contenido (sin título, va dentro del DisclosureGroup)
    private var personalRecordsSectionContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            if exercises.isEmpty {
                Text("Sin ejercicios registrados.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 12) {
                    ForEach(exercises) { exercise in
                        let pr = computePR(for: exercise)
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(exercise.name)
                                    .font(.subheadline.bold())
                                    .foregroundStyle(.white)
                                Text(exercise.muscleGroup.rawValue)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                Text(pr != nil ? "\(String(format: "%.1f", pr!.weight)) kg" : "—")
                                    .font(.subheadline.bold())
                                    .foregroundStyle(.green)
                                Text(pr != nil ? "\(pr!.reps) reps" : "")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(12)
                        .background(Color(.systemGray6).opacity(0.1))
                        .cornerRadius(12)
                    }
                }
            }
        }
    }

    struct PersonalRecord {
        let weight: Double
        let reps: Int
    }

    private func computePR(for exercise: Exercise) -> PersonalRecord? {
        let exerciseLogs = sets.filter { $0.exercise?.id == exercise.id && $0.isCompleted }
        guard let bestLog = exerciseLogs.max(by: { ($0.weight * Double($0.reps)) < ($1.weight * Double($1.reps)) }) else {
            return nil
        }
        return PersonalRecord(weight: bestLog.weight, reps: bestLog.reps)
    }

    // MARK: - Workout History & Total Volume - contenido (sin título, va dentro del DisclosureGroup)
    private var workoutHistorySectionContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            let sortedSessions = sessions.sorted(by: { $0.startDate > $1.startDate })

            if sortedSessions.isEmpty {
                Text("No hay sesiones registradas.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 12) {
                    ForEach(sortedSessions) { session in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(session.startDate, style: .date)
                                    .font(.subheadline.bold())
                                    .foregroundStyle(.white)
                                Text("\(session.setsCompleted.count) series completadas")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text("\(Int(session.totalVolumeKg)) kg vol.")
                                .font(.subheadline.bold())
                                .foregroundStyle(.white)
                        }
                        .padding(12)
                        .background(Color(.systemGray6).opacity(0.1))
                        .cornerRadius(12)
                    }
                }
            }
        }
    }
}
