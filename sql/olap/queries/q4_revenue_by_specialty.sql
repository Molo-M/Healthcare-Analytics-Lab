/* =====================================================================
   q4_revenue_by_specialty.sql
   Question 4: Revenue by Specialty & Month (STAR SCHEMA, MySQL 8.0)
   Total allowed amounts by specialty and month (month of service).
   OLTP version: sql/oltp/queries/q4_revenue_by_specialty.sql
   ===================================================================== */

USE healthanalyticsdw;

-- ---------------------------------------------------------------------
-- 1. The query
--    No billing join: total_allowed_amount was summed per encounter by
--    the ETL, and specialty_key is stored on the fact row, so the
--    billing -> encounters -> providers -> specialties chain disappears.
--    claim_count > 0 keeps only billed encounters, matching the OLTP
--    query, which starts FROM billing.
-- ---------------------------------------------------------------------
SELECT
    d.month_start_date  AS encounter_month,
    s.specialty_name,
    agg.total_allowed
FROM (
    SELECT f.encounter_date_key DIV 100   AS month_key,
           f.specialty_key,
           SUM(f.total_allowed_amount)    AS total_allowed
    FROM fact_encounters f
    WHERE f.claim_count > 0
    GROUP BY month_key, f.specialty_key
) agg
LEFT JOIN dim_date d ON d.date_key      = agg.month_key * 100 + 1
JOIN dim_specialty s ON s.specialty_key = agg.specialty_key
ORDER BY encounter_month, agg.total_allowed DESC;

-- ---------------------------------------------------------------------
-- 2. Performance measurement
-- ---------------------------------------------------------------------
EXPLAIN ANALYZE
SELECT
    d.month_start_date  AS encounter_month,
    s.specialty_name,
    agg.total_allowed
FROM (
    SELECT f.encounter_date_key DIV 100   AS month_key,
           f.specialty_key,
           SUM(f.total_allowed_amount)    AS total_allowed
    FROM fact_encounters f
    WHERE f.claim_count > 0
    GROUP BY month_key, f.specialty_key
) agg
LEFT JOIN dim_date d ON d.date_key      = agg.month_key * 100 + 1
JOIN dim_specialty s ON s.specialty_key = agg.specialty_key
ORDER BY encounter_month, agg.total_allowed DESC;
