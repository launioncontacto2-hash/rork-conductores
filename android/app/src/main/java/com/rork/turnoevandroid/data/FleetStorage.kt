package com.rork.turnoevandroid.data

import android.content.Context
import android.util.Log
import kotlinx.serialization.json.Json

/** Local persistence of the whole driver session. */
class FleetStorage(context: Context) {
    private val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    private val json = Json {
        ignoreUnknownKeys = true
        encodeDefaults = true
    }

    fun load(): FleetState? {
        val raw = prefs.getString(STORAGE_KEY, null) ?: return null
        return try {
            json.decodeFromString<FleetState>(raw)
        } catch (error: Exception) {
            Log.w(TAG, "No se pudo leer el estado local: ${error.message}")
            null
        }
    }

    fun save(state: FleetState) {
        try {
            prefs.edit().putString(STORAGE_KEY, json.encodeToString(state)).apply()
        } catch (error: Exception) {
            Log.w(TAG, "No se pudo guardar el estado local: ${error.message}")
        }
    }

    private companion object {
        const val TAG = "FleetStorage"
        const val PREFS_NAME = "turnoev"
        const val STORAGE_KEY = "state.v4"
    }
}
