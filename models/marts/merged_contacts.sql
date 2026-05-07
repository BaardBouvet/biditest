-- models/marts/merged_contacts.sql
-- ─────────────────────────────────────────────────────────────────────────────
-- Queries the pg_ripple *resolved projection* via SPARQL.
--
-- The Datalog rule (BIDI-REF-01) asserts owl:sameAs between contacts that
-- share ex:email across source graphs.  pg_ripple.rule_graph_scope = 'all'
-- is set as a database default in init/01_init_ripple.sql so the engine
-- sees triples across all named graphs on every connection.
--
-- The latest_wins conflict policy on ex:name picks the most-recently-asserted
-- value across both source graphs.
--
-- Steps covered: Steps 3–4 outcome from the worked example.
-- Run: dbt run --select merged_contacts

{{ config(materialized='view') }}

-- One row per unique email address, with the conflict-resolved name.
--
-- The Datalog rule asserts owl:sameAs between the two subjects that share an
-- email.  Subjects appearing in the owl:sameAs object position are the
-- non-canonical side; excluding them with FILTER NOT EXISTS leaves exactly
-- one row per email.  The surviving subject carries the latest_wins name.

-- One row per unique email address, with the conflict-resolved name.
--
-- The Datalog rule asserts owl:sameAs between the two subjects that share an
-- email.  We deduplicate by grouping on email and picking one canonical subject.
-- The latest_wins conflict policy on ex:name picks the most-recently-asserted
-- value (by ex:lastModified timestamp) for each email group.

WITH all_contacts AS (
    SELECT
        trim(BOTH '<>' FROM result->>'subject')    AS subject_iri,
        btrim(result->>'email', '"')               AS email,
        btrim(result->>'name', '"')                AS name,
        btrim(result->>'lastModified', '"')::timestamp AS last_modified_at
    FROM pg_ripple.sparql($sparql$
        PREFIX ex:  <http://example.org/>
        SELECT ?subject ?email ?name ?lastModified
        WHERE {
            ?subject ex:email ?email ;
                     ex:name  ?name ;
                     ex:lastModified ?lastModified .
        }
    $sparql$)
),
-- Apply latest_wins: for each email, pick the row with the latest timestamp
-- If there's a tie, pick the lexicographically first subject as tiebreaker
deduped_and_resolved AS (
    SELECT DISTINCT ON (email)
        subject_iri,
        email,
        name
    FROM all_contacts
    ORDER BY email, last_modified_at DESC, subject_iri ASC
)
SELECT
    subject_iri,
    email,
    name
FROM deduped_and_resolved
ORDER BY email
