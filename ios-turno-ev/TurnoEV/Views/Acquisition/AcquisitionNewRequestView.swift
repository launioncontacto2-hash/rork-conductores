import Observation
import SwiftUI

@MainActor
@Observable
final class AcquisitionNewRequestViewModel {
    var draft = AcquisitionRequestDraft()
    var step = 0
    var customTitle = ""
    var customValue = ""
    var customCategory: AcquisitionRequestRequirementCategory = .condition
    var isPublishing = false
    var feedback: String?
    var published: AcquisitionRequest?
    private let repository: any AcquisitionRepository
    private let onPublished: (AcquisitionRequest) -> Void

    init(repository: any AcquisitionRepository, onPublished: @escaping (AcquisitionRequest) -> Void) {
        self.repository = repository
        self.onPublished = onPublished
    }

    func addRequirement() {
        let title = customTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let value = customValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, !value.isEmpty else {
            feedback = "Captura el requisito y su condición."
            return
        }
        let code = "custom_\(UUID().uuidString.lowercased())"
        draft.requirements.append(
            .init(id: code, category: customCategory, title: title, value: value)
        )
        customTitle = ""
        customValue = ""
        feedback = nil
    }

    func removeRequirement(_ requirement: AcquisitionRequestRequirement) {
        draft.requirements.removeAll { $0.id == requirement.id }
    }

    func publish() async {
        guard !isPublishing else { return }
        do {
            _ = try draft.makePublication()
        } catch let issue as AcquisitionRequestDraftIssue {
            feedback = issue.message
            return
        } catch {
            feedback = "Revisa la información de la solicitud."
            return
        }
        isPublishing = true
        defer { isPublishing = false }
        do {
            let request = try await repository.publishRequest(draft)
            published = request
            onPublished(request)
        } catch {
            feedback = "No pudimos publicar la solicitud. Intenta nuevamente."
            print("[Adquisiciones] publicación de solicitud fallida: \(error.localizedDescription)")
        }
    }
}

struct AcquisitionNewRequestView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var model: AcquisitionNewRequestViewModel

    init(repository: any AcquisitionRepository, onPublished: @escaping (AcquisitionRequest) -> Void) {
        _model = State(initialValue: AcquisitionNewRequestViewModel(repository: repository, onPublished: onPublished))
    }

    var body: some View {
        @Bindable var bindable = model
        ZStack {
            StationBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Nueva solicitud")
                        .font(.system(.title, weight: .black))
                    Text("Paso \(model.step + 1) de 4")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(Palette.volt)
                    ProgressView(value: Double(model.step + 1), total: 4)
                        .tint(Palette.volt)

                    switch model.step {
                    case 0: basics($bindable.draft)
                    case 1: limits($bindable.draft)
                    case 2:
                        requirements(
                            customTitle: $bindable.customTitle,
                            customValue: $bindable.customValue,
                            customCategory: $bindable.customCategory
                        )
                    default: review
                    }

                    if let feedback = model.feedback {
                        Label(feedback, systemImage: "exclamationmark.triangle.fill")
                            .font(.subheadline)
                            .foregroundStyle(Palette.amber)
                    }
                }
                .padding(18)
            }
        }
        .safeAreaInset(edge: .bottom) {
            HStack(spacing: 12) {
                if model.step > 0 {
                    Button("Anterior") { model.step -= 1; model.feedback = nil }
                        .buttonStyle(.bordered)
                }
                Button {
                    if model.step < 3 { model.step += 1; model.feedback = nil }
                    else { Task { await model.publish() } }
                } label: {
                    Text(model.step < 3 ? "Continuar" : (model.isPublishing ? "Publicando…" : "Publicar solicitud"))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(Palette.volt)
                .disabled(model.isPublishing)
            }
            .padding(14)
            .background(Palette.surface.opacity(0.98))
        }
        .navigationTitle("Solicitud")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Solicitud publicada", isPresented: Binding(
            get: { model.published != nil }, set: { _ in }
        )) {
            Button("Listo") { dismiss() }
        } message: {
            Text("Los proveedores autorizados ya pueden consultarla.")
        }
    }

    private func basics(_ draft: Binding<AcquisitionRequestDraft>) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Vehículos requeridos").font(.headline)
            requestField("Modelo", text: draft.model)
            requestField("Versiones (separadas por coma)", text: draft.versions)
            requestField("Cantidad", text: draft.targetQuantity, keyboard: .numberPad)
        }
        .padding(18).panel()
    }

    private func limits(_ draft: Binding<AcquisitionRequestDraft>) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Años, kilometraje y entrega").font(.headline)
            HStack {
                requestField("Año mínimo", text: draft.minimumYear, keyboard: .numberPad)
                requestField("Año máximo", text: draft.maximumYear, keyboard: .numberPad)
            }
            requestField("Kilometraje máximo", text: draft.maximumMileage, keyboard: .numberPad)
            requestField("Ciudad de entrega", text: draft.deliveryCity)
        }
        .padding(18).panel()
    }

    private func requirements(
        customTitle: Binding<String>,
        customValue: Binding<String>,
        customCategory: Binding<AcquisitionRequestRequirementCategory>
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Requisitos de esta solicitud").font(.headline)
            Text("Incluye las 14 evidencias aprobadas. Puedes agregar condiciones o documentos propios de esta solicitud.")
                .font(.subheadline).foregroundStyle(Palette.textMuted)
            ForEach(model.draft.requirements) { requirement in
                HStack(alignment: .top) {
                    Image(systemName: requirement.category == .evidence ? "camera.fill" : "checkmark.circle.fill")
                        .foregroundStyle(Palette.volt)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(requirement.title).font(.subheadline.weight(.bold))
                        Text(requirement.value).font(.caption).foregroundStyle(Palette.textMuted)
                    }
                    Spacer()
                    if requirement.id.hasPrefix("custom_") {
                        Button(role: .destructive) { model.removeRequirement(requirement) } label: {
                            Image(systemName: "trash")
                        }
                    }
                }
            }
            Divider()
            Picker("Tipo", selection: customCategory) {
                ForEach([AcquisitionRequestRequirementCategory.condition, .documentation, .specification], id: \.self) {
                    Text($0.visibleTitle).tag($0)
                }
            }
            requestField("Nuevo requisito", text: customTitle)
            requestField("Condición o documento esperado", text: customValue)
            Button("Agregar requisito") { model.addRequirement() }
                .buttonStyle(.bordered).tint(Palette.volt)
        }
        .padding(18).panel()
    }

    private var review: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Revisar y publicar").font(.headline)
            reviewLine("Modelo", model.draft.model)
            reviewLine("Cantidad", model.draft.targetQuantity)
            reviewLine("Años", "\(model.draft.minimumYear)–\(model.draft.maximumYear)")
            reviewLine("Kilometraje", "\(model.draft.maximumMileage) km")
            reviewLine("Requisitos", "\(model.draft.requirements.count)")
            Text("La publicación será autoritativa y compartida con los proveedores del entorno TEST.")
                .font(.caption).foregroundStyle(Palette.textMuted)
        }
        .padding(18).panel()
    }

    private func requestField(
        _ title: String,
        text: Binding<String>,
        keyboard: UIKeyboardType = .default
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.caption.weight(.bold)).foregroundStyle(Palette.textMuted)
            TextField(title, text: text)
                .keyboardType(keyboard)
                .padding(12)
                .background(Palette.surfaceRaised, in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private func reviewLine(_ title: String, _ value: String) -> some View {
        HStack { Text(title).foregroundStyle(Palette.textMuted); Spacer(); Text(value).fontWeight(.bold) }
            .font(.subheadline)
    }
}
