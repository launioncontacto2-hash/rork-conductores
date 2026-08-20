package com.rork.turnoevandroid.ui.theme

import android.app.Activity
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.darkColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.SideEffect
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.view.WindowCompat
import androidx.compose.foundation.Canvas
import androidx.compose.ui.draw.drawBehind

/** Fleet-ops palette: near-black canvas, single acid-lime accent, amber/red for risk. */
object Palette {
    val canvas = Color(0xFF070909)
    val surface = Color(0xFF101519)
    val surfaceRaised = Color(0xFF161B20)
    val hairline = Color(0xFF1E262C)
    val volt = Color(0xFFC8FF3C)
    val amber = Color(0xFFFFB020)
    val danger = Color(0xFFFF4D4F)
    val info = Color(0xFF4DE1FF)
    /** Workshop accent used by the maintenance role. */
    val ember = Color(0xFFFF7A4B)

    /** Executive accent used by national direction. */
    val royal = Color(0xFFBAA3FF)
    val textPrimary = Color(0xFFF3F6F4)
    val textMuted = Color(0xFF8F99A2)
}

private val TurnoColorScheme = darkColorScheme(
    primary = Palette.volt,
    onPrimary = Palette.canvas,
    secondary = Palette.info,
    onSecondary = Palette.canvas,
    background = Palette.canvas,
    onBackground = Palette.textPrimary,
    surface = Palette.surface,
    onSurface = Palette.textPrimary,
    surfaceVariant = Palette.surfaceRaised,
    onSurfaceVariant = Palette.textMuted,
    error = Palette.danger,
    onError = Color.White,
    outline = Palette.hairline,
)

/** Digits stay tabular so counters and money never jitter. */
val TabularNumbers = FontFamily.Monospace

@Composable
fun TurnoEVTheme(content: @Composable () -> Unit) {
    val view = LocalView.current
    if (!view.isInEditMode) {
        SideEffect {
            val window = (view.context as Activity).window
            WindowCompat.getInsetsController(window, view).isAppearanceLightStatusBars = false
        }
    }
    LocalContext.current
    MaterialTheme(colorScheme = TurnoColorScheme, content = content)
}

/** Station floor backdrop: charcoal with a lime pool of light and a faint service grid. */
@Composable
fun StationBackground(modifier: Modifier = Modifier) {
    Box(
        modifier
            .fillMaxSize()
            .background(Palette.canvas)
            .drawBehind {
                drawRect(
                    brush = Brush.radialGradient(
                        colors = listOf(Palette.volt.copy(alpha = 0.13f), Color.Transparent),
                        center = Offset(size.width * 0.5f, -size.height * 0.05f),
                        radius = size.height * 0.62f,
                    ),
                )
                drawRect(
                    brush = Brush.radialGradient(
                        colors = listOf(Palette.info.copy(alpha = 0.07f), Color.Transparent),
                        center = Offset(size.width * 1.05f, size.height * 1.02f),
                        radius = size.height * 0.5f,
                    ),
                )
            },
    ) {
        ServiceGrid()
    }
}

@Composable
private fun ServiceGrid() {
    Canvas(Modifier.fillMaxSize()) {
        val step = 44.dp.toPx()
        val stroke = Stroke(width = 1f)
        val color = Color.White.copy(alpha = 0.022f)
        var x = 0f
        while (x <= size.width) {
            drawLine(color, Offset(x, 0f), Offset(x, size.height), strokeWidth = stroke.width)
            x += step
        }
        var y = 0f
        while (y <= size.height) {
            drawLine(color, Offset(0f, y), Offset(size.width, y), strokeWidth = stroke.width)
            y += step
        }
    }
}

/** Elevated operational card. */
fun Modifier.panel(cornerRadius: Dp = 26.dp): Modifier = this
    .background(Palette.surface.copy(alpha = 0.9f), RoundedCornerShape(cornerRadius))
    .border(1.dp, Palette.hairline, RoundedCornerShape(cornerRadius))

/** Flat inner block used for stats and rows. */
fun Modifier.panelFlat(cornerRadius: Dp = 18.dp): Modifier = this
    .background(Palette.surfaceRaised.copy(alpha = 0.75f), RoundedCornerShape(cornerRadius))
    .border(1.dp, Palette.hairline.copy(alpha = 0.8f), RoundedCornerShape(cornerRadius))

/** Uppercase micro-label used across every screen. */
@Composable
fun CapsLabel(
    text: String,
    modifier: Modifier = Modifier,
    color: Color = Palette.textMuted,
) {
    Text(
        text = text.uppercase(),
        modifier = modifier,
        style = TextStyle(
            fontSize = 10.sp,
            fontWeight = FontWeight.SemiBold,
            letterSpacing = 1.6.sp,
            color = color,
        ),
    )
}
