package mx.dori.vehicleagent.probe

import android.app.Activity
import android.content.pm.PackageManager
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
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

private data class Snapshot(val source: String, val battery: String, val odometer: String, val providerTimestamp: String)

class MainActivity : Activity() {
    private lateinit var log: TextView
    private val getPermissions = listOf(
        "com.byd.auto.permission.BYDAUTO_ENERGY_GET",
        "com.byd.auto.permission.BYDAUTO_CHARGING_GET",
        "com.byd.auto.permission.BYDAUTO_INSTRUMENT_GET",
        "com.byd.auto.permission.BYDAUTO_VEHICLE_DATA_GET"
    )
    private val candidateUris = listOf(
        "content://com.byd.auto.carstatus/status",
        "content://com.byd.auto.candatacollect/data",
        "content://com.byd.auto.instrument/status"
    )

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
        root.addView(label("Version 0.3 · lectura local read-only", 15f))
        root.addView(label("Sin Supabase · sin red requerida · sin controles", 14f))
        root.addView(label("Sistema: Android ${Build.VERSION.RELEASE} (API ${Build.VERSION.SDK_INT})"))
        root.addView(label("Red: ${networkState()}"))
        root.addView(label("Acceso vehículo: inspección normal, sin bypass"))
        root.addView(label("Permisos BYD GET", 20f))
        getPermissions.forEach { permission ->
            root.addView(label("${permission.substringAfterLast('.')}: ${permissionState(permission)}", 14f))
        }
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
        log = label("Estado: pendiente\nSOC: —\nODO: —\nSource: —\nTimestamp: —", 15f)
        log.setTextIsSelectable(true)
        root.addView(ScrollView(this).apply { addView(log) }, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, 0, 1f))
        setContentView(root)
    }

    private fun permissionState(permission: String): String = try {
        packageManager.getPermissionInfo(permission, 0)
        if (checkSelfPermission(permission) == PackageManager.PERMISSION_GRANTED) "GRANTED" else "DENIED"
    } catch (_: PackageManager.NameNotFoundException) {
        "NOT AVAILABLE"
    } catch (_: SecurityException) {
        "SECURITY_EXCEPTION"
    }

    private fun networkState(): String {
        val cm = getSystemService(ConnectivityManager::class.java) ?: return "unavailable"
        val network = cm.activeNetwork ?: return "offline/local-only"
        val caps = cm.getNetworkCapabilities(network) ?: return "offline/local-only"
        return if (caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)) "available (not used)" else "offline/local-only"
    }

    private fun runDiagnostics() {
        val result = StringBuilder("DORI BYD diagnostics\n")
        getPermissions.forEach { permission ->
            result.append(permission.substringAfterLast('.')).append(": ").append(permissionState(permission)).append('\n')
        }
        candidateUris.forEach { raw ->
            result.append("Provider ").append(raw).append(": ")
            try {
                contentResolver.query(Uri.parse(raw), null, null, null, null)?.use { cursor ->
                    if (cursor.moveToFirst()) {
                        result.append("AVAILABLE")
                    } else {
                        result.append("EMPTY")
                    }
                } ?: result.append("NOT AVAILABLE")
            } catch (_: SecurityException) {
                result.append("SECURITY_EXCEPTION")
            } catch (_: Exception) {
                result.append("NOT AVAILABLE")
            }
            result.append('\n')
        }
        result.append("Read at: ").append(now())
        log.text = result.toString()
    }

    private fun readVehicle() {
        var found: Snapshot? = null
        var lastState = "NOT AVAILABLE"
        for (raw in candidateUris) {
            try {
                contentResolver.query(Uri.parse(raw), null, null, null, null)?.use { cursor ->
                    if (cursor.moveToFirst()) {
                        var battery = "unavailable"
                        var odo = "unavailable"
                        var providerTs = "unavailable"
                        for (i in 0 until cursor.columnCount) {
                            val name = cursor.getColumnName(i).lowercase(Locale.US)
                            val value = cursor.getString(i) ?: continue
                            when {
                                name.contains("battery") || name == "soc" || name.contains("charge_percent") -> battery = value
                                name.contains("odometer") || name == "odo" || name.contains("mileage") -> odo = value
                                name.contains("timestamp") || name.contains("updated") -> providerTs = value
                            }
                        }
                        found = Snapshot(raw, battery, odo, providerTs)
                        lastState = "AVAILABLE"
                    } else {
                        lastState = "EMPTY"
                    }
                } ?: run { lastState = "NOT AVAILABLE" }
            } catch (_: SecurityException) {
                lastState = "SECURITY_EXCEPTION"
            } catch (_: Exception) {
                lastState = "NOT AVAILABLE"
            }
            if (found != null) break
        }
        val snapshot = found
        log.text = if (snapshot == null) {
            "Estado: $lastState\nSOC: —\nODO: —\nSource: —\nTimestamp: ${now()}"
        } else {
            "Estado: AVAILABLE\nSOC: ${snapshot.battery}\nODO: ${snapshot.odometer}\nSource: ${snapshot.source}\nTimestamp: ${snapshot.providerTimestamp}\nRead at: ${now()}"
        }
    }

    private fun now(): String = SimpleDateFormat("yyyy-MM-dd HH:mm:ss z", Locale.US).format(Date())
}