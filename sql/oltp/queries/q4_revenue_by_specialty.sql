USE healthanalyticsdb;

-- ---------------------------------------------------------------------
-- 1. Total allowed amount per specialty per month
--    Join chain: billing -> encounters -> providers -> specialties
-- ---------------------------------------------------------------------
SELECT
    CAST(DATE_FORMAT(en.encounter_date, '%Y-%m-01') AS DATE) AS encounter_month,
    sp.specialty_name,
    SUM(b.allowed_amount) AS total_allowed
FROM billing b
JOIN      encounters  en ON en.encounter_id = b.encounter_id
LEFT JOIN providers   pr ON pr.provider_id  = en.provider_id
LEFT JOIN specialties sp ON sp.specialty_id = pr.specialty_id
GROUP BY encounter_month, sp.specialty_name
ORDER BY encounter_month, total_allowed DESC;

-- ---------------------------------------------------------------------
-- 2. Performance measurement
-- ---------------------------------------------------------------------
EXPLAIN ANALYZE
SELECT
    CAST(DATE_FORMAT(en.encounter_date, '%Y-%m-01') AS DATE) AS encounter_month,
    sp.specialty_name,
    SUM(b.allowed_amount) AS total_allowed
FROM billing b
JOIN      encounters  en ON en.encounter_id = b.encounter_id
LEFT JOIN providers   pr ON pr.provider_id  = en.provider_id
LEFT JOIN specialties sp ON sp.specialty_id = pr.specialty_id
GROUP BY encounter_month, sp.specialty_name
ORDER BY encounter_month, total_allowed DESC;