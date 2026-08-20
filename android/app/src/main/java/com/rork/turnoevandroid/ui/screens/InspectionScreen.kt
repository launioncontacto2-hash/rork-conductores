package com.rork.turnoevandroid.ui.screens

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.DirectionsCar
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.rork.turnoevandroid.FleetViewModel
import com.rork.turnoevandroid.data.FleetState
import com.rork.turnoevandroid.domain.InspectionSlot
import com.rork.turnoevandroid.ui.components.BigButton
import com.rork.turnoevandroid.ui.components.PhotoSlot
import com.rork.turnoevandroid.ui.theme.CapsLabel
import com.rork.turnoevandroid.ui.theme.Palette
import com.rork.turnoevandroid.ui.theme.TabularNumbers
import com.rork.turnoevandroid.ui.theme.panelFlat
import com.rork.turnoevandroid.util.Fmt

/** Start-of-shift registration: odometer, battery and the four body photos. */
@Composable
fun InspectionScreen(
    viewModel: FleetViewModel,
    state: FleetState,
    now: Long,
    thumbnails: Map<String, android.graphics.Bitmap>,
    onDone: () -> Unit,
) {
    val shift = state.activeShift
    val vehicle = viewModel.activeVehicle(state)

    if (shift == null || vehicle == null) {
        Column(
            Modifier
                .fillMaxSize()
                .padding(32.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.Center,
        ) {
            Icon(Icons.Filled.DirectionsCar, null, tint = Palette.textMuted)
            Spacer(Modifier.padding(6.dp))
            Text(
                "Sin turno activo",
                style = TextStyle(fontSize = 18.sp, fontWeight = FontWeight.Black, color = Palette.textPrimary),
            )
            Text(
                "Escanea el QR de tu unidad para iniciar el registro.",
                style = TextStyle(fontSize = 13.sp, color = Palette.textMuted),
                textAlign = TextAlign.Center,
            )
        }
        return
    }

    Column(
        Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(horizontal = 16.dp)
            .padding(top = 8.dp, bottom = 30.dp),
        verticalArrangement = Arrangement.spacedBy(18.dp),
    ) {
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            CapsLabel("Registro automático")
            Spacer(Modifier.weight(1f))
            Text(
                "${viewModel.capturedPhotoCount}/${InspectionSlot.entries.size}",
                style = TextStyle(
                    fontSize = 13.sp,
                    fontWeight = FontWeight.Bold,
                    fontFamily = TabularNumbers,
                    color = Palette.volt,
                ),
            )
        }

        Column(
            Modifier
                .fillMaxWidth()
                .panelFlat(22.dp)
                .padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            listOf(
                "Fecha" to Fmt.dateShort(now),
                "Hora" to Fmt.clockSeconds(now),
                "Conductor" to viewModel.driver.name,
                "Vehículo" to "${vehicle.internalNumber} · ${vehicle.plates}",
                "Odómetro inicio" to Fmt.km(shift.startOdometerKm),
                "Batería inicio" to "${shift.startBatteryPct}%",
            ).chunked(2).forEach { row ->
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    row.forEach { (label, value) ->
                        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
                            CapsLabel(label)
                            Text(
                                value,
                                style = TextStyle(
                                    fontSize = 13.sp,
                                    fontWeight = FontWeight.Bold,
                                    color = Palette.textPrimary,
                                ),
                                maxLines = 2,
                            )
                        }
                    }
                }
            }
        }

        InspectionSlot.entries.chunked(2).forEach { row ->
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                row.forEach { slot ->
                    PhotoSlot(
                        title = slot.title,
                        hint = slot.hint,
                        captured = shift.photos.containsKey(slot.name),
                        thumbnail = thumbnails[slot.name],
                        onCapture = { bitmap -> viewModel.saveInspectionPhoto(slot, bitmap) },
                        modifier = Modifier.weight(1f),
                    )
                }
            }
        }

        Text(
            "Las fotografías se archivan en el historial de la unidad. En la siguiente versión el " +
                "odómetro se leerá automáticamente por OCR.",
            style = TextStyle(fontSize = 11.sp, color = Palette.textMuted),
        )

        BigButton(
            title = if (viewModel.isInspectionComplete) {
                "Confirmar inicio de turno"
            } else {
                "Faltan ${InspectionSlot.entries.size - viewModel.capturedPhotoCount} fotografías"
            },
            icon = Icons.Filled.CheckCircle,
            enabled = viewModel.isInspectionComplete,
            onClick = onDone,
        )
    }
}
