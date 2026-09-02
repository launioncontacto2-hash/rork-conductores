import SwiftUI
import UIKit

/// Incident report: accidents, damage and mechanical failures with photos and comments.
struct IncidentView: View {
    @Environment(FleetStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var kind: IncidentKind = .damage
    @State private var comments: String = ""
    @State private var photos: [Data?] = [nil, nil, nil]
    @State private var errorMessage: String?
    @State private var areDocumentsPresented: Bool = false
    @State private var isSubmitting: Bool = false

    var body: some View {
        NavigationStack {
            ZStack {
                StationBackground()

                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        documentationCard

                        VStack(spacing: 10) {
                            ForEach(IncidentKind.allCases, id: \.self) { option in
                                kindRow(option)
                            }
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            CapsLabel(text: "Comentarios")
                            TextEditor(text: $comments)
                                .scrollContentBackground(.hidden)
                                .frame(minHeight: 120)
                                .padding(12)
                                .panelFlat()
                                .overlay(alignment: .topLeading) {
                                    if comments.isEmpty {
                                        Text("Describe qué ocurrió, dónde y si la unidad sigue operable.")
                                            .font(.footnote)
                                            .foregroundStyle(Palette.textMuted)
                                            .padding(18)
                                            .allowsHitTesting(false)
                                    }
                                }
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            CapsLabel(text: "Fotografías")
                            HStack(spacing: 10) {
                                ForEach(photos.indices, id: \.self) { index in
                                    PhotoSlotView(title: "Foto \(index + 1)", data: photos[index]) { data in
                                        photos[index] = data
                                    }
                                }
                            }
                        }

                        Text("Se registra automáticamente \(Fmt.dateShort(store.now)) · \(Fmt.clockSeconds(store.now)) · \(store.driver.name)\(store.activeVehicle.map { " · \($0.internalNumber)" } ?? "")")
                            .font(.system(size: 11))
                            .foregroundStyle(Palette.textMuted)
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .panelFlat()

                        if !store.canReportIncident {
                            disconnectedBanner
                        }

                        if let errorMessage {
                            Text(errorMessage)
                                .font(.footnote)
                                .foregroundStyle(Palette.danger)
                        }

                        // The screen stays fully usable so the flow can be explained and
                        // the evidence gathered, but the button never says "enviar" when
                        // nothing is on the other end to receive it.
                        BigButton(
                            title: isSubmitting
                                ? "Enviando reporte…"
                                : (store.canReportIncident
                                    ? "Enviar reporte"
                                    : "El envío requiere conexión"),
                            symbol: store.canReportIncident
                                ? "paperplane.fill"
                                : "antenna.radiowaves.left.and.right.slash",
                            tone: store.canReportIncident ? .danger : .outline,
                            isEnabled: store.canReportIncident && !isSubmitting
                        ) {
                            Task { await submit() }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 10)
                    .padding(.bottom, 30)
                }
            }
            .navigationTitle("Reporte de incidencias")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cerrar") { dismiss() }
                }
            }
            .sheet(isPresented: $areDocumentsPresented) {
                UnitDocumentsView(
                    vehicleId: store.displayVehicle?.id,
                    vehicleLabel: store.displayVehicle.map { "\($0.internalNumber) · \($0.model)" } ?? "Sin unidad asignada",
                    driverId: store.driver.id,
                    driverLabel: "\(store.driver.name) · \(store.driver.employeeNumber)",
                    now: store.now
                )
            }
        }
        .preferredColorScheme(.dark)
    }

    /// Says what the captured photographs are, and what they are not.
    ///
    /// They stay on this screen as a draft the view holds: nothing here reaches
    /// `FleetStore.incidents`, which is the list that means "la estación lo recibió".
    /// After a collision, believing supervision is already reviewing the case is worse
    /// than knowing there is still a call to make.
    private var disconnectedBanner: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "antenna.radiowaves.left.and.right.slash")
                    .font(.system(size: 12, weight: .bold))
                Text(store.usesBackendIncidentCycle ? "Turno requerido" : "Reporte sin enviar")
                    .font(.system(.footnote, weight: .black))
            }
            .foregroundStyle(Palette.amber)

            Text(
                store.usesBackendIncidentCycle
                    ? "Para vincular la incidencia con el conductor y la unidad correctos, primero debe existir un turno abierto."
                    : (OperationalMutationError.backendRequired.errorDescription ?? "")
            )
                .font(.system(size: 11))
                .foregroundStyle(Palette.textMuted)
                .fixedSize(horizontal: false, vertical: true)

            Text(
                store.usesBackendIncidentCycle
                    ? "Inicia el turno y vuelve a esta pantalla; la estación recibirá el reporte en cuanto lo envíes."
                    : "Lo que captures aquí queda en tu dispositivo como borrador. Para una incidencia en curso, comunícate con tu supervisor de estación."
            )
                .font(.system(size: 11))
                .foregroundStyle(Palette.textMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.amber.opacity(0.1), in: .rect(cornerRadius: 18))
        .overlay {
            RoundedRectangle(cornerRadius: 18)
                .stroke(Palette.amber.opacity(0.4), lineWidth: 1)
        }
    }

    /// Everything the driver may be asked for on the road, in one tap: the papers of
    /// the unit that supervision filed and the ones recruitment filed about him.
    private var documentationCard: some View {
        let vehicle = store.displayVehicle
        let pending = DossierBook.missing(vehicleId: vehicle?.id, driverId: store.driver.id).count

        return Button {
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
            areDocumentsPresented = true
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 15)
                            .fill(Palette.volt.opacity(0.14))
                        Image(systemName: "folder.fill.badge.person.crop")
                            .font(.system(.title3, weight: .bold))
                            .foregroundStyle(Palette.volt)
                    }
                    .frame(width: 50, height: 50)

                    VStack(alignment: .leading, spacing: 3) {
                        Text("Documentación de mi unidad")
                            .font(.system(.subheadline, weight: .black))
                        Text(vehicle.map { "\($0.internalNumber) · \($0.plates)" } ?? "Sin unidad asignada")
                            .font(.system(size: 11))
                            .foregroundStyle(Palette.textMuted)
                    }

                    Spacer(minLength: 0)

                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Palette.textMuted)
                }

                HStack(spacing: 6) {
                    ForEach(DossierDocument.allCases) { kind in
                        Image(systemName: kind.symbol)
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Palette.textMuted)
                            .frame(width: 26, height: 26)
                            .background(Color.white.opacity(0.05), in: .circle)
                    }
                    Spacer(minLength: 0)
                    Text(pending == 0 ? "5 documentos listos" : "\(5 - pending) de 5 cargados")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(pending == 0 ? Palette.volt : Palette.amber)
                }

                Text("Póliza, tarjeta de circulación y factura de la unidad, más tu licencia e identificación del turno.")
                    .font(.system(size: 10))
                    .foregroundStyle(Palette.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .panel(cornerRadius: 22)
        }
        .buttonStyle(PressableCardStyle())
    }

    private func kindRow(_ option: IncidentKind) -> some View {
        let isActive = kind == option
        return Button {
            kind = option
        } label: {
            HStack(spacing: 12) {
                Image(systemName: option.symbol)
                    .font(.system(.body, weight: .semibold))
                    .foregroundStyle(isActive ? Palette.danger : Palette.textMuted)
                    .frame(width: 42, height: 42)
                    .background((isActive ? Palette.danger : Color.white).opacity(0.1), in: .rect(cornerRadius: 14))

                VStack(alignment: .leading, spacing: 2) {
                    Text(option.label)
                        .font(.system(.subheadline, weight: .bold))
                    Text(option.hint)
                        .font(.caption2)
                        .foregroundStyle(Palette.textMuted)
                }

                Spacer(minLength: 4)

                Circle()
                    .strokeBorder(isActive ? Palette.danger : Palette.hairline, lineWidth: 2)
                    .background(isActive ? Palette.danger : .clear, in: .circle)
                    .frame(width: 20, height: 20)
            }
            .padding(14)
            .background((isActive ? Palette.danger.opacity(0.1) : Palette.surfaceRaised.opacity(0.6)), in: .rect(cornerRadius: 20))
            .overlay {
                RoundedRectangle(cornerRadius: 20)
                    .stroke(isActive ? Palette.danger.opacity(0.5) : Palette.hairline, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }

    @MainActor
    private func submit() async {
        let text = comments.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count >= 10 else {
            errorMessage = "Describe la incidencia con al menos una frase."
            return
        }

        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }

        do {
            try await store.reportAvailableIncident(
                kind: kind,
                description: text,
                photos: photos.compactMap { $0 },
                idempotencyKey: "incident-\(UUID().uuidString.lowercased())"
            )
        } catch {
            let failure = error as? OperationalMutationError
            errorMessage = failure?.errorDescription
                ?? "No se pudo enviar el reporte de incidencia."
            return
        }
        dismiss()
    }
}

#Preview {
    IncidentView()
        .environment(FleetStore())
        .preferredColorScheme(.dark)
}
