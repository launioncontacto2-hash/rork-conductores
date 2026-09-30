package mx.dori.vehicleagent.probe

import android.Manifest
import android.app.Activity
import android.content.Context
import android.content.pm.PackageManager
import android.location.Location
import android.location.LocationListener
import android.location.LocationManager
import android.os.Bundle
import android.view.ViewGroup
import android.widget.Button
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView
import java.io.ByteArrayOutputStream
import java.nio.charset.StandardCharsets
import java.util.Locale

private enum class Decode { FLOAT, INT, TENTH, MILLI, RAW }
private data class Signal(val name: String, val device: Int, val fid: Int, val tx: Int, val decode: Decode, val unit: String, val status: String)
private data class Reading(val signal: Signal, val value: String, val state: String, val raw: String = "")

private val SIGNALS = listOf(
    Signal("SOC", 1014, 1246777400, 7, Decode.FLOAT, "%", "CERTIFIED_PHYSICAL"),
    Signal("ODO", 1014, 1246765072, 5, Decode.TENTH, "km", "CERTIFIED_PHYSICAL"),
    Signal("POWER_KW", 1012, 339738656, 5, Decode.INT, "kW", "OBSERVED_VALID"),
    Signal("TOTAL_ELECTRIC_KWH", 1014, 1032871984, 7, Decode.FLOAT, "kWh", "OBSERVED_VALID"),
    Signal("BATTERY_REMAIN_KWH", 1005, 882901008, 7, Decode.FLOAT, "kWh", "OBSERVED_VALID"),
    Signal("POWER_STATE", 1023, 315621408, 5, Decode.INT, "", "OBSERVED_VALID"),
    Signal("GEAR", 1011, 555745336, 5, Decode.INT, "", "OBSERVED_VALID"),
    Signal("DRIVE_MODE", 1006, 555745294, 5, Decode.INT, "", "OBSERVED_VALID"),
    Signal("WORK_MODE", 1006, 874512420, 5, Decode.INT, "", "CANDIDATE"),
    Signal("SOH", 1014, 1145045032, 5, Decode.INT, "%", "OBSERVED_VALID"),
    Signal("12V", 1001, 1128267816, 7, Decode.FLOAT, "V", "OBSERVED_VALID"),
    Signal("MAX_CELL", 1014, 1147142192, 5, Decode.MILLI, "V", "OBSERVED_VALID"),
    Signal("MIN_CELL", 1014, 1147142160, 5, Decode.MILLI, "V", "OBSERVED_VALID"),
    Signal("MAX_BAT_TEMP", 1014, 1148190752, 5, Decode.INT, "°C", "OBSERVED_VALID"),
    Signal("MIN_BAT_TEMP", 1014, 1148190736, 5, Decode.INT, "°C", "OBSERVED_VALID"),
    Signal("HV_VOLTAGE", 1009, 1145045000, 5, Decode.INT, "V", "OBSERVED_VALID"),
    Signal("HV_CURRENT", 1009, 1145045016, 7, Decode.FLOAT, "A", "OBSERVED_VALID"),
    Signal("INSULATION", 1039, 1134559256, 5, Decode.INT, "kΩ", "OBSERVED_VALID"),
    Signal("BMS_MAX_CHARGE", 1014, 877658136, 5, Decode.TENTH, "kW", "OBSERVED_VALID"),
    Signal("BMS_MAX_DISCHARGE_ALLOW", 1014, 877658120, 5, Decode.TENTH, "kW", "CANDIDATE"),
    Signal("CHARGE_GUN_STATE", 1009, 876609586, 5, Decode.INT, "", "CANDIDATE"),
    Signal("BMS_CHARGE_STATE", 1009, 876609560, 5, Decode.INT, "", "CANDIDATE"),
    Signal("CHARGING_TYPE", 1009, 876609592, 5, Decode.INT, "", "CANDIDATE"),
    Signal("CHARGING_SESSION_KWH", 1009, 666894360, 7, Decode.FLOAT, "kWh", "CANDIDATE"),
    Signal("FL_PRESSURE", 1016, -1728052956, 5, Decode.INT, "kPa", "CERTIFIED_PHYSICAL"),
    Signal("FR_PRESSURE", 1016, -1728052952, 5, Decode.INT, "kPa", "CERTIFIED_PHYSICAL"),
    Signal("RL_PRESSURE", 1016, -1728052948, 5, Decode.INT, "kPa", "CERTIFIED_PHYSICAL"),
    Signal("RR_PRESSURE", 1016, -1728052944, 5, Decode.INT, "kPa", "CERTIFIED_PHYSICAL"),
    Signal("FL_TEMPERATURE", 1007, 1246797848, 5, Decode.INT, "°C", "OBSERVED_VALID"),
    Signal("FR_TEMPERATURE", 1007, 1246797860, 5, Decode.INT, "°C", "OBSERVED_VALID"),
    Signal("RL_TEMPERATURE", 1007, 1246797872, 5, Decode.INT, "°C", "OBSERVED_VALID"),
    Signal("RR_TEMPERATURE", 1007, 1246797884, 5, Decode.INT, "°C", "OBSERVED_VALID"),
    Signal("FRONT_MOTOR_TEMP", 1039, 1154482192, 5, Decode.INT, "°C", "CANDIDATE"),
    Signal("FRONT_INVERTER_TEMP", 1039, 1154482184, 5, Decode.INT, "°C", "CANDIDATE"),
    Signal("FRONT_MOTOR_RPM", 1012, 1141899272, 5, Decode.INT, "rpm", "CANDIDATE"),
    Signal("ACCELERATOR", 1013, 874512392, 5, Decode.INT, "%", "CANDIDATE"),
    Signal("BRAKE", 1013, 874512400, 5, Decode.INT, "%", "CANDIDATE")
)

class MainActivity : Activity() {
    private lateinit var summary: TextView
    private lateinit var diagnostics: TextView
    private val locationCode = 701
    override fun onCreate(state: Bundle?) {
        super.onCreate(state)
        val root = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL; setPadding(24, 18, 24, 18) }
        fun t(s: String, n: Float = 17f) = TextView(this).apply { text = s; textSize = n; setPadding(0, 6, 0, 6) }
        root.addView(t("DORI Vehicle Agent Telemetry", 25f)); root.addView(t("0.7 · read-only", 15f))
        summary = t("RESUMEN\nSOC: unavailable\nODO: unavailable\nEstado: pendiente\nMarcha: unavailable", 18f); root.addView(summary)
        val all = Button(this).apply { text = "ACTUALIZAR TODO"; setOnClickListener { updateAll() } }; root.addView(all, full())
        val gps = Button(this).apply { text = "ACTUALIZAR GPS"; setOnClickListener { updateGps() } }; root.addView(gps, full())
        val diag = Button(this).apply { text = "DIAGNÓSTICO"; setOnClickListener { diagnostics.text = diagnosticText() } }; root.addView(diag, full())
        diagnostics = t("GPS: pendiente\nDiagnóstico: pendiente", 15f); root.addView(ScrollView(this).apply { addView(diagnostics) }, LinearLayout.LayoutParams(-1, 0, 1f)); setContentView(root)
    }
    private fun full() = LinearLayout.LayoutParams(-1, ViewGroup.LayoutParams.WRAP_CONTENT)
    private fun updateAll() { val reads = SIGNALS.map { readSignal(it) }; val map = reads.associateBy { it.signal.name }; val soc = map["SOC"]; val odo = map["ODO"]; val gear = map["GEAR"]; summary.text = "RESUMEN\nSOC: ${show(soc)}\nODO: ${show(odo)}\nEstado vehículo: ${show(map["POWER_STATE"])}\nMarcha: ${show(gear)}\n\nBATERÍA\nSoH: ${show(map["SOH"])}\n12 V: ${show(map["12V"])}\nHV: ${show(map["HV_VOLTAGE"])}\nCell delta: pendiente\n\nTPMS\nFL: ${show(map["FL_PRESSURE"])}\nFR: ${show(map["FR_PRESSURE"])}\nRL: ${show(map["RL_PRESSURE"])}\nRR: ${show(map["RR_PRESSURE"])}"; diagnostics.text = reads.joinToString("\n") { "${it.signal.name}: ${it.value} ${it.signal.unit} [${it.state}]" } }
    private fun show(r: Reading?): String = if (r == null || r.state != "OK") "UNAVAILABLE" else "${r.value} ${r.signal.unit}" 
    private fun updateGps() { if (checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION) != PackageManager.PERMISSION_GRANTED && checkSelfPermission(Manifest.permission.ACCESS_COARSE_LOCATION) != PackageManager.PERMISSION_GRANTED) { requestPermissions(arrayOf(Manifest.permission.ACCESS_FINE_LOCATION, Manifest.permission.ACCESS_COARSE_LOCATION), locationCode); return }; val lm = getSystemService(Context.LOCATION_SERVICE) as LocationManager; val provider = when { lm.isProviderEnabled(LocationManager.GPS_PROVIDER) -> LocationManager.GPS_PROVIDER; lm.isProviderEnabled(LocationManager.NETWORK_PROVIDER) -> LocationManager.NETWORK_PROVIDER; else -> null }; if (provider == null) { diagnostics.text = "GPS: UNAVAILABLE"; return }; val listener = object : LocationListener { override fun onLocationChanged(l: Location) { diagnostics.text = "GPS\nlatitude: ${l.latitude}\nlongitude: ${l.longitude}\naccuracy: ${l.accuracy}\nspeed: ${l.speed}\nbearing: ${l.bearing}\ntimestamp: ${l.time}\nprovider: ${l.provider}" } }; lm.requestLocationUpdates(provider, 0L, 0f, listener); lm.getLastKnownLocation(provider)?.let { listener.onLocationChanged(it) } }
    private fun diagnosticText(): String = "Telemetry catalog: ${SIGNALS.size} static read-only signals\nAllowed autoservice transactions: 5, 7\nNo network or vehicle permissions\nSentinels: UNAVAILABLE\nGPS: point-in-time only"
    private fun readSignal(s: Signal): Reading { if (s.tx != 5 && s.tx != 7) return Reading(s, "unavailable", "ERROR"); return try { val p = ProcessBuilder("/system/bin/service", "call", "autoservice", s.tx.toString(), "i32", s.device.toString(), "i32", s.fid.toString()).redirectErrorStream(true).start(); val out = ByteArrayOutputStream(); p.inputStream.use { it.copyTo(out) }; val raw = out.toString(Charsets.UTF_8.name()); val word = Regex("Parcel\\(00000000\\s+([0-9a-fA-F]{8})").find(raw)?.groupValues?.get(1)?.toLong(16)?.toInt() ?: return Reading(s, "unavailable", "UNAVAILABLE", raw); if (word == 0x0000ffff || word == 0xffffd8e5.toInt() || word == 0x0000ffff) return Reading(s, "unavailable", "SENTINEL", raw); val value = when (s.decode) { Decode.FLOAT -> Float.fromBits(word).toString(); Decode.TENTH -> (word / 10.0).toString(); Decode.MILLI -> (word / 1000.0).toString(); else -> word.toString() }; Reading(s, value, "OK", raw) } catch (e: Exception) { Reading(s, "unavailable", "ERROR", e.message ?: "error") } }
}
