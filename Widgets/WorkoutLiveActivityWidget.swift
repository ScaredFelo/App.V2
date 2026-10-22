import SwiftUI
import WidgetKit
import ActivityKit

@main
struct AppGymWidgetBundle: WidgetBundle {
    var body: some Widget {
        WorkoutLiveActivityWidget()
    }
}

struct WorkoutLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: WorkoutActivityAttributes.self) { context in
            // Vista en Pantalla de Bloqueo
            VStack(spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(context.attributes.workoutName.uppercased())
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                        Text(context.state.isRestFinished ? "Es hora de dar-le" : context.state.exerciseName)
                            .font(.headline)
                            .foregroundStyle(context.state.isRestFinished ? Color.green : Color.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Label("\(context.state.currentBPM > 0 ? "\(context.state.currentBPM)" : "--") BPM", systemImage: "heart.fill")
                            .font(.caption)
                            .bold()
                            .foregroundStyle(.red)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                        Text("Serie \(context.state.currentSet)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                
                // Barra de progreso sin etiquetas duplicadas
                if context.state.isRestFinished {
                    Text("Es hora de dar-le")
                        .font(.headline)
                        .bold()
                        .foregroundStyle(.green)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    VStack(spacing: 4) {
                        ProgressView(timerInterval: context.state.timerStartDate...context.state.timerEndDate, countsDown: true, label: { EmptyView() }, currentValueLabel: { EmptyView() })
                            .progressViewStyle(.linear)
                            .tint(.green)

                        HStack {
                            Text("Descanso")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                            Spacer()
                            Text(context.state.timerEndDate, style: .timer)
                                .font(.caption)
                                .bold()
                                .monospacedDigit()
                                .foregroundStyle(.green)
                                .lineLimit(1)
                                .minimumScaleFactor(0.75)
                        }
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .activityBackgroundTint(Color.black.opacity(0.85))
            
        } dynamicIsland: { context in
            DynamicIsland {
                // Modo Expandido (mantener pulsada la isla)
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(context.attributes.workoutName.uppercased())
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                        Text(context.state.isRestFinished ? "Es hora de dar-le" : context.state.exerciseName)
                            .font(.headline)
                            .bold()
                            .foregroundStyle(context.state.isRestFinished ? Color.green : Color.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                    }
                }
                
                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 2) {
                        HStack(spacing: 4) {
                            Image(systemName: "heart.fill")
                                .foregroundStyle(.red)
                            Text(context.state.currentBPM > 0 ? "\(context.state.currentBPM) BPM" : "-- BPM")
                        }
                        .font(.subheadline)
                        .bold()
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        Text("Serie \(context.state.currentSet)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                    }
                }
                
                DynamicIslandExpandedRegion(.bottom) {
                    if context.state.isRestFinished {
                        Text("Es hora de dar-le")
                            .font(.headline)
                            .bold()
                            .foregroundStyle(.green)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 2)
                    } else {
                        VStack(spacing: 4) {
                            // Ocultamos las etiquetas internas de ProgressView para no duplicar números
                            ProgressView(timerInterval: context.state.timerStartDate...context.state.timerEndDate, countsDown: true, label: { EmptyView() }, currentValueLabel: { EmptyView() })
                                .progressViewStyle(.linear)
                                .tint(.green)

                            HStack {
                                Text("Descanso restante")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.75)
                                Spacer()
                                Text(context.state.timerEndDate, style: .timer)
                                    .font(.subheadline)
                                    .bold()
                                    .monospacedDigit()
                                    .foregroundStyle(.green)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.75)
                            }
                        }
                        .padding(.top, 2)
                    }
                }
                
            } compactLeading: {
                if context.state.isRestFinished {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.system(size: 13))
                } else {
                    // Modo Compacto Izquierda (Corazón + BPM)
                    HStack(spacing: 4) {
                        Image(systemName: "heart.fill")
                            .foregroundStyle(.red)
                            .font(.system(size: 11))
                        Text(context.state.currentBPM > 0 ? "\(context.state.currentBPM)" : "--")
                            .font(.system(size: 12, weight: .bold))
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                    }
                }
            } compactTrailing: {
                if context.state.isRestFinished {
                    Text("Es hora de dar-le")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.green)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                } else {
                    // Modo Compacto Derecha (Barra centrada y alineada + un único temporizador)
                    HStack(spacing: 6) {
                        ProgressView(timerInterval: context.state.timerStartDate...context.state.timerEndDate, countsDown: true, label: { EmptyView() }, currentValueLabel: { EmptyView() })
                            .progressViewStyle(.linear)
                            .tint(.green)
                            .frame(width: 38)

                        Text(context.state.timerEndDate, style: .timer)
                            .font(.system(size: 12, weight: .bold))
                            .monospacedDigit()
                            .foregroundStyle(.green)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                    }
                }
            } minimal: {
                if context.state.isRestFinished {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.green)
                } else {
                    ProgressView(timerInterval: context.state.timerStartDate...context.state.timerEndDate, countsDown: true, label: { EmptyView() }, currentValueLabel: { EmptyView() })
                        .progressViewStyle(.linear)
                        .tint(.green)
                        .frame(width: 18)
                }
            }
        }
    }
}
