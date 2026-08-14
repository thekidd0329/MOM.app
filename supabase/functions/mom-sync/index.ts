import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2.112.3";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const db = createClient(SUPABASE_URL, SERVICE_ROLE_KEY, {
  auth: { persistSession: false, autoRefreshToken: false },
});

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "content-type, x-mom-installation, x-mom-token",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function response(status: number, value: unknown) {
  return new Response(JSON.stringify(value), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json; charset=utf-8" },
  });
}

function tokenHex(bytes = 32) {
  const buffer = new Uint8Array(bytes);
  crypto.getRandomValues(buffer);
  return Array.from(buffer, (b) => b.toString(16).padStart(2, "0")).join("");
}

async function sha256(value: string) {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value));
  return Array.from(new Uint8Array(digest), (b) => b.toString(16).padStart(2, "0")).join("");
}

function safeText(value: unknown, max: number, fallback = "") {
  if (typeof value !== "string") return fallback;
  return value.trim().slice(0, max);
}

function isUuid(value: string) {
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(value);
}

async function authenticate(req: Request) {
  const installationId = req.headers.get("x-mom-installation") ?? "";
  const token = req.headers.get("x-mom-token") ?? "";
  if (!isUuid(installationId) || token.length < 32 || token.length > 256) return null;

  const { data, error } = await db
    .from("mom_installations")
    .select("id,device_id,token_hash,revoked_at")
    .eq("id", installationId)
    .maybeSingle();
  if (error || !data || data.revoked_at) return null;
  if (await sha256(token) !== data.token_hash) return null;

  await db.from("mom_installations")
    .update({ last_seen_at: new Date().toISOString() })
    .eq("id", data.id);
  return data;
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return response(405, { error: "method_not_allowed" });

  let body: any;
  try {
    body = await req.json();
  } catch {
    return response(400, { error: "invalid_json" });
  }

  const action = safeText(body?.action, 64);

  if (action === "health") {
    return response(200, {
      ok: true,
      service: "mom-sync",
      version: 8,
      raw_memory_location: "device_only",
      raw_chat_storage: false,
      anonymous_research_endpoint: "mom-intelligence",
    });
  }

  if (action === "register") {
    const deviceId = safeText(body.device_id, 200);
    const platform = safeText(body.platform, 40, "unknown");
    const appVersion = safeText(body.app_version, 40, "dev");
    if (!/^[A-Za-z0-9._:-]{16,200}$/.test(deviceId)) {
      return response(400, { error: "invalid_device_id" });
    }

    const { data: existing } = await db
      .from("mom_installations")
      .select("id")
      .eq("device_id", deviceId)
      .maybeSingle();
    if (existing) return response(409, { error: "device_already_registered" });

    const token = tokenHex();
    const metadata = typeof body.metadata === "object" && body.metadata
      ? body.metadata
      : {};
    const { data, error } = await db.from("mom_installations").insert({
      device_id: deviceId,
      token_hash: await sha256(token),
      platform,
      app_version: appVersion,
      metadata,
    }).select("id").single();
    if (error) {
      return response(500, { error: "registration_failed", detail: error.message });
    }
    return response(201, { installation_id: data.id, token });
  }

  const installation = await authenticate(req);
  if (!installation) return response(401, { error: "invalid_installation_token" });

  if (action === "runtime_config") {
    const { data, error } = await db
      .from("mom_runtime_config")
      .select("config_value,min_app_version,updated_at")
      .eq("config_key", "mobile.runtime")
      .eq("enabled", true)
      .maybeSingle();
    if (error) {
      console.error("mom-sync runtime_config", error.message);
      return response(500, { error: "runtime_config_unavailable" });
    }
    if (!data) return response(404, { error: "runtime_config_not_found" });
    return response(200, {
      ok: true,
      config: data.config_value,
      min_app_version: data.min_app_version,
      updated_at: data.updated_at,
      server_time: new Date().toISOString(),
    });
  }

  // Privacy hard stop for old clients. Raw transcript and raw memory writes are
  // no longer accepted by the cloud, even if an outdated app attempts them.
  if (action === "sync_chat" || action === "memory" || action === "history") {
    return response(410, {
      error: "raw_cloud_memory_disabled",
      raw_memory_location: "device_only",
    });
  }

  if (action === "event") {
    const eventType = safeText(body.event_type, 80);
    if (!/^[a-z0-9_.:-]{1,80}$/i.test(eventType)) {
      return response(400, { error: "invalid_event_type" });
    }
    const payload = typeof body.payload === "object" && body.payload ? body.payload : {};
    if (JSON.stringify(payload).length > 32768) {
      return response(413, { error: "payload_too_large" });
    }

    // Runtime telemetry must remain content-free. Refuse fields that could be
    // used to sneak transcript or memory text through the event channel.
    const forbidden = ["content", "raw_text", "source_excerpt", "message", "prompt", "transcript"];
    if (forbidden.some((key) => Object.prototype.hasOwnProperty.call(payload, key))) {
      return response(400, { error: "event_content_forbidden" });
    }

    const sessionId = safeText(body.session_id, 64);
    let cloudSessionId: string | null = null;
    if (isUuid(sessionId)) {
      const { data: cloudSession, error: sessionLookupError } = await db
        .from("mom_chat_sessions")
        .select("id")
        .eq("id", sessionId)
        .eq("device_id", installation.device_id)
        .maybeSingle();
      if (sessionLookupError) {
        console.error("mom-sync session lookup", sessionLookupError.message);
      } else if (cloudSession) {
        cloudSessionId = cloudSession.id;
      }
    }

    const { error } = await db.from("mom_device_events").insert({
      installation_id: installation.id,
      session_id: cloudSessionId,
      event_type: eventType,
      payload,
    });
    if (error) {
      console.error("mom-sync event write", error.message);
      return response(500, { error: "event_write_failed" });
    }
    return response(200, { ok: true });
  }

  return response(400, { error: "unknown_action" });
});
