package com.rork.turnoevandroid.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Build
import androidx.compose.material.icons.filled.DirectionsCar
import androidx.compose.material.icons.filled.Payments
import androidx.compose.material.icons.filled.PhotoLibrary
import androidx.compose.material.icons.filled.Replay
import androidx.compose.material.icons.filled.Timer
import androidx.compose.material.icons.filled.Verified
import androidx.compose.material.icons.filled.Warning
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
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.rork.turnoevandroid.FleetViewModel
import com.rork.turnoevandroid.data.FleetState
import com.rork.turnoevandroid.domain.IncidentKind
import com.rork.turnoevandroid.domain.IncidentStatus
import com.rork.turnoevandroid.domain.ShiftRules
import com.rork.turnoevandroid.ui.components.BigButton
import com.rork.turnoevandroid.ui.components.Chip
import com.rork.turnoevandroid.ui.components.NoticeBanner
import com.rork.turnoevandroid.ui.components.Tone
import com.rork.turnoevandroid.ui.theme.CapsLabel
import com.rork.turnoevandroid.ui.theme.Palette
import com.rork.turnoevandroid.ui.theme.TabularNumbers
import com.rork.turnoevandroid.ui.theme.panel
import com.rork.turnoevandroid.ui.theme.panelFlat
import com.rork.turnoevandroid.util.Fmt

private enum class HistorySection(val label: String) {
    SHIFTS("Turnos"),
    INCOMES("Ingresos"),
    INCIDENTS("Incidencias"),
}

/** Shift log with the weekly late-time record, plus income and incident history. */
@Composable
fun HistoryScreen(viewModel: FleetViewModel, state: FleetState, now: Long) {
    var section by remember { mutableStateOf(HistorySection.SHIFTS) }
    var paybackMessage by remember { mutableStateOf<String?>(null) }

    Column(
        Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(horizontal = 16.dp)
            .padding(top = 12.dp, bottom = 28.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        Text(
            "Historial",
            style = TextStyle(fontSize = 17.sp, fontWeight = FontWeight.Black, color = Palette.textPrimary),
        )

        // Late log
        val days = viewModel.weeklyLateBreakdown(now)
        val debt = viewModel.weeklyLateDebt(now)
        val paybackOpen = ShiftRules.isPaybackWindow(viewModel.driver, now)

        Column(
            Modifier
                .fillMaxWidth()
                .panel()
                .padding(18.dp),
            verticalArrangement = Arrangement.spacedBy(14.dp),
        ) {
            Row(Modifier.fillMaxWidth()) {
                Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Icon(Icons.Filled.Timer, null, Modifier.size(14.dp), tint = Palette.textMuted)
                        Spacer(Modifier.size(6.dp))
                        Text(
                            "Atrasos de la semana",
                            style = TextStyle(fontSize = 12.sp, fontWeight = FontWeight.SemiBold, color = Palette.textMuted),
                        )
                    }
                    Text(
                        "$debt min",
                        style = TextStyle(
                            fontSize = 28.sp,
                            fontWeight = FontWeight.Black,
                            fontFamily = TabularNumbers,
                            color = if (debt > 0) Palette.amber else Palette.volt,
                        ),
                    )
                }
                Spacer(Modifier.weight(1f))
                Text(
                    viewModel.driver.slot.label.uppercase(),
                    style = TextStyle(
                        fontSize = 9.sp,
                        fontWeight = FontWeight.Black,
                        letterSpacing = 1.2.sp,
                        color = Palette.textMuted,
                    ),
                    modifier = Modifier
                        .clip(CircleShape)
                        .background(Palette.surfaceRaised)
                        .padding(horizontal = 9.dp, vertical = 5.dp),
                )
            }

            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                days.forEach { day ->
                    val tone = when {
                        !day.hasShift -> Palette.textMuted
                        day.pendingMinutes > 0 -> Palette.amber
                        else -> Palette.volt
                    }
                    Column(
                        Modifier.weight(1f),
                        horizontalAlignment = Alignment.CenterHorizontally,
                        verticalArrangement = Arrangement.spacedBy(5.dp),
                    ) {
                        Box(
                            Modifier
                                .fillMaxWidth()
                                .height(52.dp)
                                .clip(RoundedCornerShape(14.dp))
                                .background(tone.copy(alpha = if (day.hasShift) 0.12f else 0.04f))
                                .border(
                                    1.dp,
                                    tone.copy(alpha = if (day.hasShift) 0.45f else 0.15f),
                                    RoundedCornerShape(14.dp),
                                ),
                            contentAlignment = Alignment.Center,
                        ) {
                            Text(
                                if (day.hasShift) "${day.pendingMinutes}" else "—",
                                style = TextStyle(
                                    fontSize = 14.sp,
                                    fontWeight = FontWeight.Black,
                                    fontFamily = TabularNumbers,
                                    color = tone,
                                ),
                            )
                        }
                        Text(
                            day.label,
                            style = TextStyle(fontSize = 10.sp, fontWeight = FontWeight.SemiBold, color = Palette.textMuted),
                        )
                    }
                }
            }

            Text(
                "Minutos pendientes por día. Ventana de pago ${viewModel.driver.slot.paybackWindowLabel} · " +
                    "las horas fuera de esa ventana no se descuentan.",
                style = TextStyle(fontSize = 11.sp, color = Palette.textMuted),
            )

            paybackMessage?.let { message ->
                NoticeBanner(Icons.Filled.Verified, message, tone = Tone.VOLT)
            }

            BigButton(
                title = if (paybackOpen) {
                    "Abonar 30 min de atraso"
                } else {
                    "Disponible ${viewModel.driver.slot.paybackWindowLabel}"
                },
                icon = Icons.Filled.Replay,
                enabled = paybackOpen && debt > 0,
            ) {
                val applied = viewModel.payLateTime(30)
                paybackMessage = if (applied > 0) {
                    "$applied minutos abonados dentro de la ventana autorizada"
                } else {
                    "No tienes atrasos pendientes esta semana"
                }
            }
        }

        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            HistorySection.entries.forEach { option ->
                Chip(option.label, section == option, { section = option })
            }
        }

        when (section) {
            HistorySection.SHIFTS -> state.history.take(12).forEach { record ->
                Column(
                    Modifier
                        .fillMaxWidth()
                        .panelFlat(20.dp)
                        .padding(14.dp),
                    verticalArrangement = Arrangement.spacedBy(12.dp),
                ) {
                    Row(Modifier.fillMaxWidth()) {
                        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                            Text(
                                Fmt.dateShort(record.startedAt),
                                style = TextStyle(fontSize = 14.sp, fontWeight = FontWeight.Bold, color = Palette.textPrimary),
                            )
                            Text(
                                "${Fmt.clock(record.startedAt)} — ${Fmt.clock(record.endedAt)} · " +
                                    record.vehicleInternalNumber,
                                style = TextStyle(fontSize = 11.sp, fontFamily = TabularNumbers, color = Palette.textMuted),
                            )
                        }
                        val onTime = record.pendingLateMinutes == 0
                        Text(
                            if (onTime) "A TIEMPO" else "ATRASO ${Fmt.lateText(record.pendingLateMinutes)}",
                            style = TextStyle(
                                fontSize = 9.sp,
                                fontWeight = FontWeight.Black,
                                letterSpacing = 1.sp,
                                color = if (onTime) Palette.volt else Palette.amber,
                            ),
                            modifier = Modifier
                                .clip(CircleShape)
                                .background((if (onTime) Palette.volt else Palette.amber).copy(alpha = 0.13f))
                                .padding(horizontal = 8.dp, vertical = 5.dp),
                        )
                    }
                    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        HistoryCell("Km", Fmt.km(record.kmDriven), Modifier.weight(1f))
                        HistoryCell("Duración", Fmt.durationText(record.durationMinutes), Modifier.weight(1f))
                        HistoryCell("Viajes", "${record.trips}", Modifier.weight(1f))
                        HistoryCell("Ingresos", Fmt.mxn(record.earningsMxn), Modifier.weight(1f))
                    }
                }
            }

            HistorySection.INCOMES -> state.incomes.take(15).forEach { entry ->
                Row(
                    Modifier
                        .fillMaxWidth()
                        .panelFlat(20.dp)
                        .padding(14.dp),
                    horizontalArrangement = Arrangement.spacedBy(12.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Box(
                        Modifier
                            .size(42.dp)
                            .clip(RoundedCornerShape(14.dp))
                            .background(Palette.volt.copy(alpha = 0.12f)),
                        contentAlignment = Alignment.Center,
                    ) {
                        Icon(Icons.Filled.Payments, null, Modifier.size(20.dp), tint = Palette.volt)
                    }
                    Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                        Text(
                            Fmt.dateShort(entry.date),
                            style = TextStyle(fontSize = 14.sp, fontWeight = FontWeight.Bold, color = Palette.textPrimary),
                        )
                        Text(
                            "${entry.platform.label} · ${entry.trips} viajes" +
                                (entry.note?.let { " · $it" } ?: ""),
                            style = TextStyle(fontSize = 11.sp, color = Palette.textMuted),
                            maxLines = 1,
                        )
                    }
                    if (entry.hasEvidence) {
                        Icon(Icons.Filled.PhotoLibrary, null, Modifier.size(16.dp), tint = Palette.textMuted)
                    }
                    Text(
                        Fmt.mxn(entry.amountMxn),
                        style = TextStyle(
                            fontSize = 15.sp,
                            fontWeight = FontWeight.Black,
                            fontFamily = TabularNumbers,
                            color = Palette.textPrimary,
                        ),
                    )
                }
            }

            HistorySection.INCIDENTS -> {
                if (state.incidents.isEmpty()) {
                    Text(
                        "Sin incidencias registradas.",
                        style = TextStyle(fontSize = 13.sp, color = Palette.textMuted),
                        textAlign = TextAlign.Center,
                        modifier = Modifier
                            .fillMaxWidth()
                            .panelFlat(20.dp)
                            .padding(24.dp),
                    )
                }
                state.incidents.forEach { incident ->
                    Column(
                        Modifier
                            .fillMaxWidth()
                            .panelFlat(20.dp)
                            .padding(14.dp),
                        verticalArrangement = Arrangement.spacedBy(10.dp),
                    ) {
                        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                            Icon(incidentIcon(incident.kind), null, Modifier.size(16.dp), tint = Palette.danger)
                            Spacer(Modifier.size(6.dp))
                            Text(
                                incident.kind.label,
                                style = TextStyle(fontSize = 14.sp, fontWeight = FontWeight.Bold, color = Palette.danger),
                            )
                            Spacer(Modifier.weight(1f))
                            Text(
                                incident.status.label.uppercase(),
                                style = TextStyle(
                                    fontSize = 9.sp,
                                    fontWeight = FontWeight.Black,
                                    letterSpacing = 1.sp,
                                    color = statusTone(incident.status),
                                ),
                                modifier = Modifier
                                    .clip(CircleShape)
                                    .background(statusTone(incident.status).copy(alpha = 0.13f))
                                    .padding(horizontal = 8.dp, vertical = 5.dp),
                            )
                        }
                        Text(
                            incident.description,
                            style = TextStyle(fontSize = 12.sp, color = Palette.textMuted),
                        )
                        Row(horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = Alignment.CenterVertically) {
                            Icon(Icons.Filled.DirectionsCar, null, Modifier.size(12.dp), tint = Palette.textMuted)
                            Text(
                                incident.vehicleInternalNumber,
                                style = TextStyle(fontSize = 10.sp, color = Palette.textMuted),
                            )
                            Text(
                                Fmt.dateShort(incident.createdAt),
                                style = TextStyle(fontSize = 10.sp, color = Palette.textMuted),
                            )
                            if (incident.photoCount > 0) {
                                Icon(Icons.Filled.PhotoLibrary, null, Modifier.size(12.dp), tint = Palette.textMuted)
                                Text(
                                    "${incident.photoCount}",
                                    style = TextStyle(fontSize = 10.sp, color = Palette.textMuted),
                                )
                            }
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun HistoryCell(label: String, value: String, modifier: Modifier = Modifier) {
    Column(
        modifier
            .clip(RoundedCornerShape(12.dp))
            .background(Palette.canvas.copy(alpha = 0.6f))
            .padding(vertical = 8.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(3.dp),
    ) {
        CapsLabel(label)
        Text(
            value,
            style = TextStyle(
                fontSize = 11.sp,
                fontWeight = FontWeight.Bold,
                fontFamily = TabularNumbers,
                color = Palette.textPrimary,
            ),
            maxLines = 1,
        )
    }
}

private fun incidentIcon(kind: IncidentKind): ImageVector = when (kind) {
    IncidentKind.ACCIDENT -> Icons.Filled.Warning
    IncidentKind.DAMAGE -> Icons.Filled.DirectionsCar
    IncidentKind.MECHANICAL -> Icons.Filled.Build
}

private fun statusTone(status: IncidentStatus): Color = when (status) {
    IncidentStatus.OPEN -> Palette.danger
    IncidentStatus.REVIEW -> Palette.amber
    IncidentStatus.CLOSED -> Palette.volt
}
