package com.rork.turnoevandroid.domain

import kotlinx.serialization.Serializable

/**
 * Organizational model of the network: stations, regions and the staff directory that
 * authenticates every access. A station concentrates up to 100 units, 4 driver shifts,
 * 2 supervisors (morning / evening) and maintenance staff, and belongs to a region led
 * by a regional manager. National direction sits above every region.
 */

@Serializable
data class Station(
    val id: String,
    /** Short code printed on the station board and on every unit sticker. */
    val code: String,
    val name: String,
    val city: String,
    val regionId: String,
    val vehicleCapacity: Int,
) {
    val displayName: String get() = "$name · $city"
}

@Serializable
data class Region(
    val id: String,
    val name: String,
    val stationIds: List<String>,
)

@Serializable
enum class StaffRole {
    DRIVER,
    SUPERVISOR,
    MANAGER,
    MAINTENANCE,
    NATIONAL;

    val label: String
        get() = when (this) {
            DRIVER -> "Conductor"
            SUPERVISOR -> "Supervisor de estación"
            MANAGER -> "Gerente regional"
            MAINTENANCE -> "Mantenimiento"
            NATIONAL -> "Dirección nacional"
        }

    val shortLabel: String
        get() = when (this) {
            DRIVER -> "Conductor"
            SUPERVISOR -> "Supervisión"
            MANAGER -> "Gerencia"
            MAINTENANCE -> "Taller"
            NATIONAL -> "Dirección"
        }

    val scopeLabel: String
        get() = when (this) {
            DRIVER, SUPERVISOR, MAINTENANCE -> "Una estación"
            MANAGER -> "Región"
            NATIONAL -> "Red nacional"
        }

    val workspaceTitle: String
        get() = when (this) {
            DRIVER -> "Panel de turno"
            SUPERVISOR -> "Control de estación"
            MANAGER -> "Tablero regional"
            MAINTENANCE -> "Taller y flotilla"
            NATIONAL -> "Dirección nacional"
        }

    /** Landing route of the role's interface. */
    val homeRoute: String
        get() = when (this) {
            DRIVER -> "turno"
            SUPERVISOR -> "supervision"
            MANAGER -> "gerencia"
            MAINTENANCE -> "mantenimiento"
            NATIONAL -> "direccion"
        }

    val capabilities: List<String>
        get() = when (this) {
            DRIVER -> listOf(
                "Iniciar y cerrar su turno con evidencia fotográfica",
                "Registrar ingresos, viajes e incidencias",
                "Consultar metas, bonos y su crédito",
            )

            SUPERVISOR -> listOf(
                "Registrar conductores autorizados por gerencia",
                "Asignar unidades y validar inicios de turno",
                "Levantar reportes de limpieza, daños y puntualidad",
                "Autorizar pagos de atraso y recuperación de bonos",
            )

            MANAGER -> listOf(
                "Autorizar el alta de conductores de sus estaciones",
                "Comparar desempeño entre estaciones de la región",
                "Validar bonos, créditos y bajas de unidades",
            )

            MAINTENANCE -> listOf(
                "Recibir unidades reportadas y abrir órdenes de servicio",
                "Bloquear y liberar vehículos de la flotilla",
                "Programar servicios por kilometraje",
            )

            NATIONAL -> listOf(
                "Dar de alta gerentes regionales y supervisores",
                "Abrir estaciones y definir su capacidad",
                "Ver la operación consolidada de todo el país",
            )
        }

    /**
     * Roles this role is allowed to register. Direction creates managers and supervisors;
     * supervisors create drivers previously authorized by their regional manager.
     */
    val canRegister: List<StaffRole>
        get() = when (this) {
            NATIONAL -> listOf(MANAGER, SUPERVISOR, MAINTENANCE)
            SUPERVISOR -> listOf(DRIVER)
            MANAGER, MAINTENANCE, DRIVER -> emptyList()
        }

    val registrationNote: String
        get() = when (this) {
            NATIONAL -> "Tú generas los registros de gerentes regionales y supervisores."
            MANAGER -> "Autorizas a los conductores antes de que el supervisor los registre."
            SUPERVISOR -> "Registras conductores ya autorizados por tu gerente regional."
            MAINTENANCE -> "No generas registros de personal."
            DRIVER -> "Tu registro lo genera el supervisor de tu estación."
        }
}

@Serializable
enum class StaffStatus {
    ACTIVE,
    SUSPENDED;

    val label: String
        get() = when (this) {
            ACTIVE -> "Activo"
            SUSPENDED -> "Suspendido"
        }
}

/** One credential holder of the network. The role decides which interface opens. */
@Serializable
data class StaffAccount(
    val id: String,
    val name: String,
    val employeeNumber: String,
    val email: String,
    val password: String,
    val role: StaffRole,
    /** Home station; `null` for regional and national scopes. */
    val stationId: String? = null,
    /** Region covered by managers; `null` for station-level staff. */
    val regionId: String? = null,
    /** Shift covered by supervisors and maintenance technicians. */
    val slot: ShiftSlot? = null,
    val photoAsset: String? = null,
    val status: StaffStatus = StaffStatus.ACTIVE,
    /** Account that generated this record, following the network hierarchy. */
    val createdById: String? = null,
    /** Manager that authorized the hire; required for drivers. */
    val authorizedById: String? = null,
    /** Driver profile linked to this credential, only for `DRIVER`. */
    val driverId: String? = null,
) {
    val initials: String
        get() = name.split(" ").take(2).mapNotNull { it.firstOrNull() }.joinToString("").uppercase()
}

@Serializable
enum class SignInMethod {
    BIOMETRIC,
    CREDENTIALS;

    val label: String
        get() = when (this) {
            BIOMETRIC -> "Rostro o huella"
            CREDENTIALS -> "Credenciales"
        }
}

/** Active session. The role stored here is the only thing that opens an interface. */
@Serializable
data class StaffSession(
    val accountId: String,
    val role: StaffRole,
    val stationId: String? = null,
    val method: SignInMethod,
    val startedAt: Long,
)

/** Result of validating credentials against the directory. */
sealed interface AuthOutcome {
    data class Granted(val account: StaffAccount) : AuthOutcome
    data class Denied(val message: String) : AuthOutcome
}

/** Credential directory. Replace with the real identity provider when the backend lands. */
object StaffDirectory {
    val regions: List<Region> = listOf(
        Region("reg-vm", "Valle de México", listOf("est-nte-cdmx", "est-sur-cdmx")),
        Region("reg-occ", "Occidente", listOf("est-gdl-chap")),
    )

    val stations: List<Station> = listOf(
        Station("est-nte-cdmx", "NTE-01", "Estación Norte", "CDMX", "reg-vm", 100),
        Station("est-sur-cdmx", "SUR-02", "Estación Sur", "CDMX", "reg-vm", 100),
        Station("est-gdl-chap", "GDL-01", "Estación Chapalita", "Guadalajara", "reg-occ", 100),
    )

    val accounts: List<StaffAccount> = listOf(
        StaffAccount(
            id = "acc-dir-001",
            name = "Renata Salgado Aguirre",
            employeeNumber = "EV-DIR-001",
            email = "direccion.nacional@turnoev.mx",
            password = "Direccion14",
            role = StaffRole.NATIONAL,
        ),
        StaffAccount(
            id = "acc-ger-045",
            name = "Mariana Ochoa Vela",
            employeeNumber = "EV-GER-045",
            email = "gerencia.valledemexico@turnoev.mx",
            password = "Gerencia14",
            role = StaffRole.MANAGER,
            regionId = "reg-vm",
            createdById = "acc-dir-001",
        ),
        StaffAccount(
            id = "acc-sup-201",
            name = "Ana Lucía Torres",
            employeeNumber = "EV-SUP-201",
            email = "supervision.norte.am@turnoev.mx",
            password = "Supervisor14",
            role = StaffRole.SUPERVISOR,
            stationId = "est-nte-cdmx",
            regionId = "reg-vm",
            slot = ShiftSlot.MORNING,
            createdById = "acc-dir-001",
        ),
        StaffAccount(
            id = "acc-sup-202",
            name = "Iván Ramírez Cruz",
            employeeNumber = "EV-SUP-202",
            email = "supervision.norte.pm@turnoev.mx",
            password = "Supervisor14",
            role = StaffRole.SUPERVISOR,
            stationId = "est-nte-cdmx",
            regionId = "reg-vm",
            slot = ShiftSlot.EVENING,
            createdById = "acc-dir-001",
        ),
        StaffAccount(
            id = "acc-mto-118",
            name = "Luis Ángel Pech",
            employeeNumber = "EV-MTO-118",
            email = "mantenimiento.norte@turnoev.mx",
            password = "Taller14",
            role = StaffRole.MAINTENANCE,
            stationId = "est-nte-cdmx",
            regionId = "reg-vm",
            slot = ShiftSlot.MORNING,
            createdById = "acc-dir-001",
        ),
        StaffAccount(
            id = "acc-drv-1042",
            name = "Carlos Méndez Rivas",
            employeeNumber = "EV-1042",
            email = "launion.contacto2@gmail.com",
            password = "Kymyly14",
            role = StaffRole.DRIVER,
            stationId = "est-nte-cdmx",
            regionId = "reg-vm",
            slot = ShiftSlot.MORNING,
            photoAsset = "driver_portrait",
            createdById = "acc-sup-201",
            authorizedById = "acc-ger-045",
            driverId = "drv-1042",
        ),
    )

    fun station(id: String?): Station? = stations.firstOrNull { it.id == id }

    fun region(id: String?): Region? = regions.firstOrNull { it.id == id }

    fun account(id: String?): StaffAccount? = accounts.firstOrNull { it.id == id }

    fun stationsInRegion(regionId: String?): List<Station> =
        if (regionId == null) emptyList() else stations.filter { it.regionId == regionId }

    /** Scope line shown in every workspace header. */
    fun scopeDescription(account: StaffAccount): String = when (account.role) {
        StaffRole.DRIVER, StaffRole.SUPERVISOR, StaffRole.MAINTENANCE ->
            station(account.stationId)?.displayName ?: "Sin estación asignada"

        StaffRole.MANAGER ->
            "Región ${region(account.regionId)?.name ?: "—"} · " +
                "${stationsInRegion(account.regionId).size} estaciones"

        StaffRole.NATIONAL -> "${stations.size} estaciones · ${regions.size} regiones"
    }

    /** Validates an identifier (email or employee number) plus password. */
    fun authenticate(identifier: String, password: String): AuthOutcome {
        val cleaned = identifier.trim()
        if (cleaned.isEmpty()) {
            return AuthOutcome.Denied("No encontramos esa cuenta en la red de estaciones.")
        }

        val account = accounts.firstOrNull {
            it.email == cleaned.lowercase() || it.employeeNumber == cleaned.uppercase()
        } ?: return AuthOutcome.Denied("No encontramos esa cuenta en la red de estaciones.")

        if (account.password != password) {
            return AuthOutcome.Denied("Contraseña incorrecta. Verifica e intenta de nuevo.")
        }
        if (account.status != StaffStatus.ACTIVE) {
            return AuthOutcome.Denied("Cuenta suspendida. Contacta a tu gerente regional.")
        }

        val needsStation = account.role == StaffRole.DRIVER ||
            account.role == StaffRole.SUPERVISOR ||
            account.role == StaffRole.MAINTENANCE
        if ((needsStation && account.stationId == null) ||
            (account.role == StaffRole.MANAGER && account.regionId == null)
        ) {
            return AuthOutcome.Denied("Tu cuenta no tiene estación asignada. Contacta a dirección.")
        }

        return AuthOutcome.Granted(account)
    }
}
