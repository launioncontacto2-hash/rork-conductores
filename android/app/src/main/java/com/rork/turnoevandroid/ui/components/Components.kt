package com.rork.turnoevandroid.ui.components

import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.BatteryChargingFull
import androidx.compose.material.icons.filled.Battery3Bar
import androidx.compose.material.icons.filled.Battery5Bar
import androidx.compose.material3.Icon
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextFieldDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.rork.turnoevandroid.ui.theme.CapsLabel
import com.rork.turnoevandroid.ui.theme.Palette
import com.rork.turnoevandroid.ui.theme.TabularNumbers
import com.rork.turnoevandroid.ui.theme.panelFlat

enum class Tone {
    NEUTRAL,
    VOLT,
    AMBER,
    DANGER,
    INFO;

    val color: Color
        get() = when (this) {
            NEUTRAL -> Palette.textPrimary
            VOLT -> Palette.volt
            AMBER -> Palette.amber
            DANGER -> Palette.danger
            INFO -> Palette.info
        }
}

/** Big statistic block used across the operational screens. */
@Composable
fun StatTile(
    label: String,
    value: String,
    modifier: Modifier = Modifier,
    hint: String? = null,
    tone: Tone = Tone.NEUTRAL,
    icon: ImageVector? = null,
) {
    Column(
        modifier
            .panelFlat()
            .padding(14.dp),
        verticalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            CapsLabel(label, Modifier.weight(1f, fill = false))
            Spacer(Modifier.weight(1f))
            if (icon != null) {
                Icon(icon, null, Modifier.size(14.dp), tint = Palette.textMuted)
            }
        }
        Text(
            text = value,
            style = TextStyle(
                fontSize = 21.sp,
                fontWeight = FontWeight.Black,
                fontFamily = TabularNumbers,
                color = tone.color,
            ),
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
        )
        if (hint != null) {
            Text(
                hint,
                style = TextStyle(fontSize = 11.sp, color = Palette.textMuted),
                maxLines = 2,
                overflow = TextOverflow.Ellipsis,
            )
        }
    }
}

@Composable
fun BatteryPill(level: Int, modifier: Modifier = Modifier) {
    val tone = when {
        level > 70 -> Palette.volt
        level > 40 -> Palette.amber
        else -> Palette.danger
    }
    val icon = when {
        level > 70 -> Icons.Filled.BatteryChargingFull
        level > 40 -> Icons.Filled.Battery5Bar
        else -> Icons.Filled.Battery3Bar
    }
    Row(
        modifier
            .background(Palette.surfaceRaised, CircleShape)
            .border(1.dp, Palette.hairline, CircleShape)
            .padding(horizontal = 10.dp, vertical = 6.dp),
        horizontalArrangement = Arrangement.spacedBy(5.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Icon(icon, null, Modifier.size(15.dp), tint = tone)
        Text(
            "$level%",
            style = TextStyle(
                fontSize = 14.sp,
                fontWeight = FontWeight.Bold,
                fontFamily = TabularNumbers,
                color = tone,
            ),
        )
    }
}

@Composable
fun ProgressTrack(
    value: Double,
    goal: Double,
    modifier: Modifier = Modifier,
    tone: Color = Palette.volt,
    marker: Double? = null,
    height: Dp = 12.dp,
) {
    val ratio = if (goal > 0) (value / goal).coerceIn(0.0, 1.0).toFloat() else 0f
    val animated by animateFloatAsState(ratio, tween(700), label = "progress")
    Box(
        modifier
            .fillMaxWidth()
            .height(height)
            .clip(CircleShape)
            .background(Palette.surfaceRaised),
    ) {
        Box(
            Modifier
                .fillMaxWidth(animated)
                .height(height)
                .clip(CircleShape)
                .background(tone),
        )
        if (marker != null && goal > 0) {
            val markerRatio = (marker / goal).coerceIn(0.0, 1.0).toFloat()
            Box(
                Modifier
                    .fillMaxWidth(markerRatio)
                    .height(height),
                contentAlignment = Alignment.CenterEnd,
            ) {
                Box(
                    Modifier
                        .width(2.dp)
                        .height(height)
                        .background(Color.White.copy(alpha = 0.75f)),
                )
            }
        }
    }
}

/** Circular gauge used for the daily money goal and the delivery countdown. */
@Composable
fun RingGauge(
    value: Double,
    goal: Double,
    headline: String,
    caption: String,
    modifier: Modifier = Modifier,
    diameter: Dp = 176.dp,
    tone: Color = Palette.volt,
) {
    val ratio = if (goal > 0) (value / goal).coerceIn(0.0, 1.0).toFloat() else 0f
    val animated by animateFloatAsState(ratio, tween(900), label = "ring")
    Box(Modifier.size(diameter).then(modifier), contentAlignment = Alignment.Center) {
        Canvas(Modifier.fillMaxSize()) {
            val strokeWidth = 14.dp.toPx()
            val inset = strokeWidth / 2
            drawArc(
                color = Palette.surfaceRaised,
                startAngle = 0f,
                sweepAngle = 360f,
                useCenter = false,
                topLeft = androidx.compose.ui.geometry.Offset(inset, inset),
                size = androidx.compose.ui.geometry.Size(size.width - strokeWidth, size.height - strokeWidth),
                style = Stroke(width = strokeWidth),
            )
            drawArc(
                color = tone,
                startAngle = -90f,
                sweepAngle = 360f * animated,
                useCenter = false,
                topLeft = androidx.compose.ui.geometry.Offset(inset, inset),
                size = androidx.compose.ui.geometry.Size(size.width - strokeWidth, size.height - strokeWidth),
                style = Stroke(width = strokeWidth, cap = StrokeCap.Round),
            )
        }
        Column(
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(4.dp),
            modifier = Modifier.padding(30.dp),
        ) {
            Text(
                headline,
                style = TextStyle(
                    fontSize = 26.sp,
                    fontWeight = FontWeight.Black,
                    fontFamily = TabularNumbers,
                    color = Palette.textPrimary,
                ),
                maxLines = 1,
                textAlign = TextAlign.Center,
            )
            CapsLabel(caption)
        }
    }
}

enum class ButtonTone { VOLT, OUTLINE, DANGER }

/** Primary full-width action, sized for use with gloves on. */
@Composable
fun BigButton(
    title: String,
    modifier: Modifier = Modifier,
    icon: ImageVector? = null,
    tone: ButtonTone = ButtonTone.VOLT,
    enabled: Boolean = true,
    onClick: () -> Unit,
) {
    val background = when (tone) {
        ButtonTone.VOLT -> Palette.volt
        ButtonTone.OUTLINE -> Palette.surfaceRaised.copy(alpha = 0.8f)
        ButtonTone.DANGER -> Palette.danger
    }
    val foreground = when (tone) {
        ButtonTone.VOLT -> Palette.canvas
        ButtonTone.OUTLINE -> Palette.textPrimary
        ButtonTone.DANGER -> Color.White
    }
    val shape = RoundedCornerShape(18.dp)
    Row(
        modifier
            .fillMaxWidth()
            .defaultMinSize(minHeight = 58.dp)
            .clip(shape)
            .background(if (enabled) background else background.copy(alpha = 0.4f))
            .then(
                if (tone == ButtonTone.OUTLINE) Modifier.border(1.dp, Palette.hairline, shape) else Modifier,
            )
            .clickable(enabled = enabled) { onClick() }
            .padding(horizontal = 18.dp, vertical = 16.dp),
        horizontalArrangement = Arrangement.Center,
        verticalAlignment = Alignment.CenterVertically,
    ) {
        if (icon != null) {
            Icon(icon, null, Modifier.size(20.dp), tint = if (enabled) foreground else foreground.copy(alpha = 0.6f))
            Spacer(Modifier.width(10.dp))
        }
        Text(
            title,
            style = TextStyle(
                fontSize = 16.sp,
                fontWeight = FontWeight.Bold,
                color = if (enabled) foreground else foreground.copy(alpha = 0.6f),
            ),
            textAlign = TextAlign.Center,
        )
    }
}

/** Inline banner used for late starts, pending inspections and payback windows. */
@Composable
fun NoticeBanner(
    icon: ImageVector,
    title: String,
    modifier: Modifier = Modifier,
    message: String? = null,
    tone: Tone = Tone.AMBER,
    onClick: (() -> Unit)? = null,
) {
    val shape = RoundedCornerShape(18.dp)
    Row(
        modifier
            .fillMaxWidth()
            .clip(shape)
            .background(tone.color.copy(alpha = 0.1f))
            .border(1.dp, tone.color.copy(alpha = 0.4f), shape)
            .then(if (onClick != null) Modifier.clickable { onClick() } else Modifier)
            .padding(14.dp),
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Icon(icon, null, Modifier.size(20.dp), tint = tone.color)
        Column(verticalArrangement = Arrangement.spacedBy(3.dp)) {
            Text(
                title,
                style = TextStyle(fontSize = 14.sp, fontWeight = FontWeight.Bold, color = Palette.textPrimary),
            )
            if (message != null) {
                Text(message, style = TextStyle(fontSize = 13.sp, color = Palette.textMuted))
            }
        }
    }
}

/** Numeric capture field used for odometer and battery readings. */
@Composable
fun BigNumberField(
    title: String,
    placeholder: String,
    value: String,
    onValueChange: (String) -> Unit,
    modifier: Modifier = Modifier,
    icon: ImageVector? = null,
) {
    Column(modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
            if (icon != null) Icon(icon, null, Modifier.size(13.dp), tint = Palette.textMuted)
            CapsLabel(title)
        }
        OutlinedTextField(
            value = value,
            onValueChange = { input -> onValueChange(input.filter { it.isDigit() }.take(7)) },
            placeholder = {
                Text(
                    placeholder,
                    style = TextStyle(
                        fontSize = 26.sp,
                        fontWeight = FontWeight.Black,
                        fontFamily = TabularNumbers,
                        color = Palette.textMuted.copy(alpha = 0.5f),
                        textAlign = TextAlign.Center,
                    ),
                    modifier = Modifier.fillMaxWidth(),
                )
            },
            textStyle = TextStyle(
                fontSize = 26.sp,
                fontWeight = FontWeight.Black,
                fontFamily = TabularNumbers,
                color = Palette.textPrimary,
                textAlign = TextAlign.Center,
            ),
            keyboardOptions = KeyboardOptions(keyboardType = androidx.compose.ui.text.input.KeyboardType.Number),
            singleLine = true,
            shape = RoundedCornerShape(18.dp),
            colors = TextFieldDefaults.colors(
                focusedContainerColor = Palette.surfaceRaised.copy(alpha = 0.75f),
                unfocusedContainerColor = Palette.surfaceRaised.copy(alpha = 0.75f),
                focusedIndicatorColor = Palette.volt.copy(alpha = 0.6f),
                unfocusedIndicatorColor = Palette.hairline,
                cursorColor = Palette.volt,
            ),
            modifier = Modifier.fillMaxWidth(),
        )
    }
}

/** Text field styled like the fleet panels, used for credentials and notes. */
@Composable
fun PanelTextField(
    value: String,
    onValueChange: (String) -> Unit,
    placeholder: String,
    modifier: Modifier = Modifier,
    icon: ImageVector? = null,
    isPassword: Boolean = false,
    singleLine: Boolean = true,
    minHeight: Dp = 56.dp,
    keyboardOptions: KeyboardOptions = KeyboardOptions.Default,
) {
    OutlinedTextField(
        value = value,
        onValueChange = onValueChange,
        placeholder = { Text(placeholder, color = Palette.textMuted.copy(alpha = 0.7f)) },
        leadingIcon = icon?.let { { Icon(it, null, tint = Palette.textMuted) } },
        visualTransformation = if (isPassword) {
            androidx.compose.ui.text.input.PasswordVisualTransformation()
        } else {
            androidx.compose.ui.text.input.VisualTransformation.None
        },
        singleLine = singleLine,
        keyboardOptions = keyboardOptions,
        shape = RoundedCornerShape(18.dp),
        textStyle = TextStyle(fontSize = 16.sp, color = Palette.textPrimary),
        colors = TextFieldDefaults.colors(
            focusedContainerColor = Palette.surfaceRaised.copy(alpha = 0.75f),
            unfocusedContainerColor = Palette.surfaceRaised.copy(alpha = 0.75f),
            focusedIndicatorColor = Palette.volt.copy(alpha = 0.6f),
            unfocusedIndicatorColor = Palette.hairline,
            cursorColor = Palette.volt,
        ),
        modifier = modifier
            .fillMaxWidth()
            .defaultMinSize(minHeight = minHeight),
    )
}

/** Pill chip used for filters, presets and quick selections. */
@Composable
fun Chip(
    label: String,
    selected: Boolean,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    accent: Color = Palette.volt,
) {
    Box(
        modifier
            .clip(CircleShape)
            .background(if (selected) accent.copy(alpha = 0.18f) else Palette.surfaceRaised)
            .border(
                BorderStroke(1.dp, if (selected) accent.copy(alpha = 0.7f) else Palette.hairline),
                CircleShape,
            )
            .clickable(
                interactionSource = remember { MutableInteractionSource() },
                indication = null,
            ) { onClick() }
            .padding(horizontal = 14.dp, vertical = 9.dp),
    ) {
        Text(
            label,
            style = TextStyle(
                fontSize = 13.sp,
                fontWeight = FontWeight.SemiBold,
                color = if (selected) accent else Palette.textMuted,
            ),
        )
    }
}

@Composable
fun SectionTitle(text: String, modifier: Modifier = Modifier, trailing: String? = null) {
    Row(
        modifier.fillMaxWidth(),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(
            text,
            style = TextStyle(fontSize = 17.sp, fontWeight = FontWeight.Black, color = Palette.textPrimary),
        )
        Spacer(Modifier.weight(1f))
        if (trailing != null) {
            Text(trailing, style = TextStyle(fontSize = 12.sp, color = Palette.textMuted))
        }
    }
}

@Composable
fun DetailRow(
    label: String,
    value: String,
    modifier: Modifier = Modifier,
    tone: Color = Palette.textPrimary,
    showDivider: Boolean = true,
) {
    Column(modifier.fillMaxWidth()) {
        Row(
            Modifier
                .fillMaxWidth()
                .padding(horizontal = 16.dp, vertical = 11.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            CapsLabel(label)
            Spacer(Modifier.weight(1f))
            Text(
                value,
                style = TextStyle(fontSize = 14.sp, fontWeight = FontWeight.Bold, color = tone),
                textAlign = TextAlign.End,
                maxLines = 2,
            )
        }
        if (showDivider) {
            Box(
                Modifier
                    .fillMaxWidth()
                    .height(1.dp)
                    .background(Palette.hairline),
            )
        }
    }
}
