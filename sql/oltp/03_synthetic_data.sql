/* =====================================================================
   03_synthetic_data.sql
   Healthcare Analytics Lab - synthetic data for benchmarking (MySQL 8.0)

   Run AFTER 01_create_schema.sql and 02_sample_data.sql.
   Adds realistic volumes ON TOP of the sample data, so the original
   sample rows (and their IDs) are kept:

       specialties          3  ->        10
       departments          3  ->        10
       providers            3  ->       100
       patients             3  ->    20,003
       diagnoses            3  ->       200
       procedures           3  ->       100
       encounters           4  ->   200,004
       encounter_diagnoses  ~6 ->  ~465,000
       encounter_procedures ~4 ->  ~282,000
       billing              2  ->  ~190,000

   Deterministic: values come from CRC32 hashes of each row number, not
   RAND(), so every run (on any machine) produces identical data and
   benchmark results are reproducible.

   Re-runnable: synthetic rows (IDs above the sample-data ranges) are
   deleted first, then regenerated.
   Typical run time: 1-3 minutes.
   ===================================================================== */

USE healthanalyticsdb;

SET SQL_SAFE_UPDATES = 0;

-- ---------------------------------------------------------------------
-- 0. Remove previously generated synthetic rows (children first)
--    Sample data uses: billing 14001-14002, encounter_procedures
--    9001-9004, encounter_diagnoses 8001-8006, encounters 7001-7004,
--    patients 1001-1003, providers 101-103, lookups 1-3 / 3001-3003 /
--    4001-4003. Everything above those ranges is synthetic.
-- ---------------------------------------------------------------------
DELETE FROM billing              WHERE billing_id             >= 100000;
DELETE FROM encounter_procedures WHERE encounter_procedure_id >= 70000;
DELETE FROM encounter_diagnoses  WHERE encounter_diagnosis_id >= 70000;
DELETE FROM encounters           WHERE encounter_id           >  7004;
DELETE FROM providers            WHERE provider_id            >  103;
DELETE FROM patients             WHERE patient_id             >  1003;
DELETE FROM diagnoses            WHERE diagnosis_id           >  3003;
DELETE FROM procedures           WHERE procedure_id           >  4003;
DELETE FROM departments          WHERE department_id          >  3;
DELETE FROM specialties          WHERE specialty_id           >  3;

-- ---------------------------------------------------------------------
-- 1. Helper table of consecutive numbers 1..200,000
--    (built by cross-joining the digits 0-9 with themselves)
-- ---------------------------------------------------------------------
DROP TABLE IF EXISTS seq_numbers;
CREATE TABLE seq_numbers (n INT PRIMARY KEY);

INSERT INTO seq_numbers (n)
WITH digits AS (
    SELECT 0 AS d UNION ALL SELECT 1 UNION ALL SELECT 2 UNION ALL SELECT 3
    UNION ALL SELECT 4 UNION ALL SELECT 5 UNION ALL SELECT 6
    UNION ALL SELECT 7 UNION ALL SELECT 8 UNION ALL SELECT 9
)
SELECT n FROM (
    SELECT a.d + 10*b.d + 100*c.d + 1000*d.d + 10000*e.d + 100000*f.d AS n
    FROM digits a, digits b, digits c, digits d, digits e, digits f
) x
WHERE n BETWEEN 1 AND 200000;

-- ---------------------------------------------------------------------
-- 2. Lookup tables
-- ---------------------------------------------------------------------
INSERT INTO specialties (specialty_id, specialty_name, specialty_code) VALUES
    (4,  'Orthopedics',      'ORTH'),
    (5,  'Neurology',        'NEUR'),
    (6,  'Oncology',         'ONC'),
    (7,  'Pulmonology',      'PULM'),
    (8,  'Gastroenterology', 'GI'),
    (9,  'Pediatrics',       'PEDS'),
    (10, 'General Surgery',  'GSUR');

INSERT INTO departments (department_id, department_name, floor, capacity) VALUES
    (4,  'Orthopedics Unit',      4, 25),
    (5,  'Neurology Unit',        5, 20),
    (6,  'Oncology Unit',         6, 30),
    (7,  'Pulmonology Unit',      4, 15),
    (8,  'Gastroenterology Unit', 5, 15),
    (9,  'Pediatrics Unit',       2, 35),
    (10, 'Surgical Unit',         6, 40);

-- 197 synthetic ICD-10-style codes (letter + 2 digits + decimal)
INSERT INTO diagnoses (diagnosis_id, icd10_code, icd10_description)
SELECT 3000 + n,
       CONCAT(ELT(1 + (3000 + n) % 10, 'A','B','C','D','E','F','G','J','K','M'),
              LPAD(((3000 + n) DIV 10) % 100, 2, '0'), '.', (3000 + n) % 10),
       CONCAT('Synthetic diagnosis ', 3000 + n)
FROM seq_numbers WHERE n BETWEEN 4 AND 200;

-- 97 synthetic CPT-style codes (5 digits, all distinct)
INSERT INTO procedures (procedure_id, cpt_code, cpt_description)
SELECT 4000 + n,
       CAST(10000 + n * 97 AS CHAR),
       CONCAT('Synthetic procedure ', 4000 + n)
FROM seq_numbers WHERE n BETWEEN 4 AND 100;

-- ---------------------------------------------------------------------
-- 3. Providers 104-200
--    Specialty follows the same pattern as the sample data
--    (101 -> 1, 102 -> 2, 103 -> 3, ...), cycling through the 10
--    specialties. Each provider works in the matching department.
-- ---------------------------------------------------------------------
INSERT INTO providers (provider_id, first_name, last_name, credential, specialty_id, department_id)
SELECT 100 + n,
       ELT(1 + CRC32(CONCAT(n, '-fn')) % 10,
           'Amina','David','Grace','Samuel','Laura','Kwame','Maria','Peter','Aisha','Daniel'),
       ELT(1 + CRC32(CONCAT(n, '-ln')) % 10,
           'Mensah','Okafor','Nguyen','Patel','Garcia','Uwimana','Kim','Brown','Haddad','Silva'),
       ELT(1 + CRC32(CONCAT(n, '-cr')) % 10, 'MD','MD','MD','MD','MD','MD','MD','DO','DO','NP'),
       1 + (n - 1) % 10,
       1 + (n - 1) % 10
FROM seq_numbers WHERE n BETWEEN 4 AND 100;

-- ---------------------------------------------------------------------
-- 4. Patients 1004-21003
-- ---------------------------------------------------------------------
INSERT INTO patients (patient_id, first_name, last_name, date_of_birth, gender, mrn)
SELECT 1000 + n,
       ELT(1 + CRC32(CONCAT(n, '-pfn')) % 12,
           'Alice','Brian','Chloe','Eric','Fatima','George','Hannah','Ivan','Joy','Kevin','Lina','Moses'),
       ELT(1 + CRC32(CONCAT(n, '-pln')) % 12,
           'Adams','Baker','Clark','Diallo','Evans','Fischer','Gomez','Hughes','Ito','Jones','Kariuki','Lopez'),
       DATE_ADD('1935-01-01', INTERVAL CRC32(CONCAT(n, '-dob')) % 31000 DAY),
       IF(CRC32(CONCAT(n, '-sex')) % 2 = 0, 'F', 'M'),
       CONCAT('MRN', LPAD(1000 + n, 6, '0'))
FROM seq_numbers WHERE n BETWEEN 4 AND 20003;

-- ---------------------------------------------------------------------
-- 5. Encounters 7005-207004 (200,000 rows, 2023-01-01 to 2024-12-31)
--    Emergency providers see ER encounters; other providers see
--    roughly 75% Outpatient, 18% Inpatient, 7% ER.
--    Department = the treating provider's department.
-- ---------------------------------------------------------------------
INSERT INTO encounters (encounter_id, patient_id, provider_id, encounter_type,
                        encounter_date, discharge_date, department_id)
SELECT g.encounter_id, g.patient_id, g.provider_id, g.encounter_type, g.encounter_date,
       CASE g.encounter_type
           WHEN 'Outpatient' THEN g.encounter_date + INTERVAL (30 + g.h % 150) MINUTE
           WHEN 'ER'         THEN g.encounter_date + INTERVAL (120 + g.h % 600) MINUTE
           ELSE                   g.encounter_date + INTERVAL (1 + g.h % 9) DAY
                                                   + INTERVAL (g.h % 600) MINUTE
       END,
       pr.department_id
FROM (
    SELECT 7004 + s.n                                   AS encounter_id,
           1001 + CRC32(CONCAT(s.n, '-pat')) % 20003    AS patient_id,
           101  + CRC32(CONCAT(s.n, '-prv')) % 100     AS provider_id,
           CASE
               WHEN (CRC32(CONCAT(s.n, '-prv')) % 100) % 10 = 2 THEN 'ER'
               WHEN CRC32(CONCAT(s.n, '-typ')) % 100 < 75       THEN 'Outpatient'
               WHEN CRC32(CONCAT(s.n, '-typ')) % 100 < 93       THEN 'Inpatient'
               ELSE                                                  'ER'
           END                                          AS encounter_type,
           TIMESTAMP('2023-01-01 00:00:00')
               + INTERVAL (CRC32(CONCAT(s.n, '-day')) % 731) DAY
               + INTERVAL (420 + CRC32(CONCAT(s.n, '-min')) % 720) MINUTE AS encounter_date,
           CRC32(CONCAT(s.n, '-dur'))                   AS h
    FROM seq_numbers s
    WHERE s.n BETWEEN 1 AND 200000
) g
JOIN providers pr ON pr.provider_id = g.provider_id;

-- ---------------------------------------------------------------------
-- 6. Encounter diagnoses
--    Inpatient: 2-6 diagnoses; others: 1-3. The first diagnosis is
--    skewed toward common codes (POW(x, 2)), so some combinations are
--    much more frequent than others, as in real data. Diagnoses within
--    one encounter are always distinct.
--    ID = encounter_id * 10 + sequence (never collides with sample IDs).
-- ---------------------------------------------------------------------
INSERT INTO encounter_diagnoses (encounter_diagnosis_id, encounter_id, diagnosis_id, diagnosis_sequence)
SELECT e.encounter_id * 10 + s.n,
       e.encounter_id,
       3001 + (FLOOR(POW(CRC32(CONCAT(e.encounter_id, '-dx')) / 4294967296, 2) * 200)
               + (s.n - 1) * 7) % 200,
       s.n
FROM encounters e
JOIN seq_numbers s
  ON s.n <= CASE WHEN e.encounter_type = 'Inpatient'
                 THEN 2 + CRC32(CONCAT(e.encounter_id, '-ndx')) % 5
                 ELSE 1 + CRC32(CONCAT(e.encounter_id, '-ndx')) % 3 END
WHERE e.encounter_id > 7004;

-- ---------------------------------------------------------------------
-- 7. Encounter procedures
--    Inpatient: 1-5 procedures; ER: 0-3; Outpatient: 0-2.
--    Procedures within one encounter are always distinct.
-- ---------------------------------------------------------------------
INSERT INTO encounter_procedures (encounter_procedure_id, encounter_id, procedure_id, procedure_date)
SELECT e.encounter_id * 10 + s.n,
       e.encounter_id,
       4001 + (FLOOR(POW(CRC32(CONCAT(e.encounter_id, '-px')) / 4294967296, 2) * 100)
               + (s.n - 1) * 3) % 100,
       DATE(e.encounter_date)
           + INTERVAL LEAST(s.n - 1, DATEDIFF(e.discharge_date, e.encounter_date)) DAY
FROM encounters e
JOIN seq_numbers s
  ON s.n <= CASE e.encounter_type
                WHEN 'Inpatient' THEN 1 + CRC32(CONCAT(e.encounter_id, '-npx')) % 5
                WHEN 'ER'        THEN     CRC32(CONCAT(e.encounter_id, '-npx')) % 4
                ELSE                      CRC32(CONCAT(e.encounter_id, '-npx')) % 3 END
WHERE e.encounter_id > 7004;

-- ---------------------------------------------------------------------
-- 8. Billing: one claim for ~95% of encounters (the rest not yet billed)
--    Allowed amount = 60-90% of the claimed amount.
--    Claim status: ~85% Paid, ~10% Pending, ~5% Denied.
-- ---------------------------------------------------------------------
INSERT INTO billing (billing_id, encounter_id, claim_amount, allowed_amount, claim_date, claim_status)
SELECT 100000 + c.encounter_id,
       c.encounter_id,
       c.claim_amount,
       ROUND(c.claim_amount * (0.60 + (CRC32(CONCAT(c.encounter_id, '-alw')) % 31) / 100), 2),
       DATE(c.discharge_date) + INTERVAL (1 + CRC32(CONCAT(c.encounter_id, '-cd')) % 20) DAY,
       CASE WHEN CRC32(CONCAT(c.encounter_id, '-st')) % 100 < 85 THEN 'Paid'
            WHEN CRC32(CONCAT(c.encounter_id, '-st')) % 100 < 95 THEN 'Pending'
            ELSE 'Denied' END
FROM (
    SELECT e.encounter_id, e.discharge_date,
           CASE e.encounter_type
               WHEN 'Outpatient' THEN 150  + CRC32(CONCAT(e.encounter_id, '-amt')) % 500
               WHEN 'ER'         THEN 800  + CRC32(CONCAT(e.encounter_id, '-amt')) % 4200
               ELSE                   5000 + CRC32(CONCAT(e.encounter_id, '-amt')) % 35000
           END AS claim_amount
    FROM encounters e
    WHERE e.encounter_id > 7004
      AND CRC32(CONCAT(e.encounter_id, '-bill')) % 100 < 95
) c;

-- ---------------------------------------------------------------------
-- 9. Clean up and refresh optimizer statistics
-- ---------------------------------------------------------------------
DROP TABLE seq_numbers;

ANALYZE TABLE specialties, departments, providers, patients, diagnoses,
              procedures, encounters, encounter_diagnoses,
              encounter_procedures, billing;

SET SQL_SAFE_UPDATES = 1;

-- ---------------------------------------------------------------------
-- 10. Row counts
-- ---------------------------------------------------------------------
SELECT 'specialties'          AS table_name, COUNT(*) AS row_count FROM specialties
UNION ALL SELECT 'departments',          COUNT(*) FROM departments
UNION ALL SELECT 'patients',             COUNT(*) FROM patients
UNION ALL SELECT 'diagnoses',            COUNT(*) FROM diagnoses
UNION ALL SELECT 'procedures',           COUNT(*) FROM procedures
UNION ALL SELECT 'providers',            COUNT(*) FROM providers
UNION ALL SELECT 'encounters',           COUNT(*) FROM encounters
UNION ALL SELECT 'encounter_diagnoses',  COUNT(*) FROM encounter_diagnoses
UNION ALL SELECT 'encounter_procedures', COUNT(*) FROM encounter_procedures
UNION ALL SELECT 'billing',              COUNT(*) FROM billing;
