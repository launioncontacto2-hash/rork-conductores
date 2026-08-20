package com.rork.turnoevandroid.ui.components

import android.graphics.Bitmap
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
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
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.PhotoCamera
import androidx.compose.material.icons.filled.Schedule
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.rork.turnoevandroid.FleetViewModel
import com.rork.turnoevandroid.domain.ShiftRules
import com.rork.turnoevandroid.ui.theme.CapsLabel
import com.rork.turnoevandroid.ui.theme.Palette
import com.rork.turnoevandroid.ui.theme.TabularNumbers
import com.rork.turnoevandroid.ui.theme.panelFlat
import com.rork.turnoevandroid.util.Fmt

/**
 * Tappable evidence slot. Uses the device camera when one is available and keeps a
 * thumbnail of the capture; on hardware without a camera the slot is still signed off
 * so the shift log stays complete.
 */
@Composable
fun PhotoSlot(
    title: String,
    captured: Boolean,
    thumbnail: Bitmap?,
    onCapture: (Bitmap?) -> Unit,
    modifier: Modifier = Modifier,
    hint: String? = null,
) {
    val launcher = rememberLauncherForActivityResult(ActivityResultContracts.TakePicturePreview()) { bitmap ->
        onCapture(bitmap)
    }
    val shape = RoundedCornerShape(18.dp)

    Box(
        modifier
            .fillMaxWidth()
            .height(116.dp)
            .clip(shape)
            .background(if (captured) Color.Black else Palette.surfaceRaised.copy(alpha = 0.55f))
            .clickable {
                val launched = runCatching { launcher.launch(null) }.isSuccess
                if (!launched) onCapture(null)
            }
            .then(
                if (captured) {
                    Modifier.border(1.dp, Palette.volt.copy(alpha = 0.6f), shape)
                } else {
                    Modifier.dashedBorder(shape)
                },
            ),
        contentAlignment = Alignment.Center,
    ) {
        if (captured) {
            if (thumbnail != null) {
                androidx.compose.foundation.Image(
                    bitmap = thumbnail.asImageBitmap(),
                    contentDescription = null,
                    contentScale = ContentScale.Crop,
                    alpha = 0.65f,
                    modifier = Modifier.fillMaxSize(),
                )
            }
            Column(
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(6.dp),
            ) {
                Box(
                    Modifier
                        .size(34.dp)
                        .background(Palette.volt, CircleShape),
                    contentAlignment = Alignment.Center,
                ) {
                    Icon(Icons.Filled.Check, null, Modifier.size(20.dp), tint = Palette.canvas)
                }
                Text(
                    title,
                    style = TextStyle(fontSize = 11.sp, fontWeight = FontWeight.Bold, color = Palette.textPrimary),
                    modifier = Modifier
                        .clip(CircleShape)
                        .background(Color.Black.copy(alpha = 0.6f))
                        .padding(horizontal = 8.dp, vertical = 3.dp),
                )
            }
        } else {
            Column(
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(5.dp),
                modifier = Modifier.padding(8.dp),
            ) {
                Icon(Icons.Filled.PhotoCamera, null, Modifier.size(22.dp), tint = Palette.textMuted)
                Text(
                    title,
                    style = TextStyle(fontSize = 13.sp, fontWeight = FontWeight.Bold, color = Palette.textPrimary),
                    textAlign = TextAlign.Center,
                )
                if (hint != null) {
                    Text(
                        hint,
                        style = TextStyle(fontSize = 10.sp, color = Palette.textMuted),
                        textAlign = TextAlign.Center,
                    )
                }
            }
        }
    }
}

/** Dashed outline for the empty evidence slots. */
private fun Modifier.dashedBorder(shape: RoundedCornerShape): Modifier = this.drawBehind {
    drawRoundRect(
        color = Palette.hairline,
        cornerRadius = CornerRadius(18.dp.toPx()),
        style = Stroke(
            width = 1.dp.toPx(),
            pathEffect = PathEffect.dashPathEffect(floatArrayOf(14f, 10f)),
        ),
    )
}

/** Camera viewfinder framing with an animated sweep line. */
@Composable
fun ScannerFrame(modifier: Modifier = Modifier) {
    val transition = rememberInfiniteTransition(label = "scanner")
    val sweep by transition.animateFloat(
        initialValue = 0f,
        targetValue = 1f,
        animationSpec = infiniteRepeatable(tween(1_900), RepeatMode.Reverse),
        label = "sweep",
    )

    Canvas(modifier.fillMaxSize()) {
        val side = minOf(size.width, size.height) * 0.6f
        val left = (size.width - side) / 2
        val top = (size.height - side) / 2
        val corner = side * 0.24f
        val stroke = Stroke(width = 4.dp.toPx(), cap = StrokeCap.Round)

        fun corner(x: Float, y: Float, dx: Float, dy: Float) {
            drawLine(Palette.volt, Offset(x, y), Offset(x + dx * corner, y), strokeWidth = stroke.width, cap = StrokeCap.Round)
            drawLine(Palette.volt, Offset(x, y), Offset(x, y + dy * corner), strokeWidth = stroke.width, cap = StrokeCap.Round)
        }

        corner(left, top, 1f, 1f)
        corner(left + side, top, -1f, 1f)
        corner(left, top + side, 1f, -1f)
        corner(left + side, top + side, -1f, -1f)

        val y = top + 10 + (side - 20) * sweep
        drawLine(
            color = Palette.volt,
            start = Offset(left + 6, y),
            end = Offset(left + side - 6, y),
            strokeWidth = 2.dp.toPx(),
        )
    }
}

private data class ClockPreset(val label: String, val hint: String, val minutes: Int?)

private val clockPresets = listOf(
    ClockPreset("Hora real", "Reloj del dispositivo", null),
    ClockPreset("05:05", "Inicio a tiempo", 5 * 60 + 5),
    ClockPreset("05:35", "Inicio con atraso", 5 * 60 + 35),
    ClockPreset("10:00", "Turno activo", 10 * 60),
    ClockPreset("13:40", "Cierre de turno", 13 * 60 + 40),
    ClockPreset("04:15", "Pago de atraso", 4 * 60 + 15),
)

/** Demo clock control: the app always reads the device time, this offsets it. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun DemoClockButton(viewModel: FleetViewModel, now: Long, offsetMinutes: Int, modifier: Modifier = Modifier) {
    var isSheetOpen by remember { mutableStateOf(false) }
    val sheetState = rememberModalBottomSheetState()
    val isDemo = offsetMinutes != 0
    val tint = if (isDemo) Palette.amber else Palette.textPrimary

    Row(
        modifier
            .clip(CircleShape)
            .background(Palette.surfaceRaised)
            .border(1.dp, if (isDemo) Palette.amber.copy(alpha = 0.5f) else Palette.hairline, CircleShape)
            .clickable { isSheetOpen = true }
            .padding(horizontal = 10.dp, vertical = 6.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(5.dp),
    ) {
        Icon(Icons.Filled.Schedule, null, Modifier.size(14.dp), tint = tint)
        Text(
            Fmt.clock(now),
            style = TextStyle(
                fontSize = 12.sp,
                fontWeight = FontWeight.SemiBold,
                fontFamily = TabularNumbers,
                color = tint,
            ),
        )
        if (isDemo) {
            Text("DEMO", style = TextStyle(fontSize = 8.sp, fontWeight = FontWeight.Black, color = Palette.amber))
        }
    }

    if (isSheetOpen) {
        ModalBottomSheet(
            onDismissRequest = { isSheetOpen = false },
            sheetState = sheetState,
            containerColor = Palette.surface,
        ) {
            Column(
                Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 20.dp)
                    .padding(bottom = 28.dp),
                verticalArrangement = Arrangement.spacedBy(14.dp),
            ) {
                Text(
                    "Reloj de demostración",
                    style = TextStyle(fontSize = 18.sp, fontWeight = FontWeight.Black, color = Palette.textPrimary),
                )
                Text(
                    "El sistema toma la hora del dispositivo. Ajusta el reloj simulado para revisar cada regla de turno.",
                    style = TextStyle(fontSize = 13.sp, color = Palette.textMuted),
                )
                clockPresets.chunked(2).forEach { row ->
                    Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                        row.forEach { preset ->
                            Column(
                                Modifier
                                    .weight(1f)
                                    .panelFlat()
                                    .clickable {
                                        viewModel.setSimulatedTime(preset.minutes)
                                        isSheetOpen = false
                                    }
                                    .padding(12.dp),
                                verticalArrangement = Arrangement.spacedBy(3.dp),
                            ) {
                                Text(
                                    preset.label,
                                    style = TextStyle(
                                        fontSize = 15.sp,
                                        fontWeight = FontWeight.Bold,
                                        fontFamily = TabularNumbers,
                                        color = Palette.textPrimary,
                                    ),
                                )
                                Text(preset.hint, style = TextStyle(fontSize = 11.sp, color = Palette.textMuted))
                            }
                        }
                        if (row.size == 1) Spacer(Modifier.weight(1f))
                    }
                }
                CapsLabel("Hora simulada ${Fmt.clockSeconds(now)} · minuto ${ShiftRules.minutesOfDay(now)}")
            }
        }
    }
}

/** Simple horizontal divider matching the fleet hairline. */
@Composable
fun Hairline(modifier: Modifier = Modifier) {
    Box(
        modifier
            .fillMaxWidth()
            .height(1.dp)
            .background(Palette.hairline),
    )
}

/** Vertical hairline used between inline cells. */
@Composable
fun VerticalHairline(height: androidx.compose.ui.unit.Dp = 44.dp) {
    Box(
        Modifier
            .width(1.dp)
            .height(height)
            .background(Palette.hairline),
    )
}
