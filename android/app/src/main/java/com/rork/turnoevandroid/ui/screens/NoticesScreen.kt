package com.rork.turnoevandroid.ui.screens

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
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Build
import androidx.compose.material.icons.filled.CreditCard
import androidx.compose.material.icons.filled.DoneAll
import androidx.compose.material.icons.filled.NotificationsActive
import androidx.compose.material.icons.filled.Place
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.rork.turnoevandroid.FleetViewModel
import com.rork.turnoevandroid.data.FleetState
import com.rork.turnoevandroid.domain.Notice
import com.rork.turnoevandroid.domain.NoticeKind
import com.rork.turnoevandroid.ui.theme.CapsLabel
import com.rork.turnoevandroid.ui.theme.Palette
import com.rork.turnoevandroid.util.Fmt

/** Station communication: maintenance, credit payments, station notices and reminders. */
@Composable
fun NoticesScreen(viewModel: FleetViewModel, state: FleetState, now: Long) {
    Column(
        Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(horizontal = 16.dp)
            .padding(top = 12.dp, bottom = 28.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            Text(
                "Avisos",
                style = TextStyle(fontSize = 17.sp, fontWeight = FontWeight.Black, color = Palette.textPrimary),
            )
            Spacer(Modifier.weight(1f))
            if (state.unreadNoticeCount > 0) {
                Row(
                    Modifier
                        .clip(CircleShape)
                        .clickable { viewModel.markAllNoticesRead() }
                        .padding(horizontal = 8.dp, vertical = 4.dp),
                    horizontalArrangement = Arrangement.spacedBy(6.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Icon(Icons.Filled.DoneAll, null, Modifier.size(16.dp), tint = Palette.volt)
                    Text(
                        "Marcar leídos",
                        style = TextStyle(fontSize = 12.sp, fontWeight = FontWeight.SemiBold, color = Palette.volt),
                    )
                }
            }
        }

        state.notices.forEach { notice ->
            NoticeRow(notice, now) { viewModel.markNoticeRead(notice.id) }
        }
    }
}

@Composable
private fun NoticeRow(notice: Notice, now: Long, onClick: () -> Unit) {
    val tint = tone(notice.kind)
    val shape = RoundedCornerShape(20.dp)
    Row(
        Modifier
            .fillMaxWidth()
            .clip(shape)
            .background(
                if (notice.read) Palette.surfaceRaised.copy(alpha = 0.5f) else Palette.surface.copy(alpha = 0.9f),
            )
            .border(1.dp, if (notice.read) Palette.hairline else Palette.volt.copy(alpha = 0.3f), shape)
            .clickable { onClick() }
            .padding(14.dp),
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Box(
            Modifier
                .size(40.dp)
                .clip(RoundedCornerShape(14.dp))
                .background(tint.copy(alpha = 0.12f)),
            contentAlignment = Alignment.Center,
        ) {
            Icon(icon(notice.kind), null, Modifier.size(20.dp), tint = tint)
        }
        Column(verticalArrangement = Arrangement.spacedBy(5.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                CapsLabel(notice.kind.label)
                if (!notice.read) {
                    Spacer(Modifier.size(6.dp))
                    Box(
                        Modifier
                            .size(6.dp)
                            .background(Palette.danger, CircleShape),
                    )
                }
                Spacer(Modifier.weight(1f))
                Text(
                    Fmt.relative(notice.createdAt, now),
                    style = TextStyle(fontSize = 10.sp, color = Palette.textMuted),
                )
            }
            Text(
                notice.title,
                style = TextStyle(fontSize = 14.sp, fontWeight = FontWeight.Bold, color = Palette.textPrimary),
            )
            Text(
                notice.body,
                style = TextStyle(fontSize = 12.sp, color = Palette.textMuted),
            )
        }
    }
}

private fun icon(kind: NoticeKind): ImageVector = when (kind) {
    NoticeKind.MAINTENANCE -> Icons.Filled.Build
    NoticeKind.CREDIT -> Icons.Filled.CreditCard
    NoticeKind.STATION -> Icons.Filled.Place
    NoticeKind.REMINDER -> Icons.Filled.NotificationsActive
}

private fun tone(kind: NoticeKind): Color = when (kind) {
    NoticeKind.MAINTENANCE -> Palette.info
    NoticeKind.CREDIT -> Palette.amber
    NoticeKind.STATION -> Palette.volt
    NoticeKind.REMINDER -> Palette.textMuted
}
