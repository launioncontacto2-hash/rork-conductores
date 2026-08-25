import SwiftUI

/// The rule book of the network. Metas, tolerancias, bonos y crédito viven aquí, y solo
/// dirección los mueve: una estación no negocia sus reglas, las hereda. Cada movimiento
/// queda versionado, con el valor anterior y quién lo cambió.
struct NationalPolicyView: View {
    let national: NationalStore

    @State private var editing: PolicyField?
    @State private var isEditingCashAccount: Bool = false
    @State private var cashVersion: Int = 0

    /// One editable rule of the book.
    private enum PolicyField: String, Identifiable {
        case weekdayHourly
        case weekdayDaily
        case weekendHourly
        case weekendDaily
        case trips
        case grace
        case battery
        case photos
        case maxVehicles
        case bonusPunctuality
        case bonusBilling
        case bonusCare
        case creditWeekly

        var id: String { rawValue }

        var title: String {
            switch self {
            case .weekdayHourly: "Meta por hora entre semana"
            case .weekdayDaily: "Meta diaria entre semana"
            case .weekendHourly: "Meta por hora fin de semana"
            case .weekendDaily: "Meta diaria fin de semana"
            case .trips: "Viajes por jornada"
            case .grace: "Tolerancia de inicio"
            case .battery: "Batería mínima de entrega"
            case .photos: "Fotos de inspección"
            case .maxVehicles: "Máximo de unidades por estación"
            case .bonusPunctuality: "Bono de puntualidad"
            case .bonusBilling: "Bono de facturación"
            case .bonusCare: "Bono de limpieza y cuidado"
            case .creditWeekly: "Abono semanal del crédito"
            }
        }

        /// Field key stored in the change log.
        var key: String {
            switch self {
            case .weekdayHourly: "weekdayHourlyMxn"
            case .weekdayDaily: "weekdayDailyMxn"
            case .weekendHourly: "weekendHourlyMxn"
            case .weekendDaily: "weekendDailyMxn"
            case .trips: "tripsPerDay"
            case .grace: "graceMinutes"
            case .battery: "minimumBatteryPct"
            case .photos: "inspectionPhotos"
            case .maxVehicles: "maxVehiclesPerStation"
            case .bonusPunctuality: "bonusPunctualityMxn"
            case .bonusBilling: "bonusBillingMxn"
            case .bonusCare: "bonusCareMxn"
            case .creditWeekly: "creditWeeklyMxn"
            }
        }

        var range: ClosedRange<Int> {
            switch self {
            case .weekdayHourly, .weekendHourly: 80...600
            case .weekdayDaily, .weekendDaily: 500...6_000
            case .trips: 4...40
            case .grace: 0...45
            case .battery: 40...100
            case .photos: 2...12
            case .maxVehicles: 5...120
            case .bonusPunctuality, .bonusBilling, .bonusCare: 0...6_000
            case .creditWeekly: 500...6_000
            }
        }

        var step: Int {
            switch self {
            case .weekdayHourly, .weekendHourly: 10
            case .weekdayDaily, .weekendDaily: 20
            case .trips, .photos: 1
            case .grace: 1
            case .battery: 5
            case .maxVehicles: 1
            case .bonusPunctuality, .bonusBilling, .bonusCare, .creditWeekly: 50
            }
        }

        var isMoney: Bool {
            switch self {
            case .trips, .grace, .battery, .photos, .maxVehicles: false
            default: true
            }
        }

        var consequence: String {
            switch self {
            case .weekdayHourly, .weekdayDaily, .weekendHourly, .weekendDaily:
                "Cambia el objetivo de cada conductor y la meta de todas las estaciones desde el siguiente corte."
            case .trips:
                "Ajusta el contador de viajes del panel de turno y de las metas semanales."
            case .grace:
                "Después de esta tolerancia el inicio se marca con atraso y se genera tiempo adeudado."
            case .battery:
                "Ninguna unidad puede entregarse por debajo de este nivel de carga."
            case .photos:
                "Número de evidencias obligatorias en la inspección de entrega y recepción."
            case .maxVehicles:
                "Techo de diseño de una estación. No cambia la flotilla instalada, solo el límite."
            case .bonusPunctuality, .bonusBilling, .bonusCare:
                "Se evalúa por semana y se paga con el corte del mes; una semana fallida cancela el bono."
            case .creditWeekly:
                "Descuento semanal vía nómina de los contratos nuevos. Los vigentes conservan su condición."
            }
        }
    }

    var body: some View {
        NationalScreen(title: "Reglas de la red") {
            versionCard
            goalsSection
            operationSection
            bonusSection
            cashSection
            creditSection
            structureSection
            logSection
            restoreButton
        }
        .sheet(isPresented: $isEditingCashAccount) {
            CashAccountEditorView(national: national) { cashVersion += 1 }
        }
        .sheet(item: $editing) { field in
            PolicyEditorView(
                national: national,
                title: field.title,
                consequence: field.consequence,
                key: field.key,
                range: field.range,
                step: field.step,
                isMoney: field.isMoney,
                initialValue: value(for: field)
            )
        }
    }

    private var policy: PolicyBook { national.policy }

    private func value(for field: PolicyField) -> Int {
        switch field {
        case .weekdayHourly: policy.weekdayHourlyMxn
        case .weekdayDaily: policy.weekdayDailyMxn
        case .weekendHourly: policy.weekendHourlyMxn
        case .weekendDaily: policy.weekendDailyMxn
        case .trips: policy.tripsPerDay
        case .grace: policy.graceMinutes
        case .battery: policy.minimumBatteryPct
        case .photos: policy.inspectionPhotos
        case .maxVehicles: policy.maxVehiclesPerStation
        case .bonusPunctuality: policy.bonusPunctualityMxn
        case .bonusBilling: policy.bonusBillingMxn
        case .bonusCare: policy.bonusCareMxn
        case .creditWeekly: policy.creditWeeklyMxn
        }
    }

    private func display(_ field: PolicyField) -> String {
        let raw = value(for: field)
        switch field {
        case .trips: return "\(raw)"
        case .grace: return "\(raw) min"
        case .battery: return "\(raw)%"
        case .photos: return "\(raw)"
        case .maxVehicles: return "\(raw)"
        default: return Fmt.mxn(raw)
        }
    }

    // MARK: - Sections

    private var versionCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Image(systemName: "text.book.closed.fill")
                    .font(.system(.title3, weight: .bold))
                    .foregroundStyle(NatTone.accent)
                    .frame(width: 42, height: 42)
                    .background(NatTone.accent.opacity(0.13), in: .rect(cornerRadius: 14))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Versión \(policy.version) del libro de reglas")
                        .font(.system(.subheadline, weight: .black))
                    Text("Actualizada \(Fmt.dateShort(policy.updatedAt)) por \(policy.updatedBy)")
                        .font(.caption2)
                        .foregroundStyle(Palette.textMuted)
                }
                Spacer(minLength: 0)
            }
            Text("Todas las estaciones del país operan con estos números. Un cambio aquí baja a conductores, supervisores, taller y gerencia sin que nadie tenga que avisarles.")
                .font(.caption2)
                .foregroundStyle(Palette.textMuted)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .panel()
    }

    private var goalsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SupSectionHeader(title: "Metas de facturación", subtitle: "Entre semana y fin de semana")
            PolicyRow(
                title: PolicyField.weekdayHourly.title,
                detail: "Base del objetivo por jornada de 8 horas",
                value: display(.weekdayHourly)
            ) { editing = .weekdayHourly }
            PolicyRow(
                title: PolicyField.weekdayDaily.title,
                detail: "Objetivo que ve el conductor en su panel",
                value: display(.weekdayDaily)
            ) { editing = .weekdayDaily }
            PolicyRow(
                title: PolicyField.weekendHourly.title,
                detail: "Sábado y domingo",
                value: display(.weekendHourly)
            ) { editing = .weekendHourly }
            PolicyRow(
                title: PolicyField.weekendDaily.title,
                detail: "Sábado y domingo",
                value: display(.weekendDaily)
            ) { editing = .weekendDaily }
            PolicyRow(
                title: PolicyField.trips.title,
                detail: "Meta de viajes de la jornada",
                value: display(.trips)
            ) { editing = .trips }
        }
        .padding(16)
        .panel()
    }

    private var operationSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SupSectionHeader(title: "Operación", subtitle: "Lo que valida la estación en cada entrega")
            PolicyRow(
                title: PolicyField.grace.title,
                detail: "Minutos antes de marcar atraso",
                value: display(.grace)
            ) { editing = .grace }
            PolicyRow(
                title: PolicyField.battery.title,
                detail: "Carga mínima para entregar una unidad",
                value: display(.battery)
            ) { editing = .battery }
            PolicyRow(
                title: PolicyField.photos.title,
                detail: "Evidencias obligatorias por inspección",
                value: display(.photos)
            ) { editing = .photos }
        }
        .padding(16)
        .panel()
    }

    private var bonusSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SupSectionHeader(
                title: "Bonos",
                subtitle: "Evaluación semanal, pago mensual · techo \(Fmt.mxn(policy.monthlyBonusCeilingMxn))"
            )

            NoticeBanner(
                symbol: "gearshape.2.fill",
                title: "Los bonos se resuelven solos",
                message: "El motor de metas los autoriza al cerrar las 4 semanas en verde y los cancela con la primera semana incumplida. Nadie los firma uno por uno: esta pantalla es el único lugar de la red donde un bono se puede cambiar.",
                tone: .volt
            )

            PolicyRow(
                title: PolicyField.bonusPunctuality.title,
                detail: "Se pierde con una falta o con tiempo adeudado al cierre",
                value: display(.bonusPunctuality)
            ) { editing = .bonusPunctuality }
            PolicyRow(
                title: PolicyField.bonusBilling.title,
                detail: "Las 4 semanas del mes deben alcanzar la meta",
                value: display(.bonusBilling)
            ) { editing = .bonusBilling }
            PolicyRow(
                title: PolicyField.bonusCare.title,
                detail: "Se pierde con un reporte de daño o limpieza",
                value: display(.bonusCare)
            ) { editing = .bonusCare }
            PolicyRow(
                title: "Bono de calidad en el servicio",
                detail: "Lo define la plataforma; entra con la integración de Uber",
                value: "API",
                isEditable: false
            )

            Text("Al mover un monto cambia para toda la red desde el siguiente corte y queda versionado en la bitácora. Gerencia, supervisión y reclutamiento solo leen estos números.")
                .font(.caption2)
                .foregroundStyle(Palette.textMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .panel()
    }

    /// Cash is not an authorized way to charge, but when it happens the money has to
    /// land somewhere traceable. That account is written here and nowhere else.
    private var cashSection: some View {
        let account = national.cashAccount
        return VStack(alignment: .leading, spacing: 10) {
            SupSectionHeader(
                title: "Cuenta para depósitos en efectivo",
                subtitle: "Versión \(account.version) · \(Fmt.dateShort(account.updatedAt))"
            )

            NoticeBanner(
                symbol: "banknote.fill",
                title: "El cobro en efectivo sigue prohibido",
                message: "Esta cuenta no autoriza el efectivo: solo da destino al dinero que un conductor recibió en una emergencia. Él deposita el mismo día y el gerente de su estación recibe el aviso con el comprobante.",
                tone: .amber
            )

            PolicyRow(title: "Banco", detail: "Institución receptora", value: account.bank) {
                isEditingCashAccount = true
            }
            PolicyRow(title: "Titular", detail: "Razón social de la red", value: account.holder, isEditable: false)
            PolicyRow(title: "CLABE", detail: "Dato que el conductor da en la tienda", value: account.readableClabe) {
                isEditingCashAccount = true
            }
            PolicyRow(title: "Referencia", detail: "Concepto obligatorio del depósito", value: account.reference) {
                isEditingCashAccount = true
            }

            Text("Al publicarla cambia en la app de todos los conductores de la red y queda versionada en la bitácora.")
                .font(.caption2)
                .foregroundStyle(Palette.textMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .id(cashVersion)
        .padding(16)
        .panel()
    }

    private var creditSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SupSectionHeader(
                title: "Programa de crédito",
                subtitle: "\(CreditProgram.vehicleModel) · sin enganche"
            )
            PolicyRow(
                title: PolicyField.creditWeekly.title,
                detail: "Descuento vía nómina de los contratos nuevos",
                value: display(.creditWeekly)
            ) { editing = .creditWeekly }
            PolicyRow(
                title: "Plazo",
                detail: "Abonos semanales del contrato",
                value: "\(policy.creditTermWeeks)",
                isEditable: false
            )
            PolicyRow(
                title: "Entrega de la unidad",
                detail: "Mes en que el conductor recibe el vehículo",
                value: "Mes \(policy.creditDeliveryMonth)",
                isEditable: false
            )
        }
        .padding(16)
        .panel()
    }

    private var structureSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SupSectionHeader(title: "Estructura", subtitle: "La aritmética que sostiene la red")
            PolicyRow(
                title: "Conductores por unidad",
                detail: "Matutino y vespertino, entre semana y fin de semana",
                value: "\(policy.driversPerVehicle)",
                isEditable: false
            )
            PolicyRow(
                title: PolicyField.maxVehicles.title,
                detail: "Techo de diseño, no la flotilla instalada",
                value: display(.maxVehicles)
            ) { editing = .maxVehicles }
            PolicyRow(
                title: "Plantilla máxima por estación",
                detail: "Resultado de \(policy.maxVehiclesPerStation) unidades × \(policy.driversPerVehicle) turnos",
                value: "\(policy.maxVehiclesPerStation * policy.driversPerVehicle)",
                isEditable: false
            )
        }
        .padding(16)
        .panel()
    }

    private var logSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SupSectionHeader(
                title: "Historial de cambios",
                subtitle: "Ninguna regla se mueve en silencio"
            )
            if national.policyLog.isEmpty {
                Text("El libro conserva los valores con los que arrancó la red.")
                    .font(.footnote)
                    .foregroundStyle(Palette.textMuted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .panelFlat()
            } else {
                ForEach(national.policyLog) { change in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 8) {
                            Text(change.previousValue)
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(Palette.textMuted)
                                .strikethrough()
                            Image(systemName: "arrow.right")
                                .font(.system(size: 9, weight: .black))
                                .foregroundStyle(Palette.textMuted)
                            Text(change.newValue)
                                .font(.system(size: 12, weight: .black))
                                .foregroundStyle(NatTone.accent)
                            Spacer(minLength: 0)
                            RelativeTime(date: change.changedAt)
                                .font(.system(size: 10))
                                .foregroundStyle(Palette.textMuted)
                        }
                        Text(change.note.isEmpty ? change.field : change.note)
                            .font(.system(size: 11))
                            .foregroundStyle(Palette.textMuted)
                            .multilineTextAlignment(.leading)
                        Text("Autorizó \(change.changedBy)")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Palette.textMuted)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .panelFlat()
                }
            }
        }
    }

    private var restoreButton: some View {
        Button("Restaurar valores de origen") {
            national.restorePolicyDefaults()
        }
        .font(.system(.caption, weight: .bold))
        .foregroundStyle(Palette.textMuted)
    }
}

// MARK: - Editor

/// Editing one rule always shows what it breaks downstream before it is signed.
struct PolicyEditorView: View {
    let national: NationalStore
    let title: String
    let consequence: String
    let key: String
    let range: ClosedRange<Int>
    let step: Int
    let isMoney: Bool
    let initialValue: Int

    @Environment(\.dismiss) private var dismiss
    @State private var value: Int = 0
    @State private var note: String = ""

    var body: some View {
        NavigationStack {
            ZStack {
                NationalBackground()
                ScrollView {
                    VStack(spacing: 14) {
                        valueCard
                        consequenceCard
                        noteCard
                        BigButton(
                            title: "Aplicar a toda la red",
                            symbol: "checkmark.seal.fill",
                            isEnabled: value != initialValue,
                            action: apply
                        )
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 6)
                    .padding(.bottom, 34)
                }
                .scrollIndicators(.hidden)
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Palette.canvas, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancelar") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
        .onAppear { value = initialValue }
    }

    private var valueCard: some View {
        VStack(spacing: 14) {
            Text(isMoney ? Fmt.mxn(value) : "\(value)")
                .font(.system(size: 44, weight: .black, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(NatTone.accent)
                .minimumScaleFactor(0.5)
                .lineLimit(1)
                .contentTransition(.numericText())
                .animation(.smooth(duration: 0.3), value: value)

            Text(value == initialValue
                ? "Valor vigente"
                : "Antes: \(isMoney ? Fmt.mxn(initialValue) : "\(initialValue)")")
                .font(.caption2)
                .foregroundStyle(Palette.textMuted)

            HStack(spacing: 12) {
                stepButton(symbol: "minus", delta: -step)
                Slider(
                    value: Binding(
                        get: { Double(value) },
                        set: { value = Int(($0 / Double(step)).rounded()) * step }
                    ),
                    in: Double(range.lowerBound)...Double(range.upperBound)
                )
                .tint(NatTone.accent)
                stepButton(symbol: "plus", delta: step)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity)
        .panel()
    }

    private func stepButton(symbol: String, delta: Int) -> some View {
        Button {
            value = min(range.upperBound, max(range.lowerBound, value + delta))
        } label: {
            Image(systemName: symbol)
                .font(.system(.footnote, weight: .black))
                .foregroundStyle(Palette.canvas)
                .frame(width: 40, height: 40)
                .background(NatTone.accent, in: .circle)
        }
        .buttonStyle(.plain)
    }

    private var consequenceCard: some View {
        NoticeBanner(
            symbol: "arrow.triangle.branch",
            title: "Qué cambia en la operación",
            message: consequence,
            tone: .info
        )
    }

    private var noteCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            CapsLabel(text: "Motivo del cambio")
            TextField("Queda en el historial de la red", text: $note, axis: .vertical)
                .font(.system(.footnote, weight: .semibold))
                .lineLimit(2...4)
                .padding(12)
                .panelFlat(cornerRadius: 14)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .panel()
    }

    private func apply() {
        let newValue = value
        national.updatePolicy(field: key, note: note) { book in
            switch key {
            case "weekdayHourlyMxn": book.weekdayHourlyMxn = newValue
            case "weekdayDailyMxn": book.weekdayDailyMxn = newValue
            case "weekendHourlyMxn": book.weekendHourlyMxn = newValue
            case "weekendDailyMxn": book.weekendDailyMxn = newValue
            case "tripsPerDay": book.tripsPerDay = newValue
            case "graceMinutes": book.graceMinutes = newValue
            case "minimumBatteryPct": book.minimumBatteryPct = newValue
            case "inspectionPhotos": book.inspectionPhotos = newValue
            case "maxVehiclesPerStation": book.maxVehiclesPerStation = newValue
            case "bonusPunctualityMxn": book.bonusPunctualityMxn = newValue
            case "bonusBillingMxn": book.bonusBillingMxn = newValue
            case "bonusCareMxn": book.bonusCareMxn = newValue
            case "creditWeeklyMxn": book.creditWeeklyMxn = newValue
            default: break
            }
        }
        dismiss()
    }
}
