import SwiftUI

struct SensorySettingsView: View {
    @Environment(\.dismiss) private var dismiss

    let controller: SensorySettingsController

    var body: some View {
        NavigationStack {
            Form {
                Section("Feedback") {
                    Toggle(isOn: sfxBinding) {
                        Label("Sound effects", systemImage: "speaker.wave.2.fill")
                    }
                    .frame(minHeight: 44)
                    .accessibilityValue(controller.settings.sfxEnabled ? "On" : "Off")
                    .accessibilityHint("Controls engine, ambience, and event audio.")
                    .accessibilityIdentifier("sensory.sfx")

                    Toggle(isOn: hapticsBinding) {
                        Label("Haptics", systemImage: "iphone.radiowaves.left.and.right")
                    }
                    .frame(minHeight: 44)
                    .accessibilityValue(controller.settings.hapticsEnabled ? "On" : "Off")
                    .accessibilityHint("Controls feedback on both iPhone and Apple Watch.")
                    .accessibilityIdentifier("sensory.haptics")
                }

                Section {
                    balancedIntensityRow
                    reducedIntensityRow
                } header: {
                    Text("Visual effects")
                } footer: {
                    Text(
                        "Reduce Motion and Reduce Transparency in system settings always take priority."
                    )
                }
            }
            .navigationTitle("Sensory Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                    .accessibilityHint("Close sensory settings.")
                }
            }
        }
    }

    private var sfxBinding: Binding<Bool> {
        Binding(
            get: { controller.settings.sfxEnabled },
            set: { isEnabled in
                controller.setSFXEnabled(isEnabled)
            }
        )
    }

    private var hapticsBinding: Binding<Bool> {
        Binding(
            get: { controller.settings.hapticsEnabled },
            set: { isEnabled in
                controller.setHapticsEnabled(isEnabled)
            }
        )
    }

    private var balancedIntensityRow: some View {
        let isSelected = controller.settings.effectIntensity == .balanced
        return Button {
            controller.setEffectIntensity(.balanced)
        } label: {
            intensityRowLabel(title: "Balanced", isSelected: isSelected)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Balanced effects")
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityHint("Set visual effect intensity to Balanced.")
        .accessibilityIdentifier("sensory.effectIntensity.balanced")
    }

    private var reducedIntensityRow: some View {
        let isSelected = controller.settings.effectIntensity == .reduced
        return Button {
            controller.setEffectIntensity(.reduced)
        } label: {
            intensityRowLabel(title: "Reduced", isSelected: isSelected)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Reduced effects")
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityHint("Set visual effect intensity to Reduced.")
        .accessibilityIdentifier("sensory.effectIntensity.reduced")
    }

    private func intensityRowLabel(title: String, isSelected: Bool) -> some View {
        HStack {
            Text(title)
            Spacer()
            if isSelected {
                Image(systemName: "checkmark")
                    .accessibilityHidden(true)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 44)
        .contentShape(Rectangle())
    }
}
