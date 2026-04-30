-- analyses/worked_example_steps.sql
-- ─────────────────────────────────────────────────────────────────────────────
-- Full verbatim SQL for all 8 steps of the worked example from:
-- https://github.com/grove/pg-ripple/blob/main/roadmap/v0.77.0-full.md
-- (worked example ships unchanged in v0.78.0)
--
-- This file is a reference / scratch-pad.  The dbt macros and models run the
-- same SQL in a structured way.  You can also execute blocks from this file
-- directly in psql or the VS Code SQLTools pane connected to the db service.
--
-- Prerequisites: the init/01_init_ripple.sql script has already run (the
-- devcontainer Docker Compose does this automatically on first start).

-- ═══════════════════════════════════════════════════════════════════════════
-- Step 1 — Register the two source-graph JSON mappings (BIDI-ATTR-01)
-- ═══════════════════════════════════════════════════════════════════════════

SELECT pg_ripple.register_json_mapping(
    name              => 'crm_contact',
    default_graph_iri => '<urn:source:crm>',
    iri_template      => 'https://crm.example.com/contacts/{id}',
    iri_match_pattern => '^https://crm.example.com/contacts/',
    timestamp_path    => '$.lastModified',
    context           => '{
      "@vocab":       "http://example.org/",
      "email":        {"@id": "http://example.org/email"},
      "name":         {"@id": "http://example.org/name"},
      "lastModified": {"@id": "http://example.org/lastModified"}
    }'::jsonb
);

SELECT pg_ripple.register_json_mapping(
    name              => 'erp_contact',
    default_graph_iri => '<urn:source:erp>',
    iri_template      => 'https://erp.example.com/api/contact/{id}',
    iri_match_pattern => '^https://erp.example.com/api/contact/',
    timestamp_path    => '$.lastModified',
    context           => '{
      "@vocab":       "http://example.org/",
      "email":        {"@id": "http://example.org/email"},
      "name":         {"@id": "http://example.org/name"},
      "lastModified": {"@id": "http://example.org/lastModified"}
    }'::jsonb
);

-- ═══════════════════════════════════════════════════════════════════════════
-- Step 2 — Composite-identity Datalog rule: merge on shared email (BIDI-REF-01)
-- ═══════════════════════════════════════════════════════════════════════════
--
-- After both sources ingest a contact with the same email, the rule fires and
-- populates owl:sameAs, linking the two IRIs in the hub.

SELECT pg_ripple.create_datalog_rule($$
    sameAs(?a, ?b) :-
        <http://example.org/email>(?a, ?e),
        <http://example.org/email>(?b, ?e),
        ?a != ?b.
$$);

-- ═══════════════════════════════════════════════════════════════════════════
-- Step 3 — latest_wins conflict policy on ex:name (BIDI-CONFLICT-01)
-- ═══════════════════════════════════════════════════════════════════════════
--
-- The comparator reads per-triple prov:generatedAtTime annotations that
-- ingest_json(mode => 'diff') derives from each row's lastModified field.
-- The source with the higher timestamp wins in the resolved projection.
-- Losing assertions remain intact in their named graph (non-destructive).

SELECT pg_ripple.register_conflict_policy(
    predicate => 'http://example.org/name',
    strategy  => 'latest_wins',
    config    => '{
      "timestamp_predicate": "http://www.w3.org/ns/prov#generatedAtTime"
    }'::jsonb
);

-- ═══════════════════════════════════════════════════════════════════════════
-- Step 4 — Ingest from both sides using diff mode (BIDI-DIFF-01)
-- ═══════════════════════════════════════════════════════════════════════════
--
-- CRM: Ada L. at 10:00 UTC
SELECT pg_ripple.ingest_json(
    payload     => '{
        "id":           "c-42",
        "email":        "ada@example.com",
        "name":         "Ada L.",
        "lastModified": "2026-04-29T10:00:00Z"
    }'::jsonb,
    subject_iri => 'https://crm.example.com/contacts/c-42',
    mapping     => 'crm_contact',
    graph_iri   => '<urn:source:crm>',
    mode        => 'diff'
);

-- ERP: Ada Lovelace at 11:30 UTC (later → wins under latest_wins)
SELECT pg_ripple.ingest_json(
    payload     => '{
        "id":           "7",
        "email":        "ada@example.com",
        "name":         "Ada Lovelace",
        "lastModified": "2026-04-29T11:30:00Z"
    }'::jsonb,
    subject_iri => 'https://erp.example.com/api/contact/7',
    mapping     => 'erp_contact',
    graph_iri   => '<urn:source:erp>',
    mode        => 'diff'
);

-- CRM: grace@example.com (no ERP counterpart yet → fresh INSERT event)
SELECT pg_ripple.ingest_json(
    payload     => '{
        "id":           "c-99",
        "email":        "grace@example.com",
        "name":         "Grace H.",
        "lastModified": "2026-04-29T12:00:00Z"
    }'::jsonb,
    subject_iri => 'https://crm.example.com/contacts/c-99',
    mapping     => 'crm_contact',
    graph_iri   => '<urn:source:crm>',
    mode        => 'diff'
);

-- ── Verify the resolved projection ──────────────────────────────────────────
-- Expected: ada@example.com → name = "Ada Lovelace" (ERP wins)
SELECT *
FROM pg_ripple.sparql($sparql$
    PREFIX ex: <http://example.org/>
    SELECT ?subject ?email ?name
    WHERE {
        ?subject ex:email ?email ;
                 ex:name  ?name .
    }
    ORDER BY ?email
$sparql$) AS t(subject TEXT, email TEXT, name TEXT);

-- Verify the CRM raw assertion is still intact (non-destructive loser)
SELECT *
FROM pg_ripple.sparql($sparql$
    PREFIX ex: <http://example.org/>
    SELECT ?name
    FROM NAMED <urn:source:crm>
    WHERE {
        GRAPH <urn:source:crm> {
            <https://crm.example.com/contacts/c-42> ex:name ?name .
        }
    }
$sparql$) AS t(name TEXT);

-- ═══════════════════════════════════════════════════════════════════════════
-- Step 5 — Subscriptions with loop suppression (BIDI-LOOP-01, BIDI-CAS-01)
-- ═══════════════════════════════════════════════════════════════════════════
--
-- target_graph set → rewrite_target_graph and exclude_graphs default to
-- the same value, so:
--   • Events emitted to the CRM relay use CRM-shaped IRIs
--   • CRM-originated writes do not echo back to CRM

SELECT pg_ripple.create_subscription(
    name         => 'crm_relay',
    frame        => '{
      "@context": {"ex": "http://example.org/"},
      "ex:email": {},
      "ex:name":  {}
    }'::jsonb,
    target_graph => '<urn:source:crm>'
);

SELECT pg_ripple.create_subscription(
    name         => 'erp_relay',
    frame        => '{
      "@context": {"ex": "http://example.org/"},
      "ex:email": {},
      "ex:name":  {}
    }'::jsonb,
    target_graph => '<urn:source:erp>'
);

-- ═══════════════════════════════════════════════════════════════════════════
-- Step 6 — Inspect the outbound UPDATE event for the ERP-originated name change
-- ═══════════════════════════════════════════════════════════════════════════
--
-- After ingest, the crm_relay outbox should contain one UPDATE event for
-- ada@example.com with after.ex:name = "Ada Lovelace" and
-- base.ex:name = "Ada L." (the CAS precondition).

SELECT
    event_id,
    payload->>'event_type'  AS event_type,
    payload->>'subject'     AS subject,
    payload->'after'        AS after_frame,
    payload->'base'         AS base_frame
FROM pg_ripple.crm_relay_outbox
ORDER BY emitted_at DESC
LIMIT 5;

-- ═══════════════════════════════════════════════════════════════════════════
-- Step 7 — Fresh CRM-side contact: ERP relay receives INSERT, calls linkback
-- ═══════════════════════════════════════════════════════════════════════════
--
-- grace@example.com has no ERP counterpart → the erp_relay outbox holds an
-- INSERT event with subject_resolved = false.
-- The relay POSTs to ERP, gets back ID 4011, then calls record_linkback.

SELECT
    event_id,
    payload->>'event_type'            AS event_type,
    payload->>'subject'               AS subject,
    (payload->>'subject_resolved')::boolean AS subject_resolved,
    payload->'after'                  AS after_frame
FROM pg_ripple.erp_relay_outbox
WHERE (payload->>'subject_resolved')::boolean = false
ORDER BY emitted_at DESC
LIMIT 1;

-- After the relay creates the entity in ERP and gets back ID 4011:
-- SELECT pg_ripple.record_linkback(
--     event_id  => '<paste event_id UUID here>'::uuid,
--     target_id => '4011'
-- );
--
-- pg_ripple expands '4011' through the erp_contact iri_template to
-- https://erp.example.com/api/contact/4011, writes owl:sameAs, and flushes
-- any buffered follow-up events into the outbox in sequence order.

-- ═══════════════════════════════════════════════════════════════════════════
-- Step 8 — Subsequent name edit from ERP to CRM (BIDI-CONFLICT-01 in action)
-- ═══════════════════════════════════════════════════════════════════════════
--
-- User edits ada@example.com in ERP at 2026-04-30T08:00Z.
-- latest_wins sees a newer timestamp → resolved projection updates →
-- crm_relay outbox receives UPDATE with base: {"ex:name": "Ada Lovelace"}.
-- The erp_relay does NOT fire for this change (exclude_graphs suppresses it).

SELECT pg_ripple.ingest_json(
    payload     => '{
        "id":           "7",
        "email":        "ada@example.com",
        "name":         "Ada Lovelace (updated)",
        "lastModified": "2026-04-30T08:00:00Z"
    }'::jsonb,
    subject_iri => 'https://erp.example.com/api/contact/7',
    mapping     => 'erp_contact',
    graph_iri   => '<urn:source:erp>',
    mode        => 'diff'
);

-- Confirm the resolved projection now returns the updated name
SELECT *
FROM pg_ripple.sparql($sparql$
    PREFIX ex: <http://example.org/>
    SELECT ?subject ?name
    WHERE {
        ?subject ex:email "ada@example.com" ;
                 ex:name  ?name .
    }
$sparql$) AS t(subject TEXT, name TEXT);

-- ═══════════════════════════════════════════════════════════════════════════
-- Observability — per-graph metrics (BIDI-OBS-01)
-- ═══════════════════════════════════════════════════════════════════════════

SELECT * FROM pg_ripple.graph_stats();

-- Check per-triple annotations written by diff mode
SELECT *
FROM pg_ripple.sparql($sparql$
    PREFIX ex:   <http://example.org/>
    PREFIX prov: <http://www.w3.org/ns/prov#>

    SELECT ?subject ?name ?ts
    WHERE {
        ?subject ex:name ?name .
        << ?subject ex:name ?name >> prov:generatedAtTime ?ts .
    }
    ORDER BY ?subject
$sparql$) AS t(subject TEXT, name TEXT, ts TEXT);
