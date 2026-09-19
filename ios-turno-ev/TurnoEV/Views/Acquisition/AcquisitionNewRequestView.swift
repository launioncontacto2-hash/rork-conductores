import Observation
import SwiftUI

@MainActor
@Observable
final class AcquisitionNewRequestViewModel {
    var draft = AcquisitionRequestDraft()
    var step = 0
    var isPublishing = false
    var feedback: String?
    var published: AcquisitionRequest?
    private let repository: any AcquisitionRepository
    private let onPublished: (AcquisitionRequest) -> Void

    init(repository: any AcquisitionRepository, stationName: String, deliveryCity: String, onPublished: @escaping (AcquisitionRequest) -> Void) {
        self.repository = repository
        self.onPublished = onPublished
        draft.destinationStationName = stationName
        draft.deliveryCity = deliveryCity
    }

    func publish() async {
        guard !isPublishing else { return }
        do {
            _ = try draft.makePublication(authoritativeNow: AppClock.now())
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
            if let issue = error as? AcquisitionRequestDraftIssue {
                feedback = issue.message
            } else if let publicationError = error as? AcquisitionRequestPublicationError {
                feedback = publicationError.errorDescription
            } else {
                feedback = "No pudimos publicar la solicitud. Intenta nuevamente."
            }
            let diagnostic = AcquisitionRemoteDiagnostic.describe(
                error,
                operation: "publish acquisition request",
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

    init(repository: any AcquisitionRepository, stationName: String = "DORI Puebla", deliveryCity: String = "Puebla", onPublished: @escaping (AcquisitionRequest) -> Void) {
        _model = State(initialValue: AcquisitionNewRequestViewModel(repository: repository, stationName: stationName, deliveryCity: deliveryCity, onPublished: onPublished))
    }

    var body: some View {
        @Bindable var bindable = model
        ZStack {
            AcquisitionBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Nueva solicitud")
                        .font(.acquisition(.largeTitle, weight: .bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                        .foregroundStyle(AcquisitionTheme.text)
                    Text("Paso \(model.step + 1) de 4")
                        .font(.acquisition(.subheadline, weight: .bold))
                        .foregroundStyle(AcquisitionTheme.accent)
                    ProgressView(value: Double(model.step + 1), total: 4)
                        .tint(AcquisitionTheme.accent)

                    switch model.step {
                    case 0: basics($bindable.draft)
                    case 1: limits($bindable.draft)
                    case 2: requirements
                    default: review
                    }

                    if let feedback = model.feedback {
                        Label(feedback, systemImage: "exclamationmark.triangle.fill")
                            .font(.acquisition(.subheadline))
                            .foregroundStyle(AcquisitionTheme.attention)
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
                .tint(AcquisitionTheme.accent)
                .disabled(model.isPublishing)
            }
            .padding(14)
            .background(.ultraThinMaterial)
            .background(AcquisitionTheme.canvas.opacity(0.80))
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
            Text("Vehículos requeridos").font(.acquisition(.headline))
            requestField("Modelo", text: draft.model)
            requestField("Versiones (separadas por coma)", text: draft.versions)
            requestField("Cantidad", text: draft.targetQuantity, keyboard: .numberPad)
            VStack(alignment: .leading, spacing: 8) {
                Text("Periodo fiscal")
                    .font(.acquisition(.caption, weight: .bold))
                    .foregroundStyle(AcquisitionTheme.textSecondary)
                MonthYearWheel(selection: draft.fiscalPeriod)
                    .frame(height: 116)
            }
        }
        .padding(18).acquisitionGlass()
    }

    private func limits(_ draft: Binding<AcquisitionRequestDraft>) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Años, kilometraje y entrega").font(.acquisition(.headline))
            HStack {
                requestField("Año mínimo", text: draft.minimumYear, keyboard: .numberPad)
                requestField("Año máximo", text: draft.maximumYear, keyboard: .numberPad)
            }
            requestField("Kilometraje máximo", text: draft.maximumMileage, keyboard: .numberPad)
            requestField("Precio máximo por unidad", text: draft.maximumUnitPrice, keyboard: .numberPad)
            HStack {
                requestField("SOH mínimo (%)", text: draft.minimumSoh, keyboard: .numberPad)
                requestField("Vigencia diagnóstico (días)", text: draft.sohDiagnosisMaximumAgeDays, keyboard: .numberPad)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("Estación destino")
                    .font(.acquisition(.caption, weight: .bold))
                    .foregroundStyle(AcquisitionTheme.textSecondary)
                Label("\(draft.destinationStationName.wrappedValue) · \(draft.deliveryCity.wrappedValue)", systemImage: "building.2.fill")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(AcquisitionTheme.surfaceRaised, in: RoundedRectangle(cornerRadius: 12))
                Text("Asignada automáticamente según tu sesión.")
                    .font(.acquisition(.caption))
                    .foregroundStyle(AcquisitionTheme.textSecondary)
            }
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
                    title: "Fecha límite de entrega",
                    selection: nonOptionalDate(draft.targetDeliveryDate),
                    displayedComponents: .date
                )
            }
            Text("Usa una fecha realista. Esta fecha servirá como referencia formal para la operación y el seguimiento de cumplimiento.")
                .font(.acquisition(.caption))
                .foregroundStyle(AcquisitionTheme.textSecondary)
        }
        .padding(18).acquisitionGlass()
    }

    private var requirements: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Requisitos de esta solicitud").font(.acquisition(.headline))
            Text("Lineamientos institucionales definidos por DORI. Esta pantalla es informativa.")
                .font(.acquisition(.subheadline)).foregroundStyle(AcquisitionTheme.textSecondary)
            ForEach(model.draft.requirements.filter { $0.category != .evidence }) { requirement in
                HStack(alignment: .top) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(AcquisitionTheme.accent)
                    Text(requirement.title).font(.acquisition(.subheadline, weight: .bold))
                    Spacer()
                }
            }
            Divider()
            Label("Evidencias fotográficas", systemImage: "camera.fill")
                .font(.acquisition(.subheadline, weight: .bold))
            Text("\(model.draft.requirements.filter { $0.category == .evidence }.count) fotografías requeridas al proveedor.")
                .font(.acquisition(.caption)).foregroundStyle(AcquisitionTheme.textSecondary)
            Label("Condiciones de entrega administradas por DORI", systemImage: "doc.text.fill")
                .font(.acquisition(.subheadline, weight: .bold))
        }
        .padding(18).acquisitionGlass()
    }

    private var review: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Revisar y publicar").font(.acquisition(.headline))
            reviewLine("Modelo", model.draft.model)
            reviewLine("Cantidad", model.draft.targetQuantity)
            reviewLine("Años", "\(model.draft.minimumYear)–\(model.draft.maximumYear)")
            reviewLine("Kilometraje", formattedInteger(model.draft.maximumMileage, suffix: " km"))
            reviewLine("Precio máximo", formattedInteger(model.draft.maximumUnitPrice, prefix: "$"))
            reviewLine("Periodo", AcquisitionFiscalPeriodPresentation.text(for: model.draft.fiscalPeriod))
            reviewLine("Requisitos", "\(model.draft.requirements.count)")
            reviewLine("Vigencia", model.draft.deadlineAt.map(Self.dateText) ?? "Pendiente")
            reviewLine("Fecha límite de entrega", model.draft.targetDeliveryDate.map(Self.dateText) ?? "Pendiente")
            reviewLine("Estación destino", model.draft.destinationStationName)
        }
        .padding(18).acquisitionGlass()
    }

    private func requestField(
        _ title: String,
        text: Binding<String>,
        keyboard: UIKeyboardType = .default
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.acquisition(.caption, weight: .bold)).foregroundStyle(AcquisitionTheme.textSecondary)
            TextField(title, text: text)
                .keyboardType(keyboard)
                .padding(12)
                .background(AcquisitionTheme.surfaceRaised, in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private func reviewLine(_ title: String, _ value: String) -> some View {
        HStack { Text(title).foregroundStyle(AcquisitionTheme.textSecondary); Spacer(); Text(value).fontWeight(.bold) }
            .font(.acquisition(.subheadline))
    }

    private func formattedInteger(_ raw: String, prefix: String = "", suffix: String = "") -> String {
        let value = Int(raw.replacingOccurrences(of: ",", with: "").replacingOccurrences(of: "$", with: "")) ?? 0
        return prefix + value.formatted(.number.locale(Locale(identifier: "es_MX")).grouping(.automatic)) + suffix
    }

    private func nonOptionalDate(_ date: Binding<Date?>) -> Binding<Date> {
        Binding(
            get: { date.wrappedValue ?? AcquisitionRequestDraft.defaultDate(daysFromNow: 1) ?? Date() },
            set: { date.wrappedValue = $0 }
        )
    }

    private static func dateText(_ date: Date) -> String {
        AcquisitionSpanishDate.text(date)
    }
}

private struct MonthYearWheel: View {
    @Binding var selection: Date

    private var month: Binding<Int> {
        Binding(
            get: { Calendar.current.component(.month, from: selection) },
            set: { update(month: $0, year: Calendar.current.component(.year, from: selection)) }
        )
    }

    private var year: Binding<Int> {
        Binding(
            get: { Calendar.current.component(.year, from: selection) },
            set: { update(month: Calendar.current.component(.month, from: selection), year: $0) }
        )
    }

    var body: some View {
        HStack(spacing: 0) {
            Picker("Mes", selection: month) {
                ForEach(1...12, id: \.self) { value in
                    Text(AcquisitionFiscalPeriodPresentation.monthName(value)).tag(value)
                }
            }
            .pickerStyle(.wheel)
            Picker("Año", selection: year) {
                ForEach(2024...2035, id: \.self) { Text(String($0)).tag($0) }
            }
            .pickerStyle(.wheel)
        }
    }

    private func update(month: Int, year: Int) {
        selection = Calendar.current.date(from: DateComponents(year: year, month: month, day: 1)) ?? selection
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
                Text(title).foregroundStyle(AcquisitionTheme.text)
                Spacer()
                Text(AcquisitionSpanishDate.text(selection))
                    .foregroundStyle(AcquisitionTheme.accent)
                Image(systemName: "calendar")
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title), \(AcquisitionSpanishDate.text(selection))")
        .accessibilityValue(AcquisitionSpanishDate.text(selection))
        .accessibilityIdentifier("acquisition-request-deadline-picker")
        .sheet(isPresented: $isPresented) {
            VStack(spacing: 12) {
                Text(title).font(.acquisition(.headline))
                Text(AcquisitionFiscalPeriodPresentation.text(for: selection))
                    .foregroundStyle(AcquisitionTheme.text.opacity(0.62))
                    .accessibilityIdentifier("acquisition-calendar-month")
                DatePicker(
                    title,
                    selection: $selection,
                    displayedComponents: displayedComponents
                )
                .datePickerStyle(.graphical)
                .labelsHidden()
                .environment(\.locale, Locale(identifier: "es_MX"))
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
                Text(title).foregroundStyle(AcquisitionTheme.text)
                Spacer()
                Text(AcquisitionSpanishDate.time(selection))
                    .foregroundStyle(AcquisitionTheme.accent)
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
        return AcquisitionSpanishDate.time(date)
    }
}

#if DEBUG
struct AcquisitionCalendarValidationView: View {
    @State private var date = Date()

    var body: some View {
        NavigationStack {
            ZStack {
                AcquisitionBackground()
                VStack {
                    AcquisitionAutoDismissDateRow(
                        title: "Fecha límite para recibir ofertas",
                        selection: $date,
                        displayedComponents: .date
                    )
                    .padding(18)
                    .acquisitionGlass()
                    Spacer()
                }
                .padding()
            }
            .navigationTitle("Solicitud")
        }
        .environment(\.locale, Locale(identifier: "es_MX"))
    }
}
#endif
