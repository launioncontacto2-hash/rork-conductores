package mx.dori.vehicleagent.probe

import android.app.Activity
import android.content.pm.PackageManager
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
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
        val root = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL; setPadding(28, 24, 28, 24); setBackgroundColor(0xFF101216.toInt()) }
        fun label(value: String, size: Float = 18f) = TextView(this).apply { text = value; textSize = size; setTextColor(0xFFF5F5F5.toInt()); setPadding(0, 8, 0, 8) }
        root.addView(label("DORI Vehicle Agent Probe", 26f))
        root.addView(label("Lectura local read-only · sin Supabase · sin controles", 14f))
        root.addView(label("Sistema: Android " + Build.VERSION.RELEASE + " (API " + Build.VERSION.SDK_INT + ")"))
        root.addView(label("Red: " + networkState()))
        root.addView(label("Acceso vehículo: inspección normal, sin bypass"))
        root.addView(label("Permisos GET", 20f))
        getPermissions.forEach { permission -> root.addView(label(permission.substringAfterLast('.') + ": " + permissionState(permission), 14f)) }
        val read = Button(this).apply { text = "LEER VEHÍCULO"; setOnClickListener { readVehicle() } }
        root.addView(read, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT))
        root.addView(label("Diagnóstico", 20f))
        log = label("Source: unavailable\nBattery: unavailable\nOdometer: unavailable\nRead at: —\nProvider timestamp: unavailable", 15f)
        log.setTextIsSelectable(true)
        val scroll = ScrollView(this).apply { addView(log) }
        root.addView(scroll, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, 0, 1f))
        setContentView(root)
    }

    private fun permissionState(permission: String): String = try {
        packageManager.getPermissionInfo(permission, 0)
        if (checkSelfPermission(permission) == PackageManager.PERMISSION_GRANTED) "GRANTED" else "DENIED"
    } catch (_: PackageManager.NameNotFoundException) { "NOT AVAILABLE" }

    private fun networkState(): String {
        val cm = getSystemService(ConnectivityManager::class.java) ?: return "unavailable"
        val n = cm.activeNetwork ?: return "offline"
        val c = cm.getNetworkCapabilities(n) ?: return "offline"
        return if (c.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)) "available" else "offline"
    }

    private fun readVehicle() {
        var found: Snapshot? = null
        for (raw in candidateUris) {
            try {
                contentResolver.query(android.net.Uri.parse(raw), null, null, null, null)?.use { cursor ->
                    if (cursor.moveToFirst()) {
                        var battery = "unavailable"; var odo = "unavailable"; var providerTs = "unavailable"
                        for (i in 0 until cursor.columnCount) {
                            val name = cursor.getColumnName(i).lowercase(Locale.US); val value = cursor.getString(i) ?: continue
                            when {
                                name.contains("battery") || name == "soc" || name.contains("charge_percent") -> battery = value
                                name.contains("odometer") || name == "odo" || name.contains("mileage") -> odo = value
                                name.contains("timestamp") || name.contains("updated") -> providerTs = value
                            }
                        }
                        found = Snapshot(raw, battery, odo, providerTs)
                    }
                }
            } catch (_: SecurityException) { } catch (_: Exception) { }
            if (found != null) break
        }
        val s = found ?: Snapshot("unavailable", "unavailable", "unavailable", "unavailable")
        log.text = "Source: " + s.source + "\nBattery / SOC: " + s.battery + "\nOdometer: " + s.odometer + "\nRead at: " + now() + "\nProvider timestamp: " + s.providerTimestamp
    }

    private fun now() = SimpleDateFormat("yyyy-MM-dd HH:mm:ss z", Locale.US).format(Date())
}
