-- tests/assert_both_graphs_present.sql
-- ─────────────────────────────────────────────────────────────────────────────
-- Singular test: verifies that after ingest, both named graphs
-- (<urn:source:crm> and <urn:source:erp>) appear in the pg_ripple observability
-- view with at least one triple each.
--
-- The test passes when this query returns 0 rows.
-- A non-zero count means one or both graphs are missing or empty.

SELECT graph_iri
FROM {{ ref('graph_stats') }}
WHERE
    graph_iri IN ('urn:source:crm', 'urn:source:erp')
    AND triple_count < 1

-- Also fail if either expected graph is absent entirely.
UNION ALL

SELECT expected.graph_iri
FROM (
    VALUES ('urn:source:crm'), ('urn:source:erp')
) AS expected(graph_iri)
LEFT JOIN {{ ref('graph_stats') }} gs USING (graph_iri)
WHERE gs.graph_iri IS NULL
