import SwiftUI

/// Main screen: driver identity, assigned vehicle, shift clock and live metrics.
struct ShiftView: View {
    @Environment(FleetStore.self) private var store

    @State private var route: ShiftRoute?
    @State private var areNoticesPresented: Bool = false

    /// Fixed origin of the periodic schedule.
    ///
    /// This used to be `.now`, read inline in `body`. That is a new `Date` on every body
    /// pass, so the `TimelineView` value changed on every pass, its schedule was rebuilt,
    /// and the rebuilt schedule started in the past — which makes it emit an entry
    /// immediately instead of in 30 s. The immediate entry re-rendered the content, and the
    /// graph never settled. Anchoring in `@State` fixes the origin for the lifetime of the
    /// view, so the schedule is a stable value and only fires on its real cadence.
    @State private var timelineAnchor: Date = .now

    private enum ShiftRoute: Hashable, Identifiable {
        case start
        case incident
        case finish

        var id: Self { self }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                StationBackground()

                // The screen refreshes on a slow beat: only the stopwatch needs a second
                // hand, and rebuilding the whole stack once per second churned every
                // image and gesture on the page.
                TimelineView(.periodic(from: timelineAnchor, by: 30)) { _ in
                    // Derived from the anchors, not from a minute offset: at x10 the offset
                    // grows while the simulation runs and the two stop agreeing.
                    let now = store.now

                    ScrollView {
                        EditorStack(screen: .driverShift, blocks: blocks(now: now), sample: sample)
                            .padding(.horizontal, 16)
                            .padding(.top, 8)
                            .padding(.bottom, 28)
                    }
                }
            }
            .navigationTitle("Turno")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    SessionMenuButton()
                }
                ToolbarItem(placement: .topBarTrailing) {
                    DemoClockButton()
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        areNoticesPresented = true
                    } label: {
                        Image(systemName: store.unreadNoticeCount > 0 ? "bell.badge.fill" : "bell.fill")
                            .foregroundStyle(store.unreadNoticeCount > 0 ? Palette.volt : Color.primary)
                    }
                    .accessibilityLabel("Avisos de la estación")
                }
            }
            .sheet(isPresented: $areNoticesPresented) {
                NoticesView()
            }
            .onAppear { store.reloadAssignment() }
            .fullScreenCover(item: $route) { destination in
                switch destination {
                case .start: StartShiftView()
                case .incident: IncidentView()
                case .finish: FinishShiftView()
                }
            }
        }
        .editorScreen(.driverShift)
    }

    // MARK: - Editable layout

    /// What this screen is made of, declared once so the visual editor can reorder,
    /// resize, hide or restyle it. The hero and the quick actions carry the shift and the
    /// emergency report, so they are marked critical: they can be restyled, never removed.
    private func blocks(now: Date) -> [EditorBlock] {
        var blocks: [EditorBlock] = [
            .custom("shift.header", "Identidad del conductor", kind: .card) {
                driverHeader
            },
            .custom("shift.hero", "Reloj y acciones del turno", kind: .card, isCritical: true) {
                shiftHero(now: now)
            },
        ]

        if store.activeShift != nil, ShiftRules.isPastClose(slot: store.driver.slot, now: now) {
            blocks.append(
                .custom("shift.closedNotice", "Aviso de jornada cerrada", kind: .notice, isCritical: true) {
                    NoticeBanner(
                        symbol: "exclamationmark.octagon.fill",
                        title: "Tu jornada ya cerró",
                        message: "Entrega la unidad y finaliza el turno para que se registren tus métricas.",
                        tone: .danger
                    )
                }
            )
        }

        if let shift = store.activeShift, shift.lateMinutes > 0 {
            blocks.append(
                .custom("shift.lateNotice", "Aviso de atraso", kind: .notice) {
                    NoticeBanner(
                        symbol: "exclamationmark.triangle.fill",
                        title: "\(Fmt.firstName(store.driver.name)), tienes un atraso de \(Fmt.lateText(shift.lateMinutes)) minutos.",
                        message: "Recupéralos mañana en tu ventana de \(store.driver.slot.paybackWindowLabel).",
                        tone: .amber
                    )
                }
            )
        }

        if store.activeShift == nil,
           ShiftRules.isPaybackWindow(driver: store.driver, now: now),
           store.weeklyLateDebt(reference: now) > 0 {
            blocks.append(
                .custom("shift.paybackNotice", "Ventana de pago de atraso", kind: .notice) {
                    NoticeBanner(
                        symbol: "timer",
                        title: "Ventana de pago de atraso abierta (\(store.driver.slot.paybackWindowLabel))",
                        message: "Debes \(store.weeklyLateDebt(reference: now)) min esta semana. Regístralo en Historial.",
                        tone: .volt
                    )
                }
            )
        }

        if store.activeShift != nil {
            blocks.append(
                .custom("shift.actions", "Acciones rápidas", kind: .button, isCritical: true) {
                    quickActions
                }
            )
        }

        return blocks
    }

    /// Real value behind any metric the editor can point a card at, so a duplicated or
    /// re-pointed indicator still shows a true number.
    private func sample(_ metric: EditorMetric) -> EditorMetricSample {
        let now = store.now
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
            return EditorMetricSample(value: Fmt.mxn(store.earnedThisWeek(reference: now)), caption: "esta semana")
        case .tripsToday:
            let trips = store.tripsToday(reference: now)
            return EditorMetricSample(
                value: "\(trips)",
                caption: "de \(goals.tripsPerDay) viajes",
                progress: Double(trips) / Double(max(1, goals.tripsPerDay))
            )
        case .kmToday:
            let km = store.activeShift != nil ? store.estimatedKmDriven(at: now) : 0
            return EditorMetricSample(value: Fmt.km(km), caption: "en el turno activo")
        case .batteryStart:
            return EditorMetricSample(
                value: store.activeShift.map { "\($0.startBatteryPct)%" } ?? "—",
                caption: "lectura de salida"
            )
        case .batteryEnd:
            let value = store.history.first { ShiftRules.isSameDay($0.startedAt, now) }?.endBatteryPct
            return EditorMetricSample(value: value.map { "\($0)%" } ?? "—", caption: "lectura de entrega")
        case .lateMinutes:
            return EditorMetricSample(value: "\(store.weeklyLateDebt(reference: now)) min", caption: "pendientes")
        case .bonusPayable:
            return EditorMetricSample(value: Fmt.mxn(store.bonusPayableMxn(reference: now)), caption: "por cobrar")
        default:
            return EditorMetricSample(value: "—", caption: "sin dato en esta interfaz")
        }
    }

    // MARK: - Sections

    private var driverHeader: some View {
        HStack(spacing: 12) {
            ZStack(alignment: .bottomTrailing) {
                Image(store.driver.photoAsset)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 56, height: 56)
                    .clipShape(.rect(cornerRadius: 18))
                    .overlay { RoundedRectangle(cornerRadius: 18).stroke(Palette.volt.opacity(0.5), lineWidth: 1) }

                if store.activeShift != nil {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 10, weight: .black))
                        .foregroundStyle(Palette.canvas)
                        .frame(width: 22, height: 22)
                        .background(Palette.volt, in: .circle)
                        .overlay { Circle().stroke(Palette.canvas, lineWidth: 2) }
                        .offset(x: 5, y: 5)
                }
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(store.driver.name)
                    .font(.system(.headline, weight: .black))
                    .lineLimit(1)
                HStack(spacing: 4) {
                    Image(systemName: "mappin.and.ellipse")
                        .font(.system(size: 10))
                    Text("\(store.driver.station) · \(store.driver.employeeNumber)")
                        .lineLimit(1)
                }
                .font(.caption2)
                .foregroundStyle(Palette.textMuted)
            }

            Spacer(minLength: 0)
        }
    }

    private func shiftHero(now: Date) -> some View {
        let isActive = store.activeShift != nil
        let canStart = ShiftRules.isCorrectShiftMoment(driver: store.driver, now: now)

        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    CapsLabel(text: isActive ? "Turno en curso" : "Próximo turno")
                    Text("\(store.driver.slot.label) · \(store.driver.group.label)")
                        .font(.system(.title3, weight: .black))
                    Text(Fmt.dateLong(now).capitalized)
                        .font(.caption)
                        .foregroundStyle(Palette.textMuted)
                }
                Spacer(minLength: 8)
                Text(isActive ? "ACTIVO" : canStart ? "PUEDES INICIAR" : "FUERA DE HORARIO")
                    .font(.system(size: 9, weight: .black))
                    .tracking(1.2)
                    .foregroundStyle(isActive ? Palette.volt : canStart ? Palette.info : Palette.textMuted)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background((isActive ? Palette.volt : canStart ? Palette.info : Color.white).opacity(0.13), in: .capsule)
            }

            if let shift = store.activeShift {
                let elapsed = store.elapsedSeconds(at: now)

                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 2) {
                        CapsLabel(text: "Tiempo transcurrido")
                        ShiftStopwatch(store: store)
                    }
                    Spacer(minLength: 8)
                    VStack(alignment: .trailing, spacing: 2) {
                        CapsLabel(text: "Inicio")
                        Text(Fmt.clock(shift.startedAt))
                            .font(.system(.title2, weight: .bold))
                            .monospacedDigit()
                        Text("Programado \(Fmt.clock(shift.scheduledStartAt))")
                            .font(.system(size: 10))
                            .foregroundStyle(Palette.textMuted)
                    }
                }
                .padding(.top, 18)

                ProgressTrack(value: Double(elapsed) / 60, goal: 9 * 60)
                    .padding(.top, 14)

                HStack {
                    Text("8 h efectivas + 1 h comida")
                    Spacer()
                    Text(store.driver.slot.rangeLabel)
                }
                .font(.system(size: 10))
                .foregroundStyle(Palette.textMuted)
                .padding(.top, 6)

                BigButton(title: "Finalizar turno", symbol: "checkmark.seal.fill", tone: .outline) {
                    route = .finish
                }
                .padding(.top, 16)
            } else {
                Text(store.driver.slot.rangeLabel)
                    .font(.system(size: 34, weight: .black))
                    .monospacedDigit()
                    .padding(.top, 16)

                Text(windowCopy(now: now))
                    .font(.footnote)
                    .foregroundStyle(Palette.textMuted)
                    .padding(.top, 6)

                BigButton(
                    title: "Iniciar turno",
                    symbol: "bolt.car.fill",
                    isEnabled: canStart && store.hasAssignedUnit
                ) {
                    route = .start
                }
                .padding(.top, 16)

                if !store.hasAssignedUnit {
                    Text("Tu supervisor aún no te asigna unidad.")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Palette.amber)
                        .padding(.top, 8)
                }
            }
        }
        .padding(18)
        .panel()
        .overlay(alignment: .topTrailing) {
            Circle()
                .fill(Palette.volt.opacity(0.12))
                .frame(width: 180, height: 180)
                .blur(radius: 60)
                .offset(x: 60, y: -80)
                .allowsHitTesting(false)
        }
        .clipShape(.rect(cornerRadius: 26))
    }

    /// Copy under the clock: when the block opens, when it closes for good.
    private func windowCopy(now: Date) -> String {
        switch ShiftRules.windowState(driver: store.driver, now: now) {
        case .open:
            return "Ventana abierta. Cierre de jornada a las \(Fmt.clock(store.startWindow.closesAt)). Tolerancia de 10 minutos después de la hora programada."
        case .early(let opensAt):
            return "Podrás iniciar tu turno a partir de las \(Fmt.clock(opensAt))."
        case .closed(let closedAt):
            return "Tu jornada cerró a las \(Fmt.clock(closedAt)). Notifica a tu supervisor si necesitas operar fuera de horario."
        case .wrongDay:
            return "Hoy no corresponde a tu grupo de \(store.driver.group.label.lowercased())."
        }
    }

    private var quickActions: some View {
        VStack(spacing: 12) {
            actionCard(title: "Reportar incidencia", symbol: "exclamationmark.triangle.fill", tint: Palette.danger) {
                route = .incident
            }

            Text("Kilómetros, batería, viajes e ingresos del turno se siguen en Metas. Puedes iniciar y finalizar varias veces dentro de tu jornada.")
                .font(.system(size: 10))
                .foregroundStyle(Palette.textMuted)
                .multilineTextAlignment(.center)
        }
    }

    private func actionCard(
        title: String,
        symbol: String,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: symbol)
                    .font(.title2)
                    .foregroundStyle(tint)
                Text(title)
                    .font(.system(.caption, weight: .bold))
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, minHeight: 92)
            .background(tint.opacity(0.1), in: .rect(cornerRadius: 18))
            .overlay { RoundedRectangle(cornerRadius: 18).stroke(tint.opacity(0.35), lineWidth: 1) }
        }
        .buttonStyle(.plain)
    }
}

/// The only thing on the shift screen that has to tick once per second. Keeping it in its
/// own view means the second hand never drags the rest of the page through a rebuild.
private struct ShiftStopwatch: View {
    let store: FleetStore

    /// Fixed origin, for the same reason as `ShiftView.timelineAnchor`.
    @State private var anchor: Date = .now

    var body: some View {
        TimelineView(.periodic(from: anchor, by: 1)) { _ in
            let now = store.now
            Text(Fmt.stopwatch(store.elapsedSeconds(at: now)))
                .font(.system(size: 42, weight: .black))
                .monospacedDigit()
                .foregroundStyle(Palette.volt)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
        }
    }
}

#Preview {
    ShiftView()
        .environment(FleetStore())
        .preferredColorScheme(.dark)
}
