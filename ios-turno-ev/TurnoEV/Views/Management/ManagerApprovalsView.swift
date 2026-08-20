import SwiftUI
import UIKit

/// Autorizaciones: the manager's desk. Extra plazas, credits and unit retirements
/// arrive from recruitment and the workshop, and leave signed or returned.
///
/// Bonuses are not here and never will be: the goal engine releases and cancels them
/// by itself, and only the national administration can change what they pay.
struct ManagerApprovalsView: View {
    let regional: RegionalStore
    let header: ManagerHeader
    @Binding var filter: RequestFilter
    let onOpenRequest: (String) -> Void

    @State private var search: String = ""
    @State private var showsLog: Bool = false
    @State private var openedDeposit: CashDeposit?
    @State private var depositVersion: Int = 0

    private var visible: [RegionalRequest] {
        regional.requests(matching: filter, search: search)
    }

    var body: some View {
        ZStack {
            ManagementBackground()

            ScrollView {
                VStack(spacing: 14) {
                    header
                    modeSwitch

                    if showsLog {
                        log
                    } else {
                        inbox
                    }
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 34)
            }
            .scrollIndicators(.hidden)
            .searchable(text: $search, prompt: "Conductor, unidad o estación")
        }
    }

    private var modeSwitch: some View {
        HStack(spacing: 0) {
            ForEach([false, true], id: \.self) { isLog in
                Button {
                    showsLog = isLog
                } label: {
                    Text(isLog ? "Historial" : "Bandeja (\(regional.pendingRequests.count))")
                        .font(.system(.footnote, weight: .black))
                        .foregroundStyle(showsLog == isLog ? Palette.canvas : Palette.textMuted)
                        .frame(maxWidth: .infinity, minHeight: 38)
                        .background(showsLog == isLog ? MgTone.accent : .clear, in: .capsule)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(Palette.surface.opacity(0.85), in: .capsule)
        .overlay { Capsule().stroke(Palette.hairline, lineWidth: 1) }
    }

    // MARK: - Inbox

    private var inbox: some View {
        VStack(spacing: 12) {
            exposure
            cashDeposits

            FilterScroller(
                items: RequestFilter.allCases,
                title: { $0.label },
                symbol: { $0.symbol },
                count: { regional.pendingCount(for: $0) },
                selection: $filter,
                accent: MgTone.accent
            )
            .padding(.horizontal, -18)

            if visible.isEmpty {
                SupEmptyState(
                    symbol: "tray.full.fill",
                    title: "Bandeja vacía",
                    message: "No hay solicitudes de este tipo esperando tu firma en la estación.",
                    accent: MgTone.accent
                )
            } else {
                LazyVStack(spacing: 10) {
                    ForEach(visible) { request in
                        RequestRow(request: request, now: regional.now) { onOpenRequest(request.id) }
                    }
                }
            }
        }
    }

    /// Cash deposits reported by the drivers of the station. Cash is not an authorized
    /// way to charge, so every slip that lands here is an exception the manager has to
    /// see the same day — not a request to sign, a fact to acknowledge.
    @ViewBuilder
    private var cashDeposits: some View {
        let deposits = CashDepositLedger.deposits(stationId: regional.station.id)
        let pending = deposits.filter { !$0.isAcknowledged }

        if !deposits.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                SupSectionHeader(
                    title: "Depósitos en efectivo",
                    subtitle: pending.isEmpty
                        ? "Todos revisados"
                        : "\(pending.count) por revisar · \(Fmt.mxn(pending.reduce(0) { $0 + $1.declaredMxn }))",
                    accent: MgTone.accent
                )

                ForEach(deposits.prefix(6)) { deposit in
                    Button {
                        openedDeposit = deposit
                    } label: {
                        CashDepositRow(deposit: deposit, now: regional.now)
                    }
                    .buttonStyle(.plain)
                }

                Text("El efectivo no es forma de pago autorizada. Estos avisos existen para que ningún peso recibido en una emergencia se quede fuera de la cuenta de la red.")
                    .font(.system(size: 10))
                    .foregroundStyle(Palette.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .id(depositVersion)
            .padding(15)
            .panel()
            .sheet(item: $openedDeposit) { deposit in
                CashDepositDetailView(deposit: deposit, now: regional.now) {
                    CashDepositLedger.acknowledge(id: deposit.id, at: regional.now)
                    depositVersion += 1
                }
            }
        }
    }

    private var exposure: some View {
        let metrics = regional.metrics
        return HStack(spacing: 10) {
            StatTile(
                label: "Por firmar",
                value: "\(metrics.pendingRequests)",
                hint: metrics.agingRequests > 0 ? "\(metrics.agingRequests) con más de 24 h" : "Sin rezago",
                tone: metrics.agingRequests > 0 ? .danger : .amber
            )
            StatTile(
                label: "Bonos",
                value: "Automáticos",
                hint: "No pasan por tu firma",
                tone: .volt
            )
        }
    }

    // MARK: - Log

    private var log: some View {
        let resolved = regional.resolvedRequests
        return VStack(alignment: .leading, spacing: 10) {
            SupSectionHeader(
                title: "Decisiones firmadas",
                subtitle: "Cada autorización queda con su nota y su hora",
                accent: MgTone.accent
            )

            if resolved.isEmpty {
                SupEmptyState(
                    symbol: "clock.arrow.circlepath",
                    title: "Sin decisiones",
                    message: "Cuando autorices o rechaces una solicitud aparecerá en este historial.",
                    accent: MgTone.accent
                )
            } else {
                ForEach(resolved) { request in
                    ResolvedRequestRow(request: request)
                }
            }
        }
    }
}

/// One deposit in the manager's inbox, with the verdict of the slip reader visible.
private struct CashDepositRow: View {
    let deposit: CashDeposit
    let now: Date

    private var tone: Color {
        switch deposit.match {
        case .matched: MgTone.good
        case .mismatched: MgTone.bad
        case .unreadable, .notChecked: Palette.amber
        }
    }

    var body: some View {
        HStack(spacing: 11) {
            Image(systemName: deposit.match.symbol)
                .font(.system(.footnote, weight: .bold))
                .foregroundStyle(tone)
                .frame(width: 34, height: 34)
                .background(tone.opacity(0.14), in: .rect(cornerRadius: 12))

            VStack(alignment: .leading, spacing: 2) {
                Text(deposit.driverName)
                    .font(.system(.footnote, weight: .bold))
                    .lineLimit(1)
                Text("\(deposit.vehicleNumber) · \(deposit.match.label)")
                    .font(.system(size: 10))
                    .foregroundStyle(Palette.textMuted)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            VStack(alignment: .trailing, spacing: 2) {
                Text(Fmt.mxn(deposit.declaredMxn))
                    .font(.system(.subheadline, weight: .black))
                    .monospacedDigit()
                    .foregroundStyle(tone)
                Text(deposit.isAcknowledged ? "Revisado" : Fmt.relative(deposit.createdAt, from: now))
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Palette.textMuted)
            }
        }
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .panelFlat(cornerRadius: 16)
    }
}

/// Full slip: what the driver typed, what the photo said and the account it went to.
private struct CashDepositDetailView: View {
    let deposit: CashDeposit
    let now: Date
    let onAcknowledge: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                ManagementBackground()

                ScrollView {
                    VStack(spacing: 14) {
                        VStack(alignment: .leading, spacing: 8) {
                            CapsLabel(text: "Aviso de depósito")
                            Text(deposit.driverName)
                                .font(.system(.headline, weight: .black))
                            Text("\(deposit.vehicleNumber) · \(Fmt.dateShort(deposit.createdAt)) · \(Fmt.clock(deposit.createdAt))")
                                .font(.system(size: 11))
                                .foregroundStyle(Palette.textMuted)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(15)
                        .panel()

                        HStack(spacing: 8) {
                            ReadingTile(label: "Capturado", value: Fmt.mxn(deposit.declaredMxn), tone: .primary)
                            ReadingTile(
                                label: "En el ticket",
                                value: deposit.detectedMxn.map { Fmt.mxn($0) } ?? "—",
                                hint: deposit.match.label,
                                tone: deposit.match == .matched ? MgTone.good : Palette.amber
                            )
                        }

                        if let slip = deposit.slip, let image = UIImage(data: slip) {
                            Color.black
                                .frame(height: 320)
                                .overlay {
                                    Image(uiImage: image)
                                        .resizable()
                                        .aspectRatio(contentMode: .fit)
                                        .allowsHitTesting(false)
                                }
                                .clipShape(.rect(cornerRadius: 20))
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            CapsLabel(text: "Cuenta receptora")
                            Text(deposit.bank)
                                .font(.system(.subheadline, weight: .bold))
                            Text("CLABE \(deposit.clabe)")
                                .font(.system(size: 11))
                                .monospacedDigit()
                                .foregroundStyle(Palette.textMuted)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(15)
                        .panel()

                        if deposit.isAcknowledged {
                            NoticeBanner(
                                symbol: "checkmark.seal.fill",
                                title: "Aviso revisado",
                                message: "Ya marcaste este depósito como revisado en la bandeja de la estación.",
                                tone: .volt
                            )
                        } else {
                            BigButton(title: "Marcar como revisado", symbol: "checkmark.seal.fill") {
                                onAcknowledge()
                                dismiss()
                            }
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 6)
                    .padding(.bottom, 34)
                }
                .scrollIndicators(.hidden)
            }
            .navigationTitle("Depósito en efectivo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cerrar") { dismiss() }
                }
            }
        }
        .presentationContentInteraction(.scrolls)
    }
}

private struct ResolvedRequestRow: View {
    let request: RegionalRequest

    private var tone: Color { request.status == .authorized ? MgTone.good : MgTone.bad }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 10) {
                Image(systemName: request.status == .authorized ? "checkmark.seal.fill" : "xmark.octagon.fill")
                    .font(.system(.footnote, weight: .bold))
                    .foregroundStyle(tone)
                    .frame(width: 30, height: 30)
                    .background(tone.opacity(0.14), in: .rect(cornerRadius: 10))

                VStack(alignment: .leading, spacing: 2) {
                    Text(request.subject)
                        .font(.system(.subheadline, weight: .black))
                        .lineLimit(1)
                    Text("\(request.kind.label) · \(request.stationCode)")
                        .font(.system(size: 10))
                        .foregroundStyle(Palette.textMuted)
                }
                Spacer(minLength: 4)
                VStack(alignment: .trailing, spacing: 2) {
                    Text(request.status.label)
                        .font(.system(size: 10, weight: .black))
                        .foregroundStyle(tone)
                    if let resolvedAt = request.resolvedAt {
                        Text("\(Fmt.dateShort(resolvedAt)) · \(Fmt.clock(resolvedAt))")
                            .font(.system(size: 10))
                            .foregroundStyle(Palette.textMuted)
                            .monospacedDigit()
                    }
                }
            }

            if let note = request.decisionNote {
                Text(note)
                    .font(.caption)
                    .foregroundStyle(Palette.textMuted)
                    .multilineTextAlignment(.leading)
            }
        }
        .padding(13)
        .panelFlat()
    }
}

// MARK: - Detail

/// The decision itself: context, checklist and signature. Nothing is signed until every
/// point of the checklist is confirmed, which keeps the hierarchy auditable.
struct ManagerRequestDetailView: View {
    let regional: RegionalStore
    let requestId: String

    @Environment(\.dismiss) private var dismiss

    @State private var note: String = ""
    @State private var rejection: String = ""
    @State private var isRejecting: Bool = false
    @State private var feedback: String?

    private var request: RegionalRequest? { regional.request(id: requestId) }

    var body: some View {
        NavigationStack {
            ZStack {
                ManagementBackground()

                if let request {
                    ScrollView {
                        VStack(spacing: 14) {
                            summary(request)
                            if let asset = request.photoAsset {
                                evidence(asset: asset, request: request)
                            }
                            checklist(request)
                            decision(request)
                        }
                        .padding(.horizontal, 18)
                        .padding(.bottom, 34)
                    }
                    .scrollIndicators(.hidden)
                } else {
                    SupEmptyState(
                        symbol: "checkmark.seal.fill",
                        title: "Solicitud resuelta",
                        message: "Esta solicitud ya salió de tu bandeja.",
                        accent: MgTone.accent
                    )
                    .padding(18)
                }
            }
            .navigationTitle(request?.kind.label ?? "Autorización")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cerrar") { dismiss() }
                }
            }
            .alert("Rechazar solicitud", isPresented: $isRejecting) {
                TextField("Motivo para el solicitante", text: $rejection)
                Button("Rechazar", role: .destructive) {
                    let reason = rejection.trimmingCharacters(in: .whitespacesAndNewlines)
                    regional.reject(
                        requestId: requestId,
                        reason: reason.isEmpty ? "Solicitud devuelta por la gerencia de la estación." : reason
                    )
                    dismiss()
                }
                Button("Cancelar", role: .cancel) {}
            } message: {
                Text("El motivo se envía a quien la generó para que la corrija.")
            }
        }
    }

    // MARK: - Sections

    private func summary(_ request: RegionalRequest) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: request.kind.symbol)
                    .font(.title3)
                    .foregroundStyle(request.kind.tone)
                    .frame(width: 48, height: 48)
                    .background(request.kind.tone.opacity(0.14), in: .rect(cornerRadius: 15))

                VStack(alignment: .leading, spacing: 3) {
                    Text(request.subject)
                        .font(.system(.headline, weight: .black))
                        .lineLimit(2)
                    Text("\(request.kind.subjectLabel) · \(request.stationCode)")
                        .font(.caption)
                        .foregroundStyle(Palette.textMuted)
                }
                Spacer(minLength: 0)
                if let amount = request.amountMxn {
                    VStack(alignment: .trailing, spacing: 2) {
                        CapsLabel(text: request.kind == .credit ? "Abono semanal" : "Monto")
                        Text(Fmt.mxn(amount))
                            .font(.system(.headline, weight: .black))
                            .monospacedDigit()
                            .foregroundStyle(request.kind.tone)
                    }
                }
            }

            if request.isLiveSession {
                NoticeBanner(
                    symbol: "antenna.radiowaves.left.and.right",
                    title: "Solicitud en vivo",
                    message: "Viene de un conductor que está usando la app. Tu decisión le llega como aviso al instante.",
                    tone: .volt
                )
            }

            if request.isAging(now: regional.now) {
                NoticeBanner(
                    symbol: "hourglass.badge.plus",
                    title: "Detenida \(request.ageHours(now: regional.now)) horas",
                    message: "La estación está esperando tu firma para continuar.",
                    tone: .danger
                )
            }

            Text(request.detail)
                .font(.subheadline)
                .foregroundStyle(Palette.textMuted)

            Divider().overlay(Palette.hairline)

            DetailRow(label: request.kind.subjectLabel, value: request.subjectDetail)
            DetailRow(label: "Solicitada por", value: "\(request.requestedBy) · \(request.requestedByRole.shortLabel)")
            DetailRow(label: "Recibida", value: "\(Fmt.dateShort(request.createdAt)) · \(Fmt.clock(request.createdAt))")
            DetailRow(label: "Prioridad", value: request.priority.label)
            if let station = regional.station(id: request.stationId) {
                DetailRow(label: "Estación", value: "\(station.name) · \(station.city)")
                DetailRow(label: "Salud de la estación", value: station.health.label)
            }
        }
        .padding(16)
        .panel()
    }

    private func evidence(asset: String, request: RegionalRequest) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            CapsLabel(text: "Evidencia adjunta")
            EvidenceThumb(
                caption: request.kind == .retirement ? "Estado de la unidad" : "Unidad del contrato",
                asset: asset
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .panel()
    }

    private func checklist(_ request: RegionalRequest) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SupSectionHeader(
                title: "Puntos a validar",
                subtitle: "\(request.completedChecks) de \(request.requiredChecks.count) confirmados",
                accent: MgTone.accent
            )

            ForEach(request.requiredChecks) { check in
                RequestCheckRow(
                    check: check,
                    isDone: request.isChecked(check)
                ) {
                    regional.setCheck(check, on: request.id, value: !request.isChecked(check))
                }
            }
        }
    }

    private func decision(_ request: RegionalRequest) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            CapsLabel(text: "Nota de la decisión")
            TextField("Opcional: contexto para el expediente", text: $note, axis: .vertical)
                .lineLimit(2...4)
                .padding(14)
                .panelFlat()

            if let feedback {
                NoticeBanner(symbol: "exclamationmark.triangle.fill", title: feedback, tone: .amber)
            }

            BigButton(
                title: request.isReadyToAuthorize ? "Autorizar" : "Confirma los \(request.requiredChecks.count) puntos",
                symbol: "checkmark.seal.fill",
                isEnabled: request.isReadyToAuthorize
            ) {
                if regional.authorize(requestId: request.id, note: note.trimmingCharacters(in: .whitespacesAndNewlines)) {
                    dismiss()
                } else {
                    feedback = "Falta confirmar algún punto de la lista."
                }
            }

            BigButton(title: "Rechazar y devolver", symbol: "xmark.octagon.fill", tone: .danger) {
                isRejecting = true
            }
        }
        .padding(16)
        .panel()
    }
}

/// One point of the manager's checklist.
private struct RequestCheckRow: View {
    let check: RequestCheck
    let isDone: Bool
    let action: () -> Void

    var body: some View {
        Button {
            UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
            action()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: isDone ? "checkmark.circle.fill" : "circle")
                    .font(.system(.title3, weight: .bold))
                    .foregroundStyle(isDone ? MgTone.good : Palette.textMuted)
                    .frame(width: 30)

                VStack(alignment: .leading, spacing: 2) {
                    Text(check.title)
                        .font(.system(.subheadline, weight: .bold))
                        .multilineTextAlignment(.leading)
                    Text(check.hint)
                        .font(.caption2)
                        .foregroundStyle(Palette.textMuted)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
            }
            .padding(13)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                (isDone ? MgTone.good.opacity(0.1) : Palette.surfaceRaised.opacity(0.7)),
                in: .rect(cornerRadius: 16)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 16)
                    .stroke(isDone ? MgTone.good.opacity(0.45) : Palette.hairline, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }
}
