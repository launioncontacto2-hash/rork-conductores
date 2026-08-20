package com.rork.turnoevandroid.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CalendarMonth
import androidx.compose.material.icons.filled.Flag
import androidx.compose.material.icons.filled.Timer
import androidx.compose.material.icons.filled.TrendingUp
import androidx.compose.material.icons.filled.Verified
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.rork.turnoevandroid.FleetViewModel
import com.rork.turnoevandroid.data.FleetState
import com.rork.turnoevandroid.domain.ShiftRules
import com.rork.turnoevandroid.ui.components.NoticeBanner
import com.rork.turnoevandroid.ui.components.ProgressTrack
import com.rork.turnoevandroid.ui.components.RingGauge
import com.rork.turnoevandroid.ui.components.StatTile
import com.rork.turnoevandroid.ui.components.Tone
import com.rork.turnoevandroid.ui.theme.CapsLabel
import com.rork.turnoevandroid.ui.theme.Palette
import com.rork.turnoevandroid.ui.theme.TabularNumbers
import com.rork.turnoevandroid.ui.theme.panel
import com.rork.turnoevandroid.ui.theme.panelFlat
import com.rork.turnoevandroid.util.Fmt

/** Weekly money and trip goals, compared against the driver's live performance. */
@Composable
fun GoalsScreen(viewModel: FleetViewModel, state: FleetState, now: Long) {
    val goals = viewModel.goals
    val earnedToday = viewModel.earnedToday(now)
    val earnedWeek = viewModel.earnedThisWeek(now)
    val tripsToday = viewModel.tripsToday(now)
    val missingToday = (goals.dailyMxn - earnedToday).coerceAtLeast(0)
    val missingTrips = (goals.tripsPerDay - tripsToday).coerceAtLeast(0)

    Column(
        Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(horizontal = 16.dp)
            .padding(top = 12.dp, bottom = 28.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            Text(
                "Metas",
                style = TextStyle(fontSize = 17.sp, fontWeight = FontWeight.Black, color = Palette.textPrimary),
            )
            Spacer(Modifier.weight(1f))
            Text(
                "${viewModel.driver.group.label} · ${viewModel.driver.slot.label}",
                style = TextStyle(fontSize = 11.sp, fontWeight = FontWeight.SemiBold, color = Palette.textMuted),
            )
        }

        // Daily ring
        Column(
            Modifier
                .fillMaxWidth()
                .panel()
                .padding(18.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(14.dp),
        ) {
            RingGauge(
                value = earnedToday.toDouble(),
                goal = goals.dailyMxn.toDouble(),
                headline = Fmt.mxn(earnedToday),
                caption = "de ${Fmt.mxn(goals.dailyMxn)} hoy",
            )
            Row(
                horizontalArrangement = Arrangement.spacedBy(6.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Icon(
                    if (missingToday == 0) Icons.Filled.Verified else Icons.Filled.TrendingUp,
                    null,
                    Modifier.size(16.dp),
                    tint = if (missingToday == 0) Palette.volt else Palette.amber,
                )
                Text(
                    if (missingToday == 0) {
                        "Meta del día cumplida"
                    } else {
                        "Faltan ${Fmt.mxn(missingToday)} para la meta del día"
                    },
                    style = TextStyle(
                        fontSize = 14.sp,
                        fontWeight = FontWeight.Bold,
                        color = if (missingToday == 0) Palette.volt else Palette.amber,
                    ),
                )
            }

            state.activeShift?.let { shift ->
                val paceTarget = ShiftRules.paceTargetMxn(shift.group, viewModel.elapsedSeconds(now) / 60.0)
                val delta = earnedToday - paceTarget
                Column(
                    Modifier
                        .fillMaxWidth()
                        .panelFlat()
                        .padding(12.dp),
                    verticalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                        CapsLabel("Ritmo por hora")
                        Spacer(Modifier.weight(1f))
                        Text(
                            "${if (delta >= 0) "+" else "−"}${Fmt.mxn(kotlin.math.abs(delta))} vs objetivo",
                            style = TextStyle(
                                fontSize = 12.sp,
                                fontWeight = FontWeight.Bold,
                                fontFamily = TabularNumbers,
                                color = if (delta >= 0) Palette.volt else Palette.amber,
                            ),
                        )
                    }
                    ProgressTrack(
                        value = earnedToday.toDouble(),
                        goal = goals.dailyMxn.toDouble(),
                        marker = paceTarget.toDouble(),
                    )
                    Text(
                        "Objetivo acumulado ${Fmt.mxn(paceTarget)} · ${Fmt.mxn(goals.hourlyMxn)} por hora",
                        style = TextStyle(fontSize = 10.sp, color = Palette.textMuted),
                    )
                }
            }
        }

        Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            StatTile("Por hora", Fmt.mxn(goals.hourlyMxn), Modifier.weight(1f))
            StatTile("Por día", Fmt.mxn(goals.dailyMxn), Modifier.weight(1f))
            StatTile("Semana", Fmt.mxn(goals.weeklyMxn), Modifier.weight(1f))
        }

        // Weekly progress
        Column(
            Modifier
                .fillMaxWidth()
                .panel()
                .padding(18.dp),
            verticalArrangement = Arrangement.spacedBy(14.dp),
        ) {
            Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                Icon(Icons.Filled.CalendarMonth, null, Modifier.size(14.dp), tint = Palette.textMuted)
                Spacer(Modifier.size(6.dp))
                Text(
                    "Avance semanal",
                    style = TextStyle(fontSize = 12.sp, fontWeight = FontWeight.SemiBold, color = Palette.textMuted),
                )
                Spacer(Modifier.weight(1f))
                Text(
                    "${Fmt.mxn(earnedWeek)} / ${Fmt.mxn(goals.weeklyMxn)}",
                    style = TextStyle(
                        fontSize = 12.sp,
                        fontWeight = FontWeight.Bold,
                        fontFamily = TabularNumbers,
                        color = Palette.textPrimary,
                    ),
                )
            }
            ProgressTrack(value = earnedWeek.toDouble(), goal = goals.weeklyMxn.toDouble())

            val days = viewModel.weeklyEarningsByDay(now)
            val maxBar = maxOf(goals.dailyMxn.toDouble(), days.maxOfOrNull { it.amount.toDouble() } ?: 1.0)
            Row(
                Modifier
                    .fillMaxWidth()
                    .height(120.dp),
                horizontalArrangement = Arrangement.spacedBy(8.dp),
                verticalAlignment = Alignment.Bottom,
            ) {
                days.forEach { day ->
                    Column(
                        Modifier
                            .weight(1f)
                            .fillMaxHeight(),
                        horizontalAlignment = Alignment.CenterHorizontally,
                        verticalArrangement = Arrangement.Bottom,
                    ) {
                        val ratio = if (maxBar > 0) (day.amount / maxBar).toFloat() else 0f
                        Box(
                            Modifier
                                .fillMaxWidth()
                                .height((96 * ratio).dp.coerceAtLeast(4.dp))
                                .clip(RoundedCornerShape(5.dp))
                                .background(barColor(day.amount, goals.dailyMxn)),
                        )
                        Spacer(Modifier.height(6.dp))
                        Text(
                            day.label,
                            style = TextStyle(
                                fontSize = 10.sp,
                                fontWeight = FontWeight.SemiBold,
                                color = if (day.isToday) Palette.volt else Palette.textMuted,
                            ),
                        )
                    }
                }
            }
        }

        // Trips
        Column(
            Modifier
                .fillMaxWidth()
                .panel()
                .padding(18.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                Icon(Icons.Filled.Flag, null, Modifier.size(14.dp), tint = Palette.textMuted)
                Spacer(Modifier.size(6.dp))
                Text(
                    "Viajes de hoy",
                    style = TextStyle(fontSize = 12.sp, fontWeight = FontWeight.SemiBold, color = Palette.textMuted),
                )
                Spacer(Modifier.weight(1f))
                Text(
                    "$tripsToday / ${goals.tripsPerDay}",
                    style = TextStyle(
                        fontSize = 12.sp,
                        fontWeight = FontWeight.Bold,
                        fontFamily = TabularNumbers,
                        color = Palette.textPrimary,
                    ),
                )
            }
            (0 until goals.tripsPerDay).chunked(7).forEach { row ->
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    row.forEach { index ->
                        Box(
                            Modifier
                                .weight(1f)
                                .height(26.dp)
                                .clip(RoundedCornerShape(6.dp))
                                .background(if (index < tripsToday) Palette.volt else Palette.surfaceRaised),
                        )
                    }
                    repeat(7 - row.size) { Spacer(Modifier.weight(1f)) }
                }
            }
            Text(
                if (missingTrips == 0) {
                    "Meta de viajes cumplida. ¡Excelente ritmo!"
                } else {
                    "Faltan $missingTrips viajes para la meta. Recupéralos hoy o mañana."
                },
                style = TextStyle(fontSize = 11.sp, color = Palette.textMuted),
            )
        }

        val debt = viewModel.weeklyLateDebt(now)
        NoticeBanner(
            icon = Icons.Filled.Timer,
            title = if (debt > 0) "Debes $debt minutos esta semana" else "Sin atrasos esta semana",
            message = "Ventana de pago ${viewModel.driver.slot.paybackWindowLabel} · " +
                "consulta la bitácora en Historial.",
            tone = if (debt > 0) Tone.AMBER else Tone.VOLT,
        )
    }
}

private fun barColor(amount: Int, goal: Int): Color = when {
    amount >= goal -> Palette.volt
    amount > 0 -> Palette.volt.copy(alpha = 0.45f)
    else -> Palette.surfaceRaised
}
