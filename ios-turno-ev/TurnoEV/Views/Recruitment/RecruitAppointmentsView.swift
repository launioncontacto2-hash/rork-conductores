import SwiftUI
import UIKit

/// Interview agenda. Recruitment lives on appointments: an interview that nobody
/// confirms is a vacancy that stays open one more week.
struct RecruitAppointmentsView: View {
    let recruit: RecruitmentStore
    let header: RecruitHeader
    let onOpenProspect: (String) -> Void

    @State private var selected: Appointment?

    /// Instant the two counters of the summary are measured against. `.day`, matching the
    /// cadence of the lists they count.
    @State private var dayAnchor: Date = AppClock.now()

    var body: some View {
        ZStack {
            RecruitmentBackground()
            ScrollView {
                VStack(spacing: 14) {
                    header
                    summary
                    todaySection
                    upcomingSection
                    historySection
                }
                .padding(.horizontal, 18)
                .padding(.top, 6)
                .padding(.bottom, 34)
            }
            .scrollIndicators(.hidden)
        }
        .background {
            ClockAnchor(.day, date: $dayAnchor)
        }
        .sheet(item: $selected) { appointment in
            AppointmentDetailView(
                recruit: recruit,
                appointment: appointment,
                onOpenProspect: { id in
                    selected = nil
                    onOpenProspect(id)
                }
            )
        }
    }

    private var summary: some View {
        let metrics = recruit.recruiterMetrics(now: dayAnchor)
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                // "Próximas" is the caption of the list further down this same screen, and
                // that list is `upcoming` minus today. Without the same subtraction the two
                // disagreed by exactly the number of interviews left today, and the header
                // double-counted what the figure beside it already reported as "hoy".
                HeadlineFigure(
                    value: "\(recruit.todayAppointments(now: dayAnchor).count)",
                    caption: "Citas hoy",
                    tone: RecTone.accent,
                    detail: "\(recruit.upcomingAppointments(now: dayAnchor).filter { !$0.isToday(now: dayAnchor) }.count) próximas"
                )
                HeadlineFigure(
                    value: "\(Int((metrics.attendanceRate * 100).rounded())) %",
                    caption: "Asistencia",
                    tone: metrics.attendanceRate >= 0.7 ? RecTone.good : RecTone.warn,
                    detail: "\(metrics.noShowAppointments) inasistencias"
                )
            }
            Text("Un candidato que no asiste sale del proceso con motivo registrado; así se distingue una mala campaña de un mal horario.")
                .font(.system(size: 11))
                .foregroundStyle(Palette.textMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .panel()
    }

    private var todaySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Only the subtitle is a date; the heading beside it never moves.
            TimeScope(.day) { now in
                SupSectionHeader(title: "Hoy", subtitle: Fmt.dateLong(now), accent: RecTone.accent)
            }
            // Membership again: an appointment joins this list at logical midnight. The
            // scope covers the list, not the heading above it.
            TimeScope(.day) { now in
                let today = recruit.todayAppointments(now: now)
                if today.isEmpty {
                    RecEmptyState(
                        symbol: "calendar",
                        title: "Sin citas hoy",
                        message: "Programa entrevistas desde el expediente de cada candidato."
                    )
                } else {
                    ForEach(today) { appointment in
                        AppointmentRow(appointment: appointment) { selected = appointment }
                    }
                }
            }
        }
    }

    private var upcomingSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SupSectionHeader(title: "Próximas", subtitle: "Confirma un día antes", accent: RecTone.accent)
            UpcomingAppointmentsList(recruit: recruit) { selected = $0 }
        }
    }

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SupSectionHeader(title: "Historial", subtitle: "Asistencias e inasistencias", accent: RecTone.accent)
            AppointmentHistoryList(recruit: recruit) { selected = $0 }
        }
    }
}

/// Appointments already held or closed.
///
/// Membership again, and at a finer cadence than its neighbours: an appointment becomes
/// history at **its own hour**, not at midnight, so this list listens by the minute. The
/// scope covers the list alone — the `ScrollView`, the summary and the two sections above
/// stay outside. Declared exception to the leaf rule, on the same terms as
/// `UpcomingAppointmentsList`.
private struct AppointmentHistoryList: View {
    let recruit: RecruitmentStore
    let onSelect: (Appointment) -> Void

    var body: some View {
        TimeScope(.minute) { now in
            ForEach(Array(recruit.pastAppointments(now: now).prefix(10))) { appointment in
                AppointmentRow(appointment: appointment) { onSelect(appointment) }
            }
        }
    }
}

/// Appointments scheduled for a day that is not today.
///
/// The filter is `!isToday(now:)`, so a calendar rollover moves an appointment out of this
/// list and into "Hoy" above — the clock decides membership, not a label. The list is
/// therefore extracted into its own view and the scope wraps its whole content, at day
/// cadence because that is the unit the filter compares. The `ScrollView`, the header, the
/// summary and the history section stay outside. Declared exception to the leaf rule.
private struct UpcomingAppointmentsList: View {
    let recruit: RecruitmentStore
    let onSelect: (Appointment) -> Void

    var body: some View {
        TimeScope(.day) { now in
            let upcoming = recruit.upcomingAppointments(now: now).filter { !$0.isToday(now: now) }
            if upcoming.isEmpty {
                RecEmptyState(
                    symbol: "calendar.badge.plus",
                    title: "Agenda libre",
                    message: "No hay entrevistas programadas para los próximos días."
                )
            } else {
                ForEach(upcoming) { appointment in
                    AppointmentRow(appointment: appointment) { onSelect(appointment) }
                }
            }
        }
    }
}

// MARK: - Detail

struct AppointmentDetailView: View {
    let recruit: RecruitmentStore
    let appointment: Appointment
    let onOpenProspect: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var newDate: Date
    @State private var isRescheduling: Bool = false

    init(recruit: RecruitmentStore, appointment: Appointment, onOpenProspect: @escaping (String) -> Void) {
        self.recruit = recruit
        self.appointment = appointment
        self.onOpenProspect = onOpenProspect
        _newDate = State(initialValue: appointment.date)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                RecruitmentBackground()
                ScrollView {
                    VStack(spacing: 14) {
                        VStack(alignment: .leading, spacing: 10) {
                            CapsLabel(text: appointment.kind.label)
                            Text(appointment.prospectName)
                                .font(.system(.title3, weight: .black))
                            Text("\(Fmt.dateLong(appointment.date)) · \(Fmt.clock(appointment.date))")
                                .font(.footnote)
                                .foregroundStyle(Palette.textMuted)
                            StatePill(
                                text: appointment.status.label,
                                symbol: appointment.status.symbol,
                                tone: appointment.status.tone
                            )
                            if !appointment.note.isEmpty {
                                Text(appointment.note)
                                    .font(.system(size: 11))
                                    .foregroundStyle(Palette.textMuted)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                        .panel()

                        VStack(alignment: .leading, spacing: 9) {
                            SupSectionHeader(title: "Estado de la cita", accent: RecTone.accent)
                            LazyVGrid(columns: [GridItem(.flexible(), spacing: 9), GridItem(.flexible(), spacing: 9)], spacing: 9) {
                                ForEach(AppointmentStatus.allCases) { status in
                                    Button {
                                        recruit.updateAppointment(appointment.id, status: status)
                                        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                                        dismiss()
                                    } label: {
                                        HStack(spacing: 7) {
                                            Image(systemName: status.symbol)
                                                .font(.system(size: 11, weight: .bold))
                                            Text(status.label)
                                                .font(.system(size: 11, weight: .bold))
                                        }
                                        .foregroundStyle(status == appointment.status ? Palette.canvas : status.tone)
                                        .frame(maxWidth: .infinity, minHeight: 44)
                                        .background(
                                            status == appointment.status ? status.tone : status.tone.opacity(0.1),
                                            in: .rect(cornerRadius: 12)
                                        )
                                        .overlay {
                                            RoundedRectangle(cornerRadius: 12)
                                                .stroke(status == appointment.status ? .clear : status.tone.opacity(0.3), lineWidth: 1)
                                        }
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        .padding(15)
                        .panel()

                        VStack(alignment: .leading, spacing: 10) {
                            SupSectionHeader(title: "Reprogramar", accent: RecTone.accent)
                            DatePicker("Nueva fecha", selection: $newDate)
                                .datePickerStyle(.compact)
                                .font(.footnote)
                            Button {
                                recruit.rescheduleAppointment(appointment.id, to: newDate)
                                UINotificationFeedbackGenerator().notificationOccurred(.success)
                                dismiss()
                            } label: {
                                Text("Guardar nueva fecha")
                                    .font(.system(.footnote, weight: .bold))
                                    .foregroundStyle(Palette.canvas)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                    .background(RecTone.accent, in: .capsule)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(15)
                        .panel()

                        Button {
                            onOpenProspect(appointment.prospectId)
                        } label: {
                            Text("Abrir expediente del candidato")
                                .font(.system(.footnote, weight: .bold))
                                .foregroundStyle(RecTone.accent)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 6)
                    .padding(.bottom, 34)
                }
                .scrollIndicators(.hidden)
            }
            .navigationTitle("Cita")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Palette.canvas, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cerrar") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}

// MARK: - Scheduling

struct AppointmentFormView: View {
    let recruit: RecruitmentStore
    let prospect: Prospect

    @Environment(\.dismiss) private var dismiss
    @State private var date: Date = Date()
    @State private var kind: AppointmentKind = .phone
    @State private var owner: String = ""
    @State private var note: String = ""

    private var station: Station? { StaffDirectory.station(id: prospect.stationId) }

    var body: some View {
        NavigationStack {
            Form {
                Section("Candidato") {
                    LabeledContent("Nombre", value: prospect.shortName)
                    LabeledContent("Estación", value: station?.displayName ?? "—")
                    LabeledContent("Turno", value: prospect.requestedBlock.label)
                }

                Section("Cita") {
                    Picker("Tipo", selection: $kind) {
                        ForEach(AppointmentKind.allCases) { option in
                            Text(option.label).tag(option)
                        }
                    }
                    DatePicker("Fecha y hora", selection: $date)
                    TextField("Responsable", text: $owner)
                    TextField("Nota", text: $note, axis: .vertical)
                        .lineLimit(2...4)
                }

                Section {
                    Text("Todas las citas del proceso son tuyas: contacto, entrevista, cierre de expediente y firma del alta. La estación no entrevista a nadie.")
                        .font(.caption2)
                        .foregroundStyle(Palette.textMuted)
                }
            }
            .scrollContentBackground(.hidden)
            .background(RecruitmentBackground())
            .navigationTitle("Programar cita")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Palette.canvas, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Programar") {
                        recruit.scheduleAppointment(
                            prospectId: prospect.id,
                            date: date,
                            kind: kind,
                            owner: owner.isEmpty ? recruit.account.name : owner,
                            note: note
                        )
                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                        dismiss()
                    }
                    .font(.system(.body, weight: .bold))
                }
            }
            .onAppear {
                date = recruit.now.addingTimeInterval(86_400)
                owner = recruit.account.name
                if prospect.stage == .documents || prospect.stage == .interviewed {
                    kind = .operational
                }
            }
            .onChange(of: kind) { _, newValue in
                // An on-site appointment happens at the station, but the recruiter is
                // still the one who runs it.
                if newValue == .operational, owner.isEmpty {
                    owner = recruit.account.name
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}
