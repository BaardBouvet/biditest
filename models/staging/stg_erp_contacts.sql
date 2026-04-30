-- models/staging/stg_erp_contacts.sql
-- ─────────────────────────────────────────────────────────────────────────────
-- Light staging model that normalises types from the raw ERP seed.

{{ config(materialized='view') }}

SELECT
    id::text                    AS contact_id,
    email,
    name,
    last_modified::timestamptz  AS last_modified_at,
    'https://erp.example.com/api/contact/' || id AS subject_iri,
    '<urn:source:erp>'          AS graph_iri
FROM {{ ref('erp_contacts') }}
