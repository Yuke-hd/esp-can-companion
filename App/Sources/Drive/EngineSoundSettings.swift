import SwiftUI

/// Drive owns these preferences; the engine choice remains LS until GH-96.
struct EngineSoundSettings: View {
    @Binding var isEnabled: Bool
    @Binding var lowersOtherAudio: Bool
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Toggle("Engine sound", isOn: $isEnabled)
                    .accessibilityIdentifier("engineSound.enabled")
                LabeledContent("Engine", value: "LS V8")
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("engineSound.engine")
                Toggle(isOn: $lowersOtherAudio) {
                    Text("Lower other audio while playing")
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityIdentifier("engineSound.lowersOtherAudio")
            }
            .accessibilityIdentifier("engineSound.form")
            .navigationTitle("Engine sound")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .accessibilityIdentifier("engineSound.done")
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationCompactAdaptation(.sheet)
    }
}
