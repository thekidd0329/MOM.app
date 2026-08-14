import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const BRAIN_URL = `${SUPABASE_URL}/functions/v1/mom-brain`;
const db = createClient(SUPABASE_URL, SERVICE_ROLE_KEY, {
  auth: { persistSession: false, autoRefreshToken: false },
});

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

function safeText(value: unknown, max = 1000, fallback = "") {
  return typeof value === "string" ? value.trim().slice(0, max) : fallback;
}

function containsForbiddenField(value: unknown, forbidden: Set<string>) {
  const pending: unknown[] = [value];
  let visited = 0;
  while (pending.length > 0) {
    if (++visited > 10000) return true;
    const current = pending.pop();
    if (!current || typeof current !== "object") continue;
    if (Array.isArray(current)) {
      for (const nested of current) pending.push(nested);
      continue;
    }
    for (const [key, nested] of Object.entries(current as Record<string, unknown>)) {
      if (forbidden.has(key)) return true;
      pending.push(nested);
    }
  }
  return false;
}

function safeError(error: unknown) {
  if (error instanceof Error) return error.message;
  try { return JSON.stringify(error); } catch { return String(error); }
}

function isUuid(value: string) {
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(value);
}

async function sha256(value: string) {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value));
  return [...new Uint8Array(digest)].map((x) => x.toString(16).padStart(2, "0")).join("");
}

async function authenticate(req: Request) {
  const id = req.headers.get("x-mom-installation") ?? "";
  const token = req.headers.get("x-mom-token") ?? "";
  if (!isUuid(id) || token.length < 32 || token.length > 256) return null;
  const { data, error } = await db
    .from("mom_installations")
    .select("id,device_id,token_hash,revoked_at")
    .eq("id", id)
    .maybeSingle();
  if (error || !data || data.revoked_at || await sha256(token) !== data.token_hash) return null;
  return data;
}

function parseJsonObject(value: unknown) {
  if (typeof value !== "string") return value as Record<string, unknown>;
  let text = value.trim().replace(/^```(?:json)?\s*/i, "").replace(/\s*```$/i, "");
  const first = text.indexOf("{");
  const last = text.lastIndexOf("}");
  if (first >= 0 && last > first) text = text.slice(first, last + 1);
  const parsed = JSON.parse(text);
  if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) throw new Error("invalid_json_output");
  return parsed as Record<string, unknown>;
}

async function askBrain(req: Request, agentMode: "context_extractor" | "temporal", userPrompt: string) {
  const started = Date.now();
  const response = await fetch(BRAIN_URL, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "x-mom-installation": req.headers.get("x-mom-installation") ?? "",
      "x-mom-token": req.headers.get("x-mom-token") ?? "",
    },
    body: JSON.stringify({
      action: "agent",
      agent_mode: agentMode,
      user_text: userPrompt,
    }),
  });

  const rawBody = await response.text();
  let body: any = {};
  try { body = rawBody ? JSON.parse(rawBody) : {}; } catch {}
  if (!response.ok) throw new Error(`brain_${response.status}:${safeText(body?.error ?? rawBody, 300)}`);
  const raw = safeText(body?.text, 12000);
  if (!raw) throw new Error("empty_model_output");
  return {
    data: parseJsonObject(raw),
    raw,
    model: safeText(body?.model, 300, "mom-brain"),
    latencyMs: Date.now() - started,
  };
}

const obviousIdentifierPatterns = [
  /\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b/i,
  /https?:\/\/\S+|www\.\S+/i,
  /(?<!\w)@[A-Za-z0-9_]{2,32}\b/,
  /\b\d{3}-\d{2}-\d{4}\b/,
  /(?<!\d)(?:\+?1[ .-]?)?\(?[2-9]\d{2}\)?[ .-]?\d{3}[ .-]?\d{4}(?!\d)/,
  /\b(?:\d[ -]*?){13,19}\b/,
];

function containsObviousIdentifier(value: string) {
  return obviousIdentifierPatterns.some((pattern) => pattern.test(value));
}

function scrub(value: string) {
  return safeText(value, 800)
    .replace(/\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b/gi, "[EMAIL]")
    .replace(/https?:\/\/\S+|www\.\S+/gi, "[URL]")
    .replace(/(?<!\w)@[A-Za-z0-9_]{2,32}\b/g, "[HANDLE]")
    .replace(/\b\d{3}-\d{2}-\d{4}\b/g, "[SSN]")
    .replace(/(?<!\d)(?:\+?1[ .-]?)?\(?[2-9]\d{2}\)?[ .-]?\d{3}[ .-]?\d{4}(?!\d)/g, "[PHONE]")
    .replace(/\b(?:\d[ -]*?){13,19}\b/g, "[ACCOUNT_NUMBER]")
    .replace(
      /\b((?:my\s+)?(?:mom|mother|dad|father|parent|sister|brother|daughter|son|friend|girlfriend|boyfriend|wife|husband|partner|boss|manager|coworker|doctor|teacher|caseworker|lawyer|attorney|officer|detective|pastor|senator|representative|mayor|governor)\s+)([A-Z][a-z]{1,30})(?:\s+[A-Z][a-z]{1,30})?\b/gi,
      "$1[PERSON]",
    )
    .trim();
}

function stringArray(value: unknown, maxItems = 12) {
  if (!Array.isArray(value)) return [];
  return value
    .filter((x) => typeof x === "string")
    .map((x) => scrub(String(x)))
    .filter((x) => x && !containsObviousIdentifier(x))
    .slice(0, maxItems);
}

function normalizeFact(value: string) {
  return value.toLowerCase().replace(/[^a-z0-9]+/g, " ").trim().slice(0, 220);
}

function temporalLikely(text: string) {
  return /\b(today|tonight|tomorrow|yesterday|morning|afternoon|evening|monday|tuesday|wednesday|thursday|friday|saturday|sunday|week|month|hour|minute|am|pm|deadline|due|appointment|remind|remember to|need to|have to|gotta|must|before|after|by \d|at \d|in \d)\b/i.test(text);
}

async function processDeidentified(req: Request, installation: any, body: any) {
  const forbiddenFields = new Set([
    "user_text", "raw_text", "content", "source_excerpt", "session_id", "device_id", "user_id",
    "audio", "audio_bytes", "audio_base64", "audio_url", "pcm", "wav", "recording", "recording_url",
  ]);
  if (containsForbiddenField(body, forbiddenFields)) {
    return json(400, { error: "privacy_boundary_violation" });
  }
  if (safeText(body.privacy_version, 40) !== "deid-v1") {
    return json(400, { error: "unsupported_privacy_version" });
  }

  const text = safeText(body.sanitized_text, 12000);
  if (!text) return json(400, { error: "empty_sanitized_text" });
  if (containsObviousIdentifier(text)) return json(422, { error: "client_deidentification_failed" });

  const originalRaw = Number(body.original_characters ?? text.length);
  const originalCharacters = Number.isFinite(originalRaw)
    ? Math.max(text.length, Math.min(200000, Math.trunc(originalRaw)))
    : text.length;
  const redactionRaw = Number(body.redaction_count ?? 0);
  const redactionCount = Number.isFinite(redactionRaw)
    ? Math.max(0, Math.min(1000, Math.trunc(redactionRaw)))
    : 0;

  const extractionRun = await askBrain(req, "context_extractor", `DE-IDENTIFIED USER MESSAGE:\n${text}`);
  const extraction: Record<string, string[]> = {
    core_emotions: stringArray((extractionRun.data as any).core_emotions),
    vulnerabilities: stringArray((extractionRun.data as any).vulnerabilities),
    life_details: stringArray((extractionRun.data as any).life_details),
    implicit_needs: stringArray((extractionRun.data as any).implicit_needs),
  };
  if (containsObviousIdentifier(JSON.stringify(extraction))) {
    return json(422, { error: "model_deidentification_failed" });
  }

  const { data: extractionRow, error: extractionError } = await db
    .from("mom_context_extractions")
    .insert({
      device_id: installation.device_id,
      session_id: null,
      raw_text: null,
      extraction,
      model: extractionRun.model,
      input_characters: originalCharacters,
      output_characters: extractionRun.raw.length,
      latency_ms: extractionRun.latencyMs,
    })
    .select("id")
    .single();
  if (extractionError) throw new Error(`extraction_insert:${safeError(extractionError)}`);

  let factsProduced = 0;
  for (const [category, values] of Object.entries(extraction)) {
    for (const value of values) {
      const normalizedKey = normalizeFact(value);
      if (!normalizedKey) continue;
      const { error } = await db.rpc("upsert_mom_profile_fact", {
        p_device_id: installation.device_id,
        p_category: category,
        p_normalized_key: normalizedKey,
        p_value: value,
        p_truth_state: "explicit",
        p_confidence: 1,
        p_source_session_id: null,
        p_source_excerpt: null,
        p_metadata: { extraction_id: extractionRow.id, privacy_version: "deid-v1" },
      });
      if (error) throw new Error(`profile_upsert:${safeError(error)}`);
      factsProduced++;
    }
  }

  const temporalItems: any[] = [];
  if (temporalLikely(text)) {
    const temporalRun = await askBrain(req, "temporal", `DE-IDENTIFIED USER MESSAGE:\n${text}`);
    const rawItems = Array.isArray((temporalRun.data as any).items)
      ? (temporalRun.data as any).items.slice(0, 8)
      : [];

    for (const raw of rawItems) {
      const kind = safeText(raw?.kind, 20);
      const title = scrub(safeText(raw?.title, 300));
      const detail = scrub(safeText(raw?.detail, 1000));
      const timeText = scrub(safeText(raw?.time_text, 200));
      if (!title || !["task", "reminder", "deadline", "appointment", "follow_up", "event"].includes(kind)) continue;
      if (containsObviousIdentifier(`${title} ${detail} ${timeText}`)) continue;
      const dueText = safeText(raw?.due_at, 80);
      const dueAt = dueText && !Number.isNaN(Date.parse(dueText)) ? new Date(dueText).toISOString() : null;
      const item = {
        kind,
        title,
        detail: detail || null,
        due_at: dueAt,
        time_text: timeText || null,
        urgency: Math.max(0, Math.min(1, Number(raw?.urgency ?? 0.5) || 0.5)),
        importance: Math.max(0, Math.min(1, Number(raw?.importance ?? 0.5) || 0.5)),
      };
      const { error } = await db.from("mom_temporal_items").insert({
        device_id: installation.device_id,
        session_id: null,
        extraction_id: extractionRow.id,
        ...item,
        source_excerpt: null,
      });
      if (error) throw new Error(`temporal_insert:${safeError(error)}`);
      temporalItems.push(item);
    }

    const { error: runError } = await db.from("mom_agent_runs").insert({
      device_id: installation.device_id,
      session_id: null,
      agent: "temporal_deidentified",
      model: temporalRun.model,
      success: true,
      input_characters: originalCharacters,
      output_characters: temporalRun.raw.length,
      temporal_items_produced: temporalItems.length,
      latency_ms: temporalRun.latencyMs,
      metadata: { privacy_version: "deid-v1" },
    });
    if (runError) throw new Error(`temporal_run_insert:${safeError(runError)}`);
  }

  const { error: extractorRunError } = await db.from("mom_agent_runs").insert({
    device_id: installation.device_id,
    session_id: null,
    agent: "context_extractor_deidentified",
    model: extractionRun.model,
    success: true,
    input_characters: originalCharacters,
    output_characters: extractionRun.raw.length,
    facts_produced: factsProduced,
    latency_ms: extractionRun.latencyMs,
    metadata: { privacy_version: "deid-v1", redaction_count: redactionCount },
  });
  if (extractorRunError) throw new Error(`extractor_run_insert:${safeError(extractorRunError)}`);

  if (!String(installation.device_id).startsWith("mom-ci-")) {
    const { error } = await db.from("mom_research_corpus").insert({
      extraction,
      model: extractionRun.model,
      input_characters: originalCharacters,
      output_characters: extractionRun.raw.length,
      latency_ms: extractionRun.latencyMs,
      original_created_at: new Date().toISOString(),
      privacy_version: "deid-v1",
      redaction_count: redactionCount,
    });
    if (error) throw new Error(`research_insert:${safeError(error)}`);
  }

  return json(200, {
    ok: true,
    facts_produced: factsProduced,
    temporal_items: temporalItems.length,
    data_points: factsProduced + temporalItems.length,
    redactions: redactionCount,
    privacy_version: "deid-v1",
  });
}

async function snapshot(installation: any) {
  const [{ count: facts }, { count: extractions }, { count: temporal }, { data: runs }] = await Promise.all([
    db.from("mom_profile_facts").select("*", { count: "exact", head: true }).eq("device_id", installation.device_id),
    db.from("mom_context_extractions").select("*", { count: "exact", head: true }).eq("device_id", installation.device_id),
    db.from("mom_temporal_items").select("*", { count: "exact", head: true }).eq("device_id", installation.device_id),
    db.from("mom_agent_runs")
      .select("input_characters,facts_produced,temporal_items_produced,latency_ms")
      .eq("device_id", installation.device_id)
      .in("agent", ["context_extractor_deidentified", "temporal_deidentified"])
      .order("created_at", { ascending: false })
      .limit(100),
  ]);
  const userChars = (runs ?? [])
    .filter((run: any) => Number(run.facts_produced ?? 0) > 0)
    .reduce((sum: number, run: any) => sum + Number(run.input_characters ?? 0), 0);
  const unique = Number(facts ?? 0) + Number(temporal ?? 0);
  const latencyRows = (runs ?? []).filter((run: any) => Number.isFinite(run.latency_ms));
  return json(200, {
    ok: true,
    privacy_version: "deid-v1",
    content_preview_available: false,
    totals: {
      profile_facts: facts ?? 0,
      extractions: extractions ?? 0,
      temporal_items: temporal ?? 0,
      unique_data_points: unique,
      user_input_characters: userChars,
      data_points_per_1000_user_chars: Number(((unique * 1000) / Math.max(1, userChars)).toFixed(2)),
      average_agent_latency_ms: latencyRows.length
        ? Math.round(latencyRows.reduce((sum: number, run: any) => sum + Number(run.latency_ms), 0) / latencyRows.length)
        : null,
    },
    latest_facts: [],
    open_temporal_items: [],
  });
}

async function cleanupTest(installation: any) {
  if (!String(installation.device_id).startsWith("mom-ci-")) return json(403, { error: "test_cleanup_forbidden" });
  for (const table of ["mom_agent_runs", "mom_temporal_items", "mom_profile_facts", "mom_context_extractions"]) {
    const { error } = await db.from(table).delete().eq("device_id", installation.device_id);
    if (error) throw error;
  }
  return json(200, { ok: true });
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json(405, { error: "method_not_allowed" });
  let body: any;
  try { body = await req.json(); } catch { return json(400, { error: "invalid_json" }); }

  const action = safeText(body?.action, 40);
  if (action === "health") {
    const brain = await fetch(BRAIN_URL, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ action: "health" }),
    });
    let data: any = {};
    try { data = await brain.json(); } catch {}
    return json(200, {
      ok: true,
      service: "mom-intelligence",
      version: 8,
      configured: brain.ok && data?.configured === true,
      privacy_version: "deid-v1",
      raw_text_accepted: false,
      audio_input_accepted: false,
      detached_research_corpus: true,
      content_preview_available: false,
      bounded_brain_agents: true,
    });
  }

  const installation = await authenticate(req);
  if (!installation) return json(401, { error: "invalid_installation_token" });

  try {
    if (action === "process_deidentified") return await processDeidentified(req, installation, body);
    if (action === "snapshot") return await snapshot(installation);
    if (action === "cleanup_test") return await cleanupTest(installation);
    if (action === "process") return json(410, { error: "raw_extraction_disabled" });
    return json(400, { error: "unknown_action" });
  } catch (error) {
    console.error("mom-intelligence", action, safeError(error));
    return json(500, { error: "server_error" });
  }
});
