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
    @State private var isPickerPresented: Bool = false
    @State private var tick: Int = 0

    private var speed: SimulationSpeed { SimulationClock.speed }

    var body: some View {
        NavigationStack {
            ZStack {
                StationBackground()

                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        readings
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

    // MARK: - Readings

    private var readings: some View {
        // While the clock runs the panel has to breathe with it; paused it stays still.
        TimelineView(.periodic(from: .now, by: speed.isPaused ? 60 : 1)) { _ in
            VStack(spacing: 10) {
                HStack(spacing: 10) {
                    reading(
                        caption: "Hora real",
                        value: Fmt.clock(AppClock.realNow()),
                        tone: Palette.textMuted
                    )

                    // The hour itself is the control: tapping it jumps straight to any
                    // point of the simulation instead of pressing +1 h over and over.
                    Button {
                        pickedDay = store.now
                        pickedTime = store.now
                        isPickerPresented = true
                    } label: {
                        reading(
                            caption: "Hora de prueba",
                            value: Fmt.clock(store.now),
                            tone: Palette.amber,
                            isEditable: true
                        )
                    }
                    .buttonStyle(.plain)
                }

                HStack(spacing: 8) {
                    Image(systemName: "calendar")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Palette.textMuted)
                    Text("Fecha de prueba · \(Fmt.dateLong(store.now).capitalized)")
                        .font(.system(.footnote, weight: .semibold))
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
                pickedDay = store.now
                pickedTime = store.now
                isPickerPresented = true
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

                    DatePicker("Hora", selection: $pickedTime, displayedComponents: .hourAndMinute)
                        .datePickerStyle(.wheel)
                        .labelsHidden()

                    BigButton(title: "Aplicar al entorno de prueba", symbol: "checkmark.circle.fill") {
                        SimulationClock.set(SimulationClock.combine(day: pickedDay, time: pickedTime))
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

    /// Publishes the new hour so every module re-evaluates its rules without a refresh.
    private func publish() {
        store.syncSimulationClock()
        tick += 1
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
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
                Button {
                    guard canSwitch, mode != lab.mode else { return }
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
                .disabled(!canSwitch)
            }

            if !canSwitch {
                Text("Solo la Administración de Pruebas cambia el entorno. Tu sesión puede participar en la simulación, pero no encenderla ni apagarla.")
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
        lab.setMode(mode)
        // Production always runs on safe real time: any simulated hour is dropped.
        if mode == .production { SimulationClock.reset() }
        store.syncSimulationClock()
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        dismiss()
    }
}
