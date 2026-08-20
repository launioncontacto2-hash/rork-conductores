package com.rork.turnoevandroid.ui.screens

import androidx.compose.animation.AnimatedVisibility
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
import androidx.compose.material.icons.filled.AccessAlarm
import androidx.compose.material.icons.filled.AutoAwesome
import androidx.compose.material.icons.filled.Cancel
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.EventAvailable
import androidx.compose.material.icons.filled.ExpandLess
import androidx.compose.material.icons.filled.Info
import androidx.compose.material.icons.filled.Payments
import androidx.compose.material.icons.filled.Remove
import androidx.compose.material.icons.filled.SettingsEthernet
import androidx.compose.material.icons.filled.Shield
import androidx.compose.material.icons.filled.Star
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshots.SnapshotStateMap
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.rork.turnoevandroid.FleetViewModel
import com.rork.turnoevandroid.data.FleetState
import com.rork.turnoevandroid.domain.BonusAlert
import com.rork.turnoevandroid.domain.BonusEvaluation
import com.rork.turnoevandroid.domain.BonusKind
import com.rork.turnoevandroid.domain.BonusRules
import com.rork.turnoevandroid.domain.BonusWeekResult
import com.rork.turnoevandroid.domain.BonusWeekStatus
import com.rork.turnoevandroid.ui.components.BigButton
import com.rork.turnoevandroid.ui.components.ButtonTone
import com.rork.turnoevandroid.ui.components.NoticeBanner
import com.rork.turnoevandroid.ui.components.ProgressTrack
import com.rork.turnoevandroid.ui.components.Tone
import com.rork.turnoevandroid.ui.theme.CapsLabel
import com.rork.turnoevandroid.ui.theme.Palette
import com.rork.turnoevandroid.ui.theme.TabularNumbers
import com.rork.turnoevandroid.ui.theme.panel
import com.rork.turnoevandroid.ui.theme.panelFlat
import com.rork.turnoevandroid.util.Fmt

/**
 * Monthly bonuses: paid at month end, evaluated week by week, plus the
 * recovery program calendar for the weeks the driver already lost.
 */
@Composable
fun BonusesScreen(viewModel: FleetViewModel, state: FleetState, now: Long) {
    val evaluations = viewModel.bonusEvaluations(now)
    val lost = evaluations.filter { it.isLost }
    val expanded: SnapshotStateMap<String, Boolean> = remember { mutableStateMapOf() }
    var alert by remember { mutableStateOf<BonusAlert?>(null) }

    // Weekly cut-off popup: announced once per bonus and week.
    LaunchedEffect(Unit) {
        alert = viewModel.raiseBonusAlert(now)
    }

    Column(
        Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(horizontal = 16.dp)
            .padding(top = 12.dp, bottom = 30.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        Text(
            "Bonos",
            style = TextStyle(fontSize = 17.sp, fontWeight = FontWeight.Black, color = Palette.textPrimary),
        )

        MonthHeader(viewModel, evaluations, now)

        lost.firstOrNull()?.let { first ->
            NoticeBanner(
                icon = Icons.Filled.Warning,
                title = if (lost.size == 1) {
                    "¡${Fmt.firstName(viewModel.driver.name)} has perdido el bono de ${first.kind.shortName}!"
                } else {
                    "Tienes ${lost.size} bonos en riesgo este mes"
                },
                message = "Agenda hoy tu lugar en el programa de recuperación de bonos.",
                tone = Tone.DANGER,
            )
        }

        WeekLegend()

        evaluations.forEach { evaluation ->
            BonusCard(
                evaluation = evaluation,
                isOpen = expanded[evaluation.kind.name] == true,
                onToggle = { expanded[evaluation.kind.name] = expanded[evaluation.kind.name] != true },
            )
        }

        RecoveryProgramSection(
            viewModel = viewModel,
            state = state,
            now = now,
            suggestedBonus = lost.firstOrNull()?.kind ?: BonusKind.PUNCTUALITY,
        )

        if (state.supervisorReports.isNotEmpty()) {
            Column(
                Modifier
                    .fillMaxWidth()
                    .panel()
                    .padding(18.dp),
                verticalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Icon(Icons.Filled.Shield, null, Modifier.size(14.dp), tint = Palette.textMuted)
                    Spacer(Modifier.size(6.dp))
                    Text(
                        "Reportes del supervisor",
                        style = TextStyle(fontSize = 12.sp, fontWeight = FontWeight.SemiBold, color = Palette.textMuted),
                    )
                }
                state.supervisorReports.forEach { report ->
                    Column(
                        Modifier
                            .fillMaxWidth()
                            .panelFlat()
                            .padding(12.dp),
                        verticalArrangement = Arrangement.spacedBy(4.dp),
                    ) {
                        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                            Text(
                                report.kind.label,
                                style = TextStyle(fontSize = 12.sp, fontWeight = FontWeight.Bold, color = Palette.danger),
                            )
                            Spacer(Modifier.weight(1f))
                            Text(
                                Fmt.dateShort(report.createdAt),
                                style = TextStyle(fontSize = 10.sp, color = Palette.textMuted),
                            )
                        }
                        Text(report.note, style = TextStyle(fontSize = 11.sp, color = Palette.textMuted))
                        Text(
                            report.vehicleInternalNumber,
                            style = TextStyle(
                                fontSize = 10.sp,
                                fontWeight = FontWeight.Bold,
                                color = Palette.textMuted.copy(alpha = 0.8f),
                            ),
                        )
                    }
                }
            }
        }
    }

    alert?.let { pending ->
        BonusAlertSheet(pending) { alert = null }
    }
}

@Composable
private fun MonthHeader(viewModel: FleetViewModel, evaluations: List<BonusEvaluation>, now: Long) {
    val payable = evaluations.sumOf { it.payableMxn }
    val total = viewModel.bonusTotalMxn()
    val secured = evaluations.count { it.isSecured }

    Column(
        Modifier
            .fillMaxWidth()
            .panel()
            .padding(18.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        Row(Modifier.fillMaxWidth()) {
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                CapsLabel("Bonos de ${Fmt.monthLong(now)}")
                Text(
                    Fmt.mxn(payable),
                    style = TextStyle(
                        fontSize = 40.sp,
                        fontWeight = FontWeight.Black,
                        fontFamily = TabularNumbers,
                        color = if (payable == total) Palette.volt else Palette.amber,
                    ),
                    maxLines = 1,
                )
                Text(
                    "de ${Fmt.mxn(total)} posibles + calidad de servicio",
                    style = TextStyle(fontSize = 12.sp, color = Palette.textMuted),
                )
            }
            Column(
                Modifier
                    .panelFlat(16.dp)
                    .padding(12.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(2.dp),
            ) {
                Text(
                    "$secured/${evaluations.size}",
                    style = TextStyle(
                        fontSize = 19.sp,
                        fontWeight = FontWeight.Black,
                        fontFamily = TabularNumbers,
                        color = Palette.textPrimary,
                    ),
                )
                CapsLabel("Asegurados")
            }
        }

        ProgressTrack(value = payable.toDouble(), goal = total.toDouble())

        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Icon(Icons.Filled.EventAvailable, null, Modifier.size(14.dp), tint = Palette.volt)
            Text(
                "Se pagan a fin de mes y se evalúan cada semana: debes cumplir las 4 semanas.",
                style = TextStyle(fontSize = 11.sp, color = Palette.textMuted),
            )
        }
    }
}

@Composable
private fun WeekLegend() {
    Row(
        Modifier
            .fillMaxWidth()
            .padding(horizontal = 4.dp),
        horizontalArrangement = Arrangement.spacedBy(14.dp),
    ) {
        listOf(
            BonusWeekStatus.ACHIEVED,
            BonusWeekStatus.LOST,
            BonusWeekStatus.IN_PROGRESS,
            BonusWeekStatus.UPCOMING,
        ).forEach { status ->
            Row(horizontalArrangement = Arrangement.spacedBy(5.dp), verticalAlignment = Alignment.CenterVertically) {
                Box(
                    Modifier
                        .size(8.dp)
                        .background(statusColor(status), CircleShape),
                )
                Text(
                    status.label,
                    style = TextStyle(fontSize = 10.sp, fontWeight = FontWeight.SemiBold, color = Palette.textMuted),
                )
            }
        }
    }
}

@Composable
private fun BonusCard(evaluation: BonusEvaluation, isOpen: Boolean, onToggle: () -> Unit) {
    val kind = evaluation.kind
    val accent = if (evaluation.isLost) Palette.danger else Palette.volt

    Column(
        Modifier
            .fillMaxWidth()
            .panel()
            .padding(18.dp),
        verticalArrangement = Arrangement.spacedBy(14.dp),
    ) {
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            Box(
                Modifier
                    .size(42.dp)
                    .clip(RoundedCornerShape(14.dp))
                    .background(accent.copy(alpha = 0.12f)),
                contentAlignment = Alignment.Center,
            ) {
                Icon(bonusIcon(kind), null, Modifier.size(20.dp), tint = accent)
            }
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                Text(
                    kind.title,
                    style = TextStyle(fontSize = 14.sp, fontWeight = FontWeight.Black, color = Palette.textPrimary),
                )
                Text(
                    evaluation.statusText,
                    style = TextStyle(
                        fontSize = 11.sp,
                        color = if (evaluation.isLost) Palette.danger else Palette.textMuted,
                    ),
                )
            }
            Column(horizontalAlignment = Alignment.End, verticalArrangement = Arrangement.spacedBy(2.dp)) {
                Text(
                    if (kind.isExternal) "Uber" else Fmt.mxn(kind.monthlyMxn),
                    style = TextStyle(
                        fontSize = 14.sp,
                        fontWeight = FontWeight.Black,
                        fontFamily = TabularNumbers,
                        color = if (evaluation.isLost) Palette.textMuted else Palette.volt,
                        textDecoration = if (evaluation.isLost) TextDecoration.LineThrough else TextDecoration.None,
                    ),
                )
                CapsLabel("Mensual")
            }
        }

        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            evaluation.weeks.forEach { result ->
                WeekChip(result, Modifier.weight(1f))
            }
        }

        evaluation.weeks.filter { it.status != BonusWeekStatus.UPCOMING }.forEach { result ->
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Text(
                    "S${result.week.index}",
                    style = TextStyle(
                        fontSize = 10.sp,
                        fontWeight = FontWeight.Black,
                        color = statusColor(result.status),
                    ),
                )
                Text(
                    result.detail,
                    style = TextStyle(fontSize = 11.sp, color = Palette.textMuted),
                    modifier = Modifier.weight(1f),
                )
                Text(
                    result.week.rangeLabel,
                    style = TextStyle(fontSize = 10.sp, color = Palette.textMuted.copy(alpha = 0.7f)),
                )
            }
        }

        Row(
            Modifier
                .fillMaxWidth()
                .clickable { onToggle() },
            horizontalArrangement = Arrangement.spacedBy(6.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Icon(
                if (isOpen) Icons.Filled.ExpandLess else Icons.Filled.Info,
                null,
                Modifier.size(14.dp),
                tint = Palette.info,
            )
            Text(
                if (isOpen) "Ocultar reglas" else "Cómo se gana y cómo se pierde",
                style = TextStyle(fontSize = 11.sp, fontWeight = FontWeight.Bold, color = Palette.info),
            )
        }

        AnimatedVisibility(isOpen) {
            Column(
                Modifier
                    .fillMaxWidth()
                    .panelFlat()
                    .padding(12.dp),
                verticalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                RuleRow(Icons.Filled.CheckCircle, Palette.volt, kind.howToWin)
                RuleRow(Icons.Filled.Cancel, Palette.danger, kind.howToLose)
                if (kind == BonusKind.SERVICE) {
                    RuleRow(
                        Icons.Filled.SettingsEthernet,
                        Palette.info,
                        "En pruebas la métrica es positiva: " +
                            "${Fmt.rating(BonusRules.MOCK_QUALITY_SCORE)} estrellas.",
                    )
                }
            }
        }
    }
}

@Composable
private fun WeekChip(result: BonusWeekResult, modifier: Modifier = Modifier) {
    val tint = statusColor(result.status)
    Column(
        modifier,
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(5.dp),
    ) {
        Box(
            Modifier
                .size(34.dp)
                .background(
                    tint.copy(alpha = if (result.status == BonusWeekStatus.UPCOMING) 0.25f else 0.16f),
                    CircleShape,
                )
                .border(1.dp, tint.copy(alpha = 0.5f), CircleShape),
            contentAlignment = Alignment.Center,
        ) {
            Icon(
                statusIcon(result.status),
                null,
                Modifier.size(14.dp),
                tint = if (result.status == BonusWeekStatus.UPCOMING) Palette.textMuted else tint,
            )
        }
        Text(
            result.week.shortLabel,
            style = TextStyle(fontSize = 10.sp, fontWeight = FontWeight.Bold, color = Palette.textMuted),
        )
    }
}

@Composable
private fun RuleRow(icon: ImageVector, tint: Color, text: String) {
    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        Icon(icon, null, Modifier.size(14.dp), tint = tint)
        Text(text, style = TextStyle(fontSize = 11.sp, color = Palette.textMuted))
    }
}

/** Weekly cut-off popup with the exact operations copy. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun BonusAlertSheet(alert: BonusAlert, onDismiss: () -> Unit) {
    val sheetState = rememberModalBottomSheetState()
    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = sheetState,
        containerColor = Palette.surface,
    ) {
        Column(
            Modifier
                .fillMaxWidth()
                .padding(horizontal = 24.dp)
                .padding(bottom = 32.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(18.dp),
        ) {
            Box(
                Modifier
                    .size(62.dp)
                    .clip(RoundedCornerShape(20.dp))
                    .background(Palette.danger.copy(alpha = 0.14f)),
                contentAlignment = Alignment.Center,
            ) {
                Icon(Icons.Filled.Warning, null, Modifier.size(30.dp), tint = Palette.danger)
            }
            Text(
                alert.message,
                style = TextStyle(fontSize = 19.sp, fontWeight = FontWeight.Black, color = Palette.textPrimary),
                textAlign = TextAlign.Center,
            )
            Text(
                "Corte de la semana ${alert.weekIndex}. El bono de ${alert.kind.shortName} se recupera " +
                    "reservando un día en tu turno opuesto.",
                style = TextStyle(fontSize = 13.sp, color = Palette.textMuted),
                textAlign = TextAlign.Center,
            )
            BigButton("Ir al programa de recuperación", icon = Icons.Filled.EventAvailable, onClick = onDismiss)
            BigButton("Cerrar", tone = ButtonTone.OUTLINE, onClick = onDismiss)
        }
    }
}

private fun statusColor(status: BonusWeekStatus): Color = when (status) {
    BonusWeekStatus.ACHIEVED -> Palette.volt
    BonusWeekStatus.LOST -> Palette.danger
    BonusWeekStatus.IN_PROGRESS -> Palette.info
    BonusWeekStatus.UPCOMING -> Palette.hairline
}

private fun statusIcon(status: BonusWeekStatus): ImageVector = when (status) {
    BonusWeekStatus.ACHIEVED -> Icons.Filled.Check
    BonusWeekStatus.LOST -> Icons.Filled.Close
    BonusWeekStatus.IN_PROGRESS -> Icons.Filled.AccessAlarm
    BonusWeekStatus.UPCOMING -> Icons.Filled.Remove
}

private fun bonusIcon(kind: BonusKind): ImageVector = when (kind) {
    BonusKind.PUNCTUALITY -> Icons.Filled.AccessAlarm
    BonusKind.BILLING -> Icons.Filled.Payments
    BonusKind.CARE -> Icons.Filled.AutoAwesome
    BonusKind.SERVICE -> Icons.Filled.Star
}
