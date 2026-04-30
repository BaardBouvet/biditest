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

WITH raw_contacts AS (
    -- Query all contacts with their source timestamps.
    -- Uses ex:lastModified (ingested from seed data) instead of RDF-star
    -- prov:generatedAtTime annotations, which exhibit cross-product binding
    -- in pg-ripple 0.78.0 when used in subject position.
    SELECT
        btrim(result->>'email',   '"')                 AS email,
        btrim(result->>'name',    '"')                 AS name,
        trim(BOTH '<>' FROM result->>'subject')        AS subject_iri,
        -- Parse timestamp literal: "2026-04-29 11:30:00"
        to_timestamp(
            btrim(result->>'ts', '"'),
            'YYYY-MM-DD HH24:MI:SS'
        )                                              AS name_ts
    FROM pg_ripple.sparql($sparql$
        PREFIX ex: <http://example.org/>
        SELECT ?subject ?email ?name ?ts
        WHERE {
            ?subject ex:email ?email ;
                     ex:name  ?name ;
                     ex:lastModified ?ts .
        }
    $sparql$)
),

same_as_links AS (
    -- Retrieve asserted owl:sameAs pairs (inserted by ingest_contacts Step 2).
    SELECT
        trim(BOTH '<>' FROM result->>'a') AS a,
        trim(BOTH '<>' FROM result->>'b') AS b
    FROM pg_ripple.sparql($sparql$
        PREFIX owl: <http://www.w3.org/2002/07/owl#>
        SELECT ?a ?b WHERE { ?a owl:sameAs ?b . }
    $sparql$)
),

-- Map every subject to its canonical representative: the lexicographically
-- smallest IRI in its owl:sameAs equivalence class.
canonical_map AS (
    SELECT
        c.subject_iri,
        LEAST(
            c.subject_iri,
            sa_a.b,   -- partner when this subject is the "a" side
            sa_b.a    -- partner when this subject is the "b" side
        ) AS canonical
    FROM raw_contacts c
    LEFT JOIN same_as_links sa_a ON sa_a.a = c.subject_iri
    LEFT JOIN same_as_links sa_b ON sa_b.b = c.subject_iri
),

-- For each canonical entity, pick the row with the latest name_ts (latest_wins).
ranked AS (
    SELECT
        cm.canonical                                        AS subject_iri,
        c.email,
        c.name,
        ROW_NUMBER() OVER (
            PARTITION BY cm.canonical
            ORDER BY c.name_ts DESC NULLS LAST
        )                                                   AS rn
    FROM raw_contacts  c
    JOIN canonical_map cm ON cm.subject_iri = c.subject_iri
)

SELECT subject_iri, email, name
FROM   ranked
WHERE  rn = 1
ORDER BY email
