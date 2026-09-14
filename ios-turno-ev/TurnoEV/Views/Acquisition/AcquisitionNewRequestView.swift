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
    var customResponseType: AcquisitionRequirementResponseType = .confirmation
    var customRequiresVerification = false
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
            .init(
                id: code, category: customCategory, title: title, value: value,
                responseType: customResponseType,
                requiresDORIVerification: customRequiresVerification
            )
        )
        customTitle = ""
        customValue = ""
        customResponseType = .confirmation
        customRequiresVerification = false
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
            let diagnostic = AcquisitionRemoteDiagnostic.describe(
                error,
                operation: "rpc publish_acquisition_request",
                context: [
                    "deadline_present": draft.deadlineAt == nil ? "false" : "true",
                    "target_delivery_present": draft.targetDeliveryDate == nil ? "false" : "true",
                    "requirements": String(draft.requirements.count),
                ]
            )
            print("[Adquisiciones][TEST][Solicitud] \(diagnostic)")
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
                            customCategory: $bindable.customCategory,
                            customResponseType: $bindable.customResponseType,
                            customRequiresVerification: $bindable.customRequiresVerification
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
            if draft.deadlineAt.wrappedValue != nil {
                AcquisitionAutoDismissDateRow(
                    title: "Fecha límite para recibir ofertas",
                    selection: nonOptionalDate(draft.deadlineAt),
                    displayedComponents: .date
                )
                AcquisitionAutoDismissTimeRow(
                    title: "Hora límite",
                    selection: nonOptionalDate(draft.deadlineAt)
                )
            }
            if draft.targetDeliveryDate.wrappedValue != nil {
                AcquisitionAutoDismissDateRow(
                    title: "Fecha objetivo de entrega",
                    selection: nonOptionalDate(draft.targetDeliveryDate),
                    displayedComponents: .date
                )
            }
            Text("Usa una fecha realista. Esta fecha servirá como referencia formal para la operación y el seguimiento de cumplimiento.")
                .font(.caption)
                .foregroundStyle(Palette.textMuted)
        }
        .padding(18).panel()
    }

    private func requirements(
        customTitle: Binding<String>,
        customValue: Binding<String>,
        customCategory: Binding<AcquisitionRequestRequirementCategory>,
        customResponseType: Binding<AcquisitionRequirementResponseType>,
        customRequiresVerification: Binding<Bool>
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
            Picker("Tipo de respuesta", selection: customResponseType) {
                ForEach(AcquisitionRequirementResponseType.allCases, id: \.self) {
                    Text($0.visibleTitle).tag($0)
                }
            }
            Toggle("Requiere verificación DORI", isOn: customRequiresVerification)
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
            reviewLine("Vigencia", model.draft.deadlineAt.map(Self.dateText) ?? "Pendiente")
            reviewLine("Entrega objetivo", model.draft.targetDeliveryDate.map(Self.dateText) ?? "Pendiente")
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

    private func nonOptionalDate(_ date: Binding<Date?>) -> Binding<Date> {
        Binding(
            get: { date.wrappedValue ?? AcquisitionRequestDraft.defaultDate(daysFromNow: 1) ?? Date() },
            set: { date.wrappedValue = $0 }
        )
    }

    private static func dateText(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .omitted)
    }
}

private struct AcquisitionAutoDismissDateRow: View {
    let title: String
    @Binding var selection: Date
    let displayedComponents: DatePickerComponents
    @State private var isPresented = false

    var body: some View {
        Button { isPresented = true } label: {
            HStack {
                Text(title).foregroundStyle(Palette.text)
                Spacer()
                Text(selection.formatted(date: .abbreviated, time: .omitted))
                    .foregroundStyle(Palette.volt)
                Image(systemName: "calendar")
            }
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $isPresented) {
            VStack(spacing: 12) {
                Text(title).font(.headline)
                DatePicker(
                    title,
                    selection: $selection,
                    displayedComponents: displayedComponents
                )
                .datePickerStyle(.graphical)
                .labelsHidden()
                .onChange(of: selection) { _, _ in isPresented = false }
            }
            .padding(18)
            .presentationDetents([.medium])
        }
    }
}

private struct AcquisitionAutoDismissTimeRow: View {
    let title: String
    @Binding var selection: Date
    @State private var isPresented = false

    var body: some View {
        Button { isPresented = true } label: {
            HStack {
                Text(title).foregroundStyle(Palette.text)
                Spacer()
                Text(selection.formatted(date: .omitted, time: .shortened))
                    .foregroundStyle(Palette.volt)
                Image(systemName: "clock")
            }
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $isPresented) {
            NavigationStack {
                List(Self.times, id: \.self) { minuteOfDay in
                    Button(Self.label(for: minuteOfDay)) {
                        let calendar = Calendar.current
                        selection = calendar.date(
                            bySettingHour: minuteOfDay / 60,
                            minute: minuteOfDay % 60,
                            second: 0,
                            of: selection
                        ) ?? selection
                        isPresented = false
                    }
                }
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
            }
            .presentationDetents([.medium, .large])
        }
    }

    private static let times = Array(stride(from: 0, through: 23 * 60 + 30, by: 30))

    private static func label(for minuteOfDay: Int) -> String {
        let date = Calendar.current.date(
            from: DateComponents(hour: minuteOfDay / 60, minute: minuteOfDay % 60)
        ) ?? Date()
        return date.formatted(date: .omitted, time: .shortened)
    }
}
