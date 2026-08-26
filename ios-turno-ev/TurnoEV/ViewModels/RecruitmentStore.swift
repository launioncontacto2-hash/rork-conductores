import Foundation
import Observation

/// Recruitment desk of one station. It reads its demand — units × 4 turnos — and turns it
/// into vacancies, leads, appointments and a recommended budget, and it owns the whole
/// cycle up to the signed alta. It never touches payroll, credits, settlements or bank
/// data: once the contract is signed the employee file lives at the station.
@Observable
final class RecruitmentStore {
    // MARK: - Persisted shape

    nonisolated private struct PersistedState: Codable, Sendable {
        var seedKey: String
        var prospects: [Prospect]
        var campaigns: [RecruitCampaign]
        var appointments: [Appointment]
        var marginPct: Int
    }

    // MARK: - Identity

    let account: StaffAccount
    private let fleet: FleetStore

    var now: Date { fleet.now }
    var stations: [Station] { StaffDirectory.coverage(for: account) }

    // MARK: - State

    var prospects: [Prospect] = []
    var campaigns: [RecruitCampaign] = []
    var appointments: [Appointment] = []
    /// Demand read from every station covered. Derived, never typed.
    var demands: [StationDemand] = []
    /// Safety margin applied over the statistical lead need.
    var marginPct: Int = RecruitRules.defaultMarginPct
    /// Alerts the recruiter already read today.
    var reviewedAlertIds: Set<String> = []
    private var seedKey: String = ""

    private var storageKey: String { "turnoev.recruit.v1.\(account.id)" }

    init(account: StaffAccount, fleet: FleetStore) {
        self.account = account
        self.fleet = fleet
        load()
    }

    // MARK: - Lifecycle

    func refresh() {
        if seedKey != currentSeedKey {
            rebuild()
        } else {
            rebuildDemand()
        }
    }

    func regenerate() {
        reviewedAlertIds.removeAll()
        rebuild()
    }

    private var currentSeedKey: String {
        let week = ShiftRules.calendar.ordinality(of: .weekOfYear, in: .era, for: now) ?? 0
        return "\(account.id)|\(week)"
    }

    private func rebuild() {
        let snapshot = RecruitmentMockData.snapshot(
            stations: stations,
            recruiterName: account.name,
            now: now
        )
        prospects = snapshot.prospects
        campaigns = snapshot.campaigns
        appointments = snapshot.appointments
        seedKey = currentSeedKey
        republishHires()
        rebuildDemandBases()
        rebuildDemand()
        persist()
    }

    /// Fleet side of the demand, read once per station from the same source the station
    /// office uses. It only changes when the operating week changes, so it is cached: the
    /// funnel moves many times a day, the flotilla does not.
    private struct DemandBase: Sendable {
        let activeVehicles: Int
        let availableTotal: Int
        let availableByBlock: [ShiftBlock: Int]
        let hiredByBlock: [ShiftBlock: Int]
        let incorporations: [VehicleIncorporation]
    }

    private var demandBases: [String: DemandBase] = [:]

    private func rebuildDemandBases() {
        var result: [String: DemandBase] = [:]
        for station in stations {
            let supervisor = StaffDirectory.accounts.first {
                $0.role == .supervisor && $0.stationId == station.id
            }
            let snapshot = StationOfficeMockData.snapshot(
                station: station,
                supervisorName: supervisor?.name ?? "Supervisión",
                supervisorId: supervisor?.id ?? "acc-sup",
                liveDriver: fleet.driver.stationId == station.id ? fleet.driver : nil,
                now: now
            )
            let activeFiles = snapshot.files.filter { $0.status != .terminated }
            let available = activeFiles.filter { $0.isOperationallyAvailable(now: now) }
            result[station.id] = DemandBase(
                activeVehicles: snapshot.activeVehicles,
                availableTotal: available.count,
                availableByBlock: Dictionary(grouping: available, by: \.block).mapValues(\.count),
                hiredByBlock: Dictionary(grouping: activeFiles, by: \.block).mapValues(\.count),
                incorporations: snapshot.incorporations
            )
        }
        demandBases = result
    }

    /// Rebuilds the vacancy board from the same source the station office reads, so a
    /// recruiter and a supervisor can never see different numbers.
    private func rebuildDemand() {
        if demandBases.count != stations.count { rebuildDemandBases() }

        let openByStationBlock = Dictionary(
            grouping: prospects.filter { $0.stage.isOpen },
            by: { "\($0.stationId)|\($0.requestedBlock.rawValue)" }
        ).mapValues(\.count)

        demands = stations.compactMap { station in
            guard let base = demandBases[station.id] else { return nil }
            let blocks = ShiftBlock.allCases.map { block in
                BlockCoverage(
                    block: block,
                    required: base.activeVehicles,
                    available: base.availableByBlock[block] ?? 0,
                    hired: base.hiredByBlock[block] ?? 0,
                    onboarding: openByStationBlock["\(station.id)|\(block.rawValue)"] ?? 0
                )
            }
            return StationDemand(
                station: station,
                activeVehicles: base.activeVehicles,
                availableDrivers: base.availableTotal,
                inProcess: prospects.filter { $0.stationId == station.id && $0.stage.isOpen }.count,
                blocks: blocks,
                incorporations: base.incorporations
            )
        }
    }

    // MARK: - Reads: demand

    var totalRequired: Int { demands.reduce(0) { $0 + $1.requiredDrivers } }
    var totalAvailable: Int { demands.reduce(0) { $0 + $1.availableDrivers } }
    var totalVacancies: Int { demands.reduce(0) { $0 + $1.vacancies } }
    var totalIncomingVehicles: Int { demands.reduce(0) { $0 + $1.incomingVehicles } }
    var projectedVacancies: Int { demands.reduce(0) { $0 + $1.projectedVacancies } }
    var totalActiveVehicles: Int { demands.reduce(0) { $0 + $1.activeVehicles } }

    var coverageRatio: Double {
        totalRequired > 0 ? Double(totalAvailable) / Double(totalRequired) : 1
    }

    var coveragePct: Int { Int((coverageRatio * 100).rounded()) }

    func demand(stationId: String?) -> StationDemand? {
        guard let stationId else { return nil }
        return demands.first { $0.station.id == stationId }
    }

    /// Every pending incorporation of the covered stations, closest first.
    var upcomingIncorporations: [VehicleIncorporation] {
        demands
            .flatMap { $0.incorporations }
            .filter { $0.stage.isIncoming }
            .sorted { $0.operationStartAt < $1.operationStartAt }
    }

    /// Coverage per block across every station: the four questions of the week.
    var networkBlocks: [BlockCoverage] {
        ShiftBlock.allCases.map { block in
            let rows = demands.compactMap { demand in demand.blocks.first { $0.block == block } }
            return BlockCoverage(
                block: block,
                required: rows.reduce(0) { $0 + $1.required },
                available: rows.reduce(0) { $0 + $1.available },
                hired: rows.reduce(0) { $0 + $1.hired },
                onboarding: rows.reduce(0) { $0 + $1.onboarding }
            )
        }
    }

    // MARK: - Reads: prospects

    func prospects(stage: RecruitStage?, stationId: String? = nil, search: String = "") -> [Prospect] {
        let cleaned = search.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return prospects
            .filter { stage == nil || $0.stage == stage }
            .filter { stationId == nil || $0.stationId == stationId }
            .filter { prospect in
                guard !cleaned.isEmpty else { return true }
                return prospect.name.lowercased().contains(cleaned)
                    || prospect.phone.contains(cleaned)
                    || prospect.email.lowercased().contains(cleaned)
            }
            .sorted { $0.createdAt > $1.createdAt }
    }

    func prospect(id: String?) -> Prospect? {
        guard let id else { return nil }
        return prospects.first { $0.id == id }
    }

    func count(stage: RecruitStage) -> Int {
        prospects.filter { $0.stage == stage }.count
    }

    var newLeads: [Prospect] {
        prospects.filter { $0.stage == .lead }.sorted { $0.createdAt > $1.createdAt }
    }

    // MARK: - Reads that answer differently depending on the hour
    //
    // These used to read `self.now`, so a tab badge and the list behind it shared one
    // invisible dependency on the global clock. They now take the instant explicitly, which
    // forces every consumer to state the cadence it actually needs.

    /// `.minute`: a lead goes past its contact window a fixed number of minutes after it
    /// arrived, and it arrived at an arbitrary hour.
    func overdueLeads(now: Date) -> [Prospect] {
        newLeads.filter { $0.isOverdueContact(now: now) }
    }

    var inProcess: [Prospect] {
        prospects.filter { $0.stage.isOpen && $0.stage != .lead }
    }

    var awaitingScreening: [Prospect] {
        prospects.filter { $0.stage == .contacted }
    }

    var awaitingInterview: [Prospect] {
        prospects.filter { $0.stage == .prequalified }
    }

    /// `.day`: what is missing from a file is decided by document expiry.
    func awaitingDocuments(now: Date) -> [Prospect] {
        prospects.filter { $0.stage == .documents && !$0.missingDocuments(now: now).isEmpty }
    }

    /// Documented, evaluated and waiting only for the recruiter to sign the alta.
    ///
    /// `.day`. This is the set that governs whether an alta can be signed, so a consumer
    /// that shows a signing button must invalidate on the same boundary.
    func readyToHire(now: Date) -> [Prospect] {
        prospects.filter { $0.isReadyToHire(now: now) }
    }

    /// Evaluated but still missing part of the initial file. `.day`.
    func awaitingFile(now: Date) -> [Prospect] {
        prospects.filter { $0.stage.isOpen && $0.hiredAt == nil && $0.passedEvaluation() && !$0.missingDocuments(now: now).isEmpty }
    }

    var hired: [Prospect] {
        prospects.filter { $0.stage == .hired }
    }

    /// A person already in the base, matched by phone, email or CURP.
    func duplicate(phone: String, email: String, curp: String, excluding id: String? = nil) -> Prospect? {
        RecruitRules.duplicateMatch(
            phone: phone,
            email: email,
            curp: curp,
            in: prospects.filter { $0.id != id }
        )
    }

    // MARK: - Reads: funnel and metrics

    /// `.day`: the only temporal term is `isReadyToHire`, decided by document expiry.
    func funnel(now: Date) -> RecruitFunnel {
        var counts: [RecruitStage: Int] = [:]
        counts[.lead] = prospects.count
        counts[.contacted] = prospects.filter { $0.contactedAt != nil }.count
        counts[.prequalified] = prospects.filter { $0.screening != nil }.count
        counts[.interviewed] = prospects.filter { $0.interview?.interviewedAt != nil }.count
        counts[.documents] = prospects.filter { !$0.documents.isEmpty }.count
        counts[.readyToHire] = prospects.filter { $0.isReadyToHire(now: now) || $0.hiredAt != nil }.count
        counts[.approved] = prospects.filter { $0.hiringVerdict == .approved }.count
        counts[.hired] = prospects.filter { $0.hiredAt != nil }.count
        return RecruitFunnel(
            counts: counts,
            lost: prospects.filter { $0.stage == .lost }.count,
            averageHiringDays: averageHiringDays
        )
    }

    /// Days from lead registration to signed contract, read from the hires themselves.
    var averageHiringDays: Int {
        let durations = prospects.compactMap { prospect -> Int? in
            guard let hiredAt = prospect.hiredAt else { return nil }
            return max(1, Int(hiredAt.timeIntervalSince(prospect.createdAt) / 86_400))
        }
        guard !durations.isEmpty else { return RecruitRules.defaultHiringDays }
        return Int((Double(durations.reduce(0, +)) / Double(durations.count)).rounded())
    }

    /// Historical lead → hire conversion. Never assume a lead equals a driver.
    func conversion(now: Date) -> Double { funnel(now: now).leadToHire }

    var lossReasons: [(reason: LossReason, count: Int)] {
        let lost = prospects.compactMap(\.lossReason)
        return LossReason.allCases
            .map { reason in (reason, lost.filter { $0 == reason }.count) }
            .filter { $0.1 > 0 }
            .sorted { $0.1 > $1.1 }
    }

    /// `.day`, inherited from `readyToHire` — the only temporal term in the whole record.
    func recruiterMetrics(now: Date) -> RecruiterMetrics {
        let contacted = prospects.filter { $0.contactedAt != nil }
        let contactMinutes = contacted.compactMap(\.firstContactMinutes)
        let average = contactMinutes.isEmpty
            ? 0
            : Int((Double(contactMinutes.reduce(0, +)) / Double(contactMinutes.count)).rounded())
        return RecruiterMetrics(
            assignedLeads: prospects.count,
            contacted: contacted.count,
            averageFirstContactMinutes: average,
            interviewsDone: prospects.filter { $0.interview?.interviewedAt != nil }.count,
            interviewsScheduled: appointments.filter { $0.status.isOpen }.count,
            attendedAppointments: appointments.filter { $0.status == .attended }.count,
            noShowAppointments: appointments.filter { $0.status == .noShow }.count,
            readyToHire: readyToHire(now: now).count,
            approved: prospects.filter { $0.hiringVerdict == .approved }.count,
            hires: prospects.filter { $0.hiredAt != nil }.count,
            averageHiringDays: averageHiringDays
        )
    }

    // MARK: - Reads: sources and campaigns

    var sourcePerformance: [SourcePerformance] {
        LeadSource.allCases.compactMap { source in
            let rows = prospects.filter { $0.source == source }
            guard !rows.isEmpty else { return nil }
            let spent = campaigns.filter { $0.platform == source }.reduce(0) { $0 + $1.spentMxn }
            return SourcePerformance(
                source: source,
                leads: rows.count,
                interviews: rows.filter { $0.interview?.interviewedAt != nil }.count,
                hires: rows.filter { $0.hiredAt != nil }.count,
                spentMxn: spent
            )
        }
        .sorted { $0.hires > $1.hires }
    }

    var campaignPerformance: [CampaignPerformance] {
        campaigns.map { campaign in
            let rows = prospects.filter { $0.campaignId == campaign.id }
            return CampaignPerformance(
                campaign: campaign,
                leads: rows.count,
                interviews: rows.filter { $0.interview?.interviewedAt != nil }.count,
                hires: rows.filter { $0.hiredAt != nil }.count
            )
        }
        .sorted { lhs, rhs in
            lhs.campaign.isActive == rhs.campaign.isActive
                ? lhs.hires > rhs.hires
                : (lhs.campaign.isActive && !rhs.campaign.isActive)
        }
    }

    /// Average cost of a lead across paid media. Base of the budget recommendation.
    var costPerLead: Double {
        let paidCampaigns = campaigns.filter { $0.platform.isPaid }
        let spent = paidCampaigns.reduce(0) { $0 + $1.spentMxn }
        let leads = prospects.filter { prospect in
            guard let campaignId = prospect.campaignId else { return false }
            return paidCampaigns.contains { $0.id == campaignId }
        }.count
        guard leads > 0 else { return 0 }
        return Double(spent) / Double(leads)
    }

    var costPerHire: Double {
        let spent = campaigns.reduce(0) { $0 + $1.spentMxn }
        let hires = prospects.filter { $0.hiredAt != nil && $0.campaignId != nil }.count
        guard hires > 0 else { return 0 }
        return Double(spent) / Double(hires)
    }

    // MARK: - Reads: planning

    /// Leads needed to sign the drivers the network is missing today and tomorrow.
    ///
    /// `.day`, inherited from `conversion` → `funnel` → `isReadyToHire`.
    func leadsNeeded(for hires: Int, now: Date) -> Int {
        RecruitRules.leadsNeeded(hires: hires, conversion: conversion(now: now), marginPct: marginPct)
    }

    func recommendedBudget(for hires: Int, now: Date) -> Int {
        RecruitRules.budget(leads: leadsNeeded(for: hires, now: now), costPerLead: costPerLead)
    }

    /// Hires the current pipeline can realistically deliver in a window. `.day`.
    func projectedHires(days: Int, now: Date) -> Int {
        RecruitRules.projectedHires(
            inProcess: prospects.filter { $0.stage.isOpen }.count,
            conversion: conversion(now: now),
            daysAvailable: days,
            averageHiringDays: averageHiringDays
        )
    }

    // MARK: - Reads: agenda

    /// `.day`: an appointment belongs to today for the whole of today.
    func todayAppointments(now: Date) -> [Appointment] {
        appointments
            .filter { $0.isToday(now: now) && $0.status.isOpen }
            .sorted { $0.date < $1.date }
    }

    /// Still to happen. The comparison is `date >= now`, so **this function is `.minute`**:
    /// an interview leaves this list at its own hour, not at midnight.
    ///
    /// A `.day` reading is only correct for a consumer that normalises the boundary itself,
    /// by pairing this with `!isToday(now:)`. Then the finest thing that can change the
    /// result really is the date — but the `.day` belongs to that consumer, never to this
    /// function. Read raw at `.day` it is simply wrong: the count keeps an interview that
    /// already happened until the following midnight, while `pastAppointments` has already
    /// claimed it, and the two boards contradict each other for the rest of the day.
    ///
    /// Two of the three call sites were doing exactly that and were corrected. Do not assume
    /// the pairing — check it at the call site.
    func upcomingAppointments(now: Date) -> [Appointment] {
        appointments
            .filter { $0.status.isOpen && $0.date >= now }
            .sorted { $0.date < $1.date }
    }

    /// `.minute`: an appointment becomes history at its own hour, not at midnight.
    func pastAppointments(now: Date) -> [Appointment] {
        appointments
            .filter { !$0.status.isOpen || $0.date < now }
            .sorted { $0.date > $1.date }
    }

    func appointments(prospectId: String) -> [Appointment] {
        appointments.filter { $0.prospectId == prospectId }.sorted { $0.date > $1.date }
    }

    // MARK: - Alerts

    /// Threshold-driven, never hand written. Everything that needs the recruiter today.
    ///
    /// Mixed cadence, and the finer one governs: incorporations and stalled files turn on a
    /// date, but `overdueLeads` turns on a minute. A consumer of this board — including the
    /// counter in the header — has to listen by the minute.
    func alerts(now: Date) -> [RecruitAlert] {
        var result: [RecruitAlert] = []

        for demand in demands {
            guard let incorporation = demand.nextIncorporation(now: now) else { continue }
            let days = max(0, incorporation.daysToOperation(now: now))
            let needed = demand.vacancies + incorporation.requiredDrivers
            guard needed > 0 else { continue }
            let projected = projectedHires(days: days, now: now)
            let gap = max(0, needed - projected)
            let level = RecruitRules.coverageRisk(
                daysAvailable: days,
                averageHiringDays: averageHiringDays,
                deficit: gap
            )
            result.append(
                RecruitAlert(
                    id: "cover-\(demand.station.id)",
                    kind: gap > 0 ? .coverageRisk : .incomingUnits,
                    level: gap > 0 ? level : .informative,
                    title: "\(incorporation.units) unidades entran en \(days) días · \(demand.station.name)",
                    detail: gap > 0
                        ? "Se requieren \(needed) conductores. Proyección actual: \(projected). Déficit proyectado: \(gap). Contratar toma \(averageHiringDays) días en promedio."
                        : "Se requieren \(needed) conductores y la proyección actual los cubre con \(projected).",
                    actionLabel: "Ver vacantes",
                    destination: .vacancies,
                    stationId: demand.station.id
                )
            )
        }

        let overdue = overdueLeads(now: now).count
        if overdue > 0 {
            result.append(
                RecruitAlert(
                    id: "uncontacted",
                    kind: .uncontactedLeads,
                    level: overdue >= 12 ? .critical : (overdue >= 5 ? .important : .preventive),
                    title: "\(overdue) leads sin contactar",
                    detail: "Llevan más de \(RecruitRules.contactSlaMinutes / 60) horas esperando respuesta. Un lead frío rara vez vuelve a contestar.",
                    actionLabel: "Abrir leads",
                    destination: .leads,
                    stationId: nil
                )
            )
        }

        let today = todayAppointments(now: now).count
        if today > 0 {
            result.append(
                RecruitAlert(
                    id: "agenda",
                    kind: .appointmentsToday,
                    level: .informative,
                    title: "\(today) citas hoy",
                    detail: "Confirma asistencia antes de la hora acordada para no perder el espacio.",
                    actionLabel: "Ver agenda",
                    destination: .appointments,
                    stationId: nil
                )
            )
        }

        let stalled = awaitingDocuments(now: now).filter { $0.daysInProcess(now: now) > RecruitRules.documentStallDays }
        if !stalled.isEmpty {
            result.append(
                RecruitAlert(
                    id: "documents",
                    kind: .documentsStalled,
                    level: stalled.count >= 4 ? .important : .preventive,
                    title: "\(stalled.count) expedientes detenidos",
                    detail: "Más de \(RecruitRules.documentStallDays) días sin completar la documentación inicial.",
                    actionLabel: "Revisar candidatos",
                    destination: .prospects,
                    stationId: nil
                )
            )
        }

        let unsigned = readyToHire(now: now)
        if !unsigned.isEmpty {
            result.append(
                RecruitAlert(
                    id: "altas",
                    kind: .hiresPending,
                    level: unsigned.count >= 3 ? .important : .preventive,
                    title: "\(unsigned.count) altas listas para firmar",
                    detail: "Expediente completo y entrevista aprobada. Cada día sin firmar es un turno que la estación no cubre.",
                    actionLabel: "Contratar",
                    destination: .prospects,
                    stationId: nil
                )
            )
        }

        let needed = totalVacancies + projectedVacancies - totalVacancies
        let leadTarget = leadsNeeded(for: totalVacancies + needed, now: now)
        let available = prospects.filter { $0.stage.isOpen }.count
        if leadTarget > available {
            result.append(
                RecruitAlert(
                    id: "leads",
                    kind: .leadDeficit,
                    level: leadTarget > available * 2 ? .important : .preventive,
                    title: "Faltan \(leadTarget - available) leads en proceso",
                    detail: "Con una conversión de \(Int((conversion(now: now) * 100).rounded())) % se necesitan \(leadTarget) candidatos para firmar \(totalVacancies + needed) contrataciones.",
                    actionLabel: "Ver campañas",
                    destination: .campaigns,
                    stationId: nil
                )
            )
        }

        return result
            .filter { !reviewedAlertIds.contains($0.id) }
            .sorted { $0.level.weight > $1.level.weight }
    }

    func criticalAlerts(now: Date) -> [RecruitAlert] {
        alerts(now: now).filter { $0.level.demandsAction }
    }

    func reviewAlert(id: String) {
        reviewedAlertIds.insert(id)
    }

    func restoreAlerts() {
        reviewedAlertIds.removeAll()
    }

    // MARK: - Writes: leads

    /// Registers a lead by hand. Duplicates are never created silently.
    @discardableResult
    func createProspect(
        name: String,
        phone: String,
        email: String,
        curp: String,
        city: String,
        age: Int,
        stationId: String,
        block: ShiftBlock,
        experienceYears: Int,
        platforms: [String],
        hasLicense: Bool,
        source: LeadSource,
        campaignId: String?,
        notes: String
    ) -> Prospect? {
        guard duplicate(phone: phone, email: email, curp: curp) == nil else { return nil }
        let prospect = makeProspect(
            id: "prs-man-\(Int(now.timeIntervalSince1970))",
            name: name,
            phone: phone,
            email: email,
            curp: curp,
            city: city,
            age: age,
            stationId: stationId,
            block: block,
            experienceYears: experienceYears,
            platforms: platforms,
            hasLicense: hasLicense,
            source: source,
            campaignId: campaignId,
            notes: notes,
            origin: "Alta manual por \(account.name)"
        )
        prospects.append(prospect)
        rebuildDemand()
        persist()
        return prospect
    }

    /// Simulates the Meta Lead Ads webhook: a form is submitted and a lead is born.
    /// When the integration lands only the transport changes — this is the same entry point.
    @discardableResult
    func ingest(_ payload: LeadAdPayload) -> Prospect? {
        guard let station = stations.first(where: { $0.code == payload.stationCode }) ?? stations.first else {
            return nil
        }
        guard duplicate(phone: payload.phone, email: payload.email, curp: "") == nil else { return nil }
        let prospect = makeProspect(
            id: "prs-meta-\(payload.leadgenId)",
            name: payload.fullName,
            phone: payload.phone,
            email: payload.email,
            curp: "",
            city: payload.city,
            age: payload.age,
            stationId: station.id,
            block: payload.requestedBlock,
            experienceYears: payload.experienceYears,
            platforms: payload.platforms,
            hasLicense: payload.hasLicense,
            source: payload.platform,
            campaignId: payload.campaignId,
            notes: "",
            origin: "Formulario \(payload.platform.label) · \(payload.formId)"
        )
        prospects.append(prospect)
        rebuildDemand()
        persist()
        return prospect
    }

    private func makeProspect(
        id: String,
        name: String,
        phone: String,
        email: String,
        curp: String,
        city: String,
        age: Int,
        stationId: String,
        block: ShiftBlock,
        experienceYears: Int,
        platforms: [String],
        hasLicense: Bool,
        source: LeadSource,
        campaignId: String?,
        notes: String,
        origin: String
    ) -> Prospect {
        Prospect(
            id: id,
            name: name,
            phone: phone,
            email: email,
            city: city,
            age: age,
            curp: curp,
            stationId: stationId,
            requestedBlock: block,
            experienceYears: experienceYears,
            platforms: platforms,
            hasLicense: hasLicense,
            source: source,
            campaignId: campaignId,
            createdAt: now,
            stage: .lead,
            contactedAt: nil,
            screening: nil,
            interview: nil,
            documents: [],
            authorizedAt: nil,
            hiringVerdict: nil,
            hiringNote: nil,
            verdictAt: nil,
            hiredAt: nil,
            lossReason: nil,
            lossNote: nil,
            ownerName: account.name,
            notes: notes,
            history: [
                ProspectEvent(
                    id: "\(id)-e0",
                    kind: .created,
                    date: now,
                    detail: origin,
                    author: account.name
                ),
            ]
        )
    }

    // MARK: - Writes: process

    func markContacted(_ prospectId: String, note: String = "") {
        update(prospectId) { prospect in
            if prospect.contactedAt == nil { prospect.contactedAt = self.now }
            if prospect.stage == .lead { prospect.stage = .contacted }
            self.log(
                &prospect,
                kind: .contact,
                detail: note.isEmpty ? "Contacto registrado con el candidato." : note
            )
        }
    }

    func saveScreening(_ prospectId: String, screening: Screening) {
        update(prospectId) { prospect in
            var updated = screening
            updated.reviewedAt = self.now
            updated.reviewer = self.account.name
            prospect.screening = updated
            if prospect.contactedAt == nil { prospect.contactedAt = self.now }
            switch updated.outcome {
            case .fit:
                if prospect.stage.order < RecruitStage.prequalified.order { prospect.stage = .prequalified }
            case .review:
                if prospect.stage == .lead { prospect.stage = .contacted }
            case .unfit:
                prospect.stage = .lost
                prospect.lossReason = .rejectedByRecruiter
                prospect.lossNote = updated.notes
            }
            self.log(
                &prospect,
                kind: .screening,
                detail: "Precalificación: \(updated.outcome.label) · \(updated.passed)/\(ScreeningCheck.allCases.count) criterios."
            )
        }
    }

    func saveInterview(_ prospectId: String, sheet: InterviewSheet) {
        update(prospectId) { prospect in
            var updated = sheet
            updated.interviewedAt = self.now
            updated.interviewerName = self.account.name
            prospect.interview = updated
            if updated.decision == .notRecommended {
                prospect.stage = .lost
                prospect.lossReason = .rejectedByRecruiter
                prospect.lossNote = updated.notes
            } else if prospect.stage.order < RecruitStage.interviewed.order {
                prospect.stage = .interviewed
            }
            self.log(
                &prospect,
                kind: .interview,
                detail: "Primera entrevista: \(updated.scorePct) / 100 · \((updated.decision ?? updated.suggestion).label)."
            )
        }
    }

    func toggleDocument(_ prospectId: String, kind: DocumentKind) {
        update(prospectId) { prospect in
            if let index = prospect.documents.firstIndex(where: { $0.kind == kind }) {
                let isDelivered = prospect.documents[index].status == .delivered
                prospect.documents[index].status = isDelivered ? .pending : .delivered
                prospect.documents[index].uploadedAt = isDelivered ? nil : self.now
                prospect.documents[index].uploadedBy = isDelivered ? nil : self.account.name
            } else {
                prospect.documents.append(
                    StaffDocument(
                        kind: kind,
                        status: .delivered,
                        uploadedAt: self.now,
                        uploadedBy: self.account.name
                    )
                )
            }
            if prospect.stage == .interviewed || prospect.stage == .prequalified {
                prospect.stage = .documents
            }
            // The file completes itself: when nothing is missing the candidate is ready
            // for the alta, without anybody having to move him by hand.
            if prospect.stage == .documents,
               prospect.passedEvaluation(),
               prospect.missingDocuments(now: self.now).isEmpty {
                prospect.stage = .readyToHire
            } else if prospect.stage == .readyToHire, !prospect.missingDocuments(now: self.now).isEmpty {
                prospect.stage = .documents
            }
            self.log(
                &prospect,
                kind: .document,
                detail: "\(kind.label): expediente inicial al \(prospect.documentPct(now: self.now)) %."
            )
        }
    }

    /// Suggested employee number for the next alta of a station, following its code.
    func suggestedEmployeeNumber(for prospect: Prospect) -> String {
        let code = stations.first { $0.id == prospect.stationId }?.code ?? "TEV"
        let signed = prospects.filter { $0.stationId == prospect.stationId && $0.hiredAt != nil }.count
        return "\(code)-\(String(format: "%03d", signed + 1))"
    }

    /// Signs the alta. Recruitment carries the process end to end: nobody else approves,
    /// interviews again or vetoes. The station only receives the finished employee file.
    @discardableResult
    func hire(_ prospectId: String, employeeNumber: String, notes: String) -> Bool {
        guard let candidate = prospect(id: prospectId), candidate.isReadyToHire(now: now) else { return false }
        let number = employeeNumber.trimmingCharacters(in: .whitespaces).uppercased()
        guard !number.isEmpty else { return false }

        update(prospectId) { prospect in
            prospect.authorizedAt = self.now
            prospect.hiringVerdict = .approved
            prospect.hiringNote = notes.isEmpty ? "Alta firmada por reclutamiento." : notes
            prospect.verdictAt = self.now
            prospect.hiredAt = self.now
            prospect.stage = .hired
            self.log(
                &prospect,
                kind: .verdict,
                detail: "Alta firmada por reclutamiento · número \(number) · bloque \(prospect.requestedBlock.label)."
            )
            RecruitmentHandoff.submit(
                self.packet(for: prospect, employeeNumber: number, comments: notes)
            )
        }
        return true
    }

    /// Rejects a candidate at the hiring decision itself, after a complete file.
    func rejectAtHire(_ prospectId: String, note: String) {
        update(prospectId) { prospect in
            prospect.hiringVerdict = .rejected
            prospect.hiringNote = note
            prospect.verdictAt = self.now
            prospect.stage = .lost
            prospect.lossReason = .rejectedAtHire
            prospect.lossNote = note
            self.log(&prospect, kind: .verdict, detail: "Alta rechazada por reclutamiento. \(note)")
            RecruitmentHandoff.remove(prospectId: prospect.id)
        }
    }

    func markLost(_ prospectId: String, reason: LossReason, note: String) {
        update(prospectId) { prospect in
            prospect.stage = .lost
            prospect.lossReason = reason
            prospect.lossNote = note
            self.log(
                &prospect,
                kind: .lost,
                detail: "Motivo de pérdida: \(reason.label).\(note.isEmpty ? "" : " \(note)")"
            )
            RecruitmentHandoff.remove(prospectId: prospect.id)
        }
    }

    /// A candidate can come back. The history of the previous attempt is kept intact.
    func reopen(_ prospectId: String) {
        update(prospectId) { prospect in
            prospect.lossReason = nil
            prospect.lossNote = nil
            prospect.stage = prospect.interview?.interviewedAt != nil
                ? .interviewed
                : (prospect.screening != nil ? .prequalified : .contacted)
            self.log(&prospect, kind: .reentry, detail: "Reingreso al proceso de reclutamiento.")
        }
    }

    func saveNotes(_ prospectId: String, notes: String) {
        update(prospectId) { prospect in
            prospect.notes = notes
        }
    }

    // MARK: - Writes: appointments

    @discardableResult
    func scheduleAppointment(
        prospectId: String,
        date: Date,
        kind: AppointmentKind,
        owner: String,
        note: String
    ) -> Appointment? {
        guard let prospect = prospect(id: prospectId) else { return nil }
        let appointment = Appointment(
            id: "apt-\(prospectId)-\(Int(date.timeIntervalSince1970))",
            prospectId: prospectId,
            prospectName: prospect.name,
            stationId: prospect.stationId,
            date: date,
            kind: kind,
            owner: owner,
            status: .scheduled,
            note: note,
            remindedAt: nil
        )
        appointments.append(appointment)
        update(prospectId) { prospect in
            self.log(
                &prospect,
                kind: .appointment,
                detail: "\(kind.label) programada para \(Fmt.dateShort(date)) \(Fmt.clock(date))."
            )
        }
        return appointment
    }

    func updateAppointment(_ appointmentId: String, status: AppointmentStatus) {
        guard let index = appointments.firstIndex(where: { $0.id == appointmentId }) else { return }
        appointments[index].status = status
        let appointment = appointments[index]
        update(appointment.prospectId) { prospect in
            self.log(
                &prospect,
                kind: .appointment,
                detail: "\(appointment.kind.label): \(status.label)."
            )
            if status == .noShow, prospect.stage.isOwnedByRecruitment {
                prospect.stage = .lost
                prospect.lossReason = .noShow
                prospect.lossNote = "No asistió a la cita programada."
            }
        }
        persist()
    }

    func rescheduleAppointment(_ appointmentId: String, to date: Date) {
        guard let index = appointments.firstIndex(where: { $0.id == appointmentId }) else { return }
        appointments[index].date = date
        appointments[index].status = .rescheduled
        let appointment = appointments[index]
        update(appointment.prospectId) { prospect in
            self.log(
                &prospect,
                kind: .appointment,
                detail: "Cita reprogramada para \(Fmt.dateShort(date)) \(Fmt.clock(date))."
            )
        }
    }

    func markReminded(_ appointmentId: String) {
        guard let index = appointments.firstIndex(where: { $0.id == appointmentId }) else { return }
        appointments[index].remindedAt = now
        persist()
    }

    // MARK: - Writes: settings

    func setMargin(_ value: Int) {
        marginPct = max(0, min(60, value))
        persist()
    }

    // MARK: - Handoff bridge

    private func packet(for prospect: Prospect, employeeNumber: String, comments: String) -> HirePacket {
        HirePacket(
            id: "ref-\(prospect.id)",
            prospectId: prospect.id,
            stationId: prospect.stationId,
            name: prospect.name,
            initials: prospect.initials,
            phone: prospect.phone,
            block: prospect.requestedBlock,
            experienceYears: prospect.experienceYears,
            platforms: prospect.platforms,
            availabilityNote: prospect.screening?.notes ?? "",
            screeningOutcome: prospect.screening?.outcome ?? .review,
            interviewScorePct: prospect.interview?.scorePct ?? 0,
            interviewSuggestion: prospect.interview?.decision ?? prospect.interview?.suggestion ?? .secondReview,
            documentPct: prospect.documentPct(now: now),
            recruiterName: account.name,
            comments: comments,
            sentAt: now,
            verdict: .approved,
            verdictNote: comments.isEmpty ? "Alta firmada por reclutamiento." : comments,
            verdictAt: now,
            verdictBy: account.name,
            hiredAt: now,
            employeeNumber: employeeNumber,
            curp: prospect.curp,
            email: prospect.email,
            documents: prospect.documents,
            ingestedAt: nil
        )
    }

    /// Republishes signed altas after a rebuild, so a station that has not opened its
    /// office yet still receives the employee files it is owed.
    private func republishHires() {
        let existing = Set(RecruitmentHandoff.all().map(\.prospectId))
        for prospect in prospects where prospect.hiredAt != nil && !existing.contains(prospect.id) {
            RecruitmentHandoff.submit(
                packet(
                    for: prospect,
                    employeeNumber: suggestedEmployeeNumber(for: prospect),
                    comments: prospect.hiringNote ?? ""
                )
            )
        }
    }

    // MARK: - Internals

    private func update(_ prospectId: String, _ transform: (inout Prospect) -> Void) {
        guard let index = prospects.firstIndex(where: { $0.id == prospectId }) else { return }
        transform(&prospects[index])
        rebuildDemand()
        persist()
    }

    private func log(_ prospect: inout Prospect, kind: ProspectEventKind, detail: String, author: String? = nil) {
        prospect.history.insert(
            ProspectEvent(
                id: "\(prospect.id)-\(kind.rawValue)-\(Int(now.timeIntervalSince1970))-\(prospect.history.count)",
                kind: kind,
                date: now,
                detail: detail,
                author: author ?? account.name
            ),
            at: 0
        )
    }

    // MARK: - Persistence

    private func persist() {
        let state = PersistedState(
            seedKey: seedKey,
            prospects: prospects,
            campaigns: campaigns,
            appointments: appointments,
            marginPct: marginPct
        )
        guard let data = try? JSONEncoder().encode(state) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }

    private func load() {
        guard
            let data = UserDefaults.standard.data(forKey: storageKey),
            let state = try? JSONDecoder().decode(PersistedState.self, from: data)
        else {
            rebuild()
            return
        }
        seedKey = state.seedKey
        prospects = state.prospects
        campaigns = state.campaigns
        appointments = state.appointments
        marginPct = state.marginPct
        rebuildDemandBases()
        rebuildDemand()
    }
}
