package com.rork.turnoevandroid.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.border
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
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Bolt
import androidx.compose.material.icons.filled.Handyman
import androidx.compose.material.icons.filled.Logout
import androidx.compose.material.icons.filled.PhonelinkErase
import androidx.compose.material.icons.filled.VerifiedUser
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.rork.turnoevandroid.FleetViewModel
import com.rork.turnoevandroid.data.FleetState
import com.rork.turnoevandroid.domain.StaffAccount
import com.rork.turnoevandroid.domain.StaffDirectory
import com.rork.turnoevandroid.ui.components.BigButton
import com.rork.turnoevandroid.ui.components.ButtonTone
import com.rork.turnoevandroid.ui.components.DemoClockButton
import com.rork.turnoevandroid.ui.components.DetailRow
import com.rork.turnoevandroid.ui.components.NoticeBanner
import com.rork.turnoevandroid.ui.components.RoleBadge
import com.rork.turnoevandroid.ui.components.Tone
import com.rork.turnoevandroid.ui.components.accent
import com.rork.turnoevandroid.ui.theme.CapsLabel
import com.rork.turnoevandroid.ui.theme.Palette
import com.rork.turnoevandroid.ui.theme.panel

/**
 * Interface reserved for a role whose modules are not published yet. It renders only the
 * scope the credential is entitled to, never driver data.
 */
@Composable
fun RoleWorkspaceScreen(
    viewModel: FleetViewModel,
    state: FleetState,
    now: Long,
    account: StaffAccount,
) {
    val role = account.role
    val station = StaffDirectory.station(account.stationId)
    val creator = StaffDirectory.account(account.createdById)
    val authorizer = StaffDirectory.account(account.authorizedById)

    Column(
        Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(horizontal = 18.dp)
            .padding(top = 12.dp, bottom = 40.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        Row(
            Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(12.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Box(
                Modifier
                    .size(46.dp)
                    .background(role.accent.copy(alpha = 0.14f), RoundedCornerShape(15.dp)),
                contentAlignment = Alignment.Center,
            ) {
                Icon(Icons.Filled.Bolt, null, Modifier.size(24.dp), tint = role.accent)
            }
            Column(verticalArrangement = Arrangement.spacedBy(3.dp)) {
                Text(
                    role.workspaceTitle,
                    style = TextStyle(fontSize = 19.sp, fontWeight = FontWeight.Black, color = Palette.textPrimary),
                )
                CapsLabel("Turno EV · red nacional")
            }
            Spacer(Modifier.weight(1f))
            DemoClockButton(viewModel, now, state.clockOffsetMinutes)
        }

        RoleBadge(role)

        Column(
            Modifier
                .fillMaxWidth()
                .panel()
                .padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Row(
                horizontalArrangement = Arrangement.spacedBy(12.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Box(
                    Modifier
                        .size(52.dp)
                        .background(Palette.surfaceRaised, CircleShape)
                        .border(1.5.dp, role.accent.copy(alpha = 0.5f), CircleShape),
                    contentAlignment = Alignment.Center,
                ) {
                    Text(
                        account.initials,
                        style = TextStyle(fontSize = 16.sp, fontWeight = FontWeight.Black, color = role.accent),
                    )
                }
                Column(verticalArrangement = Arrangement.spacedBy(3.dp)) {
                    Text(
                        account.name,
                        style = TextStyle(fontSize = 16.sp, fontWeight = FontWeight.Bold, color = Palette.textPrimary),
                    )
                    Text(
                        "${account.employeeNumber} · ${account.status.label}",
                        style = TextStyle(fontSize = 12.sp, color = Palette.textMuted),
                    )
                }
            }

            Box(
                Modifier
                    .fillMaxWidth()
                    .height(1.dp)
                    .background(Palette.hairline),
            )

            DetailRow("Alcance", role.scopeLabel)
            DetailRow("Asignación", StaffDirectory.scopeDescription(account))
            account.slot?.let { slot ->
                DetailRow("Cobertura", "${slot.label} · ${slot.rangeLabel}")
            }
            station?.let {
                DetailRow("Código de estación", it.code)
                DetailRow("Capacidad", "${it.vehicleCapacity} unidades · 4 turnos")
            }
            state.session?.let { session ->
                DetailRow("Acceso", session.method.label, showDivider = false)
            }
        }

        Column(
            Modifier
                .fillMaxWidth()
                .panel()
                .padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            CapsLabel("Permisos de esta credencial")
            role.capabilities.forEach { capability ->
                Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    Icon(
                        Icons.Filled.VerifiedUser,
                        null,
                        Modifier
                            .padding(top = 2.dp)
                            .size(15.dp),
                        tint = role.accent,
                    )
                    Text(
                        capability,
                        style = TextStyle(fontSize = 14.sp, color = Palette.textPrimary),
                    )
                }
            }
        }

        Column(
            Modifier
                .fillMaxWidth()
                .panel()
                .padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            CapsLabel("Jerarquía de registros")
            Text(
                role.registrationNote,
                style = TextStyle(fontSize = 14.sp, color = Palette.textPrimary),
            )
            if (role.canRegister.isNotEmpty()) {
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    role.canRegister.forEach { target -> RoleBadge(target, compact = true) }
                }
            }
            creator?.let { DetailRow("Registrado por", "${it.name} · ${it.role.shortLabel}") }
            authorizer?.let {
                DetailRow("Autorizado por", "${it.name} · ${it.role.shortLabel}", showDivider = false)
            }
        }

        Column(
            Modifier
                .fillMaxWidth()
                .panel()
                .padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            NoticeBanner(
                icon = Icons.Filled.Handyman,
                title = "Interfaz en construcción",
                message = "Tu sesión ya está identificada y protegida. Los módulos de " +
                    "${role.shortLabel.lowercase()} se publican en la siguiente entrega.",
                tone = Tone.INFO,
            )
            Text(
                "Ningún dato de otra interfaz se carga en esta sesión: la app solo resuelve las " +
                    "pantallas del rol autenticado.",
                style = TextStyle(fontSize = 12.sp, color = Palette.textMuted),
            )
        }

        BigButton(
            title = "Cerrar sesión",
            icon = Icons.Filled.Logout,
            tone = ButtonTone.OUTLINE,
        ) { viewModel.signOut() }

        BigButton(
            title = "Desvincular este dispositivo",
            icon = Icons.Filled.PhonelinkErase,
            tone = ButtonTone.OUTLINE,
        ) { viewModel.forgetDevice() }
    }
}
