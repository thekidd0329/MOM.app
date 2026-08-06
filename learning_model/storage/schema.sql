-- MOM local learning-store foundation.
-- Intentionally runtime-language agnostic.

PRAGMA foreign_keys = ON;

CREATE TABLE IF NOT EXISTS observations (
    id TEXT PRIMARY KEY,
    user_id TEXT NOT NULL,
    observed_at TEXT NOT NULL,
    source_type TEXT NOT NULL,
    source TEXT NOT NULL,
    payload_json TEXT NOT NULL,
    confidence REAL,
    sensitivity TEXT NOT NULL DEFAULT 'normal',
    expires_at TEXT,
    created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_observations_user_time
ON observations(user_id, observed_at);

CREATE TABLE IF NOT EXISTS fact_candidates (
    id TEXT PRIMARY KEY,
    user_id TEXT NOT NULL,
    created_at TEXT NOT NULL,
    subject TEXT NOT NULL,
    predicate TEXT NOT NULL,
    value_json TEXT NOT NULL,
    confidence REAL,
    confirmation_needed INTEGER NOT NULL DEFAULT 1,
    confirmation_question TEXT,
    memory_scope TEXT NOT NULL DEFAULT 'short_term',
    state TEXT NOT NULL DEFAULT 'candidate',
    expires_at TEXT
);

CREATE INDEX IF NOT EXISTS idx_candidates_user_state
ON fact_candidates(user_id, state);

CREATE TABLE IF NOT EXISTS candidate_observations (
    candidate_id TEXT NOT NULL,
    observation_id TEXT NOT NULL,
    PRIMARY KEY (candidate_id, observation_id),
    FOREIGN KEY (candidate_id) REFERENCES fact_candidates(id),
    FOREIGN KEY (observation_id) REFERENCES observations(id)
);

CREATE TABLE IF NOT EXISTS confirmed_facts (
    id TEXT PRIMARY KEY,
    user_id TEXT NOT NULL,
    confirmed_at TEXT NOT NULL,
    subject TEXT NOT NULL,
    predicate TEXT NOT NULL,
    value_json TEXT NOT NULL,
    confirmation_source TEXT NOT NULL,
    state TEXT NOT NULL DEFAULT 'confirmed',
    importance REAL NOT NULL DEFAULT 0.5,
    valid_from TEXT,
    valid_until TEXT,
    last_verified_at TEXT,
    superseded_by TEXT,
    FOREIGN KEY (superseded_by) REFERENCES confirmed_facts(id)
);

CREATE INDEX IF NOT EXISTS idx_facts_lookup
ON confirmed_facts(user_id, subject, predicate, state);

CREATE TABLE IF NOT EXISTS fact_provenance (
    fact_id TEXT NOT NULL,
    event_id TEXT NOT NULL,
    source_kind TEXT NOT NULL,
    source_id TEXT,
    PRIMARY KEY (fact_id, event_id),
    FOREIGN KEY (fact_id) REFERENCES confirmed_facts(id)
);

CREATE TABLE IF NOT EXISTS corrections (
    id TEXT PRIMARY KEY,
    user_id TEXT NOT NULL,
    corrected_at TEXT NOT NULL,
    target_fact_id TEXT NOT NULL,
    replacement_fact_id TEXT,
    replacement_value_json TEXT NOT NULL,
    reason TEXT NOT NULL,
    FOREIGN KEY (target_fact_id) REFERENCES confirmed_facts(id),
    FOREIGN KEY (replacement_fact_id) REFERENCES confirmed_facts(id)
);

CREATE TABLE IF NOT EXISTS memories (
    id TEXT PRIMARY KEY,
    user_id TEXT NOT NULL,
    created_at TEXT NOT NULL,
    memory_type TEXT NOT NULL,
    content_json TEXT NOT NULL,
    state TEXT NOT NULL DEFAULT 'confirmed',
    importance REAL NOT NULL DEFAULT 0.5,
    retrieval_tags_json TEXT NOT NULL DEFAULT '[]',
    provenance_json TEXT NOT NULL,
    last_accessed_at TEXT,
    last_verified_at TEXT,
    valid_until TEXT
);

CREATE INDEX IF NOT EXISTS idx_memories_user_type_state
ON memories(user_id, memory_type, state);

CREATE TABLE IF NOT EXISTS learning_events (
    id TEXT PRIMARY KEY,
    user_id TEXT NOT NULL,
    created_at TEXT NOT NULL,
    event_type TEXT NOT NULL,
    entity_id TEXT NOT NULL,
    conversation_id TEXT,
    metadata_json TEXT NOT NULL DEFAULT '{}'
);

CREATE INDEX IF NOT EXISTS idx_learning_events_user_time
ON learning_events(user_id, created_at);
