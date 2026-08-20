import Foundation

/// Deterministic simulator of a recruitment desk: 150 leads distributed across the
/// funnel, the campaigns that produced them, the agenda of interviews and a couple of
/// deliberate duplicates so the duplicate guard can be seen working. Replace with the
/// central database when the backend lands — every shape already matches the screens.
nonisolated enum RecruitmentMockData {
    struct Snapshot: Sendable {
        var prospects: [Prospect]
        var campaigns: [RecruitCampaign]
        var appointments: [Appointment]
    }

    private static let firstNames = [
        "Alejandro", "Brenda", "Cristian", "Daniela", "Emiliano", "Fernanda", "Gerardo", "Hilda",
        "Ismael", "Jazmín", "Kevin", "Lorena", "Marco", "Nayeli", "Omar", "Perla",
        "Quetzal", "Rodrigo", "Sofía", "Tomás", "Ulises", "Verónica", "Wendy", "Ximena",
        "Yahir", "Zaira", "Abril", "Bruno", "Citlali", "Diego",
    ]

    private static let lastNames = [
        "Aguilar", "Bautista", "Cordero", "Delgado", "Escamilla", "Fuentes", "Garrido", "Hinojosa",
        "Íñiguez", "Jaramillo", "Kuri", "Landeros", "Maldonado", "Novoa", "Ontiveros", "Pacheco",
        "Rendón", "Sandoval", "Tapia", "Ugalde", "Villalobos", "Yépez", "Zúñiga", "Barrios",
    ]

    private static let platformSets = [
        ["Uber"], ["Uber", "DiDi"], ["DiDi"], ["Uber", "inDrive"], ["DiDi", "inDrive"], [],
    ]

    private static let citiesByStation: [String: [String]] = [
        "est-nte-cdmx": ["CDMX", "Ecatepec", "Tlalnepantla", "Naucalpan"],
        "est-sur-cdmx": ["CDMX", "Iztapalapa", "Xochimilco", "Tláhuac"],
        "est-gdl-chap": ["Guadalajara", "Zapopan", "Tlaquepaque", "Tonalá"],
    ]

    /// How the 150 leads sit across the funnel today.
    private static let stagePlan: [(stage: RecruitStage, count: Int)] = [
        (.lead, 30),
        (.contacted, 22),
        (.prequalified, 14),
        (.interviewed, 10),
        (.documents, 8),
        (.readyToHire, 7),
        (.approved, 4),
        (.hired, 10),
        (.lost, 45),
    ]

    // MARK: - Snapshot

    static func snapshot(stations: [Station], recruiterName: String, now: Date) -> Snapshot {
        if LabRuntime.isTest {
            return LabSeed.recruitmentSnapshot(world: LabRuntime.world, stations: stations)
        }
        guard !stations.isEmpty else {
            return Snapshot(prospects: [], campaigns: [], appointments: [])
        }
        var random = SeededGenerator(seed: seed(stations: stations, now: now))
        let campaigns = self.campaigns(stations: stations, now: now, random: &random)
        var prospects = self.prospects(
            stations: stations,
            campaigns: campaigns,
            recruiterName: recruiterName,
            now: now,
            random: &random
        )
        prospects.append(contentsOf: duplicates(of: prospects, recruiterName: recruiterName, now: now))
        let appointments = self.appointments(prospects: prospects, now: now, random: &random)
        return Snapshot(prospects: prospects, campaigns: campaigns, appointments: appointments)
    }

    private static func seed(stations: [Station], now: Date) -> UInt64 {
        let week = ShiftRules.calendar.ordinality(of: .weekOfYear, in: .era, for: now) ?? 0
        let base = stations.reduce(0) { $0 + $1.code.utf8.reduce(0) { Int($0) + Int($1) } }
        return UInt64(abs(base) % 100_000 + week * 7_919 + 13)
    }

    // MARK: - Campaigns

    private static func campaigns(
        stations: [Station],
        now: Date,
        random: inout SeededGenerator
    ) -> [RecruitCampaign] {
        var result: [RecruitCampaign] = []
        let month = Fmt.monthLong(now).split(separator: " ").first.map(String.init) ?? "Mes"

        for (index, station) in stations.enumerated() {
            let budget = 12_000 + index * 3_000
            result.append(
                RecruitCampaign(
                    id: "cmp-fb-\(station.code)",
                    name: "Facebook · \(station.name) \(month)",
                    platform: .facebook,
                    stationId: station.id,
                    startedAt: now.addingTimeInterval(-Double(random.int(18...26)) * 86_400),
                    endsAt: now.addingTimeInterval(Double(random.int(4...12)) * 86_400),
                    budgetMxn: budget,
                    spentMxn: Int(Double(budget) * random.double(0.55...0.92)),
                    isActive: true,
                    externalFormId: "form_\(station.code.lowercased())_fb"
                )
            )
            result.append(
                RecruitCampaign(
                    id: "cmp-ig-\(station.code)",
                    name: "Instagram · \(station.name) \(month)",
                    platform: .instagram,
                    stationId: station.id,
                    startedAt: now.addingTimeInterval(-Double(random.int(10...20)) * 86_400),
                    endsAt: now.addingTimeInterval(Double(random.int(3...15)) * 86_400),
                    budgetMxn: 7_000 + index * 1_500,
                    spentMxn: Int(Double(7_000 + index * 1_500) * random.double(0.4...0.85)),
                    isActive: true,
                    externalFormId: "form_\(station.code.lowercased())_ig"
                )
            )
        }

        if let first = stations.first {
            result.append(
                RecruitCampaign(
                    id: "cmp-bolsa-\(first.code)",
                    name: "Bolsa de trabajo · nacional",
                    platform: .jobBoard,
                    stationId: first.id,
                    startedAt: now.addingTimeInterval(-45 * 86_400),
                    endsAt: now.addingTimeInterval(-6 * 86_400),
                    budgetMxn: 9_000,
                    spentMxn: 9_000,
                    isActive: false,
                    externalFormId: nil
                )
            )
        }
        return result
    }

    // MARK: - Prospects

    private static func prospects(
        stations: [Station],
        campaigns: [RecruitCampaign],
        recruiterName: String,
        now: Date,
        random: inout SeededGenerator
    ) -> [Prospect] {
        var result: [Prospect] = []
        var index = 0

        for entry in stagePlan {
            for _ in 0..<entry.count {
                index += 1
                let station = stations[index % stations.count]
                let source = self.source(random: &random)
                let campaign = campaigns.first {
                    $0.stationId == station.id && $0.platform == source
                }
                result.append(
                    prospect(
                        index: index,
                        station: station,
                        stage: entry.stage,
                        source: source,
                        campaignId: campaign?.id,
                        recruiterName: recruiterName,
                        now: now,
                        random: &random
                    )
                )
            }
        }
        return result
    }

    private static func source(random: inout SeededGenerator) -> LeadSource {
        let roll = random.double()
        if roll < 0.42 { return .facebook }
        if roll < 0.66 { return .instagram }
        if roll < 0.78 { return .referral }
        if roll < 0.88 { return .website }
        if roll < 0.95 { return .walkIn }
        return .jobBoard
    }

    private static func prospect(
        index: Int,
        station: Station,
        stage: RecruitStage,
        source: LeadSource,
        campaignId: String?,
        recruiterName: String,
        now: Date,
        random: inout SeededGenerator
    ) -> Prospect {
        let name = "\(random.pick(firstNames)) \(random.pick(lastNames)) \(random.pick(lastNames))"
        let block = random.pick(ShiftBlock.allCases)
        let ageDays: Int = {
            switch stage {
            case .lead: random.int(0...2)
            case .contacted: random.int(1...5)
            case .prequalified: random.int(3...9)
            case .interviewed: random.int(5...13)
            case .documents: random.int(7...16)
            case .readyToHire: random.int(9...18)
            case .approved: random.int(10...20)
            case .hired: random.int(9...16)
            case .lost: random.int(2...25)
            }
        }()
        let createdAt = now.addingTimeInterval(-Double(ageDays) * 86_400 - Double(random.int(0...20)) * 3_600)
        let experience = random.int(0...9)
        let hasLicense = random.chance(0.92)
        let age = random.int(21...52)
        let cities = citiesByStation[station.id] ?? [station.city]

        var prospect = Prospect(
            id: "prs-\(String(format: "%04d", index))",
            name: name,
            phone: phone(index: index, random: &random),
            email: email(name: name, index: index),
            city: random.pick(cities),
            age: age,
            curp: curp(index: index, random: &random),
            stationId: station.id,
            requestedBlock: block,
            experienceYears: experience,
            platforms: random.pick(platformSets),
            hasLicense: hasLicense,
            source: source,
            campaignId: campaignId,
            createdAt: createdAt,
            stage: stage,
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
            ownerName: recruiterName,
            notes: "",
            history: []
        )

        var history: [ProspectEvent] = [
            ProspectEvent(
                id: "\(prospect.id)-e0",
                kind: .created,
                date: createdAt,
                detail: "Lead recibido desde \(source.label)\(campaignId == nil ? "" : " · campaña activa").",
                author: source.isMetaChannel ? "Integración Meta (simulada)" : recruiterName
            ),
        ]

        // Contact
        if stage.order >= RecruitStage.contacted.order || stage == .lost {
            let delay = Double(random.int(12...420)) * 60
            let contactedAt = createdAt.addingTimeInterval(delay)
            if contactedAt < now, stage != .lead {
                prospect.contactedAt = contactedAt
                history.append(
                    ProspectEvent(
                        id: "\(prospect.id)-e1",
                        kind: .contact,
                        date: contactedAt,
                        detail: "Primer contacto telefónico. Interesado en \(block.label).",
                        author: recruiterName
                    )
                )
            }
        }

        // Screening
        if stage.order >= RecruitStage.prequalified.order, stage != .lost {
            var screening = Screening(reviewer: recruiterName)
            for check in ScreeningCheck.allCases {
                let value: Bool = {
                    switch check {
                    case .age: age >= 21
                    case .license: hasLicense
                    case .drivingExperience: experience >= 1
                    case .platformExperience: !prospect.platforms.isEmpty
                    default: random.chance(0.86)
                    }
                }()
                screening.answers[check.rawValue] = value
            }
            screening.reviewedAt = createdAt.addingTimeInterval(Double(random.int(1...3)) * 86_400)
            screening.decision = screening.suggestion == .unfit ? .review : screening.suggestion
            screening.notes = "Confirma disponibilidad para \(block.label) y traslado desde \(prospect.city)."
            prospect.screening = screening
            history.append(
                ProspectEvent(
                    id: "\(prospect.id)-e2",
                    kind: .screening,
                    date: screening.reviewedAt ?? createdAt,
                    detail: "Precalificación: \(screening.outcome.label) · \(screening.passed)/\(ScreeningCheck.allCases.count) criterios.",
                    author: recruiterName
                )
            )
        }

        // Interview
        if stage.order >= RecruitStage.interviewed.order, stage != .lost {
            var sheet = InterviewSheet(interviewerName: recruiterName)
            for criterion in InterviewCriterion.allCases {
                sheet.scores[criterion.rawValue] = random.int(3...5)
            }
            sheet.interviewedAt = createdAt.addingTimeInterval(Double(random.int(3...6)) * 86_400)
            sheet.decision = sheet.suggestion
            sheet.notes = "Historial verificable en apps de movilidad. Sin observaciones de presentación."
            prospect.interview = sheet
            history.append(
                ProspectEvent(
                    id: "\(prospect.id)-e3",
                    kind: .interview,
                    date: sheet.interviewedAt ?? createdAt,
                    detail: "Primera entrevista: \(sheet.scorePct) / 100 · \(sheet.suggestion.label).",
                    author: recruiterName
                )
            )
        }

        // Documents
        if stage.order >= RecruitStage.documents.order, stage != .lost {
            let delivered = stage.order >= RecruitStage.readyToHire.order
                ? DocumentKind.recruitmentChecklist.count
                : random.int(3...5)
            prospect.documents = DocumentKind.recruitmentChecklist.enumerated().map { position, kind in
                let isDelivered = position < delivered
                return StaffDocument(
                    kind: kind,
                    status: isDelivered ? .delivered : .pending,
                    uploadedAt: isDelivered ? createdAt.addingTimeInterval(Double(random.int(4...8)) * 86_400) : nil,
                    expiresAt: isDelivered && kind.expires
                        ? now.addingTimeInterval(Double(random.int(120...900)) * 86_400)
                        : nil,
                    uploadedBy: isDelivered ? recruiterName : nil
                )
            }
            history.append(
                ProspectEvent(
                    id: "\(prospect.id)-e4",
                    kind: .document,
                    date: createdAt.addingTimeInterval(Double(random.int(4...8)) * 86_400),
                    detail: "Expediente inicial al \(Int(Double(delivered) / Double(DocumentKind.recruitmentChecklist.count) * 100)) %.",
                    author: recruiterName
                )
            )
        }

        // Ready for the alta and hiring decision — both taken by recruitment itself.
        if stage.order >= RecruitStage.readyToHire.order, stage != .lost {
            let readyAt = createdAt.addingTimeInterval(Double(random.int(7...11)) * 86_400)
            history.append(
                ProspectEvent(
                    id: "\(prospect.id)-e5",
                    kind: .stage,
                    date: readyAt,
                    detail: "Expediente inicial completo. Listo para firmar el alta en \(station.code).",
                    author: recruiterName
                )
            )
            if stage == .approved || stage == .hired {
                let verdictAt = readyAt.addingTimeInterval(Double(random.int(1...3)) * 86_400)
                prospect.authorizedAt = verdictAt
                prospect.hiringVerdict = .approved
                prospect.verdictAt = verdictAt
                prospect.hiringNote = "Perfil compatible con el bloque solicitado y con la vacante abierta."
                history.append(
                    ProspectEvent(
                        id: "\(prospect.id)-e6",
                        kind: .verdict,
                        date: verdictAt,
                        detail: "Alta autorizada por reclutamiento.",
                        author: recruiterName
                    )
                )
            }
        }

        if stage == .hired {
            let hiredAt = createdAt.addingTimeInterval(Double(random.int(9...15)) * 86_400)
            prospect.hiredAt = hiredAt
            history.append(
                ProspectEvent(
                    id: "\(prospect.id)-e7",
                    kind: .stage,
                    date: hiredAt,
                    detail: "Alta firmada · \(station.displayName) · \(block.label).",
                    author: recruiterName
                )
            )
        }

        if stage == .lost {
            let reason = random.pick(LossReason.allCases)
            prospect.lossReason = reason
            prospect.lossNote = "Salida registrada durante el seguimiento."
            history.append(
                ProspectEvent(
                    id: "\(prospect.id)-e8",
                    kind: .lost,
                    date: createdAt.addingTimeInterval(Double(random.int(1...6)) * 86_400),
                    detail: "Motivo de pérdida: \(reason.label).",
                    author: recruiterName
                )
            )
        }

        prospect.history = history.sorted { $0.date > $1.date }
        return prospect
    }

    // MARK: - Duplicates

    /// Two people that already exist in the base, arriving again from another campaign.
    /// They are seeded on purpose so the duplicate guard can be seen working.
    private static func duplicates(
        of prospects: [Prospect],
        recruiterName: String,
        now: Date
    ) -> [Prospect] {
        let sources = prospects.filter { $0.stage == .lost || $0.stage == .contacted }.prefix(2)
        return sources.enumerated().map { index, origin in
            var copy = origin
            let created = now.addingTimeInterval(-Double(index + 1) * 5_400)
            return Prospect(
                id: "prs-dup-\(index + 1)",
                name: copy.name,
                phone: copy.phone,
                email: copy.email,
                city: copy.city,
                age: copy.age,
                curp: copy.curp,
                stationId: copy.stationId,
                requestedBlock: copy.requestedBlock,
                experienceYears: copy.experienceYears,
                platforms: copy.platforms,
                hasLicense: copy.hasLicense,
                source: index == 0 ? .instagram : .referral,
                campaignId: nil,
                createdAt: created,
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
                ownerName: recruiterName,
                notes: "",
                history: [
                    ProspectEvent(
                        id: "prs-dup-\(index + 1)-e0",
                        kind: .created,
                        date: created,
                        detail: "Lead recibido nuevamente. Coincide con un expediente existente.",
                        author: "Integración Meta (simulada)"
                    ),
                ]
            )
        }
    }

    // MARK: - Appointments

    private static func appointments(
        prospects: [Prospect],
        now: Date,
        random: inout SeededGenerator
    ) -> [Appointment] {
        var result: [Appointment] = []
        let calendar = ShiftRules.calendar

        // Upcoming agenda: first interviews for people already contacted.
        let upcoming = prospects.filter { $0.stage == .contacted || $0.stage == .prequalified }.prefix(14)
        for (index, prospect) in upcoming.enumerated() {
            let dayOffset = index % 5
            let hour = 9 + (index % 7)
            let base = calendar.date(
                bySettingHour: hour,
                minute: index % 2 == 0 ? 0 : 30,
                second: 0,
                of: now.addingTimeInterval(Double(dayOffset) * 86_400)
            ) ?? now
            result.append(
                Appointment(
                    id: "apt-\(prospect.id)",
                    prospectId: prospect.id,
                    prospectName: prospect.name,
                    stationId: prospect.stationId,
                    date: base,
                    kind: index % 3 == 0 ? .phone : (index % 3 == 1 ? .video : .onsite),
                    owner: prospect.ownerName,
                    status: index % 4 == 0 ? .confirmed : .scheduled,
                    note: "Entrevista inicial de reclutamiento.",
                    remindedAt: nil
                )
            )
        }

        // Document appointments: the candidate comes to close his initial file so the
        // alta can be signed the same day.
        let operational = prospects.filter { $0.stage == .readyToHire }.prefix(7)
        for (index, prospect) in operational.enumerated() {
            let base = calendar.date(
                bySettingHour: 11 + (index % 5),
                minute: 0,
                second: 0,
                of: now.addingTimeInterval(Double(index % 4 + 1) * 86_400)
            ) ?? now
            result.append(
                Appointment(
                    id: "apt-op-\(prospect.id)",
                    prospectId: prospect.id,
                    prospectName: prospect.name,
                    stationId: prospect.stationId,
                    date: base,
                    kind: .operational,
                    owner: prospect.ownerName,
                    status: .scheduled,
                    note: "Cierre de expediente y firma del alta.",
                    remindedAt: nil
                )
            )
        }

        // History: attendance and no-shows feed the metrics.
        let past = prospects.filter { $0.stage == .hired || $0.stage == .lost }.prefix(12)
        for (index, prospect) in past.enumerated() {
            let base = now.addingTimeInterval(-Double(random.int(2...12)) * 86_400)
            result.append(
                Appointment(
                    id: "apt-old-\(prospect.id)",
                    prospectId: prospect.id,
                    prospectName: prospect.name,
                    stationId: prospect.stationId,
                    date: base,
                    kind: index % 2 == 0 ? .onsite : .video,
                    owner: prospect.ownerName,
                    status: prospect.stage == .hired ? .attended : (index % 3 == 0 ? .noShow : .attended),
                    note: "Entrevista de reclutamiento.",
                    remindedAt: nil
                )
            )
        }

        return result.sorted { $0.date < $1.date }
    }

    // MARK: - Field helpers

    private static func phone(index: Int, random: inout SeededGenerator) -> String {
        let prefix = random.pick(["55", "56", "33", "81"])
        let body = String(format: "%04d%04d", random.int(1000...9999), (index * 37) % 10_000)
        return "\(prefix) \(body.prefix(4)) \(body.suffix(4))"
    }

    private static func email(name: String, index: Int) -> String {
        let parts = name.lowercased().split(separator: " ")
        let user = parts.prefix(2).joined(separator: ".")
            .folding(options: .diacriticInsensitive, locale: Locale(identifier: "es_MX"))
        return "\(user)\(index)@correo.mx"
    }

    private static func curp(index: Int, random: inout SeededGenerator) -> String {
        let letters = ["A", "B", "C", "D", "E", "F", "G", "H", "J", "L", "M", "N", "P", "R", "S", "T", "V", "Z"]
        let head = (0..<4).map { _ in random.pick(letters) }.joined()
        let digits = String(format: "%06d", random.int(700_101...991_231))
        let tail = (0..<6).map { _ in random.pick(letters) }.joined()
        return "\(head)\(digits)\(tail)\(String(format: "%02d", index % 100))"
    }
}
