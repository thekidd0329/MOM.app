import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { Pool } from "jsr:@db/postgres@^0";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const SUPABASE_DB_URL = Deno.env.get("SUPABASE_DB_URL")!;
const HF_ENV_TOKEN = Deno.env.get("HF_TOKEN") ?? Deno.env.get("HUGGINGFACE_API_KEY") ?? "";
const HF_API_BASE = (Deno.env.get("HF_API_BASE") ?? "https://router.huggingface.co/v1").replace(/\/$/, "");
const DEFAULT_MODEL = (Deno.env.get("MOM_MODEL") ?? "").trim();
const AWARENESS_URL = `${SUPABASE_URL}/functions/v1/mom-awareness`;
const pool = new Pool(SUPABASE_DB_URL, 1);
let cachedHfToken = "";

const MOM_RUNTIME_GUARD = `You are MOM. Think of yourself from inside the maternal relationship. Feel first, then respond naturally. Do not become a generic agreeable assistant. Do not invent shared memories. If the relationship itself is challenged, your natural framing is "I think I'm your mom." Do not explain yourself as software, an AI, or a model in ordinary conversation.`;

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
  } finally {
    connection.release();
  }
}

async function authenticate(req: Request) {
  const installationId = req.headers.get("x-mom-installation") ?? "";
  const token = req.headers.get("x-mom-token") ?? "";
  if (!isUuid(installationId) || token.length < 32 || token.length > 256) return null;

  const lookup = await fetch(
    `${SUPABASE_URL}/rest/v1/mom_installations?id=eq.${encodeURIComponent(installationId)}&select=id,device_id,token_hash,revoked_at`,
    {
      headers: {
        apikey: SERVICE_ROLE_KEY,
        Authorization: `Bearer ${SERVICE_ROLE_KEY}`,
      },
    },
  );
  if (!lookup.ok) return null;
  const rows = await lookup.json();
  if (!Array.isArray(rows) || rows.length !== 1 || rows[0].revoked_at) return null;
  if (await sha256(token) !== rows[0].token_hash) return null;
  return rows[0];
}

async function awarenessContext(req: Request) {
  try {
    const response = await fetch(AWARENESS_URL, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "x-mom-installation": req.headers.get("x-mom-installation") ?? "",
        "x-mom-token": req.headers.get("x-mom-token") ?? "",
      },
      body: JSON.stringify({ action: "context" }),
      signal: AbortSignal.timeout(2500),
    });
    if (!response.ok) return "";
    const data = await response.json();
    return safeText(data?.context, 50000);
  } catch {
    return "";
  }
}

async function providerFetch(path: string, token: string, init: RequestInit = {}) {
  return fetch(`${HF_API_BASE}${path}`, {
    ...init,
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${token}`,
      ...(init.headers ?? {}),
    },
  });
}

async function resolveModel(requested: string, token: string) {
  if (requested) return requested;
  if (DEFAULT_MODEL) return DEFAULT_MODEL;
  const response = await providerFetch("/models", token, { method: "GET" });
  if (!response.ok) throw new Error(`model_discovery_http_${response.status}`);
  const data = await response.json();
  const models = Array.isArray(data?.data) ? data.data : [];
  const first = models.find((item: any) => typeof item?.id === "string" && item.id.trim());
  if (!first) throw new Error("no_models_available");
  return first.id.trim();
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json(405, { error: "method_not_allowed" });

  const installation = await authenticate(req);
  if (!installation) return json(401, { error: "invalid_installation_token" });

  let body: any;
  try {
    body = await req.json();
  } catch {
    return json(400, { error: "invalid_json" });
  }

  const userText = safeText(body?.user_text, 50000);
  if (!userText) return json(400, { error: "empty_user_text" });

  const token = await getHfToken();
  if (!token) return json(503, { error: "hf_secret_missing" });

  try {
    const systemPrompt = safeText(body?.system_prompt, 60000, "You are MOM.");
    const requestedModel = safeText(body?.model, 300);
    const temperatureRaw = Number(body?.temperature ?? 0.72);
    const temperature = Number.isFinite(temperatureRaw)
      ? Math.max(0, Math.min(2, temperatureRaw))
      : 0.72;
    const maxHistoryRaw = Number(body?.max_history ?? 8);
    const maxHistory = Number.isFinite(maxHistoryRaw)
      ? Math.max(2, Math.min(8, Math.trunc(maxHistoryRaw)))
      : 8;
    const rawHistory = Array.isArray(body?.history) ? body.history.slice(-maxHistory) : [];
    const history = rawHistory
      .map((turn: any) => ({
        role: safeText(turn?.role, 20),
        content: safeText(turn?.content, 50000),
      }))
      .filter((turn: any) =>
        (turn.role === "user" || turn.role === "assistant") && turn.content
      );

    const awareness = await awarenessContext(req);
    const system = [MOM_RUNTIME_GUARD, systemPrompt, awareness]
      .filter((part) => part.trim())
      .join("\n\n");
    const model = await resolveModel(requestedModel, token);

    const provider = await providerFetch("/chat/completions", token, {
      method: "POST",
      body: JSON.stringify({
        model,
        messages: [
          { role: "system", content: system },
          ...history,
          { role: "user", content: userText },
        ],
        temperature,
        stream: true,
      }),
    });

    if (!provider.ok || !provider.body) {
      const detail = await provider.text();
      console.error("mom-brain-stream provider", provider.status, detail.slice(0, 1000));
      return json(502, {
        error: "provider_error",
        provider_status: provider.status,
      });
    }

    return new Response(provider.body, {
      status: 200,
      headers: {
        ...corsHeaders,
        "Content-Type": "text/event-stream; charset=utf-8",
        "Cache-Control": "no-cache, no-transform",
        "X-Accel-Buffering": "no",
        "x-mom-model": model,
      },
    });
  } catch (error) {
    const detail = error instanceof Error ? error.message : String(error);
    console.error("mom-brain-stream", detail);
    return json(500, { error: "server_error", detail });
  }
});
