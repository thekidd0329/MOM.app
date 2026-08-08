import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { Pool } from "jsr:@db/postgres@^0";
import { createClient } from "npm:@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const SUPABASE_DB_URL = Deno.env.get("SUPABASE_DB_URL")!;
const HF_ENV_TOKEN = Deno.env.get("HF_TOKEN") ?? Deno.env.get("HUGGINGFACE_API_KEY") ?? "";
const HF_API_BASE = (Deno.env.get("HF_API_BASE") ?? "https://router.huggingface.co/v1").replace(/\/$/, "");
const DEFAULT_MODEL = (Deno.env.get("MOM_MODEL") ?? "").trim();
const pool = new Pool(SUPABASE_DB_URL, 1);
const db = createClient(SUPABASE_URL, SERVICE_ROLE_KEY, {
  auth: { persistSession: false, autoRefreshToken: false },
});
let cachedHfToken = "";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "content-type, x-mom-installation, x-mom-token",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function json(status: number, value: unknown) {
  return new Response(JSON.stringify(value), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json; charset=utf-8" },
  });
}

function safeText(value: unknown, max: number, fallback = "") {
  if (typeof value !== "string") return fallback;
  return value.trim().slice(0, max);
}

function isUuid(value: string) {
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(value);
}

async function sha256(value: string) {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value));
  return Array.from(new Uint8Array(digest), (b) => b.toString(16).padStart(2, "0")).join("");
}

async function authenticate(req: Request) {
  const installationId = req.headers.get("x-mom-installation") ?? "";
  const token = req.headers.get("x-mom-token") ?? "";
  if (!isUuid(installationId) || token.length < 32 || token.length > 256) return null;
  const { data, error } = await db
    .from("mom_installations")
    .select("id,device_id,user_id,token_hash,revoked_at")
    .eq("id", installationId)
    .maybeSingle();
  if (error || !data || data.revoked_at) return null;
  if (await sha256(token) !== data.token_hash) return null;
  return data;
}

async function getHfToken() {
  if (HF_ENV_TOKEN) return HF_ENV_TOKEN;
  if (cachedHfToken) return cachedHfToken;
  const connection = await pool.connect();
  try {
    const result = await connection.queryObject<{ decrypted_secret: string }>(
      "select decrypted_secret from vault.decrypted_secrets where name = 'mom_hf_token' limit 1",
    );
    const token = result.rows[0]?.decrypted_secret?.trim() ?? "";
    if (token) cachedHfToken = token;
    return token;
  } catch (error) {
    console.error("mom-agent vault lookup failed", error instanceof Error ? error.message : String(error));
    return "";
  } finally {
    connection.release();
  }
}

async function hf(path: string, init: RequestInit = {}) {
  const token = await getHfToken();
  if (!token) return { ok: false, status: 503, body: { error: "hf_secret_missing" } };
  const response = await fetch(`${HF_API_BASE}${path}`, {
    ...init,
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${token}`,
      ...(init.headers ?? {}),
    },
  });
  const text = await response.text();
  let body: unknown = text;
  try { body = text ? JSON.parse(text) : {}; } catch {}
  return { ok: response.ok, status: response.status, body };
}

async function resolveModel(requested: string) {
  if (requested) return requested;
  if (DEFAULT_MODEL) return DEFAULT_MODEL;
  const result = await hf("/models", { method: "GET" });
  if (!result.ok) throw new Error(`model_discovery_http_${result.status}`);
  const data = result.body as any;
  const models = Array.isArray(data?.data) ? data.data : [];
  const first = models.find((item: any) => typeof item?.id === "string" && item.id.trim());
  if (!first) throw new Error("no_models_available");
  return first.id.trim();
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json(405, { error: "method_not_allowed" });

  let body: any;
  try { body = await req.json(); } catch { return json(400, { error: "invalid_json" }); }
  const action = safeText(body?.action, 32);

  if (action === "health") {
    return json(200, {
      ok: true,
      service: "mom-agent",
      version: 1,
      configured: Boolean(await getHfToken()),
      personality_context: false,
      memory_context: false,
    });
  }

  const installation = await authenticate(req);
  if (!installation) return json(401, { error: "invalid_installation_token" });

  try {
    if (action !== "run") return json(400, { error: "unknown_action" });

    const systemPrompt = safeText(body.system_prompt, 60000);
    const userText = safeText(body.user_text, 60000);
    if (!systemPrompt || !userText) return json(400, { error: "agent_prompt_required" });

    const temperatureRaw = Number(body.temperature ?? 0);
    const temperature = Number.isFinite(temperatureRaw) ? Math.max(0, Math.min(2, temperatureRaw)) : 0;
    const model = await resolveModel(safeText(body.model, 300));
    const result = await hf("/chat/completions", {
      method: "POST",
      body: JSON.stringify({
        model,
        messages: [
          { role: "system", content: systemPrompt },
          { role: "user", content: userText },
        ],
        temperature,
        stream: false,
      }),
    });

    if (!result.ok) {
      return json(502, {
        error: "provider_error",
        provider_status: result.status,
        detail: result.body,
      });
    }
    const data = result.body as any;
    const content = data?.choices?.[0]?.message?.content;
    if (typeof content !== "string" || !content.trim()) {
      return json(502, { error: "unexpected_provider_response" });
    }

    return json(200, {
      text: content.trim(),
      model,
      context_layers: ["agent_system", "current_user_input"],
    });
  } catch (error) {
    const detail = error instanceof Error ? error.message : String(error);
    console.error("mom-agent", action, detail);
    return json(500, { error: "server_error", detail });
  }
});
