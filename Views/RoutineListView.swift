import Foundation
import SwiftUI
import SwiftData
import UIKit

public struct RoutineListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: [SortDescriptor(\Routine.sortOrder), SortDescriptor(\Routine.name)])
    private var routines: [Routine]

    @State private var activeSession: WorkoutSession? = nil
    @State private var selectedRoutineForWorkout: Routine? = nil
    @State private var routineToEdit: Routine? = nil
    @State private var isCreatingNewRoutine = false
    @State private var isEditing = false
    @State private var routinePendingDeletion: Routine? = nil

    public var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                List {
                    ForEach(routines) { routine in
                        RoutineRowView(
                            routine: routine,
                            isEditing: isEditing,
                            onStart: { startWorkout(with: routine) },
                            onEdit: {
                                guard !isEditing else { return }
                                isCreatingNewRoutine = false
                                routineToEdit = routine
                            },
                            onLongPress: { enterEditMode() },
                            canMoveUp: canMoveUp(routine),
                            canMoveDown: canMoveDown(routine),
                            onMoveUp: { moveRoutine(routine, offset: -1) },
                            onMoveDown: { moveRoutine(routine, offset: 1) },
                            onRequestDelete: { routinePendingDeletion = routine }
                        )
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
            .navigationTitle(isEditing ? "Editar rutinas" : "Rutinas")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if isEditing {
                        Button("Cancelar") {
                            exitEditMode()
                        }
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    if isEditing {
                        Button(action: confirmEditMode) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.headline)
                                .foregroundStyle(.green)
                        }
                        .accessibilityLabel("Confirmar cambios")
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
            .alert(
                "Eliminar rutina",
                isPresented: Binding(
                    get: { routinePendingDeletion != nil },
                    set: { if !$0 { routinePendingDeletion = nil } }
                )
            ) {
                Button("Eliminar", role: .destructive) {
                    if let routine = routinePendingDeletion {
                        deleteRoutine(routine)
                    }
                }
                Button("Cancelar", role: .cancel) {
                    routinePendingDeletion = nil
                }
            } message: {
                Text("Se eliminará \"\(routinePendingDeletion?.name ?? "")\". Esta acción no se puede deshacer.")
            }
        }
    }

    private func startWorkout(with routine: Routine) {
        guard !isEditing else { return }

        routineToEdit = nil
        let session = WorkoutSession(startDate: Date(), totalVolumeKg: 0.0)
        modelContext.insert(session)
        try? modelContext.save()
        selectedRoutineForWorkout = routine
        activeSession = session
    }

    private func createRoutine() {
        guard !isEditing else { return }

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

    private func enterEditMode() {
        guard !isEditing else { return }

        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        withAnimation(.easeInOut(duration: 0.2)) {
            isEditing = true
        }
    }

    private func exitEditMode() {
        withAnimation(.easeInOut(duration: 0.2)) {
            isEditing = false
        }
        routinePendingDeletion = nil
    }

    private func confirmEditMode() {
        try? modelContext.save()
        exitEditMode()
    }

    private func deleteRoutine(_ routine: Routine) {
        modelContext.delete(routine)

        let remaining = routines.filter { $0.id != routine.id }
        for (index, item) in remaining.enumerated() {
            item.sortOrder = index
        }

        try? modelContext.save()
        routinePendingDeletion = nil
    }
}

struct RoutineRowView: View {
    let routine: Routine
    let isEditing: Bool
    let onStart: () -> Void
    let onEdit: () -> Void
    let onLongPress: () -> Void
    let canMoveUp: Bool
    let canMoveDown: Bool
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void
    let onRequestDelete: () -> Void

    @State private var suppressNextTap = false
    @State private var dragOffset: CGFloat = 0
    @State private var thresholdHapticTriggered = false

    private let deleteThreshold: CGFloat = 120
    private let cardBackground = Color(red: 0.07, green: 0.07, blue: 0.08)

    var body: some View {
        ZStack {
            if isEditing {
                deleteBackground
            }

            cardSurface
        }
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .id(routine.id)
        .onChange(of: isEditing) { _, editing in
            if !editing {
                dragOffset = 0
                thresholdHapticTriggered = false
            }
        }
    }

    private var cardSurface: some View {
        HStack(spacing: 8) {
            routineContent
            trailingControls
        }
        .background(cardBackground)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
        .cornerRadius(16)
        .offset(x: dragOffset)
    }

    private var routineContent: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(routine.name)
                    .font(.title3.bold())
                    .foregroundStyle(.white)
                Text("\(routine.exercises.count) ejercicios configurados")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            if !isEditing {
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
            guard !isEditing, !suppressNextTap else { return }
            onStart()
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
        .simultaneousGesture(swipeGesture, including: isEditing ? .all : .none)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(
            isEditing
                ? "Editar \(routine.name)"
                : "Iniciar entrenamiento con \(routine.name)"
        )
    }

    @ViewBuilder
    private var trailingControls: some View {
        if isEditing {
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

    private var deleteBackground: some View {
        ZStack {
            Color.red

            HStack(spacing: 8) {
                Image(systemName: "trash.fill")
                Text("Eliminar")
            }
            .font(.subheadline.bold())
            .foregroundStyle(.white)
            .padding(.horizontal, 20)
            .frame(
                maxWidth: .infinity,
                alignment: dragOffset >= 0 ? .leading : .trailing
            )
        }
    }

    private var swipeGesture: some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { value in
                guard isEditing else { return }
                guard abs(value.translation.width) > abs(value.translation.height) else { return }

                dragOffset = value.translation.width

                if abs(value.translation.width) >= deleteThreshold, !thresholdHapticTriggered {
                    thresholdHapticTriggered = true
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                }
            }
            .onEnded { value in
                guard isEditing else { return }

                let horizontal = value.translation.width
                let isHorizontal = abs(horizontal) > abs(value.translation.height)
                let passedThreshold = isHorizontal && abs(horizontal) >= deleteThreshold

                withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) {
                    dragOffset = 0
                }
                thresholdHapticTriggered = false

                if passedThreshold {
                    onRequestDelete()
                }
            }
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
