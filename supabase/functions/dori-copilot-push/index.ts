import { createClient } from "npm:@supabase/supabase-js@2.115.0";
type Notification = { id: string; environment_id: string; profile_id: string; offer_id: string; body: string; payload: Record<string, unknown>; status: string };
type Device = { id: string; device_token: string; bundle_id: string; updated_at: string };
let cached: { token: string; at: number } | null = null;
const b64 = (v: Uint8Array | string) => { const bytes = typeof v === "string" ? new TextEncoder().encode(v) : v; let s = ""; for (const b of bytes) s += String.fromCharCode(b); return btoa(s).replaceAll("+", "-").replaceAll("/", "_").replaceAll("=", ""); };
const pemBytes = (pem: string) => Uint8Array.from(atob(pem.replace(/-----[^-]+-----/g, "").replace(/\s/g, "")), c => c.charCodeAt(0));
async function providerToken(team: string, key: string, pem: string) { const now = Math.floor(Date.now()/1000); if (cached && now-cached.at < 2700) return cached.token; const input = `${b64(JSON.stringify({alg:"ES256",kid:key}))}.${b64(JSON.stringify({iss:team,iat:now}))}`; const cryptoKey = await crypto.subtle.importKey("pkcs8", pemBytes(pem), {name:"ECDSA",namedCurve:"P-256"}, false, ["sign"]); const sig = new Uint8Array(await crypto.subtle.sign({name:"ECDSA",hash:"SHA-256"}, cryptoKey, new TextEncoder().encode(input))); const token = `${input}.${b64(sig)}`; cached = { token, at: now }; return token; }
const required = (name: string) => { const v = Deno.env.get(name)?.trim(); if (!v) throw new Error(`missing_${name}`); return v; };
Deno.serve(async (request) => {
  if (request.method !== "POST") return Response.json({error:"method_not_allowed"},{status:405});
  if (request.headers.get("x-push-dispatch-secret") !== required("PUSH_DISPATCH_SECRET")) return Response.json({error:"unauthorized"},{status:401});
  try {
    const url = required("SUPABASE_URL"), service = required("SUPABASE_SERVICE_ROLE_KEY"), bundle = required("APNS_BUNDLE_ID");
    const admin = createClient(url, service, {auth:{persistSession:false,autoRefreshToken:false}});
    const {data: claimed,error} = await admin.rpc("claim_dori_copilot_notifications",{p_limit:25}); if(error) throw error;
    const token = await providerToken(required("APNS_TEAM_ID"),required("APNS_KEY_ID"),required("APNS_PRIVATE_KEY").replaceAll("\\n","\n")); let sent=0, failed=0;
    for (const n of (claimed ?? []) as Notification[]) {
      const {data: devices,error: de} = await admin.from("dori_copilot_push_devices").select("id,device_token,bundle_id,updated_at").eq("environment_id",n.environment_id).eq("profile_id",n.profile_id).eq("status","active").gte("updated_at",new Date(Date.now()-10*60*1000).toISOString()); if(de) throw de;
      let delivered=false;
      for (const d of (devices ?? []) as Device[]) {
        if(d.bundle_id !== bundle) continue;
        let response: Response | undefined;
        for (let attempt=0; attempt<3; attempt++) {
          response = await fetch(
            `https://api.push.apple.com/3/device/${d.device_token}`,
            {
              method: "POST",
              headers: {
                authorization: `bearer ${token}`,
                "apns-topic": bundle,
                "apns-push-type": "alert",
                "apns-priority": "10",
                "apns-collapse-id": n.offer_id.slice(0, 64),
              },
              body: JSON.stringify({
                aps: { alert: { title: "DORI Copiloto", body: n.body }, sound: "default" },
                dori: { offerId: n.offer_id, deepLink: "turno://copiloto" },
              }),
            },
          );
          if(response.ok || (response.status<500 && response.status!==429)) break;
          await new Promise(resolve=>setTimeout(resolve,250*(attempt+1)));
        }
        if(response?.ok){delivered=true;break;}
        if(response?.status===400 || response?.status===404 || response?.status===410){ await admin.from("dori_copilot_push_devices").update({status:"revoked"}).eq("id",d.id); }
      }
      await admin.from("dori_copilot_notifications").update({status:delivered?"sent":"failed",sent_at:delivered?new Date().toISOString():null}).eq("id",n.id); if(delivered) sent++; else failed++;
    }
    return Response.json({claimed:claimed?.length ?? 0,sent,failed});
  } catch (error) { console.error("dori-copilot-push failed",error instanceof Error?error.message:"unknown"); return Response.json({error:"push_dispatch_failed"},{status:500}); }
});
