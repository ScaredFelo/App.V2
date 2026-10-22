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
            // Vista en Pantalla de Bloqueo / Notificaciones
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(context.attributes.workoutName.uppercased())
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundStyle(.secondary)
                    
                    Text(context.state.exerciseName)
                        .font(.headline)
                        .foregroundStyle(.white)
                    
                    HStack(spacing: 8) {
                        Label("\(context.state.currentBPM > 0 ? "\(context.state.currentBPM)" : "--") BPM", systemImage: "heart.fill")
                            .font(.caption)
                            .foregroundStyle(.red)
                        
                        Text("•")
                            .foregroundStyle(.secondary)
                        
                        Text("Serie \(context.state.currentSet)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                
                Spacer()
                
                // Barra y tiempo de descanso
                VStack(alignment: .trailing, spacing: 6) {
                    Text(context.state.timerEndDate, style: .timer)
                        .font(.title2)
                        .bold()
                        .monospacedDigit()
                        .foregroundStyle(.white)
                    
                    ProgressView(timerInterval: Date()...context.state.timerEndDate, countsDown: true) {
                        EmptyView()
                    }
                    .progressViewStyle(.linear)
                    .tint(.green)
                    .frame(width: 80)
                }
            }
            .padding()
            .activityBackgroundTint(Color.black.opacity(0.85))
            
        } dynamicIsland: { context in
            DynamicIsland {
                // Modo Expandido (mantener pulsada la isla)
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(context.attributes.workoutName.uppercased())
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.secondary)
                        
                        Text(context.state.exerciseName)
                            .font(.headline)
                            .bold()
                            .foregroundStyle(.white)
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
                        
                        Text("Serie \(context.state.currentSet)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 6) {
                        ProgressView(timerInterval: Date()...context.state.timerEndDate, countsDown: true) {
                            EmptyView()
                        }
                        .progressViewStyle(.linear)
                        .tint(.green)
                        
                        HStack {
                            Text("Descanso")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(context.state.timerEndDate, style: .timer)
                                .font(.subheadline)
                                .bold()
                                .monospacedDigit()
                        }
                    }
                    .padding(.top, 4)
                }
                
            } compactLeading: {
                // Modo Compacto Izquierda (Corazón + BPM)
                HStack(spacing: 4) {
                    Image(systemName: "heart.fill")
                        .foregroundStyle(.red)
                        .font(.system(size: 11))
                    Text(context.state.currentBPM > 0 ? "\(context.state.currentBPM)" : "--")
                        .font(.system(size: 12, weight: .bold))
                        .monospacedDigit()
                }
            } compactTrailing: {
                // Modo Compacto Derecha (Barra Lineal + Contador)
                HStack(spacing: 6) {
                    ProgressView(timerInterval: Date()...context.state.timerEndDate, countsDown: true) {
                        EmptyView()
                    }
                    .progressViewStyle(.linear)
                    .tint(.green)
                    .frame(width: 36)
                    
                    Text(context.state.timerEndDate, style: .timer)
                        .font(.system(size: 12, weight: .bold))
                        .monospacedDigit()
                }
            } minimal: {
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
            .keylineTint(.green)
        }
    }
}
