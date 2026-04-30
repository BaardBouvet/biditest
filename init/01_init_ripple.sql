-- Runs automatically when the pg-ripple container first starts.
-- The pg_ripple extension is already installed in the image; this script
-- enables it in the biditest database, registers mappings/rules/policies,
-- and creates supporting schemas.

CREATE EXTENSION IF NOT EXISTS pg_ripple;

-- ─────────────────────────────────────────────────────────────────────────────
-- Step 1: Register the two source-graph JSON mappings (BIDI-ATTR-01)
-- ─────────────────────────────────────────────────────────────────────────────

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

-- ─────────────────────────────────────────────────────────────────────────────
-- Step 2: Composite-identity rule — merge on shared email (BIDI-REF-01)
-- ─────────────────────────────────────────────────────────────────────────────

SELECT pg_ripple.drop_rules('same_email');

SELECT pg_ripple.load_rules(
    rules    => '?x <http://www.w3.org/2002/07/owl#sameAs> ?y :-
                   ?x <http://example.org/email> ?e,
                   ?y <http://example.org/email> ?e,
                   ?x != ?y .',
    rule_set => 'same_email'
);

-- ─────────────────────────────────────────────────────────────────────────────
-- Step 3: latest_wins conflict policy on ex:name (BIDI-CONFLICT-01)
-- ─────────────────────────────────────────────────────────────────────────────

SELECT pg_ripple.register_conflict_policy(
    predicate => 'http://example.org/name',
    strategy  => 'latest_wins',
    config    => '{
      "timestamp_predicate":
        "http://www.w3.org/ns/prov#generatedAtTime"
    }'::jsonb
);

-- ─────────────────────────────────────────────────────────────────────────────
-- Step 5: Subscriptions for both relays (BIDI-LOOP-01)
-- ─────────────────────────────────────────────────────────────────────────────
-- With only name set, pg_ripple automatically defaults exclude_graphs to the
-- same value, so CRM-originated writes don't echo back to CRM, and vice-versa.

SELECT pg_ripple.create_subscription(
    name         => 'crm_relay',
    filter_sparql => '
        FILTER EXISTS { ?s <http://example.org/email> ?e }
        FILTER(?g NOT IN (<urn:source:crm>))
    '
);

SELECT pg_ripple.create_subscription(
    name         => 'erp_relay',
    filter_sparql => '
        FILTER EXISTS { ?s <http://example.org/email> ?e }
        FILTER(?g NOT IN (<urn:source:erp>))
    '
);

-- ─────────────────────────────────────────────────────────────────────────────
-- Database defaults and access control
-- ─────────────────────────────────────────────────────────────────────────────

-- Make rule_graph_scope = 'all' the permanent default for this database so
-- the Datalog engine sees triples across all named graphs on every connection.
ALTER DATABASE biditest SET pg_ripple.rule_graph_scope = 'all';

-- Schema for the pg-trickle inbox helper tables (used in Step 6).
CREATE SCHEMA IF NOT EXISTS pg_ripple_inbox;

-- Grant the dbt user access to both the pg_ripple and public schemas.
GRANT USAGE ON SCHEMA pg_ripple     TO postgres;
GRANT USAGE ON SCHEMA pg_ripple_inbox TO postgres;
GRANT ALL   ON SCHEMA public        TO postgres;
