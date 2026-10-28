USE healthanalyticsdb;

-- 1. The Query: What are the most common diagnosis-procedure combinations? 
-- Show the ICD code (diagnosis), procedure code (cpt code), and encounter count.
SELECT
    d.icd10_code,
    p.cpt_code,
    COUNT(DISTINCT ed.encounter_id) AS encounter_count
FROM encounter_diagnoses ed
JOIN encounter_procedures ep ON ep.encounter_id = ed.encounter_id
JOIN diagnoses  d ON d.diagnosis_id = ed.diagnosis_id
JOIN procedures p ON p.procedure_id = ep.procedure_id
GROUP BY d.icd10_code, p.cpt_code
ORDER BY encounter_count DESC, d.icd10_code, p.cpt_code;

-- 2. Performance Measurement

EXPLAIN ANALYZE
SELECT
    d.icd10_code,
    p.cpt_code,
    COUNT(DISTINCT ed.encounter_id) AS encounter_count
FROM encounter_diagnoses ed
JOIN encounter_procedures ep ON ep.encounter_id = ed.encounter_id
JOIN diagnoses  d ON d.diagnosis_id = ed.diagnosis_id
JOIN procedures p ON p.procedure_id = ep.procedure_id
GROUP BY d.icd10_code, p.cpt_code
ORDER BY encounter_count DESC, d.icd10_code, p.cpt_code;