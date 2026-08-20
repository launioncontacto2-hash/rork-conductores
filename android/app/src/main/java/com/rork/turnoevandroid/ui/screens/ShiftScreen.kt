package com.rork.turnoevandroid.ui.screens

import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
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
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Bolt
import androidx.compose.material.icons.filled.CameraAlt
import androidx.compose.material.icons.filled.DirectionsCar
import androidx.compose.material.icons.filled.Flag
import androidx.compose.material.icons.filled.Notifications
import androidx.compose.material.icons.filled.NotificationsActive
import androidx.compose.material.icons.filled.Payments
import androidx.compose.material.icons.filled.Place
import androidx.compose.material.icons.filled.QrCodeScanner
import androidx.compose.material.icons.filled.Route
import androidx.compose.material.icons.filled.Timer
import androidx.compose.material.icons.filled.Verified
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.rork.turnoevandroid.FleetViewModel
import com.rork.turnoevandroid.R
import com.rork.turnoevandroid.data.FleetState
import com.rork.turnoevandroid.domain.ActiveShift
import com.rork.turnoevandroid.domain.InspectionSlot
import com.rork.turnoevandroid.domain.ShiftRules
import com.rork.turnoevandroid.domain.Vehicle
import com.rork.turnoevandroid.ui.components.BatteryPill
import com.rork.turnoevandroid.ui.components.BigButton
import com.rork.turnoevandroid.ui.components.DemoClockButton
import com.rork.turnoevandroid.ui.components.Hairline
import com.rork.turnoevandroid.ui.components.NoticeBanner
import com.rork.turnoevandroid.ui.components.ProgressTrack
import com.rork.turnoevandroid.ui.components.StatTile
import com.rork.turnoevandroid.ui.components.Tone
import com.rork.turnoevandroid.ui.components.VerticalHairline
import com.rork.turnoevandroid.ui.theme.CapsLabel
import com.rork.turnoevandroid.ui.theme.Palette
import com.rork.turnoevandroid.ui.theme.TabularNumbers
import com.rork.turnoevandroid.ui.theme.panel
import com.rork.turnoevandroid.ui.theme.panelFlat
import com.rork.turnoevandroid.util.Fmt

/** Main screen: driver identity, assigned vehicle, shift clock and live metrics. */
@Composable
fun ShiftScreen(
    viewModel: FleetViewModel,
    state: FleetState,
    now: Long,
    onAssign: () -> Unit,
    onInspection: () -> Unit,
    onIncome: () -> Unit,
    onIncident: () -> Unit,
    onFinish: () -> Unit,
    onNotices: () -> Unit,
) {
    val driver = viewModel.driver
    val shift = state.activeShift
    val vehicle = viewModel.activeVehicle(state)

    Column(
        Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(horizontal = 16.dp)
            .padding(top = 12.dp, bottom = 28.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Box(
                Modifier
                    .size(24.dp)
                    .clickable { onNotices() },
                contentAlignment = Alignment.Center,
            ) {
                Icon(
                    if (state.unreadNoticeCount > 0) Icons.Filled.NotificationsActive else Icons.Filled.Notifications,
                    "Avisos de la estación",
                    tint = if (state.unreadNoticeCount > 0) Palette.volt else Palette.textPrimary,
                )
                if (state.unreadNoticeCount > 0) {
                    Box(
                        Modifier
                            .align(Alignment.TopEnd)
                            .size(8.dp)
                            .background(Palette.danger, CircleShape),
                    )
                }
            }
            Spacer(Modifier.width(12.dp))
            Text(
                "Turno",
                style = TextStyle(fontSize = 17.sp, fontWeight = FontWeight.Black, color = Palette.textPrimary),
            )
            Spacer(Modifier.weight(1f))
            DemoClockButton(viewModel, now, state.clockOffsetMinutes)
        }

        // Driver header
        Row(
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Box {
                Image(
                    painter = painterResource(R.drawable.driver_portrait),
                    contentDescription = driver.name,
                    contentScale = ContentScale.Crop,
                    modifier = Modifier
                        .size(56.dp)
                        .clip(RoundedCornerShape(18.dp))
                        .border(1.dp, Palette.volt.copy(alpha = 0.5f), RoundedCornerShape(18.dp)),
                )
                if (shift != null) {
                    Box(
                        Modifier
                            .align(Alignment.BottomEnd)
                            .size(22.dp)
                            .background(Palette.volt, CircleShape)
                            .border(2.dp, Palette.canvas, CircleShape),
                        contentAlignment = Alignment.Center,
                    ) {
                        Icon(Icons.Filled.Bolt, null, Modifier.size(12.dp), tint = Palette.canvas)
                    }
                }
            }
            Column(verticalArrangement = Arrangement.spacedBy(3.dp)) {
                Text(
                    driver.name,
                    style = TextStyle(fontSize = 17.sp, fontWeight = FontWeight.Black, color = Palette.textPrimary),
                    maxLines = 1,
                )
                Row(
                    horizontalArrangement = Arrangement.spacedBy(4.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Icon(Icons.Filled.Place, null, Modifier.size(11.dp), tint = Palette.textMuted)
                    Text(
                        "${driver.station} · ${driver.employeeNumber}",
                        style = TextStyle(fontSize = 11.sp, color = Palette.textMuted),
                        maxLines = 1,
                    )
                }
            }
        }

        ShiftHero(viewModel, state, now, onAssign)

        if (shift != null && shift.lateMinutes > 0) {
            NoticeBanner(
                icon = Icons.Filled.Warning,
                title = "${Fmt.firstName(driver.name)}, tienes un atraso de " +
                    "${Fmt.lateText(shift.lateMinutes)} minutos.",
                message = "Recupéralos mañana en tu ventana de ${driver.slot.paybackWindowLabel}.",
                tone = Tone.AMBER,
            )
        }

        if (shift != null && !viewModel.isInspectionComplete) {
            NoticeBanner(
                icon = Icons.Filled.CameraAlt,
                title = "Registro de inicio incompleto",
                message = "Faltan ${InspectionSlot.entries.size - viewModel.capturedPhotoCount} " +
                    "fotografías del vehículo.",
                tone = Tone.INFO,
                onClick = onInspection,
            )
        }

        if (shift == null &&
            ShiftRules.isPaybackWindow(driver, now) &&
            viewModel.weeklyLateDebt(now) > 0
        ) {
            NoticeBanner(
                icon = Icons.Filled.Timer,
                title = "Ventana de pago de atraso abierta (${driver.slot.paybackWindowLabel})",
                message = "Debes ${viewModel.weeklyLateDebt(now)} min esta semana. Regístralo en Historial.",
                tone = Tone.VOLT,
            )
        }

        VehicleCard(vehicle)

        if (shift != null) {
            LiveMetrics(viewModel, shift, now)
            QuickActions(onIncome = onIncome, onIncident = onIncident, onFinish = onFinish)
        }
    }
}

@Composable
private fun ShiftHero(viewModel: FleetViewModel, state: FleetState, now: Long, onAssign: () -> Unit) {
    val driver = viewModel.driver
    val shift = state.activeShift
    val isActive = shift != null
    val canStart = ShiftRules.isCorrectShiftMoment(driver, now)
    val statusTone = when {
        isActive -> Palette.volt
        canStart -> Palette.info
        else -> Palette.textMuted
    }

    Box(
        Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(26.dp))
            .panel(),
    ) {
        Box(
            Modifier
                .align(Alignment.TopEnd)
                .size(190.dp)
                .background(
                    Brush.radialGradient(
                        listOf(Palette.volt.copy(alpha = 0.14f), Color.Transparent),
                    ),
                ),
        )
        Column(Modifier.padding(18.dp)) {
            Row(Modifier.fillMaxWidth()) {
                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    CapsLabel(if (isActive) "Turno en curso" else "Próximo turno")
                    Text(
                        "${driver.slot.label} · ${driver.group.label}",
                        style = TextStyle(fontSize = 19.sp, fontWeight = FontWeight.Black, color = Palette.textPrimary),
                    )
                    Text(
                        Fmt.dateLong(now),
                        style = TextStyle(fontSize = 12.sp, color = Palette.textMuted),
                    )
                }
                Text(
                    when {
                        isActive -> "ACTIVO"
                        canStart -> "PUEDES INICIAR"
                        else -> "FUERA DE HORARIO"
                    },
                    style = TextStyle(
                        fontSize = 9.sp,
                        fontWeight = FontWeight.Black,
                        letterSpacing = 1.2.sp,
                        color = statusTone,
                    ),
                    modifier = Modifier
                        .clip(CircleShape)
                        .background(statusTone.copy(alpha = 0.13f))
                        .padding(horizontal = 9.dp, vertical = 5.dp),
                )
            }

            if (shift != null) {
                val elapsed = viewModel.elapsedSeconds(now)
                Spacer(Modifier.height(18.dp))
                Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.Bottom) {
                    Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                        CapsLabel("Tiempo transcurrido")
                        Text(
                            Fmt.stopwatch(elapsed),
                            style = TextStyle(
                                fontSize = 38.sp,
                                fontWeight = FontWeight.Black,
                                fontFamily = TabularNumbers,
                                color = Palette.volt,
                            ),
                            maxLines = 1,
                        )
                    }
                    Column(horizontalAlignment = Alignment.End, verticalArrangement = Arrangement.spacedBy(2.dp)) {
                        CapsLabel("Inicio")
                        Text(
                            Fmt.clock(shift.startedAt),
                            style = TextStyle(
                                fontSize = 20.sp,
                                fontWeight = FontWeight.Bold,
                                fontFamily = TabularNumbers,
                                color = Palette.textPrimary,
                            ),
                        )
                        Text(
                            "Programado ${Fmt.clock(shift.scheduledStartAt)}",
                            style = TextStyle(fontSize = 10.sp, color = Palette.textMuted),
                        )
                    }
                }
                Spacer(Modifier.height(14.dp))
                ProgressTrack(value = elapsed / 60.0, goal = (9 * 60).toDouble())
                Spacer(Modifier.height(6.dp))
                Row(Modifier.fillMaxWidth()) {
                    Text(
                        "8 h efectivas + 1 h comida",
                        style = TextStyle(fontSize = 10.sp, color = Palette.textMuted),
                    )
                    Spacer(Modifier.weight(1f))
                    Text(
                        driver.slot.rangeLabel,
                        style = TextStyle(fontSize = 10.sp, color = Palette.textMuted),
                    )
                }
            } else {
                Spacer(Modifier.height(16.dp))
                Text(
                    driver.slot.rangeLabel,
                    style = TextStyle(
                        fontSize = 30.sp,
                        fontWeight = FontWeight.Black,
                        fontFamily = TabularNumbers,
                        color = Palette.textPrimary,
                    ),
                )
                Spacer(Modifier.height(6.dp))
                Text(
                    "Escanea el QR de tu unidad para iniciar. Tolerancia de 10 minutos después de la hora programada.",
                    style = TextStyle(fontSize = 13.sp, color = Palette.textMuted),
                )
                Spacer(Modifier.height(16.dp))
                BigButton("Escanear vehículo", icon = Icons.Filled.QrCodeScanner, onClick = onAssign)
            }
        }
    }
}

@Composable
private fun VehicleCard(vehicle: Vehicle?) {
    if (vehicle == null) {
        Row(
            Modifier
                .fillMaxWidth()
                .panelFlat()
                .padding(14.dp),
            horizontalArrangement = Arrangement.spacedBy(10.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Icon(Icons.Filled.DirectionsCar, null, Modifier.size(18.dp), tint = Palette.textMuted)
            Text(
                "Sin vehículo asignado. Tu unidad aparecerá aquí al iniciar turno.",
                style = TextStyle(fontSize = 13.sp, color = Palette.textMuted),
            )
        }
        return
    }

    Column(
        Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(26.dp))
            .panel(),
    ) {
        Box(
            Modifier
                .fillMaxWidth()
                .height(128.dp)
                .background(Color.Black),
        ) {
            Image(
                painter = painterResource(R.drawable.vehicle_photo),
                contentDescription = vehicle.model,
                contentScale = ContentScale.Crop,
                modifier = Modifier.fillMaxSize(),
            )
            Box(
                Modifier
                    .fillMaxSize()
                    .background(
                        Brush.verticalGradient(
                            listOf(Color.Transparent, Palette.surface.copy(alpha = 0.95f)),
                        ),
                    ),
            )
            Row(
                Modifier
                    .align(Alignment.BottomStart)
                    .fillMaxWidth()
                    .padding(14.dp),
                verticalAlignment = Alignment.Bottom,
            ) {
                Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                    CapsLabel("Unidad asignada")
                    Text(
                        vehicle.internalNumber,
                        style = TextStyle(
                            fontSize = 22.sp,
                            fontWeight = FontWeight.Black,
                            color = Palette.textPrimary,
                        ),
                    )
                }
                Spacer(Modifier.weight(1f))
                BatteryPill(vehicle.batteryPct)
            }
        }
        Hairline()
        Row(
            Modifier
                .fillMaxWidth()
                .padding(vertical = 10.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            VehicleCell("Modelo", vehicle.model.split(" ").take(2).joinToString(" "), Modifier.weight(1f))
            VerticalHairline()
            VehicleCell("Placas", vehicle.plates, Modifier.weight(1f))
            VerticalHairline()
            VehicleCell("Odómetro", Fmt.km(vehicle.odometerKm), Modifier.weight(1f))
        }
    }
}

@Composable
private fun VehicleCell(label: String, value: String, modifier: Modifier = Modifier) {
    Column(
        modifier,
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        CapsLabel(label)
        Text(
            value,
            style = TextStyle(
                fontSize = 12.sp,
                fontWeight = FontWeight.Bold,
                fontFamily = TabularNumbers,
                color = Palette.textPrimary,
            ),
            maxLines = 1,
            textAlign = TextAlign.Center,
        )
    }
}

@Composable
private fun LiveMetrics(viewModel: FleetViewModel, shift: ActiveShift, now: Long) {
    val paceTarget = ShiftRules.paceTargetMxn(shift.group, viewModel.elapsedSeconds(now) / 60.0)
    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            StatTile(
                label = "Km recorridos",
                value = Fmt.km(viewModel.estimatedKmDriven(now)),
                hint = "GPS simulado",
                icon = Icons.Filled.Route,
                modifier = Modifier.weight(1f),
            )
            StatTile(
                label = "Ingresos",
                value = Fmt.mxn(shift.earningsMxn),
                hint = "Ritmo objetivo ${Fmt.mxn(paceTarget)}",
                tone = if (shift.earningsMxn >= paceTarget) Tone.VOLT else Tone.AMBER,
                icon = Icons.Filled.Payments,
                modifier = Modifier.weight(1f),
            )
        }
        Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            StatTile(
                label = "Viajes",
                value = "${shift.trips} / ${viewModel.goals.tripsPerDay}",
                tone = if (shift.trips >= viewModel.goals.tripsPerDay) Tone.VOLT else Tone.NEUTRAL,
                icon = Icons.Filled.Flag,
                modifier = Modifier.weight(1f),
            )
            StatTile(
                label = "Batería inicio",
                value = "${shift.startBatteryPct}%",
                hint = "Odómetro ${Fmt.km(shift.startOdometerKm)}",
                icon = Icons.Filled.Bolt,
                modifier = Modifier.weight(1f),
            )
        }
    }
}

@Composable
private fun QuickActions(onIncome: () -> Unit, onIncident: () -> Unit, onFinish: () -> Unit) {
    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            ActionCard(
                title = "Registrar ingreso",
                icon = Icons.Filled.Payments,
                tint = Palette.volt,
                modifier = Modifier.weight(1f),
                onClick = onIncome,
            )
            ActionCard(
                title = "Reportar incidencia",
                icon = Icons.Filled.Warning,
                tint = Palette.danger,
                modifier = Modifier.weight(1f),
                onClick = onIncident,
            )
        }
        Row(
            Modifier
                .fillMaxWidth()
                .height(58.dp)
                .clip(RoundedCornerShape(18.dp))
                .background(Palette.volt.copy(alpha = 0.12f))
                .border(1.dp, Palette.volt.copy(alpha = 0.5f), RoundedCornerShape(18.dp))
                .clickable { onFinish() },
            horizontalArrangement = Arrangement.Center,
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Icon(Icons.Filled.Verified, null, Modifier.size(20.dp), tint = Palette.volt)
            Spacer(Modifier.width(10.dp))
            Text(
                "Finalizar turno",
                style = TextStyle(fontSize = 16.sp, fontWeight = FontWeight.Bold, color = Palette.volt),
            )
        }
    }
}

@Composable
private fun ActionCard(
    title: String,
    icon: ImageVector,
    tint: Color,
    modifier: Modifier = Modifier,
    onClick: () -> Unit,
) {
    Column(
        modifier
            .height(92.dp)
            .clip(RoundedCornerShape(18.dp))
            .background(tint.copy(alpha = 0.1f))
            .border(1.dp, tint.copy(alpha = 0.35f), RoundedCornerShape(18.dp))
            .clickable { onClick() }
            .padding(10.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center,
    ) {
        Icon(icon, null, Modifier.size(24.dp), tint = tint)
        Spacer(Modifier.height(8.dp))
        Text(
            title,
            style = TextStyle(fontSize = 12.sp, fontWeight = FontWeight.Bold, color = Palette.textPrimary),
            textAlign = TextAlign.Center,
        )
    }
}
