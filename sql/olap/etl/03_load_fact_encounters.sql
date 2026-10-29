/* =====================================================================
   03_load_fact_encounters.sql
   ETL step 3: load fact_encounters (grain: one row per encounter).

   Run after 01_load_dim_date.sql and 02_load_dimensions.sql.

   For every OLTP encounter this script:
   1. Pre-aggregates its diagnoses, procedures and billing into one row
      per encounter (staging tables).
   2. Computes the 30-day readmission flag once (the self-join that
      Question 3 ran on every query now runs only here).
   3. Looks up every dimension key; anything missing gets key -1
      (Unknown) so no encounter is dropped.
   4. Upserts the fact row: new encounters are inserted, existing ones
      are updated. Re-running therefore picks up late-arriving data,
      such as a claim billed weeks after the visit.

   This version processes all encounters (initial / full load).
   etl_design.txt describes the incremental version.
   ===================================================================== */

USE healthanalyticsdw;

-- ---------------------------------------------------------------------
-- 1. Pre-aggregate the many-side tables to one row per encounter
--    COUNT(DISTINCT ...) so the counts match the deduplicated bridges.
-- ---------------------------------------------------------------------
DROP TEMPORARY TABLE IF EXISTS stg_dx_counts;
CREATE TEMPORARY TABLE stg_dx_counts (PRIMARY KEY (encounter_id))
SELECT encounter_id, COUNT(DISTINCT diagnosis_id) AS diagnosis_count
FROM healthanalyticsdb.encounter_diagnoses
WHERE encounter_id IS NOT NULL
GROUP BY encounter_id;

DROP TEMPORARY TABLE IF EXISTS stg_px_counts;
CREATE TEMPORARY TABLE stg_px_counts (PRIMARY KEY (encounter_id))
SELECT encounter_id, COUNT(DISTINCT procedure_id) AS procedure_count
FROM healthanalyticsdb.encounter_procedures
WHERE encounter_id IS NOT NULL
GROUP BY encounter_id;

DROP TEMPORARY TABLE IF EXISTS stg_billing;
CREATE TEMPORARY TABLE stg_billing (PRIMARY KEY (encounter_id))
SELECT encounter_id,
       COUNT(*)                           AS claim_count,
       COALESCE(SUM(claim_amount), 0)     AS total_claim_amount,
       COALESCE(SUM(allowed_amount), 0)   AS total_allowed_amount
FROM healthanalyticsdb.billing
WHERE encounter_id IS NOT NULL
GROUP BY encounter_id;

-- ---------------------------------------------------------------------
-- 2. Readmissions: for each inpatient stay, the first encounter of the
--    same patient that starts after the discharge. The stay counts as
--    readmitted if that encounter starts within 30 days (the same rule
--    as the OLTP Question 3 query).
-- ---------------------------------------------------------------------
DROP TEMPORARY TABLE IF EXISTS stg_next_encounter;
CREATE TEMPORARY TABLE stg_next_encounter (PRIMARY KEY (encounter_id))
SELECT idx.encounter_id,
       MIN(nxt.encounter_date) AS next_encounter_date
FROM healthanalyticsdb.encounters idx
JOIN healthanalyticsdb.encounters nxt
  ON nxt.patient_id     = idx.patient_id
 AND nxt.encounter_date > idx.discharge_date
WHERE idx.encounter_type = 'Inpatient'
GROUP BY idx.encounter_id;

-- ---------------------------------------------------------------------
-- 3 + 4. Look up dimension keys and upsert the fact rows
-- ---------------------------------------------------------------------
INSERT INTO fact_encounters (
    encounter_id,
    encounter_date_key, discharge_date_key, patient_key, provider_key,
    specialty_key, department_key, encounter_type_key,
    encounter_count, diagnosis_count, procedure_count,
    claim_count, total_claim_amount, total_allowed_amount,
    length_of_stay_hours, readmitted_within_30d, days_to_next_encounter,
    patient_age_at_encounter
)
SELECT * FROM (
    SELECT
        e.encounter_id,

        -- Dimension keys: -1 (Unknown) when the source value is missing
        -- or has no matching dimension row
        COALESCE(d_enc.date_key, -1)            AS encounter_date_key,
        COALESCE(d_dis.date_key, -1)            AS discharge_date_key,
        COALESCE(pat.patient_key, -1)           AS patient_key,
        COALESCE(prv.provider_key, -1)          AS provider_key,
        COALESCE(prv.specialty_key, -1)         AS specialty_key,   -- provider's specialty at encounter time
        COALESCE(dep.department_key, -1)        AS department_key,
        COALESCE(et.encounter_type_key, -1)     AS encounter_type_key,

        -- Pre-aggregated measures (0 when the encounter has none)
        1                                       AS encounter_count,
        COALESCE(dx.diagnosis_count, 0)         AS diagnosis_count,
        COALESCE(px.procedure_count, 0)         AS procedure_count,
        COALESCE(b.claim_count, 0)              AS claim_count,
        COALESCE(b.total_claim_amount, 0)       AS total_claim_amount,
        COALESCE(b.total_allowed_amount, 0)     AS total_allowed_amount,
        ROUND(TIMESTAMPDIFF(MINUTE, e.encounter_date, e.discharge_date) / 60, 2)
                                                AS length_of_stay_hours,

        -- Readmission flag (inpatient stays only)
        CASE WHEN e.encounter_type = 'Inpatient'
              AND nx.next_encounter_date <= e.discharge_date + INTERVAL 30 DAY
             THEN 1 ELSE 0 END                  AS readmitted_within_30d,
        CASE WHEN e.encounter_type = 'Inpatient'
             THEN DATEDIFF(nx.next_encounter_date, e.discharge_date) END
                                                AS days_to_next_encounter,

        TIMESTAMPDIFF(YEAR, pat.date_of_birth, e.encounter_date)
                                                AS patient_age_at_encounter
    FROM healthanalyticsdb.encounters e
    LEFT JOIN dim_date d_enc        ON d_enc.full_date = DATE(e.encounter_date)
    LEFT JOIN dim_date d_dis        ON d_dis.full_date = DATE(e.discharge_date)
    LEFT JOIN dim_patient pat       ON pat.patient_id  = e.patient_id
    -- SCD Type 2 lookup: the provider version valid on the encounter date
    LEFT JOIN dim_provider prv      ON prv.provider_id = e.provider_id
                                   AND DATE(e.encounter_date) BETWEEN prv.effective_from AND prv.effective_to
    LEFT JOIN dim_department dep    ON dep.department_id = e.department_id
    LEFT JOIN dim_encounter_type et ON et.encounter_type_name = e.encounter_type
    LEFT JOIN stg_dx_counts dx      ON dx.encounter_id = e.encounter_id
    LEFT JOIN stg_px_counts px      ON px.encounter_id = e.encounter_id
    LEFT JOIN stg_billing b         ON b.encounter_id  = e.encounter_id
    LEFT JOIN stg_next_encounter nx ON nx.encounter_id = e.encounter_id
) AS src
ON DUPLICATE KEY UPDATE
    encounter_date_key       = src.encounter_date_key,
    discharge_date_key       = src.discharge_date_key,
    patient_key              = src.patient_key,
    provider_key             = src.provider_key,
    specialty_key            = src.specialty_key,
    department_key           = src.department_key,
    encounter_type_key       = src.encounter_type_key,
    diagnosis_count          = src.diagnosis_count,
    procedure_count          = src.procedure_count,
    claim_count              = src.claim_count,
    total_claim_amount       = src.total_claim_amount,
    total_allowed_amount     = src.total_allowed_amount,
    length_of_stay_hours     = src.length_of_stay_hours,
    readmitted_within_30d    = src.readmitted_within_30d,
    days_to_next_encounter   = src.days_to_next_encounter,
    patient_age_at_encounter = src.patient_age_at_encounter;

DROP TEMPORARY TABLE stg_dx_counts;
DROP TEMPORARY TABLE stg_px_counts;
DROP TEMPORARY TABLE stg_billing;
DROP TEMPORARY TABLE stg_next_encounter;

ANALYZE TABLE fact_encounters;

-- ---------------------------------------------------------------------
-- 5. Load summary: rows loaded, and how many used an Unknown key
--    (non-zero values point to data-quality problems in the source)
-- ---------------------------------------------------------------------
SELECT COUNT(*)                                   AS fact_rows,
       SUM(encounter_date_key = -1)               AS unknown_encounter_date,
       SUM(patient_key = -1)                      AS unknown_patient,
       SUM(provider_key = -1)                     AS unknown_provider,
       SUM(specialty_key = -1)                    AS unknown_specialty,
       SUM(department_key = -1)                   AS unknown_department,
       SUM(encounter_type_key = -1)               AS unknown_encounter_type,
       SUM(readmitted_within_30d)                 AS readmissions_flagged
FROM fact_encounters;
