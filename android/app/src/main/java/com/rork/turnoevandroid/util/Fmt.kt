package com.rork.turnoevandroid.util

import java.text.NumberFormat
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Date
import java.util.Locale

/** Spanish (MX) formatting for money, distance, clocks and durations. */
object Fmt {
    val locale: Locale = Locale("es", "MX")

    private val currency: NumberFormat = NumberFormat.getCurrencyInstance(locale).apply {
        maximumFractionDigits = 0
        minimumFractionDigits = 0
    }

    private val integer: NumberFormat = NumberFormat.getIntegerInstance(locale)

    private fun formatter(pattern: String): SimpleDateFormat = SimpleDateFormat(pattern, locale)

    fun mxn(value: Int): String = currency.format(value.toLong())

    fun mxn(value: Double): String = currency.format(Math.round(value))

    fun km(value: Int): String = "${integer.format(value.toLong())} km"

    fun number(value: Int): String = integer.format(value.toLong())

    fun clock(millis: Long): String = formatter("HH:mm").format(Date(millis))

    fun clockSeconds(millis: Long): String = formatter("HH:mm:ss").format(Date(millis))

    fun dateLong(millis: Long): String =
        formatter("EEEE d 'de' MMMM").format(Date(millis)).capitalizedFirst()

    fun dateShort(millis: Long): String =
        formatter("EEE dd MMM").format(Date(millis)).replace(".", "").capitalizedFirst()

    /** "12 ago" for the bonus week ranges. */
    fun dayNumber(millis: Long): String =
        formatter("d MMM").format(Date(millis)).replace(".", "")

    fun monthLong(millis: Long): String =
        formatter("MMMM yyyy").format(Date(millis)).capitalizedFirst()

    /** "2026-08", used to key monthly bonus evaluations. */
    fun monthKey(millis: Long): String = formatter("yyyy-MM").format(Date(millis))

    fun rating(value: Double): String = String.format(locale, "%.2f", value)

    fun dayShort(millis: Long): String {
        val raw = formatter("EEE").format(Date(millis)).replace(".", "")
        return raw.take(3).capitalizedFirst()
    }

    /** 07:32:11 for the live shift counter. */
    fun stopwatch(seconds: Int): String {
        val total = seconds.coerceAtLeast(0)
        return String.format(locale, "%02d:%02d:%02d", total / 3600, (total % 3600) / 60, total % 60)
    }

    /** Late time is always communicated as hh:mm. */
    fun lateText(minutes: Int): String {
        val total = minutes.coerceAtLeast(0)
        return String.format(locale, "%02d:%02d", total / 60, total % 60)
    }

    fun durationText(minutes: Int): String {
        val total = minutes.coerceAtLeast(0)
        val hours = total / 60
        val rest = total % 60
        return if (hours > 0) "${hours}h ${String.format(locale, "%02d", rest)}m" else "${rest}m"
    }

    fun firstName(fullName: String): String =
        fullName.split(" ").firstOrNull()?.takeIf { it.isNotBlank() } ?: fullName

    fun relative(millis: Long, now: Long): String {
        val minutes = ((now - millis) / 60_000L).toInt()
        return when {
            minutes < 1 -> "ahora"
            minutes < 60 -> "hace $minutes min"
            minutes < 60 * 24 -> "hace ${minutes / 60} h"
            minutes / (60 * 24) == 1 -> "ayer"
            else -> "hace ${minutes / (60 * 24)} días"
        }
    }

    fun percent(value: Double): String = "${Math.round(value * 100)}%"

    fun String.capitalizedFirst(): String =
        if (isEmpty()) this else substring(0, 1).uppercase(locale) + substring(1)

    /** Calendar bound to the fleet locale, used by every date rule. */
    fun calendar(millis: Long? = null): Calendar = Calendar.getInstance(locale).apply {
        if (millis != null) timeInMillis = millis
    }
}

/** Adds whole days to an epoch timestamp, honoring the calendar. */
fun Long.plusDays(days: Int): Long = Fmt.calendar(this).apply {
    add(Calendar.DAY_OF_YEAR, days)
}.timeInMillis

fun Long.plusMonths(months: Int): Long = Fmt.calendar(this).apply {
    add(Calendar.MONTH, months)
}.timeInMillis

fun Long.plusMinutes(minutes: Int): Long = this + minutes * 60_000L

fun Long.startOfDay(): Long = Fmt.calendar(this).apply {
    set(Calendar.HOUR_OF_DAY, 0)
    set(Calendar.MINUTE, 0)
    set(Calendar.SECOND, 0)
    set(Calendar.MILLISECOND, 0)
}.timeInMillis
