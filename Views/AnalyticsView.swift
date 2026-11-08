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

    /// Días del mes actual con su estado de entrenamiento, pre-computados fuera
    /// del ViewBuilder para evitar sentencias no conformes a View.
    /// Genera el mes completo desde el día 1 hasta el último día (28, 30 o 31).
    private var calendarDays: [(dayNumber: Int, hasWorkout: Bool)] {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month], from: Date())
        guard let startOfMonth = calendar.date(from: components),
              let range = calendar.range(of: .day, in: .month, for: startOfMonth) else {
            return []
        }

        return range.map { dayNumber in
            let dayDate: Date = calendar.date(byAdding: .day, value: dayNumber - 1, to: startOfMonth) ?? Date()
            let hasWorkout: Bool = sessions.contains { (session: WorkoutSession) -> Bool in
                calendar.isDate(session.startDate, inSameDayAs: dayDate)
            }
            return (dayNumber: dayNumber, hasWorkout: hasWorkout)
        }
    }

    /// Offset de celdas vacías para alinear el primer día del mes en su columna de Lunes.
    /// Lunes = 0 desfase, Martes = 1, ..., Domingo = 6.
    private var calendarWeekdayOffset: Int {
        var calendar = Calendar.current
        calendar.firstWeekday = 2
        let components = calendar.dateComponents([.year, .month], from: Date())
        guard let startOfMonth = calendar.date(from: components) else { return 0 }

        let firstWeekday = calendar.component(.weekday, from: startOfMonth)
        return (firstWeekday - 2 + 7) % 7
    }

    /// Símbolos de los días de la semana, empezando en Lunes.
    private var calendarWeekdaySymbols: [String] {
        ["L", "M", "X", "J", "V", "S", "D"]
    }

    /// Calendario mensual con los días del mes actual. Los días en los que se
    /// inició una rutina (`startDate`) se resaltan con un borde circular verde.
    /// La fecha de referencia es exclusivamente `startDate` de cada sesión.
    private var monthlyCalendarSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Calendario de Entrenamientos")
                .font(.headline)
                .foregroundStyle(.white)

            VStack(spacing: 8) {
                // Encabezado de días de la semana (7 columnas)
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7),
                    spacing: 4
                ) {
                    ForEach(calendarWeekdaySymbols, id: \.self) { symbol in
                        Text(symbol)
                            .font(.caption2.bold())
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                    }
                }

                // Días del mes (pre-computados fuera del ViewBuilder para evitar
                // sentencias no conformes a View dentro de @ViewBuilder).
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7),
                    spacing: 4
                ) {
                    // Celdas vacías antes del primer día del mes (alineado a Lunes)
                    ForEach(0 ..< calendarWeekdayOffset, id: \.self) { _ in
                        Color.clear
                            .frame(maxWidth: .infinity)
                    }

                    // Días numerados del mes actual
                    ForEach(calendarDays, id: \.dayNumber) { dayInfo in
                        CalendarDayView(
                            dayNumber: dayInfo.dayNumber,
                            hasWorkout: dayInfo.hasWorkout
                        )
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

// MARK: - CalendarDayView (vista auxiliar para un día del calendario mensual)

struct CalendarDayView: View {
    let dayNumber: Int
    let hasWorkout: Bool

    var body: some View {
        ZStack {
            Text("\(dayNumber)")
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

