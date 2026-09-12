import SwiftUI

struct AcquisitionRootView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var model: AcquisitionViewModel
    @State private var selectedDestination: AcquisitionDockDestination = .home
    @State private var showConversations = false
    @State private var navigationID = UUID()
    private let repository: any AcquisitionRepository

    init(
        principal: SessionPrincipal,
        repository: any AcquisitionRepository = SupabaseAcquisitionRepository()
    ) {
        self.repository = repository
        _model = State(
            initialValue: AcquisitionViewModel(principal: principal, repository: repository)
        )
    }

    var body: some View {
        ZStack {
            StationBackground()
            NavigationStack {
                content
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            SessionMenuButton()
                        }
                    }
                    .navigationDestination(isPresented: $showConversations) {
                        if let membership = model.membership,
                           let profileID = UUID(uuidString: model.principal.profileId) {
                            ZStack {
                                StationBackground()
                                ScrollView {
                                    AcquisitionChatListView(
                                        membership: membership,
                                        profileID: profileID,
                                        repository: repository
                                    )
                                    .padding(18)
                                }
                            }
                            .navigationTitle("Conversaciones")
                            .navigationBarTitleDisplayMode(.inline)
                        }
                    }
            }
            .id(navigationID)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if let role = model.membership?.role {
                AcquisitionDock(
                    selection: dockSelection,
                    role: role,
                    badges: dockBadges(for: role)
                )
            }
        }
        .task(id: model.principal.profileId) { await model.load() }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task { await model.load() }
        }
        .onDisappear { model.stopObserving() }
    }

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .idle, .loading:
            statusMessage(symbol: nil, title: "Cargando…", action: nil)
        case .empty:
            statusMessage(
                symbol: "car.2.fill",
                title: "No hay solicitudes disponibles por ahora.",
                action: nil
            )
        case .failed:
            statusMessage(
                symbol: "wifi.exclamationmark",
                title: "No pudimos cargar la información.",
                action: "Reintentar"
            )
        case .content:
            if let membership = model.membership {
                destinationContent(membership: membership)
            } else {
                statusMessage(symbol: "lock.shield.fill", title: "Acceso no permitido.", action: nil)
            }
        }
    }

    @ViewBuilder
    private func destinationContent(membership: AcquisitionMembership) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                AcquisitionIdentityHeader(
                    name: model.organizationName,
                    subtitle: model.organizationSubtitle,
                    stationName: model.organizationLocation,
                    contextLine: model.organizationContext
                )

                switch selectedDestination {
                case .home:
                    home(membership: membership)
                case .requests:
                    requests(membership: membership)
                case .vehicles:
                    vehicles(membership: membership)
                case .contact:
                    contactDirectory
                case .account:
                    account(membership: membership)
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 18)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .refreshable { await model.load() }
        .navigationBarTitleDisplayMode(.inline)
    }

    private var dockSelection: Binding<AcquisitionDockDestination> {
        Binding(
            get: { selectedDestination },
            set: { destination in
                guard selectedDestination != destination else { return }
                selectedDestination = destination
                showConversations = false
                // The dock is intentionally global. Rebuilding the stack pops
                // any detail that was covering the newly selected section.
                navigationID = UUID()
            }
        )
    }

    @ViewBuilder
    private func home(membership: AcquisitionMembership) -> some View {
        if let summary = model.activeSummary {
            switch membership.role {
            case .doriAdmin:
                administratorHome(summary: summary, membership: membership)
            case .provider:
                providerHome(summary: summary, membership: membership)
            }
        }
    }

    private func administratorHome(
        summary: AcquisitionRequestSummary,
        membership: AcquisitionMembership
    ) -> some View {
        let attention = groupedOffers(.attention, role: .doriAdmin)
        let inProgress = groupedOffers(.inProgress, role: .doriAdmin)
        return VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 12) {
                AcquisitionSectionHeader(title: "Solicitud actual")
                NavigationLink {
                    AcquisitionRequestDetailView(
                        summary: summary,
                        membership: membership,
                        repository: repository,
                        onSubmitted: { _ in Task { await model.load() } }
                    )
                } label: {
                    AcquisitionAdminRequestCard(summary: summary)
                }
                .buttonStyle(.plain)
            }

            administratorOfferSection(
                title: "Necesita tu atención",
                symbol: "exclamationmark.triangle.fill",
                tint: Palette.amber,
                offers: attention,
                membership: membership,
                emptyText: "No tienes decisiones pendientes."
            )

            administratorOfferSection(
                title: "En proceso",
                symbol: "clock.fill",
                tint: Palette.info,
                offers: inProgress,
                membership: membership,
                emptyText: "No hay compras en proceso."
            )

            finishedLink(membership: membership)
        }
    }

    private func providerHome(
        summary: AcquisitionRequestSummary,
        membership: AcquisitionMembership
    ) -> some View {
        let attention = groupedOffers(.attention, role: .provider)
        let inProgress = groupedOffers(.inProgress, role: .provider)
        return VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 12) {
                AcquisitionSectionHeader(title: "Solicitud disponible")
                AcquisitionProviderRequestCard(summary: summary)
                NavigationLink {
                    AcquisitionOfferFormView(
                        request: summary.request,
                        membership: membership,
                        repository: repository,
                        onSubmitted: { _ in Task { await model.load() } }
                    )
                } label: {
                    Label("Ofrecer una unidad", systemImage: "car.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .buttonStyle(.borderedProminent)
                .tint(Palette.volt)

                NavigationLink {
                    AcquisitionRequestDetailView(
                        summary: summary,
                        membership: membership,
                        repository: repository,
                        onSubmitted: { _ in Task { await model.load() } }
                    )
                } label: {
                    Label("Ver requisitos completos", systemImage: "list.bullet.rectangle")
                        .font(.subheadline.weight(.bold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.bordered)
                .tint(Palette.volt)
            }

            offerSection(
                title: "Necesita tu atención",
                offers: attention,
                membership: membership,
                emptyText: "No tienes acciones pendientes."
            )

            offerSection(
                title: "Mis vehículos",
                offers: inProgress,
                membership: membership,
                emptyText: "Aún no has ofrecido vehículos."
            )

            finishedLink(membership: membership)
        }
    }

    private func requests(membership: AcquisitionMembership) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            AcquisitionSectionHeader(title: "Solicitudes", count: model.requests.count)
            ForEach(model.requests) { request in
                let summary = AcquisitionRequestSummary(request: request, offers: model.uniqueOffers)
                NavigationLink {
                    AcquisitionRequestDetailView(
                        summary: summary,
                        membership: membership,
                        repository: repository,
                        onSubmitted: { _ in Task { await model.load() } }
                    )
                } label: {
                    AcquisitionRequestCard(
                        request: request,
                        progressText: membership.role == .doriAdmin
                            ? "\(summary.securedCount) confirmados · \(summary.missingCount) por conseguir"
                            : nil,
                        audience: membership.role
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func vehicles(membership: AcquisitionMembership) -> some View {
        VStack(alignment: .leading, spacing: 24) {
            offerSection(
                title: membership.role == .doriAdmin ? "Operaciones" : "Mis vehículos",
                offers: groupedOffers(.attention, role: membership.role)
                    + groupedOffers(.inProgress, role: membership.role),
                membership: membership,
                emptyText: "No hay vehículos activos."
            )
            offerSection(
                title: "Terminadas",
                offers: groupedOffers(.finished, role: membership.role),
                membership: membership,
                emptyText: "Aún no hay operaciones terminadas."
            )
        }
    }

    private func account(membership: AcquisitionMembership) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            AcquisitionSectionHeader(title: "Cuenta")
            AcquisitionContactCard(
                organization: model.organizationName,
                roleDescription: membership.role == .doriAdmin
                    ? "Administrador DORI"
                    : "Proveedor autorizado",
                personName: model.principal.name
            )
            Text(membership.role == .provider
                 ? "Estos datos son administrados por DORI."
                 : "Tu acceso corresponde a esta operación de DORI.")
                .font(.subheadline)
                .foregroundStyle(Palette.textMuted)
        }
    }

    private var contactDirectory: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 12) {
                AcquisitionSectionHeader(title: "Personas", count: model.counterpartContacts.count)
                if model.counterpartContacts.isEmpty {
                    Text("Información de contacto pendiente")
                        .font(.subheadline)
                        .foregroundStyle(Palette.textMuted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(18)
                        .panelFlat()
                } else {
                    ForEach(model.counterpartContacts) { contact in
                        AcquisitionInstitutionalContactCard(
                            contact: contact,
                            openChat: { showConversations = true }
                        )
                    }
                }
            }

            VStack(alignment: .leading, spacing: 12) {
                if let membership = model.membership,
                   let profileID = UUID(uuidString: model.principal.profileId) {
                    AcquisitionChatListView(
                        membership: membership,
                        profileID: profileID,
                        repository: repository
                    )
                }
            }
        }
    }

    private func offerSection(
        title: String,
        offers: [AcquisitionOfferSummary],
        membership: AcquisitionMembership,
        emptyText: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            AcquisitionSectionHeader(title: title, count: offers.count)
            if offers.isEmpty {
                Text(emptyText)
                    .font(.subheadline)
                    .foregroundStyle(Palette.textMuted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(18)
                    .panelFlat()
            } else {
                ForEach(offers) { offer in
                    NavigationLink {
                        AcquisitionOfferDetailView(
                            offerID: offer.id,
                            membership: membership,
                            repository: repository,
                            onChanged: { Task { await model.load() } }
                        )
                    } label: {
                        AcquisitionDashboardVehicleCard(
                            offer: offer,
                            role: membership.role,
                            supplierName: model.supplierName(for: offer),
                            actionTitle: actionTitle(for: offer, role: membership.role)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func administratorOfferSection(
        title: String,
        symbol: String,
        tint: Color,
        offers: [AcquisitionOfferSummary],
        membership: AcquisitionMembership,
        emptyText: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            AcquisitionOperationalSectionHeader(
                title: title,
                symbol: symbol,
                tint: tint,
                count: offers.count
            )
            if offers.isEmpty {
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Palette.volt)
                    Text(emptyText)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Palette.textMuted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(18)
                .panelFlat()
            } else {
                ForEach(offers) { offer in
                    NavigationLink {
                        AcquisitionOfferDetailView(
                            offerID: offer.id,
                            membership: membership,
                            repository: repository,
                            onChanged: { Task { await model.load() } }
                        )
                    } label: {
                        AcquisitionDashboardVehicleCard(
                            offer: offer,
                            role: .doriAdmin,
                            supplierName: model.supplierName(for: offer),
                            actionTitle: administratorActionTitle(for: offer)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func administratorActionTitle(for offer: AcquisitionOfferSummary) -> String {
        return switch offer.status {
        case "submitted": "Revisar propuesta"
        case "negotiating", "price_agreed": "Resolver negociación"
        case "accepted_with_condition": "Resolver condición"
        default: "Ver unidad"
        }
    }

    private func actionTitle(for offer: AcquisitionOfferSummary, role: AcquisitionRole) -> String {
        if role == .doriAdmin { return administratorActionTitle(for: offer) }
        switch offer.status {
        case "negotiating": "Revisar oferta"
        case "accepted_with_condition": "Resolver"
        default: "Ver unidad"
        }
    }

    private func dockBadges(for role: AcquisitionRole) -> [AcquisitionDockDestination: Int] {
        let attention = groupedOffers(.attention, role: role).count
        var badges: [AcquisitionDockDestination: Int] = [:]
        if attention > 0 { badges[.vehicles] = attention }
        if model.unreadChatCount > 0 { badges[.contact] = model.unreadChatCount }
        return badges
    }

    private func finishedLink(membership: AcquisitionMembership) -> some View {
        let finished = groupedOffers(.finished, role: membership.role)
        return Button {
            selectedDestination = .vehicles
        } label: {
            HStack {
                Text("Ver operaciones terminadas")
                    .font(.headline)
                Spacer()
                Text("\(finished.count)")
                Image(systemName: "arrow.right")
            }
            .foregroundStyle(Palette.text)
            .padding(18)
            .panelFlat()
        }
        .buttonStyle(.plain)
    }

    private func groupedOffers(
        _ group: AcquisitionHomeGroup,
        role: AcquisitionRole
    ) -> [AcquisitionOfferSummary] {
        model.uniqueOffers.filter {
            AcquisitionHumanStatus.group(for: $0.status, role: role) == group
        }
    }

    private func phasePlaceholder(title: String, message: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            AcquisitionSectionHeader(title: title)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(Palette.textMuted)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(18)
                .panel()
        }
    }

    private func statusMessage(symbol: String?, title: String, action: String?) -> some View {
        VStack(spacing: 16) {
            if let symbol {
                Image(systemName: symbol)
                    .font(.system(size: 42, weight: .light))
                    .foregroundStyle(Palette.volt)
            } else {
                ProgressView()
            }
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

private struct AcquisitionRequestDetailView: View {
    let summary: AcquisitionRequestSummary
    let membership: AcquisitionMembership
    let repository: any AcquisitionRepository
    let onSubmitted: (AcquisitionOfferSummary) -> Void

    var body: some View {
        ZStack {
            StationBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Solicitud actual")
                                .font(.system(.title, weight: .black))
                            Text("Detalles y requisitos")
                                .font(.title3.weight(.semibold))
                                .foregroundStyle(Palette.textMuted)
                        }
                        Spacer()
                        Label("Activa", systemImage: "circle.fill")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(Palette.volt)
                    }

                    if membership.role == .provider {
                        AcquisitionProviderRequestCard(summary: summary)
                    } else {
                        AcquisitionAdminRequestCard(summary: summary)
                    }

                    AcquisitionOperationalSectionHeader(
                        title: "Requisitos de la unidad",
                        symbol: "checklist",
                        tint: Palette.volt,
                        count: summary.request.visibleRequirements.count
                    )
                    AcquisitionRequirementsGrid(request: summary.request)

                    VStack(alignment: .leading, spacing: 7) {
                        Label("Importante", systemImage: "info.circle.fill")
                            .font(.headline)
                            .foregroundStyle(Palette.info)
                        Text("Solo se aceptarán unidades que cumplan con todos los requisitos. Revisa los detalles antes de enviar una propuesta.")
                            .font(.subheadline)
                            .foregroundStyle(Palette.textMuted)
                    }
                    .padding(16)
                    .background(Palette.info.opacity(0.10), in: RoundedRectangle(cornerRadius: 16))

                    if membership.role == .provider {
                        NavigationLink {
                            AcquisitionOfferFormView(
                                request: summary.request,
                                membership: membership,
                                repository: repository,
                                onSubmitted: onSubmitted
                            )
                        } label: {
                            Label("Ofrecer una unidad", systemImage: "arrow.right")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Palette.volt)
                    }
                }
                .padding(18)
            }
        }
        .navigationTitle("Solicitud")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview("Administrador DORI") {
    AcquisitionRootView(
        principal: previewPrincipal(role: .doriAdmin),
        repository: PreviewAcquisitionRepository(role: .doriAdmin)
    )
    .environment(FleetStore())
    .environment(LabStore())
}

#Preview("Usuario Proveedor") {
    AcquisitionRootView(
        principal: previewPrincipal(role: .provider),
        repository: PreviewAcquisitionRepository(role: .provider)
    )
    .environment(FleetStore())
    .environment(LabStore())
}

@MainActor
private func previewPrincipal(role: StaffRole) -> SessionPrincipal {
    SessionPrincipal(
        authUserId: UUID().uuidString,
        profileId: UUID().uuidString,
        name: role == .provider ? "BYD Iztacalco" : "Administrador DORI",
        employeeNumber: role == .provider ? "ADQ-TEST-PROV-001" : "ADQ-TEST-ADMIN",
        email: "cuenta@ejemplo.test",
        role: role,
        environmentId: UUID().uuidString,
        stationId: nil,
        stationCode: nil,
        stationName: nil,
        shiftGroup: nil,
        shiftSlot: nil
    )
}
