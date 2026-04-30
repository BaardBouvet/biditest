-- models/marts/merged_contacts.sql
-- ─────────────────────────────────────────────────────────────────────────────
-- Queries the pg_ripple *resolved projection* via SPARQL.
--
-- Because CRM and ERP contacts share ex:email (via the sameAs SPARQL UPDATE in
-- ingest_contacts), this model returns one canonical row per unique email.
-- The latest_wins conflict policy on ex:name is implemented by ordering on the
-- prov:generatedAtTime annotation and picking the most-recently-asserted value.
--
-- Steps covered: Steps 3–4 outcome from the worked example.
-- Run: dbt run --select merged_contacts

{{ config(materialized='table') }}

-- One row per unique email address, with the conflict-resolved name.
--
-- The Datalog rule in setup_bidi_example (BIDI-REF-01) asserts:
--   crm_subject owl:sameAs erp_subject
-- for contacts that share ex:email.  Subjects in the owl:sameAs subject
-- position are the "non-canonical" side; excluding them leaves exactly one
-- row per email.  The surviving subject already carries the latest_wins name
-- because recompute_conflict_winners() ran after ingest.

SELECT
    trim(BOTH '<>' FROM result->>'subject')  AS subject_iri,
    btrim(result->>'email', '"')             AS email,
    btrim(result->>'name',  '"')             AS name
FROM pg_ripple.sparql($sparql$
    PREFIX ex:  <http://example.org/>
    PREFIX owl: <http://www.w3.org/2002/07/owl#>
    SELECT ?subject ?email ?name
    WHERE {
        ?subject ex:email ?email ;
                 ex:name  ?name .
        FILTER NOT EXISTS { ?subject owl:sameAs ?other }
    }
$sparql$)
ORDER BY email
