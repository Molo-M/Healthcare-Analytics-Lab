USE healthanalyticsdb;

-- 1. The query: For each month and specialty, show total encounters and unique 
--    patients by encounter type.

SELECT
    CAST(DATE_FORMAT(en.encounter_date, '%Y-%m-01') AS DATE) AS encounter_month,
    sp.specialty_name,
    en.encounter_type,
    COUNT(*) AS total_encounters,
    COUNT(DISTINCT en.patient_id) AS unique_patients
FROM encounters en
LEFT JOIN providers   pr ON pr.provider_id  = en.provider_id
LEFT JOIN specialties sp ON sp.specialty_id = pr.specialty_id
GROUP BY encounter_month, sp.specialty_name, en.encounter_type;
 
-- 2. Performance measurement

EXPLAIN ANALYZE
SELECT
    CAST(DATE_FORMAT(en.encounter_date, '%Y-%m-01') AS DATE) AS encounter_month,
    sp.specialty_name,
    en.encounter_type,
    COUNT(*) AS total_encounters,
    COUNT(DISTINCT en.patient_id) AS unique_patients
FROM encounters en
LEFT JOIN providers   pr ON pr.provider_id  = en.provider_id
LEFT JOIN specialties sp ON sp.specialty_id = pr.specialty_id
GROUP BY encounter_month, sp.specialty_name, en.encounter_type;
 