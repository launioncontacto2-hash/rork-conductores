import SwiftUI

/// Personal: who holds every shift of the manager's own station. The module opens with
/// the station directory — the two supervisors, the workshop and the recruitment desk,
/// each with their direct line — because when something breaks on the floor the manager
/// needs a phone call, not an org chart. Below it, how each one is performing.
struct ManagerStaffView: View {
    let regional: RegionalStore
    let header: ManagerHeader
    let onOpenStation: (String) -> Void

    @State private var search: String = ""

    /// Instant the coverage counters are measured against. `.minute`, inherited from
    /// `metrics`.
    @State private var minuteAnchor: Date = AppClock.now()

    private var supervisors: [SupervisorScorecard] {
        let cleaned = search.trimmingCharacters(in: .whitespacesAndNewlines)
        let all = regional.supervisors.sorted { lhs, rhs in
            lhs.stationCode == rhs.stationCode
                ? (lhs.slot == .morning && rhs.slot != .morning)
                : lhs.stationCode < rhs.stationCode
        }
        guard !cleaned.isEmpty else { return all }
        return all.filter {
            $0.name.localizedStandardContains(cleaned)
                || $0.stationCode.localizedStandardContains(cleaned)
                || $0.employeeNumber.localizedStandardContains(cleaned)
        }
    }

    var body: some View {
        ZStack {
            ManagementBackground()

            ScrollView {
                VStack(spacing: 14) {
                    header
                    directory
                    coverage
                    supervisionList
                    workshopList
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 34)
            }
            .scrollIndicators(.hidden)
            .searchable(text: $search, prompt: "Supervisor o número de empleado")
        }
        .background {
            ClockAnchor(.minute, date: $minuteAnchor)
        }
    }

    // MARK: - Directory

    /// The plantilla of the station with a call key on every line.
    private var directory: some View {
        let contacts = regional.staffDirectory
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                CapsLabel(text: "Directorio de \(regional.station.code)")
                Spacer(minLength: 0)
                Text("\(contacts.count) personas")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Palette.textMuted)
            }

            if contacts.isEmpty {
                Text("Esta estación todavía no tiene plantilla registrada. Dirección nacional debe dar de alta la supervisión, el taller y la mesa de reclutamiento.")
                    .font(.footnote)
                    .foregroundStyle(Palette.textMuted)
            } else {
                ForEach(StationContactDesk.allCases, id: \.self) { desk in
                    let group = contacts.filter { $0.desk == desk }
                    if !group.isEmpty {
                        Text(desk.label.uppercased())
                            .font(.system(size: 9, weight: .black))
                            .tracking(1.1)
                            .foregroundStyle(Palette.textMuted.opacity(0.8))
                            .padding(.top, 2)
                        ForEach(group) { contact in
                            StationContactRow(contact: contact)
                        }
                    }
                }
            }

            Text("Todos están registrados en \(regional.station.code): la credencial queda amarrada a la estación donde fue dada de alta, y eso te incluye a ti.")
                .font(.caption2)
                .foregroundStyle(Palette.textMuted)
        }
        .padding(16)
        .panel()
    }

    // MARK: - Coverage

    private var coverage: some View {
        let metrics = regional.metrics(now: minuteAnchor)
        let required = regional.station.requiredDrivers
        return VStack(alignment: .leading, spacing: 12) {
            CapsLabel(text: "Cobertura de la estación")
            HStack(spacing: 10) {
                StatTile(
                    label: "Conductores",
                    value: "\(metrics.payrollSize)",
                    hint: "de \(required) requeridos",
                    tone: metrics.payrollSize < required ? .amber : .volt
                )
                StatTile(label: "Supervisores", value: "\(regional.supervisors.count)", hint: "Uno por turno", tone: .neutral)
            }
            HStack(spacing: 10) {
                StatTile(label: "Mantenimiento", value: "2", hint: "Uno por turno", tone: .neutral)
                StatTile(label: "Plazas por cubrir", value: "\(max(0, required - metrics.payrollSize))", hint: "Las trabaja reclutamiento", tone: metrics.payrollSize < required ? .amber : .volt)
            }
        }
        .padding(16)
        .panel()
    }

    // MARK: - Lists

    private var supervisionList: some View {
        VStack(alignment: .leading, spacing: 10) {
            SupSectionHeader(
                title: "Supervisión",
                subtitle: "Un supervisor por turno en tu estación",
                accent: MgTone.accent
            )

            if supervisors.isEmpty {
                SupEmptyState(
                    symbol: "person.2.badge.gearshape",
                    title: "Sin resultados",
                    message: "Ningún supervisor de tu estación coincide con la búsqueda.",
                    accent: MgTone.accent
                )
            } else {
                ForEach(supervisors) { supervisor in
                    Button {
                        onOpenStation(supervisor.stationId)
                    } label: {
                        SupervisorRow(card: supervisor)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var workshopList: some View {
        VStack(alignment: .leading, spacing: 10) {
            SupSectionHeader(
                title: "Mantenimiento",
                subtitle: "Personal de taller asignado a tu estación",
                accent: MgTone.accent
            )

            ForEach(regional.scorecards) { card in
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        Text(card.code)
                            .font(.system(size: 10, weight: .black))
                            .foregroundStyle(Palette.textMuted)
                        Text(card.name)
                            .font(.system(.footnote, weight: .bold))
                        Spacer(minLength: 0)
                        InfoChip(
                            symbol: "wrench.and.screwdriver.fill",
                            text: "\(card.inMaintenance) en taller",
                            tone: card.inMaintenance >= RegionalRules.maintenanceBacklogCeiling ? MgTone.bad : Palette.textMuted
                        )
                    }
                    Text("Los teléfonos del taller están en el directorio, arriba.")
                        .font(.caption2)
                        .foregroundStyle(Palette.textMuted)
                }
                .padding(13)
                .panelFlat()
            }
        }
    }
}

/// Order the desks appear in the directory: supervision first, because it is the desk
/// the manager calls most, then the workshop and the recruitment desk.
private typealias StationContactDesk = StationContact.Desk
