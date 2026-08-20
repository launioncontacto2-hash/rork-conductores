import Foundation

/// Expansion pipeline the network starts with. Three projects at different stages, so the
/// arithmetic that matters to direction — every unit purchased demands four drivers — is
/// visible with one project on time, one tight and one that opens without a plantilla.
nonisolated enum NationalMockData {
    static func projects(now: Date, author: String) -> [StationProject] {
        guard !LabRuntime.isTest else { return [] }
        let calendar = ShiftRules.calendar

        func date(inDays days: Int) -> Date {
            calendar.date(byAdding: .day, value: days, to: now) ?? now
        }

        return [
            StationProject(
                id: "prj-qro-01",
                code: "QRO-01",
                name: "Estación Querétaro Centro",
                city: "Querétaro",
                regionId: "reg-occ",
                targetVehicles: 18,
                launchDate: date(inDays: 54),
                stage: .fleet,
                hiredDrivers: 44,
                candidatesStarted: 96,
                investmentMxn: 18 * CreditProgram.priceMxn,
                note: "Nave rentada y contrato de carga firmado. La compra de unidades sale del corte del mes.",
                createdAt: date(inDays: -62),
                createdBy: author
            ),
            StationProject(
                id: "prj-mty-01",
                code: "MTY-01",
                name: "Estación Monterrey San Pedro",
                city: "Monterrey",
                regionId: "reg-vm",
                targetVehicles: 22,
                launchDate: date(inDays: 16),
                stage: .hiring,
                hiredDrivers: 51,
                candidatesStarted: 140,
                investmentMxn: 22 * CreditProgram.priceMxn,
                note: "Unidades entregadas y cargadores instalados. La contratación va por detrás del calendario.",
                createdAt: date(inDays: -118),
                createdBy: author
            ),
            StationProject(
                id: "prj-pue-01",
                code: "PUE-01",
                name: "Estación Puebla Angelópolis",
                city: "Puebla",
                regionId: "reg-vm",
                targetVehicles: 14,
                launchDate: date(inDays: 121),
                stage: .study,
                hiredDrivers: 0,
                candidatesStarted: 0,
                investmentMxn: 14 * CreditProgram.priceMxn,
                note: "Estudio de demanda en curso. Falta cerrar el predio y la acometida eléctrica.",
                createdAt: date(inDays: -9),
                createdBy: author
            ),
        ]
    }
}
