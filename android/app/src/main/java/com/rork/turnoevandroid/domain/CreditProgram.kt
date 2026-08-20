package com.rork.turnoevandroid.domain

import com.rork.turnoevandroid.util.Fmt
import com.rork.turnoevandroid.util.plusDays
import com.rork.turnoevandroid.util.plusMonths
import java.util.Calendar

/**
 * Terms of the fleet's used-unit credit program.
 * Units leave the fleet between 110,000 and 120,000 km and are handed to drivers
 * who built a clean compliance record inside the program.
 */
object CreditProgram {
    const val VEHICLE_MODEL = "BYD Dolphin Mini"

    /** Internal figure used only for calculations; never shown in the marketing banner. */
    const val PRICE_MXN = 390_000
    const val DOWN_PAYMENT_MXN = 0
    const val TERM_MONTHS = 48
    const val TERM_WEEKS = 192

    /** 390,000 / 192 weekly instalments, rounded to the peso. */
    const val WEEKLY_MXN = 2_031

    /** The unit stays in the fleet while the driver builds credit behaviour. */
    const val DELIVERY_MONTH = 24
    const val DELIVERY_WEEK = 96
    const val MIN_HANDOVER_KM = 110_000
    const val MAX_HANDOVER_KM = 120_000

    data class Benefit(val title: String, val detail: String)

    val benefits: List<Benefit> = listOf(
        Benefit("Sin enganche", "Arrancas tu crédito sin pago inicial"),
        Benefit("Aprobación inmediata", "Se firma el mismo día en la estación"),
        Benefit("Equipo de carga incluido", "Cargador portátil para tu domicilio"),
        Benefit("Máximo 120,000 km", "La unidad sale de flotilla entre 110 y 120 mil km"),
        Benefit("Se entrega unidad del año", "Modelo reciente, seminueva certificada"),
        Benefit("Plazo de 48 meses", "192 pagos semanales vía nómina"),
    )

    data class Step(val index: Int, val title: String, val detail: String)

    val steps: List<Step> = listOf(
        Step(1, "Firma de contrato", "Sin enganche y con aprobación inmediata"),
        Step(2, "Descuento semanal", "Tu abono se descuenta cada semana vía nómina"),
        Step(3, "Comportamiento crediticio", "Riesgo bajo, precio bajo: tu cumplimiento define tus condiciones"),
        Step(4, "Entrega en el mes 24", "La unidad permanece en flotilla hasta que la recibes"),
    )

    val howItWorksScript: String = "Los créditos tradicionales incorporan el costo del riesgo en el " +
        "precio final del vehículo. Nuestro programa funciona de manera diferente. Durante los primeros " +
        "24 meses la unidad permanece dentro de la flotilla mientras construyes tu historial de " +
        "cumplimiento. Ese modelo nos permite reducir costos y ofrecerte mejores condiciones de financiamiento."

    /** Captions shown while the explainer narration plays, in seconds. */
    data class Caption(val start: Double, val text: String)

    val captions: List<Caption> = listOf(
        Caption(0.0, "Los créditos tradicionales incorporan el costo del riesgo en el precio final del vehículo."),
        Caption(7.0, "Nuestro programa funciona de manera diferente."),
        Caption(11.1, "Durante los primeros 24 meses la unidad permanece en la flotilla mientras construyes tu historial de cumplimiento."),
        Caption(20.4, "Ese modelo reduce costos y te da mejores condiciones de financiamiento."),
    )

    /** Derives the transparent contract metrics for a given moment. */
    fun metrics(account: CreditAccount, now: Long): CreditMetrics {
        val monthsElapsed = monthsBetween(account.startedAt, now).coerceAtLeast(0)
        val deliveryDate = account.startedAt.plusMonths(DELIVERY_MONTH)
        val endDate = account.startedAt.plusMonths(TERM_MONTHS)
        val evaluated = account.onTimePayments + account.latePayments
        val compliance = if (evaluated > 0) account.onTimePayments.toDouble() / evaluated else 1.0

        val risk = when {
            account.latePayments == 0 -> CreditRisk.LOW
            account.latePayments <= 2 -> CreditRisk.MEDIUM
            else -> CreditRisk.HIGH
        }

        return CreditMetrics(
            weeksPaid = account.weeksPaid,
            weeksRemaining = (TERM_WEEKS - account.weeksPaid).coerceAtLeast(0),
            paidMxn = account.paidMxn,
            balanceMxn = (account.totalMxn - account.paidMxn).coerceAtLeast(0),
            paymentProgress = if (account.totalMxn > 0) {
                account.paidMxn.toDouble() / account.totalMxn
            } else {
                0.0
            },
            nextPayment = account.payments
                .filter { it.status != CreditStatus.PAID }
                .minByOrNull { it.dueDate },
            complianceRate = compliance,
            risk = risk,
            monthsElapsed = monthsElapsed,
            monthsToDelivery = (DELIVERY_MONTH - monthsElapsed).coerceAtLeast(0),
            deliveryProgress = (monthsElapsed.toDouble() / DELIVERY_MONTH).coerceAtMost(1.0),
            estimatedDeliveryDate = deliveryDate,
            contractEndDate = endDate,
            kmToHandover = (MIN_HANDOVER_KM - account.assignedVehicleOdometerKm).coerceAtLeast(0),
            isUnitDelivered = monthsElapsed >= DELIVERY_MONTH,
        )
    }

    /** Fresh contract signed today: no down payment, first instalment in a week. */
    fun newAccount(now: Long, vehicleInternalNumber: String): CreditAccount = CreditAccount(
        contractId = "CR-${(now / 1000) % 100_000}",
        vehicleTarget = "$VEHICLE_MODEL · $vehicleInternalNumber",
        startedAt = now,
        totalMxn = PRICE_MXN,
        paidMxn = 0,
        weeklyMxn = WEEKLY_MXN,
        weeksPaid = 0,
        onTimePayments = 0,
        latePayments = 0,
        assignedVehicleOdometerKm = 96_480,
        payments = listOf(
            CreditPayment(
                id = "cp-new-1",
                concept = "Abono semanal 1",
                dueDate = now.plusDays(7),
                amountMxn = WEEKLY_MXN,
                status = CreditStatus.DUE,
            ),
        ),
    )

    private fun monthsBetween(from: Long, to: Long): Int {
        val start = Fmt.calendar(from)
        val end = Fmt.calendar(to)
        var months = (end.get(Calendar.YEAR) - start.get(Calendar.YEAR)) * 12 +
            (end.get(Calendar.MONTH) - start.get(Calendar.MONTH))
        if (end.get(Calendar.DAY_OF_MONTH) < start.get(Calendar.DAY_OF_MONTH)) months -= 1
        return months
    }
}

enum class CreditRisk {
    LOW,
    MEDIUM,
    HIGH;

    val label: String
        get() = when (this) {
            LOW -> "Bajo"
            MEDIUM -> "Medio"
            HIGH -> "Alto"
        }

    val detail: String
        get() = when (this) {
            LOW -> "Riesgo bajo: conservas las mejores condiciones del programa."
            MEDIUM -> "Un atraso más y tu perfil sube a riesgo alto."
            HIGH -> "Riesgo alto: la entrega de la unidad puede posponerse."
        }
}

/** Everything the driver needs to see about an active contract, derived from the account. */
data class CreditMetrics(
    val weeksPaid: Int,
    val weeksRemaining: Int,
    val paidMxn: Int,
    val balanceMxn: Int,
    val paymentProgress: Double,
    val nextPayment: CreditPayment?,
    val complianceRate: Double,
    val risk: CreditRisk,
    val monthsElapsed: Int,
    val monthsToDelivery: Int,
    val deliveryProgress: Double,
    val estimatedDeliveryDate: Long,
    val contractEndDate: Long,
    val kmToHandover: Int,
    val isUnitDelivered: Boolean,
)
