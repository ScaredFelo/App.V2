import SwiftUI

struct SettingsView: View {
    @AppStorage(UserSettingsManager.multipowerBarWeightKey) private var multipowerBarWeight = UserSettingsManager.defaultBarWeight
    @AppStorage(UserSettingsManager.availablePlatesKey) private var availablePlatesRaw = UserSettingsManager.defaultAvailablePlates
    @AppStorage(UserSettingsManager.isBigPictureModeEnabledKey) private var isBigPictureModeEnabled = false

    private var availablePlates: [Double] {
        UserSettingsManager.parsePlates(availablePlatesRaw)
    }

    var body: some View {
        Form {
            Section {
                HStack {
                    Text("Peso de la barra")
                    Spacer()
                    TextField("0", value: $multipowerBarWeight, format: .number)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 80)
                    Text("kg")
                        .foregroundStyle(.secondary)
                }

                Stepper(
                    "Ajustar barra: \(UserSettingsManager.formatted(multipowerBarWeight)) kg",
                    value: $multipowerBarWeight,
                    in: 0...100,
                    step: 0.5
                )
            } header: {
                Text("Barra / Multipower")
            } footer: {
                Text("Peso de la barra que usas en multipower.")
            }

            Section {
                ForEach(UserSettingsManager.plateOptions, id: \.self) { plate in
                    Toggle(isOn: plateBinding(for: plate)) {
                        Text("\(UserSettingsManager.formatted(plate)) kg")
                    }
                }
            } header: {
                Text("Discos disponibles")
            } footer: {
                Text("Selecciona los discos de los que dispones.")
            }

            Section {
                Toggle(isOn: $isBigPictureModeEnabled) {
                    Label("BIG PICTURE", systemImage: "textformat.size")
                }
                .tint(.green)
            } header: {
                Text("Modo visual")
            } footer: {
                Text("Aumenta la tipografía y el contraste durante el entrenamiento activo.")
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.black)
        .preferredColorScheme(.dark)
        .tint(.green)
        .navigationTitle("Configuración")
        .withKeyboardDismiss()
    }

    private func plateBinding(for plate: Double) -> Binding<Bool> {
        Binding(
            get: { availablePlates.contains(plate) },
            set: { isEnabled in
                var plates = Set(availablePlates)
                if isEnabled {
                    plates.insert(plate)
                } else {
                    plates.remove(plate)
                }
                availablePlatesRaw = UserSettingsManager.serializePlates(plates)
            }
        )
    }
}
