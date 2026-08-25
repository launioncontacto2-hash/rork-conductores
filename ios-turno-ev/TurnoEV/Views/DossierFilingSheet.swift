import SwiftUI
import UIKit

/// The desk-side form for filing one document. Supervision uses it in the car file,
/// recruitment in the candidate file; the driver never sees it, he only reads the result.
struct DossierFilingSheet: View {
    let kind: DossierDocument
    let subjectId: String
    let subjectLabel: String
    let deskName: String
    /// Instant the form was opened with. Action time, not a cadence: it preloads the issue
    /// date of a blank form and stamps the record on save. No `TimeScope` belongs here.
    var now: Date = Date()
    var onSaved: (() -> Void)?

    @Environment(\.dismiss) private var dismiss

    @State private var reference: String = ""
    @State private var issuer: String = ""
    @State private var issuedAt: Date = .now
    @State private var expiresAt: Date = .now
    @State private var hasExpiry: Bool = false
    @State private var scan: Data?
    @State private var loaded: Bool = false

    private var existing: FiledDocument? {
        DossierBook.document(kind: kind, subjectId: subjectId)
    }

    private var canSave: Bool {
        reference.trimmingCharacters(in: .whitespaces).count >= 3
            && issuer.trimmingCharacters(in: .whitespaces).count >= 3
    }

    var body: some View {
        NavigationStack {
            ZStack {
                StationBackground()

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        header

                        PhotoSlotView(
                            title: scan == nil ? "Fotografiar o adjuntar" : "Documento cargado",
                            hint: "Documento completo y legible",
                            data: scan
                        ) { data in
                            scan = data
                        }

                        VStack(alignment: .leading, spacing: 10) {
                            CapsLabel(text: kind.referenceLabel)
                            TextField("Número de \(kind.referenceLabel.lowercased())", text: $reference)
                                .textInputAutocapitalization(.characters)
                                .autocorrectionDisabled()
                                .font(.system(.body, weight: .semibold))
                                .padding(14)
                                .panelFlat()

                            CapsLabel(text: kind.issuerLabel)
                            TextField(kind.issuerLabel, text: $issuer)
                                .font(.system(.body, weight: .semibold))
                                .padding(14)
                                .panelFlat()
                        }

                        VStack(spacing: 10) {
                            DatePicker("Fecha de expedición", selection: $issuedAt, displayedComponents: .date)
                                .font(.system(.subheadline, weight: .semibold))

                            if kind.expires {
                                Toggle("Tiene vigencia", isOn: $hasExpiry)
                                    .font(.system(.subheadline, weight: .semibold))
                                if hasExpiry {
                                    DatePicker("Vence el", selection: $expiresAt, displayedComponents: .date)
                                        .font(.system(.subheadline, weight: .semibold))
                                }
                            }
                        }
                        .tint(Palette.volt)
                        .padding(14)
                        .panelFlat()

                        if kind.watermark != nil {
                            NoticeBanner(
                                symbol: "seal.fill",
                                title: "Se mostrará con marca de agua",
                                message: "Cualquier consulta de este documento aparece estampada como «Copia sin valor fiscal».",
                                tone: .amber
                            )
                        }

                        BigButton(title: existing == nil ? "Guardar en expediente" : "Actualizar documento", symbol: "tray.and.arrow.down.fill", isEnabled: canSave) {
                            save()
                        }

                        if existing != nil {
                            BigButton(title: "Quitar del expediente", symbol: "trash.fill", tone: .danger) {
                                DossierBook.remove(kind: kind, subjectId: subjectId)
                                onSaved?()
                                dismiss()
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 10)
                    .padding(.bottom, 30)
                }
                .scrollIndicators(.hidden)
            }
            .navigationTitle(kind.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cerrar") { dismiss() }
                }
            }
        }
        .presentationContentInteraction(.scrolls)
        .preferredColorScheme(.dark)
        .onAppear(perform: loadExisting)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(subjectLabel)
                .font(.system(.headline, weight: .black))
            Text("Resguarda \(kind.desk.label.lowercased()) · \(kind.hint.lowercased())")
                .font(.system(size: 11))
                .foregroundStyle(Palette.textMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .panel()
    }

    private func loadExisting() {
        guard !loaded else { return }
        loaded = true
        guard let existing else { return }
        reference = existing.reference
        issuer = existing.issuer
        issuedAt = existing.issuedAt ?? now
        if let expires = existing.expiresAt {
            hasExpiry = true
            expiresAt = expires
        }
        scan = existing.image
    }

    private func save() {
        let record = DossierBook.make(
            kind: kind,
            subjectId: subjectId,
            subjectLabel: subjectLabel,
            reference: reference,
            issuer: issuer,
            issuedAt: issuedAt,
            expiresAt: hasExpiry ? expiresAt : nil,
            uploadedBy: deskName,
            now: now,
            image: scan
        )
        DossierBook.upsert(record)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        onSaved?()
        dismiss()
    }
}

/// Desk-side row: one document of a file, with what is missing said out loud.
///
/// The row owns the freshness of its own temporal data. Both things the clock decides here
/// — the status pill and the expiry caption — are answers to a date, and they change
/// together, which makes the row the smallest honest unit. It registers that dependency
/// itself at `.day` cadence, so neither desk that shows it has to hand over a clock: a car
/// file of nine documents invalidates nine rows once per logical midnight.
struct DossierDeskRow: View {
    let kind: DossierDocument
    let document: FiledDocument?
    let accent: Color
    let action: () -> Void

    var body: some View {
        TimeScope(.day) { now in
            row(now: now)
        }
    }

    private func row(now: Date) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 13)
                        .fill((document == nil ? Color.white : accent).opacity(document == nil ? 0.05 : 0.14))
                    Image(systemName: document == nil ? "tray.fill" : kind.symbol)
                        .font(.system(.footnote, weight: .bold))
                        .foregroundStyle(document == nil ? Palette.textMuted : accent)
                }
                .frame(width: 42, height: 42)

                VStack(alignment: .leading, spacing: 2) {
                    Text(kind.title)
                        .font(.system(.footnote, weight: .bold))
                    Text(detail(now: now))
                        .font(.system(size: 10))
                        .foregroundStyle(Palette.textMuted)
                        .lineLimit(1)
                }

                Spacer(minLength: 4)

                if let document {
                    let status = document.status(now: now)
                    StatePill(
                        text: status.label,
                        symbol: status.symbol,
                        tone: status == .onFile ? accent : status == .expiringSoon ? Palette.amber : Palette.danger,
                        compact: true
                    )
                } else {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(.footnote, weight: .bold))
                        .foregroundStyle(accent)
                }
            }
            .padding(11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .panelFlat(cornerRadius: 16)
        }
        .buttonStyle(.plain)
    }

    private func detail(now: Date) -> String {
        guard let document else { return "Pendiente de cargar" }
        return "\(document.kind.referenceLabel) \(document.reference) · \(document.expiryText(now: now))"
    }
}
