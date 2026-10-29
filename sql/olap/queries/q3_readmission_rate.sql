/* =====================================================================
   q3_readmission_rate.sql
   Question 3: 30-Day Readmission Rate (STAR SCHEMA, MySQL 8.0)
   Readmission rate by specialty (inpatient discharge, then any return
   within 30 days).
   OLTP version: sql/oltp/queries/q3_readmission_rate.sql
   ===================================================================== */

USE healthanalyticsdw;

-- ---------------------------------------------------------------------
-- 1. The query
--    No self-join: the ETL computed readmitted_within_30d once per
--    inpatient stay. The query filters inpatient rows through the
--    encounter type dimension and sums the flag per specialty.
-- ---------------------------------------------------------------------
SELECT
    s.specialty_name,
    agg.inpatient_discharges,
    agg.readmissions,
    ROUND(100 * agg.readmissions / agg.inpatient_discharges, 2) AS readmission_rate_pct
FROM (
    SELECT f.specialty_key,
           COUNT(*)                     AS inpatient_discharges,
           SUM(f.readmitted_within_30d) AS readmissions
    FROM fact_encounters f
    JOIN dim_encounter_type t ON t.encounter_type_key = f.encounter_type_key
    WHERE t.is_inpatient = TRUE
    GROUP BY f.specialty_key
) agg
JOIN dim_specialty s ON s.specialty_key = agg.specialty_key
ORDER BY readmission_rate_pct DESC;

-- ---------------------------------------------------------------------
-- 2. Performance measurement
-- ---------------------------------------------------------------------
EXPLAIN ANALYZE
SELECT
    s.specialty_name,
    agg.inpatient_discharges,
    agg.readmissions,
    ROUND(100 * agg.readmissions / agg.inpatient_discharges, 2) AS readmission_rate_pct
FROM (
    SELECT f.specialty_key,
           COUNT(*)                     AS inpatient_discharges,
           SUM(f.readmitted_within_30d) AS readmissions
    FROM fact_encounters f
    JOIN dim_encounter_type t ON t.encounter_type_key = f.encounter_type_key
    WHERE t.is_inpatient = TRUE
    GROUP BY f.specialty_key
) agg
JOIN dim_specialty s ON s.specialty_key = agg.specialty_key
ORDER BY readmission_rate_pct DESC;
