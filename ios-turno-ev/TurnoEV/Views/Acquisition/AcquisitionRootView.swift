import SwiftUI

struct AcquisitionRootView: View {
    @Environment(FleetStore.self) private var fleet
    @Environment(\.scenePhase) private var scenePhase
    @State private var model: AcquisitionViewModel

    init(
        principal: SessionPrincipal,
        repository: any AcquisitionRepository = SupabaseAcquisitionRepository()
    ) {
        _model = State(
            initialValue: AcquisitionViewModel(principal: principal, repository: repository)
        )
    }

    var body: some View {
        NavigationStack {
            ZStack {
                StationBackground()
                content
            }
            .navigationTitle(model.destination == .administrator ? "Adquisiciones" : "DORI")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    SessionMenuButton()
                }
            }
            .task(id: model.principal.profileId) { await model.load() }
            .refreshable { await model.load() }
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active else { return }
                Task { await model.load() }
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .idle, .loading:
            VStack(spacing: 12) {
                ProgressView()
                Text("Cargando…")
                    .foregroundStyle(Palette.textMuted)
            }

        case .empty:
            message(
                symbol: "car.2.fill",
                title: "Sin solicitudes disponibles.",
                action: nil
            )

        case .failed:
            message(
                symbol: "wifi.exclamationmark",
                title: "No pudimos cargar la información.",
                action: "Reintentar"
            )

        case .content:
            if let summary = model.activeSummary {
                ScrollView {
                    Group {
                        switch model.destination {
                        case .administrator:
                            AcquisitionAdministratorHome(summary: summary)
                        case .provider:
                            AcquisitionProviderHome(
                                summary: summary,
                                requestCount: model.requests.count,
                                offers: model.offers
                            )
                        case nil:
                            message(
                                symbol: "lock.shield.fill",
                                title: "Acceso no permitido.",
                                action: nil
                            )
                        }
                    }
                    .padding(18)
                }
                .scrollIndicators(.hidden)
            } else {
                message(
                    symbol: "car.2.fill",
                    title: "Sin solicitudes disponibles.",
                    action: nil
                )
            }
        }
    }

    private func message(symbol: String, title: String, action: String?) -> some View {
        VStack(spacing: 16) {
            Image(systemName: symbol)
                .font(.system(size: 42, weight: .light))
                .foregroundStyle(Palette.volt)
            Text(title)
                .font(.headline)
                .multilineTextAlignment(.center)
            if let action {
                Button(action) { Task { await model.load() } }
                    .buttonStyle(.borderedProminent)
                    .tint(Palette.volt)
            }
        }
        .padding(28)
    }
}

private struct AcquisitionAdministratorHome: View {
    let summary: AcquisitionRequestSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                Text(summary.request.title)
                    .font(.system(.title, weight: .black))
                HStack(spacing: 18) {
                    metric(summary.securedCount, "asegurados")
                    metric(summary.decidingCount, "por decidir")
                    metric(summary.missingCount, "faltantes")
                }
            }

            requestCard(summary.request)

            NavigationLink {
                AcquisitionRequestDetailView(summary: summary)
            } label: {
                Label("Abrir solicitud", systemImage: "arrow.right")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .tint(Palette.volt)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func metric(_ value: Int, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(value)")
                .font(.title2.weight(.black))
            Text(label)
                .font(.caption)
                .foregroundStyle(Palette.textMuted)
        }
    }
}

private struct AcquisitionProviderHome: View {
    let summary: AcquisitionRequestSummary
    let requestCount: Int
    let offers: [AcquisitionOfferSummary]
    @State private var isNextBlockNoticePresented = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(
                requestCount == 1
                    ? "1 solicitud disponible"
                    : "\(requestCount) solicitudes disponibles"
            )
                .font(.system(.title2, weight: .black))

            requestCard(summary.request)

            Button {
                isNextBlockNoticePresented = true
            } label: {
                Label("Tengo unidades", systemImage: "car.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .tint(Palette.volt)
            .alert("Próximamente", isPresented: $isNextBlockNoticePresented) {
                Button("Entendido", role: .cancel) {}
            } message: {
                Text("El registro de unidades estará disponible en el siguiente bloque.")
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Mis operaciones")
                    .font(.headline)
                Text(offers.isEmpty
                     ? "Aún no tienes operaciones."
                     : "Tienes \(offers.count) operaciones en curso.")
                    .foregroundStyle(Palette.textMuted)
            }
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct AcquisitionRequestDetailView: View {
    let summary: AcquisitionRequestSummary

    var body: some View {
        ZStack {
            StationBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text(summary.request.title)
                        .font(.system(.title2, weight: .black))
                    requestCard(summary.request)
                    Text("\(summary.securedCount) asegurados · \(summary.missingCount) faltantes")
                        .font(.subheadline)
                        .foregroundStyle(Palette.textMuted)
                }
                .padding(18)
            }
        }
        .navigationTitle("Solicitud activa")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private func requestCard(_ request: AcquisitionRequest) -> some View {
    VStack(alignment: .leading, spacing: 8) {
        Text("Solicitud activa")
            .font(.caption.weight(.bold))
            .foregroundStyle(Palette.textMuted)
        Text(request.modelAndVersions)
            .font(.title3.weight(.bold))
        Text("\(request.yearRange) · Máx. \(request.maximumMileageText) km")
            .font(.subheadline)
            .foregroundStyle(Palette.textMuted)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(18)
    .panel()
}

#Preview("Administrador DORI") {
    let principal = SessionPrincipal(
        authUserId: UUID().uuidString,
        profileId: UUID().uuidString,
        name: "Administrador DORI",
        employeeNumber: "ADQ-TEST-ADMIN",
        email: "admin@ejemplo.test",
        role: .doriAdmin,
        environmentId: UUID().uuidString,
        stationId: nil,
        stationCode: nil,
        stationName: nil,
        shiftGroup: nil,
        shiftSlot: nil
    )
    AcquisitionRootView(
        principal: principal,
        repository: PreviewAcquisitionRepository(role: .doriAdmin)
    )
    .environment(FleetStore())
    .environment(LabStore())
}

#Preview("Usuario Proveedor") {
    let principal = SessionPrincipal(
        authUserId: UUID().uuidString,
        profileId: UUID().uuidString,
        name: "Agencia Puebla Centro",
        employeeNumber: "ADQ-TEST-PROV-001",
        email: "proveedor@ejemplo.test",
        role: .provider,
        environmentId: UUID().uuidString,
        stationId: nil,
        stationCode: nil,
        stationName: nil,
        shiftGroup: nil,
        shiftSlot: nil
    )
    AcquisitionRootView(
        principal: principal,
        repository: PreviewAcquisitionRepository(role: .provider)
    )
    .environment(FleetStore())
    .environment(LabStore())
}
