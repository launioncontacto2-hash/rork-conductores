import { createClient } from "@supabase/supabase-js";

type Notification = {
  id: string;
  environment_id: string;
  recipient_profile_id: string;
  title: string;
  subtitle: string | null;
  body: string;
  deep_link: Record<string, unknown>;
  collapse_id: string;
  push_attempts: number;
};

type Device = {
  id: string;
  device_token: string;
  bundle_id: string;
};

let cachedProviderToken: { value: string; issuedAt: number } | null = null;

function base64URL(value: Uint8Array | string): string {
  const bytes = typeof value === "string"
    ? new TextEncoder().encode(value)
    : value;
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replaceAll("+", "-").replaceAll("/", "_").replaceAll(
    "=",
    "",
  );
}

function pemToBytes(pem: string): ArrayBuffer {
  const body = pem.replace(/-----[^-]+-----/g, "").replace(/\s/g, "");
  const binary = atob(body);
  return Uint8Array.from(binary, (character) => character.charCodeAt(0))
    .buffer as ArrayBuffer;
}

async function providerToken(
  teamID: string,
  keyID: string,
  privateKeyPEM: string,
): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  if (cachedProviderToken && now - cachedProviderToken.issuedAt < 45 * 60) {
    return cachedProviderToken.value;
  }
  const header = base64URL(JSON.stringify({ alg: "ES256", kid: keyID }));
  const claims = base64URL(JSON.stringify({ iss: teamID, iat: now }));
  const input = `${header}.${claims}`;
  const key = await crypto.subtle.importKey(
    "pkcs8",
    pemToBytes(privateKeyPEM),
    { name: "ECDSA", namedCurve: "P-256" },
    false,
    ["sign"],
  );
  const signature = new Uint8Array(
    await crypto.subtle.sign(
      { name: "ECDSA", hash: "SHA-256" },
      key,
      new TextEncoder().encode(input),
    ),
  );
  const value = `${input}.${base64URL(signature)}`;
  cachedProviderToken = { value, issuedAt: now };
  return value;
}

function required(name: string): string {
  const value = Deno.env.get(name)?.trim();
  if (!value) throw new Error(`missing_${name.toLowerCase()}`);
  return value;
}

Deno.serve(async (request) => {
  if (request.method !== "POST") {
    return new Response("method_not_allowed", { status: 405 });
  }
  const dispatchSecret = required("PUSH_DISPATCH_SECRET");
  if (request.headers.get("x-push-dispatch-secret") !== dispatchSecret) {
    return new Response("unauthorized", { status: 401 });
  }

  try {
    const supabaseURL = required("SUPABASE_URL");
    const serviceRoleKey = required("SUPABASE_SERVICE_ROLE_KEY");
    const teamID = required("APNS_TEAM_ID");
    const keyID = required("APNS_KEY_ID");
    const privateKey = required("APNS_PRIVATE_KEY").replaceAll("\\n", "\n");
    const expectedBundleID = required("APNS_BUNDLE_ID");
    const token = await providerToken(teamID, keyID, privateKey);
    const admin = createClient(supabaseURL, serviceRoleKey, {
      auth: { persistSession: false, autoRefreshToken: false },
    });
    const { data: claimed, error: claimError } = await admin.rpc(
      "claim_acquisition_push_notifications",
      { p_limit: 25 },
    );
    if (claimError) throw claimError;

    let sent = 0;
    let failed = 0;
    let skipped = 0;
    for (const notification of (claimed ?? []) as Notification[]) {
      const { data: devices, error: deviceError } = await admin
        .from("acquisition_push_devices")
        .select("id, device_token, bundle_id")
        .eq("environment_id", notification.environment_id)
        .eq("profile_id", notification.recipient_profile_id)
        .eq("app_environment", "test")
        .eq("status", "active");
      if (deviceError) throw deviceError;
      const validDevices = ((devices ?? []) as Device[]).filter(
        (device) => device.bundle_id === expectedBundleID,
      );
      if (validDevices.length === 0) {
        await admin.from("acquisition_notifications").update({
          push_status: "skipped",
          last_push_error: "no_active_test_device",
        }).eq("id", notification.id);
        skipped += 1;
        continue;
      }

      const { count } = await admin.from("acquisition_notifications")
        .select("id", { count: "exact", head: true })
        .eq("environment_id", notification.environment_id)
        .eq("recipient_profile_id", notification.recipient_profile_id)
        .is("read_at", null);
      const alert: Record<string, string> = {
        title: notification.title,
        body: notification.body,
      };
      if (notification.subtitle) alert.subtitle = notification.subtitle;
      const payload = JSON.stringify({
        aps: {
          alert,
          sound: "default",
          badge: count ?? 0,
          "thread-id": notification.collapse_id,
        },
        dori: notification.deep_link,
        notification_id: notification.id,
      });

      let delivered = false;
      let lastReason = "apns_delivery_failed";
      for (const device of validDevices) {
        const response = await fetch(
          `https://api.push.apple.com/3/device/${device.device_token}`,
          {
            method: "POST",
            headers: {
              authorization: `bearer ${token}`,
              "apns-topic": expectedBundleID,
              "apns-push-type": "alert",
              "apns-priority": "10",
              "apns-collapse-id": notification.collapse_id.slice(0, 64),
            },
            body: payload,
          },
        );
        if (response.ok) {
          delivered = true;
          continue;
        }
        const failure = await response.json().catch(() => ({
          reason: `HTTP_${response.status}`,
        }));
        lastReason = String(failure.reason ?? `HTTP_${response.status}`);
        if (
          response.status === 410 ||
          ["BadDeviceToken", "DeviceTokenNotForTopic", "Unregistered"].includes(
            lastReason,
          )
        ) {
          await admin.from("acquisition_push_devices").update({
            status: "revoked",
            revoked_at: new Date().toISOString(),
          }).eq("id", device.id);
        }
      }
      if (delivered) {
        await admin.from("acquisition_notifications").update({
          push_status: "sent",
          pushed_at: new Date().toISOString(),
          last_push_error: null,
        }).eq("id", notification.id);
        sent += 1;
      } else {
        const terminal = notification.push_attempts >= 5;
        await admin.from("acquisition_notifications").update({
          push_status: terminal ? "failed" : "pending",
          last_push_error: lastReason.slice(0, 200),
        }).eq("id", notification.id);
        failed += 1;
      }
    }
    return Response.json({
      claimed: claimed?.length ?? 0,
      sent,
      failed,
      skipped,
    });
  } catch (error) {
    console.error(
      "dispatch-acquisition-push failed",
      error instanceof Error ? error.message : "unknown",
    );
    return Response.json({ error: "push_dispatch_failed" }, { status: 500 });
  }
});
