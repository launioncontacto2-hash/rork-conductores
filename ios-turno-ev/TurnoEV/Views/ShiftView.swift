import SwiftUI

/// Main screen: driver identity, assigned vehicle, shift clock and live metrics.
///
/// The clock is live again, but it no longer drives the page. The composition depends on
/// `ShiftPhase` — a handful of booleans that change twice a day — while the hour itself is
/// read inside the few leaves that display it, through `TimeScope`. Nothing that ticks can
/// reach the `ScrollView`, the `EditorStack` or the navigation stack.
struct ShiftView: View {
    @Environment(FleetStore.self) private var store

    @State private var route: ShiftRoute?
    @State private var areNoticesPresented: Bool = false
    @State private var isSigningOutPresented: Bool = false

    /// Structural state of the screen. Written only from the resolvers below, never from
    /// `body`. `nil` until the first resolution lands.
    @State private var phase: ShiftPhase?

    private enum ShiftRoute: Hashable, Identifiable {
        case start
        case incident
        case finish

        var id: Self { self }
    }

    /// The phase the screen is drawn against.
    ///
    /// The fallback is a pure computation, not a state write: it gives the very first
    /// paint a correct arrangement instead of a placeholder frame, and `AppClock` is a
    /// static enum, so reading it here registers no dependency on the clock.
    private var currentPhase: ShiftPhase {
        phase ?? resolvedPhase(at: AppClock.now())
    }

    var body: some View {
        let phase = currentPhase

        return NavigationStack {
            ZStack {
                StationBackground()

                ScrollView {
                    VStack(spacing: 26) {
                        EditorStack(screen: .driverShift, blocks: blocks(phase: phase), sample: sample)
                        accountSection
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 28)
                }
            }
            .background(phaseTicker)
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
            // Deliberately one question with two answers. Signing out destroys nothing:
            // the operational state stays written under the key of whoever is leaving, so
            // there is nothing to warn about here beyond leaving.
            .confirmationDialog(
                "Cerrar sesión",
                isPresented: $isSigningOutPresented,
                titleVisibility: .visible
            ) {
                Button("Cerrar sesión", role: .destructive) {
                    // The single implementation, the same one `SessionMenuButton` calls. A
                    // second one would be a second set of rules about what a sign-out clears.
                    store.signOut()
                }
                Button("Cancelar", role: .cancel) {}
            } message: {
                Text("¿Quieres salir de esta cuenta?")
            }
            .onAppear {
                store.reloadAssignment()
                updatePhase()
            }
            // Starting, finishing or reporting can change the state of the shift the
            // instant the sheet closes, well before the next minute arrives.
            .fullScreenCover(item: $route, onDismiss: updatePhase) { destination in
                switch destination {
                case .start: StartShiftView()
                case .incident: IncidentView()
                case .finish: FinishShiftView()
                }
            }
        }
        .editorScreen(.driverShift)
    }

    // MARK: - Phase

    /// Invisible heartbeat of the composition.
    ///
    /// A leaf of zero size whose only job is to hear the minute — and, through
    /// `TimeScope`, any discontinuous jump of the clock — and hand it to the resolver. The
    /// dependency is registered inside this leaf, so the cadence cannot invalidate the
    /// page: it can only run a comparison that usually decides nothing changed.
    private var phaseTicker: some View {
        TimeScope(.minute) { _ in
            Color.clear
                .frame(width: 0, height: 0)
                .onChange(of: ClockBeat.shared.minute, initial: true) { _, _ in
                    updatePhase()
                }
        }
    }

    /// Pure derivation. No state is written and no dependency is registered.
    private func resolvedPhase(at now: Date) -> ShiftPhase {
        ShiftPhase.resolve(
            driver: store.driver,
            activeShift: store.activeShift,
            lateDebtMinutes: store.weeklyLateDebt(reference: now),
            now: now
        )
    }

    /// Recomputes the phase and publishes it only if the screen really became a different
    /// screen. Called from appearance, from the minute heartbeat and after any action that
    /// can change the shift; never from `body`.
    private func updatePhase() {
        let resolved = resolvedPhase(at: AppClock.now())
        guard resolved != phase else { return }
        phase = resolved
    }

    // MARK: - Editable layout

    /// What this screen is made of, declared once so the visual editor can reorder,
    /// resize, hide or restyle it. The hero and the quick actions carry the shift and the
    /// emergency report, so they are marked critical: they can be restyled, never removed.
    ///
    /// It takes a `ShiftPhase`, never a `Date`. That is the whole point: the arrangement of
    /// blocks changes when the shift structurally changes, not when a second passes.
    private func blocks(phase: ShiftPhase) -> [EditorBlock] {
        var blocks: [EditorBlock] = [
            .custom("shift.header", "Identidad del conductor", kind: .card) {
                driverHeader
            },
            .custom("shift.hero", "Reloj y acciones del turno", kind: .card, isCritical: true) {
                shiftHero(phase: phase)
            },
        ]

        if phase.isActive, phase.isPastClose {
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

        if let shift = store.activeShift, phase.isLate {
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

        if !phase.isActive, phase.isPaybackOpen, phase.hasLateDebt {
            blocks.append(
                .custom("shift.paybackNotice", "Ventana de pago de atraso", kind: .notice) {
                    paybackNotice
                }
            )
        }

        if phase.isActive {
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
    ///
    /// `AppClock.now()` is read directly and on purpose: this closure runs inside
    /// `EditorStack`, and a live reading here would hand the whole stack a dependency on
    /// the clock — exactly what this migration removes. It is a pure read, so the figures
    /// are correct on every pass without any of them causing one.
    private func sample(_ metric: EditorMetric) -> EditorMetricSample {
        let now = AppClock.now()
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

    // MARK: - Account

    /// The way out of the session, at the foot of the screen that already says whose
    /// session it is.
    ///
    /// It sits **outside** `EditorStack` on purpose. Everything inside that stack can be
    /// reordered, restyled or hidden from the visual editor, and a sign-out that a layout
    /// can hide is a sign-out that does not exist — which is the exact situation this
    /// change fixes. The identity is not repeated either: `driverHeader` already carries
    /// the photo, the name, the station and the employee number a few centimetres above.
    ///
    /// One control, one route. `SessionMenuButton` in the toolbar keeps calling the same
    /// `store.signOut()`; nothing here is a second door.
    private var accountSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            CapsLabel(text: "Cuenta")

            Button {
                isSigningOutPresented = true
            } label: {
                HStack(spacing: 14) {
                    Image(systemName: "rectangle.portrait.and.arrow.right")
                        .font(.system(.footnote, weight: .bold))
                        .foregroundStyle(Palette.danger)
                        .frame(width: 34, height: 34)
                        .background(Palette.danger.opacity(0.12), in: .rect(cornerRadius: 12))
                    Text("Cerrar sesión")
                        .font(.system(.subheadline, weight: .bold))
                        .foregroundStyle(Palette.danger)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 14)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .panel()
            .accessibilityLabel("Cerrar sesión")
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

    /// Late time owed this week. The figure moves with the week, so it is read at minute
    /// cadence inside this banner and nowhere else.
    private var paybackNotice: some View {
        TimeScope(.minute) { now in
            NoticeBanner(
                symbol: "timer",
                title: "Ventana de pago de atraso abierta (\(store.driver.slot.paybackWindowLabel))",
                message: "Debes \(store.weeklyLateDebt(reference: now)) min esta semana. Regístralo en Historial.",
                tone: .volt
            )
        }
    }

    private func shiftHero(phase: ShiftPhase) -> some View {
        let isActive = phase.isActive
        let canStart = phase.canStart

        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    CapsLabel(text: isActive ? "Turno en curso" : "Próximo turno")
                    Text("\(store.driver.slot.label) · \(store.driver.group.label)")
                        .font(.system(.title3, weight: .black))
                    // Only the date needs the clock here, and a date changes once a day.
                    TimeScope(.day) { now in
                        Text(Fmt.dateLong(now).capitalized)
                            .font(.caption)
                            .foregroundStyle(Palette.textMuted)
                    }
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

                // The bar measures a nine-hour block: a minute is the finest step that can
                // move it visibly.
                TimeScope(.minute) { now in
                    ProgressTrack(value: Double(store.elapsedSeconds(at: now)) / 60, goal: 9 * 60)
                }
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

                Text(windowCopy(phase: phase))
                    .font(.footnote)
                    .foregroundStyle(Palette.textMuted)
                    .padding(.top, 6)

                BigButton(
                    title: "Iniciar turno",
                    symbol: "bolt.car.fill",
                    isEnabled: canStart && store.hasAssignedUnit && store.canRunShiftCycle
                ) {
                    route = .start
                }
                .padding(.top, 16)

                // Two different blockers, never the same sentence. Missing a unit is
                // something the supervisor fixes; a missing connection is not, and
                // telling a driver who *has* a unit that they do not is how someone
                // spends a morning chasing an assignment that already exists.
                if !store.hasAssignedUnit {
                    Text("Tu supervisor aún no te asigna unidad.")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Palette.amber)
                        .padding(.top, 8)
                } else if !store.canRunShiftCycle {
                    VStack(spacing: 4) {
                        Text("Tienes unidad asignada.")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Palette.volt)
                        Text("El inicio de turno aún requiere conexión con el sistema operativo de tu estación.")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Palette.amber)
                            .multilineTextAlignment(.center)
                    }
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
    ///
    /// Reads the window out of the phase. Those boundaries change by the day, so the
    /// sentence has no reason to be rebuilt by the passing of time.
    private func windowCopy(phase: ShiftPhase) -> String {
        switch phase.window {
        case .open:
            return "Ventana abierta. Cierre de jornada a las \(Fmt.clock(phase.closesAt)). Tolerancia de 10 minutos después de la hora programada."
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

/// The only thing on the shift screen that has to tick once per second.
///
/// The `TimeScope` sits around the reading and nothing else, so the second hand invalidates
/// one `Text` — not the hero, not the card, not the stack, not the page.
private struct ShiftStopwatch: View {
    let store: FleetStore

    var body: some View {
        TimeScope(.second) { now in
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
