package com.rork.turnoevandroid.ui.screens

import androidx.biometric.BiometricManager
import androidx.biometric.BiometricPrompt
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
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
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AlternateEmail
import androidx.compose.material.icons.filled.Badge
import androidx.compose.material.icons.filled.Bolt
import androidx.compose.material.icons.filled.Fingerprint
import androidx.compose.material.icons.filled.Groups
import androidx.compose.material.icons.filled.Send
import androidx.compose.material.icons.filled.VerifiedUser
import androidx.compose.material.icons.filled.VpnKey
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.scale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.content.ContextCompat
import androidx.fragment.app.FragmentActivity
import com.rork.turnoevandroid.FleetViewModel
import com.rork.turnoevandroid.data.FleetState
import com.rork.turnoevandroid.domain.AuthOutcome
import com.rork.turnoevandroid.domain.SignInMethod
import com.rork.turnoevandroid.domain.StaffAccount
import com.rork.turnoevandroid.domain.StaffDirectory
import com.rork.turnoevandroid.ui.components.BigButton
import com.rork.turnoevandroid.ui.components.ButtonTone
import com.rork.turnoevandroid.ui.components.Chip
import com.rork.turnoevandroid.ui.components.NoticeBanner
import com.rork.turnoevandroid.ui.components.PanelTextField
import com.rork.turnoevandroid.ui.components.RoleBadge
import com.rork.turnoevandroid.ui.components.Tone
import com.rork.turnoevandroid.ui.components.accent
import com.rork.turnoevandroid.ui.components.icon
import com.rork.turnoevandroid.ui.theme.CapsLabel
import com.rork.turnoevandroid.ui.theme.Palette
import com.rork.turnoevandroid.ui.theme.StationBackground
import com.rork.turnoevandroid.ui.theme.panelFlat
import kotlinx.coroutines.delay

private const val MAX_ATTEMPTS = 3

private enum class LoginMode { BIOMETRIC, CREDENTIALS }

private enum class CredentialMode(val label: String) { EMAIL("Correo"), EMPLOYEE("N° empleado") }

/**
 * Access to the network. Credentials are validated against the staff directory and the
 * resolved role is what opens an interface — a driver credential can never open the
 * supervisor, manager, maintenance or national workspace.
 *
 * The biometric sensor unlocks only the credential enrolled on this device: the first
 * access always requires identifier + password, so biometrics can never escalate a role.
 */
@Composable
fun LoginScreen(viewModel: FleetViewModel, state: FleetState) {
    val context = LocalContext.current
    val enrolled = StaffDirectory.account(state.enrolledAccountId)

    var mode by remember { mutableStateOf(if (enrolled == null) LoginMode.CREDENTIALS else LoginMode.BIOMETRIC) }
    var attempts by remember { mutableIntStateOf(0) }
    var isScanning by remember { mutableStateOf(false) }
    var lastFailed by remember { mutableStateOf(false) }
    var errorMessage by remember { mutableStateOf<String?>(null) }
    var credentialMode by remember { mutableStateOf(CredentialMode.EMAIL) }
    var identifier by remember { mutableStateOf("") }
    var password by remember { mutableStateOf("") }
    var isRecoveryOpen by remember { mutableStateOf(false) }
    var isDirectoryOpen by remember { mutableStateOf(false) }
    var handoff by remember { mutableStateOf<StaffAccount?>(null) }

    LaunchedEffect(enrolled?.id) {
        if (enrolled == null) mode = LoginMode.CREDENTIALS
    }

    /** Shows the identified role for a beat, then opens that role's interface only. */
    fun grantAccess(account: StaffAccount, method: SignInMethod) {
        handoff = account
        viewModel.scheduleSignIn(account, method, delayMillis = 1_100)
    }

    fun registerFailure(message: String) {
        isScanning = false
        attempts += 1
        lastFailed = true
        errorMessage = message
        if (attempts >= MAX_ATTEMPTS) {
            mode = LoginMode.CREDENTIALS
            errorMessage = null
        }
    }

    fun authenticate() {
        val target = enrolled
        if (target == null) {
            mode = LoginMode.CREDENTIALS
            return
        }
        val activity = context as? FragmentActivity
        if (activity == null) {
            registerFailure("El desbloqueo biométrico no está disponible")
            return
        }
        val status = BiometricManager.from(context)
            .canAuthenticate(
                BiometricManager.Authenticators.BIOMETRIC_WEAK or
                    BiometricManager.Authenticators.DEVICE_CREDENTIAL,
            )
        if (status != BiometricManager.BIOMETRIC_SUCCESS) {
            registerFailure(biometricUnavailableMessage(status))
            return
        }

        isScanning = true
        errorMessage = null
        val prompt = BiometricPrompt(
            activity,
            ContextCompat.getMainExecutor(context),
            object : BiometricPrompt.AuthenticationCallback() {
                override fun onAuthenticationSucceeded(result: BiometricPrompt.AuthenticationResult) {
                    isScanning = false
                    lastFailed = false
                    grantAccess(target, SignInMethod.BIOMETRIC)
                }

                override fun onAuthenticationError(errorCode: Int, errString: CharSequence) {
                    registerFailure("No se confirmó tu identidad")
                }

                override fun onAuthenticationFailed() {
                    registerFailure("Rostro o huella no reconocidos")
                }
            },
        )
        prompt.authenticate(
            BiometricPrompt.PromptInfo.Builder()
                .setTitle("Confirma tu identidad")
                .setSubtitle("Abriremos el panel de ${target.role.shortLabel.lowercase()}")
                .setAllowedAuthenticators(
                    BiometricManager.Authenticators.BIOMETRIC_WEAK or
                        BiometricManager.Authenticators.DEVICE_CREDENTIAL,
                )
                .build(),
        )
    }

    fun submitCredentials() {
        when (val outcome = StaffDirectory.authenticate(identifier, password)) {
            is AuthOutcome.Granted -> {
                errorMessage = null
                password = ""
                grantAccess(outcome.account, SignInMethod.CREDENTIALS)
            }

            is AuthOutcome.Denied -> errorMessage = outcome.message
        }
    }

    Box(Modifier.fillMaxSize()) {
        StationBackground()

        Column(
            Modifier
                .fillMaxSize()
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 24.dp, vertical = 40.dp),
            verticalArrangement = Arrangement.spacedBy(18.dp),
        ) {
            Row(
                horizontalArrangement = Arrangement.spacedBy(12.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Box(
                    Modifier
                        .size(48.dp)
                        .background(Palette.volt.copy(alpha = 0.15f), RoundedCornerShape(16.dp)),
                    contentAlignment = Alignment.Center,
                ) {
                    Icon(Icons.Filled.Bolt, null, Modifier.size(26.dp), tint = Palette.volt)
                }
                Column(verticalArrangement = Arrangement.spacedBy(3.dp)) {
                    Text(
                        "TURNO EV",
                        style = TextStyle(fontSize = 20.sp, fontWeight = FontWeight.Black, color = Palette.textPrimary),
                    )
                    CapsLabel("Acceso por rol y estación")
                }
            }

            Spacer(Modifier.size(8.dp))

            if (mode == LoginMode.BIOMETRIC && enrolled != null) {
                BiometricSection(
                    account = enrolled,
                    isScanning = isScanning,
                    lastFailed = lastFailed,
                    statusMessage = errorMessage
                        ?: if (lastFailed) {
                            "Intento $attempts de $MAX_ATTEMPTS. Después de 3 intentos pedimos tus credenciales."
                        } else {
                            "El biométrico abre únicamente la credencial vinculada a este dispositivo."
                        },
                    onAuthenticate = { authenticate() },
                    onFail = { registerFailure("Rostro no reconocido") },
                    onUseCredentials = {
                        mode = LoginMode.CREDENTIALS
                        attempts = 0
                        lastFailed = false
                        errorMessage = null
                    },
                )
            } else {
                Column(verticalArrangement = Arrangement.spacedBy(14.dp)) {
                    Text(
                        "Identifícate",
                        style = TextStyle(fontSize = 22.sp, fontWeight = FontWeight.Black, color = Palette.textPrimary),
                    )
                    Text(
                        "Detectamos tu rol y estación con tus credenciales, y abrimos solo tu interfaz.",
                        style = TextStyle(fontSize = 13.sp, color = Palette.textMuted),
                    )

                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        CredentialMode.entries.forEach { option ->
                            Chip(
                                label = option.label,
                                selected = credentialMode == option,
                                onClick = {
                                    credentialMode = option
                                    identifier = ""
                                },
                            )
                        }
                    }

                    PanelTextField(
                        value = identifier,
                        onValueChange = { identifier = it },
                        placeholder = if (credentialMode == CredentialMode.EMAIL) "correo@turnoev.mx" else "EV-1042",
                        icon = if (credentialMode == CredentialMode.EMAIL) {
                            Icons.Filled.AlternateEmail
                        } else {
                            Icons.Filled.Badge
                        },
                        keyboardOptions = KeyboardOptions(
                            keyboardType = if (credentialMode == CredentialMode.EMAIL) {
                                KeyboardType.Email
                            } else {
                                KeyboardType.Text
                            },
                        ),
                    )

                    PanelTextField(
                        value = password,
                        onValueChange = { password = it },
                        placeholder = "Contraseña",
                        icon = Icons.Filled.VpnKey,
                        isPassword = true,
                        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Password),
                    )

                    errorMessage?.let { message ->
                        Text(message, style = TextStyle(fontSize = 13.sp, color = Palette.danger))
                    }

                    BigButton("Identificar y entrar", icon = Icons.Filled.VerifiedUser) { submitCredentials() }

                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Row(
                            Modifier.clickable { isRecoveryOpen = true },
                            horizontalArrangement = Arrangement.spacedBy(6.dp),
                            verticalAlignment = Alignment.CenterVertically,
                        ) {
                            Icon(Icons.Filled.VpnKey, null, Modifier.size(16.dp), tint = Palette.volt)
                            Text(
                                "Recuperar contraseña",
                                style = TextStyle(
                                    fontSize = 14.sp,
                                    fontWeight = FontWeight.SemiBold,
                                    color = Palette.volt,
                                ),
                            )
                        }
                        Spacer(Modifier.weight(1f))
                        if (enrolled != null) {
                            Text(
                                "Volver a biométrico",
                                style = TextStyle(
                                    fontSize = 14.sp,
                                    fontWeight = FontWeight.SemiBold,
                                    color = Palette.textMuted,
                                ),
                                modifier = Modifier.clickable {
                                    mode = LoginMode.BIOMETRIC
                                    attempts = 0
                                    lastFailed = false
                                    errorMessage = null
                                },
                            )
                        }
                    }
                }
            }

            Spacer(Modifier.weight(1f))

            Row(
                Modifier
                    .fillMaxWidth()
                    .clickable { isDirectoryOpen = true },
                horizontalArrangement = Arrangement.Center,
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Icon(Icons.Filled.Groups, null, Modifier.size(16.dp), tint = Palette.textMuted)
                Spacer(Modifier.size(6.dp))
                Text(
                    "Cuentas de demostración",
                    style = TextStyle(fontSize = 13.sp, fontWeight = FontWeight.SemiBold, color = Palette.textMuted),
                )
            }

            Text(
                "${StaffDirectory.stations.size} estaciones · ${StaffDirectory.regions.size} regiones · " +
                    "v1.0 datos simulados",
                style = TextStyle(fontSize = 11.sp, color = Palette.textMuted),
                modifier = Modifier.fillMaxWidth(),
                textAlign = TextAlign.Center,
            )
        }

        handoff?.let { account -> RoleHandoffOverlay(account) }
    }

    if (isRecoveryOpen) {
        RecoverySheet(onDismiss = { isRecoveryOpen = false })
    }

    if (isDirectoryOpen) {
        DirectorySheet(
            onDismiss = { isDirectoryOpen = false },
            onPick = { account ->
                credentialMode = CredentialMode.EMAIL
                identifier = account.email
                password = account.password
                mode = LoginMode.CREDENTIALS
                errorMessage = null
                isDirectoryOpen = false
            },
        )
    }
}

@Composable
private fun BiometricSection(
    account: StaffAccount,
    isScanning: Boolean,
    lastFailed: Boolean,
    statusMessage: String,
    onAuthenticate: () -> Unit,
    onFail: () -> Unit,
    onUseCredentials: () -> Unit,
) {
    val accent = if (lastFailed) Palette.danger else account.role.accent
    val transition = rememberInfiniteTransition(label = "pulse")
    val pulse by transition.animateFloat(
        initialValue = 1f,
        targetValue = if (isScanning) 1.06f else 1.02f,
        animationSpec = infiniteRepeatable(tween(1_200), RepeatMode.Reverse),
        label = "scale",
    )

    Column(
        Modifier.fillMaxWidth(),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        Box(
            Modifier
                .size(160.dp)
                .scale(pulse)
                .clip(RoundedCornerShape(42.dp))
                .background(accent.copy(alpha = 0.06f))
                .border(2.dp, accent.copy(alpha = 0.45f), RoundedCornerShape(42.dp)),
            contentAlignment = Alignment.Center,
        ) {
            Icon(Icons.Filled.Fingerprint, null, Modifier.size(82.dp), tint = accent)
        }

        Spacer(Modifier.size(14.dp))

        Text(
            if (isScanning) "Verificando identidad…" else "Inicia con tu biométrico",
            style = TextStyle(fontSize = 22.sp, fontWeight = FontWeight.Black, color = Palette.textPrimary),
            textAlign = TextAlign.Center,
        )

        Text(
            account.name,
            style = TextStyle(fontSize = 14.sp, fontWeight = FontWeight.Bold, color = Palette.textPrimary),
        )
        RoleBadge(account.role, compact = true)
        Text(
            StaffDirectory.scopeDescription(account),
            style = TextStyle(fontSize = 12.sp, color = Palette.textMuted),
            textAlign = TextAlign.Center,
        )

        Text(
            statusMessage,
            style = TextStyle(fontSize = 13.sp, color = if (lastFailed) Palette.danger else Palette.textMuted),
            textAlign = TextAlign.Center,
            modifier = Modifier.padding(top = 6.dp),
        )

        Spacer(Modifier.size(12.dp))

        BigButton(
            title = if (isScanning) "Escaneando" else "Usar rostro o huella",
            icon = Icons.Filled.Fingerprint,
            enabled = !isScanning,
            onClick = onAuthenticate,
        )
        BigButton(
            title = "No reconoce mi rostro",
            tone = ButtonTone.OUTLINE,
            enabled = !isScanning,
            onClick = onFail,
        )
        Text(
            "Entrar con otra credencial",
            style = TextStyle(fontSize = 14.sp, fontWeight = FontWeight.SemiBold, color = Palette.textMuted),
            modifier = Modifier
                .clickable(enabled = !isScanning, onClick = onUseCredentials)
                .padding(10.dp),
        )
    }
}

/** Brief confirmation of the identified role before its interface is built. */
@Composable
private fun RoleHandoffOverlay(account: StaffAccount) {
    var appeared by remember { mutableStateOf(false) }
    LaunchedEffect(account.id) {
        delay(30)
        appeared = true
    }
    val scale by androidx.compose.animation.core.animateFloatAsState(
        targetValue = if (appeared) 1f else 0.94f,
        animationSpec = tween(320),
        label = "handoff",
    )

    Box(
        Modifier
            .fillMaxSize()
            .background(Palette.canvas.copy(alpha = 0.94f)),
        contentAlignment = Alignment.Center,
    ) {
        Column(
            Modifier
                .scale(scale)
                .padding(30.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            Box(
                Modifier
                    .size(104.dp)
                    .background(account.role.accent.copy(alpha = 0.12f), CircleShape)
                    .border(2.dp, account.role.accent.copy(alpha = 0.5f), CircleShape),
                contentAlignment = Alignment.Center,
            ) {
                Icon(account.role.icon, null, Modifier.size(46.dp), tint = account.role.accent)
            }
            CapsLabel("Rol identificado")
            Text(
                account.role.label,
                style = TextStyle(fontSize = 22.sp, fontWeight = FontWeight.Black, color = account.role.accent),
                textAlign = TextAlign.Center,
            )
            Text(
                account.name,
                style = TextStyle(fontSize = 14.sp, fontWeight = FontWeight.SemiBold, color = Palette.textPrimary),
            )
            Text(
                StaffDirectory.scopeDescription(account),
                style = TextStyle(fontSize = 12.sp, color = Palette.textMuted),
                textAlign = TextAlign.Center,
            )
            Text(
                "Abriendo ${account.role.workspaceTitle.lowercase()}…",
                style = TextStyle(fontSize = 13.sp, color = Palette.textMuted),
                modifier = Modifier.padding(top = 6.dp),
            )
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun DirectorySheet(onDismiss: () -> Unit, onPick: (StaffAccount) -> Unit) {
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)

    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = sheetState,
        containerColor = Palette.surface,
    ) {
        Column(
            Modifier
                .fillMaxWidth()
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 20.dp)
                .padding(bottom = 32.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Text(
                "Cuentas de demostración",
                style = TextStyle(fontSize = 18.sp, fontWeight = FontWeight.Black, color = Palette.textPrimary),
            )
            Text(
                "Toca una cuenta para llenar sus datos y revisar la interfaz que abre cada rol.",
                style = TextStyle(fontSize = 13.sp, color = Palette.textMuted),
            )
            StaffDirectory.accounts.forEach { account ->
                Column(
                    Modifier
                        .fillMaxWidth()
                        .clickable { onPick(account) }
                        .panelFlat()
                        .padding(14.dp),
                    verticalArrangement = Arrangement.spacedBy(6.dp),
                ) {
                    Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                        RoleBadge(account.role, compact = true)
                        Spacer(Modifier.weight(1f))
                        Text(
                            account.employeeNumber,
                            style = TextStyle(
                                fontSize = 12.sp,
                                fontWeight = FontWeight.SemiBold,
                                color = Palette.textMuted,
                            ),
                        )
                    }
                    Text(
                        account.name,
                        style = TextStyle(fontSize = 14.sp, fontWeight = FontWeight.Bold, color = Palette.textPrimary),
                    )
                    Text(
                        StaffDirectory.scopeDescription(account),
                        style = TextStyle(fontSize = 12.sp, color = Palette.textMuted),
                    )
                    Text(
                        "${account.email} · ${account.password}",
                        style = TextStyle(fontSize = 11.sp, color = Palette.textMuted),
                    )
                }
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun RecoverySheet(onDismiss: () -> Unit) {
    val sheetState = rememberModalBottomSheetState()
    var target by remember { mutableStateOf("") }
    var sent by remember { mutableStateOf(false) }

    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = sheetState,
        containerColor = Palette.surface,
    ) {
        Column(
            Modifier
                .fillMaxWidth()
                .padding(horizontal = 20.dp)
                .padding(bottom = 32.dp),
            verticalArrangement = Arrangement.spacedBy(14.dp),
        ) {
            Text(
                "Recuperar contraseña",
                style = TextStyle(fontSize = 18.sp, fontWeight = FontWeight.Black, color = Palette.textPrimary),
            )
            Text(
                "Los conductores restablecen con el supervisor de su estación. Supervisores, gerencia y " +
                    "mantenimiento lo hacen con dirección nacional.",
                style = TextStyle(fontSize = 13.sp, color = Palette.textMuted),
            )
            PanelTextField(
                value = target,
                onValueChange = { target = it },
                placeholder = "Correo o número de empleado",
            )
            if (sent) {
                NoticeBanner(
                    icon = Icons.Filled.VerifiedUser,
                    title = "Solicitud enviada",
                    message = "Quien generó tu registro validará el restablecimiento.",
                    tone = Tone.VOLT,
                )
            }
            BigButton(
                title = "Enviar solicitud",
                icon = Icons.Filled.Send,
                enabled = target.trim().length > 3,
            ) {
                sent = true
                target = ""
            }
        }
    }
}

private fun biometricUnavailableMessage(status: Int): String = when (status) {
    BiometricManager.BIOMETRIC_ERROR_NONE_ENROLLED ->
        "No hay rostro ni huella registrados en este dispositivo"

    BiometricManager.BIOMETRIC_ERROR_NO_HARDWARE ->
        "Este dispositivo no tiene sensor biométrico"

    BiometricManager.BIOMETRIC_ERROR_HW_UNAVAILABLE ->
        "El sensor biométrico está ocupado, intenta de nuevo"

    else -> "El acceso biométrico no está disponible"
}
