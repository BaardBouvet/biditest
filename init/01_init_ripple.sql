-- Runs automatically when the pg-ripple container first starts.
-- The pg_ripple extension is already installed in the image; this script
-- enables it in the biditest database and creates supporting schemas.
-- Application-layer setup (mappings, rules, policies) is in the setup_bidi_example macro.

CREATE EXTENSION IF NOT EXISTS pg_ripple;

-- pg_ripple must be in shared_preload_libraries so its GUCs (including
-- rule_graph_scope) are registered at server startup. ALTER SYSTEM writes to
-- postgresql.auto.conf; the server must be restarted once after first init.
ALTER SYSTEM SET shared_preload_libraries = 'pg_ripple';

-- Make rule_graph_scope = 'all' the permanent default for this database so
-- the Datalog engine sees triples across all named graphs on every connection.
-- NOTE: this only takes effect after pg_ripple is in shared_preload_libraries
-- (i.e. after the one-time restart triggered by the line above).
ALTER DATABASE biditest SET pg_ripple.rule_graph_scope = 'all';

-- Schema for the pg-trickle inbox helper tables (used in Step 6).
CREATE SCHEMA IF NOT EXISTS pg_ripple_inbox;

-- Grant the dbt user access to both the pg_ripple and public schemas.
GRANT USAGE ON SCHEMA pg_ripple     TO postgres;
GRANT USAGE ON SCHEMA pg_ripple_inbox TO postgres;
GRANT ALL   ON SCHEMA public        TO postgres;
