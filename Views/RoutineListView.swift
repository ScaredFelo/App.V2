import SwiftUI
import SwiftData

public struct RoutineListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Routine.name) private var routines: [Routine]

    @State private var activeSession: WorkoutSession? = nil
    @State private var selectedRoutineForWorkout: Routine? = nil
    @State private var routineToEdit: Routine? = nil

    public var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                List {
                    ForEach(routines) { routine in
                        RoutineRowView(
                            routine: routine,
                            onStart: { startWorkout(with: routine) },
                            onEdit: { routineToEdit = routine }
                        )
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Rutinas")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: createRoutine) {
                        Image(systemName: "plus")
                            .font(.headline)
                            .foregroundStyle(.white)
                    }
                    .accessibilityLabel("Nueva rutina")
                }
            }
            .fullScreenCover(item: $activeSession) { session in
                if let routine = selectedRoutineForWorkout {
                    ActiveWorkoutView(session: session, routine: routine, modelContext: modelContext)
                }
            }
            .sheet(item: $routineToEdit) { routine in
                NavigationStack {
                    EditRoutineView(routine: routine)
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

    private func createRoutine() {
        let routine = Routine(name: "Nueva rutina", isTemplate: true, exercises: [])
        modelContext.insert(routine)
        try? modelContext.save()
        routineToEdit = routine
    }
}

struct RoutineRowView: View {
    let routine: Routine
    let onStart: () -> Void
    let onEdit: () -> Void

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

                Button(action: onEdit) {
                    Image(systemName: "pencil")
                        .font(.subheadline.bold())
                        .foregroundStyle(.white)
                        .frame(width: 34, height: 34)
                        .background(Color(.systemGray6).opacity(0.3))
                        .clipShape(Circle())
                }
                .accessibilityLabel("Editar rutina")

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
