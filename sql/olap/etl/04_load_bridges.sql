/* =====================================================================
   04_load_bridges.sql
   ETL step 4: load the bridge tables (encounter <-> diagnosis and
   encounter <-> procedure).

   Run after 03_load_fact_encounters.sql (bridge rows reference fact
   rows through encounter_id).

   Bridges are fully derived from the OLTP junction tables, so they are
   rebuilt on every run: TRUNCATE is fast and safe here because no
   other table references the bridges.

   Rules:
   - Natural keys are translated to warehouse surrogate keys; codes
     missing from the dimension map to -1 (Unknown).
   - Duplicate rows for the same encounter and code are collapsed into
     one bridge row (GROUP BY), so each (encounter, code) pair appears
     once and pair counts never double count.
   - Junction rows whose encounter is not in fact_encounters (orphans)
     are skipped by the inner join to the fact table.
   ===================================================================== */

USE healthanalyticsdw;

TRUNCATE TABLE bridge_encounter_diagnoses;
TRUNCATE TABLE bridge_encounter_procedures;

-- ---------------------------------------------------------------------
-- 1. bridge_encounter_diagnoses
--    diagnosis_sequence = the lowest sequence recorded for that code;
--    is_primary = TRUE when that sequence is 1.
-- ---------------------------------------------------------------------
INSERT INTO bridge_encounter_diagnoses (encounter_id, diagnosis_key, diagnosis_sequence, is_primary)
SELECT ed.encounter_id,
       COALESCE(dd.diagnosis_key, -1)         AS diagnosis_key,
       MIN(ed.diagnosis_sequence)             AS diagnosis_sequence,
       COALESCE(MIN(ed.diagnosis_sequence) = 1, FALSE) AS is_primary
FROM healthanalyticsdb.encounter_diagnoses ed
JOIN fact_encounters f      ON f.encounter_id  = ed.encounter_id
LEFT JOIN dim_diagnosis dd  ON dd.diagnosis_id = ed.diagnosis_id
GROUP BY ed.encounter_id, COALESCE(dd.diagnosis_key, -1);

-- ---------------------------------------------------------------------
-- 2. bridge_encounter_procedures
--    procedure_quantity = how many times the procedure was recorded;
--    first_procedure_date_key = the earliest date it was performed.
-- ---------------------------------------------------------------------
INSERT INTO bridge_encounter_procedures (encounter_id, procedure_key, procedure_quantity, first_procedure_date_key)
SELECT agg.encounter_id,
       agg.procedure_key,
       agg.procedure_quantity,
       COALESCE(dt.date_key, -1)
FROM (
    SELECT ep.encounter_id,
           COALESCE(dp.procedure_key, -1)  AS procedure_key,
           COUNT(*)                        AS procedure_quantity,
           MIN(ep.procedure_date)          AS first_procedure_date
    FROM healthanalyticsdb.encounter_procedures ep
    JOIN fact_encounters f      ON f.encounter_id  = ep.encounter_id
    LEFT JOIN dim_procedure dp  ON dp.procedure_id = ep.procedure_id
    GROUP BY ep.encounter_id, COALESCE(dp.procedure_key, -1)
) agg
LEFT JOIN dim_date dt ON dt.full_date = agg.first_procedure_date;

ANALYZE TABLE bridge_encounter_diagnoses, bridge_encounter_procedures;

SELECT 'bridge_encounter_diagnoses'  AS bridge, COUNT(*) AS row_count FROM bridge_encounter_diagnoses
UNION ALL
SELECT 'bridge_encounter_procedures',          COUNT(*)              FROM bridge_encounter_procedures;
