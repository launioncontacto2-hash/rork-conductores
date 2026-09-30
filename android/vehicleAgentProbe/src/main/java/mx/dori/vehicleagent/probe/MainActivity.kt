package mx.dori.vehicleagent.probe

import android.app.Activity
import android.os.Bundle
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.Parcel
import android.view.ViewGroup
import android.widget.Button
import android.widget.LinearLayout
import android.widget.TextView
import java.net.HttpURLConnection
import java.net.URL
import java.time.Instant
import java.util.Locale
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean

private const val DEVICE = 1014
private const val TX_INT = 5
private const val TX_FLOAT = 7
private const val FID_SOC = 1246777400
private const val FID_ODO = 1246765072
private const val FID_POWER = 315621408
private data class Snapshot(val soc: Float?, val odo: Float?, val power: Int?, val detail: String)

class MainActivity : Activity() {
    private val executor = Executors.newSingleThreadExecutor()
    private val handler = Handler(Looper.getMainLooper())
    private val running = AtomicBoolean(false)
    private var sequence = 0L
    private lateinit var values: TextView
    private lateinit var connection: TextView
    private lateinit var lastSend: TextView
    private lateinit var sequenceView: TextView
    private lateinit var diagnostics: TextView

    override fun onCreate(state: Bundle?) {
        super.onCreate(state)
        val root = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL; setPadding(28, 24, 28, 24) }
        fun label(t: String, s: Float = 18f) = TextView(this).apply { text = t; textSize = s; setPadding(0, 6, 0, 6) }
        root.addView(label("DORI Vehicle Live Bridge", 27f)); root.addView(label("DMP-003 · solo lectura autoservice", 16f))
        values = label("SOC -- %   ODO -- km   Estado --", 23f); root.addView(values)
        connection = label("CONEXIÓN DORI: DETENIDA"); root.addView(connection)
        lastSend = label("Último envío: --"); root.addView(lastSend)
        sequenceView = label("Secuencia: 0"); root.addView(sequenceView)
        root.addView(Button(this).apply { text = "INICIAR ENLACE"; setOnClickListener { startLink() } })
        root.addView(Button(this).apply { text = "DETENER ENLACE"; setOnClickListener { running.set(false); connection.text = "CONEXIÓN DORI: DETENIDA" } })
        root.addView(Button(this).apply { text = "ENVIAR AHORA"; setOnClickListener { cycle() } })
        root.addView(Button(this).apply { text = "DIAGNÓSTICO"; setOnClickListener { diagnostics.text = "URL: ${BuildConfig.INGEST_URL}\nToken TEST: ${if (BuildConfig.AGENT_TOKEN.isBlank()) "NO CONFIGURADO" else "CONFIGURADO"}" } })
        diagnostics = label("Lectura pendiente", 14f); root.addView(diagnostics, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, 0, 1f)); setContentView(root)
    }
    private fun startLink() { if (running.compareAndSet(false, true)) { connection.text = "CONEXIÓN DORI: ENVIANDO"; cycle() } }
    private fun cycle() { executor.execute { val s = readSnapshot(); handler.post { values.text = "SOC ${s.soc?.let { "%.1f".format(Locale.US, it) } ?: "--"}%   ODO ${s.odo?.let { "%.1f".format(Locale.US, it) } ?: "--"} km   Estado ${s.power ?: "--"}"; diagnostics.text = s.detail }; if (running.get()) send(s); if (running.get()) handler.postDelayed({ cycle() }, 5_000) } }
    private fun send(s: Snapshot) { val soc=s.soc ?: return; val odo=s.odo ?: return; val next=++sequence; executor.execute { if (BuildConfig.AGENT_TOKEN.isBlank()) { handler.post { connection.text = "CONEXIÓN DORI: ERROR · TOKEN TEST NO CONFIGURADO" }; return@execute }; try { val c=URL(BuildConfig.INGEST_URL).openConnection() as HttpURLConnection; c.requestMethod="POST"; c.connectTimeout=4000; c.readTimeout=4000; c.doOutput=true; c.setRequestProperty("content-type","application/json"); c.setRequestProperty("x-dori-agent-token",BuildConfig.AGENT_TOKEN); c.outputStream.use { it.write("{\"vehicle_code\":\"DMP-003\",\"soc_percent\":$soc,\"odometer_km\":$odo,\"power_state\":${s.power ?: "null"},\"captured_at\":\"${Instant.now()}\",\"agent_version\":\"0.8\",\"sequence\":$next}".toByteArray()) }; val code=c.responseCode; handler.post { if (code in 200..299) { lastSend.text="Último envío: ${Instant.now()}"; sequenceView.text="Secuencia: $next" } else connection.text="CONEXIÓN DORI: ERROR HTTP $code" }; c.disconnect() } catch (_: Exception) { handler.post { connection.text="CONEXIÓN DORI: ERROR DE RED" } } } }
    private fun readSnapshot(): Snapshot = try { val b=Class.forName("android.os.ServiceManager").getDeclaredMethod("getService",String::class.java).invoke(null,"autoservice") as? IBinder ?: return Snapshot(null,null,null,"autoservice no disponible"); val soc=transactFloat(b,TX_FLOAT,FID_SOC); val odo=transactInt(b,TX_INT,FID_ODO)/10f; val power=transactInt(b,TX_INT,FID_POWER); Snapshot(soc,odo,power,"autoservice: AVAILABLE · tx 5/7 · ${Instant.now()}") } catch (e: Exception) { Snapshot(null,null,null,"autoservice: ERROR ${e.javaClass.simpleName}") }
    private fun transactInt(b: IBinder, tx: Int, fid: Int): Int { check(tx == TX_INT); val d=Parcel.obtain(); val r=Parcel.obtain(); return try { d.writeInt(DEVICE); d.writeInt(fid); check(b.transact(tx,d,r,0)); r.readException(); r.readInt() } finally { d.recycle(); r.recycle() } }
    private fun transactFloat(b: IBinder, tx: Int, fid: Int): Float { check(tx == TX_FLOAT); val d=Parcel.obtain(); val r=Parcel.obtain(); return try { d.writeInt(DEVICE); d.writeInt(fid); check(b.transact(tx,d,r,0)); r.readException(); r.readFloat() } finally { d.recycle(); r.recycle() } }
}
