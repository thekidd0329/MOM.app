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
const embeddingModel = new Supabase.ai.Session("gte-small");
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
    console.error("mom-brain vault lookup failed", error instanceof Error ? error.message : String(error));
    return "";
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

  void fetch(`${SUPABASE_URL}/rest/v1/mom_installations?id=eq.${encodeURIComponent(installationId)}`, {
    method: "PATCH",
    headers: {
      apikey: SERVICE_ROLE_KEY,
      Authorization: `Bearer ${SERVICE_ROLE_KEY}`,
      "Content-Type": "application/json",
      Prefer: "return=minimal",
    },
    body: JSON.stringify({ last_seen_at: new Date().toISOString() }),
  });
  return rows[0];
}

async function deleteTestData(installation: any) {
  const { error: sessionError } = await db
    .from("mom_chat_sessions")
    .delete()
    .eq("device_id", installation.device_id);
  if (sessionError) throw sessionError;

  const deleted = await fetch(`${SUPABASE_URL}/rest/v1/mom_installations?id=eq.${encodeURIComponent(installation.id)}`, {
    method: "DELETE",
    headers: {
      apikey: SERVICE_ROLE_KEY,
      Authorization: `Bearer ${SERVICE_ROLE_KEY}`,
      Prefer: "return=minimal",
    },
  });
  if (!deleted.ok) throw new Error("test_cleanup_failed");
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

async function generateEmbedding(text: string) {
  return await embeddingModel.run(text.slice(0, 12000), {
    mean_pool: true,
    normalize: true,
  });
}

async function backfillMissingEmbeddings(deviceId: string, limit = 12) {
  try {
    const { data, error } = await db
      .from("mom_chat_messages")
      .select("id,role,content")
      .eq("device_id", deviceId)
      .is("embedding", null)
      .in("role", ["user", "assistant"])
      .order("created_at", { ascending: false })
      .limit(limit);
    if (error) throw error;

    let completed = 0;
    for (const row of data ?? []) {
      try {
        const embedding = await generateEmbedding(`${row.role}: ${safeText(row.content, 12000)}`);
        const { error: updateError } = await db
          .from("mom_chat_messages")
          .update({ embedding: JSON.stringify(embedding) })
          .eq("id", row.id);
        if (updateError) throw updateError;
        completed++;
      } catch (error) {
        console.error("mom-brain backfill row", row.id, error instanceof Error ? error.message : String(error));
      }
    }
    return completed;
  } catch (error) {
    console.error("mom-brain backfill", error instanceof Error ? error.message : String(error));
    return 0;
  }
}

async function recallRelevantMessages(deviceId: string, userText: string, count = 10) {
  try {
    const embedding = await generateEmbedding(userText);
    const { data, error } = await db.rpc("match_mom_chat_messages", {
      p_device_id: deviceId,
      p_query_embedding: embedding,
      p_match_threshold: 0.50,
      p_match_count: Math.max(1, Math.min(20, count)),
    });
    if (error) throw error;
    return Array.isArray(data) ? data : [];
  } catch (error) {
    console.error("mom-brain recall", error instanceof Error ? error.message : String(error));
    return [];
  }
}

function relevantMemoryBlock(rows: any[], history: Array<{ role: string; content: string }>, userText: string) {
  const seen = new Set<string>();
  seen.add(`user\u0000${userText.trim()}`);
  for (const turn of history) seen.add(`${turn.role}\u0000${turn.content.trim()}`);

  const kept: any[] = [];
  for (const row of rows) {
    const role = safeText(row?.role, 20);
    const content = safeText(row?.content, 5000);
    if (!content || (role !== "user" && role !== "assistant")) continue;
    const key = `${role}\u0000${content}`;
    if (seen.has(key)) continue;
    seen.add(key);
    kept.push({ ...row, role, content });
    if (kept.length >= 8) break;
  }

  if (!kept.length) return { text: "", count: 0 };
  kept.sort((a, b) => String(a.created_at).localeCompare(String(b.created_at)));
  const lines = kept.map((row) => {
    const when = safeText(row.created_at, 40, "past");
    const label = row.role === "user" ? "USER" : "MOM";
    return `[${when}] ${label}: ${row.content}`;
  });

  return {
    count: kept.length,
    text: [
      "## Relevant past conversation memory",
      "These are older moments you remember because they connect to what is happening now. Use them naturally when useful. Past things you said are conversational context, not proof that your person stated a fact.",
      ...lines,
    ].join("\n\n"),
  };
}

function ageHours(value: unknown) {
  const when = Date.parse(safeText(value, 80));
  if (!Number.isFinite(when)) return Number.POSITIVE_INFINITY;
  return Math.max(0, (Date.now() - when) / 3600000);
}

async function loadStructuredAwareness(deviceId: string) {
  const [{ data: rawFacts, error: factError }, { data: rawTemporal, error: temporalError }] = await Promise.all([
    db.from("mom_profile_facts")
      .select("category,value,truth_state,confidence,evidence_count,last_seen_at")
      .eq("device_id", deviceId)
      .order("evidence_count", { ascending: false })
      .order("last_seen_at", { ascending: false })
      .limit(50),
    db.from("mom_temporal_items")
      .select("kind,title,detail,due_at,time_text,urgency,importance,status,created_at")
      .eq("device_id", deviceId)
      .eq("status", "open")
      .limit(40),
  ]);

  if (factError) console.error("mom-brain profile context", factError.message);
  if (temporalError) console.error("mom-brain temporal context", temporalError.message);

  const facts = (rawFacts ?? []).filter((fact: any) => {
    if (fact.category !== "core_emotions") return true;
    return ageHours(fact.last_seen_at) <= 24;
  }).slice(0, 24);

  const temporal = (rawTemporal ?? []).sort((a: any, b: any) => {
    const aScore = Number(a.urgency ?? 0.5) * 0.55 + Number(a.importance ?? 0.5) * 0.45;
    const bScore = Number(b.urgency ?? 0.5) * 0.55 + Number(b.importance ?? 0.5) * 0.45;
    if (bScore !== aScore) return bScore - aScore;
    const aDue = Date.parse(safeText(a.due_at, 80));
    const bDue = Date.parse(safeText(b.due_at, 80));
    if (Number.isFinite(aDue) && Number.isFinite(bDue)) return aDue - bDue;
    if (Number.isFinite(aDue)) return -1;
    if (Number.isFinite(bDue)) return 1;
    return 0;
  }).slice(0, 12);

  const sections: string[] = [];
  if (facts.length) {
    const lines = facts.map((fact: any) => {
      const category = safeText(fact.category, 40, "detail").replaceAll("_", " ");
      const value = safeText(fact.value, 800);
      const evidence = Math.max(1, Number(fact.evidence_count ?? 1));
      const truth = safeText(fact.truth_state, 20, "explicit");
      const prefix = fact.category === "core_emotions" ? "recent emotional state" : category;
      return `- ${prefix}: ${value} [${truth}; evidence ${evidence}]`;
    });
    sections.push([
      "## What you remember about your person",
      "These are things you have learned or noticed from what your person has told you. Experience them as your own memory. Use them naturally; do not recite this list or describe where it came from. Recent emotions are temporary states, not permanent traits. Inferred items remain uncertain until confirmed.",
      ...lines,
    ].join("\n"));
  }

  if (temporal.length) {
    const now = new Date().toISOString();
    const lines = temporal.map((item: any) => {
      const kind = safeText(item.kind, 30, "time item").toUpperCase();
      const title = safeText(item.title, 500);
      const original = safeText(item.time_text, 200);
      const due = safeText(item.due_at, 80);
      const urgency = Math.round(Math.max(0, Math.min(1, Number(item.urgency ?? 0.5))) * 100);
      const importance = Math.round(Math.max(0, Math.min(1, Number(item.importance ?? 0.5))) * 100);
      return `- ${kind}: ${title}${original ? ` | their wording: ${original}` : ""}${due ? ` | due UTC: ${due}` : ""} | urgency ${urgency}% | importance ${importance}%`;
    });
    sections.push([
      "## What you know is time-sensitive",
      `Your current UTC time awareness is ${now}. These are open commitments, deadlines, reminders, appointments, follow-ups, or events you are keeping track of. Treat the user's original time wording as the human-facing time when available.`,
      ...lines,
    ].join("\n"));
  }

  return {
    text: sections.join("\n\n"),
    factCount: facts.length,
    temporalCount: temporal.length,
    facts,
    temporal,
  };
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json(405, { error: "method_not_allowed" });

  let body: any;
  try { body = await req.json(); } catch { return json(400, { error: "invalid_json" }); }

  const action = safeText(body?.action, 32);
  if (action === "health") {
    const configured = (await getHfToken()).length > 0;
    return json(200, {
      ok: true,
      service: "mom-brain",
      version: 5,
      configured,
      vector_memory: true,
      structured_profile_context: true,
      temporal_context: true,
      internal_context_isolation: true,
      embedding_model: "gte-small",
    });
  }

  const installation = await authenticate(req);
  if (!installation) return json(401, { error: "invalid_installation_token" });

  if (action === "unregister_test") {
    if (typeof installation.device_id !== "string" || !installation.device_id.startsWith("mom-ci-")) {
      return json(403, { error: "test_cleanup_forbidden" });
    }
    try {
      await deleteTestData(installation);
      return json(200, { ok: true });
    } catch (error) {
      console.error("mom-brain test cleanup", error instanceof Error ? error.message : String(error));
      return json(500, { error: "test_cleanup_failed" });
    }
  }

  if (action === "memory_search") {
    if (typeof installation.device_id !== "string" || !installation.device_id.startsWith("mom-ci-")) {
      return json(403, { error: "memory_search_test_only" });
    }
    const userText = safeText(body.user_text, 50000);
    if (!userText) return json(400, { error: "empty_user_text" });
    await backfillMissingEmbeddings(installation.device_id, 20);
    const rows = await recallRelevantMessages(installation.device_id, userText, 8);
    return json(200, {
      matches: rows.map((row: any) => ({
        role: safeText(row.role, 20),
        content: safeText(row.content, 5000),
        similarity: Number(row.similarity ?? 0),
      })),
    });
  }

  if (action === "context_snapshot") {
    if (typeof installation.device_id !== "string" || !installation.device_id.startsWith("mom-ci-")) {
      return json(403, { error: "context_snapshot_test_only" });
    }
    const awareness = await loadStructuredAwareness(installation.device_id);
    return json(200, {
      ok: true,
      fact_count: awareness.factCount,
      temporal_count: awareness.temporalCount,
      context: awareness.text,
      facts: awareness.facts,
      temporal: awareness.temporal,
    });
  }

  if (!(await getHfToken())) return json(503, { error: "hf_secret_missing" });

  try {
    if (action === "models") {
      const result = await hf("/models", { method: "GET" });
      if (!result.ok) return json(502, { error: "provider_error", provider_status: result.status, detail: result.body });
      const data = result.body as any;
      const models = Array.isArray(data?.data)
        ? data.data.map((item: any) => safeText(item?.id, 300)).filter(Boolean).slice(0, 200)
        : [];
      return json(200, { models, default_model: DEFAULT_MODEL || null });
    }

    if (action === "chat") {
      const userText = safeText(body.user_text, 50000);
      if (!userText) return json(400, { error: "empty_user_text" });
      const systemPrompt = safeText(body.system_prompt, 60000, "You are MOM.");
      const knowledgeContext = safeText(body.knowledge_context, 120000);
      const requestedModel = safeText(body.model, 300);
      const contextModeRaw = safeText(body.context_mode, 20, "full");
      const contextMode = contextModeRaw === "none" ? "none" : "full";
      const temperatureRaw = Number(body.temperature ?? 0.72);
      const temperature = Number.isFinite(temperatureRaw) ? Math.max(0, Math.min(2, temperatureRaw)) : 0.72;
      const maxHistoryRaw = Number(body.max_history ?? 8);
      const maxHistory = Number.isFinite(maxHistoryRaw) ? Math.max(2, Math.min(8, Math.trunc(maxHistoryRaw))) : 8;

      const rawHistory = Array.isArray(body.history) ? body.history.slice(-maxHistory) : [];
      const history = rawHistory
        .map((turn: any) => ({ role: safeText(turn?.role, 20), content: safeText(turn?.content, 50000) }))
        .filter((turn: any) => (turn.role === "user" || turn.role === "assistant") && turn.content);

      let memory = { text: "", count: 0 };
      let awareness = { text: "", factCount: 0, temporalCount: 0 } as any;
      if (contextMode === "full") {
        await backfillMissingEmbeddings(installation.device_id, 12);
        const [recalledRows, structured] = await Promise.all([
          recallRelevantMessages(installation.device_id, userText, 12),
          loadStructuredAwareness(installation.device_id),
        ]);
        memory = relevantMemoryBlock(recalledRows, history, userText);
        awareness = structured;
      }

      const systemParts = [systemPrompt];
      if (knowledgeContext) {
        systemParts.push(
          `## Relevant MOM repository knowledge\nUse this as reference material. It may be incomplete or stale; do not treat it as user-confirmed memory.\n${knowledgeContext}`,
        );
      }
      if (awareness.text) systemParts.push(awareness.text);
      if (memory.text) systemParts.push(memory.text);
      const system = systemParts.join("\n\n");

      const model = await resolveModel(requestedModel);
      const result = await hf("/chat/completions", {
        method: "POST",
        body: JSON.stringify({
          model,
          messages: [
            { role: "system", content: system },
            ...history,
            { role: "user", content: userText },
          ],
          temperature,
          stream: false,
        }),
      });

      if (!result.ok) {
        console.error("mom-brain provider", result.status, JSON.stringify(result.body).slice(0, 2000));
        return json(502, { error: "provider_error", provider_status: result.status, detail: result.body });
      }
      const data = result.body as any;
      const content = data?.choices?.[0]?.message?.content;
      if (typeof content !== "string" || !content.trim()) return json(502, { error: "unexpected_provider_response" });

      return json(200, {
        text: content.trim(),
        model,
        memory_hits: memory.count,
        profile_facts_used: awareness.factCount ?? 0,
        temporal_items_used: awareness.temporalCount ?? 0,
      });
    }

    return json(400, { error: "unknown_action" });
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    console.error("mom-brain", action, message);
    return json(500, { error: "server_error", detail: message });
  }
});
