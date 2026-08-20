package com.rork.turnoevandroid.ui.screens

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
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Bolt
import androidx.compose.material.icons.filled.Celebration
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.CheckBox
import androidx.compose.material.icons.filled.CheckBoxOutlineBlank
import androidx.compose.material.icons.filled.Error
import androidx.compose.material.icons.filled.Flag
import androidx.compose.material.icons.filled.Route
import androidx.compose.material.icons.filled.Speed
import androidx.compose.material.icons.filled.Timer
import androidx.compose.material.icons.filled.Verified
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.rork.turnoevandroid.FleetViewModel
import com.rork.turnoevandroid.data.FleetState
import com.rork.turnoevandroid.domain.ShiftRules
import com.rork.turnoevandroid.domain.ShiftSummary
import com.rork.turnoevandroid.ui.components.BigButton
import com.rork.turnoevandroid.ui.components.BigNumberField
import com.rork.turnoevandroid.ui.components.NoticeBanner
import com.rork.turnoevandroid.ui.components.PhotoSlot
import com.rork.turnoevandroid.ui.components.StatTile
import com.rork.turnoevandroid.ui.components.Tone
import com.rork.turnoevandroid.ui.theme.CapsLabel
import com.rork.turnoevandroid.ui.theme.Palette
import com.rork.turnoevandroid.util.Fmt

/** Shift closing: final odometer photo, delivery confirmation and automatic totals. */
@Composable
fun FinishShiftScreen(
    viewModel: FleetViewModel,
    state: FleetState,
    now: Long,
    onDone: () -> Unit,
) {
    val shift = state.activeShift
    val vehicle = viewModel.activeVehicle(state)

    var odometer by remember { mutableStateOf("") }
    var battery by remember { mutableStateOf("") }
    var photo by remember { mutableStateOf<android.graphics.Bitmap?>(null) }
    var hasPhoto by remember { mutableStateOf(false) }
    var confirmDelivery by remember { mutableStateOf(false) }
    var summary by remember { mutableStateOf<ShiftSummary?>(null) }
    var errorMessage by remember { mutableStateOf<String?>(null) }

    if (shift == null || vehicle == null) {
        Column(
            Modifier
                .fillMaxSize()
                .padding(32.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.Center,
        ) {
            Icon(Icons.Filled.Verified, null, tint = Palette.textMuted)
            Text(
                "Sin turno activo",
                style = TextStyle(fontSize = 18.sp, fontWeight = FontWeight.Black, color = Palette.textPrimary),
            )
            Text(
                "No hay un turno por cerrar.",
                style = TextStyle(fontSize = 13.sp, color = Palette.textMuted),
            )
        }
        return
    }

    val suggestedOdometer = shift.startOdometerKm + viewModel.estimatedKmDriven(now)

    Column(
        Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(horizontal = 16.dp)
            .padding(top = 8.dp, bottom = 30.dp),
        verticalArrangement = Arrangement.spacedBy(18.dp),
    ) {
        Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            StatTile(
                label = "Odómetro inicial",
                value = Fmt.km(shift.startOdometerKm),
                icon = Icons.Filled.Speed,
                modifier = Modifier.weight(1f),
            )
            StatTile(
                label = "Km estimados",
                value = Fmt.km(viewModel.estimatedKmDriven(now)),
                hint = "GPS simulado",
                icon = Icons.Filled.Route,
                modifier = Modifier.weight(1f),
            )
        }

        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            BigNumberField(
                title = "Kilometraje final",
                placeholder = "$suggestedOdometer",
                value = odometer,
                onValueChange = { odometer = it },
                icon = Icons.Filled.Speed,
            )
            Text(
                "Usar estimado ${Fmt.km(suggestedOdometer)}",
                style = TextStyle(fontSize = 12.sp, fontWeight = FontWeight.SemiBold, color = Palette.textMuted),
                modifier = Modifier
                    .clip(CircleShape)
                    .background(Palette.surfaceRaised)
                    .border(1.dp, Palette.hairline, CircleShape)
                    .clickable { odometer = "$suggestedOdometer" }
                    .padding(horizontal = 12.dp, vertical = 8.dp),
            )
        }

        BigNumberField(
            title = "Nivel de batería de entrega",
            placeholder = "28",
            value = battery,
            onValueChange = { battery = it },
            icon = Icons.Filled.Bolt,
        )

        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            CapsLabel("Fotografía final del odómetro")
            PhotoSlot(
                title = "Odómetro final",
                hint = "Lectura legible",
                captured = hasPhoto,
                thumbnail = photo,
                onCapture = { bitmap ->
                    photo = bitmap
                    hasPhoto = true
                },
            )
        }

        Row(
            Modifier
                .fillMaxWidth()
                .clip(RoundedCornerShape(20.dp))
                .background(
                    if (confirmDelivery) Palette.volt.copy(alpha = 0.1f) else Palette.surfaceRaised.copy(alpha = 0.6f),
                )
                .border(
                    1.dp,
                    if (confirmDelivery) Palette.volt.copy(alpha = 0.5f) else Palette.hairline,
                    RoundedCornerShape(20.dp),
                )
                .clickable { confirmDelivery = !confirmDelivery }
                .padding(14.dp),
            horizontalArrangement = Arrangement.spacedBy(12.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Icon(
                if (confirmDelivery) Icons.Filled.CheckBox else Icons.Filled.CheckBoxOutlineBlank,
                null,
                Modifier.size(22.dp),
                tint = if (confirmDelivery) Palette.volt else Palette.textMuted,
            )
            Text(
                "Confirmo la entrega de la unidad en ${vehicle.station} conectada al cargador.",
                style = TextStyle(fontSize = 13.sp, fontWeight = FontWeight.SemiBold, color = Palette.textPrimary),
            )
        }

        errorMessage?.let { message ->
            Text(message, style = TextStyle(fontSize = 13.sp, color = Palette.danger))
        }

        BigButton("Cerrar turno", icon = Icons.Filled.Verified) {
            val odometerValue = odometer.toIntOrNull()
            when {
                odometerValue == null || odometerValue < shift.startOdometerKm ->
                    errorMessage = "El kilometraje final debe ser mayor o igual a ${Fmt.km(shift.startOdometerKm)}."

                !hasPhoto -> errorMessage = "Falta la fotografía final del odómetro."

                !confirmDelivery -> errorMessage = "Confirma la entrega de la unidad."

                else -> {
                    errorMessage = null
                    summary = viewModel.finishShift(
                        endOdometerKm = odometerValue,
                        endBatteryPct = battery.toIntOrNull() ?: 20,
                        hasPhoto = true,
                    )
                }
            }
        }
    }

    summary?.let { result ->
        SummarySheet(result, viewModel.driver.name) {
            summary = null
            onDone()
        }
    }
}

/** End-of-shift messages, in the order defined by operations. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun SummarySheet(summary: ShiftSummary, driverName: String, onDismiss: () -> Unit) {
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = sheetState,
        containerColor = Palette.surface,
    ) {
        Column(
            Modifier
                .fillMaxWidth()
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 20.dp)
                .padding(bottom = 32.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            Box(
                Modifier
                    .size(60.dp)
                    .clip(RoundedCornerShape(20.dp))
                    .background(Palette.volt.copy(alpha = 0.14f)),
                contentAlignment = Alignment.Center,
            ) {
                Icon(Icons.Filled.Celebration, null, Modifier.size(30.dp), tint = Palette.volt)
            }
            Text(
                "Turno finalizado",
                style = TextStyle(fontSize = 22.sp, fontWeight = FontWeight.Black, color = Palette.textPrimary),
            )
            Text(
                "${Fmt.firstName(driverName)}, tu turno ha finalizado. ¡Bien hecho!, ahora, " +
                    "vuelve a la estación.",
                style = TextStyle(fontSize = 13.sp, color = Palette.textMuted),
                textAlign = TextAlign.Center,
            )

            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                StatTile("Kilómetros", Fmt.km(summary.kmDriven), Modifier.weight(1f), tone = Tone.VOLT)
                StatTile(
                    "Duración",
                    Fmt.durationText(summary.durationMinutes),
                    Modifier.weight(1f),
                    icon = Icons.Filled.Timer,
                )
            }
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                StatTile("Ingresos", Fmt.mxn(summary.earningsMxn), Modifier.weight(1f))
                StatTile(
                    "Viajes",
                    "${summary.trips} / ${ShiftRules.TRIPS_GOAL_PER_DAY}",
                    Modifier.weight(1f),
                    icon = Icons.Filled.Flag,
                )
            }

            if (summary.missingMxn > 0) {
                NoticeBanner(
                    icon = Icons.Filled.Error,
                    title = "${Fmt.firstName(driverName)}, faltó ${Fmt.mxn(summary.missingMxn)} " +
                        "para llegar a la meta del día.",
                    tone = Tone.AMBER,
                )
            }
            if (summary.missingTrips > 0) {
                NoticeBanner(
                    icon = Icons.Filled.Flag,
                    title = "${Fmt.firstName(driverName)}, faltaron ${summary.missingTrips} viajes para la meta.",
                    message = "Recupéralos mañana.",
                    tone = Tone.AMBER,
                )
            }
            if (summary.lateMinutes > 0) {
                NoticeBanner(
                    icon = Icons.Filled.Timer,
                    title = "Atraso registrado: ${Fmt.lateText(summary.lateMinutes)}",
                    message = "Se agregó a tu bitácora semanal.",
                    tone = Tone.AMBER,
                )
            }

            BigButton("Entendido", icon = Icons.Filled.Check, onClick = onDismiss)
            Spacer(Modifier.size(4.dp))
        }
    }
}
