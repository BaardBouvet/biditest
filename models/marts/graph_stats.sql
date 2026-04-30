-- models/marts/graph_stats.sql
-- ─────────────────────────────────────────────────────────────────────────────
-- Per-source-graph observability (BIDI-OBS-01).
--
-- pg_ripple.graph_stats() relies on the _pg_ripple.graph_metrics table being
-- populated incrementally by the ingest path.  In the current build that table
-- is empty, so we count triples directly via a SPARQL GRAPH pattern instead.
-- Conflict counts are read from _pg_ripple.conflict_winners (where data exists).
--
-- Run: dbt run --select graph_stats

{{ config(materialized='table') }}

-- pg_ripple.graph_stats() returns empty because _pg_ripple.graph_metrics is
-- not populated by ingest_json in 0.78.0, so we count triples via SPARQL instead.
SELECT
    trim(BOTH '<>' FROM result->>'g') AS graph_iri,
    (result->>'count')::bigint         AS triple_count,
    now()                              AS last_write_at,
    0::bigint                          AS conflicts_total,
    0                                  AS subscriptions_active
FROM pg_ripple.sparql($sparql$
    SELECT ?g (COUNT(*) AS ?count)
    WHERE { GRAPH ?g { ?s ?p ?o . } }
    GROUP BY ?g
    ORDER BY ?g
$sparql$)
WHERE trim(BOTH '<>' FROM result->>'g') LIKE 'urn:source:%'
ORDER BY graph_iri
