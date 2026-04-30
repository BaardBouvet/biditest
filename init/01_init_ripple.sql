-- Runs automatically when the pg-ripple container first starts.
-- The pg_ripple extension is already installed in the image; this script
-- enables it in the biditest database and creates supporting schemas.
-- Application-layer setup (mappings, rules, policies) is in the setup_bidi_example macro.

CREATE EXTENSION IF NOT EXISTS pg_ripple;

-- Make rule_graph_scope = 'all' the permanent default for this database so
-- the Datalog engine sees triples across all named graphs on every connection.
ALTER DATABASE biditest SET pg_ripple.rule_graph_scope = 'all';

-- Schema for the pg-trickle inbox helper tables (used in Step 6).
CREATE SCHEMA IF NOT EXISTS pg_ripple_inbox;

-- Grant the dbt user access to both the pg_ripple and public schemas.
GRANT USAGE ON SCHEMA pg_ripple     TO postgres;
GRANT USAGE ON SCHEMA pg_ripple_inbox TO postgres;
GRANT ALL   ON SCHEMA public        TO postgres;
