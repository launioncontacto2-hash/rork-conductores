package com.rork.turnoevandroid.ui.screens

import android.media.MediaPlayer
import android.net.Uri
import android.util.Log
import android.widget.VideoView
import androidx.compose.animation.Crossfade
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Pause
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material3.Text
import com.rork.turnoevandroid.R
import com.rork.turnoevandroid.domain.CreditProgram
import com.rork.turnoevandroid.ui.components.BigButton
import com.rork.turnoevandroid.ui.components.ProgressTrack
import com.rork.turnoevandroid.ui.theme.CapsLabel
import com.rork.turnoevandroid.ui.theme.Palette
import com.rork.turnoevandroid.ui.theme.TabularNumbers
import com.rork.turnoevandroid.util.Fmt
import kotlinx.coroutines.delay

/** Explainer for the credit program: looping fleet clip, narration and synced captions. */
@Composable
fun CreditHowItWorksScreen() {
    val context = LocalContext.current
    var isPlaying by remember { mutableStateOf(false) }
    var elapsed by remember { mutableFloatStateOf(0f) }
    var duration by remember { mutableFloatStateOf(0f) }

    val player = remember {
        runCatching {
            MediaPlayer.create(context, R.raw.credit_narration)?.apply { isLooping = false }
        }.onFailure { error ->
            Log.w("CreditHowItWorks", "No se pudo preparar la narración: ${error.message}")
        }.getOrNull()
    }

    DisposableEffect(player) {
        duration = (player?.duration ?: 0) / 1000f
        player?.start()
        isPlaying = player != null
        onDispose {
            runCatching {
                player?.stop()
                player?.release()
            }
        }
    }

    LaunchedEffect(isPlaying) {
        while (isPlaying) {
            delay(150)
            val current = player ?: break
            elapsed = current.currentPosition / 1000f
            if (!current.isPlaying) {
                isPlaying = false
                if (duration > 0) elapsed = duration
            }
        }
    }

    val caption = CreditProgram.captions.lastOrNull { elapsed >= it.start }?.text
        ?: CreditProgram.captions.firstOrNull()?.text.orEmpty()

    Box(Modifier.fillMaxSize().background(Palette.canvas)) {
        AndroidView(
            factory = { ctx ->
                VideoView(ctx).apply {
                    setVideoURI(Uri.parse("android.resource://${ctx.packageName}/${R.raw.credit_explainer}"))
                    setOnPreparedListener { media ->
                        media.isLooping = true
                        media.setVolume(0f, 0f)
                        start()
                    }
                }
            },
            modifier = Modifier.fillMaxSize(),
        )

        Box(
            Modifier
                .fillMaxSize()
                .background(
                    Brush.verticalGradient(
                        listOf(Palette.canvas.copy(alpha = 0.35f), Palette.canvas.copy(alpha = 0.95f)),
                    ),
                ),
        )

        Column(
            Modifier
                .fillMaxSize()
                .padding(horizontal = 20.dp)
                .padding(top = 24.dp, bottom = 26.dp),
            verticalArrangement = Arrangement.Bottom,
        ) {
            CapsLabel("Cómo funciona")
            Spacer(Modifier.padding(4.dp))
            Text(
                "Bajamos el costo del riesgo, no lo cargamos al precio",
                style = TextStyle(fontSize = 20.sp, fontWeight = FontWeight.Black, color = Palette.textPrimary),
            )

            Spacer(Modifier.padding(11.dp))

            Crossfade(caption, label = "caption") { text ->
                Text(
                    text,
                    style = TextStyle(
                        fontSize = 17.sp,
                        fontWeight = FontWeight.SemiBold,
                        color = Palette.textPrimary.copy(alpha = 0.92f),
                    ),
                )
            }

            Spacer(Modifier.padding(12.dp))

            ProgressTrack(value = elapsed.toDouble(), goal = maxOf(duration.toDouble(), 1.0))

            Row(Modifier.fillMaxWidth().padding(top = 6.dp)) {
                Text(
                    Fmt.stopwatch(elapsed.toInt()),
                    style = TextStyle(
                        fontSize = 11.sp,
                        fontWeight = FontWeight.SemiBold,
                        fontFamily = TabularNumbers,
                        color = Palette.textMuted,
                    ),
                )
                Spacer(Modifier.weight(1f))
                Text(
                    Fmt.stopwatch(duration.toInt()),
                    style = TextStyle(
                        fontSize = 11.sp,
                        fontWeight = FontWeight.SemiBold,
                        fontFamily = TabularNumbers,
                        color = Palette.textMuted,
                    ),
                )
            }

            Spacer(Modifier.padding(9.dp))

            BigButton(
                title = when {
                    isPlaying -> "Pausar explicación"
                    elapsed > 0 -> "Continuar"
                    else -> "Reproducir explicación"
                },
                icon = if (isPlaying) Icons.Filled.Pause else Icons.Filled.PlayArrow,
                enabled = player != null,
            ) {
                val current = player ?: return@BigButton
                if (current.isPlaying) {
                    current.pause()
                    isPlaying = false
                } else {
                    if (duration > 0 && elapsed >= duration) current.seekTo(0)
                    current.start()
                    isPlaying = true
                }
            }

            if (player == null) {
                Text(
                    CreditProgram.howItWorksScript,
                    style = TextStyle(fontSize = 13.sp, color = Palette.textMuted),
                    modifier = Modifier.padding(top = 14.dp),
                )
            }
        }
    }
}
