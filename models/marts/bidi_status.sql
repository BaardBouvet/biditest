-- models/marts/bidi_status.sql
-- ─────────────────────────────────────────────────────────────────────────────
-- Per-subscription operational health from pg_ripple.bidi_status().
-- Shows queue depth, pending linkbacks, dead-letter counts, and pg-trickle
-- delivery state for each relay subscription.
--
-- Run: dbt run --select bidi_status

{{ config(materialized='view') }}

SELECT *
FROM pg_ripple.bidi_status()
