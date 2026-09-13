import SwiftUI

struct AcquisitionRootView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var model: AcquisitionViewModel
    @State private var selectedDestination: AcquisitionDockDestination = .home
    @State private var showConversations = false
    @State private var navigationID = UUID()
    @State private var push = AcquisitionPushCoordinator.shared
    @State private var pushDestination: AcquisitionPushDestination?
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
                    // The custom dock belongs to section roots only. Applying
                    // the inset to the root content keeps it out of pushed
                    // Chat, Unit and Offer screens and away from their CTAs.
                    .safeAreaInset(edge: .bottom, spacing: 0) {
                        if let role = model.membership?.role {
                            AcquisitionDock(
                                selection: dockSelection,
                                role: role,
                                badges: dockBadges(for: role)
                            )
                        }
                    }
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
                    .navigationDestination(isPresented: pushDestinationBinding) {
                        if let destination = pushDestination,
                           let membership = model.membership {
                            pushedView(destination, membership: membership)
                        }
                    }
            }
            .id(navigationID)
        }
        .task(id: model.principal.profileId) {
            await model.load()
            if let membership = model.membership {
                await push.activate(membership: membership, repository: repository)
            }
            openPendingPushDestination()
        }
        .onChange(of: push.pendingDestination) { _, _ in
            openPendingPushDestination()
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task {
                await model.load()
                await push.refreshBadge()
            }
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

    private var pushDestinationBinding: Binding<Bool> {
        Binding(
            get: { pushDestination != nil },
            set: { if !$0 { pushDestination = nil } }
        )
    }

    @ViewBuilder
    private func pushedView(
        _ destination: AcquisitionPushDestination,
        membership: AcquisitionMembership
    ) -> some View {
        switch destination {
        case .offer(let offerID):
            AcquisitionOfferDetailView(
                offerID: offerID,
                membership: membership,
                repository: repository,
                onChanged: { Task { await model.load() } }
            )
        case .chat(let threadID, _):
            AcquisitionPushChatLauncherView(
                threadID: threadID,
                membership: membership,
                profileID: membership.profileID,
                repository: repository
            )
        case .request(let requestID):
            if let request = model.requests.first(where: { $0.id == requestID }) {
                AcquisitionRequestDetailView(
                    summary: AcquisitionRequestSummary(request: request, offers: model.uniqueOffers),
                    membership: membership,
                    repository: repository,
                    onSubmitted: { _ in Task { await model.load() } }
                )
            } else {
                ContentUnavailableView(
                    "La solicitud ya no está disponible",
                    systemImage: "doc.text.magnifyingglass"
                )
            }
        }
    }

    private func openPendingPushDestination() {
        guard model.membership != nil, let destination = push.pendingDestination else { return }
        pushDestination = destination
        Task { await push.consume(destination) }
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

            compactRequestsSummary(summary: summary, role: .doriAdmin)
            recentActivity(role: .doriAdmin, membership: membership)

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
            offerSection(
                title: "Necesita tu atención",
                offers: attention,
                membership: membership,
                emptyText: "No tienes acciones pendientes."
            )

            offerSection(
                title: "Mis unidades en proceso",
                offers: inProgress,
                membership: membership,
                emptyText: "Aún no has ofrecido vehículos."
            )

            compactRequestsSummary(summary: summary, role: .provider)

            Button { selectedDestination = .contact } label: {
                HStack {
                    Label("Mensajes nuevos", systemImage: "bubble.left.and.bubble.right.fill")
                        .font(.headline)
                    Spacer()
                    Text("\(model.unreadChatCount)").font(.headline.monospacedDigit())
                    Image(systemName: "chevron.right")
                }
                .padding(16).panelFlat()
            }
            .buttonStyle(.plain)

            finishedLink(membership: membership)
        }
    }

    private func compactRequestsSummary(
        summary: AcquisitionRequestSummary,
        role: AcquisitionRole
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            AcquisitionSectionHeader(
                title: role == .doriAdmin ? "Solicitudes activas" : "Solicitudes disponibles",
                count: model.requests.count
            )
            HStack(spacing: 12) {
                Image(systemName: "doc.text.fill")
                    .font(.title2)
                    .foregroundStyle(Palette.volt)
                VStack(alignment: .leading, spacing: 3) {
                    Text(summary.request.modelAndVersions).font(.headline)
                    Text("\(summary.request.targetQuantity) vehículos · \(summary.request.yearRange)")
                        .font(.subheadline).foregroundStyle(Palette.textMuted)
                }
                Spacer()
            }
            Button(role == .doriAdmin ? "Ver solicitudes" : "Revisar solicitudes") {
                selectedDestination = .requests
            }
            .buttonStyle(.bordered).tint(Palette.volt)
        }
        .padding(16).panelFlat()
    }

    private func recentActivity(
        role: AcquisitionRole,
        membership: AcquisitionMembership
    ) -> some View {
        let recent = model.uniqueOffers.sorted {
            (model.activity(for: $0)?.createdAt ?? $0.submittedAt ?? .distantPast)
                > (model.activity(for: $1)?.createdAt ?? $1.submittedAt ?? .distantPast)
        }.prefix(3)
        return VStack(alignment: .leading, spacing: 10) {
            AcquisitionSectionHeader(title: "Actividad reciente", count: recent.count)
            ForEach(Array(recent)) { offer in
                NavigationLink {
                    AcquisitionOfferDetailView(
                        offerID: offer.id,
                        membership: membership,
                        repository: repository,
                        onChanged: { Task { await model.load() } }
                    )
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "clock.arrow.circlepath")
                            .foregroundStyle(Palette.info)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(offer.modelAndVersion) \(offer.yearText)").font(.subheadline.weight(.bold))
                            Text(AcquisitionHumanStatus.title(for: offer.status, role: role))
                                .font(.caption).foregroundStyle(Palette.textMuted)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").foregroundStyle(Palette.textMuted)
                    }
                    .padding(13).panelFlat()
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func requests(membership: AcquisitionMembership) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                AcquisitionSectionHeader(title: "Solicitudes", count: model.requests.count)
                Spacer()
                if membership.role == .doriAdmin {
                    NavigationLink {
                        AcquisitionNewRequestView(
                            repository: repository,
                            onPublished: { _ in Task { await model.load() } }
                        )
                    } label: {
                        Label("Nueva solicitud", systemImage: "plus")
                            .font(.subheadline.weight(.bold))
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Palette.volt)
                }
            }
            ForEach(model.requests) { request in
                let summary = AcquisitionRequestSummary(request: request, offers: model.uniqueOffers)
                if membership.role == .provider {
                    AcquisitionRequestCard(
                        request: request,
                        progressText: nil,
                        audience: membership.role
                    )
                    HStack(spacing: 10) {
                        NavigationLink {
                            AcquisitionRequestDetailView(
                                summary: summary,
                                membership: membership,
                                repository: repository,
                                onSubmitted: { _ in Task { await model.load() } }
                            )
                        } label: {
                            Label("Ver requisitos", systemImage: "list.bullet.rectangle")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .tint(Palette.volt)

                        NavigationLink {
                            AcquisitionOfferFormView(
                                request: request,
                                membership: membership,
                                repository: repository,
                                onSubmitted: { _ in Task { await model.load() } }
                            )
                        } label: {
                            Label("Ofrecer una unidad", systemImage: "car.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Palette.volt)
                    }
                } else {
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
                            progressText: "\(summary.securedCount) confirmados · \(summary.missingCount) por conseguir",
                            audience: membership.role
                        )
                    }
                    .buttonStyle(.plain)
                }
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
                if let membership = model.membership,
                   let profileID = UUID(uuidString: model.principal.profileId) {
                    AcquisitionChatListView(
                        membership: membership,
                        profileID: profileID,
                        repository: repository
                    )
                }
            }

            if let membership = model.membership {
                NavigationLink {
                    AcquisitionCounterpartDirectoryView(
                        title: membership.role == .doriAdmin
                            ? "Directorio de proveedores" : "Contactos DORI",
                        contacts: model.counterpartContacts,
                        openChat: { showConversations = true }
                    )
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "person.2.crop.square.stack.fill")
                            .foregroundStyle(Palette.volt)
                        Text(membership.role == .doriAdmin
                             ? "Directorio de proveedores" : "Contactos DORI")
                            .font(.headline)
                        Spacer()
                        Text("\(model.counterpartContacts.count)")
                            .font(.caption.weight(.bold))
                        Image(systemName: "chevron.right")
                    }
                    .padding(16)
                    .panelFlat()
                }
                .buttonStyle(.plain)
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
                            actionTitle: actionTitle(for: offer, role: membership.role),
                            activity: model.activity(for: offer),
                            showsNewActivity: model.hasNewActivity(for: offer)
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
                            actionTitle: administratorActionTitle(for: offer),
                            activity: model.activity(for: offer),
                            showsNewActivity: model.hasNewActivity(for: offer)
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
        return switch offer.status {
        case "negotiating": "Revisar oferta"
        case "accepted_with_condition": "Resolver"
        default: "Ver unidad"
        }
    }

    private func dockBadges(for role: AcquisitionRole) -> [AcquisitionDockDestination: Int] {
        let attention = groupedOffers(.attention, role: role).count
        let vehicleActivity = model.unreadActivityOfferIDs.count
        var badges: [AcquisitionDockDestination: Int] = [:]
        if max(attention, vehicleActivity) > 0 {
            badges[.vehicles] = max(attention, vehicleActivity)
        }
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
        model.uniqueOffers.filter { offer in
            let effectiveGroup: AcquisitionHomeGroup
            if offer.status == "negotiating", let activity = model.activity(for: offer) {
                effectiveGroup = activity.requiresResponse(for: role, offerStatus: offer.status)
                    ? .attention : .inProgress
            } else {
                effectiveGroup = AcquisitionHumanStatus.group(for: offer.status, role: role)
            }
            return effectiveGroup == group
        }.sorted { left, right in
            let leftDate = model.activity(for: left)?.createdAt ?? left.submittedAt ?? .distantPast
            let rightDate = model.activity(for: right)?.createdAt ?? right.submittedAt ?? .distantPast
            return leftDate > rightDate
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

private struct AcquisitionCounterpartDirectoryView: View {
    let title: String
    let contacts: [AcquisitionInstitutionalContact]
    let openChat: () -> Void

    var body: some View {
        ZStack {
            StationBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    AcquisitionSectionHeader(title: title, count: contacts.count)
                    if contacts.isEmpty {
                        Text("Información de contacto pendiente")
                            .font(.subheadline)
                            .foregroundStyle(Palette.textMuted)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(18)
                            .panelFlat()
                    } else {
                        ForEach(contacts) { contact in
                            AcquisitionInstitutionalContactCard(contact: contact, openChat: openChat)
                        }
                    }
                }
                .padding(18)
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
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
                        Label(
                            summary.request.visibleStatus.title,
                            systemImage: summary.request.visibleStatus.systemImage
                        )
                            .font(.caption.weight(.bold))
                            .foregroundStyle(requestStatusColor(summary.request.visibleStatus.tone))
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

    private func requestStatusColor(_ tone: AcquisitionRequestStatusTone) -> Color {
        switch tone {
        case .active, .complete: Palette.volt
        case .waiting: Palette.info
        case .neutral: Palette.textMuted
        case .cancelled: Palette.danger
        }
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
