import { useQueryClient } from "@tanstack/react-query";
import { createContext, type ReactNode, useCallback, useContext, useEffect, useMemo, useState } from "react";

import { supabase, supabaseConfigurationError } from "@/lib/supabase";

export interface ConsoleIdentity {
  profile_id: string;
  environment_id: string;
  display_name: string;
  employee_number: string;
  membership_id: string;
  station_id: string;
  role: "supervisor";
  station_code: string;
  station_name: string;
  station_timezone: string;
}

interface ConsoleAuthValue {
  identity: ConsoleIdentity | null;
  isResolving: boolean;
  accessMessage: string | null;
  realtimeConnections: number;
  signInSupervisor: (email: string, password: string) => Promise<void>;
  signOut: () => Promise<void>;
  refreshIdentity: () => Promise<ConsoleIdentity | null>;
}

const ConsoleAuthContext = createContext<ConsoleAuthValue | null>(null);
const CONSOLE_QUERY_PREFIX = "console";

const sameIdentity = (left: ConsoleIdentity | null, right: ConsoleIdentity) =>
  Boolean(
    left &&
      left.membership_id === right.membership_id &&
      left.station_id === right.station_id &&
      left.display_name === right.display_name &&
      left.station_name === right.station_name &&
      left.station_timezone === right.station_timezone,
  );

const getInstallId = (): string => {
  const key = "turnoev.console.install-id";
  const existing = window.sessionStorage.getItem(key);
  if (existing) return existing;
  const created = crypto.randomUUID();
  window.sessionStorage.setItem(key, created);
  return created;
};

export const ConsoleAuthProvider = ({ children }: { children: ReactNode }) => {
  const queryClient = useQueryClient();
  const [identity, setIdentity] = useState<ConsoleIdentity | null>(null);
  const [isResolving, setIsResolving] = useState(false);
  const [accessMessage, setAccessMessage] = useState<string | null>(null);
  const [realtimeConnections, setRealtimeConnections] = useState(0);

  const clearConsole = useCallback(() => {
    setIdentity(null);
    setRealtimeConnections(0);
    queryClient.removeQueries({ queryKey: [CONSOLE_QUERY_PREFIX] });
  }, [queryClient]);

  const refreshIdentity = useCallback(async (): Promise<ConsoleIdentity | null> => {
    if (!supabase) return null;
    const { data, error } = await supabase.from("console_identity").select("*").maybeSingle();
    if (error) throw new Error(error.message);
    const next = (data as ConsoleIdentity | null) ?? null;
    if (next) setIdentity((current) => (sameIdentity(current, next) ? current : next));
    else clearConsole();
    return next;
  }, [clearConsole]);

  const signOut = useCallback(async () => {
    clearConsole();
    setAccessMessage(null);
    if (supabase) await supabase.auth.signOut();
  }, [clearConsole]);

  const revokeAccess = useCallback(
    async (message: string) => {
      setAccessMessage(message);
      clearConsole();
      if (supabase) await supabase.auth.signOut();
    },
    [clearConsole],
  );

  const signInSupervisor = useCallback(
    async (email: string, password: string) => {
      if (!supabase) throw new Error(supabaseConfigurationError ?? "Supabase no está disponible.");
      setIsResolving(true);
      setAccessMessage(null);
      try {
        const { error: authError } = await supabase.auth.signInWithPassword({ email, password });
        if (authError) throw new Error("Credencial TEST inválida o sesión no disponible.");

        const resolved = await refreshIdentity();
        if (!resolved) {
          await supabase.auth.signOut();
          throw new Error("La cuenta no tiene una membresía supervisora vigente para esta consola.");
        }

        const { error: heartbeatError } = await supabase.rpc("touch_device", {
          p_install_id: getInstallId(),
          p_active_membership_id: resolved.membership_id,
          p_platform: "web",
          p_app_version: "console-0.1",
        });
        if (heartbeatError) {
          await revokeAccess("La membresía dejó de estar vigente durante el acceso.");
          throw new Error("No fue posible registrar este navegador en la estación.");
        }
      } finally {
        setIsResolving(false);
      }
    },
    [refreshIdentity, revokeAccess],
  );

  useEffect(() => {
    if (!supabase || !identity) return;

    const statuses = new Map<string, boolean>();
    const updateCount = (name: string, status: string) => {
      statuses.set(name, status === "SUBSCRIBED");
      setRealtimeConnections([...statuses.values()].filter(Boolean).length);
    };

    const stationChannel = supabase
      .channel(`station:${identity.station_id}:ops`)
      .on(
        "postgres_changes",
        { event: "*", schema: "public", table: "station_live", filter: `station_id=eq.${identity.station_id}` },
        () => queryClient.invalidateQueries({ queryKey: [CONSOLE_QUERY_PREFIX] }),
      )
      .subscribe((status) => updateCount("station", status));

    const membershipChannel = supabase
      .channel(`me:${identity.profile_id}:membership`)
      .on(
        "postgres_changes",
        { event: "*", schema: "public", table: "staff_memberships", filter: `profile_id=eq.${identity.profile_id}` },
        () => {
          void refreshIdentity()
            .then((current) => {
              if (!current) void revokeAccess("Tu membresía fue cerrada. La consola retiró los datos de la estación.");
            })
            .catch(() => revokeAccess("No fue posible volver a validar tu membresía."));
        },
      )
      .subscribe((status) => updateCount("membership", status));

    const heartbeat = window.setInterval(() => {
      void supabase
        ?.rpc("touch_device", {
          p_install_id: getInstallId(),
          p_active_membership_id: identity.membership_id,
          p_platform: "web",
          p_app_version: "console-0.1",
        })
        .then(({ error }) => {
          if (error) void revokeAccess("Tu membresía ya no autoriza esta consola.");
        });
    }, 60_000);

    return () => {
      window.clearInterval(heartbeat);
      void supabase?.removeChannel(stationChannel);
      void supabase?.removeChannel(membershipChannel);
    };
  }, [identity, queryClient, refreshIdentity, revokeAccess]);

  const value = useMemo(
    () => ({
      identity,
      isResolving,
      accessMessage,
      realtimeConnections,
      signInSupervisor,
      signOut,
      refreshIdentity,
    }),
    [accessMessage, identity, isResolving, realtimeConnections, refreshIdentity, signInSupervisor, signOut],
  );

  return <ConsoleAuthContext.Provider value={value}>{children}</ConsoleAuthContext.Provider>;
};

export const useConsoleAuth = (): ConsoleAuthValue => {
  const value = useContext(ConsoleAuthContext);
  if (!value) throw new Error("useConsoleAuth debe usarse dentro de ConsoleAuthProvider");
  return value;
};
