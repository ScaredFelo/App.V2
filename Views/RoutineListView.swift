import Foundation
import SwiftUI
import SwiftData

public struct RoutineListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: [SortDescriptor(\Routine.sortOrder), SortDescriptor(\Routine.name)])
    private var routines: [Routine]

    @State private var activeSession: WorkoutSession? = nil
    @State private var selectedRoutineForWorkout: Routine? = nil
    @State private var routineToEdit: Routine? = nil
    @State private var isCreatingNewRoutine = false
    @State private var isSelecting = false
    @State private var selectedRoutineIDs: Set<UUID> = []
    @State private var showingDeleteConfirmation = false

    private var selectionTitle: String {
        selectedRoutineIDs.count == 1 ? "1 seleccionada" : "\(selectedRoutineIDs.count) seleccionadas"
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                List {
                    ForEach(routines) { routine in
                        RoutineRowView(
                            routine: routine,
                            isSelecting: isSelecting,
                            isSelected: selectedRoutineIDs.contains(routine.id),
                            onStart: { startWorkout(with: routine) },
                            onEdit: {
                                guard !isSelecting else { return }
                                isCreatingNewRoutine = false
                                routineToEdit = routine
                            },
                            onToggleSelection: { toggleSelection(for: routine) },
                            onLongPress: { enterSelectionMode(with: routine) },
                            canMoveUp: canMoveUp(routine),
                            canMoveDown: canMoveDown(routine),
                            onMoveUp: { moveRoutine(routine, offset: -1) },
                            onMoveDown: { moveRoutine(routine, offset: 1) }
                        )
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
            .navigationTitle(isSelecting ? selectionTitle : "Rutinas")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if isSelecting {
                        Button("Cancelar") {
                            exitSelectionMode()
                        }
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    if isSelecting {
                        Button(role: .destructive) {
                            showingDeleteConfirmation = true
                        } label: {
                            Label("Eliminar seleccionadas", systemImage: "trash")
                        }
                        .tint(.red)
                        .disabled(selectedRoutineIDs.isEmpty)
                    } else {
                        Button(action: createRoutine) {
                            Image(systemName: "plus")
                                .font(.headline)
                                .foregroundStyle(.white)
                        }
                        .accessibilityLabel("Nueva rutina")
                    }
                }
            }
            .fullScreenCover(item: $activeSession, onDismiss: {
                selectedRoutineForWorkout = nil
                routineToEdit = nil
            }) { session in
                if let routine = selectedRoutineForWorkout {
                    ActiveWorkoutView(session: session, routine: routine, modelContext: modelContext)
                }
            }
            .sheet(item: $routineToEdit, onDismiss: {
                routineToEdit = nil
                isCreatingNewRoutine = false
            }) { routine in
                NavigationStack {
                    EditRoutineView(routine: routine, isNewRoutine: isCreatingNewRoutine)
                }
            }
            .alert("Eliminar rutinas", isPresented: $showingDeleteConfirmation) {
                Button("Eliminar", role: .destructive) {
                    deleteSelectedRoutines()
                }
                Button("Cancelar", role: .cancel) {}
            } message: {
                Text("Se eliminarán las rutinas seleccionadas y sus ejercicios configurados. Esta acción no se puede deshacer.")
            }
        }
    }

    private func startWorkout(with routine: Routine) {
        guard !isSelecting else { return }

        routineToEdit = nil
        let session = WorkoutSession(startDate: Date(), totalVolumeKg: 0.0)
        modelContext.insert(session)
        try? modelContext.save()
        selectedRoutineForWorkout = routine
        activeSession = session
    }

    private func createRoutine() {
        guard !isSelecting else { return }

        let nextOrder = (routines.map(\.sortOrder).max() ?? -1) + 1
        let routine = Routine(name: "Nueva rutina", isTemplate: true, sortOrder: nextOrder, exercises: [])
        isCreatingNewRoutine = true
        routineToEdit = routine
    }

    private func canMoveUp(_ routine: Routine) -> Bool {
        guard let index = routines.firstIndex(where: { $0.id == routine.id }) else { return false }
        return index > 0
    }

    private func canMoveDown(_ routine: Routine) -> Bool {
        guard let index = routines.firstIndex(where: { $0.id == routine.id }) else { return false }
        return index < routines.count - 1
    }

    private func moveRoutine(_ routine: Routine, offset: Int) {
        var ordered = routines
        guard let index = ordered.firstIndex(where: { $0.id == routine.id }) else { return }

        let targetIndex = index + offset
        guard ordered.indices.contains(targetIndex) else { return }

        withAnimation(.easeInOut(duration: 0.2)) {
            ordered.swapAt(index, targetIndex)
            for (position, item) in ordered.enumerated() {
                item.sortOrder = position
            }
        }
        try? modelContext.save()
    }

    private func enterSelectionMode(with routine: Routine) {
        if !isSelecting {
            withAnimation(.easeInOut(duration: 0.2)) {
                isSelecting = true
            }
        }
        selectedRoutineIDs.insert(routine.id)
    }

    private func toggleSelection(for routine: Routine) {
        if selectedRoutineIDs.contains(routine.id) {
            selectedRoutineIDs.remove(routine.id)
        } else {
            selectedRoutineIDs.insert(routine.id)
        }
    }

    private func exitSelectionMode() {
        withAnimation(.easeInOut(duration: 0.2)) {
            isSelecting = false
        }
        selectedRoutineIDs.removeAll()
    }

    private func deleteSelectedRoutines() {
        let idsToDelete = selectedRoutineIDs

        for routine in routines where idsToDelete.contains(routine.id) {
            modelContext.delete(routine)
        }

        let remaining = routines.filter { !idsToDelete.contains($0.id) }
        for (index, routine) in remaining.enumerated() {
            routine.sortOrder = index
        }

        try? modelContext.save()
        exitSelectionMode()
    }
}

struct RoutineRowView: View {
    let routine: Routine
    let isSelecting: Bool
    let isSelected: Bool
    let onStart: () -> Void
    let onEdit: () -> Void
    let onToggleSelection: () -> Void
    let onLongPress: () -> Void
    let canMoveUp: Bool
    let canMoveDown: Bool
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void

    @State private var suppressNextTap = false

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 12) {
                if isSelecting {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(isSelected ? Color.green : Color.secondary)
                        .transition(.scale.combined(with: .opacity))
                        .accessibilityHidden(true)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(routine.name)
                        .font(.title3.bold())
                        .foregroundStyle(.white)
                    Text("\(routine.exercises.count) ejercicios configurados")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)

                if !isSelecting {
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
            .padding(16)
            .contentShape(Rectangle())
            .onTapGesture {
                guard !suppressNextTap else { return }

                if isSelecting {
                    onToggleSelection()
                } else {
                    onStart()
                }
            }
            .onLongPressGesture(
                minimumDuration: 0.5,
                maximumDistance: 20,
                perform: {
                    suppressNextTap = true
                    onLongPress()
                },
                onPressingChanged: { isPressing in
                    guard !isPressing, suppressNextTap else { return }

                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                        suppressNextTap = false
                    }
                }
            )
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel(
                isSelecting
                    ? (isSelected ? "Deseleccionar \(routine.name)" : "Seleccionar \(routine.name)")
                    : "Iniciar entrenamiento con \(routine.name)"
            )

            if isSelecting {
                if canMoveUp || canMoveDown {
                    VStack(spacing: 6) {
                        if canMoveUp {
                            moveButton(
                                icon: "chevron.up",
                                action: onMoveUp,
                                accessibilityLabel: "Subir \(routine.name)"
                            )
                        }

                        if canMoveDown {
                            moveButton(
                                icon: "chevron.down",
                                action: onMoveDown,
                                accessibilityLabel: "Bajar \(routine.name)"
                            )
                        }
                    }
                    .padding(.trailing, 12)
                }
            } else {
                Button(action: onEdit) {
                    Image(systemName: "pencil")
                        .font(.subheadline.bold())
                        .foregroundStyle(.white)
                        .frame(width: 34, height: 34)
                        .background(Color(.systemGray6).opacity(0.3))
                        .clipShape(Circle())
                }
                .buttonStyle(.borderless)
                .padding(.trailing, 16)
                .accessibilityLabel("Editar rutina \(routine.name)")
            }
        }
        .background(isSelected ? Color.green.opacity(0.14) : Color(.systemGray6).opacity(0.15))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(isSelected ? Color.green.opacity(0.7) : Color.clear, lineWidth: 1)
        )
        .cornerRadius(16)
    }

    private func moveButton(
        icon: String,
        action: @escaping () -> Void,
        accessibilityLabel: String
    ) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.caption.bold())
                .foregroundStyle(.white.opacity(0.8))
                .frame(width: 28, height: 28)
                .background(Color(.systemGray6).opacity(0.3))
                .clipShape(Circle())
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(accessibilityLabel)
    }
}
