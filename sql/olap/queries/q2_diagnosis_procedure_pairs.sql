/* =====================================================================
   q2_diagnosis_procedure_pairs.sql
   Question 2: Top Diagnosis-Procedure Pairs (STAR SCHEMA, MySQL 8.0)
   Most common diagnosis-procedure combinations: ICD code, procedure
   code and encounter count.
   OLTP version: sql/oltp/queries/q2_diagnosis_procedure_pairs.sql
   ===================================================================== */

USE healthanalyticsdw;

-- ---------------------------------------------------------------------
-- 1. The query
--    The two bridges are joined on encounter_id. Both are clustered by
--    encounter_id (their primary keys start with it), so each
--    encounter's diagnoses and procedures sit next to each other on disk.
--    Pairs are counted using surrogate keys only, then labelled.
--    The ETL removed duplicate (encounter, code) rows, so COUNT(*) per
--    pair already equals the number of distinct encounters: no
--    COUNT(DISTINCT) is needed.
--    JOIN_ORDER hint: start from the smaller bridge (procedures, ~282k
--    rows) and look up each encounter's diagnoses by primary key.
--    Without it, MySQL sometimes starts from the larger diagnoses
--    bridge (~465k rows) right after a load, which is about 40% slower.
-- ---------------------------------------------------------------------
SELECT
    dd.icd10_code,
    dp.cpt_code,
    pairs.encounter_count
FROM (
    SELECT /*+ JOIN_ORDER(bp, bd) */
           bd.diagnosis_key,
           bp.procedure_key,
           COUNT(*) AS encounter_count
    FROM bridge_encounter_procedures bp
    JOIN bridge_encounter_diagnoses  bd ON bd.encounter_id = bp.encounter_id
    GROUP BY bd.diagnosis_key, bp.procedure_key
) pairs
JOIN dim_diagnosis dd ON dd.diagnosis_key = pairs.diagnosis_key
JOIN dim_procedure dp ON dp.procedure_key = pairs.procedure_key
ORDER BY pairs.encounter_count DESC, dd.icd10_code, dp.cpt_code;

-- ---------------------------------------------------------------------
-- 2. Performance measurement
-- ---------------------------------------------------------------------
EXPLAIN ANALYZE
SELECT
    dd.icd10_code,
    dp.cpt_code,
    pairs.encounter_count
FROM (
    SELECT /*+ JOIN_ORDER(bp, bd) */
           bd.diagnosis_key,
           bp.procedure_key,
           COUNT(*) AS encounter_count
    FROM bridge_encounter_procedures bp
    JOIN bridge_encounter_diagnoses  bd ON bd.encounter_id = bp.encounter_id
    GROUP BY bd.diagnosis_key, bp.procedure_key
) pairs
JOIN dim_diagnosis dd ON dd.diagnosis_key = pairs.diagnosis_key
JOIN dim_procedure dp ON dp.procedure_key = pairs.procedure_key
ORDER BY pairs.encounter_count DESC, dd.icd10_code, dp.cpt_code;
