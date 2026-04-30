-- models/marts/outbox_events.sql
-- ─────────────────────────────────────────────────────────────────────────────
-- Reads the latest pending outbox events from both relay outbox tables so you
-- can inspect what pg_ripple would deliver to each target system.
--
-- The outbox tables are provisioned by create_subscription (BIDI-OUTBOX-01)
-- and named <subscription_name>_outbox by convention.  The model unions both
-- relay tables into a single view.
--
-- Run: dbt run --select outbox_events

{{ config(materialized='view') }}

SELECT
    'crm_relay'             AS subscription,
    event_id,
    (payload->>'event_type')  AS event_type,
    (payload->>'subject')     AS subject,
    (payload->>'subject_resolved')::boolean AS subject_resolved,
    (payload->>'graph')       AS graph,
    (payload->>'timestamp')::timestamptz    AS event_ts,
    payload->'after'          AS after_frame,
    payload->'base'           AS base_frame,
    emitted_at,
    delivered_at
FROM pg_ripple.crm_relay_outbox

UNION ALL

SELECT
    'erp_relay'             AS subscription,
    event_id,
    (payload->>'event_type')  AS event_type,
    (payload->>'subject')     AS subject,
    (payload->>'subject_resolved')::boolean AS subject_resolved,
    (payload->>'graph')       AS graph,
    (payload->>'timestamp')::timestamptz    AS event_ts,
    payload->'after'          AS after_frame,
    payload->'base'           AS base_frame,
    emitted_at,
    delivered_at
FROM pg_ripple.erp_relay_outbox

ORDER BY emitted_at DESC
