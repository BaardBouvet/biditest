-- models/marts/graph_stats.sql
-- ─────────────────────────────────────────────────────────────────────────────
-- Wraps pg_ripple.graph_stats() (BIDI-OBS-01) as a dbt table model so the
-- per-source-graph triple counts, last-write timestamps, and conflict counters
-- are available via standard SQL tooling.
--
-- Run: dbt run --select graph_stats

{{ config(materialized='table') }}

SELECT
    graph_iri,
    triple_count,
    last_write_at,
    conflicts_total,
    subscriptions_active
FROM pg_ripple.graph_stats()
