-- Runs automatically when the pg-ripple container first starts.
-- The pg_ripple extension is already installed in the image; this script
-- enables it in the biditest database and creates supporting schemas.

CREATE EXTENSION IF NOT EXISTS pg_ripple;

-- Schema for the pg-trickle inbox helper tables used in BIDI-INBOX-01.
-- The schema is created here so the bidi setup macro can install the inbox
-- trigger without extra DDL in the macro itself.
CREATE SCHEMA IF NOT EXISTS pg_ripple_inbox;

-- Grant the dbt user access to both the pg_ripple and public schemas.
GRANT USAGE ON SCHEMA pg_ripple     TO postgres;
GRANT USAGE ON SCHEMA pg_ripple_inbox TO postgres;
GRANT ALL   ON SCHEMA public        TO postgres;
