import SwiftUI
import UIKit

/// Controller of the logical time of the simulation. It replaces the old list of fixed
/// scenarios: the administrator moves the hour freely, minute by minute if he needs to,
/// and every rule of the app re-evaluates on the spot.
struct SimulationClockSheet: View {
    @Environment(FleetStore.self) private var store
    @Environment(LabStore.self) private var lab
    @Environment(\.dismiss) private var dismiss

    @State private var pickedDay: Date = Date()
    @State private var pickedTime: Date = Date()
    @State private var pickedSecond: Int = 0
    @State private var isPickerPresented: Bool = false

    /// Observable mirror of the clock. Reading the speed from here — instead of from the
    /// static `SimulationClock` — is what makes the selector highlight move the instant the
    /// pace changes, including when the change came from the other device.
    private var signal: ClockSignal { ClockSignal.shared }

    private var speed: SimulationSpeed { signal.speed }

    var body: some View {
        NavigationStack {
            ZStack {
                StationBackground()

                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        ClockReadingsPanel(onEditHour: openPicker)
                        steppers
                        speedPicker
                        configureButton
                        note
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 28)
                }
                .scrollIndicators(.hidden)
            }
            .navigationTitle("Reloj de prueba")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Listo") { dismiss() }
                }
            }
            .sheet(isPresented: $isPickerPresented) {
                datePicker
            }
        }
        .presentationDetents([.large])
        .presentationContentInteraction(.scrolls)
        .preferredColorScheme(.dark)
    }

    // MARK: - Steppers

    private var steppers: some View {
        VStack(alignment: .leading, spacing: 9) {
            CapsLabel(text: "Mover el tiempo")

            HStack(spacing: 7) {
                step("-1 h", seconds: -3600)
                step("-10 min", seconds: -600)
                step("-1 min", seconds: -60)
            }
            HStack(spacing: 7) {
                step("+1 min", seconds: 60)
                step("+10 min", seconds: 600)
                step("+1 h", seconds: 3600)
            }
            // Second-level nudges: standing exactly on 05:59:50 is what lets a boundary be
            // crossed on purpose instead of jumped over.
            HStack(spacing: 7) {
                step("-10 s", seconds: -10)
                step("+10 s", seconds: 10)
            }

            Text("Con el reloj pausado la hora solo cambia cuando la mueves aquí. Es el modo indicado para probar un límite exacto: 05:59 → 06:00 convierte un demorado en ausente y dispara la búsqueda de sustituto.")
                .font(.system(size: 10))
                .foregroundStyle(Palette.textMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(15)
        .frame(maxWidth: .infinity, alignment: .leading)
        .panel()
    }

    private func step(_ title: String, seconds: Int) -> some View {
        Button {
            SimulationClock.shift(seconds: seconds)
            publish()
        } label: {
            Text(title)
                .font(.system(.footnote, weight: .black))
                .monospacedDigit()
                .foregroundStyle(seconds < 0 ? Palette.info : Palette.volt)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(
                    (seconds < 0 ? Palette.info : Palette.volt).opacity(0.12),
                    in: .rect(cornerRadius: 14)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 14)
                        .stroke((seconds < 0 ? Palette.info : Palette.volt).opacity(0.35), lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Speed

    private var speedPicker: some View {
        VStack(alignment: .leading, spacing: 9) {
            CapsLabel(text: "Velocidad")

            HStack(spacing: 7) {
                ForEach(SimulationSpeed.allCases) { option in
                    Button {
                        SimulationClock.setSpeed(option)
                        publish()
                    } label: {
                        Text(option.label)
                            .font(.system(size: 11, weight: .black))
                            .foregroundStyle(speed == option ? Palette.canvas : Palette.textMuted)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(
                                speed == option ? Palette.amber : Palette.surfaceRaised,
                                in: .rect(cornerRadius: 12)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }

            Text(speed.detail)
                .font(.system(size: 10))
                .foregroundStyle(Palette.textMuted)
        }
        .padding(15)
        .frame(maxWidth: .infinity, alignment: .leading)
        .panel()
    }

    // MARK: - Exact configuration

    private var configureButton: some View {
        VStack(spacing: 9) {
            BigButton(title: "Configurar fecha y hora", symbol: "calendar.badge.clock", tone: .outline) {
                openPicker()
            }

            Button("Volver a la hora real") {
                SimulationClock.reset()
                publish()
            }
            .font(.system(.footnote, weight: .bold))
            .foregroundStyle(Palette.textMuted)
            .buttonStyle(.plain)
        }
    }

    private var datePicker: some View {
        NavigationStack {
            ZStack {
                StationBackground()

                VStack(spacing: 14) {
                    DatePicker("Fecha", selection: $pickedDay, displayedComponents: .date)
                        .datePickerStyle(.graphical)
                        .tint(Palette.amber)

                    // Hour and minute keep the system wheel; the second is its own wheel
                    // beside it, in this same sheet. The picker offers no seconds component,
                    // so without this an exact instant simply could not be entered.
                    HStack(spacing: 0) {
                        DatePicker("Hora", selection: $pickedTime, displayedComponents: .hourAndMinute)
                            .datePickerStyle(.wheel)
                            .labelsHidden()

                        Picker("Segundos", selection: $pickedSecond) {
                            ForEach(0..<60, id: \.self) { value in
                                Text(String(format: "%02d", value))
                                    .monospacedDigit()
                                    .tag(value)
                            }
                        }
                        .pickerStyle(.wheel)
                        .frame(width: 84)
                    }

                    HStack(spacing: 6) {
                        Text("SE APLICARÁ")
                            .font(.system(size: 9, weight: .black))
                            .tracking(0.8)
                            .foregroundStyle(Palette.textMuted)
                        Text(Fmt.clockSeconds(pendingInstant))
                            .font(.system(size: 16, weight: .black, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(Palette.amber)
                        Spacer(minLength: 0)
                    }

                    BigButton(title: "Aplicar al entorno de prueba", symbol: "checkmark.circle.fill") {
                        SimulationClock.set(pendingInstant)
                        publish()
                        isPickerPresented = false
                    }

                    Spacer(minLength: 0)
                }
                .padding(16)
            }
            .navigationTitle("Fecha y hora de prueba")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { isPickerPresented = false }
                }
            }
        }
        .presentationDetents([.large])
        .preferredColorScheme(.dark)
    }

    private var note: some View {
        VStack(spacing: 9) {
            Text("Esta hora gobierna todas las reglas del entorno de prueba en este dispositivo: turno, tolerancias, ausencias, metas y cortes. Retroceder el reloj no borra lo que ya ocurrió — las ausencias, búsquedas y asignaciones se conservan hasta que reinicies el escenario desde el laboratorio.")
                .font(.system(size: 10))
                .foregroundStyle(Palette.textMuted)
                .multilineTextAlignment(.center)

            // Said plainly, so no two-device test is run on a false assumption.
            syncNotice
            RealtimeDiagnosticPanel()
        }
        .frame(maxWidth: .infinity)
    }

    /// State of the shared clock, in one compact line.
    private var syncNotice: some View {
        let sync = SharedClockSync.shared
        let isShared = sync.status == .synced

        return HStack(alignment: .top, spacing: 7) {
            Circle()
                .fill(isShared ? Palette.volt : (sync.status == .connecting ? Palette.info : Palette.textMuted))
                .frame(width: 6, height: 6)
                .padding(.top, 3)

            VStack(alignment: .leading, spacing: 2) {
                Text(sync.status.label)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(isShared ? Palette.volt : Palette.textMuted)
                Text(isShared ? SharedSimulationClock.sharedNotice : SharedSimulationClock.pendingNotice)
                    .font(.system(size: 10))
                    .foregroundStyle(Palette.textMuted)
                    .fixedSize(horizontal: false, vertical: true)

                // A rejected write is said here, where the change was made — not only in
                // the laboratory diagnostic.
                if let error = sync.lastError {
                    Text(error)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Palette.amber)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 2)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(11)
        .background((isShared ? Palette.volt : Palette.info).opacity(0.08), in: .rect(cornerRadius: 13))
    }

    /// Instant the picker is currently describing, seconds included.
    private var pendingInstant: Date {
        SimulationClock.combine(day: pickedDay, time: pickedTime, second: pickedSecond)
    }

    private func openPicker() {
        let current = store.now
        pickedDay = current
        pickedTime = current
        pickedSecond = SimulationClock.second(of: current)
        isPickerPresented = true
    }

    /// Follow-up to a local change. It performs **no** write of its own: the single logical
    /// publication already happened inside `SimulationClock.save`, which handed the state to
    /// `SharedSimulationClock.publish` and from there to one RPC call. This only keeps the
    /// stored offset in step and confirms the tap.
    private func publish() {
        store.syncSimulationClock()
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
    }
}

// MARK: - Readings

/// The two hours, the date and the pace badge — the only part of the sheet that has to
/// follow the clock second by second.
///
/// The panel itself is static. Each reading registers its own dependency, at its own
/// cadence, inside its own `TimeScope`, so the passing of time repaints two numbers and a
/// date — never the panel, the scroll view, the steppers, the speed picker or the
/// diagnostic section.
///
/// Two mechanisms were tried here and both are gone. The original
/// `TimelineView(.periodic(from: .now, ...))` read `.now` inline, handing the schedule a
/// new origin on every body pass: an origin already in the past fires immediately, and the
/// immediate fire caused the next pass. Its replacement, a private `pulse` written by a
/// `.task` loop, was inert — the body never read it, so the write registered no dependency
/// and invalidated nothing. The panel only appeared to follow the clock because it is the
/// surface the commands are pressed on, and every command bumped `ClockSignal.generation`
/// through `store.now`.
private struct ClockReadingsPanel: View {
    let onEditHour: () -> Void

    private var signal: ClockSignal { ClockSignal.shared }

    /// Episodic, not periodic: the badge changes when the pace is changed, here or on
    /// another device, and at no other time.
    private var speed: SimulationSpeed { signal.speed }

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                // The wall clock, not the simulated one, so the instant is read straight
                // from `AppClock.realNow()`. The scope is here only to supply the cadence.
                TimeScope(.second) { _ in
                    reading(
                        caption: "Hora real",
                        value: Fmt.clockSeconds(AppClock.realNow()),
                        tone: Palette.textMuted
                    )
                }

                // The hour itself is the control: tapping it jumps straight to any
                // point of the simulation instead of pressing +1 h over and over.
                Button {
                    onEditHour()
                } label: {
                    TimeScope(.second) { now in
                        reading(
                            caption: "Hora de prueba",
                            // Always with seconds: a boundary test is decided in the last
                            // ten of them, and HH:mm hid exactly that.
                            value: Fmt.clockSeconds(now),
                            tone: Palette.amber,
                            isEditable: true
                        )
                    }
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 8) {
                Image(systemName: "calendar")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Palette.textMuted)
                // A date has no business hearing about seconds.
                TimeScope(.minute) { now in
                    Text("Fecha de prueba · \(Fmt.dateLong(now).capitalized)")
                        .font(.system(.footnote, weight: .semibold))
                }
                Spacer(minLength: 0)
                Text(speed.label.uppercased())
                    .font(.system(size: 9, weight: .black))
                    .tracking(0.8)
                    .foregroundStyle(speed.isPaused ? Palette.info : Palette.amber)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background((speed.isPaused ? Palette.info : Palette.amber).opacity(0.15), in: .capsule)
            }
        }
        .padding(15)
        .frame(maxWidth: .infinity, alignment: .leading)
        .panel()
    }

    private func reading(
        caption: String,
        value: String,
        tone: Color,
        isEditable: Bool = false
    ) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Text(caption.uppercased())
                    .font(.system(size: 9, weight: .black))
                    .tracking(0.8)
                    .foregroundStyle(Palette.textMuted)
                if isEditable {
                    Image(systemName: "pencil.circle.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(tone)
                }
                Spacer(minLength: 0)
            }
            Text(value)
                .font(.system(size: 30, weight: .black, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(tone)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .panelFlat(cornerRadius: 16)
        .overlay {
            if isEditable {
                RoundedRectangle(cornerRadius: 16).stroke(tone.opacity(0.45), lineWidth: 1)
            }
        }
    }
}

// MARK: - Diagnostic

/// End-to-end trace of the shared clock, visible during the two-device test.
///
/// It separates the two failures that look identical from the outside: `recibidos = 0`
/// means the UPDATE never reached this phone, while `recibidos > 0` with a stale reading
/// means it arrived and the interface did not redraw.
///
/// Kept as a leaf so the counters — and the view generation it still reports — invalidate
/// this box alone and never the sheet around it.
private struct RealtimeDiagnosticPanel: View {
    private var sync: SharedClockSync { SharedClockSync.shared }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                Text("DIAGNÓSTICO REALTIME")
                    .font(.system(size: 9, weight: .black))
                    .tracking(0.8)
                    .foregroundStyle(Palette.textMuted)
                Spacer(minLength: 0)
                Text(sync.isSubscribed ? "subscribed" : "disconnected")
                    .font(.system(size: 9, weight: .black))
                    .foregroundStyle(sync.isSubscribed ? Palette.volt : Palette.amber)
            }

            diagnosticLine("Canal", sync.channelState)
            diagnosticLine("Revisión aplicada", sync.revision == 0 ? "—" : "\(sync.revision)")
            diagnosticLine(
                "Revisión Realtime",
                sync.lastRemoteRevision == 0 ? "—" : "\(sync.lastRemoteRevision)"
            )
            diagnosticLine(
                "Último evento",
                sync.lastRemoteEventAt.map { Fmt.clockSeconds($0) } ?? "ninguno"
            )
            diagnosticLine(
                "Eventos recibidos / aplicados",
                "\(sync.remoteEventsReceived) / \(sync.remoteEventsApplied)"
            )
            diagnosticLine("Generación de vista", "\(ClockSignal.shared.generation)")
        }
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.surfaceRaised.opacity(0.5), in: .rect(cornerRadius: 13))
    }

    private func diagnosticLine(_ title: String, _ value: String) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.system(size: 10))
                .foregroundStyle(Palette.textMuted)
            Spacer(minLength: 4)
            Text(value)
                .font(.system(size: 10, weight: .bold))
                .monospacedDigit()
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }
}

// MARK: - Environment control

/// Global switch between Producción and Modo prueba. It never signs anybody out and never
/// moves the person off the screen they were on.
struct EnvironmentSheet: View {
    @Environment(FleetStore.self) private var store
    @Environment(LabStore.self) private var lab
    @Environment(\.dismiss) private var dismiss

    @State private var isLeavingTestPresented: Bool = false

    private var canSwitch: Bool { EnvironmentControl.canSwitchEnvironment(account: store.currentAccount) }

    /// The one-way valve. A session without laboratory rights cannot start a simulation,
    /// but it is never trapped inside one.
    private var canLeaveTest: Bool {
        EnvironmentControl.canLeaveTestEnvironment(isSignedIn: store.isAuthenticated, mode: lab.mode)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                StationBackground()

                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        modeCard

                        if lab.isTest {
                            roleSwitcher
                        }

                        Text("Cambiar de entorno no cierra tu sesión ni te saca de la ventana en la que estás. Producción y pruebas nunca comparten usuarios, vehículos, pagos, asistencias ni documentos.")
                            .font(.system(size: 10))
                            .foregroundStyle(Palette.textMuted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 28)
                }
                .scrollIndicators(.hidden)
            }
            .navigationTitle("Entorno")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Listo") { dismiss() }
                }
            }
            .confirmationDialog(
                "Salir de Modo prueba",
                isPresented: $isLeavingTestPresented,
                titleVisibility: .visible
            ) {
                Button("Ir a Producción") { apply(.production) }
                Button("Cancelar", role: .cancel) {}
            } message: {
                Text(EnvironmentControl.leavingTestNotice)
            }
        }
        .presentationDetents([.medium, .large])
        .presentationContentInteraction(.scrolls)
        .preferredColorScheme(.dark)
    }

    private var modeCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            CapsLabel(text: "Entorno activo")

            ForEach(LabMode.allCases) { mode in
                let isAdoptable = EnvironmentControl.canAdopt(
                    mode: mode,
                    account: store.currentAccount,
                    isSignedIn: store.isAuthenticated,
                    current: lab.mode
                )
                Button {
                    guard isAdoptable, mode != lab.mode else { return }
                    if mode == .production {
                        isLeavingTestPresented = true
                    } else {
                        apply(mode)
                    }
                } label: {
                    HStack(spacing: 11) {
                        Image(systemName: mode.symbol)
                            .font(.system(.footnote, weight: .bold))
                            .foregroundStyle(mode == .test ? Palette.amber : Palette.volt)
                            .frame(width: 34, height: 34)
                            .background(
                                (mode == .test ? Palette.amber : Palette.volt).opacity(0.13),
                                in: .rect(cornerRadius: 12)
                            )

                        VStack(alignment: .leading, spacing: 2) {
                            Text(mode.label)
                                .font(.system(.subheadline, weight: .black))
                            Text(mode.detail)
                                .font(.system(size: 10))
                                .foregroundStyle(Palette.textMuted)
                                .multilineTextAlignment(.leading)
                        }

                        Spacer(minLength: 4)

                        if lab.mode == mode {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(.footnote, weight: .bold))
                                .foregroundStyle(mode == .test ? Palette.amber : Palette.volt)
                        }
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .panelFlat(cornerRadius: 16)
                }
                .buttonStyle(.plain)
                .disabled(!isAdoptable)
            }

            if !canSwitch {
                Text(
                    canLeaveTest
                        ? "Solo la Administración de Pruebas enciende una simulación. Salir de ella y volver a Producción sí está en tus manos, y no cierra tu sesión."
                        : "Solo la Administración de Pruebas cambia el entorno. Tu sesión puede participar en la simulación, pero no encenderla."
                )
                .font(.system(size: 10))
                .foregroundStyle(Palette.textMuted)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(15)
        .frame(maxWidth: .infinity, alignment: .leading)
        .panel()
    }

    /// Reuses the existing credentials of the environment so a role can be checked without
    /// restarting the simulation: same station, same hour, same vehicles, same events.
    private var roleSwitcher: some View {
        let accounts = StaffDirectory.accounts.filter {
            $0.role != .lab && $0.status == .active
        }

        return VStack(alignment: .leading, spacing: 9) {
            CapsLabel(text: "Ver como…")

            if accounts.isEmpty {
                Text("El entorno de pruebas todavía no tiene credenciales. Créalas en el laboratorio.")
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.textMuted)
            } else {
                ForEach(accounts.prefix(8)) { account in
                    Button {
                        store.signIn(account: account, method: .credentials)
                        dismiss()
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: account.role.symbol)
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(account.role.accent)
                                .frame(width: 28, height: 28)
                                .background(account.role.accent.opacity(0.13), in: .rect(cornerRadius: 10))

                            VStack(alignment: .leading, spacing: 1) {
                                Text(account.name)
                                    .font(.system(.footnote, weight: .bold))
                                    .lineLimit(1)
                                Text(account.role.label)
                                    .font(.system(size: 10))
                                    .foregroundStyle(Palette.textMuted)
                            }

                            Spacer(minLength: 4)

                            if store.currentAccount?.id == account.id {
                                Text("ACTUAL")
                                    .font(.system(size: 8, weight: .black))
                                    .foregroundStyle(Palette.volt)
                            } else {
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(Palette.textMuted)
                            }
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .panelFlat(cornerRadius: 14)
                    }
                    .buttonStyle(.plain)
                }
            }

            Text("Cambiar de rol no reinicia la simulación: la hora, la estación y los eventos siguen exactamente donde estaban.")
                .font(.system(size: 10))
                .foregroundStyle(Palette.textMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(15)
        .frame(maxWidth: .infinity, alignment: .leading)
        .panel()
    }

    private func apply(_ mode: LabMode) {
        if mode == .production {
            // One exit, shared with the account menu, so both routes leave the simulation
            // in exactly the same state.
            lab.exitTestEnvironment()
        } else {
            lab.setMode(mode)
            SharedClockSync.shared.update(isTest: true)
            store.syncSimulationClock()
        }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        dismiss()
    }
}
