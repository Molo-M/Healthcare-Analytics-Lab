/* =====================================================================
   q1_monthly_encounters.sql
   Question 1: Monthly Encounters by Specialty (STAR SCHEMA, MySQL 8.0)
   For each month and specialty: total encounters and unique patients
   by encounter type.
   OLTP version: sql/oltp/queries/q1_monthly_encounters.sql
   ===================================================================== */

USE healthanalyticsdw;

-- ---------------------------------------------------------------------
-- 1. The query
--    Aggregate the fact table first, using only its integer keys (all
--    read from one covering index), then join the small dimensions to
--    the few hundred aggregated rows to get readable labels.
--    The month comes from the YYYYMMDD date key: date_key DIV 100 =
--    YYYYMM, so no DATE_FORMAT and no join is needed before grouping.
--    YYYYMM * 100 + 1 is the date key of the first day of that month.
-- ---------------------------------------------------------------------
SELECT
    d.month_start_date     AS encounter_month,
    s.specialty_name,
    t.encounter_type_name  AS encounter_type,
    agg.total_encounters,
    agg.unique_patients
FROM (
    SELECT f.encounter_date_key DIV 100       AS month_key,
           f.specialty_key,
           f.encounter_type_key,
           COUNT(*)                           AS total_encounters,
           COUNT(DISTINCT f.patient_key)      AS unique_patients
    FROM fact_encounters f
    GROUP BY month_key, f.specialty_key, f.encounter_type_key
) agg
LEFT JOIN dim_date      d ON d.date_key           = agg.month_key * 100 + 1
JOIN dim_specialty      s ON s.specialty_key      = agg.specialty_key
JOIN dim_encounter_type t ON t.encounter_type_key = agg.encounter_type_key
ORDER BY encounter_month, s.specialty_name, encounter_type;

-- ---------------------------------------------------------------------
-- 2. Performance measurement
-- ---------------------------------------------------------------------
EXPLAIN ANALYZE
SELECT
    d.month_start_date     AS encounter_month,
    s.specialty_name,
    t.encounter_type_name  AS encounter_type,
    agg.total_encounters,
    agg.unique_patients
FROM (
    SELECT f.encounter_date_key DIV 100       AS month_key,
           f.specialty_key,
           f.encounter_type_key,
           COUNT(*)                           AS total_encounters,
           COUNT(DISTINCT f.patient_key)      AS unique_patients
    FROM fact_encounters f
    GROUP BY month_key, f.specialty_key, f.encounter_type_key
) agg
LEFT JOIN dim_date      d ON d.date_key           = agg.month_key * 100 + 1
JOIN dim_specialty      s ON s.specialty_key      = agg.specialty_key
JOIN dim_encounter_type t ON t.encounter_type_key = agg.encounter_type_key
ORDER BY encounter_month, s.specialty_name, encounter_type;
