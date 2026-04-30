-- tests/assert_email_merge_deduplicates.sql
-- ─────────────────────────────────────────────────────────────────────────────
-- Singular test: verifies that the sameAs Datalog rule (merge on ex:email)
-- produces exactly one row per unique email in the resolved projection, even
-- though both CRM and ERP each ingest a contact for ada@example.com.
--
-- The test passes when this query returns 0 rows.
-- A non-zero count means the merge failed and ada@example.com appears twice.

SELECT
    email,
    COUNT(*) AS row_count
FROM {{ ref('merged_contacts') }}
GROUP BY email
HAVING COUNT(*) > 1
