package com.rork.turnoevandroid.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Build
import androidx.compose.material.icons.filled.DirectionsCar
import androidx.compose.material.icons.filled.Send
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.rork.turnoevandroid.FleetViewModel
import com.rork.turnoevandroid.data.FleetState
import com.rork.turnoevandroid.domain.IncidentKind
import com.rork.turnoevandroid.ui.components.BigButton
import com.rork.turnoevandroid.ui.components.NoticeBanner
import com.rork.turnoevandroid.ui.components.PanelTextField
import com.rork.turnoevandroid.ui.components.PhotoSlot
import com.rork.turnoevandroid.ui.components.Tone
import com.rork.turnoevandroid.ui.theme.CapsLabel
import com.rork.turnoevandroid.ui.theme.Palette

/** Incident report: kind, description and photo evidence sent to the station. */
@Composable
fun IncidentScreen(
    viewModel: FleetViewModel,
    state: FleetState,
    onDone: () -> Unit,
) {
    var kind by remember { mutableStateOf(IncidentKind.DAMAGE) }
    var description by remember { mutableStateOf("") }
    val photos = remember { mutableStateMapOf<Int, android.graphics.Bitmap?>() }
    var errorMessage by remember { mutableStateOf<String?>(null) }
    val vehicle = viewModel.activeVehicle(state) ?: state.vehicles.firstOrNull()

    Column(
        Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(horizontal = 16.dp)
            .padding(top = 8.dp, bottom = 30.dp),
        verticalArrangement = Arrangement.spacedBy(18.dp),
    ) {
        NoticeBanner(
            icon = Icons.Filled.DirectionsCar,
            title = "Unidad ${vehicle?.internalNumber ?: "—"}",
            message = "El reporte llega a la estación ${vehicle?.station ?: ""} y queda en revisión.",
            tone = Tone.INFO,
        )

        Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
            CapsLabel("Tipo de incidencia")
            IncidentKind.entries.forEach { option ->
                val isActive = kind == option
                Row(
                    Modifier
                        .fillMaxWidth()
                        .clip(RoundedCornerShape(18.dp))
                        .background(
                            if (isActive) Palette.danger.copy(alpha = 0.12f) else Palette.surfaceRaised.copy(alpha = 0.6f),
                        )
                        .border(
                            1.dp,
                            if (isActive) Palette.danger.copy(alpha = 0.5f) else Palette.hairline,
                            RoundedCornerShape(18.dp),
                        )
                        .clickable { kind = option }
                        .padding(14.dp),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(12.dp),
                ) {
                    Icon(
                        icon(option),
                        null,
                        Modifier.size(20.dp),
                        tint = if (isActive) Palette.danger else Palette.textMuted,
                    )
                    Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                        Text(
                            option.label,
                            style = TextStyle(fontSize = 14.sp, fontWeight = FontWeight.Bold, color = Palette.textPrimary),
                        )
                        Text(
                            option.hint,
                            style = TextStyle(fontSize = 11.sp, color = Palette.textMuted),
                        )
                    }
                }
            }
        }

        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            CapsLabel("Descripción de lo ocurrido")
            PanelTextField(
                value = description,
                onValueChange = { description = it },
                placeholder = "Describe qué pasó, dónde y si hay terceros involucrados",
                singleLine = false,
                minHeight = 120.dp,
            )
        }

        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            CapsLabel("Evidencia fotográfica")
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                (0..1).forEach { index ->
                    PhotoSlot(
                        title = if (index == 0) "Daño principal" else "Contexto",
                        hint = if (index == 0) "Acércate al detalle" else "Toma general",
                        captured = photos.containsKey(index),
                        thumbnail = photos[index],
                        onCapture = { bitmap -> photos[index] = bitmap },
                        modifier = Modifier.weight(1f),
                    )
                }
            }
        }

        errorMessage?.let { message ->
            Text(message, style = TextStyle(fontSize = 13.sp, color = Palette.danger))
        }

        BigButton("Enviar reporte", icon = Icons.Filled.Send) {
            when {
                description.trim().length < 12 ->
                    errorMessage = "Describe la incidencia con al menos unas palabras."

                photos.isEmpty() ->
                    errorMessage = "Adjunta al menos una fotografía."

                else -> {
                    errorMessage = null
                    viewModel.reportIncident(kind, description.trim(), photos.size)
                    onDone()
                }
            }
        }

        Spacer(Modifier.size(2.dp))
    }
}

private fun icon(kind: IncidentKind): ImageVector = when (kind) {
    IncidentKind.ACCIDENT -> Icons.Filled.Warning
    IncidentKind.DAMAGE -> Icons.Filled.DirectionsCar
    IncidentKind.MECHANICAL -> Icons.Filled.Build
}
