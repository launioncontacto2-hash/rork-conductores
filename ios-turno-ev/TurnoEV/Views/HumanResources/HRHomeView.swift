import SwiftUI

/// Personal: the people the station already has. Recruiting and hiring belong to the
/// recruitment desk of the station, so nothing here interviews, approves or signs an
/// alta — the supervisor reads coverage and administers who is already on the payroll.
struct HRHomeView: View {
    let office: StationOfficeStore
    let header: SupervisorHeader

    @Environment(CoverageStore.self) private var coverage

    var body: some View {
        NavigationStack {
            ZStack {
                SupervisionBackground()

                ScrollView {
                    VStack(spacing: 14) {
                        header
                        coverageCard
                        shiftCoverageDigest
                        recruitmentCard
                        modules
                        metricsCard
                    }
                    .padding(.horizontal, 18)
                    .padding(.bottom, 34)
                }
                .scrollIndicators(.hidden)
            }
            .toolbarBackground(Palette.canvas, for: .navigationBar)
        }
    }

    private var plan: CapacityPlan { office.capacityPlan }
    private var pipeline: HiringPipeline { office.pipeline }

    // MARK: - Coverage headline

    private var coverageCard: some View {
        NavigationLink {
            HRCapacityView(office: office)
        } label: {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 3) {
                        CapsLabel(text: "Cobertura de personal")
                        Text(plan.deficit == 0 ? "La estación puede operar" : "Faltan \(plan.deficit) conductores")
                            .font(.system(.headline, weight: .black))
                            .foregroundStyle(plan.deficit == 0 ? Palette.volt : Palette.amber)
                    }
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Palette.textMuted)
                }

                HStack(alignment: .center, spacing: 16) {
                    RingGauge(
                        value: Double(plan.availableDrivers),
                        goal: Double(max(1, plan.requiredDrivers)),
                        headline: "\(plan.coveragePct)%",
                        caption: "cobertura"
                    )
                    .scaleEffect(0.78)
                    .frame(width: 140, height: 140)

                    VStack(alignment: .leading, spacing: 9) {
                        DetailRow(label: "Requeridos", value: "\(plan.requiredDrivers)")
                        DetailRow(label: "Contratados", value: "\(plan.hiredDrivers)")
                        DetailRow(
                            label: "Disponibles reales",
                            value: "\(plan.availableDrivers)",
                            tone: plan.availableDrivers >= plan.requiredDrivers ? Palette.volt : Palette.amber
                        )
                        DetailRow(label: "En contratación", value: "\(plan.onboardingDrivers)")
                        DetailRow(
                            label: "Faltantes",
                            value: "\(plan.deficit)",
                            tone: plan.deficit == 0 ? Palette.volt : Palette.danger
                        )
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                Text("\(plan.activeVehicles) unidades activas × \(HRRules.driversPerVehicle) turnos = \(plan.requiredDrivers) conductores requeridos.")
                    .font(.caption2)
                    .foregroundStyle(Palette.textMuted)

                if let worst = plan.worstBlock, worst.deficit > 0 {
                    NoticeBanner(
                        symbol: worst.block.symbol,
                        title: "Déficit \(worst.block.label.lowercased()): \(worst.deficit) conductores",
                        message: "Tener plantilla total no basta: cada bloque se cubre por separado.",
                        tone: worst.level == .critical ? .danger : .amber
                    )
                }
            }
            .padding(16)
            .panel()
        }
        .buttonStyle(.plain)
    }

    // MARK: - Shift coverage, read only

    /// What cobertura de turnos hands to Recursos Humanos. Strictly a reading: nothing on
    /// this card can be edited from here, because a historical record is evidence and not
    /// a working document.
    @ViewBuilder
    private var shiftCoverageDigest: some View {
        let digest = coverage.hrDigest(stationId: office.station.id)
        let total = digest.absences + digest.leaves + digest.emergencies
        if total > 0 || digest.completedGuards > 0 || digest.noShows > 0 {
            VStack(alignment: .leading, spacing: 12) {
                SupSectionHeader(
                    title: "Cobertura de turnos",
                    subtitle: "Lo que el módulo entrega a Recursos Humanos"
                )

                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                    StatTile(label: "Ausencias", value: "\(digest.absences)", tone: .neutral)
                    StatTile(label: "Permisos", value: "\(digest.leaves)", tone: .neutral)
                    StatTile(
                        label: "Emergencias",
                        value: "\(digest.emergencies)",
                        tone: digest.emergencies > 0 ? .amber : .neutral
                    )
                    StatTile(
                        label: "Cancelaciones",
                        value: "\(digest.cancellations)",
                        tone: digest.cancellations > 0 ? .amber : .neutral
                    )
                    StatTile(
                        label: "No presentados",
                        value: "\(digest.noShows)",
                        tone: digest.noShows > 0 ? .danger : .neutral
                    )
                    StatTile(
                        label: "Guardias",
                        value: "\(digest.completedGuards)",
                        hint: "Completadas",
                        tone: digest.completedGuards > 0 ? .volt : .neutral
                    )
                }

                if digest.uncovered > 0 {
                    NoticeBanner(
                        symbol: "exclamationmark.triangle.fill",
                        title: "\(digest.uncovered) turno\(digest.uncovered == 1 ? "" : "s") quedó sin cobertura",
                        message: "Nadie elegíble pudo tomarlo. Recursos Humanos decide qué consecuencia tiene esa falta.",
                        tone: .danger
                    )
                }

                if digest.bonusPayableMxn > 0 {
                    Text("Bonos por guardia devengados: \(Fmt.mxn(digest.bonusPayableMxn)). Solo cuentan los turnos efectivamente completados.")
                        .font(.caption2)
                        .foregroundStyle(Palette.volt)
                }

                Text("Qué ausencias requieren autorización, cuáles piden evidencia y cuáles afectan asistencia o bonos lo define la política de Recursos Humanos. Cubrir un turno nunca autoriza una falta.")
                    .font(.system(size: 10))
                    .foregroundStyle(Palette.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(16)
            .panel()
        }
    }

    // MARK: - Recruitment, read only

    /// What the recruitment desk of this station is doing. The supervisor watches the
    /// pipeline because it decides whether his shifts get covered, but he does not move
    /// a single candidate: he cannot interview, approve, reject or hire.
    private var recruitmentCard: some View {
        let recentHires = RecruitmentHandoff.hires(stationId: office.station.id)
        return VStack(alignment: .leading, spacing: 12) {
            SupSectionHeader(
                title: "Reclutamiento de tu estación",
                subtitle: "Lo lleva la mesa de reclutamiento, de principio a fin"
            )
            PipelineFunnel(pipeline: pipeline)
            HStack(spacing: 10) {
                StatTile(
                    label: "En proceso",
                    value: "\(office.candidatesInProcess.count)",
                    hint: "Candidatos activos",
                    tone: .neutral
                )
                StatTile(
                    label: "Tiempo medio",
                    value: "\(pipeline.averageHiringDays) días",
                    hint: "Lead → alta firmada",
                    tone: .neutral
                )
                StatTile(
                    label: "Altas recibidas",
                    value: "\(recentHires.count)",
                    hint: "Ya en tu plantilla",
                    tone: recentHires.isEmpty ? .neutral : .volt
                )
            }

            if let last = recentHires.first, let hiredAt = last.hiredAt {
                TimeScope(.minute) { now in
                    Text("Última alta: \(last.name) · \(last.block.label) · firmada por \(last.recruiterName) \(Fmt.relative(hiredAt, from: now)).")
                        .font(.caption2)
                        .foregroundStyle(Palette.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Text("Tú no entrevistas ni autorizas altas: cuando reclutamiento firma, el expediente aparece solo en tus expedientes y el conductor ya puede tomar turno.")
                .font(.system(size: 10))
                .foregroundStyle(Palette.textMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .panel()
    }

    // MARK: - Modules

    private var modules: some View {
        VStack(alignment: .leading, spacing: 10) {
            SupSectionHeader(title: "Módulos", subtitle: "La gente que ya trabaja en tu estación")

            ModuleLink(
                title: "Expedientes",
                subtitle: "\(office.activeFiles.count) contratados · \(office.incompleteFiles.count) incompletos",
                symbol: "folder.fill",
                badge: office.incompleteFiles.count
            ) {
                HRFilesView(office: office)
            }

            ModuleLink(
                title: "Capacidad de personal",
                subtitle: "Cobertura por bloque y unidades por incorporar",
                symbol: "chart.bar.doc.horizontal.fill",
                badge: plan.deficit,
                badgeTone: Palette.danger
            ) {
                HRCapacityView(office: office)
            }

            ModuleLink(
                title: "Solicitudes bancarias",
                subtitle: "Alta y cambio de cuenta con CLABE única nacional",
                symbol: "building.columns.fill",
                badge: office.openBankRequests.count
            ) {
                HRBankRequestsView(office: office)
            }

            ModuleLink(
                title: "Auditoría",
                subtitle: "Bitácora inmutable de acciones sensibles",
                symbol: "lock.doc.fill"
            ) {
                AuditTrailView(office: office)
            }
        }
    }

    // MARK: - Metrics

    private var metricsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            SupSectionHeader(title: "Indicadores", subtitle: "Lectura de la semana en curso")

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                StatTile(
                    label: "Vacantes actuales",
                    value: "\(plan.deficit)",
                    hint: "Contra flotilla activa",
                    tone: plan.deficit > 0 ? .amber : .volt
                )
                StatTile(
                    label: "Vacantes proyectadas",
                    value: "\(plan.futureDeficit)",
                    hint: "Con \(plan.incomingVehicles) unidades nuevas",
                    tone: plan.futureDeficit > 0 ? .danger : .volt
                )
                StatTile(
                    label: "Expedientes incompletos",
                    value: "\(office.incompleteFiles.count)",
                    hint: "Falta documentación",
                    tone: office.incompleteFiles.isEmpty ? .volt : .amber
                )
                StatTile(
                    label: "Documentos por vencer",
                    value: "\(office.expiringDocumentFiles.count)",
                    hint: "Próximos \(HRRules.documentWarningDays) días",
                    tone: office.expiringDocumentFiles.isEmpty ? .volt : .amber
                )
                StatTile(
                    label: "Tasa de rechazo",
                    value: "\(Int(pipeline.rejectionRate * 100))%",
                    hint: "Candidatos descartados",
                    tone: .neutral
                )
                StatTile(
                    label: "No disponibles",
                    value: "\(office.unavailableFiles.count)",
                    hint: "Bajas, permisos y documentos",
                    tone: office.unavailableFiles.isEmpty ? .volt : .amber
                )
            }
        }
        .padding(16)
        .panel()
    }
}
