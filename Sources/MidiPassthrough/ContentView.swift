import SwiftUI

struct ContentView: View {
    @StateObject private var midi = MIDIManager()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 10) {
                GridRow {
                    Text("Input").gridColumnAlignment(.trailing)
                    Picker("Input", selection: $midi.selectedInput) {
                        Text("None").tag(Int32?.none)
                        ForEach(midi.inputs + [midi.missingInput].compactMap { $0 }) { device in
                            Text(device.name).tag(Int32?.some(device.id))
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: 225, alignment: .leading)
                }
                GridRow {
                    Text("Output")
                    Picker("Output", selection: $midi.selectedOutput) {
                        Text("None").tag(Int32?.none)
                        ForEach(midi.outputs + [midi.missingOutput].compactMap { $0 }) { device in
                            Text(device.name).tag(Int32?.some(device.id))
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: 225, alignment: .leading)
                }
            }
            .padding(.leading, 10)
            .frame(maxWidth: .infinity, alignment: .leading)

            GroupBox("Pass Through") {
                HStack(spacing: 16) {
                    Toggle("Notes", isOn: $midi.passNotes)
                    Toggle("Clock", isOn: $midi.passClock)
                    Toggle("CC", isOn: $midi.passCC)
                    Toggle("PC", isOn: $midi.passPC)
                    Spacer()
                }
                .padding(4)
            }

            GroupBox("Channel Activity") {
                VStack(spacing: 10) {
                    ForEach(0..<2, id: \.self) { row in
                        HStack(spacing: 10) {
                            ForEach(row * 8..<row * 8 + 8, id: \.self) { channel in
                                VStack(spacing: 4) {
                                    Circle()
                                        .fill(midi.active[channel] ? Color.green : Color.secondary.opacity(0.25))
                                        .frame(width: 12, height: 12)
                                    Text("\(channel + 1)")
                                        .font(.caption2.monospacedDigit())
                                        .foregroundStyle(.secondary)
                                }
                                .frame(maxWidth: .infinity)
                                .accessibilityElement(children: .ignore)
                                .accessibilityLabel("Channel \(channel + 1)")
                                .accessibilityValue(midi.active[channel] ? "Active" : "Inactive")
                            }
                        }
                    }
                }
                .padding(4)
            }
        }
        .padding(20)
        .frame(width: 340)
    }
}
