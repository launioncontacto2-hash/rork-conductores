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
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Article
import androidx.compose.material.icons.filled.Bolt
import androidx.compose.material.icons.filled.CalendarMonth
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.DirectionsCar
import androidx.compose.material.icons.filled.EvStation
import androidx.compose.material.icons.filled.ExpandLess
import androidx.compose.material.icons.filled.ExpandMore
import androidx.compose.material.icons.filled.FormatListNumbered
import androidx.compose.material.icons.filled.Info
import androidx.compose.material.icons.filled.PlayCircle
import androidx.compose.material.icons.filled.Receipt
import androidx.compose.material.icons.filled.Speed
import androidx.compose.material.icons.filled.ThumbUp
import androidx.compose.material.icons.filled.TrendingUp
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
import com.rork.turnoevandroid.domain.CreditAccount
import com.rork.turnoevandroid.domain.CreditMetrics
import com.rork.turnoevandroid.domain.CreditProgram
import com.rork.turnoevandroid.domain.CreditRisk
import com.rork.turnoevandroid.domain.CreditStatus
import com.rork.turnoevandroid.ui.components.BigButton
import com.rork.turnoevandroid.ui.components.ButtonTone
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

/**
 * Credit panel: sale of the fleet's used units on credit.
 * Shows a promotional banner while the driver has no contract, and the full
 * transparency dashboard once the contract is signed.
 */
@Composable
fun CreditScreen(
    viewModel: FleetViewModel,
    state: FleetState,
    now: Long,
    onHowItWorks: () -> Unit,
) {
    var isApprovalOpen by remember { mutableStateOf(false) }
    val credit = state.credit
    val metrics = viewModel.creditMetrics(now)

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
                "Créditos",
                style = TextStyle(fontSize = 17.sp, fontWeight = FontWeight.Black, color = Palette.textPrimary),
            )
            Spacer(Modifier.weight(1f))
            Icon(
                Icons.Filled.PlayCircle,
                "Cómo funciona",
                Modifier
                    .size(26.dp)
                    .clickable { onHowItWorks() },
                tint = Palette.volt,
            )
        }

        if (credit != null && metrics != null) {
            ActiveCreditPanel(credit, metrics)
            DemoFooter(hasCredit = true, viewModel = viewModel)
        } else {
            CreditOfferPanel(
                onHowItWorks = onHowItWorks,
                onRequest = {
                    viewModel.requestCredit()
                    isApprovalOpen = true
                },
            )
            DemoFooter(hasCredit = false, viewModel = viewModel)
        }
    }

    if (isApprovalOpen) {
        AlertDialog(
            onDismissRequest = { isApprovalOpen = false },
            containerColor = Palette.surface,
            title = {
                Text(
                    "¡Crédito aprobado!",
                    style = TextStyle(fontSize = 18.sp, fontWeight = FontWeight.Black, color = Palette.volt),
                )
            },
            text = {
                Text(
                    "Firmaste tu contrato del ${CreditProgram.VEHICLE_MODEL} sin enganche. El descuento " +
                        "semanal empieza en 7 días y la unidad se entrega en el mes " +
                        "${CreditProgram.DELIVERY_MONTH}.",
                    style = TextStyle(fontSize = 14.sp, color = Palette.textMuted),
                )
            },
            confirmButton = {
                TextButton(onClick = { isApprovalOpen = false }) {
                    Text("Ver mi crédito", color = Palette.volt)
                }
            },
        )
    }
}

/** Demo helpers so both presentations of the panel can be reviewed. */
@Composable
private fun DemoFooter(hasCredit: Boolean, viewModel: FleetViewModel) {
    Column(
        Modifier
            .fillMaxWidth()
            .panelFlat()
            .padding(14.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        CapsLabel("Vista de demostración")
        Row(horizontalArrangement = Arrangement.spacedBy(16.dp)) {
            if (hasCredit) {
                DemoLink("Contrato semana 14") { viewModel.loadCreditDemoProgress() }
                DemoLink("Ver anuncio") { viewModel.cancelCredit() }
            } else {
                DemoLink("Ver crédito en curso (semana 14)") { viewModel.loadCreditDemoProgress() }
            }
        }
    }
}

@Composable
private fun DemoLink(label: String, onClick: () -> Unit) {
    Text(
        label,
        style = TextStyle(fontSize = 12.sp, fontWeight = FontWeight.SemiBold, color = Palette.info),
        modifier = Modifier
            .clip(CircleShape)
            .clickable { onClick() }
            .padding(horizontal = 6.dp, vertical = 4.dp),
    )
}

// MARK: - Offer (driver without credit)

@Composable
private fun CreditOfferPanel(onHowItWorks: () -> Unit, onRequest: () -> Unit) {
    Column(verticalArrangement = Arrangement.spacedBy(16.dp)) {
        // Hero
        Column(
            Modifier
                .fillMaxWidth()
                .clip(RoundedCornerShape(26.dp))
                .background(Palette.surface.copy(alpha = 0.9f))
                .border(1.dp, Palette.volt.copy(alpha = 0.35f), RoundedCornerShape(26.dp)),
        ) {
            Box(
                Modifier
                    .fillMaxWidth()
                    .height(208.dp)
                    .background(Palette.surfaceRaised),
            ) {
                Image(
                    painter = painterResource(R.drawable.credit_vehicle),
                    contentDescription = CreditProgram.VEHICLE_MODEL,
                    contentScale = ContentScale.Crop,
                    modifier = Modifier.fillMaxSize(),
                )
                Box(
                    Modifier
                        .fillMaxSize()
                        .background(
                            Brush.verticalGradient(
                                0.4f to Color.Transparent,
                                1f to Palette.surface.copy(alpha = 0.95f),
                            ),
                        ),
                )
                Text(
                    "SEMINUEVA CERTIFICADA",
                    style = TextStyle(
                        fontSize = 10.sp,
                        fontWeight = FontWeight.Black,
                        letterSpacing = 1.2.sp,
                        color = Palette.canvas,
                    ),
                    modifier = Modifier
                        .padding(14.dp)
                        .clip(CircleShape)
                        .background(Palette.volt)
                        .padding(horizontal = 10.dp, vertical = 6.dp),
                )
            }
            Column(Modifier.padding(18.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                CapsLabel("Venta de unidades de flotilla")
                Text(
                    "Llévate tu ${CreditProgram.VEHICLE_MODEL} a crédito",
                    style = TextStyle(fontSize = 22.sp, fontWeight = FontWeight.Black, color = Palette.textPrimary),
                )
                Text(
                    "Sin enganche, con aprobación inmediata y equipo de carga incluido. " +
                        "Kilometraje no mayor a ${Fmt.km(CreditProgram.MAX_HANDOVER_KM)}.",
                    style = TextStyle(fontSize = 13.sp, color = Palette.textMuted),
                )
            }
        }

        // Benefits
        CreditProgram.benefits.chunked(2).forEach { row ->
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                row.forEachIndexed { index, benefit ->
                    Column(
                        Modifier
                            .weight(1f)
                            .height(132.dp)
                            .panelFlat()
                            .padding(14.dp),
                        verticalArrangement = Arrangement.spacedBy(6.dp),
                    ) {
                        Icon(benefitIcon(benefit.title), null, Modifier.size(20.dp), tint = Palette.volt)
                        Text(
                            benefit.title,
                            style = TextStyle(fontSize = 14.sp, fontWeight = FontWeight.Bold, color = Palette.textPrimary),
                        )
                        Text(
                            benefit.detail,
                            style = TextStyle(fontSize = 11.sp, color = Palette.textMuted),
                        )
                    }
                    if (row.size == 1 && index == 0) Spacer(Modifier.weight(1f))
                }
            }
        }

        // Steps
        Column(
            Modifier
                .fillMaxWidth()
                .panel()
                .padding(18.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Icon(Icons.Filled.FormatListNumbered, null, Modifier.size(14.dp), tint = Palette.textMuted)
                Spacer(Modifier.width(6.dp))
                Text(
                    "Así funciona en 4 pasos",
                    style = TextStyle(fontSize = 12.sp, fontWeight = FontWeight.SemiBold, color = Palette.textMuted),
                )
            }
            Row(
                Modifier.horizontalScroll(rememberScrollState()),
                horizontalArrangement = Arrangement.spacedBy(10.dp),
            ) {
                CreditProgram.steps.forEach { step ->
                    Column(
                        Modifier
                            .width(168.dp)
                            .panelFlat()
                            .padding(14.dp),
                        verticalArrangement = Arrangement.spacedBy(8.dp),
                    ) {
                        Box(
                            Modifier
                                .size(26.dp)
                                .background(Palette.volt, CircleShape),
                            contentAlignment = Alignment.Center,
                        ) {
                            Text(
                                "${step.index}",
                                style = TextStyle(
                                    fontSize = 13.sp,
                                    fontWeight = FontWeight.Black,
                                    color = Palette.canvas,
                                ),
                            )
                        }
                        Text(
                            step.title,
                            style = TextStyle(fontSize = 14.sp, fontWeight = FontWeight.Bold, color = Palette.textPrimary),
                        )
                        Text(
                            step.detail,
                            style = TextStyle(fontSize = 11.sp, color = Palette.textMuted),
                        )
                    }
                }
            }
        }

        BigButton("Solicitar mi crédito", icon = Icons.Filled.Article, onClick = onRequest)
        BigButton("Cómo funciona", icon = Icons.Filled.PlayCircle, tone = ButtonTone.OUTLINE, onClick = onHowItWorks)

        Text(
            "Descuento vía nómina · ${CreditProgram.TERM_WEEKS} pagos semanales · plazo de " +
                "${CreditProgram.TERM_MONTHS} meses · la unidad se entrega en el mes " +
                "${CreditProgram.DELIVERY_MONTH}.",
            style = TextStyle(fontSize = 11.sp, color = Palette.textMuted),
            textAlign = TextAlign.Center,
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 8.dp),
        )
    }
}

// MARK: - Active contract

@Composable
private fun ActiveCreditPanel(credit: CreditAccount, metrics: CreditMetrics) {
    var areTermsExpanded by remember { mutableStateOf(false) }

    Column(verticalArrangement = Arrangement.spacedBy(16.dp)) {
        // Balance
        Column(
            Modifier
                .fillMaxWidth()
                .panel()
                .padding(18.dp),
            verticalArrangement = Arrangement.spacedBy(14.dp),
        ) {
            Row(Modifier.fillMaxWidth()) {
                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    CapsLabel("Saldo del crédito")
                    Text(
                        Fmt.mxn(metrics.balanceMxn),
                        style = TextStyle(
                            fontSize = 34.sp,
                            fontWeight = FontWeight.Black,
                            fontFamily = TabularNumbers,
                            color = Palette.textPrimary,
                        ),
                        maxLines = 1,
                    )
                    Text(
                        "${credit.vehicleTarget} · contrato ${credit.contractId}",
                        style = TextStyle(fontSize = 11.sp, color = Palette.textMuted),
                    )
                }
                Column(
                    Modifier
                        .panelFlat()
                        .padding(12.dp),
                    horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.spacedBy(2.dp),
                ) {
                    Text(
                        "${metrics.weeksPaid}",
                        style = TextStyle(
                            fontSize = 19.sp,
                            fontWeight = FontWeight.Black,
                            fontFamily = TabularNumbers,
                            color = Palette.textPrimary,
                        ),
                    )
                    Text(
                        "de ${CreditProgram.TERM_WEEKS}",
                        style = TextStyle(fontSize = 10.sp, fontWeight = FontWeight.Bold, color = Palette.textMuted),
                    )
                    CapsLabel("Semanas")
                }
            }

            ProgressTrack(value = metrics.paidMxn.toDouble(), goal = credit.totalMxn.toDouble())

            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                StatTile("Pagado", Fmt.mxn(metrics.paidMxn), Modifier.weight(1f), tone = Tone.VOLT)
                StatTile("Abono semanal", Fmt.mxn(credit.weeklyMxn), Modifier.weight(1f), hint = "Vía nómina")
                StatTile("Restan", "${metrics.weeksRemaining}", Modifier.weight(1f), hint = "Semanas por pagar")
            }
        }

        // Next payment
        Column(
            Modifier
                .fillMaxWidth()
                .panel()
                .padding(18.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            SectionLabel(Icons.Filled.CalendarMonth, "Próximo descuento")
            val next = metrics.nextPayment
            if (next != null) {
                Row(Modifier.fillMaxWidth()) {
                    Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
                        Text(
                            next.concept,
                            style = TextStyle(fontSize = 16.sp, fontWeight = FontWeight.Black, color = Palette.textPrimary),
                        )
                        Text(
                            Fmt.dateShort(next.dueDate),
                            style = TextStyle(fontSize = 13.sp, color = Palette.textMuted),
                        )
                    }
                    Column(horizontalAlignment = Alignment.End, verticalArrangement = Arrangement.spacedBy(3.dp)) {
                        Text(
                            Fmt.mxn(next.amountMxn),
                            style = TextStyle(
                                fontSize = 16.sp,
                                fontWeight = FontWeight.Black,
                                fontFamily = TabularNumbers,
                                color = Palette.textPrimary,
                            ),
                        )
                        Text(
                            next.status.label.uppercase(),
                            style = TextStyle(
                                fontSize = 9.sp,
                                fontWeight = FontWeight.Black,
                                letterSpacing = 1.sp,
                                color = statusTone(next.status),
                            ),
                        )
                    }
                }
            } else {
                Text(
                    "No tienes abonos pendientes esta semana.",
                    style = TextStyle(fontSize = 13.sp, color = Palette.textMuted),
                )
            }
            Text(
                "El descuento se aplica automáticamente en tu nómina semanal; no necesitas hacer transferencias.",
                style = TextStyle(fontSize = 11.sp, color = Palette.textMuted),
            )
        }

        // Delivery
        Column(
            Modifier
                .fillMaxWidth()
                .panel()
                .padding(18.dp),
            verticalArrangement = Arrangement.spacedBy(14.dp),
        ) {
            SectionLabel(Icons.Filled.DirectionsCar, "Entrega de la unidad")
            Row(
                Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(16.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                RingGauge(
                    value = metrics.monthsElapsed.toDouble(),
                    goal = CreditProgram.DELIVERY_MONTH.toDouble(),
                    headline = "${metrics.monthsElapsed}/${CreditProgram.DELIVERY_MONTH}",
                    caption = "Meses",
                    diameter = 138.dp,
                )
                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text(
                        if (metrics.isUnitDelivered) {
                            "Unidad lista para entrega"
                        } else {
                            "Faltan ${metrics.monthsToDelivery} meses"
                        },
                        style = TextStyle(
                            fontSize = 14.sp,
                            fontWeight = FontWeight.Black,
                            color = if (metrics.isUnitDelivered) Palette.volt else Palette.textPrimary,
                        ),
                    )
                    Text(
                        "Fecha estimada: ${Fmt.dateShort(metrics.estimatedDeliveryDate)}",
                        style = TextStyle(fontSize = 11.sp, color = Palette.textMuted),
                    )
                    Text(
                        "Odómetro actual: ${Fmt.km(credit.assignedVehicleOdometerKm)}",
                        style = TextStyle(fontSize = 11.sp, color = Palette.textMuted),
                    )
                    Text(
                        "Sale de flotilla entre ${Fmt.km(CreditProgram.MIN_HANDOVER_KM)} y " +
                            "${Fmt.km(CreditProgram.MAX_HANDOVER_KM)}.",
                        style = TextStyle(fontSize = 11.sp, color = Palette.textMuted),
                    )
                }
            }
            NoticeBanner(
                icon = Icons.Filled.Info,
                title = "Mientras construyes tu historial, la unidad sigue operando en la flotilla.",
                message = "Ese modelo es lo que nos permite venderte más barato que un crédito tradicional.",
                tone = Tone.INFO,
            )
        }

        // Behaviour
        Column(
            Modifier
                .fillMaxWidth()
                .panel()
                .padding(18.dp),
            verticalArrangement = Arrangement.spacedBy(14.dp),
        ) {
            Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                SectionLabel(Icons.Filled.TrendingUp, "Comportamiento crediticio")
                Spacer(Modifier.weight(1f))
                Text(
                    "RIESGO ${metrics.risk.label.uppercase()}",
                    style = TextStyle(
                        fontSize = 9.sp,
                        fontWeight = FontWeight.Black,
                        letterSpacing = 1.sp,
                        color = riskColor(metrics.risk),
                    ),
                    modifier = Modifier
                        .clip(CircleShape)
                        .background(riskColor(metrics.risk).copy(alpha = 0.14f))
                        .padding(horizontal = 10.dp, vertical = 5.dp),
                )
            }
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                StatTile(
                    "Cumplimiento",
                    Fmt.percent(metrics.complianceRate),
                    Modifier.weight(1f),
                    tone = if (metrics.complianceRate >= 0.95) Tone.VOLT else Tone.AMBER,
                )
                StatTile("Puntuales", "${credit.onTimePayments}", Modifier.weight(1f), tone = Tone.INFO)
                StatTile(
                    "Atrasados",
                    "${credit.latePayments}",
                    Modifier.weight(1f),
                    tone = if (credit.latePayments == 0) Tone.NEUTRAL else Tone.DANGER,
                )
            }
            Text(metrics.risk.detail, style = TextStyle(fontSize = 11.sp, color = Palette.textMuted))
        }

        // Payments
        Column(
            Modifier
                .fillMaxWidth()
                .panel()
                .padding(18.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            SectionLabel(Icons.Filled.Receipt, "Historial de abonos")
            credit.payments.forEach { payment ->
                Row(
                    Modifier
                        .fillMaxWidth()
                        .panelFlat(20.dp)
                        .padding(14.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                        Text(
                            payment.concept,
                            style = TextStyle(fontSize = 14.sp, fontWeight = FontWeight.Bold, color = Palette.textPrimary),
                        )
                        Text(
                            Fmt.dateShort(payment.dueDate),
                            style = TextStyle(fontSize = 11.sp, color = Palette.textMuted),
                        )
                    }
                    Column(horizontalAlignment = Alignment.End, verticalArrangement = Arrangement.spacedBy(2.dp)) {
                        Text(
                            Fmt.mxn(payment.amountMxn),
                            style = TextStyle(
                                fontSize = 14.sp,
                                fontWeight = FontWeight.Black,
                                fontFamily = TabularNumbers,
                                color = Palette.textPrimary,
                            ),
                        )
                        Text(
                            payment.status.label.uppercase(),
                            style = TextStyle(
                                fontSize = 9.sp,
                                fontWeight = FontWeight.Black,
                                letterSpacing = 1.sp,
                                color = statusTone(payment.status),
                            ),
                        )
                    }
                }
            }
        }

        // Terms
        Column(
            Modifier
                .fillMaxWidth()
                .panel()
                .padding(18.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Row(
                Modifier
                    .fillMaxWidth()
                    .clickable { areTermsExpanded = !areTermsExpanded },
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Icon(Icons.Filled.Article, null, Modifier.size(16.dp), tint = Palette.textPrimary)
                Spacer(Modifier.width(8.dp))
                Text(
                    "Condiciones del contrato",
                    style = TextStyle(fontSize = 14.sp, fontWeight = FontWeight.Bold, color = Palette.textPrimary),
                )
                Spacer(Modifier.weight(1f))
                Icon(
                    if (areTermsExpanded) Icons.Filled.ExpandLess else Icons.Filled.ExpandMore,
                    null,
                    Modifier.size(18.dp),
                    tint = Palette.textMuted,
                )
            }
            if (areTermsExpanded) {
                listOf(
                    "Firma" to Fmt.dateShort(credit.startedAt),
                    "Enganche" to "Sin enganche",
                    "Monto financiado" to Fmt.mxn(credit.totalMxn),
                    "Plazo" to "${CreditProgram.TERM_MONTHS} meses · ${CreditProgram.TERM_WEEKS} semanas",
                    "Forma de pago" to "Descuento semanal vía nómina",
                    "Entrega de unidad" to "Mes ${CreditProgram.DELIVERY_MONTH}",
                    "Último abono" to Fmt.dateShort(metrics.contractEndDate),
                ).forEach { (label, value) ->
                    Row(
                        Modifier
                            .fillMaxWidth()
                            .panelFlat(14.dp)
                            .padding(horizontal = 12.dp, vertical = 10.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Text(label, style = TextStyle(fontSize = 12.sp, color = Palette.textMuted))
                        Spacer(Modifier.weight(1f))
                        Text(
                            value,
                            style = TextStyle(fontSize = 12.sp, fontWeight = FontWeight.Bold, color = Palette.textPrimary),
                            textAlign = TextAlign.End,
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun SectionLabel(icon: ImageVector, text: String) {
    Row(verticalAlignment = Alignment.CenterVertically) {
        Icon(icon, null, Modifier.size(14.dp), tint = Palette.textMuted)
        Spacer(Modifier.width(6.dp))
        Text(
            text,
            style = TextStyle(fontSize = 12.sp, fontWeight = FontWeight.SemiBold, color = Palette.textMuted),
        )
    }
}

private fun benefitIcon(title: String): ImageVector = when {
    title.contains("enganche") -> Icons.Filled.ThumbUp
    title.contains("Aprobación") -> Icons.Filled.Bolt
    title.contains("carga") -> Icons.Filled.EvStation
    title.contains("km") -> Icons.Filled.Speed
    title.contains("año") -> Icons.Filled.CheckCircle
    else -> Icons.Filled.CalendarMonth
}

private fun riskColor(risk: CreditRisk): Color = when (risk) {
    CreditRisk.LOW -> Palette.volt
    CreditRisk.MEDIUM -> Palette.amber
    CreditRisk.HIGH -> Palette.danger
}

private fun statusTone(status: CreditStatus): Color = when (status) {
    CreditStatus.PAID -> Palette.volt
    CreditStatus.DUE -> Palette.amber
    CreditStatus.LATE -> Palette.danger
}
