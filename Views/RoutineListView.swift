import SwiftUI
import SwiftData

public struct RoutineListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Routine.name) private var routines: [Routine]

    @State private var activeSession: WorkoutSession? = nil
    @State private var selectedRoutineForWorkout: Routine? = nil

    public var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                List {
                    ForEach(routines) { routine in
                        RoutineRowView(routine: routine) {
                            startWorkout(with: routine)
                        }
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                    }
                }
                .listStyle(.plain)
            }
            .navigationTitle("Rutinas")
            .fullScreenCover(item: $activeSession) { session in
                if let routine = selectedRoutineForWorkout {
                    ActiveWorkoutView(session: session, routine: routine, modelContext: modelContext)
                }
            }
        }
    }

    private func startWorkout(with routine: Routine) {
        let session = WorkoutSession(startDate: Date(), totalVolumeKg: 0.0)
        modelContext.insert(session)
        try? modelContext.save()
        selectedRoutineForWorkout = routine
        activeSession = session
    }
}

struct RoutineRowView: View {
    let routine: Routine
    let onStart: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(routine.name)
                        .font(.title3.bold())
                        .foregroundStyle(.white)
                    Text("\(routine.exercises.count) ejercicios configurados")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()

                Button(action: onStart) {
                    HStack(spacing: 4) {
                        Image(systemName: "play.fill")
                        Text("Iniciar")
                    }
                    .font(.subheadline.bold())
                    .foregroundColor(.black)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.white)
                    .cornerRadius(20)
                }
            }
        }
        .padding(16)
        .background(Color(.systemGray6).opacity(0.15))
        .cornerRadius(16)
    }
}
