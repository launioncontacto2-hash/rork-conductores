package com.rork.turnoevandroid.ui.screens

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Flag
import androidx.compose.material.icons.filled.Payments
import androidx.compose.material.icons.filled.Verified
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.rork.turnoevandroid.FleetViewModel
import com.rork.turnoevandroid.data.FleetState
import com.rork.turnoevandroid.domain.IncomePlatform
import com.rork.turnoevandroid.ui.components.BigButton
import com.rork.turnoevandroid.ui.components.BigNumberField
import com.rork.turnoevandroid.ui.components.Chip
import com.rork.turnoevandroid.ui.components.PhotoSlot
import com.rork.turnoevandroid.ui.components.StatTile
import com.rork.turnoevandroid.ui.components.Tone
import com.rork.turnoevandroid.ui.theme.CapsLabel
import com.rork.turnoevandroid.ui.theme.Palette
import com.rork.turnoevandroid.util.Fmt

/** Income capture: amount, trips, platform and the app-screenshot evidence. */
@Composable
fun IncomeScreen(
    viewModel: FleetViewModel,
    state: FleetState,
    now: Long,
    onDone: () -> Unit,
) {
    var amount by remember { mutableStateOf("") }
    var trips by remember { mutableStateOf("") }
    var platform by remember { mutableStateOf(IncomePlatform.UBER) }
    var hasEvidence by remember { mutableStateOf(false) }
    var evidence by remember { mutableStateOf<android.graphics.Bitmap?>(null) }
    var errorMessage by remember { mutableStateOf<String?>(null) }

    val goals = viewModel.goals
    val earnedToday = viewModel.earnedToday(now)
    val tripsToday = viewModel.tripsToday(now)

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
                label = "Acumulado hoy",
                value = Fmt.mxn(earnedToday),
                hint = "Meta ${Fmt.mxn(goals.dailyMxn)}",
                tone = if (earnedToday >= goals.dailyMxn) Tone.VOLT else Tone.NEUTRAL,
                icon = Icons.Filled.Payments,
                modifier = Modifier.weight(1f),
            )
            StatTile(
                label = "Viajes hoy",
                value = "$tripsToday / ${goals.tripsPerDay}",
                icon = Icons.Filled.Flag,
                modifier = Modifier.weight(1f),
            )
        }

        BigNumberField(
            title = "Monto facturado",
            placeholder = "0",
            value = amount,
            onValueChange = { amount = it },
            icon = Icons.Filled.Payments,
        )

        BigNumberField(
            title = "Viajes realizados",
            placeholder = "0",
            value = trips,
            onValueChange = { trips = it },
            icon = Icons.Filled.Flag,
        )

        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            CapsLabel("Plataforma")
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                IncomePlatform.entries.forEach { option ->
                    Chip(option.label, platform == option, { platform = option })
                }
            }
        }

        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            CapsLabel("Evidencia de la plataforma")
            PhotoSlot(
                title = "Captura de app",
                hint = "Total del día visible",
                captured = hasEvidence,
                thumbnail = evidence,
                onCapture = { bitmap ->
                    evidence = bitmap
                    hasEvidence = true
                },
            )
        }

        errorMessage?.let { message ->
            Text(message, style = TextStyle(fontSize = 13.sp, color = Palette.danger))
        }

        BigButton("Registrar ingreso", icon = Icons.Filled.Verified) {
            val amountValue = amount.toIntOrNull()
            val tripsValue = trips.toIntOrNull() ?: 0
            when {
                amountValue == null || amountValue <= 0 ->
                    errorMessage = "Captura el monto facturado."

                !hasEvidence ->
                    errorMessage = "Adjunta la captura de la plataforma."

                else -> {
                    errorMessage = null
                    viewModel.registerIncome(amountValue, tripsValue, platform, hasEvidence)
                    onDone()
                }
            }
        }

        Text(
            "En la siguiente versión el monto se sincroniza directo con la API de la plataforma; " +
                "hoy la captura queda como evidencia.",
            style = TextStyle(fontSize = 11.sp, fontWeight = FontWeight.Normal, color = Palette.textMuted),
        )
    }
}
