import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const INTELLIGENCE_URL = `${SUPABASE_URL}/functions/v1/mom-intelligence`;
const db = createClient(SUPABASE_URL, SERVICE_ROLE_KEY, {
  auth: { persistSession: false, autoRefreshToken: false },
});
const embeddingModel = new Supabase.ai.Session("gte-small");

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
    .select("id, device_id, token_hash, platform, app_version, revoked_at")
    .eq("id", installationId)
    .maybeSingle();
  if (error || !data || data.revoked_at) return null;
  if (await sha256(token) !== data.token_hash) return null;
  await db.from("mom_installations").update({ last_seen_at: new Date().toISOString() }).eq("id", data.id);
  return data;
}

async function ensureSession(installation: any, body: any) {
  const sessionId = safeText(body.session_id, 64);
  if (!isUuid(sessionId)) throw new Error("invalid_session_id");
  const { data: existing, error: findError } = await db
    .from("mom_chat_sessions")
    .select("id, device_id")
    .eq("id", sessionId)
    .maybeSingle();
  if (findError) throw findError;
  if (existing && existing.device_id !== installation.device_id) throw new Error("session_owner_mismatch");

  if (!existing) {
    const { error } = await db.from("mom_chat_sessions").insert({
      id: sessionId,
      device_id: installation.device_id,
      title: safeText(body.title, 160, "MOM"),
      model_provider: safeText(body.model_provider, 500) || null,
      model_name: safeText(body.model_name, 300) || null,
    });
    if (error) throw error;
  } else {
    const { error } = await db.from("mom_chat_sessions").update({
      model_provider: safeText(body.model_provider, 500) || null,
      model_name: safeText(body.model_name, 300) || null,
      updated_at: new Date().toISOString(),
    }).eq("id", sessionId);
    if (error) throw error;
  }
  return sessionId;
}

async function embedStoredMessage(id: number, role: string, content: string) {
  try {
    const input = `${role}: ${content.slice(0, 12000)}`;
    const embedding = await embeddingModel.run(input, { mean_pool: true, normalize: true });
    const { error } = await db.from("mom_chat_messages")
      .update({ embedding: JSON.stringify(embedding) }).eq("id", id);
    if (error) throw error;
    return true;
  } catch (error) {
    console.error("mom-sync embedding", id, error instanceof Error ? error.message : String(error));
    return false;
  }
}

async function extractIntelligence(
  req: Request,
  sessionId: string,
  content: string,
  localNow: string,
  utcOffsetMinutes: number,
) {
  try {
    const installation = req.headers.get("x-mom-installation") ?? "";
    const token = req.headers.get("x-mom-token") ?? "";
    const call = await fetch(INTELLIGENCE_URL, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "x-mom-installation": installation,
        "x-mom-token": token,
      },
      body: JSON.stringify({
        action: "process",
        session_id: sessionId,
        user_text: content,
        local_now: localNow || new Date().toISOString(),
        utc_offset_minutes: utcOffsetMinutes,
      }),
    });
    const raw = await call.text();
    let data: any = {};
    try { data = raw ? JSON.parse(raw) : {}; } catch {}
    if (!call.ok) {
      console.error("mom-sync intelligence", call.status, raw.slice(0, 1000));
      return { ok: false, error: data?.error ?? `http_${call.status}` };
    }
    return {
      ok: data?.ok === true,
      facts_produced: Number(data?.facts_produced ?? 0),
      temporal_items: Array.isArray(data?.temporal_items) ? data.temporal_items.length : 0,
      data_points: Number(data?.data_points ?? 0),
      data_points_per_1000_user_chars: Number(data?.data_points_per_1000_user_chars ?? 0),
    };
  } catch (error) {
    console.error("mom-sync intelligence", error instanceof Error ? error.message : String(error));
    return { ok: false, error: "intelligence_unavailable" };
  }
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return response(405, { error: "method_not_allowed" });

  let body: any;
  try { body = await req.json(); } catch { return response(400, { error: "invalid_json" }); }

  const action = safeText(body?.action, 64);
  if (action === "health") {
    return response(200, {
      ok: true,
      service: "mom-sync",
      version: 4,
      vector_memory: true,
      structured_context: true,
      temporal_agent: true,
      client_time_context: true,
    });
  }

  if (action === "register") {
    const deviceId = safeText(body.device_id, 200);
    const platform = safeText(body.platform, 40, "unknown");
    const appVersion = safeText(body.app_version, 40, "dev");
    if (!/^[A-Za-z0-9._:-]{16,200}$/.test(deviceId)) return response(400, { error: "invalid_device_id" });
    const { data: existing } = await db.from("mom_installations").select("id").eq("device_id", deviceId).maybeSingle();
    if (existing) return response(409, { error: "device_already_registered" });
    const token = tokenHex();
    const { data, error } = await db.from("mom_installations").insert({
      device_id: deviceId,
      token_hash: await sha256(token),
      platform,
      app_version: appVersion,
      metadata: typeof body.metadata === "object" && body.metadata ? body.metadata : {},
    }).select("id").single();
    if (error) return response(500, { error: "registration_failed", detail: error.message });
    return response(201, { installation_id: data.id, token });
  }

  const installation = await authenticate(req);
  if (!installation) return response(401, { error: "invalid_installation_token" });

  try {
    if (action === "sync_chat") {
      const role = safeText(body.role, 20);
      if (!new Set(["system", "user", "assistant", "tool"]).has(role)) return response(400, { error: "invalid_role" });
      const content = typeof body.content === "string" ? body.content.slice(0, 200000) : "";
      if (!content.trim()) return response(400, { error: "empty_content" });
      const sessionId = await ensureSession(installation, body);
      const { data: inserted, error } = await db.from("mom_chat_messages").insert({
        session_id: sessionId,
        device_id: installation.device_id,
        role,
        content,
        metadata: typeof body.metadata === "object" && body.metadata ? body.metadata : {},
      }).select("id").single();
      if (error) throw error;

      const embedded = (role === "user" || role === "assistant")
        ? await embedStoredMessage(inserted.id, role, content)
        : false;
      const offsetRaw = Number(body.utc_offset_minutes ?? 0);
      const utcOffsetMinutes = Number.isFinite(offsetRaw)
        ? Math.max(-840, Math.min(840, Math.trunc(offsetRaw)))
        : 0;
      const intelligence = role === "user"
        ? await extractIntelligence(
            req,
            sessionId,
            content,
            safeText(body.local_now, 80),
            utcOffsetMinutes,
          )
        : null;

      if (intelligence) {
        await db.from("mom_chat_messages").update({
          metadata: {
            ...(typeof body.metadata === "object" && body.metadata ? body.metadata : {}),
            intelligence,
          },
        }).eq("id", inserted.id);
      }
      return response(200, { ok: true, embedded, intelligence });
    }

    if (action === "event") {
      const eventType = safeText(body.event_type, 80);
      if (!/^[a-z0-9_.:-]{1,80}$/i.test(eventType)) return response(400, { error: "invalid_event_type" });
      const sessionId = safeText(body.session_id, 64);
      const payload = typeof body.payload === "object" && body.payload ? body.payload : {};
      if (JSON.stringify(payload).length > 32768) return response(413, { error: "payload_too_large" });
      const { error } = await db.from("mom_device_events").insert({
        installation_id: installation.id,
        session_id: isUuid(sessionId) ? sessionId : null,
        event_type: eventType,
        payload,
      });
      if (error) throw error;
      return response(200, { ok: true });
    }

    if (action === "memory") {
      const content = typeof body.content === "string" ? body.content.slice(0, 20000) : "";
      if (!content.trim()) return response(400, { error: "empty_content" });
      const sessionId = safeText(body.session_id, 64);
      const truthState = safeText(body.truth_state, 20, "candidate");
      if (!new Set(["observed", "candidate"]).has(truthState)) return response(400, { error: "invalid_truth_state" });
      const confidenceRaw = Number(body.confidence ?? 0.5);
      const confidence = Number.isFinite(confidenceRaw) ? Math.max(0, Math.min(1, confidenceRaw)) : 0.5;
      const { data: session } = isUuid(sessionId)
        ? await db.from("mom_chat_sessions").select("id, device_id").eq("id", sessionId).maybeSingle()
        : { data: null } as any;
      if (session && session.device_id !== installation.device_id) return response(403, { error: "session_owner_mismatch" });
      const { error } = await db.from("mom_memories").insert({
        owner_id: null,
        session_id: session?.id ?? null,
        kind: safeText(body.kind, 80, "observation"),
        subject: safeText(body.subject, 300) || null,
        content,
        truth_state: truthState,
        confidence,
        source: `native:${installation.device_id}`,
      });
      if (error) throw error;
      return response(200, { ok: true });
    }

    if (action === "history") {
      const limit = Math.max(1, Math.min(200, Number(body.limit ?? 100)));
      const { data: sessions, error: sessionError } = await db.from("mom_chat_sessions")
        .select("id,title,model_provider,model_name,created_at,updated_at")
        .eq("device_id", installation.device_id)
        .order("updated_at", { ascending: false })
        .limit(20);
      if (sessionError) throw sessionError;
      const ids = (sessions ?? []).map((s: any) => s.id);
      let messages: any[] = [];
      if (ids.length) {
        const { data, error } = await db.from("mom_chat_messages")
          .select("id,session_id,role,content,metadata,created_at")
          .in("session_id", ids)
          .order("created_at", { ascending: false })
          .limit(limit);
        if (error) throw error;
        messages = data ?? [];
      }
      return response(200, { sessions: sessions ?? [], messages });
    }

    return response(400, { error: "unknown_action" });
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    if (message === "session_owner_mismatch") return response(403, { error: message });
    if (message === "invalid_session_id") return response(400, { error: message });
    console.error("mom-sync", action, message);
    return response(500, { error: "server_error", detail: message });
  }
});
