package mx.dori.vehicleagent.probe

import android.app.Activity
import android.os.Bundle
import android.os.IBinder
import android.os.Parcel
import android.view.ViewGroup
import android.widget.Button
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView
import java.io.ByteArrayOutputStream
import java.nio.charset.StandardCharsets
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

private const val DEVICE = 1014
private const val TX_GET_INT = 5
private const val TX_GET_FLOAT = 7
private const val FID_SOC = 1246777400
private const val FID_ODO = 1246765072

private data class Reading(val soc: Float?, val odo: Float?, val detail: String)

class MainActivity : Activity() {
    private lateinit var socValue: TextView
    private lateinit var odoValue: TextView
    private lateinit var channelValue: TextView
    private lateinit var diagnosticLog: TextView

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
        root.addView(label("Version 0.6 · autoservice read-only", 15f))
        root.addView(label("SOC", 20f))
        socValue = label("-- %", 34f)
        root.addView(socValue)
        root.addView(label("ODO", 20f))
        odoValue = label("-- km", 34f)
        root.addView(odoValue)
        root.addView(label("CANAL", 20f))
        channelValue = label("Pendiente", 20f)
        root.addView(channelValue)
        val read = Button(this).apply {
            text = "LEER SOC + ODO"
            setOnClickListener { readValues() }
        }
        root.addView(read, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT))
        val diagnostic = Button(this).apply {
            text = "DIAGNÓSTICO AUTOSERVICE"
            setOnClickListener { diagnose() }
        }
        root.addView(diagnostic, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT))
        diagnosticLog = label("autoservice: pendiente", 15f).apply { setTextIsSelectable(true) }
        root.addView(ScrollView(this).apply { addView(diagnosticLog) }, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, 0, 1f))
        setContentView(root)
    }

    private fun readValues() {
        val direct = directRead()
        if (direct.soc != null && direct.odo != null && direct.soc in 0f..100f && direct.odo >= 0f) {
            showReading(direct, "DIRECT_BINDER")
            diagnosticLog.text = direct.detail
            return
        }
        val fallback = binaryRead()
        if (fallback.soc != null && fallback.odo != null && fallback.soc in 0f..100f && fallback.odo >= 0f) {
            showReading(fallback, "SERVICE_BINARY_APP_UID")
        } else {
            socValue.text = "unavailable"
            odoValue.text = "unavailable"
            channelValue.text = "BLOCKED"
        }
        diagnosticLog.text = "DIRECT_BINDER:\n${direct.detail}\n\nSERVICE_BINARY_APP_UID:\n${fallback.detail}"
    }

    private fun showReading(reading: Reading, channel: String) {
        socValue.text = "${"%.1f".format(Locale.US, reading.soc)} %"
        odoValue.text = "${"%.1f".format(Locale.US, reading.odo)} km"
        channelValue.text = channel
    }

    private fun diagnose() {
        val direct = directRead()
        val fallback = binaryRead()
        val available = try {
            serviceBinder() != null
        } catch (_: Exception) {
            false
        }
        diagnosticLog.text = "autoservice: ${if (available) "AVAILABLE" else "NOT_AVAILABLE"}\n\nDIRECT_BINDER:\n${direct.detail}\n\nSERVICE_BINARY_APP_UID:\n${fallback.detail}"
    }

    private fun directRead(): Reading {
        var binder: IBinder? = null
        return try {
            binder = serviceBinder()
            if (binder == null) return Reading(null, null, "state: NOT_AVAILABLE\nerror: ServiceManager returned null")
            val soc = transactFloat(binder, TX_GET_FLOAT, FID_SOC)
            val odo = transactInt(binder, TX_GET_INT, FID_ODO) / 10.0f
            Reading(soc, odo, "state: AVAILABLE\nSOC: $soc\nODO: $odo\ntransactions: 7, 5")
        } catch (e: Exception) {
            Reading(null, null, "state: FAILED\nerror: ${e.javaClass.simpleName}: ${e.message ?: "unknown"}")
        }
    }

    private fun serviceBinder(): IBinder? {
        val manager = Class.forName("android.os.ServiceManager")
        val method = manager.getDeclaredMethod("getService", String::class.java)
        method.isAccessible = true
        return method.invoke(null, "autoservice") as? IBinder
    }

    private fun transactFloat(binder: IBinder, transaction: Int, field: Int): Float {
        check(transaction == TX_GET_FLOAT && field == FID_SOC)
        val data = Parcel.obtain()
        val reply = Parcel.obtain()
        return try {
            data.writeInt(DEVICE)
            data.writeInt(field)
            check(binder.transact(transaction, data, reply, 0))
            reply.readException()
            reply.readFloat()
        } finally {
            data.recycle()
            reply.recycle()
        }
    }

    private fun transactInt(binder: IBinder, transaction: Int, field: Int): Int {
        check(transaction == TX_GET_INT && field == FID_ODO)
        val data = Parcel.obtain()
        val reply = Parcel.obtain()
        return try {
            data.writeInt(DEVICE)
            data.writeInt(field)
            check(binder.transact(transaction, data, reply, 0))
            reply.readException()
            reply.readInt()
        } finally {
            data.recycle()
            reply.recycle()
        }
    }

    private fun binaryRead(): Reading {
        val soc = runServiceCall(TX_GET_FLOAT, FID_SOC)
        val odo = runServiceCall(TX_GET_INT, FID_ODO)
        val socValue = soc.word?.let { Float.fromBits(it) }
        val odoValue = odo.word?.toFloat()?.div(10.0f)
        val detail = "SOC state: ${soc.state}\nODO state: ${odo.state}\nexit code: ${soc.exitCode}/${odo.exitCode}\nParcel raw:\n${soc.raw}\n${odo.raw}" +
            "\nerror: ${soc.error ?: odo.error ?: "none"}"
        return Reading(socValue, odoValue, detail)
    }

    private data class ServiceResult(val state: String, val word: Int?, val exitCode: Int, val raw: String, val error: String?)

    private fun runServiceCall(transaction: Int, field: Int): ServiceResult {
        check(transaction == TX_GET_FLOAT || transaction == TX_GET_INT)
        check(field == FID_SOC || field == FID_ODO)
        return try {
            val process = ProcessBuilder("/system/bin/service", "call", "autoservice", transaction.toString(), "i32", DEVICE.toString(), "i32", field.toString())
                .redirectErrorStream(true).start()
            val output = ByteArrayOutputStream()
            process.inputStream.use { it.copyTo(output) }
            val exit = process.waitFor()
            val raw = output.toString(StandardCharsets.UTF_8.name()).trim()
            val match = Regex("Parcel\\(00000000\\s+([0-9a-fA-F]{8})").find(raw)
            val word = match?.groupValues?.get(1)?.toLong(16)?.toInt()
            ServiceResult(if (word != null) "AVAILABLE" else "NOT_AVAILABLE", word, exit, raw, if (word == null) "no parcel word" else null)
        } catch (e: Exception) {
            ServiceResult("FAILED", null, -1, "", "${e.javaClass.simpleName}: ${e.message ?: "unknown"}")
        }
    }
}
