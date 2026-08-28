import Foundation

/// Terms of the fleet's used-unit credit program.
/// Units leave the fleet between 110,000 and 120,000 km and are handed to drivers
/// who built a clean compliance record inside the program.
nonisolated struct CreditProgram: Sendable {
    static let vehicleModel: String = "BYD Dolphin Mini"
    /// Internal figure used only for calculations; never shown in the marketing banner.
    static let priceMxn: Int = 390_000
    static let downPaymentMxn: Int = 0
    static let termMonths: Int = 48
    static let termWeeks: Int = 192
    /// 390,000 / 192 weekly instalments, rounded to the peso.
    static let weeklyMxn: Int = 2_031
    /// The unit stays in the fleet while the driver builds credit behaviour.
    static let deliveryMonth: Int = 24
    static let deliveryWeek: Int = 96
    static let minHandoverKm: Int = 110_000
    static let maxHandoverKm: Int = 120_000

    nonisolated struct Benefit: Identifiable, Sendable {
        let symbol: String
        let title: String
        let detail: String
        var id: String { title }
    }

    static let benefits: [Benefit] = [
        Benefit(symbol: "hand.thumbsup.fill", title: "Sin enganche", detail: "Arrancas tu crédito sin pago inicial"),
        Benefit(symbol: "bolt.badge.checkmark.fill", title: "Aprobación inmediata", detail: "Se firma el mismo día en la estación"),
        Benefit(symbol: "ev.charger.fill", title: "Equipo de carga incluido", detail: "Cargador portátil para tu domicilio"),
        Benefit(symbol: "gauge.with.dots.needle.33percent", title: "Máximo 120,000 km", detail: "La unidad sale de flotilla entre 110 y 120 mil km"),
        Benefit(symbol: "sparkles", title: "Se entrega unidad del año", detail: "Modelo reciente, seminueva certificada"),
        Benefit(symbol: "calendar.badge.clock", title: "Plazo de 48 meses", detail: "192 pagos semanales vía nómina"),
    ]

    nonisolated struct Step: Identifiable, Sendable {
        let index: Int
        let title: String
        let detail: String
        var id: Int { index }
    }

    static let steps: [Step] = [
        Step(index: 1, title: "Firma de contrato", detail: "Sin enganche y con aprobación inmediata"),
        Step(index: 2, title: "Descuento semanal", detail: "Tu abono se descuenta cada semana vía nómina"),
        Step(index: 3, title: "Comportamiento crediticio", detail: "Riesgo bajo, precio bajo: tu cumplimiento define tus condiciones"),
        Step(index: 4, title: "Entrega en el mes 24", detail: "La unidad permanece en flotilla hasta que la recibes"),
    ]

    static let howItWorksScript: String = """
    Los créditos tradicionales incorporan el costo del riesgo en el precio final del vehículo. \
    Nuestro programa funciona de manera diferente. Durante los primeros 24 meses la unidad permanece \
    dentro de la flotilla mientras construyes tu historial de cumplimiento. Ese modelo nos permite \
    reducir costos y ofrecerte mejores condiciones de financiamiento.
    """

    /// Captions shown while the explainer narration plays, in seconds.
    nonisolated struct Caption: Identifiable, Sendable {
        let start: Double
        let text: String
        var id: Double { start }
    }

    static let captions: [Caption] = [
        Caption(start: 0, text: "Los créditos tradicionales incorporan el costo del riesgo en el precio final del vehículo."),
        Caption(start: 7.0, text: "Nuestro programa funciona de manera diferente."),
        Caption(start: 11.1, text: "Durante los primeros 24 meses la unidad permanece en la flotilla mientras construyes tu historial de cumplimiento."),
        Caption(start: 20.4, text: "Ese modelo reduce costos y te da mejores condiciones de financiamiento."),
    ]

    static let imageAssetName: String = "electric_hatchback_charging"
    static let videoResourceName: String = "electric_car_charging_night"
    static let narrationResourceName: String = "credit_program_explanation"
}

nonisolated enum CreditRisk: String, Sendable {
    case low
    case medium
    case high

    var label: String {
        switch self {
        case .low: "Bajo"
        case .medium: "Medio"
        case .high: "Alto"
        }
    }

    var detail: String {
        switch self {
        case .low: "Riesgo bajo: conservas las mejores condiciones del programa."
        case .medium: "Un atraso más y tu perfil sube a riesgo alto."
        case .high: "Riesgo alto: la entrega de la unidad puede posponerse."
        }
    }
}

/// Everything the driver needs to see about an active contract, derived from the account.
nonisolated struct CreditMetrics: Sendable {
    let weeksPaid: Int
    let weeksRemaining: Int
    let paidMxn: Int
    let balanceMxn: Int
    let paymentProgress: Double
    let nextPayment: CreditPayment?
    let complianceRate: Double
    let risk: CreditRisk
    let monthsElapsed: Int
    let monthsToDelivery: Int
    let deliveryProgress: Double
    let estimatedDeliveryDate: Date
    let contractEndDate: Date
    let kmToHandover: Int
    let isUnitDelivered: Bool
}

extension CreditProgram {
    /// Derives the transparent contract metrics for a given moment.
    static func metrics(for account: CreditAccount, now: Date) -> CreditMetrics {
        let calendar = Calendar(identifier: .gregorian)
        let monthsElapsed = max(
            0,
            calendar.dateComponents([.month], from: account.startedAt, to: now).month ?? 0
        )
        let deliveryDate = calendar.date(byAdding: .month, value: deliveryMonth, to: account.startedAt) ?? now
        let endDate = calendar.date(byAdding: .month, value: termMonths, to: account.startedAt) ?? now
        let evaluated = account.onTimePayments + account.latePayments
        let compliance = evaluated > 0 ? Double(account.onTimePayments) / Double(evaluated) : 1

        let risk: CreditRisk = {
            if account.latePayments == 0 { return .low }
            if account.latePayments <= 2 { return .medium }
            return .high
        }()

        return CreditMetrics(
            weeksPaid: account.weeksPaid,
            weeksRemaining: max(0, termWeeks - account.weeksPaid),
            paidMxn: account.paidMxn,
            balanceMxn: max(0, account.totalMxn - account.paidMxn),
            paymentProgress: account.totalMxn > 0 ? Double(account.paidMxn) / Double(account.totalMxn) : 0,
            nextPayment: account.payments
                .filter { $0.status != .paid }
                .sorted { $0.dueDate < $1.dueDate }
                .first,
            complianceRate: compliance,
            risk: risk,
            monthsElapsed: monthsElapsed,
            monthsToDelivery: max(0, deliveryMonth - monthsElapsed),
            deliveryProgress: min(1, Double(monthsElapsed) / Double(deliveryMonth)),
            estimatedDeliveryDate: deliveryDate,
            contractEndDate: endDate,
            kmToHandover: max(0, minHandoverKm - account.assignedVehicleOdometerKm),
            isUnitDelivered: monthsElapsed >= deliveryMonth
        )
    }

    /// Fresh contract signed today: no down payment, first instalment in a week.
    ///
    /// `driverId` and `origin` are required, with no defaults on purpose: the caller has
    /// to state whose contract this is and who produced it. There is no way to mint an
    /// anonymous one.
    static func newAccount(
        now: Date,
        vehicleInternalNumber: String,
        driverId: String,
        origin: RecordOrigin
    ) -> CreditAccount {
        CreditAccount(
            driverId: driverId,
            origin: origin,
            contractId: "CR-\(Int(now.timeIntervalSince1970) % 100_000)",
            vehicleTarget: "\(vehicleModel) · \(vehicleInternalNumber)",
            startedAt: now,
            totalMxn: priceMxn,
            paidMxn: 0,
            weeklyMxn: weeklyMxn,
            weeksPaid: 0,
            onTimePayments: 0,
            latePayments: 0,
            assignedVehicleOdometerKm: 96_480,
            payments: [
                CreditPayment(
                    id: "cp-new-1",
                    concept: "Abono semanal 1",
                    dueDate: now.addingTimeInterval(7 * 86400),
                    amountMxn: weeklyMxn,
                    status: .due
                ),
            ]
        )
    }
}
