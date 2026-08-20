/** Organizational model of the network: stations, regions, roles and the staff
 *  directory that authenticates every access. A station concentrates up to 100 units,
 *  4 driver shifts, 2 supervisors (morning / evening) and maintenance staff, and
 *  belongs to a region led by a regional manager. National direction sits on top. */

import type { ShiftSlot } from "./types";

export interface Station {
  id: string;
  /** Short code printed on the station board and on every unit sticker. */
  code: string;
  name: string;
  city: string;
  regionId: string;
  vehicleCapacity: number;
}

export interface Region {
  id: string;
  name: string;
  stationIds: string[];
}

export type StaffRole = "driver" | "supervisor" | "manager" | "maintenance" | "national";

export type StaffStatus = "active" | "suspended";

export interface StaffAccount {
  id: string;
  name: string;
  employeeNumber: string;
  email: string;
  password: string;
  role: StaffRole;
  /** Home station; null for regional and national scopes. */
  stationId: string | null;
  /** Region covered by managers; null for station-level staff. */
  regionId: string | null;
  /** Shift covered by supervisors and maintenance technicians. */
  slot: ShiftSlot | null;
  photoUrl: string | null;
  status: StaffStatus;
  /** Account that generated this record, following the network hierarchy. */
  createdById: string | null;
  /** Manager that authorized the hire; required for drivers. */
  authorizedById: string | null;
  /** Driver profile linked to this credential, only when role === "driver". */
  driverId: string | null;
}

export type SignInMethod = "biometric" | "credentials";

/** Active session. The role stored here is the only thing that opens an interface. */
export interface StaffSession {
  accountId: string;
  role: StaffRole;
  stationId: string | null;
  method: SignInMethod;
  startedAt: string;
}

export interface RoleDefinition {
  label: string;
  shortLabel: string;
  scopeLabel: string;
  workspaceTitle: string;
  /** Landing route of the role's interface. */
  home: string;
  accent: string;
  capabilities: string[];
  /** Roles this role is allowed to register. */
  canRegister: StaffRole[];
  registrationNote: string;
}

export const ROLE: Record<StaffRole, RoleDefinition> = {
  driver: {
    label: "Conductor",
    shortLabel: "Conductor",
    scopeLabel: "Una estación",
    workspaceTitle: "Panel de turno",
    home: "/turno",
    accent: "#C8FF3C",
    capabilities: [
      "Iniciar y cerrar su turno con evidencia fotográfica",
      "Registrar ingresos, viajes e incidencias",
      "Consultar metas, bonos y su crédito",
    ],
    canRegister: [],
    registrationNote: "Tu registro lo genera el supervisor de tu estación.",
  },
  supervisor: {
    label: "Supervisor de estación",
    shortLabel: "Supervisión",
    scopeLabel: "Una estación",
    workspaceTitle: "Control de estación",
    home: "/supervision",
    accent: "#4DE1FF",
    capabilities: [
      "Registrar conductores autorizados por gerencia",
      "Asignar unidades y validar inicios de turno",
      "Levantar reportes de limpieza, daños y puntualidad",
      "Autorizar pagos de atraso y recuperación de bonos",
    ],
    canRegister: ["driver"],
    registrationNote: "Registras conductores ya autorizados por tu gerente regional.",
  },
  manager: {
    label: "Gerente regional",
    shortLabel: "Gerencia",
    scopeLabel: "Región",
    workspaceTitle: "Tablero regional",
    home: "/gerencia",
    accent: "#FFB020",
    capabilities: [
      "Autorizar el alta de conductores de sus estaciones",
      "Comparar desempeño entre estaciones de la región",
      "Validar bonos, créditos y bajas de unidades",
    ],
    canRegister: [],
    registrationNote: "Autorizas a los conductores antes de que el supervisor los registre.",
  },
  maintenance: {
    label: "Mantenimiento",
    shortLabel: "Taller",
    scopeLabel: "Una estación",
    workspaceTitle: "Taller y flotilla",
    home: "/mantenimiento",
    accent: "#FF7A4B",
    capabilities: [
      "Recibir unidades reportadas y abrir órdenes de servicio",
      "Bloquear y liberar vehículos de la flotilla",
      "Programar servicios por kilometraje",
    ],
    canRegister: [],
    registrationNote: "No generas registros de personal.",
  },
  national: {
    label: "Dirección nacional",
    shortLabel: "Dirección",
    scopeLabel: "Red nacional",
    workspaceTitle: "Dirección nacional",
    home: "/direccion",
    accent: "#BAA3FF",
    capabilities: [
      "Dar de alta gerentes regionales y supervisores",
      "Abrir estaciones y definir su capacidad",
      "Ver la operación consolidada de todo el país",
    ],
    canRegister: ["manager", "supervisor", "maintenance"],
    registrationNote: "Tú generas los registros de gerentes regionales y supervisores.",
  },
};

export const REGIONS: Region[] = [
  { id: "reg-vm", name: "Valle de México", stationIds: ["est-nte-cdmx", "est-sur-cdmx"] },
  { id: "reg-occ", name: "Occidente", stationIds: ["est-gdl-chap"] },
];

export const STATIONS: Station[] = [
  {
    id: "est-nte-cdmx",
    code: "NTE-01",
    name: "Estación Norte",
    city: "CDMX",
    regionId: "reg-vm",
    vehicleCapacity: 100,
  },
  {
    id: "est-sur-cdmx",
    code: "SUR-02",
    name: "Estación Sur",
    city: "CDMX",
    regionId: "reg-vm",
    vehicleCapacity: 100,
  },
  {
    id: "est-gdl-chap",
    code: "GDL-01",
    name: "Estación Chapalita",
    city: "Guadalajara",
    regionId: "reg-occ",
    vehicleCapacity: 100,
  },
];

export const STAFF_ACCOUNTS: StaffAccount[] = [
  {
    id: "acc-dir-001",
    name: "Renata Salgado Aguirre",
    employeeNumber: "EV-DIR-001",
    email: "direccion.nacional@turnoev.mx",
    password: "Direccion14",
    role: "national",
    stationId: null,
    regionId: null,
    slot: null,
    photoUrl: null,
    status: "active",
    createdById: null,
    authorizedById: null,
    driverId: null,
  },
  {
    id: "acc-ger-045",
    name: "Mariana Ochoa Vela",
    employeeNumber: "EV-GER-045",
    email: "gerencia.valledemexico@turnoev.mx",
    password: "Gerencia14",
    role: "manager",
    stationId: null,
    regionId: "reg-vm",
    slot: null,
    photoUrl: null,
    status: "active",
    createdById: "acc-dir-001",
    authorizedById: null,
    driverId: null,
  },
  {
    id: "acc-sup-201",
    name: "Ana Lucía Torres",
    employeeNumber: "EV-SUP-201",
    email: "supervision.norte.am@turnoev.mx",
    password: "Supervisor14",
    role: "supervisor",
    stationId: "est-nte-cdmx",
    regionId: "reg-vm",
    slot: "morning",
    photoUrl: null,
    status: "active",
    createdById: "acc-dir-001",
    authorizedById: null,
    driverId: null,
  },
  {
    id: "acc-sup-202",
    name: "Iván Ramírez Cruz",
    employeeNumber: "EV-SUP-202",
    email: "supervision.norte.pm@turnoev.mx",
    password: "Supervisor14",
    role: "supervisor",
    stationId: "est-nte-cdmx",
    regionId: "reg-vm",
    slot: "evening",
    photoUrl: null,
    status: "active",
    createdById: "acc-dir-001",
    authorizedById: null,
    driverId: null,
  },
  {
    id: "acc-mto-118",
    name: "Luis Ángel Pech",
    employeeNumber: "EV-MTO-118",
    email: "mantenimiento.norte@turnoev.mx",
    password: "Taller14",
    role: "maintenance",
    stationId: "est-nte-cdmx",
    regionId: "reg-vm",
    slot: "morning",
    photoUrl: null,
    status: "active",
    createdById: "acc-dir-001",
    authorizedById: null,
    driverId: null,
  },
  {
    id: "acc-drv-1042",
    name: "Carlos Méndez Rivas",
    employeeNumber: "EV-1042",
    email: "launion.contacto2@gmail.com",
    password: "Kymyly14",
    role: "driver",
    stationId: "est-nte-cdmx",
    regionId: "reg-vm",
    slot: "morning",
    photoUrl: "/driver-portrait.jpg",
    status: "active",
    createdById: "acc-sup-201",
    authorizedById: "acc-ger-045",
    driverId: "drv-1042",
  },
];

export const stationById = (id: string | null | undefined): Station | null =>
  STATIONS.find((station) => station.id === id) ?? null;

export const regionById = (id: string | null | undefined): Region | null =>
  REGIONS.find((region) => region.id === id) ?? null;

export const accountById = (id: string | null | undefined): StaffAccount | null =>
  STAFF_ACCOUNTS.find((account) => account.id === id) ?? null;

export const stationDisplayName = (station: Station): string => `${station.name} · ${station.city}`;

export const stationsInRegion = (regionId: string | null): Station[] =>
  regionId ? STATIONS.filter((station) => station.regionId === regionId) : [];

export const accountInitials = (account: StaffAccount): string =>
  account.name
    .split(" ")
    .slice(0, 2)
    .map((part) => part.charAt(0))
    .join("")
    .toUpperCase();

/** Scope line shown in every workspace header. */
export const scopeDescription = (account: StaffAccount): string => {
  switch (account.role) {
    case "driver":
    case "supervisor":
    case "maintenance": {
      const station = stationById(account.stationId);
      return station ? stationDisplayName(station) : "Sin estación asignada";
    }
    case "manager": {
      const region = regionById(account.regionId);
      return `Región ${region?.name ?? "—"} · ${stationsInRegion(account.regionId).length} estaciones`;
    }
    case "national":
      return `${STATIONS.length} estaciones · ${REGIONS.length} regiones`;
  }
};

export type AuthOutcome =
  | { status: "granted"; account: StaffAccount }
  | { status: "unknown_identity"; message: string }
  | { status: "wrong_password"; message: string }
  | { status: "suspended"; message: string }
  | { status: "missing_assignment"; message: string };

/** Validates an identifier (email or employee number) plus password. */
export const authenticateStaff = (identifier: string, password: string): AuthOutcome => {
  const cleaned = identifier.trim();
  const byEmail = cleaned.toLowerCase();
  const byEmployee = cleaned.toUpperCase();
  const account = STAFF_ACCOUNTS.find(
    (item) => item.email === byEmail || item.employeeNumber === byEmployee,
  );

  if (!cleaned || !account) {
    return { status: "unknown_identity", message: "No encontramos esa cuenta en la red de estaciones." };
  }
  if (account.password !== password) {
    return { status: "wrong_password", message: "Contraseña incorrecta. Verifica e intenta de nuevo." };
  }
  if (account.status !== "active") {
    return { status: "suspended", message: "Cuenta suspendida. Contacta a tu gerente regional." };
  }

  const needsStation =
    account.role === "driver" || account.role === "supervisor" || account.role === "maintenance";
  if ((needsStation && !account.stationId) || (account.role === "manager" && !account.regionId)) {
    return {
      status: "missing_assignment",
      message: "Tu cuenta no tiene estación asignada. Contacta a dirección.",
    };
  }

  return { status: "granted", account };
};
