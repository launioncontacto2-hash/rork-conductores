import SwiftUI

/// Bonus recovery program: the driver reserves days on the opposite group
/// (weekday drivers on Saturday/Sunday, weekend drivers Monday to Friday)
/// and picks the morning or evening slot.
struct RecoveryProgramSection: View {
    @Environment(FleetStore.self) private var store

    let suggestedBonus: BonusKind

    /// Start of the logical day, resolved once by the host screen.
    ///
    /// Everything this calendar asks of the clock is day-granular — which month it opens
    /// on, which cells are still bookable, which one is today — so it takes the day instead
    /// of reading `store.now` in its own body. The host owns the one detector; this section
    /// simply redraws when the day it was given changes.
    let today: Date

    @State private var monthAnchor: Date?
    @State private var selectedDay: Date?
    @State private var slot: ShiftSlot?
    @State private var bonus: BonusKind?
    @State private var feedback: String?

    private var anchor: Date { monthAnchor ?? BonusRules.monthStart(for: today) }
    private var activeSlot: ShiftSlot { slot ?? store.driver.slot }
    private var activeBonus: BonusKind { bonus ?? suggestedBonus }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            slotPicker
            bonusPicker
            calendar
            selectionFooter

            if !store.recoveryBookings.isEmpty {
                bookingsList
            }
        }
        .padding(18)
        .panel()
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: "calendar.badge.plus")
                    .font(.system(.body, weight: .semibold))
                    .foregroundStyle(Palette.volt)
                    .frame(width: 42, height: 42)
                    .background(Palette.volt.opacity(0.12), in: .rect(cornerRadius: 14))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Programa de recuperación de bonos")
                        .font(.system(.subheadline, weight: .black))
                    Text("Turnos disponibles: \(BonusRules.recoveryDaysLabel(for: store.driver))")
                        .font(.caption2)
                        .foregroundStyle(Palette.textMuted)
                }
                Spacer(minLength: 0)
            }

            Text("Tu grupo es \(store.driver.group.label.lowercased()), así que recuperas en \(BonusRules.recoveryGroup(for: store.driver).label.lowercased()). Elige el día y el turno en el que quieres laborar.")
                .font(.system(size: 11))
                .foregroundStyle(Palette.textMuted)
        }
    }

    private var slotPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            CapsLabel(text: "Turno a laborar")
            HStack(spacing: 10) {
                ForEach(ShiftSlot.allCases, id: \.self) { option in
                    let isActive = activeSlot == option
                    Button {
                        slot = option
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(option.label)
                                .font(.system(.subheadline, weight: .bold))
                            Text(option.rangeLabel)
                                .font(.system(size: 10))
                                .monospacedDigit()
                                .foregroundStyle(Palette.textMuted)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background((isActive ? Palette.volt.opacity(0.13) : Palette.surfaceRaised.opacity(0.6)), in: .rect(cornerRadius: 16))
                        .overlay {
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(isActive ? Palette.volt.opacity(0.6) : Palette.hairline, lineWidth: 1)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var bonusPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            CapsLabel(text: "Bono a recuperar")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(BonusKind.allCases.filter { !$0.isExternal }) { option in
                        let isActive = activeBonus == option
                        Button {
                            bonus = option
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: option.symbol)
                                    .font(.system(size: 10, weight: .bold))
                                Text(option.title)
                                    .font(.system(size: 11, weight: .bold))
                            }
                            .foregroundStyle(isActive ? Palette.canvas : Palette.textMuted)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 9)
                            .background(isActive ? Palette.volt : Palette.surfaceRaised.opacity(0.7), in: .capsule)
                            .overlay { Capsule().stroke(isActive ? .clear : Palette.hairline, lineWidth: 1) }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .contentMargins(.horizontal, 0)
        }
    }

    // MARK: - Calendar

    private var calendar: some View {
        VStack(spacing: 12) {
            HStack {
                Button {
                    shiftMonth(by: -1)
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(.footnote, weight: .bold))
                        .frame(width: 34, height: 34)
                        .background(Palette.surfaceRaised, in: .circle)
                }
                .buttonStyle(.plain)

                Spacer()
                Text(Fmt.monthLong(anchor))
                    .font(.system(.subheadline, weight: .black))
                Spacer()

                Button {
                    shiftMonth(by: 1)
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(.footnote, weight: .bold))
                        .frame(width: 34, height: 34)
                        .background(Palette.surfaceRaised, in: .circle)
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 4) {
                ForEach(["L", "M", "M", "J", "V", "S", "D"], id: \.self) { day in
                    Text(day)
                        .font(.system(size: 10, weight: .black))
                        .foregroundStyle(Palette.textMuted)
                        .frame(maxWidth: .infinity)
                }
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 4) {
                ForEach(Array(monthCells.enumerated()), id: \.offset) { _, day in
                    if let day {
                        dayCell(day)
                    } else {
                        Color.clear.frame(height: 42)
                    }
                }
            }
        }
    }

    private var monthCells: [Date?] {
        let cal = ShiftRules.calendar
        guard let range = cal.range(of: .day, in: .month, for: anchor) else { return [] }
        let weekday = cal.component(.weekday, from: anchor)
        let leading = (weekday + 5) % 7
        var cells: [Date?] = Array(repeating: nil, count: leading)
        for offset in 0..<range.count {
            cells.append(cal.date(byAdding: .day, value: offset, to: anchor))
        }
        return cells
    }

    private func dayCell(_ day: Date) -> some View {
        let cal = ShiftRules.calendar
        let booking = store.recoveryBooking(on: day)
        let isAvailable = BonusRules.canBook(driver: store.driver, date: day, now: today)
        let isSelected = selectedDay.map { cal.isDate($0, inSameDayAs: day) } ?? false
        let isToday = ShiftRules.isSameDay(day, today)
        let dayNumber = cal.component(.day, from: day)

        return Button {
            guard isAvailable, booking == nil else { return }
            selectedDay = day
            feedback = nil
        } label: {
            VStack(spacing: 2) {
                Text("\(dayNumber)")
                    .font(.system(size: 13, weight: .bold))
                    .monospacedDigit()
                if booking != nil {
                    Image(systemName: "checkmark")
                        .font(.system(size: 8, weight: .black))
                } else if isAvailable {
                    Circle().fill(Palette.volt).frame(width: 4, height: 4)
                }
            }
            .foregroundStyle(foreground(isSelected: isSelected, isAvailable: isAvailable, hasBooking: booking != nil))
            .frame(maxWidth: .infinity)
            .frame(height: 42)
            .background(background(isSelected: isSelected, isAvailable: isAvailable, hasBooking: booking != nil), in: .rect(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isToday ? Palette.info.opacity(0.7) : .clear, lineWidth: 1.5)
            }
        }
        .buttonStyle(.plain)
        .disabled(!isAvailable || booking != nil)
    }

    private func foreground(isSelected: Bool, isAvailable: Bool, hasBooking: Bool) -> Color {
        if isSelected { return Palette.canvas }
        if hasBooking { return Palette.volt }
        return isAvailable ? .primary : Palette.textMuted.opacity(0.45)
    }

    private func background(isSelected: Bool, isAvailable: Bool, hasBooking: Bool) -> Color {
        if isSelected { return Palette.volt }
        if hasBooking { return Palette.volt.opacity(0.16) }
        return isAvailable ? Palette.surfaceRaised.opacity(0.85) : Palette.surfaceRaised.opacity(0.25)
    }

    private func shiftMonth(by value: Int) {
        let cal = ShiftRules.calendar
        guard let next = cal.date(byAdding: .month, value: value, to: anchor) else { return }
        monthAnchor = next
        selectedDay = nil
    }

    // MARK: - Footer

    private var selectionFooter: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let selectedDay {
                HStack(spacing: 8) {
                    Image(systemName: "calendar")
                        .font(.caption2)
                        .foregroundStyle(Palette.volt)
                    Text("\(Fmt.dateShort(selectedDay).capitalized) · \(activeSlot.label) \(activeSlot.rangeLabel)")
                        .font(.system(size: 11, weight: .semibold))
                    Spacer(minLength: 0)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .panelFlat()
            } else {
                Text("Selecciona un día disponible (marcado con punto) para reservar tu lugar.")
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.textMuted)
            }

            if let feedback {
                Text(feedback)
                    .font(.footnote)
                    .foregroundStyle(Palette.volt)
            }

            BigButton(
                title: "Reservar día de recuperación",
                symbol: "checkmark.circle.fill",
                isEnabled: selectedDay != nil
            ) {
                reserve()
            }
        }
    }

    private func reserve() {
        guard let day = selectedDay else { return }
        let saved = store.bookRecovery(date: day, slot: activeSlot, bonus: activeBonus)
        if saved {
            feedback = "Reserva confirmada para \(Fmt.dateShort(day).capitalized) en turno \(activeSlot.label.lowercased())."
            selectedDay = nil
        } else {
            feedback = "Ese día ya no está disponible. Elige otro."
        }
    }

    private var bookingsList: some View {
        VStack(alignment: .leading, spacing: 10) {
            CapsLabel(text: "Mis reservas")
            ForEach(store.upcomingRecoveryBookings) { booking in
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(Fmt.dateShort(booking.date).capitalized)
                            .font(.system(.caption, weight: .bold))
                        Text("\(booking.slot.label) \(booking.slot.rangeLabel) · bono de \(booking.bonus.shortName)")
                            .font(.system(size: 10))
                            .foregroundStyle(Palette.textMuted)
                    }
                    Spacer(minLength: 0)
                    Button {
                        store.cancelRecovery(id: booking.id)
                    } label: {
                        Text("Cancelar")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Palette.danger)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Palette.danger.opacity(0.12), in: .capsule)
                    }
                    .buttonStyle(.plain)
                }
                .padding(12)
                .panelFlat()
            }
        }
    }
}

#Preview {
    ScrollView {
        RecoveryProgramSection(suggestedBonus: .punctuality, today: .now)
            .padding()
    }
    .background { StationBackground() }
    .environment(FleetStore())
    .preferredColorScheme(.dark)
}
