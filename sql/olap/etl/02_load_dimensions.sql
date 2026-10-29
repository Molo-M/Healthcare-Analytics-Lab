/* =====================================================================
   02_load_dimensions.sql
   ETL step 2: load the dimensions from the OLTP database.

   Source: healthanalyticsdb (OLTP)   Target: healthanalyticsdw (star)

   Change handling:
   - Type 1 (overwrite): specialty, department, encounter type,
     diagnosis, procedure, patient. INSERT ... ON DUPLICATE KEY UPDATE
     inserts new natural keys and overwrites changed attributes.
   - Type 2 (keep history): provider specialty and department. A change
     closes the current provider row and inserts a new version.
     Provider name and credential are Type 1 (corrections overwrite all
     versions).

   Re-runnable: every step is an upsert, so running it again only
   applies what changed in the source since the last run.
   Order matters: specialty and department load before provider,
   because provider versions look up their keys.
   ===================================================================== */

USE healthanalyticsdw;

SET SQL_SAFE_UPDATES = 0;

-- ---------------------------------------------------------------------
-- 1. Unknown members (key -1) - inserted once, skipped afterwards
-- ---------------------------------------------------------------------
INSERT IGNORE INTO dim_specialty (specialty_key, specialty_id, specialty_name, specialty_code)
VALUES (-1, -1, 'Unknown', 'UNK');

INSERT IGNORE INTO dim_department (department_key, department_id, department_name, floor_number, bed_capacity)
VALUES (-1, -1, 'Unknown', NULL, NULL);

INSERT IGNORE INTO dim_encounter_type (encounter_type_key, encounter_type_name, is_inpatient)
VALUES (-1, 'Unknown', FALSE);

INSERT IGNORE INTO dim_diagnosis (diagnosis_key, diagnosis_id, icd10_code, icd10_description, icd10_category)
VALUES (-1, -1, 'UNK', 'Unknown', 'UNK');

INSERT IGNORE INTO dim_procedure (procedure_key, procedure_id, cpt_code, cpt_description)
VALUES (-1, -1, 'UNK', 'Unknown');

INSERT IGNORE INTO dim_patient (patient_key, patient_id, mrn, first_name, last_name, full_name,
                                gender, date_of_birth, age_group)
VALUES (-1, -1, NULL, NULL, NULL, 'Unknown', NULL, NULL, 'Unknown');

INSERT IGNORE INTO dim_provider (provider_key, provider_id, first_name, last_name, full_name, credential,
                                 specialty_key, specialty_name, department_key, department_name,
                                 effective_from, effective_to, is_current)
VALUES (-1, -1, NULL, NULL, 'Unknown', NULL, -1, 'Unknown', -1, 'Unknown',
        '1900-01-01', '9999-12-31', TRUE);

-- ---------------------------------------------------------------------
-- 2. dim_specialty (Type 1)
-- ---------------------------------------------------------------------
INSERT INTO dim_specialty (specialty_id, specialty_name, specialty_code)
SELECT * FROM (
    SELECT specialty_id,
           COALESCE(specialty_name, 'Unknown') AS specialty_name,
           specialty_code
    FROM healthanalyticsdb.specialties
) AS src
ON DUPLICATE KEY UPDATE
    specialty_name = src.specialty_name,
    specialty_code = src.specialty_code;

-- ---------------------------------------------------------------------
-- 3. dim_department (Type 1)
-- ---------------------------------------------------------------------
INSERT INTO dim_department (department_id, department_name, floor_number, bed_capacity)
SELECT * FROM (
    SELECT department_id,
           COALESCE(department_name, 'Unknown') AS department_name,
           floor     AS floor_number,
           capacity  AS bed_capacity
    FROM healthanalyticsdb.departments
) AS src
ON DUPLICATE KEY UPDATE
    department_name = src.department_name,
    floor_number    = src.floor_number,
    bed_capacity    = src.bed_capacity;

-- ---------------------------------------------------------------------
-- 4. dim_encounter_type: the known types, plus any new value that
--    appears in the source
-- ---------------------------------------------------------------------
INSERT IGNORE INTO dim_encounter_type (encounter_type_name, is_inpatient)
VALUES ('Outpatient', FALSE), ('Inpatient', TRUE), ('ER', FALSE);

INSERT IGNORE INTO dim_encounter_type (encounter_type_name, is_inpatient)
SELECT DISTINCT encounter_type, encounter_type = 'Inpatient'
FROM healthanalyticsdb.encounters
WHERE encounter_type IS NOT NULL;

-- ---------------------------------------------------------------------
-- 5. dim_diagnosis (Type 1)
-- ---------------------------------------------------------------------
INSERT INTO dim_diagnosis (diagnosis_id, icd10_code, icd10_description, icd10_category)
SELECT * FROM (
    SELECT diagnosis_id,
           COALESCE(icd10_code, 'UNK')            AS icd10_code,
           icd10_description,
           LEFT(COALESCE(icd10_code, 'UNK'), 3)   AS icd10_category
    FROM healthanalyticsdb.diagnoses
) AS src
ON DUPLICATE KEY UPDATE
    icd10_code        = src.icd10_code,
    icd10_description = src.icd10_description,
    icd10_category    = src.icd10_category;

-- ---------------------------------------------------------------------
-- 6. dim_procedure (Type 1)
-- ---------------------------------------------------------------------
INSERT INTO dim_procedure (procedure_id, cpt_code, cpt_description)
SELECT * FROM (
    SELECT procedure_id,
           COALESCE(cpt_code, 'UNK') AS cpt_code,
           cpt_description
    FROM healthanalyticsdb.procedures
) AS src
ON DUPLICATE KEY UPDATE
    cpt_code        = src.cpt_code,
    cpt_description = src.cpt_description;

-- ---------------------------------------------------------------------
-- 7. dim_patient (Type 1). age_group is the age as of this load.
-- ---------------------------------------------------------------------
INSERT INTO dim_patient (patient_id, mrn, first_name, last_name, full_name,
                         gender, date_of_birth, age_group)
SELECT * FROM (
    SELECT p.patient_id,
           p.mrn,
           p.first_name,
           p.last_name,
           CONCAT_WS(' ', p.first_name, p.last_name) AS full_name,
           p.gender,
           p.date_of_birth,
           CASE
               WHEN p.date_of_birth IS NULL                              THEN 'Unknown'
               WHEN TIMESTAMPDIFF(YEAR, p.date_of_birth, CURDATE()) < 18 THEN '0-17'
               WHEN TIMESTAMPDIFF(YEAR, p.date_of_birth, CURDATE()) < 35 THEN '18-34'
               WHEN TIMESTAMPDIFF(YEAR, p.date_of_birth, CURDATE()) < 50 THEN '35-49'
               WHEN TIMESTAMPDIFF(YEAR, p.date_of_birth, CURDATE()) < 65 THEN '50-64'
               WHEN TIMESTAMPDIFF(YEAR, p.date_of_birth, CURDATE()) < 80 THEN '65-79'
               ELSE '80+'
           END AS age_group
    FROM healthanalyticsdb.patients p
) AS src
ON DUPLICATE KEY UPDATE
    mrn           = src.mrn,
    first_name    = src.first_name,
    last_name     = src.last_name,
    full_name     = src.full_name,
    gender        = src.gender,
    date_of_birth = src.date_of_birth,
    age_group     = src.age_group;

-- ---------------------------------------------------------------------
-- 8. dim_provider (Type 2 on specialty and department)
-- ---------------------------------------------------------------------

-- 8a. Stage the providers as they are in the source today, with the
--     warehouse keys of their specialty and department
DROP TEMPORARY TABLE IF EXISTS stg_provider;
CREATE TEMPORARY TABLE stg_provider AS
SELECT p.provider_id,
       p.first_name,
       p.last_name,
       CONCAT_WS(' ', p.first_name, p.last_name) AS full_name,
       p.credential,
       COALESCE(ds.specialty_key, -1)            AS specialty_key,
       COALESCE(ds.specialty_name, 'Unknown')    AS specialty_name,
       COALESCE(dd.department_key, -1)           AS department_key,
       COALESCE(dd.department_name, 'Unknown')   AS department_name
FROM healthanalyticsdb.providers p
LEFT JOIN dim_specialty  ds ON ds.specialty_id  = p.specialty_id
LEFT JOIN dim_department dd ON dd.department_id = p.department_id;

-- 8b. Close the current version of providers whose specialty or
--     department changed (the new version starts today)
UPDATE dim_provider d
JOIN stg_provider s ON s.provider_id = d.provider_id
SET d.effective_to = CURDATE() - INTERVAL 1 DAY,
    d.is_current   = FALSE
WHERE d.is_current = TRUE
  AND (d.specialty_key <> s.specialty_key OR d.department_key <> s.department_key);

-- 8c. Type 1 attributes: overwrite name and credential on every version
UPDATE dim_provider d
JOIN stg_provider s ON s.provider_id = d.provider_id
SET d.first_name = s.first_name,
    d.last_name  = s.last_name,
    d.full_name  = s.full_name,
    d.credential = s.credential;

-- 8d. Insert a current version for every provider that has none:
--     brand-new providers start at 1900-01-01 so all their historical
--     encounters find a version; changed providers start today.
INSERT INTO dim_provider (provider_id, first_name, last_name, full_name, credential,
                          specialty_key, specialty_name, department_key, department_name,
                          effective_from, effective_to, is_current)
SELECT s.provider_id, s.first_name, s.last_name, s.full_name, s.credential,
       s.specialty_key, s.specialty_name, s.department_key, s.department_name,
       CASE WHEN EXISTS (SELECT 1 FROM dim_provider old WHERE old.provider_id = s.provider_id)
            THEN CURDATE()
            ELSE DATE('1900-01-01') END,
       DATE('9999-12-31'),
       TRUE
FROM stg_provider s
WHERE NOT EXISTS (
    SELECT 1 FROM dim_provider cur
    WHERE cur.provider_id = s.provider_id AND cur.is_current = TRUE
);

DROP TEMPORARY TABLE stg_provider;

SET SQL_SAFE_UPDATES = 1;

-- ---------------------------------------------------------------------
-- 9. Row counts (each includes the Unknown row)
-- ---------------------------------------------------------------------
SELECT 'dim_specialty'      AS dimension, COUNT(*) AS row_count FROM dim_specialty
UNION ALL SELECT 'dim_department',     COUNT(*) FROM dim_department
UNION ALL SELECT 'dim_encounter_type', COUNT(*) FROM dim_encounter_type
UNION ALL SELECT 'dim_diagnosis',      COUNT(*) FROM dim_diagnosis
UNION ALL SELECT 'dim_procedure',      COUNT(*) FROM dim_procedure
UNION ALL SELECT 'dim_patient',        COUNT(*) FROM dim_patient
UNION ALL SELECT 'dim_provider',       COUNT(*) FROM dim_provider;
