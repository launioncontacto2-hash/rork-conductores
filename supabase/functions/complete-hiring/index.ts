import { createClient } from "npm:@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, apikey, content-type, x-client-info",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const json = (status: number, body: Record<string, unknown>) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });

const isUuid = (value: unknown): value is string =>
  typeof value === "string" &&
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(value);

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (request.method !== "POST") return json(405, { error: "method_not_allowed" });

  const authorization = request.headers.get("Authorization");
  if (!authorization?.startsWith("Bearer ")) {
    return json(401, { error: "authentication_required" });
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseUrl || !anonKey || !serviceRoleKey) {
    return json(500, { error: "function_configuration_missing" });
  }

  let payload: Record<string, unknown>;
  try {
    payload = await request.json();
  } catch {
    return json(400, { error: "invalid_json" });
  }

  const candidateId = payload.candidate_id;
  const employeeNumber = typeof payload.employee_number === "string"
    ? payload.employee_number.trim().toUpperCase()
    : "";
  const temporaryPassword = typeof payload.temporary_password === "string"
    ? payload.temporary_password
    : "";
  const idempotencyKey = typeof payload.idempotency_key === "string"
    ? payload.idempotency_key.trim()
    : "";

  if (
    !isUuid(candidateId) ||
    !/^[A-Z0-9][A-Z0-9-]{2,39}$/.test(employeeNumber) ||
    temporaryPassword.length < 8 ||
    temporaryPassword.length > 72 ||
    idempotencyKey.length < 8 ||
    idempotencyKey.length > 200
  ) {
    return json(422, { error: "invalid_hiring_request" });
  }

  const caller = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: authorization } },
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const admin = createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  const { error: callerError } = await caller.auth.getUser();
  if (callerError) return json(401, { error: "authentication_required" });

  const { data: candidate, error: candidateError } = await caller
    .from("candidates")
    .select("id,email,full_name,environment_id")
    .eq("id", candidateId)
    .single();
  if (candidateError || !candidate) return json(404, { error: "candidate_not_found" });

  const { data: environment, error: environmentError } = await admin
    .from("environments")
    .select("code")
    .eq("id", candidate.environment_id)
    .single();
  if (environmentError || environment?.code !== "test") {
    return json(403, { error: "test_environment_required" });
  }

  const { data: signed, error: signError } = await caller.rpc("sign_hiring", {
    p_candidate_id: candidateId,
    p_employee_number: employeeNumber,
    p_idempotency_key: idempotencyKey,
  });
  if (signError || !signed) {
    return json(409, { error: signError?.message ?? "hiring_signature_failed" });
  }
  if (signed.status === "completed") {
    return json(200, { hiring: signed, created: false });
  }

  let authUserId: string | null = null;
  let createdNow = false;
  const { data: created, error: createError } = await admin.auth.admin.createUser({
    email: candidate.email,
    password: temporaryPassword,
    email_confirm: true,
    user_metadata: {
      display_name: candidate.full_name,
      employee_number: employeeNumber,
      source: "turnoev_15h_test_hiring",
    },
  });

  if (!createError && created.user) {
    authUserId = created.user.id;
    createdNow = true;
  } else {
    // Covers the narrow crash window after Auth succeeded but before Postgres
    // completed the saga. The resolver never exposes arbitrary Auth users.
    const { data: resolved } = await admin.rpc("resolve_hiring_auth_user", {
      p_hiring_id: signed.id,
    });
    authUserId = typeof resolved === "string" ? resolved : null;
    if (!authUserId) {
      return json(409, { error: createError?.message ?? "auth_identity_creation_failed" });
    }
  }

  const { data: completed, error: completeError } = await admin.rpc("complete_hiring", {
    p_hiring_id: signed.id,
    p_auth_user_id: authUserId,
  });
  if (completeError || !completed) {
    if (createdNow && authUserId) {
      // Best-effort compensation. If deletion itself fails, the next request
      // resolves the existing identity and safely retries completion.
      await admin.auth.admin.deleteUser(authUserId);
    }
    return json(500, { error: "hiring_completion_pending_retry" });
  }

  return json(201, {
    hiring: completed,
    created: createdNow,
  });
});
