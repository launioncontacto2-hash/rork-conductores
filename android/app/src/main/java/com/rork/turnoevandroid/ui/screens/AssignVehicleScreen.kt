package com.rork.turnoevandroid.ui.screens

import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
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
import androidx.compose.material.icons.filled.Bolt
import androidx.compose.material.icons.filled.Error
import androidx.compose.material.icons.filled.Keyboard
import androidx.compose.material.icons.filled.QrCode
import androidx.compose.material.icons.filled.QrCodeScanner
import androidx.compose.material.icons.filled.Speed
import androidx.compose.material.icons.filled.Verified
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
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
import com.rork.turnoevandroid.domain.AssignmentIssue
import com.rork.turnoevandroid.domain.AssignmentIssueCode
import com.rork.turnoevandroid.domain.Vehicle
import com.rork.turnoevandroid.domain.VehicleStatus
import com.rork.turnoevandroid.ui.components.BatteryPill
import com.rork.turnoevandroid.ui.components.BigButton
import com.rork.turnoevandroid.ui.components.BigNumberField
import com.rork.turnoevandroid.ui.components.ButtonTone
import com.rork.turnoevandroid.ui.components.DetailRow
import com.rork.turnoevandroid.ui.components.NoticeBanner
import com.rork.turnoevandroid.ui.components.ScannerFrame
import com.rork.turnoevandroid.ui.components.Tone
import com.rork.turnoevandroid.ui.theme.CapsLabel
import com.rork.turnoevandroid.ui.theme.Palette
import com.rork.turnoevandroid.ui.theme.panel
import com.rork.turnoevandroid.ui.theme.panelFlat
import com.rork.turnoevandroid.util.Fmt

/** QR scan → unit data → start readings → blocking validations. */
@Composable
fun AssignVehicleScreen(
    viewModel: FleetViewModel,
    state: FleetState,
    onDone: () -> Unit,
) {
    var vehicle by remember { mutableStateOf<Vehicle?>(null) }
    var odometer by remember { mutableStateOf("") }
    var battery by remember { mutableStateOf("") }
    var issues by remember { mutableStateOf<List<AssignmentIssue>>(emptyList()) }
    var manualCode by remember { mutableStateOf("") }
    var isManualEntry by remember { mutableStateOf(false) }
    var scanMessage by remember { mutableStateOf<String?>(null) }
    var supervisorNotified by remember { mutableStateOf(false) }

    fun handleDetected(code: String) {
        val normalized = code.trim().uppercase()
        val found = state.vehicles.firstOrNull {
            it.qrCode.uppercase() == normalized || it.internalNumber.uppercase() == normalized
        }
        if (found == null) {
            scanMessage = "El código $normalized no pertenece a la flotilla"
            return
        }
        scanMessage = null
        vehicle = found
        battery = "${found.batteryPct}"
    }

    fun confirm(selected: Vehicle) {
        val odometerValue = odometer.toIntOrNull()
        if (odometerValue == null || odometerValue <= 0) {
            issues = listOf(
                AssignmentIssue(AssignmentIssueCode.ODOMETER_MISMATCH, "Captura el kilometraje de inicio"),
            )
            return
        }
        val batteryValue = battery.toIntOrNull()
        if (batteryValue == null || batteryValue <= 0 || batteryValue > 100) {
            issues = listOf(
                AssignmentIssue(AssignmentIssueCode.LOW_BATTERY, "Captura el nivel de batería de inicio"),
            )
            return
        }
        val found = viewModel.validateAssignment(selected, odometerValue, batteryValue)
        if (found.isNotEmpty()) {
            issues = found
            return
        }
        viewModel.assign(selected, odometerValue, batteryValue)
        onDone()
    }

    Column(
        Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(horizontal = 16.dp)
            .padding(top = 8.dp, bottom = 30.dp),
        verticalArrangement = Arrangement.spacedBy(18.dp),
    ) {
        val selected = vehicle
        if (selected != null) {
            VehicleDetailCard(selected)

            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                BigNumberField(
                    title = "Kilometraje de inicio",
                    placeholder = "${selected.odometerKm}",
                    value = odometer,
                    onValueChange = { odometer = it },
                    icon = Icons.Filled.Speed,
                )
                Text(
                    "Usar registrado ${Fmt.km(selected.odometerKm)}",
                    style = TextStyle(fontSize = 12.sp, fontWeight = FontWeight.SemiBold, color = Palette.textMuted),
                    modifier = Modifier
                        .clip(CircleShape)
                        .background(Palette.surfaceRaised)
                        .border(1.dp, Palette.hairline, CircleShape)
                        .clickable { odometer = "${selected.odometerKm}" }
                        .padding(horizontal = 12.dp, vertical = 8.dp),
                )
            }

            BigNumberField(
                title = "Nivel de batería de inicio",
                placeholder = "${selected.batteryPct}",
                value = battery,
                onValueChange = { battery = it },
                icon = Icons.Filled.Bolt,
            )

            BigButton("Confirmar asignación", icon = Icons.Filled.Verified) { confirm(selected) }
            BigButton("Escanear otra unidad", icon = Icons.Filled.QrCodeScanner, tone = ButtonTone.OUTLINE) {
                vehicle = null
                odometer = ""
                battery = ""
                manualCode = ""
                isManualEntry = false
            }
        } else {
            Box(
                Modifier
                    .fillMaxWidth()
                    .height(320.dp)
                    .clip(RoundedCornerShape(26.dp))
                    .background(Color.Black)
                    .border(1.dp, Palette.hairline, RoundedCornerShape(26.dp)),
            ) {
                Box(
                    Modifier
                        .fillMaxSize()
                        .background(
                            Brush.verticalGradient(
                                listOf(Palette.canvas, Palette.surface.copy(alpha = 0.4f), Palette.canvas),
                            ),
                        ),
                )
                ScannerFrame()
                Row(
                    Modifier
                        .align(Alignment.BottomCenter)
                        .padding(bottom = 14.dp)
                        .clip(CircleShape)
                        .background(Color.Black.copy(alpha = 0.65f))
                        .padding(horizontal = 12.dp, vertical = 8.dp),
                    horizontalArrangement = Arrangement.spacedBy(6.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Icon(Icons.Filled.QrCodeScanner, null, Modifier.size(14.dp), tint = Palette.volt)
                    Text(
                        "Centra el código QR del parabrisas",
                        style = TextStyle(fontSize = 12.sp, fontWeight = FontWeight.SemiBold, color = Palette.textPrimary),
                    )
                }
            }

            scanMessage?.let { message ->
                NoticeBanner(Icons.Filled.Error, message, tone = Tone.DANGER)
            }

            if (supervisorNotified) {
                NoticeBanner(
                    icon = Icons.Filled.Verified,
                    title = "Supervisor notificado",
                    message = "Se envió el reporte a la estación con el detalle de la unidad.",
                    tone = Tone.VOLT,
                )
            }

            if (isManualEntry) {
                Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    BigNumberField(
                        title = "Número interno",
                        placeholder = "014",
                        value = manualCode,
                        onValueChange = { manualCode = it },
                        icon = Icons.Filled.QrCode,
                    )
                    BigButton(
                        title = "Validar unidad",
                        icon = Icons.Filled.QrCode,
                        enabled = manualCode.trim().length >= 3,
                    ) {
                        handleDetected("TEV-${manualCode.trim()}")
                    }
                }
            } else {
                Row(
                    Modifier
                        .fillMaxWidth()
                        .height(48.dp)
                        .panelFlat()
                        .clickable { isManualEntry = true },
                    horizontalArrangement = Arrangement.Center,
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Icon(Icons.Filled.Keyboard, null, Modifier.size(18.dp), tint = Palette.textMuted)
                    Spacer(Modifier.size(8.dp))
                    Text(
                        "Capturar número interno",
                        style = TextStyle(fontSize = 14.sp, fontWeight = FontWeight.SemiBold, color = Palette.textPrimary),
                    )
                }
            }

            // Station units — lets the driver pick a unit when the sticker is damaged.
            Row(
                Modifier
                    .fillMaxWidth()
                    .horizontalScroll(rememberScrollState()),
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                state.vehicles.forEach { item ->
                    Text(
                        item.qrCode,
                        style = TextStyle(fontSize = 12.sp, fontWeight = FontWeight.SemiBold, color = Palette.textMuted),
                        modifier = Modifier
                            .clip(CircleShape)
                            .background(Palette.surfaceRaised)
                            .border(1.dp, Palette.hairline, CircleShape)
                            .clickable { handleDetected(item.qrCode) }
                            .padding(horizontal = 12.dp, vertical = 8.dp),
                    )
                }
            }

            Text(
                "La lectura valida turno, autorización, batería y kilometraje.",
                style = TextStyle(fontSize = 11.sp, color = Palette.textMuted),
            )
        }
    }

    if (issues.isNotEmpty()) {
        AlertDialog(
            onDismissRequest = { issues = emptyList() },
            containerColor = Palette.surface,
            title = {
                Text(
                    "Asignación bloqueada",
                    style = TextStyle(fontSize = 18.sp, fontWeight = FontWeight.Black, color = Palette.textPrimary),
                )
            },
            text = {
                Text(
                    issues.joinToString("\n\n") { it.message },
                    style = TextStyle(fontSize = 14.sp, color = Palette.textMuted),
                )
            },
            confirmButton = {
                TextButton(onClick = {
                    supervisorNotified = true
                    issues = emptyList()
                }) {
                    Text("Notificar a supervisor", color = Palette.danger)
                }
            },
            dismissButton = {
                TextButton(onClick = { issues = emptyList() }) {
                    Text("Corregir datos", color = Palette.textMuted)
                }
            },
        )
    }
}

@Composable
private fun VehicleDetailCard(vehicle: Vehicle) {
    Column(
        Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(26.dp))
            .panel(),
    ) {
        Box(
            Modifier
                .fillMaxWidth()
                .height(150.dp)
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
                    CapsLabel("Número interno")
                    Text(
                        vehicle.internalNumber,
                        style = TextStyle(fontSize = 28.sp, fontWeight = FontWeight.Black, color = Palette.textPrimary),
                    )
                }
                Spacer(Modifier.weight(1f))
                BatteryPill(vehicle.batteryPct)
            }
        }
        DetailRow("Modelo", vehicle.model)
        DetailRow("Placas", vehicle.plates)
        DetailRow("Kilometraje registrado", Fmt.km(vehicle.odometerKm))
        DetailRow("Nivel de batería", "${vehicle.batteryPct}%")
        DetailRow("Estación asignada", vehicle.station)
        DetailRow(
            "Estado",
            vehicle.status.label,
            tone = if (vehicle.status == VehicleStatus.AVAILABLE) Palette.textPrimary else Palette.danger,
            showDivider = false,
        )
    }
}

@Composable
private fun ScreenTitleSpacer() {
    Text("", textAlign = TextAlign.Center)
}
