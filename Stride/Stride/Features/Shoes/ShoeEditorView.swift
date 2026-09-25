import SwiftUI
import SwiftData
import StrideKit
import StrideUI

/// Adds a shoe, or edits one.
struct ShoeEditorView: View {
    /// nil to add a new shoe.
    let shoe: Shoe?
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(filter: #Predicate<Shoe> { !$0.isRetired }) private var activeShoes: [Shoe]
    @AppStorage(StrideSettings.unitSystem) private var unit: UnitSystem = .metric

    @State private var name = ""
    @State private var brand = ""
    @State private var colorIndex = 0
    @State private var initialDistance: Double = 0
    /// In the runner's unit.
    @State private var replaceAfter: Double = 800
    /// The rounded value shown when editing; the stored distance is only rewritten if it changes.
    @State private var loadedReplaceAfter: Double?
    @State private var isDefault = false
    @State private var loaded = false

    private var canSave: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name, prompt: Text("Daily trainer"))
                        .textInputAutocapitalization(.words)
                    TextField("Brand and model", text: $brand, prompt: Text("Brand and model"))
                        .textInputAutocapitalization(.words)
                }

                Section("Color") {
                    HStack(spacing: Space.x2) {
                        ForEach(Shoe.colors.indices, id: \.self) { index in
                            Button {
                                colorIndex = index
                            } label: {
                                Circle()
                                    .fill(Shoe.colors[index])
                                    .frame(width: 30, height: 30)
                                    .overlay {
                                        if colorIndex == index {
                                            Circle().strokeBorder(Color.surfaceRaised, lineWidth: 3)
                                            Circle().strokeBorder(Shoe.colors[index], lineWidth: 1)
                                                .padding(-3)
                                        }
                                    }
                                    .frame(maxWidth: .infinity, minHeight: Dimension.hitMin)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(Shoe.colorNames[index])
                            .accessibilityAddTraits(colorIndex == index ? .isSelected : [])
                        }
                    }
                    .sensoryFeedback(.selection, trigger: colorIndex)
                }

                Section {
                    DistanceField(label: "Already run", meters: $initialDistance, unit: unit)
                    Stepper(value: $replaceAfter, in: 100...2_000, step: 50) {
                        LabeledContent("Replace after", value: "\(Int(replaceAfter).formatted()) \(unit.distanceSymbol)")
                    }
                } header: {
                    Text("Distance")
                } footer: {
                    Text(unit == .metric ? "Most running shoes last 500–800 km." : "Most running shoes last 300–500 miles.")
                }

                Section {
                    Toggle("Default for new runs", isOn: $isDefault)
                        .tint(.track)
                } footer: {
                    Text("Runs on iPhone, Apple Watch and added by hand use this shoe unless you pick another.")
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.surface)
            .navigationTitle(shoe == nil ? "Add shoe" : "Edit shoe")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save).disabled(!canSave)
                }
            }
            .onAppear(perform: load)
        }
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        if let shoe {
            name = shoe.name
            brand = shoe.brand
            colorIndex = shoe.colorIndex
            initialDistance = shoe.initialDistance
            replaceAfter = min(max((shoe.maxDistance / unit.metersPerUnit / 50).rounded() * 50, 100), 2_000)
            loadedReplaceAfter = replaceAfter
            isDefault = ShoeDefaults.isDefault(shoe)
        } else {
            replaceAfter = unit == .metric ? 800 : 500
            colorIndex = activeShoes.count % Shoe.colors.count
            // The first shoe is the default one.
            isDefault = activeShoes.isEmpty
        }
    }

    private func save() {
        let target = shoe ?? Shoe(name: "")
        target.name = name.trimmingCharacters(in: .whitespaces)
        target.brand = brand.trimmingCharacters(in: .whitespaces)
        target.colorIndex = colorIndex
        target.initialDistance = max(initialDistance, 0)
        if replaceAfter != loadedReplaceAfter {
            target.maxDistance = replaceAfter * unit.metersPerUnit
        }
        if shoe == nil { context.insert(target) }
        if isDefault {
            // A retired shoe goes back into rotation when it's made the default.
            target.isRetired = false
            ShoeDefaults.set(target)
        } else if ShoeDefaults.isDefault(target) {
            ShoeDefaults.set(nil)
        }
        try? context.save()
        dismiss()
    }
}
