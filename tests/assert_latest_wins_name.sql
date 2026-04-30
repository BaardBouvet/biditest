-- tests/assert_latest_wins_name.sql
-- ─────────────────────────────────────────────────────────────────────────────
-- Singular test: verifies that the latest_wins conflict policy on ex:name
-- correctly returns the ERP-side value ("Ada Lovelace") for ada@example.com,
-- not the earlier CRM value ("Ada L.").
--
-- The test passes when this query returns 0 rows.
-- A non-zero row count means the resolved projection returned the wrong winner.

SELECT
    email,
    name AS actual_name,
    'Ada Lovelace' AS expected_name
FROM {{ ref('merged_contacts') }}
WHERE
    email = 'ada@example.com'
    -- The ERP contact has lastModified = 2026-04-29T11:30Z vs CRM's 10:00Z.
    -- latest_wins must pick the ERP value.
    AND name <> 'Ada Lovelace'
