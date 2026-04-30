-- models/marts/merged_contacts.sql
-- ─────────────────────────────────────────────────────────────────────────────
-- Queries the pg_ripple *resolved projection* via SPARQL.
--
-- Because CRM and ERP contacts share ex:email (via the sameAs Datalog rule),
-- this query returns one canonical row per unique email regardless of which
-- source system originated each field.  The latest_wins conflict policy on
-- ex:name guarantees the most-recently-asserted name value wins.
--
-- Steps covered: Steps 3–4 outcome from the worked example.
-- Run: dbt run --select merged_contacts

{{ config(materialized='table') }}

SELECT
    sparql.subject    AS subject_iri,
    sparql.email      AS email,
    sparql.name       AS name
FROM pg_ripple.sparql($sparql$
    PREFIX ex: <http://example.org/>

    SELECT ?subject ?email ?name
    WHERE {
        ?subject ex:email ?email ;
                 ex:name  ?name .
    }
    ORDER BY ?email
$sparql$) AS sparql(subject TEXT, email TEXT, name TEXT)
