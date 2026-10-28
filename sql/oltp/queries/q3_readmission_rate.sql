USE healthanalyticsdb;

-- 1. Query: Which specialty has the highest readmission rate? (Definition: inpatient discharge, then return within 30 days)

SELECT
    sp.specialty_name,
    COUNT(DISTINCT idx.encounter_id) AS inpatient_discharges,
    COUNT(DISTINCT CASE WHEN re.encounter_id IS NOT NULL
                        THEN idx.encounter_id END) AS readmissions,
    ROUND(100 * COUNT(DISTINCT CASE WHEN re.encounter_id IS NOT NULL
                                    THEN idx.encounter_id END)
              / COUNT(DISTINCT idx.encounter_id), 2) AS readmission_rate_pct
FROM encounters idx                                    -- the inpatient stay
LEFT JOIN encounters re                                -- a possible return visit
       ON re.patient_id = idx.patient_id
      AND re.encounter_date >  idx.discharge_date
      AND re.encounter_date <= DATE_ADD(idx.discharge_date, INTERVAL 30 DAY)
LEFT JOIN providers   pr ON pr.provider_id  = idx.provider_id
LEFT JOIN specialties sp ON sp.specialty_id = pr.specialty_id
WHERE idx.encounter_type = 'Inpatient'
GROUP BY sp.specialty_name
ORDER BY readmission_rate_pct DESC;

-- 2. Performance Measurement
EXPLAIN ANALYZE
SELECT
    sp.specialty_name,
    COUNT(DISTINCT idx.encounter_id) AS inpatient_discharges,
    COUNT(DISTINCT CASE WHEN re.encounter_id IS NOT NULL
                        THEN idx.encounter_id END) AS readmissions,
    ROUND(100 * COUNT(DISTINCT CASE WHEN re.encounter_id IS NOT NULL
                                    THEN idx.encounter_id END)
              / COUNT(DISTINCT idx.encounter_id), 2) AS readmission_rate_pct
FROM encounters idx                                    -- the inpatient stay
LEFT JOIN encounters re                                -- a possible return visit
       ON re.patient_id = idx.patient_id
      AND re.encounter_date >  idx.discharge_date
      AND re.encounter_date <= DATE_ADD(idx.discharge_date, INTERVAL 30 DAY)
LEFT JOIN providers   pr ON pr.provider_id  = idx.provider_id
LEFT JOIN specialties sp ON sp.specialty_id = pr.specialty_id
WHERE idx.encounter_type = 'Inpatient'
GROUP BY sp.specialty_name
ORDER BY readmission_rate_pct DESC;