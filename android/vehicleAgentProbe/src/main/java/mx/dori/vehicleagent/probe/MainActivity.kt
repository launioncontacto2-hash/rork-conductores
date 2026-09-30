package mx.dori.vehicleagent.probe

import android.app.Activity
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.view.ViewGroup
import android.widget.Button
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

private data class ProbeResult(
    val uri: String,
    val state: String,
    val columns: List<String> = emptyList(),
    val rows: Int = 0,
    val exception: String? = null,
    val soc: String = "unavailable",
    val odo: String = "unavailable",
    val socSource: String = "unavailable",
    val odoSource: String = "unavailable"
)

class MainActivity : Activity() {
    private lateinit var log: TextView
    private val commonPermissions = listOf(
        "android.permission.BYDAUTO_ENERGY_COMMON",
        "android.permission.BYDAUTO_CHARGING_COMMON",
        "android.permission.BYDAUTO_INSTRUMENT_COMMON"
    )
    private val candidateUris = listOf(
        "content://com.byd.carStatusProvider",
        "content://com.byd.carStatusProvider/status"
    )
    private val permissionRequestCode = 501

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(28, 24, 28, 24)
            setBackgroundColor(0xFF101216.toInt())
        }
        fun label(value: String, size: Float = 18f) = TextView(this).apply {
            text = value
            textSize = size
            setTextColor(0xFFF5F5F5.toInt())
            setPadding(0, 7, 0, 7)
        }
        root.addView(label("DORI Vehicle Agent Probe", 26f))
        root.addView(label("Version 0.5 · lectura local read-only", 15f))
        root.addView(label("Provider: com.byd.carStatusProvider", 14f))
        root.addView(label("Sin Supabase · sin red requerida · sin controles", 14f))
        root.addView(label("Sistema: Android ${Build.VERSION.RELEASE} (API ${Build.VERSION.SDK_INT})"))
        root.addView(label("Permisos BYD COMMON", 20f))
        commonPermissions.forEach { permission ->
            root.addView(label("${permission.substringAfterLast('.')}: ${permissionState(permission)}", 14f))
        }
        val authorize = Button(this).apply {
            text = "AUTORIZAR LECTURA BYD"
            setOnClickListener { requestCommonPermissions() }
        }
        root.addView(authorize, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT))
        val diagnostics = Button(this).apply {
            text = "DIAGNÓSTICO BYD"
            setOnClickListener { runDiagnostics() }
        }
        root.addView(diagnostics, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT))
        val read = Button(this).apply {
            text = "LEER VEHÍCULO"
            setOnClickListener { readVehicle() }
        }
        root.addView(read, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT))
        root.addView(label("Resultados", 20f))
        log = label("Estado: pendiente\nSOC: unavailable\nODO: unavailable\nSource: —", 15f)
        log.setTextIsSelectable(true)
        root.addView(ScrollView(this).apply { addView(log) }, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, 0, 1f))
        setContentView(root)
    }

    private fun permissionState(permission: String): String = try {
        packageManager.getPermissionInfo(permission, 0)
        when {
            checkSelfPermission(permission) == PackageManager.PERMISSION_GRANTED -> "GRANTED"
            Build.VERSION.SDK_INT >= 23 && !shouldShowRequestPermissionRationale(permission) -> "DENIED_PERMANENTLY"
            else -> "DENIED"
        }
    } catch (_: PackageManager.NameNotFoundException) {
        "NOT AVAILABLE"
    } catch (_: SecurityException) {
        "SECURITY_EXCEPTION"
    }

    private fun requestCommonPermissions() {
        val pending = commonPermissions.filter { permissionState(it) != "GRANTED" && permissionState(it) != "NOT AVAILABLE" }
        if (pending.isEmpty()) {
            log.text = "Permisos COMMON: GRANTED\nNo hay permisos pendientes."
        } else if (Build.VERSION.SDK_INT >= 23) {
            requestPermissions(pending.toTypedArray(), permissionRequestCode)
        }
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, results: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, results)
        if (requestCode == permissionRequestCode) {
            log.text = commonPermissions.joinToString("\n") { "${it.substringAfterLast('.')}: ${permissionState(it)}" }
        }
    }

    private fun runDiagnostics() {
        val result = StringBuilder("DORI BYD diagnostics\nProvider: com.byd.carStatusProvider\n")
        commonPermissions.forEach { permission ->
            result.append(permission.substringAfterLast('.')).append(": ").append(permissionState(permission)).append('\n')
        }
        candidateUris.forEach { raw ->
            val probe = queryUri(raw)
            result.append("URI: ").append(probe.uri).append("\n")
                .append("Resultado: ").append(probe.state).append("\n")
                .append("Columnas: ").append(if (probe.columns.isEmpty()) "—" else probe.columns.joinToString(", ")).append("\n")
                .append("Filas: ").append(probe.rows).append("\n")
            probe.exception?.let { result.append("Excepción: ").append(it).append('\n') }
        }
        result.append("Read at: ").append(now())
        log.text = result.toString()
    }

    private fun queryUri(raw: String): ProbeResult = try {
        contentResolver.query(Uri.parse(raw), null, null, null, null)?.use { cursor ->
            val columns = cursor.columnNames.toList()
            var rows = 0
            while (cursor.moveToNext()) rows++
            ProbeResult(raw, if (rows > 0) "AVAILABLE" else "EMPTY", columns, rows)
        } ?: ProbeResult(raw, "NOT AVAILABLE")
    } catch (e: SecurityException) {
        ProbeResult(raw, "SECURITY_EXCEPTION", exception = e.message?.take(160))
    } catch (e: IllegalArgumentException) {
        ProbeResult(raw, "ILLEGAL_ARGUMENT", exception = e.message?.take(160))
    } catch (e: Exception) {
        ProbeResult(raw, "UNKNOWN_URI", exception = e.message?.take(160))
    }

    private fun readVehicle() {
        val results = candidateUris.map { raw -> queryVehicle(raw) }
        val available = results.firstOrNull { it.state == "AVAILABLE" }
        val output = StringBuilder("DORI BYD vehicle read\nProvider: com.byd.carStatusProvider\n")
        results.forEach { probe ->
            output.append("URI: ").append(probe.uri).append(" · ").append(probe.state)
                .append(" · filas=").append(probe.rows).append("\n")
        }
        if (available == null) {
            output.append("SOC: unavailable\nODO: unavailable\nSource: —\n")
        } else {
            output.append("SOC: ").append(available.soc).append("\nSource: ").append(available.socSource).append("\n")
                .append("ODO: ").append(available.odo).append("\nSource: ").append(available.odoSource).append("\n")
        }
        output.append("Read at: ").append(now())
        log.text = output.toString()
    }

    private fun queryVehicle(raw: String): ProbeResult = try {
        contentResolver.query(Uri.parse(raw), null, null, null, null)?.use { cursor ->
            val columns = cursor.columnNames.toList()
            var rows = 0
            var soc = "unavailable"
            var odo = "unavailable"
            var socSource = "unavailable"
            var odoSource = "unavailable"
            while (cursor.moveToNext()) {
                rows++
                for (i in 0 until cursor.columnCount) {
                    val name = cursor.getColumnName(i)
                    val normalized = name.lowercase(Locale.US)
                    val value = if (isSensitive(normalized)) "<REDACTED>" else cursor.getString(i) ?: "unavailable"
                    when {
                        normalized == "soc" || normalized.contains("battery") || normalized.contains("charge_percent") || normalized == "energy" -> {
                            if (soc == "unavailable") { soc = value; socSource = "$raw + $name" }
                        }
                        normalized == "odo" || normalized.contains("odometer") || normalized.contains("mileage") -> {
                            if (odo == "unavailable") { odo = value; odoSource = "$raw + $name" }
                        }
                    }
                }
            }
            ProbeResult(raw, if (rows > 0) "AVAILABLE" else "EMPTY", columns, rows, soc = soc, odo = odo, socSource = socSource, odoSource = odoSource)
        } ?: ProbeResult(raw, "NOT AVAILABLE")
    } catch (e: SecurityException) {
        ProbeResult(raw, "SECURITY_EXCEPTION", exception = e.message?.take(160))
    } catch (e: IllegalArgumentException) {
        ProbeResult(raw, "ILLEGAL_ARGUMENT", exception = e.message?.take(160))
    } catch (e: Exception) {
        ProbeResult(raw, "UNKNOWN_URI", exception = e.message?.take(160))
    }

    private fun isSensitive(name: String): Boolean = listOf("vin", "imei", "iccid", "serial", "account", "token").any { name.contains(it) }

    private fun now(): String = SimpleDateFormat("yyyy-MM-dd HH:mm:ss z", Locale.US).format(Date())
}
