import SwiftUI
import UIKit

/// Read-only viewer of the paperwork already filed for a unit and for the person
/// driving it. Nothing is captured here: supervision files the papers of the vehicle,
/// recruitment files the identity of the driver, and the road just needs to show them.
struct UnitDocumentsView: View {
    let vehicleId: String?
    let vehicleLabel: String
    let driverId: String?
    let driverLabel: String
    var now: Date = Date()

    @Environment(\.dismiss) private var dismiss
    @State private var opened: FiledDocument?

    private var vehicleDocuments: [FiledDocument] {
        DossierDocument.vehicleFile.compactMap { DossierBook.document(kind: $0, subjectId: vehicleId) }
    }

    private var driverDocuments: [FiledDocument] {
        DossierDocument.driverFile.compactMap { DossierBook.document(kind: $0, subjectId: driverId) }
    }

    private var missing: [DossierDocument] {
        DossierBook.missing(vehicleId: vehicleId, driverId: driverId)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                StationBackground()

                ScrollView {
                    VStack(spacing: 16) {
                        headerCard

                        section(
                            subject: .vehicle,
                            caption: "Cargados por tu supervisor en el archivo del auto",
                            expected: DossierDocument.vehicleFile,
                            filed: vehicleDocuments
                        )

                        section(
                            subject: .driver,
                            caption: "Cargados por reclutamiento en tu expediente",
                            expected: DossierDocument.driverFile,
                            filed: driverDocuments
                        )

                        Text("Documentos de consulta. La factura se muestra siempre con la marca de agua «Copia sin valor fiscal».")
                            .font(.system(size: 10))
                            .foregroundStyle(Palette.textMuted)
                            .multilineTextAlignment(.center)
                            .padding(.top, 2)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 10)
                    .padding(.bottom, 30)
                }
                .scrollIndicators(.hidden)
            }
            .navigationTitle("Documentación de mi unidad")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cerrar") { dismiss() }
                }
            }
            .sheet(item: $opened) { document in
                DocumentReaderView(document: document, now: now)
            }
        }
        .preferredColorScheme(.dark)
    }

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            CapsLabel(text: "Expediente en consulta")
            HStack(spacing: 10) {
                Image(systemName: "car.side.fill")
                    .font(.system(.footnote, weight: .bold))
                    .foregroundStyle(Palette.volt)
                Text(vehicleLabel)
                    .font(.system(.subheadline, weight: .black))
                Spacer(minLength: 0)
            }
            HStack(spacing: 10) {
                Image(systemName: "person.crop.circle.fill")
                    .font(.system(.footnote, weight: .bold))
                    .foregroundStyle(Palette.info)
                Text(driverLabel)
                    .font(.system(.footnote, weight: .semibold))
                    .foregroundStyle(Palette.textMuted)
                Spacer(minLength: 0)
            }

            if !missing.isEmpty {
                NoticeBanner(
                    symbol: "tray.fill",
                    title: "Faltan \(missing.count) documentos por cargar",
                    message: missing.map(\.title).joined(separator: " · ") + ". Solicítalos a \(missing.map(\.desk.label).uniqueOrdered.joined(separator: " y ")).",
                    tone: .amber
                )
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .panel()
    }

    private func section(
        subject: DossierSubject,
        caption: String,
        expected: [DossierDocument],
        filed: [FiledDocument]
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(subject.label)
                    .font(.system(.headline, weight: .black))
                Text(caption)
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.textMuted)
            }

            ForEach(expected) { kind in
                if let document = filed.first(where: { $0.kind == kind }) {
                    Button {
                        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                        opened = document
                    } label: {
                        DossierRow(document: document, now: now)
                    }
                    .buttonStyle(PressableCardStyle())
                } else {
                    DossierMissingRow(kind: kind)
                }
            }
        }
    }
}

// MARK: - Rows

private struct DossierRow: View {
    let document: FiledDocument
    let now: Date

    var body: some View {
        let status = document.status(now: now)

        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 14)
                    .fill(Palette.volt.opacity(0.12))
                Image(systemName: document.kind.symbol)
                    .font(.system(.body, weight: .bold))
                    .foregroundStyle(Palette.volt)
            }
            .frame(width: 46, height: 46)

            VStack(alignment: .leading, spacing: 3) {
                Text(document.kind.title)
                    .font(.system(.subheadline, weight: .bold))
                Text("\(document.kind.referenceLabel) \(document.reference)")
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.textMuted)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    StatePill(
                        text: status.label,
                        symbol: status.symbol,
                        tone: status == .onFile ? Palette.volt : status == .expiringSoon ? Palette.amber : Palette.danger,
                        compact: true
                    )
                    if document.kind.watermark != nil {
                        Text("COPIA")
                            .font(.system(size: 8, weight: .black))
                            .tracking(1)
                            .foregroundStyle(Palette.amber)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Palette.amber.opacity(0.14), in: .capsule)
                    }
                }
            }

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Palette.textMuted)
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .panel(cornerRadius: 20)
    }
}

private struct DossierMissingRow: View {
    let kind: DossierDocument

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.white.opacity(0.05))
                Image(systemName: "tray.fill")
                    .font(.system(.body, weight: .bold))
                    .foregroundStyle(Palette.textMuted)
            }
            .frame(width: 46, height: 46)

            VStack(alignment: .leading, spacing: 3) {
                Text(kind.title)
                    .font(.system(.subheadline, weight: .bold))
                    .foregroundStyle(Palette.textMuted)
                Text("Pendiente de cargar por \(kind.desk.label.lowercased())")
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.textMuted)
            }
            Spacer(minLength: 0)
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .panelFlat(cornerRadius: 20)
    }
}

// MARK: - Reader

/// Full sheet of one document. Renders the scan when the desk uploaded one, and the
/// data sheet the desk captured when it did not, always with its fiscal stamp.
struct DocumentReaderView: View {
    let document: FiledDocument
    var now: Date = Date()

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                StationBackground()

                ScrollView {
                    VStack(spacing: 14) {
                        DocumentPaper(document: document)

                        VStack(alignment: .leading, spacing: 10) {
                            CapsLabel(text: "Datos del documento")
                            DetailRow(label: document.kind.referenceLabel, value: document.reference)
                            DetailRow(label: document.kind.issuerLabel, value: document.issuer)
                            DetailRow(label: "Titular", value: document.subjectLabel)
                            if let issuedAt = document.issuedAt {
                                DetailRow(label: "Expedido", value: Fmt.dateShort(issuedAt))
                            }
                            DetailRow(label: "Vigencia", value: document.expiryText(now: now))
                            DetailRow(label: "Cargado por", value: document.uploadedBy)
                            DetailRow(label: "Fecha de carga", value: Fmt.dateShort(document.uploadedAt))
                        }
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .panel()

                        Text(document.kind.watermark == nil
                             ? "Documento de consulta responsabilidad de \(document.kind.desk.label.lowercased())."
                             : "Esta reproducción es únicamente informativa: no ampara efectos fiscales.")
                            .font(.system(size: 10))
                            .foregroundStyle(Palette.textMuted)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 10)
                    .padding(.bottom, 28)
                }
                .scrollIndicators(.hidden)
            }
            .navigationTitle(document.kind.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cerrar") { dismiss() }
                }
            }
        }
        .presentationContentInteraction(.scrolls)
        .preferredColorScheme(.dark)
    }
}

/// The sheet itself: scan or generated page, stamped when the paper is a fiscal copy.
struct DocumentPaper: View {
    let document: FiledDocument

    var body: some View {
        ZStack {
            if let data = document.image, let image = UIImage(data: data) {
                Color.black
                    .frame(height: 380)
                    .overlay {
                        Image(uiImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .allowsHitTesting(false)
                    }
            } else {
                generatedPage
            }
        }
        .clipShape(.rect(cornerRadius: 22))
        .overlay {
            RoundedRectangle(cornerRadius: 22).stroke(Palette.hairline, lineWidth: 1)
        }
        .overlay {
            if let watermark = document.kind.watermark {
                WatermarkOverlay(text: watermark)
            }
        }
    }

    private var generatedPage: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: document.kind.symbol)
                    .font(.system(.title3, weight: .black))
                Spacer()
                Text(document.kind.referenceLabel.uppercased())
                    .font(.system(size: 9, weight: .black))
                    .tracking(1.4)
            }
            .foregroundStyle(Color.black.opacity(0.55))

            Text(document.reference)
                .font(.system(size: 30, weight: .black, design: .rounded))
                .foregroundStyle(.black)
                .minimumScaleFactor(0.6)
                .lineLimit(1)

            Rectangle()
                .fill(Color.black.opacity(0.12))
                .frame(height: 1)

            paperRow(label: document.kind.issuerLabel, value: document.issuer)
            paperRow(label: "Titular", value: document.subjectLabel)
            if let issuedAt = document.issuedAt {
                paperRow(label: "Expedición", value: Fmt.dateShort(issuedAt))
            }
            if let expiresAt = document.expiresAt {
                paperRow(label: "Vigencia", value: Fmt.dateShort(expiresAt))
            }

            Spacer(minLength: 0)

            HStack(spacing: 8) {
                Image(systemName: document.kind.desk.symbol)
                    .font(.system(size: 10, weight: .bold))
                Text("Archivo digital · \(document.kind.desk.label)")
                    .font(.system(size: 10, weight: .semibold))
                Spacer()
                Text("TURNO EV")
                    .font(.system(size: 10, weight: .black))
                    .tracking(1.6)
            }
            .foregroundStyle(Color.black.opacity(0.45))
        }
        .padding(20)
        .frame(height: 380)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [Color(white: 0.96), Color(white: 0.87)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }

    private func paperRow(label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label.uppercased())
                .font(.system(size: 9, weight: .black))
                .tracking(1)
                .foregroundStyle(Color.black.opacity(0.4))
            Spacer(minLength: 10)
            Text(value)
                .font(.system(.footnote, weight: .bold))
                .foregroundStyle(Color.black.opacity(0.8))
                .multilineTextAlignment(.trailing)
        }
    }
}

/// Diagonal stamp for reproductions with no fiscal effect.
struct WatermarkOverlay: View {
    let text: String

    var body: some View {
        GeometryReader { proxy in
            VStack(spacing: 26) {
                ForEach(0..<5, id: \.self) { _ in
                    Text(text)
                        .font(.system(size: 17, weight: .black))
                        .tracking(2)
                        .foregroundStyle(Palette.danger.opacity(0.32))
                        .lineLimit(1)
                        .fixedSize()
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .rotationEffect(.degrees(-28))
        }
        .allowsHitTesting(false)
        .accessibilityLabel(text)
    }
}

private extension Array where Element == String {
    /// Keeps the first appearance of every value, preserving reading order.
    var uniqueOrdered: [String] {
        var seen: Set<String> = []
        return filter { seen.insert($0).inserted }
    }
}

#Preview {
    UnitDocumentsView(
        vehicleId: "veh-014",
        vehicleLabel: "TEV-014 · BYD Dolphin Mini 2025",
        driverId: "drv-1042",
        driverLabel: "Carlos Méndez Rivas · EV-1042"
    )
    .preferredColorScheme(.dark)
}
