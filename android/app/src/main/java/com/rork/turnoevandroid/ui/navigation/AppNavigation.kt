package com.rork.turnoevandroid.ui.navigation

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.CreditCard
import androidx.compose.material.icons.filled.EmojiEvents
import androidx.compose.material.icons.filled.ListAlt
import androidx.compose.material.icons.filled.Speed
import androidx.compose.material.icons.filled.TrackChanges
import androidx.compose.material3.CenterAlignedTopAppBar
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.NavigationBarItemDefaults
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import androidx.navigation.NavDestination.Companion.hierarchy
import androidx.navigation.NavGraph.Companion.findStartDestination
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.currentBackStackEntryAsState
import androidx.navigation.compose.rememberNavController
import com.rork.turnoevandroid.FleetViewModel
import com.rork.turnoevandroid.domain.StaffDirectory
import com.rork.turnoevandroid.domain.StaffRole
import com.rork.turnoevandroid.ui.screens.AssignVehicleScreen
import com.rork.turnoevandroid.ui.screens.BonusesScreen
import com.rork.turnoevandroid.ui.screens.CreditHowItWorksScreen
import com.rork.turnoevandroid.ui.screens.CreditScreen
import com.rork.turnoevandroid.ui.screens.FinishShiftScreen
import com.rork.turnoevandroid.ui.screens.GoalsScreen
import com.rork.turnoevandroid.ui.screens.HistoryScreen
import com.rork.turnoevandroid.ui.screens.IncidentScreen
import com.rork.turnoevandroid.ui.screens.IncomeScreen
import com.rork.turnoevandroid.ui.screens.InspectionScreen
import com.rork.turnoevandroid.ui.screens.LoginScreen
import com.rork.turnoevandroid.ui.screens.NoticesScreen
import com.rork.turnoevandroid.ui.screens.RoleWorkspaceScreen
import com.rork.turnoevandroid.ui.screens.ShiftScreen
import com.rork.turnoevandroid.ui.theme.Palette
import com.rork.turnoevandroid.ui.theme.StationBackground

private object Routes {
    const val SHIFT = "turno"
    const val GOALS = "metas"
    const val BONUSES = "bonos"
    const val CREDIT = "creditos"
    const val HISTORY = "historial"
    const val ASSIGN = "asignacion"
    const val INSPECTION = "inspeccion"
    const val INCOME = "ingreso"
    const val INCIDENT = "incidencia"
    const val FINISH = "cierre"
    const val NOTICES = "avisos"
    const val CREDIT_HOW = "credito-explicacion"
}

private data class Tab(val route: String, val label: String, val icon: ImageVector)

private val tabs = listOf(
    Tab(Routes.SHIFT, "Turno", Icons.Filled.Speed),
    Tab(Routes.GOALS, "Metas", Icons.Filled.TrackChanges),
    Tab(Routes.BONUSES, "Bonos", Icons.Filled.EmojiEvents),
    Tab(Routes.CREDIT, "Créditos", Icons.Filled.CreditCard),
    Tab(Routes.HISTORY, "Historial", Icons.Filled.ListAlt),
)

/** Titles for the full-screen operational flows presented over the tabs. */
private val modalTitles = mapOf(
    Routes.ASSIGN to "Asignación de vehículo",
    Routes.INSPECTION to "Registro de inicio",
    Routes.INCOME to "Registro de ingreso",
    Routes.INCIDENT to "Reporte de incidencia",
    Routes.FINISH to "Finalización de turno",
    Routes.NOTICES to "Avisos de la estación",
    Routes.CREDIT_HOW to "Programa de crédito",
)

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun AppNavigation() {
    val viewModel: FleetViewModel = viewModel()
    val state by viewModel.state.collectAsStateWithLifecycle()
    val now by viewModel.now.collectAsStateWithLifecycle()
    val thumbnails by viewModel.photoThumbnails.collectAsStateWithLifecycle()
    val navController = rememberNavController()
    val backStackEntry by navController.currentBackStackEntryAsState()
    val currentRoute = backStackEntry?.destination?.route
    val isTabRoute = tabs.any { it.route == currentRoute }

    Box(Modifier.fillMaxSize()) {
        StationBackground()

        // The session role is the only gate that opens an interface: the driver tabs are
        // never built for a supervisor, manager, maintenance or national credential.
        val account = StaffDirectory.account(state.session?.accountId)

        if (account == null) {
            LoginScreen(viewModel, state)
            return@Box
        }

        if (account.role != StaffRole.DRIVER) {
            RoleWorkspaceScreen(viewModel, state, now, account)
            return@Box
        }

        Scaffold(
            containerColor = Color.Transparent,
            topBar = {
                val title = modalTitles[currentRoute]
                if (title != null) {
                    CenterAlignedTopAppBar(
                        title = {
                            Text(
                                title,
                                style = TextStyle(
                                    fontSize = 15.sp,
                                    fontWeight = FontWeight.Black,
                                    color = Palette.textPrimary,
                                ),
                            )
                        },
                        navigationIcon = {
                            IconButton(onClick = { navController.popBackStack() }) {
                                Icon(Icons.Filled.Close, "Cerrar", tint = Palette.textPrimary)
                            }
                        },
                        colors = TopAppBarDefaults.centerAlignedTopAppBarColors(
                            containerColor = Color.Transparent,
                        ),
                    )
                }
            },
            bottomBar = {
                AnimatedVisibility(
                    visible = isTabRoute,
                    enter = fadeIn(tween(200)),
                    exit = fadeOut(tween(150)),
                ) {
                    Column {
                        Box(
                            Modifier
                                .fillMaxWidth()
                                .height(1.dp)
                                .background(Palette.hairline),
                        )
                        NavigationBar(containerColor = Palette.surface.copy(alpha = 0.96f)) {
                            tabs.forEach { tab ->
                                val selected = backStackEntry?.destination?.hierarchy
                                    ?.any { it.route == tab.route } == true
                                NavigationBarItem(
                                    selected = selected,
                                    onClick = {
                                        navController.navigate(tab.route) {
                                            popUpTo(navController.graph.findStartDestination().id) {
                                                saveState = true
                                            }
                                            launchSingleTop = true
                                            restoreState = true
                                        }
                                    },
                                    icon = { Icon(tab.icon, tab.label, Modifier.size(22.dp)) },
                                    label = {
                                        Text(
                                            tab.label,
                                            style = TextStyle(fontSize = 10.sp, fontWeight = FontWeight.SemiBold),
                                        )
                                    },
                                    colors = NavigationBarItemDefaults.colors(
                                        selectedIconColor = Palette.canvas,
                                        selectedTextColor = Palette.volt,
                                        indicatorColor = Palette.volt,
                                        unselectedIconColor = Palette.textMuted,
                                        unselectedTextColor = Palette.textMuted,
                                    ),
                                )
                            }
                        }
                    }
                }
            },
        ) { padding ->
            NavHost(
                navController = navController,
                startDestination = Routes.SHIFT,
                modifier = Modifier.padding(padding),
            ) {
                composable(Routes.SHIFT) {
                    ShiftScreen(
                        viewModel = viewModel,
                        state = state,
                        now = now,
                        onAssign = { navController.navigate(Routes.ASSIGN) },
                        onInspection = { navController.navigate(Routes.INSPECTION) },
                        onIncome = { navController.navigate(Routes.INCOME) },
                        onIncident = { navController.navigate(Routes.INCIDENT) },
                        onFinish = { navController.navigate(Routes.FINISH) },
                        onNotices = { navController.navigate(Routes.NOTICES) },
                    )
                }
                composable(Routes.GOALS) { GoalsScreen(viewModel, state, now) }
                composable(Routes.BONUSES) { BonusesScreen(viewModel, state, now) }
                composable(Routes.CREDIT) {
                    CreditScreen(viewModel, state, now) { navController.navigate(Routes.CREDIT_HOW) }
                }
                composable(Routes.HISTORY) { HistoryScreen(viewModel, state, now) }

                composable(Routes.ASSIGN) {
                    AssignVehicleScreen(viewModel, state) {
                        navController.popBackStack()
                        navController.navigate(Routes.INSPECTION)
                    }
                }
                composable(Routes.INSPECTION) {
                    InspectionScreen(viewModel, state, now, thumbnails) { navController.popBackStack() }
                }
                composable(Routes.INCOME) {
                    IncomeScreen(viewModel, state, now) { navController.popBackStack() }
                }
                composable(Routes.INCIDENT) {
                    IncidentScreen(viewModel, state) { navController.popBackStack() }
                }
                composable(Routes.FINISH) {
                    FinishShiftScreen(viewModel, state, now) { navController.popBackStack() }
                }
                composable(Routes.NOTICES) { NoticesScreen(viewModel, state, now) }
                composable(Routes.CREDIT_HOW) { CreditHowItWorksScreen() }
            }
        }
    }
}
