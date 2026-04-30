-- models/staging/stg_crm_contacts.sql
-- ─────────────────────────────────────────────────────────────────────────────
-- Light staging model that normalises types from the raw CRM seed.
-- Downstream models (ingest macros, mart queries) reference this view.

{{ config(materialized='view') }}

SELECT
    id                          AS contact_id,
    email,
    name,
    last_modified::timestamptz  AS last_modified_at,
    'https://crm.example.com/contacts/' || id AS subject_iri,
    '<urn:source:crm>'          AS graph_iri
FROM {{ ref('crm_contacts') }}
