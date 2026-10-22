import SwiftUI

public struct MainTabView: View {
    public init() {}

    public var body: some View {
        TabView {
            NavigationStack {
                RoutineListView()
            }
            .tabItem {
                Label("Rutinas", systemImage: "figure.strengthtraining.traditional")
            }

            NavigationStack {
                ExerciseListView()
            }
            .tabItem {
                Label("Ejercicios", systemImage: "list.bullet")
            }

            NavigationStack {
                AnalyticsView()
            }
            .tabItem {
                Label("Progreso", systemImage: "chart.line.uptrend.xyaxis")
            }
        }
        .tint(.accentColor)
    }
}
