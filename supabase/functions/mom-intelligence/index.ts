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
  if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) {
    throw new Error("invalid_json_output");
  }
  return parsed as Record<string, unknown>;
}

async function askBrain(req: Request, systemPrompt: string, userPrompt: string) {
  const started = Date.now();
  const response = await fetch(BRAIN_URL, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "x-mom-installation": req.headers.get("x-mom-installation") ?? "",
      "x-mom-token": req.headers.get("x-mom-token") ?? "",
    },
    body: JSON.stringify({
      action: "chat",
      system_prompt: systemPrompt,
      history: [],
      user_text: userPrompt,
      knowledge_context: "",
      model: "",
      temperature: 0,
      max_history: 2,
      context_mode: "none",
    }),
  });

  const rawBody = await response.text();
  let body: any = {};
  try { body = rawBody ? JSON.parse(rawBody) : {}; } catch {}
  if (!response.ok) {
    throw new Error(`brain_${response.status}:${safeText(body?.error ?? rawBody, 300)}`);
  }
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
  let text = safeText(value, 800);
  text = text
    .replace(/\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b/gi, "[EMAIL]")
    .replace(/https?:\/\/\S+|www\.\S+/gi, "[URL]")
    .replace(/(?<!\w)@[A-Za-z0-9_]{2,32}\b/g, "[HANDLE]")
    .replace(/\b\d{3}-\d{2}-\d{4}\b/g, "[SSN]")
    .replace(/(?<!\d)(?:\+?1[ .-]?)?\(?[2-9]\d{2}\)?[ .-]?\d{3}[ .-]?\d{4}(?!\d)/g, "[PHONE]")
    .replace(/\b(?:\d[ -]*?){13,19}\b/g, "[ACCOUNT_NUMBER]")
    .replace(
      /\b((?:my\s+)?(?:mom|mother|dad|father|parent|sister|brother|daughter|son|friend|girlfriend|boyfriend|wife|husband|partner|boss|manager|coworker|doctor|teacher|caseworker|lawyer|attorney|officer|detective|pastor|senator|representative|mayor|governor)\s+)([A-Z][a-z]{1,30})(?:\s+[A-Z][a-z]{1,30})?\b/gi,
      "$1[PERSON]",
    );
  return text.trim();
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

const extractorPrompt = `You are MOM's privacy-preserving silent data extraction parser.

The input has already been de-identified on the user's device. Do not reconstruct, infer, guess, or preserve identities. Generalize any remaining named person, organization, precise location, username, address, phone, email, account number, or other direct identifier.

Output ONLY valid JSON exactly as:
{"core_emotions":[],"vulnerabilities":[],"life_details":[],"implicit_needs":[]}

Rules:
1. Do not guess. Extract only information supported by the supplied de-identified text.
2. If no new data exists for a category, use [].
3. Keep each item concise and atomic.
4. Do not turn temporary states into permanent traits.
5. Never output proper names, exact addresses, usernames, account identifiers, phone numbers, email addresses, URLs, or exact coordinates.
6. Generalize public figures and organizations by role/category, for example "public official", "employer", "school", or "medical provider".
7. life_details may include generalized relationships, routines, preferences, projects, commitments, possessions, and broad context, but not identity-bearing details.
8. implicit_needs is the conservative immediate thing sought from MOM, such as validation, reassurance, information, problem-solving, planning, emotional support, or venting.
9. No prose or markdown.`;

const temporalPrompt = `You are MOM's privacy-preserving temporal/executive parser.

Output ONLY valid JSON exactly as:
{"items":[]}

Each item may contain:
{"kind":"task|reminder|deadline|appointment|follow_up|event","title":"short generalized title","detail":"optional generalized detail","due_at":"ISO-8601 or null","time_text":"original de-identified wording or null","urgency":0.0,"importance":0.0}

Rules:
1. Never invent dates, tasks, reminders, appointments, deadlines, or commitments.
2. Never output names or identity-bearing details.
3. Keep titles and details generalized.
4. If time is ambiguous, preserve de-identified time_text and use null due_at.
5. urgency is how soon action is needed; importance is how consequential it appears.
6. Empty array if none.
7. No prose or markdown.`;

function temporalLikely(text: string) {
  return /\b(today|tonight|tomorrow|yesterday|morning|afternoon|evening|monday|tuesday|wednesday|thursday|friday|saturday|sunday|week|month|hour|minute|am|pm|deadline|due|appointment|remind|remember to|need to|have to|gotta|must|before|after|by \d|at \d|in \d)\b/i.test(text);
}

async function processDeidentified(req: Request, installation: any, body: any) {
  const forbiddenFields = [
    "user_text", "raw_text", "content", "source_excerpt", "session_id", "device_id", "user_id",
  ];
  if (forbiddenFields.some((field) => Object.prototype.hasOwnProperty.call(body, field))) {
    return json(400, { error: "privacy_boundary_violation" });
  }
  if (safeText(body.privacy_version, 40) !== "deid-v1") {
    return json(400, { error: "unsupported_privacy_version" });
  }

  const text = safeText(body.sanitized_text, 12000);
  if (!text) return json(400, { error: "empty_sanitized_text" });
  if (containsObviousIdentifier(text)) {
    return json(422, { error: "client_deidentification_failed" });
  }

  const originalCharactersRaw = Number(body.original_characters ?? text.length);
  const originalCharacters = Number.isFinite(originalCharactersRaw)
    ? Math.max(text.length, Math.min(200000, Math.trunc(originalCharactersRaw)))
    : text.length;
  const redactionRaw = Number(body.redaction_count ?? 0);
  const redactionCount = Number.isFinite(redactionRaw)
    ? Math.max(0, Math.min(1000, Math.trunc(redactionRaw)))
    : 0;

  const extractionRun = await askBrain(
    req,
    extractorPrompt,
    `DE-IDENTIFIED USER MESSAGE:\n${text}`,
  );

  const extraction: Record<string, string[]> = {
    core_emotions: stringArray((extractionRun.data as any).core_emotions),
    vulnerabilities: stringArray((extractionRun.data as any).vulnerabilities),
    life_details: stringArray((extractionRun.data as any).life_details),
    implicit_needs: stringArray((extractionRun.data as any).implicit_needs),
  };

  const serializedExtraction = JSON.stringify(extraction);
  if (containsObviousIdentifier(serializedExtraction)) {
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
    const temporalRun = await askBrain(
      req,
      temporalPrompt,
      `DE-IDENTIFIED USER MESSAGE:\n${text}`,
    );
    const rawItems = Array.isArray((temporalRun.data as any).items)
      ? (temporalRun.data as any).items.slice(0, 8)
      : [];

    for (const raw of rawItems) {
      const kind = safeText(raw?.kind, 20);
      const title = scrub(safeText(raw?.title, 300));
      if (!title || !["task", "reminder", "deadline", "appointment", "follow_up", "event"].includes(kind)) continue;
      const detail = scrub(safeText(raw?.detail, 1000));
      const timeText = scrub(safeText(raw?.time_text, 200));
      if (containsObviousIdentifier(`${title} ${detail} ${timeText}`)) continue;

      const urgency = Math.max(0, Math.min(1, Number(raw?.urgency ?? 0.5) || 0.5));
      const importance = Math.max(0, Math.min(1, Number(raw?.importance ?? 0.5) || 0.5));
      const dueText = safeText(raw?.due_at, 80);
      const dueAt = dueText && !Number.isNaN(Date.parse(dueText))
        ? new Date(dueText).toISOString()
        : null;
      const item = {
        kind,
        title,
        detail: detail || null,
        due_at: dueAt,
        time_text: timeText || null,
        urgency,
        importance,
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

    const { error } = await db.from("mom_agent_runs").insert({
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
    if (error) throw new Error(`temporal_run_insert:${safeError(error)}`);
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

  // The research copy is deliberately detached: no device, user, session, raw
  // text, source excerpt, or extraction-row identifier is written with it.
  if (!String(installation.device_id).startsWith("mom-ci-")) {
    const { error: researchError } = await db.from("mom_research_corpus").insert({
      extraction,
      model: extractionRun.model,
      input_characters: originalCharacters,
      output_characters: extractionRun.raw.length,
      latency_ms: extractionRun.latencyMs,
      original_created_at: new Date().toISOString(),
      privacy_version: "deid-v1",
      redaction_count: redactionCount,
    });
    if (researchError) throw new Error(`research_insert:${safeError(researchError)}`);
  }

  const dataPoints = factsProduced + temporalItems.length;
  return json(200, {
    ok: true,
    facts_produced: factsProduced,
    temporal_items: temporalItems.length,
    data_points: dataPoints,
    redactions: redactionCount,
    privacy_version: "deid-v1",
  });
}

async function snapshot(installation: any) {
  const [
    { count: facts },
    { count: extractions },
    { count: temporal },
    { data: runs },
  ] = await Promise.all([
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
    .filter((row: any) => Number(row.facts_produced ?? 0) > 0)
    .reduce((sum: number, row: any) => sum + Number(row.input_characters ?? 0), 0);
  const uniquePoints = Number(facts ?? 0) + Number(temporal ?? 0);
  const latencyRows = (runs ?? []).filter((row: any) => Number.isFinite(row.latency_ms));
  const averageLatency = latencyRows.length
    ? Math.round(latencyRows.reduce((sum: number, row: any) => sum + Number(row.latency_ms), 0) / latencyRows.length)
    : null;

  return json(200, {
    ok: true,
    privacy_version: "deid-v1",
    content_preview_available: false,
    totals: {
      profile_facts: facts ?? 0,
      extractions: extractions ?? 0,
      temporal_items: temporal ?? 0,
      unique_data_points: uniquePoints,
      user_input_characters: userChars,
      data_points_per_1000_user_chars: Number(((uniquePoints * 1000) / Math.max(1, userChars)).toFixed(2)),
      average_agent_latency_ms: averageLatency,
    },
    latest_facts: [],
    open_temporal_items: [],
  });
}

async function cleanupTest(installation: any) {
  if (!String(installation.device_id).startsWith("mom-ci-")) {
    return json(403, { error: "test_cleanup_forbidden" });
  }
  for (const table of ["mom_agent_runs", "mom_temporal_items", "mom_profile_facts", "mom_context_extractions"]) {
    const { error } = await db.from(table).delete().eq("device_id", installation.device_id);
    if (error) throw new Error(`cleanup_${table}:${safeError(error)}`);
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
      version: 7,
      configured: brain.ok && data?.configured === true,
      privacy_version: "deid-v1",
      raw_text_accepted: false,
      detached_research_corpus: true,
      content_preview_available: false,
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
    const detail = safeError(error);
    console.error("mom-intelligence", action, detail);
    return json(500, { error: "server_error", detail });
  }
});
