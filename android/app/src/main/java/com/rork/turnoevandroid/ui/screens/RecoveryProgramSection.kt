package com.rork.turnoevandroid.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CalendarMonth
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.ChevronLeft
import androidx.compose.material.icons.filled.ChevronRight
import androidx.compose.material.icons.filled.EventAvailable
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.rork.turnoevandroid.FleetViewModel
import com.rork.turnoevandroid.data.FleetState
import com.rork.turnoevandroid.domain.BonusKind
import com.rork.turnoevandroid.domain.BonusRules
import com.rork.turnoevandroid.domain.ShiftRules
import com.rork.turnoevandroid.domain.ShiftSlot
import com.rork.turnoevandroid.ui.components.BigButton
import com.rork.turnoevandroid.ui.theme.CapsLabel
import com.rork.turnoevandroid.ui.theme.Palette
import com.rork.turnoevandroid.ui.theme.TabularNumbers
import com.rork.turnoevandroid.ui.theme.panel
import com.rork.turnoevandroid.ui.theme.panelFlat
import com.rork.turnoevandroid.util.Fmt
import com.rork.turnoevandroid.util.plusDays
import com.rork.turnoevandroid.util.plusMonths
import java.util.Calendar

/**
 * Bonus recovery program: the driver reserves days on the opposite group
 * (weekday drivers on Saturday/Sunday, weekend drivers Monday to Friday)
 * and picks the morning or evening slot.
 */
@Composable
fun RecoveryProgramSection(
    viewModel: FleetViewModel,
    state: FleetState,
    now: Long,
    suggestedBonus: BonusKind,
    modifier: Modifier = Modifier,
) {
    val driver = viewModel.driver
    var monthAnchor by remember { mutableStateOf<Long?>(null) }
    var selectedDay by remember { mutableStateOf<Long?>(null) }
    var slot by remember { mutableStateOf<ShiftSlot?>(null) }
    var bonus by remember { mutableStateOf<BonusKind?>(null) }
    var feedback by remember { mutableStateOf<String?>(null) }

    val anchor = monthAnchor ?: BonusRules.monthStart(now)
    val activeSlot = slot ?: driver.slot
    val activeBonus = bonus ?: suggestedBonus

    Column(
        modifier
            .fillMaxWidth()
            .panel()
            .padding(18.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        // Header
        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Row(horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.CenterVertically) {
                Box(
                    Modifier
                        .size(42.dp)
                        .clip(RoundedCornerShape(14.dp))
                        .background(Palette.volt.copy(alpha = 0.12f)),
                    contentAlignment = Alignment.Center,
                ) {
                    Icon(Icons.Filled.EventAvailable, null, Modifier.size(20.dp), tint = Palette.volt)
                }
                Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                    Text(
                        "Programa de recuperación de bonos",
                        style = TextStyle(fontSize = 14.sp, fontWeight = FontWeight.Black, color = Palette.textPrimary),
                    )
                    Text(
                        "Turnos disponibles: ${BonusRules.recoveryDaysLabel(driver)}",
                        style = TextStyle(fontSize = 11.sp, color = Palette.textMuted),
                    )
                }
            }
            Text(
                "Tu grupo es ${driver.group.label.lowercase()}, así que recuperas en " +
                    "${BonusRules.recoveryGroup(driver).label.lowercase()}. Elige el día y el turno en el " +
                    "que quieres laborar.",
                style = TextStyle(fontSize = 11.sp, color = Palette.textMuted),
            )
        }

        // Slot picker
        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            CapsLabel("Turno a laborar")
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                ShiftSlot.entries.forEach { option ->
                    val isActive = activeSlot == option
                    Column(
                        Modifier
                            .weight(1f)
                            .clip(RoundedCornerShape(16.dp))
                            .background(
                                if (isActive) {
                                    Palette.volt.copy(alpha = 0.13f)
                                } else {
                                    Palette.surfaceRaised.copy(alpha = 0.6f)
                                },
                            )
                            .border(
                                1.dp,
                                if (isActive) Palette.volt.copy(alpha = 0.6f) else Palette.hairline,
                                RoundedCornerShape(16.dp),
                            )
                            .clickable { slot = option }
                            .padding(12.dp),
                        verticalArrangement = Arrangement.spacedBy(2.dp),
                    ) {
                        Text(
                            option.label,
                            style = TextStyle(fontSize = 14.sp, fontWeight = FontWeight.Bold, color = Palette.textPrimary),
                        )
                        Text(
                            option.rangeLabel,
                            style = TextStyle(
                                fontSize = 10.sp,
                                fontFamily = TabularNumbers,
                                color = Palette.textMuted,
                            ),
                        )
                    }
                }
            }
        }

        // Bonus picker
        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            CapsLabel("Bono a recuperar")
            Row(
                Modifier
                    .fillMaxWidth()
                    .horizontalScroll(rememberScrollState()),
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                BonusKind.entries.filterNot { it.isExternal }.forEach { option ->
                    val isActive = activeBonus == option
                    Text(
                        option.title,
                        style = TextStyle(
                            fontSize = 11.sp,
                            fontWeight = FontWeight.Bold,
                            color = if (isActive) Palette.canvas else Palette.textMuted,
                        ),
                        modifier = Modifier
                            .clip(CircleShape)
                            .background(if (isActive) Palette.volt else Palette.surfaceRaised.copy(alpha = 0.7f))
                            .border(
                                1.dp,
                                if (isActive) Color.Transparent else Palette.hairline,
                                CircleShape,
                            )
                            .clickable { bonus = option }
                            .padding(horizontal = 12.dp, vertical = 9.dp),
                    )
                }
            }
        }

        // Calendar
        Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                CalendarArrow(Icons.Filled.ChevronLeft) {
                    monthAnchor = anchor.plusMonths(-1)
                    selectedDay = null
                }
                Spacer(Modifier.weight(1f))
                Text(
                    Fmt.monthLong(anchor),
                    style = TextStyle(fontSize = 14.sp, fontWeight = FontWeight.Black, color = Palette.textPrimary),
                )
                Spacer(Modifier.weight(1f))
                CalendarArrow(Icons.Filled.ChevronRight) {
                    monthAnchor = anchor.plusMonths(1)
                    selectedDay = null
                }
            }

            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                listOf("L", "M", "M", "J", "V", "S", "D").forEach { day ->
                    Text(
                        day,
                        style = TextStyle(
                            fontSize = 10.sp,
                            fontWeight = FontWeight.Black,
                            color = Palette.textMuted,
                        ),
                        textAlign = TextAlign.Center,
                        modifier = Modifier.weight(1f),
                    )
                }
            }

            monthCells(anchor).chunked(7).forEach { week ->
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                    week.forEach { day ->
                        if (day == null) {
                            Spacer(
                                Modifier
                                    .weight(1f)
                                    .height(42.dp),
                            )
                        } else {
                            val booking = viewModel.recoveryBooking(day)
                            val isAvailable = BonusRules.canBook(driver, day, now)
                            val isSelected = selectedDay?.let { ShiftRules.isSameDay(it, day) } == true
                            val isToday = ShiftRules.isSameDay(day, now)
                            DayCell(
                                dayNumber = Fmt.calendar(day).get(Calendar.DAY_OF_MONTH),
                                isSelected = isSelected,
                                isAvailable = isAvailable,
                                hasBooking = booking != null,
                                isToday = isToday,
                                modifier = Modifier.weight(1f),
                            ) {
                                if (isAvailable && booking == null) {
                                    selectedDay = day
                                    feedback = null
                                }
                            }
                        }
                    }
                    repeat(7 - week.size) {
                        Spacer(
                            Modifier
                                .weight(1f)
                                .height(42.dp),
                        )
                    }
                }
            }
        }

        // Footer
        Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
            val chosen = selectedDay
            if (chosen != null) {
                Row(
                    Modifier
                        .fillMaxWidth()
                        .panelFlat()
                        .padding(12.dp),
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Icon(Icons.Filled.CalendarMonth, null, Modifier.size(14.dp), tint = Palette.volt)
                    Text(
                        "${Fmt.dateShort(chosen)} · ${activeSlot.label} ${activeSlot.rangeLabel}",
                        style = TextStyle(fontSize = 11.sp, fontWeight = FontWeight.SemiBold, color = Palette.textPrimary),
                    )
                }
            } else {
                Text(
                    "Selecciona un día disponible (marcado con punto) para reservar tu lugar.",
                    style = TextStyle(fontSize = 11.sp, color = Palette.textMuted),
                )
            }

            feedback?.let { message ->
                Text(message, style = TextStyle(fontSize = 13.sp, color = Palette.volt))
            }

            BigButton(
                title = "Reservar día de recuperación",
                icon = Icons.Filled.CheckCircle,
                enabled = chosen != null,
            ) {
                val day = chosen ?: return@BigButton
                val saved = viewModel.bookRecovery(day, activeSlot, activeBonus)
                feedback = if (saved) {
                    selectedDay = null
                    "Reserva confirmada para ${Fmt.dateShort(day)} en turno ${activeSlot.label.lowercase()}."
                } else {
                    "Ese día ya no está disponible. Elige otro."
                }
            }
        }

        if (state.recoveryBookings.isNotEmpty()) {
            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                CapsLabel("Mis reservas")
                viewModel.upcomingRecoveryBookings.forEach { booking ->
                    Row(
                        Modifier
                            .fillMaxWidth()
                            .panelFlat()
                            .padding(12.dp),
                        horizontalArrangement = Arrangement.spacedBy(10.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                            Text(
                                Fmt.dateShort(booking.date),
                                style = TextStyle(fontSize = 12.sp, fontWeight = FontWeight.Bold, color = Palette.textPrimary),
                            )
                            Text(
                                "${booking.slot.label} ${booking.slot.rangeLabel} · bono de ${booking.bonus.shortName}",
                                style = TextStyle(fontSize = 10.sp, color = Palette.textMuted),
                            )
                        }
                        Text(
                            "Cancelar",
                            style = TextStyle(fontSize = 10.sp, fontWeight = FontWeight.Bold, color = Palette.danger),
                            modifier = Modifier
                                .clip(CircleShape)
                                .background(Palette.danger.copy(alpha = 0.12f))
                                .clickable { viewModel.cancelRecovery(booking.id) }
                                .padding(horizontal = 10.dp, vertical = 6.dp),
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun CalendarArrow(icon: androidx.compose.ui.graphics.vector.ImageVector, onClick: () -> Unit) {
    Box(
        Modifier
            .size(34.dp)
            .background(Palette.surfaceRaised, CircleShape)
            .clickable { onClick() },
        contentAlignment = Alignment.Center,
    ) {
        Icon(icon, null, Modifier.size(18.dp), tint = Palette.textPrimary)
    }
}

@Composable
private fun DayCell(
    dayNumber: Int,
    isSelected: Boolean,
    isAvailable: Boolean,
    hasBooking: Boolean,
    isToday: Boolean,
    modifier: Modifier = Modifier,
    onClick: () -> Unit,
) {
    val foreground = when {
        isSelected -> Palette.canvas
        hasBooking -> Palette.volt
        isAvailable -> Palette.textPrimary
        else -> Palette.textMuted.copy(alpha = 0.45f)
    }
    val background = when {
        isSelected -> Palette.volt
        hasBooking -> Palette.volt.copy(alpha = 0.16f)
        isAvailable -> Palette.surfaceRaised.copy(alpha = 0.85f)
        else -> Palette.surfaceRaised.copy(alpha = 0.25f)
    }
    Column(
        modifier
            .height(42.dp)
            .clip(RoundedCornerShape(12.dp))
            .background(background)
            .then(
                if (isToday) {
                    Modifier.border(1.5.dp, Palette.info.copy(alpha = 0.7f), RoundedCornerShape(12.dp))
                } else {
                    Modifier
                },
            )
            .clickable(enabled = isAvailable && !hasBooking) { onClick() },
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center,
    ) {
        Text(
            "$dayNumber",
            style = TextStyle(
                fontSize = 13.sp,
                fontWeight = FontWeight.Bold,
                fontFamily = TabularNumbers,
                color = foreground,
            ),
        )
        when {
            hasBooking -> Icon(Icons.Filled.Check, null, Modifier.size(10.dp), tint = foreground)
            isAvailable -> Box(
                Modifier
                    .size(4.dp)
                    .background(if (isSelected) Palette.canvas else Palette.volt, CircleShape),
            )
        }
    }
}

/** Leading blanks + every day of the anchored month, Monday first. */
private fun monthCells(anchor: Long): List<Long?> {
    val calendar = Fmt.calendar(anchor)
    val daysInMonth = calendar.getActualMaximum(Calendar.DAY_OF_MONTH)
    val weekday = calendar.get(Calendar.DAY_OF_WEEK)
    val leading = (weekday + 5) % 7
    val cells = mutableListOf<Long?>()
    repeat(leading) { cells += null }
    for (offset in 0 until daysInMonth) {
        cells += anchor.plusDays(offset)
    }
    return cells
}
