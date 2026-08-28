import Foundation

/// Deterministic simulator of the back office of a station: employee files, candidates,
/// bank requests, incoming units, assets and work orders. Replace with API calls when
/// the backend lands; every shape here already matches what the screens read.
nonisolated enum StationOfficeMockData {
    struct Snapshot: Sendable {
        var activeVehicles: Int
        var files: [EmployeeFile]
        var candidates: [Candidate]
        var incorporations: [VehicleIncorporation]
        var bankRequests: [BankChangeRequest]
        var assets: [StationAsset]
        var orders: [WorkOrder]
        var hiringDurations: [Int]
        var audit: [AuditEntry]
    }

    private static let firstNames = [
        "Adrián", "Bárbara", "César", "Dulce", "Ernesto", "Fabiola", "Gustavo", "Helena",
        "Iker", "Julieta", "Karla", "Leonardo", "Miriam", "Néstor", "Olivia", "Patricio",
        "Rebeca", "Salvador", "Tania", "Uriel", "Valeria", "Wilfrido", "Xóchitl", "Yolanda",
    ]

    private static let lastNames = [
        "Anaya", "Beltrán", "Carrillo", "Domínguez", "Estrada", "Figueroa", "Galván", "Herrera",
        "Ibarra", "Juárez", "Lara", "Medina", "Nava", "Olvera", "Peña", "Quintero",
        "Rosales", "Solís", "Trejo", "Urbina", "Valdez", "Zamora",
    ]

    private static let banks = ["BBVA México", "Banorte", "Santander", "HSBC", "Banco Azteca", "Nu México"]

    private static let platforms = [["Uber"], ["Uber", "DiDi"], ["DiDi"], ["Uber", "inDrive"], []]

    private static let cities = ["CDMX", "Ecatepec", "Nezahualcóyotl", "Tlalnepantla", "Naucalpan"]

    // MARK: - Snapshot

    /// - Parameter mayFabricateLiveDriverFile: whether the credential running the driver
    ///   app may have an employee file invented for it here. Deliberately without a
    ///   default: this generator is the only place where a real `profileId` gets handed a
    ///   bank account, a CLABE and a `.verified` badge that nobody registered, and a new
    ///   call site must state which side of that line it stands on rather than inherit the
    ///   permissive answer. The caller derives it from `FleetStore.runsAgainstStation`.
    static func snapshot(
        station: Station,
        supervisorName: String,
        supervisorId: String,
        liveDriver: Driver?,
        mayFabricateLiveDriverFile: Bool,
        now: Date
    ) -> Snapshot {
        if LabRuntime.isTest {
            return LabSeed.stationOfficeSnapshot(world: LabRuntime.world, station: station, now: now)
        }
        var random = SeededGenerator(seed: seed(station: station, now: now))

        let activeVehicles = station.vehicleCapacity
        let files = employeeFiles(
            station: station,
            supervisorName: supervisorName,
            liveDriver: mayFabricateLiveDriverFile ? liveDriver : nil,
            now: now,
            random: &random
        )
        let candidates = self.candidates(
            station: station,
            supervisorName: supervisorName,
            supervisorId: supervisorId,
            now: now,
            random: &random
        )
        let assets = self.assets(station: station, activeVehicles: activeVehicles, now: now, random: &random)
        let orders = workOrders(station: station, assets: assets, supervisorName: supervisorName, now: now, random: &random)

        return Snapshot(
            activeVehicles: activeVehicles,
            files: files,
            candidates: candidates,
            incorporations: incorporations(station: station, now: now),
            bankRequests: bankRequests(station: station, files: files, now: now),
            assets: assets,
            orders: orders,
            hiringDurations: [10, 14, 9, 12, 15, 11, 13, 12],
            audit: []
        )
    }

    // MARK: - Employee files

    /// 60 contracted drivers spread over the four blocks, with the real-life texture:
    /// vacations, a suspension, a medical leave and expiring licences.
    private static func employeeFiles(
        station: Station,
        supervisorName: String,
        liveDriver: Driver?,
        now: Date,
        random: inout SeededGenerator
    ) -> [EmployeeFile] {
        let distribution: [(ShiftBlock, Int)] = [
            (.weekdayMorning, 20),
            (.weekdayEvening, 18),
            (.weekendMorning, 12),
            (.weekendEvening, 10),
        ]

        var files: [EmployeeFile] = []
        var index = 0

        for (block, count) in distribution {
            for slotIndex in 0..<count {
                let first = firstNames[(index * 5 + 2) % firstNames.count]
                let paternal = lastNames[(index * 7 + 3) % lastNames.count]
                let maternal = lastNames[(index * 3 + 11) % lastNames.count]
                let name = "\(first) \(paternal) \(maternal)"
                let id = "drv-f\(String(format: "%03d", 300 + index))"

                let status: EmploymentStatus = {
                    switch index {
                    case 4: return .suspended
                    case 17: return .vacation
                    case 29: return .medicalLeave
                    case 41: return .vacation
                    default: return .active
                    }
                }()

                let hiredAt = now.addingTimeInterval(-Double(random.int(40...900)) * 86_400)
                // Licence expiry: a few already expired, a few about to.
                let licenseExpiry: Date = {
                    switch index % 13 {
                    case 0: return now.addingTimeInterval(Double(random.int(4...26)) * 86_400)
                    case 6: return now.addingTimeInterval(-Double(random.int(2...20)) * 86_400)
                    default: return now.addingTimeInterval(Double(random.int(120...900)) * 86_400)
                    }
                }()
                let missingSome = index % 9 == 2

                var documents = fullChecklist(
                    now: now,
                    uploadedBy: supervisorName,
                    licenseExpiry: licenseExpiry,
                    random: &random
                )
                if missingSome {
                    for kind in [DocumentKind.addressProof, .consent] {
                        if let position = documents.firstIndex(where: { $0.kind == kind }) {
                            documents[position] = StaffDocument(kind: kind, status: .pending)
                        }
                    }
                }

                let bank = BankAccount(
                    bank: banks[index % banks.count],
                    clabe: clabe(index: index),
                    accountNumber: String(format: "%010d", 1_000_000 + index * 7_919),
                    holder: name,
                    rfc: rfc(name: name, index: index),
                    registeredAt: hiredAt,
                    registeredBy: supervisorName,
                    status: index % 11 == 5 ? .pending : .verified,
                    hasProof: index % 11 != 5
                )

                var events: [FileEvent] = [
                    FileEvent(
                        id: "evt-\(id)-hire",
                        kind: .hire,
                        date: hiredAt,
                        detail: "Alta como conductor · bloque \(block.label)",
                        author: supervisorName
                    )
                ]
                if status == .suspended {
                    events.insert(
                        FileEvent(
                            id: "evt-\(id)-susp",
                            kind: .suspension,
                            date: now.addingTimeInterval(-3 * 86_400),
                            detail: "Suspensión de 7 días por reincidencia en retrasos.",
                            author: supervisorName
                        ),
                        at: 0
                    )
                }
                if status == .vacation {
                    events.insert(
                        FileEvent(
                            id: "evt-\(id)-vac",
                            kind: .vacation,
                            date: now.addingTimeInterval(-2 * 86_400),
                            detail: "Periodo vacacional de 6 días autorizado.",
                            author: supervisorName
                        ),
                        at: 0
                    )
                }
                if status == .medicalLeave {
                    events.insert(
                        FileEvent(
                            id: "evt-\(id)-inc",
                            kind: .incident,
                            date: now.addingTimeInterval(-5 * 86_400),
                            detail: "Incapacidad médica por 14 días.",
                            author: supervisorName
                        ),
                        at: 0
                    )
                }
                if index % 8 == 3 {
                    events.insert(
                        FileEvent(
                            id: "evt-\(id)-rec",
                            kind: .recognition,
                            date: now.addingTimeInterval(-Double(random.int(6...40)) * 86_400),
                            detail: "Reconocimiento por cuidado de unidad y cero incidencias.",
                            author: supervisorName
                        ),
                        at: 0
                    )
                }

                files.append(
                    EmployeeFile(
                        id: id,
                        name: name,
                        employeeNumber: "EV-\(2100 + index * 3)",
                        photoAsset: nil,
                        stationId: station.id,
                        block: block,
                        hiredAt: hiredAt,
                        status: status,
                        supervisorName: supervisorName,
                        phone: "55 \(random.int(1000...9999)) \(random.int(1000...9999))",
                        curp: curp(name: name, index: index),
                        rfc: rfc(name: name, index: index),
                        documents: documents,
                        events: events.sorted { $0.date > $1.date },
                        bank: bank,
                        isLiveSession: false
                    )
                )
                index += 1
                if slotIndex == count - 1 { continue }
            }
        }

        // The credential running the driver app owns a real file too.
        //
        // Only when the session may be simulated. `liveDriver` arrives nil for an identity
        // proved by the backend and standing in production: everything below — the hire
        // event, the signed credit contract, and above all the BBVA account with its
        // `.verified` status and its printed proof — would otherwise be written under that
        // person's own `profileId`. The wallet reads exactly this file, so a fixture would
        // be telling a real driver where their week is going to be deposited.
        if let liveDriver, liveDriver.stationId == station.id {
            let block = ShiftBlock.block(group: liveDriver.group, slot: liveDriver.slot)
            let hiredAt = now.addingTimeInterval(-420 * 86_400)
            var documents = fullChecklist(
                now: now,
                uploadedBy: supervisorName,
                licenseExpiry: now.addingTimeInterval(21 * 86_400),
                random: &random
            )
            if let position = documents.firstIndex(where: { $0.kind == .addressProof }) {
                documents[position] = StaffDocument(kind: .addressProof, status: .pending)
            }
            files.insert(
                EmployeeFile(
                    id: liveDriver.id,
                    name: liveDriver.name,
                    employeeNumber: liveDriver.employeeNumber,
                    photoAsset: liveDriver.photoAsset,
                    stationId: station.id,
                    block: block,
                    hiredAt: hiredAt,
                    status: .active,
                    supervisorName: supervisorName,
                    phone: "55 4821 9077",
                    curp: "MERC900412HDFNVR03",
                    rfc: "MERC900412H45",
                    documents: documents,
                    events: [
                        FileEvent(
                            id: "evt-live-hire",
                            kind: .hire,
                            date: hiredAt,
                            detail: "Alta como conductor · bloque \(block.label)",
                            author: supervisorName
                        ),
                        FileEvent(
                            id: "evt-live-credit",
                            kind: .documentUpdate,
                            date: now.addingTimeInterval(-60 * 86_400),
                            detail: "Contrato de crédito de unidad firmado y archivado.",
                            author: supervisorName
                        ),
                    ],
                    bank: BankAccount(
                        bank: "BBVA México",
                        clabe: "012180001234564587",
                        accountNumber: "0123456458",
                        holder: liveDriver.name,
                        rfc: "MERC900412H45",
                        registeredAt: hiredAt,
                        registeredBy: supervisorName,
                        status: .verified,
                        hasProof: true
                    ),
                    isLiveSession: true
                ),
                at: 0
            )
        }

        return files
    }

    private static func fullChecklist(
        now: Date,
        uploadedBy: String,
        licenseExpiry: Date,
        random: inout SeededGenerator
    ) -> [StaffDocument] {
        DocumentKind.hiringChecklist.map { kind in
            let uploaded = now.addingTimeInterval(-Double(random.int(30...600)) * 86_400)
            let expires: Date? = {
                switch kind {
                case .license: return licenseExpiry
                case .addressProof: return uploaded.addingTimeInterval(Double(random.int(60...400)) * 86_400)
                case .officialId: return now.addingTimeInterval(Double(random.int(200...1600)) * 86_400)
                default: return nil
                }
            }()
            return StaffDocument(
                kind: kind,
                status: .delivered,
                uploadedAt: uploaded,
                issuedAt: uploaded,
                expiresAt: expires,
                uploadedBy: uploadedBy,
                versions: []
            )
        }
    }

    // MARK: - Candidates

    private static func candidates(
        station: Station,
        supervisorName: String,
        supervisorId: String,
        now: Date,
        random: inout SeededGenerator
    ) -> [Candidate] {
        let stages: [CandidateStage] = [
            .lead, .lead, .lead, .lead,
            .interview, .interview, .interview,
            .documents, .documents, .documents,
            .approved, .approved,
            .toHire, .toHire, .toHire,
            .hired, .hired,
            .rejected, .rejected, .rejected,
        ]

        return stages.enumerated().map { index, stage in
            let first = firstNames[(index * 3 + 7) % firstNames.count]
            let paternal = lastNames[(index * 5 + 1) % lastNames.count]
            let maternal = lastNames[(index * 9 + 4) % lastNames.count]
            let name = "\(first) \(paternal) \(maternal)"
            let createdAt = now.addingTimeInterval(-Double(random.int(1...34)) * 86_400)
            let block = ShiftBlock.allCases[index % ShiftBlock.allCases.count]

            var interview: InterviewSheet?
            if stage.order >= CandidateStage.interview.order && stage != .rejected {
                var sheet = InterviewSheet(interviewerName: supervisorName)
                for criterion in InterviewCriterion.allCases {
                    sheet.scores[criterion.rawValue] = random.int(3...5)
                }
                sheet.interviewedAt = createdAt.addingTimeInterval(Double(random.int(2...6)) * 86_400)
                sheet.notes = "Buena disposición para el bloque \(block.label). Vive a \(random.int(10...45)) minutos de la estación."
                sheet.decision = sheet.suggestion
                interview = sheet
            } else if stage == .rejected {
                var sheet = InterviewSheet(interviewerName: supervisorName)
                for criterion in InterviewCriterion.allCases {
                    sheet.scores[criterion.rawValue] = random.int(1...3)
                }
                sheet.interviewedAt = createdAt.addingTimeInterval(3 * 86_400)
                sheet.notes = "No cubre la disponibilidad del bloque solicitado."
                sheet.decision = .notRecommended
                interview = sheet
            }

            var documents: [StaffDocument] = []
            if stage.order >= CandidateStage.documents.order && stage != .rejected {
                let delivered = stage == .documents ? random.int(6...10) : DocumentKind.hiringChecklist.count
                documents = DocumentKind.hiringChecklist.enumerated().map { position, kind in
                    position < delivered
                        ? StaffDocument(
                            kind: kind,
                            status: .delivered,
                            uploadedAt: createdAt.addingTimeInterval(Double(position) * 3_600),
                            issuedAt: createdAt,
                            expiresAt: kind == .license ? now.addingTimeInterval(Double(random.int(90...900)) * 86_400) : nil,
                            uploadedBy: supervisorName
                        )
                        : StaffDocument(kind: kind, status: .pending)
                }
            }

            return Candidate(
                id: "cnd-\(String(format: "%03d", index + 1))",
                name: name,
                birthDate: now.addingTimeInterval(-Double(random.int(22...48)) * 365 * 86_400),
                phone: "55 \(random.int(1000...9999)) \(random.int(1000...9999))",
                email: "\(first.lowercased()).\(paternal.lowercased())@correo.mx"
                    .folding(options: .diacriticInsensitive, locale: Fmt.locale),
                curp: curp(name: name, index: index + 40),
                rfc: rfc(name: name, index: index + 40),
                officialId: "INE \(random.int(1000...9999)) \(random.int(1000...9999))",
                address: "Calle \(lastNames[index % lastNames.count]) \(random.int(10...480)), Col. Centro",
                postalCode: "0\(random.int(1000...9999))",
                city: cities[index % cities.count],
                state: index % 3 == 0 ? "Estado de México" : "Ciudad de México",
                experienceYears: random.int(0...9),
                platforms: platforms[index % platforms.count],
                requestedBlock: block,
                availableWeekdays: block.group == .weekday || random.chance(0.6),
                availableWeekends: block.group == .weekend || random.chance(0.45),
                possibleStartAt: now.addingTimeInterval(Double(random.int(3...25)) * 86_400),
                availabilityNote: random.chance(0.4) ? "Puede cubrir turnos extra en fin de semana." : "",
                emergencyName: "\(firstNames[(index * 11) % firstNames.count]) \(paternal)",
                emergencyPhone: "55 \(random.int(1000...9999)) \(random.int(1000...9999))",
                emergencyRelation: index % 3 == 0 ? "Cónyuge" : (index % 3 == 1 ? "Madre" : "Hermano"),
                stationId: station.id,
                supervisorId: supervisorId,
                supervisorName: supervisorName,
                createdAt: createdAt,
                stage: stage,
                interview: interview,
                documents: documents,
                hiredAt: stage == .hired ? createdAt.addingTimeInterval(Double(random.int(9...15)) * 86_400) : nil,
                rejectionReason: stage == .rejected ? "Sin disponibilidad real para el bloque solicitado." : nil
            )
        }
    }

    // MARK: - Incoming units

    private static func incorporations(station: Station, now: Date) -> [VehicleIncorporation] {
        [
            VehicleIncorporation(
                id: "inc-\(station.code)-1",
                stationId: station.id,
                model: "BYD Dolphin Mini 2026",
                units: 6,
                stage: .inTransit,
                arrivalAt: now.addingTimeInterval(6 * 86_400),
                operationStartAt: now.addingTimeInterval(10 * 86_400),
                note: "Liberadas en aduana, llegan por traslado terrestre."
            ),
            VehicleIncorporation(
                id: "inc-\(station.code)-2",
                stationId: station.id,
                model: "BYD Dolphin 2026",
                units: 4,
                stage: .purchaseConfirmed,
                arrivalAt: now.addingTimeInterval(28 * 86_400),
                operationStartAt: now.addingTimeInterval(35 * 86_400),
                note: "Pedido confirmado con la armadora, pendiente de embarque."
            ),
        ]
    }

    // MARK: - Bank requests

    private static func bankRequests(station: Station, files: [EmployeeFile], now: Date) -> [BankChangeRequest] {
        let targets = files.filter { !$0.isLiveSession }.prefix(2)
        return targets.enumerated().map { index, file in
            BankChangeRequest(
                id: "bnk-\(String(format: "%03d", index + 1))",
                driverId: file.id,
                driverName: file.name,
                stationId: station.id,
                createdAt: now.addingTimeInterval(-Double(index + 1) * 36_000),
                bank: index == 0 ? "Nu México" : "Banorte",
                clabe: index == 0 ? "638180000112233445" : "072180001199887766",
                holder: file.name,
                reason: index == 0
                    ? "Cambié de banco por comisiones, la cuenta anterior ya se cerró."
                    : "Mi cuenta fue bloqueada por el banco tras un cargo no reconocido.",
                hasOfficialId: true,
                hasBankProof: true,
                hasAddressProof: index == 0,
                addressMatches: index != 0,
                status: index == 0 ? .requested : .review,
                resolvedAt: nil,
                resolutionNote: nil,
                validatedBy: index == 0 ? nil : "Supervisión",
                approvedBy: nil
            )
        }
    }

    // MARK: - Assets

    private static func assets(
        station: Station,
        activeVehicles: Int,
        now: Date,
        random: inout SeededGenerator
    ) -> [StationAsset] {
        var result: [StationAsset] = []

        let installations: [(AssetCategory, String, String, StationAsset.State)] = [
            (.chargers, "Cargador rápido bahía 1", "CHG-01", .operational),
            (.chargers, "Cargador rápido bahía 2", "CHG-02", .degraded),
            (.chargers, "Cargador rápido bahía 3", "CHG-03", .operational),
            (.chargers, "Cargador semirrápido patio", "CHG-04", .operational),
            (.electrical, "Tablero general de acometida", "ELE-01", .operational),
            (.electrical, "Subtablero de bahías 1-6", "ELE-02", .degraded),
            (.solar, "Arreglo solar techumbre norte", "SOL-01", .operational),
            (.solar, "Arreglo solar techumbre sur", "SOL-02", .down),
            (.inverters, "Inversor híbrido 30 kW", "INV-01", .operational),
            (.warehouse, "Bodega de refacciones", "BOD-01", .operational),
            (.facilities, "Área de descanso de conductores", "INS-01", .operational),
            (.facilities, "Sanitarios y vestidores", "INS-02", .degraded),
            (.tools, "Gato hidráulico y torquímetros", "HER-01", .operational),
            (.computers, "Estación de supervisión", "TIC-01", .operational),
            (.network, "Router principal y respaldo LTE", "RED-01", .degraded),
            (.surveillance, "Circuito cerrado 12 cámaras", "CCTV-01", .operational),
            (.other, "Planta de emergencia", "OTR-01", .operational),
        ]

        for (index, item) in installations.enumerated() {
            result.append(
                StationAsset(
                    id: "ast-\(station.code.lowercased())-\(index)",
                    stationId: station.id,
                    category: item.0,
                    name: item.1,
                    code: item.2,
                    state: item.3,
                    lastServiceAt: now.addingTimeInterval(-Double(random.int(5...120)) * 86_400),
                    note: "",
                    vehicleId: nil
                )
            )
        }

        for index in 0..<activeVehicles {
            let number = 101 + index
            let state: StationAsset.State = index % 17 == 3 ? .down : (index % 11 == 5 ? .degraded : .operational)
            result.append(
                StationAsset(
                    id: "ast-veh-\(station.code.lowercased())-\(number)",
                    stationId: station.id,
                    category: .vehicles,
                    name: "Unidad TEV-\(number)",
                    code: "TEV-\(number)",
                    state: state,
                    lastServiceAt: now.addingTimeInterval(-Double(random.int(3...90)) * 86_400),
                    note: "",
                    vehicleId: "veh-\(station.code.lowercased())-\(number)"
                )
            )
        }

        return result
    }

    // MARK: - Work orders

    private static func workOrders(
        station: Station,
        assets: [StationAsset],
        supervisorName: String,
        now: Date,
        random: inout SeededGenerator
    ) -> [WorkOrder] {
        let technician = StaffDirectory.accounts.first {
            $0.role == .maintenance && $0.stationId == station.id
        }
        let technicianId = technician?.id ?? "acc-mto-generic"
        let technicianName = technician?.name ?? "Personal de mantenimiento"

        let blueprint: [(String, WorkOrderPriority, WorkOrderStatus, Bool, Int, String)] = [
            ("CHG-02", .high, .inProgress, false, 90, "El cargador corta la sesión a los 10 minutos y marca error E-14."),
            ("SOL-02", .medium, .pending, false, 180, "Cadena de paneles sur sin generación desde la tormenta del lunes."),
            ("RED-01", .medium, .waiting, false, 60, "Caídas de enlace en horario pico, respaldo LTE sin activarse."),
            ("INS-02", .low, .pending, false, 120, "Fuga en llave de vestidores y puerta sin cierre."),
            ("ELE-02", .critical, .inProgress, false, 240, "Subtablero con calentamiento en barra de bahías 1-6."),
            ("TEV-104", .high, .finished, false, 150, "Ruido metálico en suspensión trasera reportado por conductor."),
            ("TEV-108", .medium, .closed, true, 120, "Servicio preventivo de 10,000 km: frenos, filtros y refrigerante."),
            ("TEV-112", .low, .returned, false, 45, "Cámara de reversa con imagen intermitente."),
            ("CHG-01", .medium, .closed, true, 90, "Preventivo trimestral de conectores y prueba de carga."),
            ("CCTV-01", .low, .closed, false, 60, "Reubicación de cámara 7 por ángulo muerto en bahías."),
        ]

        return blueprint.enumerated().compactMap { index, item in
            guard let asset = assets.first(where: { $0.code == item.0 }) else { return nil }
            let assignedAt = now.addingTimeInterval(-Double(random.int(2...80)) * 3_600)
            let accepted: Date? = item.2 == .pending ? nil : assignedAt.addingTimeInterval(Double(random.int(5...40)) * 60)
            let finished: Date? = {
                switch item.2 {
                case .finished, .closed, .returned:
                    return (accepted ?? assignedAt).addingTimeInterval(Double(random.int(35...260)) * 60)
                default: return nil
                }
            }()
            let closed: Date? = item.2 == .closed ? finished?.addingTimeInterval(1_800) : nil

            return WorkOrder(
                id: "wo-\(String(format: "%03d", index + 1))",
                folio: "OT-\(String(format: "%04d", 1200 + index))",
                stationId: station.id,
                assetId: asset.id,
                assetName: asset.name,
                assetCode: asset.code,
                category: asset.category,
                problem: item.5,
                priority: item.1,
                isPreventive: item.3,
                assignedAt: assignedAt,
                assignedByName: supervisorName,
                technicianId: technicianId,
                technicianName: technicianName,
                acceptedAt: accepted,
                finishedAt: finished,
                closedAt: closed,
                estimatedMinutes: item.4,
                status: item.2,
                workDone: finished == nil ? "" : "Diagnóstico realizado, componente ajustado y prueba de operación conforme.",
                pendingWork: item.2 == .returned ? "Falta evidencia del cableado posterior al ajuste." : "",
                observations: "",
                materials: finished == nil
                    ? []
                    : [WorkOrderMaterial(id: "mat-\(index)", name: index % 2 == 0 ? "Juego de balatas" : "Conector de carga", quantity: random.int(1...4))],
                evidence: [],
                evidenceAssets: finished == nil ? [] : ["electric_hatchback_charging"],
                returnReason: item.2 == .returned ? "Falta evidencia fotográfica del trabajo terminado." : nil,
                vehicleId: asset.vehicleId
            )
        }
    }

    // MARK: - Identity helpers

    private static func clabe(index: Int) -> String {
        String(format: "0121800%011d", 10_000_000 + index * 137)
    }

    private static func curp(name: String, index: Int) -> String {
        let letters = name.folding(options: .diacriticInsensitive, locale: Fmt.locale)
            .uppercased()
            .filter { $0.isLetter }
            .prefix(4)
        return "\(letters)\(String(format: "%06d", 800_101 + index * 37))HDF\(String(format: "%03d", index % 999))"
    }

    private static func rfc(name: String, index: Int) -> String {
        let letters = name.folding(options: .diacriticInsensitive, locale: Fmt.locale)
            .uppercased()
            .filter { $0.isLetter }
            .prefix(4)
        return "\(letters)\(String(format: "%06d", 850_215 + index * 11))\(String(format: "%02d", index % 99))"
    }

    private static func seed(station: Station, now: Date) -> UInt64 {
        var value: UInt64 = 0x5DEE_CE66
        for byte in station.id.utf8 { value = value &* 31 &+ UInt64(byte) }
        let week = ShiftRules.calendar.ordinality(of: .weekOfYear, in: .era, for: now) ?? 1
        return value &+ UInt64(week)
    }
}
