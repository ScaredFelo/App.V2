import SwiftUI
import WidgetKit
import ActivityKit

struct WorkoutLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: WorkoutActivityAttributes.self) { context in
            // Vista en la pantalla de bloqueo
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(context.attributes.workoutName.uppercased())
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundStyle(.secondary)
                    
                    Text(context.state.exerciseName)
                        .font(.headline)
                    
                    HStack(spacing: 12) {
                        Label("\(context.state.currentBPM > 0 ? "\(context.state.currentBPM)" : "--") BPM", systemImage: "heart.fill")
                            .font(.caption)
                            .foregroundStyle(.red)
                        
                        Label(title: {
                            Text(context.state.sessionStartDate, style: .timer)
                                .font(.caption)
                                .monospacedDigit()
                        }, icon: {
                            Image(systemName: "clock")
                                .font(.caption)
                        })
                        .foregroundStyle(.secondary)
                    }
                }
                
                Spacer()
                
                // Anillo de progreso / cuenta atrás
                ProgressView(timerInterval: Date()...context.state.timerEndDate, countsDown: true) {
                    EmptyView()
                } currentValueLabel: {
                    Text(context.state.timerEndDate, style: .timer)
                        .font(.title3)
                        .bold()
                        .monospacedDigit()
                }
                .progressViewStyle(.circular)
                .tint(.green)
            }
            .padding()
            .activityBackgroundTint(Color.black.opacity(0.8))
            
        } dynamicIsland: { context in
            DynamicIsland {
                // Estado Expandido (manteniendo pulsada la Dynamic Island)
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(context.state.exerciseName)
                            .font(.headline)
                        
                        HStack(spacing: 8) {
                            HStack(spacing: 4) {
                                Image(systemName: "heart.fill")
                                    .foregroundStyle(.red)
                                Text(context.state.currentBPM > 0 ? "\(context.state.currentBPM) BPM" : "--")
                            }
                            .font(.caption)
                            .bold()
                            
                            Text("•")
                                .foregroundStyle(.secondary)
                            
                            HStack(spacing: 4) {
                                Image(systemName: "clock")
                                Text(context.state.sessionStartDate, style: .timer)
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                        }
                    }
                }
                
                DynamicIslandExpandedRegion(.trailing) {
                    ProgressView(timerInterval: Date()...context.state.timerEndDate, countsDown: true) {
                        EmptyView()
                    } currentValueLabel: {
                        Text(context.state.timerEndDate, style: .timer)
                            .font(.title2)
                            .bold()
                            .monospacedDigit()
                    }
                    .progressViewStyle(.circular)
                    .tint(.green)
                }
                
            } compactLeading: {
                // Modo Compacto Izquierda
                HStack(spacing: 4) {
                    Image(systemName: "heart.fill")
                        .foregroundStyle(.red)
                        .font(.caption2)
                    Text(context.state.currentBPM > 0 ? "\(context.state.currentBPM)" : "--")
                        .font(.caption2)
                        .bold()
                }
            } compactTrailing: {
                // Modo Compacto Derecha (Anillo de descanso + Tiempo)
                ProgressView(timerInterval: Date()...context.state.timerEndDate, countsDown: true) {
                    EmptyView()
                } currentValueLabel: {
                    Text(context.state.timerEndDate, style: .timer)
                        .font(.system(size: 10, weight: .bold))
                        .monospacedDigit()
                }
                .progressViewStyle(.circular)
                .tint(.green)
                .frame(width: 24, height: 24)
            } minimal: {
                // Modo Minimalista (si hay varias actividades activas)
                ProgressView(timerInterval: Date()...context.state.timerEndDate, countsDown: true) {
                    EmptyView()
                } currentValueLabel: {
                    Image(systemName: "heart.fill")
                        .font(.system(size: 8))
                        .foregroundStyle(.red)
                }
                .progressViewStyle(.circular)
                .tint(.green)
            }
        }
    }
}
