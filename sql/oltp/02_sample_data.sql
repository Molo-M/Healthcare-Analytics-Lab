/* =====================================================================
   02_sample_data.sql
   Healthcare Analytics Lab - sample data for the OLTP schema (MySQL 8.0)
   Run 01_create_schema.sql first.
   Re-runnable: existing rows are cleared before inserting.
   ===================================================================== */

USE healthanalyticsdb;

-- MySQL Workbench turns on "safe update mode" by default, which blocks
-- DELETE statements without a WHERE clause on a key column. Turn it off
-- for this session only; it is switched back on at the end.
SET SQL_SAFE_UPDATES = 0;

-- Note: MySQL always reads 'YYYY-MM-DD hh:mm:ss' as year-month-day,
-- so no equivalent of SQL Server's SET DATEFORMAT is needed.

START TRANSACTION;

-- ---------------------------------------------------------------------
-- 1. Clear existing rows (children first, then parents)
-- ---------------------------------------------------------------------
DELETE FROM billing;
DELETE FROM encounter_procedures;
DELETE FROM encounter_diagnoses;
DELETE FROM encounters;
DELETE FROM providers;
DELETE FROM procedures;
DELETE FROM diagnoses;
DELETE FROM departments;
DELETE FROM specialties;
DELETE FROM patients;

-- ---------------------------------------------------------------------
-- 2. Insert data (parents first, then children)
-- ---------------------------------------------------------------------

-- Lookup / parent tables (no foreign keys)
INSERT INTO specialties (specialty_id, specialty_name, specialty_code) VALUES
    (1, 'Cardiology', 'CARD'),
    (2, 'Internal Medicine', 'IM'),
    (3, 'Emergency', 'ER');

INSERT INTO departments (department_id, department_name, floor, capacity) VALUES
    (1, 'Cardiology Unit', 3, 20),
    (2, 'Internal Medicine', 2, 30),
    (3, 'Emergency', 1, 45);

INSERT INTO patients (patient_id, first_name, last_name, date_of_birth, gender, mrn) VALUES
    (1001, 'John', 'Doe', '1955-03-15', 'M', 'MRN001'),
    (1002, 'Jane', 'Smith', '1962-07-22', 'F', 'MRN002'),
    (1003, 'Robert', 'Johnson', '1948-11-08', 'M', 'MRN003');

INSERT INTO diagnoses (diagnosis_id, icd10_code, icd10_description) VALUES
    (3001, 'I10', 'Hypertension'),
    (3002, 'E11.9', 'Type 2 Diabetes'),
    (3003, 'I50.9', 'Heart Failure');

INSERT INTO procedures (procedure_id, cpt_code, cpt_description) VALUES
    (4001, '99213', 'Office Visit'),
    (4002, '93000', 'EKG'),
    (4003, '71020', 'Chest X-ray');

-- Depends on specialties, departments
INSERT INTO providers (provider_id, first_name, last_name, credential, specialty_id, department_id) VALUES
    (101, 'James', 'Chen', 'MD', 1, 1),
    (102, 'Sarah', 'Williams', 'MD', 2, 2),
    (103, 'Michael', 'Rodriguez', 'MD', 3, 3);

-- Depends on patients, providers, departments
INSERT INTO encounters (encounter_id, patient_id, provider_id, encounter_type, encounter_date, discharge_date, department_id) VALUES
    (7001, 1001, 101, 'Outpatient', '2024-05-10 10:00:00', '2024-05-10 11:30:00', 1),
    (7002, 1001, 101, 'Inpatient',  '2024-06-02 14:00:00', '2024-06-06 09:00:00', 1),
    (7003, 1002, 102, 'Outpatient', '2024-05-15 09:00:00', '2024-05-15 10:15:00', 2),
    (7004, 1003, 103, 'ER',         '2024-06-12 23:45:00', '2024-06-13 06:30:00', 3);

-- Depend on encounters (in the original script, billing was inserted
-- BEFORE encounters, which violates its foreign key)
INSERT INTO encounter_diagnoses (encounter_diagnosis_id, encounter_id, diagnosis_id, diagnosis_sequence) VALUES
    (8001, 7001, 3001, 1), (8002, 7001, 3002, 2),
    (8003, 7002, 3001, 1), (8004, 7002, 3003, 2),
    (8005, 7003, 3002, 1), (8006, 7004, 3001, 1);

INSERT INTO encounter_procedures (encounter_procedure_id, encounter_id, procedure_id, procedure_date) VALUES
    (9001, 7001, 4001, '2024-05-10'), (9002, 7001, 4002, '2024-05-10'),
    (9003, 7002, 4001, '2024-06-02'), (9004, 7003, 4001, '2024-05-15');

INSERT INTO billing (billing_id, encounter_id, claim_amount, allowed_amount, claim_date, claim_status) VALUES
    (14001, 7001, 350, 280, '2024-05-11', 'Paid'),
    (14002, 7002, 12500, 10000, '2024-06-08', 'Paid');

COMMIT;

-- Restore Workbench's default safety setting.
SET SQL_SAFE_UPDATES = 1;

-- ---------------------------------------------------------------------
-- 3. Quick check: row counts per table
--    Expected: 3, 3, 3, 3, 3, 3, 4, 6, 4, 2
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