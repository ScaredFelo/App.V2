import SwiftUI
import SwiftData
import Charts

public struct AnalyticsView: View {
    @Query private var sets: [WorkoutSetLog]
    @Query private var sessions: [WorkoutSession]
    @Query private var exercises: [Exercise]

    public var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 24) {
                        // Weekly Volume Chart
                        weeklyVolumeChartSection

                        // Personal Records (PRs)
                        personalRecordsSection

                        // Workout History & Total Volume
                        workoutHistorySection
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

        let recentSets = sets.filter { $0.date >= oneWeekAgo && $0.isCompleted }
        var counts: [String: Int] = [:]

        for setLog in recentSets {
            if let muscle = setLog.exercise?.muscleGroup.rawValue {
                counts[muscle, default: 0] += 1
            }
        }

        return counts.map { MuscleVolumeItem(muscleGroup: $0.key, setsCount: $0.value) }
            .sorted { $0.setsCount > $1.setsCount }
    }

    // MARK: - Personal Records (PRs)
    private var personalRecordsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Récords Personales (PRs)")
                .font(.headline)
                .foregroundStyle(.white)

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
        .padding(16)
        .background(Color(.systemGray6).opacity(0.1))
        .cornerRadius(16)
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

    // MARK: - Workout History & Total Volume
    private var workoutHistorySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Historial de Sesiones")
                .font(.headline)
                .foregroundStyle(.white)

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
        .padding(16)
        .background(Color(.systemGray6).opacity(0.1))
        .cornerRadius(16)
    }
}
