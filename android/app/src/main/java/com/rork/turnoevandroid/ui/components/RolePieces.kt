package com.rork.turnoevandroid.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AccountBalance
import androidx.compose.material.icons.filled.Build
import androidx.compose.material.icons.filled.DirectionsCar
import androidx.compose.material.icons.filled.InsertChart
import androidx.compose.material.icons.filled.SupervisorAccount
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.rork.turnoevandroid.domain.StaffRole
import com.rork.turnoevandroid.ui.theme.Palette

/** Accent that identifies each role across headers and badges. */
val StaffRole.accent: Color
    get() = when (this) {
        StaffRole.DRIVER -> Palette.volt
        StaffRole.SUPERVISOR -> Palette.info
        StaffRole.MANAGER -> Palette.amber
        StaffRole.MAINTENANCE -> Palette.ember
        StaffRole.NATIONAL -> Palette.royal
    }

val StaffRole.icon: ImageVector
    get() = when (this) {
        StaffRole.DRIVER -> Icons.Filled.DirectionsCar
        StaffRole.SUPERVISOR -> Icons.Filled.SupervisorAccount
        StaffRole.MANAGER -> Icons.Filled.InsertChart
        StaffRole.MAINTENANCE -> Icons.Filled.Build
        StaffRole.NATIONAL -> Icons.Filled.AccountBalance
    }

/** Badge with the identified role, reused by the login handoff and workspace headers. */
@Composable
fun RoleBadge(role: StaffRole, modifier: Modifier = Modifier, compact: Boolean = false) {
    val shape = RoundedCornerShape(50)
    Row(
        modifier
            .background(role.accent.copy(alpha = 0.14f), shape)
            .border(1.dp, role.accent.copy(alpha = 0.45f), shape)
            .padding(horizontal = if (compact) 9.dp else 12.dp, vertical = if (compact) 5.dp else 7.dp),
        horizontalArrangement = Arrangement.spacedBy(6.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Icon(role.icon, null, Modifier.size(if (compact) 13.dp else 15.dp), tint = role.accent)
        Text(
            role.label.uppercase(),
            style = TextStyle(
                fontSize = if (compact) 9.sp else 10.sp,
                fontWeight = FontWeight.Black,
                letterSpacing = 1.1.sp,
                color = role.accent,
            ),
        )
    }
}
