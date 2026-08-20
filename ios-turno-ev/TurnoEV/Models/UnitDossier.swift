import Foundation

/// The paperwork the network keeps on file for a unit and for the person driving it.
/// Two desks write here and nobody else: recruitment files the identity of the driver,
/// supervision files the papers of the vehicle. Every other role only reads them.

nonisolated enum DocumentDesk: String, Codable, Sendable {
    case recruitment
    case supervision

    var label: String {
        switch self {
        case .recruitment: "Reclutamiento"
        case .supervision: "Supervisión de estación"
        }
    }

    var symbol: String {
        switch self {
        case .recruitment: "person.text.rectangle.fill"
        case .supervision: "dot.radiowaves.left.and.right"
        }
    }
}

/// Whether the paper belongs to the unit or to the person driving it.
nonisolated enum DossierSubject: String, Codable, Sendable {
    case vehicle
    case driver

    var label: String {
        switch self {
        case .vehicle: "Documentos de la unidad"
        case .driver: "Documentos del conductor"
        }
    }

    var symbol: String {
        switch self {
        case .vehicle: "car.side.fill"
        case .driver: "person.crop.circle.fill"
        }
    }
}

nonisolated enum DossierDocument: String, Codable, CaseIterable, Identifiable, Sendable {
    case insurancePolicy
    case registrationCard
    case invoice
    case driverLicense
    case officialIdCard

    var id: String { rawValue }

    var title: String {
        switch self {
        case .insurancePolicy: "Póliza de seguro"
        case .registrationCard: "Tarjeta de circulación"
        case .invoice: "Factura de la unidad"
        case .driverLicense: "Licencia de conducir"
        case .officialIdCard: "Identificación oficial"
        }
    }

    var hint: String {
        switch self {
        case .insurancePolicy: "Cobertura vigente del vehículo"
        case .registrationCard: "Documento de circulación"
        case .invoice: "Copia para revisión en vía pública"
        case .driverLicense: "Licencia del conductor en turno"
        case .officialIdCard: "Identificación del conductor en turno"
        }
    }

    var symbol: String {
        switch self {
        case .insurancePolicy: "shield.lefthalf.filled"
        case .registrationCard: "doc.text.fill"
        case .invoice: "doc.richtext.fill"
        case .driverLicense: "person.text.rectangle.fill"
        case .officialIdCard: "person.crop.rectangle.fill"
        }
    }

    var subject: DossierSubject {
        switch self {
        case .insurancePolicy, .registrationCard, .invoice: .vehicle
        case .driverLicense, .officialIdCard: .driver
        }
    }

    /// The only desk allowed to upload or replace this paper.
    var desk: DocumentDesk {
        switch self {
        case .insurancePolicy, .registrationCard, .invoice: .supervision
        case .driverLicense, .officialIdCard: .recruitment
        }
    }

    /// Fiscal paper travels as a copy: the viewer stamps it so the screen can never be
    /// presented as the original document.
    var watermark: String? {
        self == .invoice ? "COPIA SIN VALOR FISCAL" : nil
    }

    var expires: Bool {
        switch self {
        case .insurancePolicy, .driverLicense, .officialIdCard: true
        case .registrationCard, .invoice: false
        }
    }

    var referenceLabel: String {
        switch self {
        case .insurancePolicy: "Póliza"
        case .registrationCard: "Folio"
        case .invoice: "Factura"
        case .driverLicense: "Licencia"
        case .officialIdCard: "Clave"
        }
    }

    var issuerLabel: String {
        switch self {
        case .insurancePolicy: "Aseguradora"
        case .registrationCard: "Emisor"
        case .invoice: "Expedida por"
        case .driverLicense: "Emisor"
        case .officialIdCard: "Emisor"
        }
    }

    static let vehicleFile: [DossierDocument] = [.insurancePolicy, .registrationCard, .invoice]
    static let driverFile: [DossierDocument] = [.driverLicense, .officialIdCard]
}

nonisolated enum DossierStatus: String, Sendable {
    case onFile
    case expiringSoon
    case expired
    case missing

    var label: String {
        switch self {
        case .onFile: "Vigente"
        case .expiringSoon: "Por vencer"
        case .expired: "Vencido"
        case .missing: "Sin cargar"
        }
    }

    var symbol: String {
        switch self {
        case .onFile: "checkmark.seal.fill"
        case .expiringSoon: "exclamationmark.triangle.fill"
        case .expired: "calendar.badge.exclamationmark"
        case .missing: "tray.fill"
        }
    }

    var needsAttention: Bool { self != .onFile }
}

/// One filed paper. `image` is the scan; when it is missing the record still carries the
/// data the desk captured, so the viewer renders the sheet with its folio and dates.
nonisolated struct FiledDocument: Codable, Identifiable, Sendable {
    let kind: DossierDocument
    /// Vehicle id for unit papers, driver id for personal ones.
    let subjectId: String
    var subjectLabel: String
    var reference: String
    var issuer: String
    var issuedAt: Date?
    var expiresAt: Date?
    var uploadedBy: String
    var uploadedAt: Date
    var image: Data?

    var id: String { "\(subjectId)|\(kind.rawValue)" }

    var hasScan: Bool { image != nil }

    func status(now: Date) -> DossierStatus {
        guard kind.expires, let expiresAt else { return .onFile }
        if expiresAt < now { return .expired }
        let days = Calendar.current.dateComponents([.day], from: now, to: expiresAt).day ?? 0
        return days <= 30 ? .expiringSoon : .onFile
    }

    func expiryText(now: Date) -> String {
        guard kind.expires, let expiresAt else { return "Sin vencimiento" }
        return expiresAt < now
            ? "Venció el \(Fmt.dateShort(expiresAt))"
            : "Vigente hasta \(Fmt.dateShort(expiresAt))"
    }
}

/// Shared document registry. Same bridge pattern as the assignment book: what
/// recruitment and supervision file, the driver app reads at the moment it is needed.
nonisolated enum DossierBook {
    private static let storageKey = "turnoev.dossier.v1"
    private static let seedKey = "turnoev.dossier.seeded.v1"

    /// These records carry document scans. Views ask for them while drawing, several
    /// times per frame, so the file is decoded once and kept in memory: decoding the
    /// whole archive on every read allocated a fresh copy of every image and pushed the
    /// app out of memory.
    private static var cache: [FiledDocument]?

    private static func decode() -> [FiledDocument] {
        if let cache { return cache }
        guard let data = UserDefaults.standard.data(forKey: storageKey) else {
            cache = []
            return []
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = (try? decoder.decode([FiledDocument].self, from: data)) ?? []
        cache = decoded
        return decoded
    }

    private static func save(_ documents: [FiledDocument]) {
        cache = documents
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(documents) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }

    private static func load() -> [FiledDocument] {
        seedIfNeeded()
        return decode()
    }

    static func all() -> [FiledDocument] { load() }

    static func documents(subjectId: String?) -> [FiledDocument] {
        guard let subjectId else { return [] }
        return load().filter { $0.subjectId == subjectId }
    }

    static func document(kind: DossierDocument, subjectId: String?) -> FiledDocument? {
        guard let subjectId else { return nil }
        return load().first { $0.subjectId == subjectId && $0.kind == kind }
    }

    static func upsert(_ document: FiledDocument) {
        seedIfNeeded()
        var current = decode()
        current.removeAll { $0.id == document.id }
        current.append(document)
        save(current)
    }

    static func remove(kind: DossierDocument, subjectId: String) {
        seedIfNeeded()
        var current = decode()
        current.removeAll { $0.subjectId == subjectId && $0.kind == kind }
        save(current)
    }

    static func clear() {
        cache = nil
        UserDefaults.standard.removeObject(forKey: storageKey)
        UserDefaults.standard.removeObject(forKey: seedKey)
    }

    /// Personal papers follow the person, not the process: once the candidate has a
    /// credential in the network the file is kept under the driver profile, so the app
    /// he opens finds it. While that credential does not exist yet, the candidate id
    /// holds the file.
    static func driverSubjectId(email: String, fallback: String) -> String {
        let cleaned = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !cleaned.isEmpty else { return fallback }
        return StaffDirectory.accounts.first { $0.email == cleaned }?.driverId ?? fallback
    }

    /// Which papers are still missing for a unit + driver pair, in reading order.
    /// The archive is read once and every kind resolved against that snapshot.
    static func missing(vehicleId: String?, driverId: String?) -> [DossierDocument] {
        let filed = load()
        return DossierDocument.allCases.filter { kind in
            guard let subject = kind.subject == .vehicle ? vehicleId : driverId else { return true }
            return !filed.contains { $0.subjectId == subject && $0.kind == kind }
        }
    }

    // MARK: - Demo seed

    /// Fills the registry once with the papers the two desks would already have filed
    /// for the seeded fleet, so the driver's viewer is never empty in a demo station.
    private static func seedIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: seedKey) else { return }
        UserDefaults.standard.set(true, forKey: seedKey)

        let now = Date()
        let calendar = Calendar.current
        var seeded: [FiledDocument] = decode()

        let insurers = ["Qualitas Compañía de Seguros", "GNP Seguros", "AXA Seguros México"]

        for (index, vehicle) in MockData.seededVehicles.enumerated() {
            let label = "\(vehicle.internalNumber) · \(vehicle.model)"
            let issued = calendar.date(byAdding: .month, value: -(6 + index), to: now)
            let expires = calendar.date(byAdding: .month, value: 6 - index, to: now)

            seeded.append(
                FiledDocument(
                    kind: .insurancePolicy,
                    subjectId: vehicle.id,
                    subjectLabel: label,
                    reference: "POL-\(vehicle.internalNumber.suffix(3))-\(2400 + index)",
                    issuer: insurers[index % insurers.count],
                    issuedAt: issued,
                    expiresAt: expires,
                    uploadedBy: "Supervisión de estación",
                    uploadedAt: issued ?? now,
                    image: nil
                )
            )
            seeded.append(
                FiledDocument(
                    kind: .registrationCard,
                    subjectId: vehicle.id,
                    subjectLabel: label,
                    reference: "TC-\(vehicle.plates.replacingOccurrences(of: "-", with: ""))",
                    issuer: "Secretaría de Movilidad · CDMX",
                    issuedAt: calendar.date(byAdding: .year, value: -1, to: now),
                    expiresAt: nil,
                    uploadedBy: "Supervisión de estación",
                    uploadedAt: issued ?? now,
                    image: nil
                )
            )
            seeded.append(
                FiledDocument(
                    kind: .invoice,
                    subjectId: vehicle.id,
                    subjectLabel: label,
                    reference: "F-\(9100 + index * 7)",
                    issuer: "Turno EV Movilidad S.A. de C.V.",
                    issuedAt: calendar.date(byAdding: .year, value: -1, to: now),
                    expiresAt: nil,
                    uploadedBy: "Supervisión de estación",
                    uploadedAt: issued ?? now,
                    image: nil
                )
            )
        }

        let driver = MockData.seededDriver
        seeded.append(
            FiledDocument(
                kind: .driverLicense,
                subjectId: driver.id,
                subjectLabel: "\(driver.name) · \(driver.employeeNumber)",
                reference: "LIC-CDMX-\(driver.employeeNumber.suffix(4))",
                issuer: "Semovi CDMX · Tipo A",
                issuedAt: calendar.date(byAdding: .year, value: -2, to: now),
                expiresAt: calendar.date(byAdding: .year, value: 1, to: now),
                uploadedBy: "Reclutamiento",
                uploadedAt: calendar.date(byAdding: .month, value: -8, to: now) ?? now,
                image: nil
            )
        )
        seeded.append(
            FiledDocument(
                kind: .officialIdCard,
                subjectId: driver.id,
                subjectLabel: "\(driver.name) · \(driver.employeeNumber)",
                reference: "INE-\(driver.employeeNumber.suffix(4))-MX",
                issuer: "INE · Credencial para votar",
                issuedAt: calendar.date(byAdding: .year, value: -4, to: now),
                expiresAt: calendar.date(byAdding: .year, value: 6, to: now),
                uploadedBy: "Reclutamiento",
                uploadedAt: calendar.date(byAdding: .month, value: -8, to: now) ?? now,
                image: nil
            )
        )

        save(seeded)
    }

    /// Builds the record a desk files, keeping ownership explicit.
    static func make(
        kind: DossierDocument,
        subjectId: String,
        subjectLabel: String,
        reference: String,
        issuer: String,
        issuedAt: Date?,
        expiresAt: Date?,
        uploadedBy: String,
        now: Date,
        image: Data?
    ) -> FiledDocument {
        FiledDocument(
            kind: kind,
            subjectId: subjectId,
            subjectLabel: subjectLabel,
            reference: reference.trimmingCharacters(in: .whitespacesAndNewlines),
            issuer: issuer.trimmingCharacters(in: .whitespacesAndNewlines),
            issuedAt: issuedAt,
            expiresAt: kind.expires ? expiresAt : nil,
            uploadedBy: uploadedBy,
            uploadedAt: now,
            image: image
        )
    }
}
