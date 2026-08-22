import SwiftUI

/// Weekly money and trip goals, compared against the driver's live performance.
struct GoalsView: View {
    @Environment(FleetStore.self) private var store

    @State private var isIncomePresented: Bool = false

    var body: some View {
        NavigationStack {
            ZStack {
                StationBackground()

                TimelineView(.periodic(from: .now, by: 30)) { _ in
                    let now = store.now
                    let goals = store.goals
                    let earnedToday = store.earnedToday(reference: now)
                    let earnedWeek = store.earnedThisWeek(reference: now)
                    let tripsToday = store.tripsToday(reference: now)
                    let missingToday = max(0, goals.dailyMxn - earnedToday)
                    let missingTrips = max(0, goals.tripsPerDay - tripsToday)

                    ScrollView {
                        EditorStack(
                            screen: .driverGoals,
                            blocks: blocks(
                                goals: goals,
                                earnedToday: earnedToday,
                                earnedWeek: earnedWeek,
                                tripsToday: tripsToday,
                                missingToday: missingToday,
                                missingTrips: missingTrips,
                                now: now
                            ),
                            sample: { metric in metricSample(metric, now: now) }
                        )
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                        .padding(.bottom, 28)
                    }
                }
            }
            .navigationTitle("Metas")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    SessionMenuButton()
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Text("\(store.driver.group.label) · \(store.driver.slot.label)")
                        .font(.system(.caption2, weight: .semibold))
                        .foregroundStyle(Palette.textMuted)
                }
            }
            .fullScreenCover(isPresented: $isIncomePresented) {
                IncomeView()
            }
        }
        .editorScreen(.driverGoals)
    }

    // MARK: - Editable layout

    /// What this screen is made of, declared once so the visual editor can rearrange it
    /// without the screen knowing anything about the editor.
    private func blocks(
        goals: ShiftRules.Goals,
        earnedToday: Int,
        earnedWeek: Int,
        tripsToday: Int,
        missingToday: Int,
        missingTrips: Int,
        now: Date
    ) -> [EditorBlock] {
        let days = store.weeklyEarningsByDay(reference: now)

        return [
            .custom("goals.ring", "Meta del día", kind: .progress) {
                dailyRing(earnedToday: earnedToday, goals: goals, missingToday: missingToday, now: now)
            },
            .custom("goals.telemetry", "Recorrido y batería del turno", kind: .kpi) {
                shiftTelemetrySection(now: now)
            },
            .chart(
                "goals.weekly",
                "Avance semanal",
                subtitle: "\(Fmt.mxn(earnedWeek)) de \(Fmt.mxn(goals.weeklyMxn))",
                series: EditorSeries(
                    points: days.map { EditorPoint($0.label, Double($0.amount), isHighlighted: $0.isToday) },
                    goal: Double(goals.dailyMxn),
                    totalGoal: Double(goals.weeklyMxn),
                    isComposition: true,
                    unit: .money
                )
            ),
            .custom("goals.trips", "Viajes de hoy", kind: .progress) {
                tripsSection(tripsToday: tripsToday, missingTrips: missingTrips, goals: goals)
            },
            .custom("goals.late", "Atrasos de la semana", kind: .notice) {
                lateSection(now: now)
            },
        ]
    }

    /// Real value behind any metric of the controlled list, so a card the administrator
    /// re-pointed still shows a true number.
    private func metricSample(_ metric: EditorMetric, now: Date) -> EditorMetricSample {
        let goals = store.goals
        switch metric {
        case .earningsToday:
            let earned = store.earnedToday(reference: now)
            return EditorMetricSample(
                value: Fmt.mxn(earned),
                caption: "de \(Fmt.mxn(goals.dailyMxn)) hoy",
                progress: Double(earned) / Double(max(1, goals.dailyMxn))
            )
        case .earningsWeek:
            let earned = store.earnedThisWeek(reference: now)
            return EditorMetricSample(
                value: Fmt.mxn(earned),
                caption: "de \(Fmt.mxn(goals.weeklyMxn)) esta semana",
                progress: Double(earned) / Double(max(1, goals.weeklyMxn))
            )
        case .tripsToday:
            let trips = store.tripsToday(reference: now)
            return EditorMetricSample(
                value: "\(trips)",
                caption: "de \(goals.tripsPerDay) viajes",
                progress: Double(trips) / Double(max(1, goals.tripsPerDay))
            )
        case .kmToday:
            let km = store.history
                .filter { ShiftRules.isSameDay($0.startedAt, now) }
                .reduce(0) { $0 + $1.kmDriven }
                + (store.activeShift != nil ? store.estimatedKmDriven(at: now) : 0)
            return EditorMetricSample(value: Fmt.km(km), caption: "recorridos hoy")
        case .batteryStart:
            let value = store.activeShift?.startBatteryPct
            return EditorMetricSample(value: value.map { "\($0)%" } ?? "—", caption: "lectura de salida")
        case .batteryEnd:
            let value = store.history.first { ShiftRules.isSameDay($0.startedAt, now) }?.endBatteryPct
            return EditorMetricSample(value: value.map { "\($0)%" } ?? "—", caption: "lectura de entrega")
        case .lateMinutes:
            let debt = store.weeklyLateDebt(reference: now)
            return EditorMetricSample(value: "\(debt) min", caption: "pendientes esta semana")
        case .bonusPayable:
            let payable = store.bonusPayableMxn(reference: now)
            return EditorMetricSample(
                value: Fmt.mxn(payable),
                caption: "de \(Fmt.mxn(store.bonusTotalMxn())) posibles",
                progress: Double(payable) / Double(max(1, store.bonusTotalMxn()))
            )
        default:
            return EditorMetricSample(value: "—", caption: "sin dato en esta interfaz")
        }
    }

    private func dailyRing(
        earnedToday: Int,
        goals: ShiftRules.Goals,
        missingToday: Int,
        now: Date
    ) -> some View {
        VStack(spacing: 14) {
            RingGauge(
                value: Double(earnedToday),
                goal: Double(goals.dailyMxn),
                headline: Fmt.mxn(earnedToday),
                caption: "de \(Fmt.mxn(goals.dailyMxn)) hoy"
            )

            Label(
                missingToday == 0
                    ? "Meta del día cumplida"
                    : "Faltan \(Fmt.mxn(missingToday)) para la meta del día",
                systemImage: missingToday == 0 ? "checkmark.seal.fill" : "chart.line.uptrend.xyaxis"
            )
            .font(.system(.subheadline, weight: .bold))
            .foregroundStyle(missingToday == 0 ? Palette.volt : Palette.amber)

            if let shift = store.activeShift {
                let paceTarget = ShiftRules.paceTargetMxn(
                    group: shift.group,
                    elapsedMinutes: Double(store.elapsedSeconds(at: now)) / 60
                )
                let delta = earnedToday - paceTarget

                VStack(spacing: 8) {
                    HStack {
                        CapsLabel(text: "Ritmo por hora")
                        Spacer()
                        Text("\(delta >= 0 ? "+" : "−")\(Fmt.mxn(abs(delta))) vs objetivo")
                            .font(.system(.caption, weight: .bold))
                            .monospacedDigit()
                            .foregroundStyle(delta >= 0 ? Palette.volt : Palette.amber)
                    }
                    ProgressTrack(
                        value: Double(earnedToday),
                        goal: Double(goals.dailyMxn),
                        marker: Double(paceTarget)
                    )
                    Text("Objetivo acumulado \(Fmt.mxn(paceTarget)) · \(Fmt.mxn(goals.hourlyMxn)) por hora")
                        .font(.system(size: 10))
                        .foregroundStyle(Palette.textMuted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(12)
                .panelFlat()
            }
        }
        .padding(18)
        .panel()
    }

    /// What the unit did during the turn: distance covered and the two battery
    /// readings. While the turn is open the closing charge is still unknown; once it
    /// closes, the three numbers stay in the shift log for later analysis.
    private func shiftTelemetrySection(now: Date) -> some View {
        let active = store.activeShift
        let todayRecords = store.history.filter { ShiftRules.isSameDay($0.startedAt, now) }
        let closedToday = todayRecords.first
        let kmToday = todayRecords.reduce(0) { $0 + $1.kmDriven }
            + (active != nil ? store.estimatedKmDriven(at: now) : 0)

        let startBattery = active?.startBatteryPct ?? closedToday?.startBatteryPct
        let endBattery = active == nil ? closedToday?.endBatteryPct : nil
        let startOdometer = active?.startOdometerKm ?? closedToday?.startOdometerKm

        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Recorrido y batería del turno", systemImage: "gauge.with.dots.needle.bottom.50percent")
                    .font(.system(.caption, weight: .semibold))
                    .foregroundStyle(Palette.textMuted)
                Spacer()
                Text(active != nil ? "EN CURSO" : closedToday != nil ? "CERRADO HOY" : "SIN TURNO")
                    .font(.system(size: 9, weight: .black))
                    .tracking(1)
                    .foregroundStyle(active != nil ? Palette.volt : Palette.textMuted)
            }

            // Three readings side by side: at a glance, without scrolling and without
            // a single label breaking into two lines.
            HStack(spacing: 8) {
                ReadingTile(
                    label: "Km",
                    value: Fmt.km(kmToday),
                    hint: startOdometer.map { "Desde \(Fmt.km($0))" } ?? "Sin lectura",
                    tone: Palette.volt
                )
                ReadingTile(
                    label: "Bat. inicio",
                    value: startBattery.map { "\($0)%" } ?? "—",
                    hint: "Salida",
                    tone: .primary
                )
                ReadingTile(
                    label: "Bat. fin",
                    value: endBattery.map { "\($0)%" } ?? (active != nil ? "···" : "—"),
                    hint: endBattery == nil && active != nil ? "En curso" : "Entrega",
                    tone: endBattery == nil ? .primary : Palette.volt
                )
            }

            if let startBattery, let endBattery {
                Text("Consumo del turno: \(max(0, startBattery - endBattery)) puntos de carga para \(Fmt.km(closedToday?.kmDriven ?? kmToday)).")
                    .font(.caption2)
                    .foregroundStyle(Palette.textMuted)
            } else {
                Text("La carga de entrega se registra al finalizar el turno. Las tres lecturas quedan guardadas en tu historial para análisis posterior.")
                    .font(.caption2)
                    .foregroundStyle(Palette.textMuted)
            }

            BigButton(title: "Registrar ingreso", symbol: "banknote.fill", tone: .outline) {
                isIncomePresented = true
            }
        }
        .padding(18)
        .panel()
    }

    private func tripsSection(tripsToday: Int, missingTrips: Int, goals: ShiftRules.Goals) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Viajes de hoy", systemImage: "flag.checkered")
                    .font(.system(.caption, weight: .semibold))
                    .foregroundStyle(Palette.textMuted)
                Spacer()
                Text("\(tripsToday) / \(goals.tripsPerDay)")
                    .font(.system(.caption, weight: .bold))
                    .monospacedDigit()
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 7), spacing: 6) {
                ForEach(0..<goals.tripsPerDay, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 6)
                        .fill(index < tripsToday ? Palette.volt : Palette.surfaceRaised)
                        .frame(height: 26)
                }
            }

            Text(
                missingTrips == 0
                    ? "Meta de viajes cumplida. ¡Excelente ritmo!"
                    : "Faltan \(missingTrips) viajes para la meta. Recupéralos hoy o mañana."
            )
            .font(.caption2)
            .foregroundStyle(Palette.textMuted)
        }
        .padding(18)
        .panel()
    }

    private func lateSection(now: Date) -> some View {
        let debt = store.weeklyLateDebt(reference: now)
        return NoticeBanner(
            symbol: "timer",
            title: debt > 0 ? "Debes \(debt) minutos esta semana" : "Sin atrasos esta semana",
            message: "Ventana de pago \(store.driver.slot.paybackWindowLabel) · consulta la bitácora en Historial.",
            tone: debt > 0 ? .amber : .volt
        )
    }
}

#Preview {
    GoalsView()
        .environment(FleetStore())
        .preferredColorScheme(.dark)
}
