import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";
import { Pool } from "jsr:@db/postgres@^0";

const U = Deno.env.get("SUPABASE_URL")!;
const K = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const D = Deno.env.get("SUPABASE_DB_URL")!;
const HB = (Deno.env.get("HF_API_BASE") ?? "https://router.huggingface.co/v1").replace(/\/$/, "");
const HM = (Deno.env.get("MOM_EXTRACT_MODEL") ?? Deno.env.get("MOM_MODEL") ?? "").trim();
const HE = Deno.env.get("HF_TOKEN") ?? Deno.env.get("HUGGINGFACE_API_KEY") ?? "";
const db = createClient(U, K, { auth: { persistSession: false, autoRefreshToken: false } });
const pool = new Pool(D, 1);
let tok = "";
let model = "";

const C = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "content-type, x-mom-installation, x-mom-token",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const j = (s: number, v: unknown) => new Response(JSON.stringify(v), {
  status: s,
  headers: { ...C, "Content-Type": "application/json; charset=utf-8" },
});
const t = (v: unknown, n = 1000) => typeof v === "string" ? v.trim().slice(0, n) : "";
const uuid = (v: string) => /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(v);

async function h(v: string) {
  const d = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(v));
  return [...new Uint8Array(d)].map((x) => x.toString(16).padStart(2, "0")).join("");
}

async function token() {
  if (HE) return HE;
  if (tok) return tok;
  const c = await pool.connect();
  try {
    const r = await c.queryObject<{ decrypted_secret: string }>(
      "select decrypted_secret from vault.decrypted_secrets where name='mom_hf_token' limit 1",
    );
    tok = r.rows[0]?.decrypted_secret?.trim() ?? "";
    return tok;
  } finally {
    c.release();
  }
}

async function auth(req: Request) {
  const id = req.headers.get("x-mom-installation") ?? "";
  const q = req.headers.get("x-mom-token") ?? "";
  if (!uuid(id) || q.length < 32) return null;
  const { data } = await db.from("mom_installations")
    .select("id,device_id,token_hash,revoked_at").eq("id", id).maybeSingle();
  if (!data || data.revoked_at || await h(q) !== data.token_hash) return null;
  return data;
}

async function hf(path: string, init: RequestInit = {}) {
  const k = await token();
  if (!k) throw Error("hf_secret_missing");
  const r = await fetch(HB + path, {
    ...init,
    headers: { "Content-Type": "application/json", Authorization: `Bearer ${k}`, ...(init.headers ?? {}) },
  });
  const x = await r.text();
  let b: any = x;
  try { b = x ? JSON.parse(x) : {}; } catch {}
  if (!r.ok) throw Error(`provider_${r.status}`);
  return b;
}

async function mdl() {
  if (HM) return HM;
  if (model) return model;
  const d = await hf("/models", { method: "GET" });
  const a = Array.isArray(d?.data) ? d.data : [];
  model = t(a.find((x: any) => t(x?.id))?.id, 300);
  if (!model) throw Error("no_model");
  return model;
}

function obj(v: unknown) {
  if (typeof v !== "string") return v as any;
  let s = v.trim().replace(/^```(?:json)?\s*/i, "").replace(/\s*```$/i, "");
  const a = s.indexOf("{");
  const b = s.lastIndexOf("}");
  if (a >= 0 && b > a) s = s.slice(a, b + 1);
  return JSON.parse(s);
}

async function ask(sys: string, prompt: string, max = 650) {
  const m = await mdl();
  const st = Date.now();
  const d = await hf("/chat/completions", {
    method: "POST",
    body: JSON.stringify({
      model: m,
      messages: [{ role: "system", content: sys }, { role: "user", content: prompt }],
      temperature: 0,
      max_tokens: max,
      stream: false,
    }),
  });
  const raw = t(d?.choices?.[0]?.message?.content, 12000);
  if (!raw) throw Error("empty_output");
  return { data: obj(raw), raw, model: m, latency: Date.now() - st };
}

const arr = (v: unknown) => Array.isArray(v)
  ? v.filter((x) => typeof x === "string").map((x) => t(x, 600)).filter(Boolean).slice(0, 12)
  : [];
const key = (v: string) => v.toLowerCase().replace(/[^a-z0-9]+/g, " ").trim().slice(0, 220);

const EX = `You are MOM's silent data extraction parser. Analyze ONLY the user's current message, using recent messages only to resolve references. Output ONLY valid JSON exactly as {"core_emotions":[],"vulnerabilities":[],"life_details":[],"implicit_needs":[]}. Rules: Do not guess. Extract explicit current-message information. If no new data for a category, use []. Keep each item concise and atomic. Do not turn temporary states into permanent traits. vulnerabilities includes explicit substance use, risks, triggers, dangerous situations, instability, or wellbeing-relevant circumstances. life_details includes explicit names, relationships, places, routines, schedules, possessions, projects, commitments, preferences, or physical context. implicit_needs is the conservative immediate thing sought from MOM such as validation, reassurance, information, problem-solving, distraction, planning, emotional support, or venting. No prose or markdown.`;

const TM = `You are MOM's silent temporal/executive agent. Output ONLY valid JSON exactly as {"items":[]}. Convert ONLY explicit time-sensitive information into items shaped {"kind":"task|reminder|deadline|appointment|follow_up|event","title":"short title","detail":"optional","due_at":"ISO-8601 or null","time_text":"original wording or null","urgency":0.0,"importance":0.0}. Never invent dates, tasks, reminders, appointments, deadlines, or commitments. Resolve relative time only when clear from the supplied local current time. If ambiguous, preserve time_text and use null due_at. urgency is how soon action is needed; importance is how consequential the user presents it. Empty array if none.`;

const timey = (s: string) => /\b(today|tonight|tomorrow|yesterday|morning|afternoon|evening|monday|tuesday|wednesday|thursday|friday|saturday|sunday|week|month|hour|minute|am|pm|deadline|due|appointment|remind|remember to|need to|have to|gotta|must|before|after|by \d|at \d|in \d)\b/i.test(s);

async function session(device: string, id: string) {
  if (!uuid(id)) return null;
  const { data } = await db.from("mom_chat_sessions").select("id")
    .eq("id", id).eq("device_id", device).maybeSingle();
  return data?.id ?? null;
}

async function recent(device: string, current: string) {
  const { data } = await db.from("mom_chat_messages").select("content")
    .eq("device_id", device).eq("role", "user").order("created_at", { ascending: false }).limit(6);
  return (data ?? []).map((r: any) => t(r.content, 1200)).filter((x: string) => x && x !== current).reverse();
}

async function runProcess(ins: any, body: any) {
  const text = t(body.user_text, 50000);
  if (!text) return j(400, { error: "empty_user_text" });
  const sid = await session(ins.device_id, t(body.session_id, 64));
  const prev = await recent(ins.device_id, text);
  const prompt = `Recent user messages (reference only):\n${prev.map((x: string, i: number) => `${i + 1}. ${x}`).join("\n")}\n\nCURRENT USER MESSAGE:\n${text}`;
  const ex = await ask(EX, prompt, 650);
  const clean: any = {
    core_emotions: arr(ex.data?.core_emotions),
    vulnerabilities: arr(ex.data?.vulnerabilities),
    life_details: arr(ex.data?.life_details),
    implicit_needs: arr(ex.data?.implicit_needs),
  };
  const { data: er, error: ee } = await db.from("mom_context_extractions").insert({
    device_id: ins.device_id,
    session_id: sid,
    raw_text: text,
    extraction: clean,
    model: ex.model,
    input_characters: text.length,
    output_characters: ex.raw.length,
    latency_ms: ex.latency,
  }).select("id").single();
  if (ee) throw ee;

  let facts = 0;
  for (const cat of Object.keys(clean)) {
    for (const value of clean[cat]) {
      const k = key(value);
      if (!k) continue;
      const { error } = await db.rpc("upsert_mom_profile_fact", {
        p_device_id: ins.device_id,
        p_category: cat,
        p_normalized_key: k,
        p_value: value,
        p_truth_state: "explicit",
        p_confidence: 1,
        p_source_session_id: sid,
        p_source_excerpt: text.slice(0, 1200),
        p_metadata: { extraction_id: er.id },
      });
      if (!error) facts++;
    }
  }

  await db.from("mom_agent_runs").insert({
    device_id: ins.device_id,
    session_id: sid,
    agent: "context_extractor",
    model: ex.model,
    success: true,
    input_characters: text.length,
    output_characters: ex.raw.length,
    facts_produced: facts,
    latency_ms: ex.latency,
    metadata: { extraction_id: er.id },
  });

  const items: any[] = [];
  if (timey(text)) {
    const now = t(body.local_now, 80) || new Date().toISOString();
    const tr = await ask(TM, `LOCAL CURRENT TIME: ${now}\nCURRENT USER MESSAGE:\n${text}`, 500);
    const raw = Array.isArray(tr.data?.items) ? tr.data.items.slice(0, 8) : [];
    for (const r of raw) {
      const kind = t(r?.kind, 20);
      const title = t(r?.title, 300);
      if (!title || !["task", "reminder", "deadline", "appointment", "follow_up", "event"].includes(kind)) continue;
      const urgency = Math.max(0, Math.min(1, Number(r?.urgency ?? .5) || .5));
      const importance = Math.max(0, Math.min(1, Number(r?.importance ?? .5) || .5));
      const due = t(r?.due_at, 80);
      const dueAt = due && !Number.isNaN(Date.parse(due)) ? new Date(due).toISOString() : null;
      const item = {
        kind,
        title,
        detail: t(r?.detail, 1000) || null,
        due_at: dueAt,
        time_text: t(r?.time_text, 200) || null,
        urgency,
        importance,
      };
      items.push(item);
      await db.from("mom_temporal_items").insert({
        device_id: ins.device_id,
        session_id: sid,
        extraction_id: er.id,
        ...item,
        source_excerpt: text.slice(0, 1200),
      });
    }
    await db.from("mom_agent_runs").insert({
      device_id: ins.device_id,
      session_id: sid,
      agent: "temporal",
      model: tr.model,
      success: true,
      input_characters: text.length,
      output_characters: tr.raw.length,
      temporal_items_produced: items.length,
      latency_ms: tr.latency,
    });
  }

  return j(200, {
    ok: true,
    extraction_id: er.id,
    extraction: clean,
    facts_produced: facts,
    temporal_items: items,
    data_points: facts + items.length,
    data_points_per_1000_chars: Number((((facts + items.length) * 1000) / Math.max(1, text.length)).toFixed(2)),
  });
}

async function snapshot(ins: any) {
  const [
    { count: facts },
    { count: extracts },
    { count: temporal },
    { data: latest },
    { data: open },
    { data: runs },
  ] = await Promise.all([
    db.from("mom_profile_facts").select("*", { count: "exact", head: true }).eq("device_id", ins.device_id),
    db.from("mom_context_extractions").select("*", { count: "exact", head: true }).eq("device_id", ins.device_id),
    db.from("mom_temporal_items").select("*", { count: "exact", head: true }).eq("device_id", ins.device_id),
    db.from("mom_profile_facts").select("category,value,truth_state,confidence,evidence_count,last_seen_at")
      .eq("device_id", ins.device_id).order("last_seen_at", { ascending: false }).limit(30),
    db.from("mom_temporal_items").select("kind,title,due_at,time_text,urgency,importance,status,created_at")
      .eq("device_id", ins.device_id).eq("status", "open").order("created_at", { ascending: false }).limit(20),
    db.from("mom_agent_runs").select("agent,input_characters,output_characters,facts_produced,temporal_items_produced,latency_ms,created_at")
      .eq("device_id", ins.device_id).order("created_at", { ascending: false }).limit(100),
  ]);
  const rr = runs ?? [];
  const input = rr.reduce((s: number, r: any) => s + (r.input_characters || 0), 0);
  const points = rr.reduce((s: number, r: any) => s + (r.facts_produced || 0) + (r.temporal_items_produced || 0), 0);
  const lat = rr.filter((r: any) => Number.isFinite(r.latency_ms));
  return j(200, {
    ok: true,
    totals: {
      profile_facts: facts ?? 0,
      extractions: extracts ?? 0,
      temporal_items: temporal ?? 0,
      agent_runs: rr.length,
      input_characters: input,
      data_points: points,
      data_points_per_1000_chars: Number(((points * 1000) / Math.max(1, input)).toFixed(2)),
      average_agent_latency_ms: lat.length ? Math.round(lat.reduce((s: number, r: any) => s + r.latency_ms, 0) / lat.length) : null,
    },
    latest_facts: latest ?? [],
    open_temporal_items: open ?? [],
  });
}

async function cleanup(ins: any) {
  if (!String(ins.device_id).startsWith("mom-ci-")) return j(403, { error: "test_cleanup_forbidden" });
  for (const table of ["mom_agent_runs", "mom_temporal_items", "mom_profile_facts", "mom_context_extractions"]) {
    const { error } = await db.from(table).delete().eq("device_id", ins.device_id);
    if (error) throw error;
  }
  return j(200, { ok: true });
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: C });
  if (req.method !== "POST") return j(405, { error: "method_not_allowed" });
  let body: any;
  try { body = await req.json(); } catch { return j(400, { error: "invalid_json" }); }
  const action = t(body?.action, 32);
  if (action === "health") return j(200, {
    ok: true,
    service: "mom-intelligence",
    version: 2,
    configured: (await token()).length > 0,
  });
  const ins = await auth(req);
  if (!ins) return j(401, { error: "invalid_installation_token" });
  try {
    if (action === "process") return await runProcess(ins, body);
    if (action === "snapshot") return await snapshot(ins);
    if (action === "cleanup_test") return await cleanup(ins);
    return j(400, { error: "unknown_action" });
  } catch (e) {
    console.error("mom-intelligence", action, e);
    return j(500, { error: "server_error", detail: e instanceof Error ? e.message : String(e) });
  }
});
