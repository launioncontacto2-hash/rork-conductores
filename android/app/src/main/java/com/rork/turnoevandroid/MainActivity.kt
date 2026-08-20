package com.rork.turnoevandroid

import android.os.Bundle
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.fragment.app.FragmentActivity
import com.rork.turnoevandroid.ui.navigation.AppNavigation
import com.rork.turnoevandroid.ui.theme.TurnoEVTheme

/** FragmentActivity so the biometric prompt used at sign-in can attach to it. */
class MainActivity : FragmentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        setContent {
            TurnoEVTheme {
                AppNavigation()
            }
        }
    }
}
