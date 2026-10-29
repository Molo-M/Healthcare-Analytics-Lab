/* =====================================================================
   star_schema.sql
   Healthcare Analytics Lab - Star schema (dimensional model), MySQL 8.0

   Lives in its own database, healthanalyticsdw (the data warehouse),
   separate from the OLTP database healthanalyticsdb. The ETL scripts in
   sql/olap/etl/ read from the OLTP database and load these tables.

   Model overview
   --------------
   Fact table : fact_encounters (grain: one row per encounter)
   Dimensions : dim_date, dim_patient, dim_provider, dim_specialty,
                dim_department, dim_encounter_type, dim_diagnosis,
                dim_procedure
   Bridges    : bridge_encounter_diagnoses, bridge_encounter_procedures
                (many-to-many: one encounter has many diagnoses and
                many procedures)

   Conventions
   -----------
   - Every dimension has a surrogate key (*_key). The OLTP natural key
     (*_id) is kept as an attribute for traceability.
   - dim_date uses a "smart" key in YYYYMMDD format (e.g. 20240510),
     the standard exception to meaningless surrogate keys.
   - Every dimension contains an "Unknown" row with key -1. The ETL
     points a fact at -1 when the source value is missing, so fact
     foreign keys are never NULL and no fact row is lost in a join.

   Re-runnable: drops and recreates every warehouse table (all data in
   the warehouse is lost; reload it with the ETL scripts).
   ===================================================================== */

CREATE DATABASE IF NOT EXISTS healthanalyticsdw;
USE healthanalyticsdw;

-- Drop in dependency order: bridges -> fact -> dimensions
DROP TABLE IF EXISTS bridge_encounter_procedures;
DROP TABLE IF EXISTS bridge_encounter_diagnoses;
DROP TABLE IF EXISTS fact_encounters;
DROP TABLE IF EXISTS dim_procedure;
DROP TABLE IF EXISTS dim_diagnosis;
DROP TABLE IF EXISTS dim_encounter_type;
DROP TABLE IF EXISTS dim_department;
DROP TABLE IF EXISTS dim_specialty;
DROP TABLE IF EXISTS dim_provider;
DROP TABLE IF EXISTS dim_patient;
DROP TABLE IF EXISTS dim_date;


/* =====================================================================
   DIMENSIONS
   ===================================================================== */

-- ---------------------------------------------------------------------
-- dim_date: one row per calendar day (2020-01-01 to 2030-12-31).
-- Role-playing dimension: the fact table references it twice, as the
-- encounter date and as the discharge date. Month, quarter and year
-- are precomputed so queries never call DATE_FORMAT at query time.
-- ---------------------------------------------------------------------
CREATE TABLE dim_date (
    date_key          INT          NOT NULL,   -- YYYYMMDD, e.g. 20240510; -1 = Unknown
    full_date         DATE         NULL,       -- NULL only for the Unknown row
    day_of_month      TINYINT      NOT NULL,
    day_of_week       TINYINT      NOT NULL,   -- 1 = Sunday ... 7 = Saturday
    day_name          VARCHAR(10)  NOT NULL,
    is_weekend        BOOLEAN      NOT NULL,
    week_of_year      TINYINT      NOT NULL,
    month_number      TINYINT      NOT NULL,
    month_name        VARCHAR(10)  NOT NULL,
    month_start_date  DATE         NULL,       -- first day of the month (for monthly reports)
    month_label       CHAR(7)      NOT NULL,   -- 'YYYY-MM'
    calendar_quarter  TINYINT      NOT NULL,
    quarter_label     CHAR(7)      NOT NULL,   -- 'YYYY-Q1'
    calendar_year     SMALLINT     NOT NULL,
    PRIMARY KEY (date_key),
    UNIQUE KEY uq_dim_date_full_date (full_date),
    KEY idx_dim_date_month (calendar_year, month_number)
) ENGINE = InnoDB
  COMMENT = 'Calendar dimension, one row per day; role-plays as encounter and discharge date';

-- ---------------------------------------------------------------------
-- dim_patient: one row per patient (SCD Type 1: changes overwrite).
-- age_group reflects the patient's age when the ETL last ran; the
-- age at the time of each visit is stored on the fact row instead.
-- ---------------------------------------------------------------------
CREATE TABLE dim_patient (
    patient_key     INT           NOT NULL AUTO_INCREMENT,
    patient_id      INT           NOT NULL,      -- OLTP natural key
    mrn             VARCHAR(20)   NULL,          -- medical record number (business key)
    first_name      VARCHAR(100)  NULL,
    last_name       VARCHAR(100)  NULL,
    full_name       VARCHAR(201)  NULL,
    gender          CHAR(1)       NULL,
    date_of_birth   DATE          NULL,
    age_group       VARCHAR(10)   NOT NULL,      -- '0-17', '18-34', '35-49', '50-64', '65-79', '80+', 'Unknown'
    dw_updated_at   TIMESTAMP     NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (patient_key),
    UNIQUE KEY uq_dim_patient_id (patient_id)
) ENGINE = InnoDB
  COMMENT = 'Patient dimension (SCD Type 1)';

-- ---------------------------------------------------------------------
-- dim_specialty: one row per medical specialty.
-- ---------------------------------------------------------------------
CREATE TABLE dim_specialty (
    specialty_key   INT           NOT NULL AUTO_INCREMENT,
    specialty_id    INT           NOT NULL,      -- OLTP natural key
    specialty_name  VARCHAR(100)  NOT NULL,
    specialty_code  VARCHAR(10)   NULL,
    PRIMARY KEY (specialty_key),
    UNIQUE KEY uq_dim_specialty_id (specialty_id)
) ENGINE = InnoDB
  COMMENT = 'Medical specialty dimension (SCD Type 1)';

-- ---------------------------------------------------------------------
-- dim_department: one row per hospital department.
-- ---------------------------------------------------------------------
CREATE TABLE dim_department (
    department_key   INT           NOT NULL AUTO_INCREMENT,
    department_id    INT           NOT NULL,     -- OLTP natural key
    department_name  VARCHAR(100)  NOT NULL,
    floor_number     INT           NULL,
    bed_capacity     INT           NULL,
    PRIMARY KEY (department_key),
    UNIQUE KEY uq_dim_department_id (department_id)
) ENGINE = InnoDB
  COMMENT = 'Hospital department dimension (SCD Type 1)';

-- ---------------------------------------------------------------------
-- dim_provider: one row per provider VERSION (SCD Type 2).
-- If a provider changes specialty or department, the current row is
-- closed (effective_to, is_current = FALSE) and a new row is added, so
-- past encounters keep pointing at the provider as they were then.
-- specialty_name and department_name are denormalized here for easy
-- filtering; specialty_key and department_key record which version of
-- those dimensions this provider version belongs to (used by the ETL
-- to stamp each fact row; queries use the fact table's own keys).
-- ---------------------------------------------------------------------
CREATE TABLE dim_provider (
    provider_key     INT           NOT NULL AUTO_INCREMENT,
    provider_id      INT           NOT NULL,     -- OLTP natural key (repeats across versions)
    first_name       VARCHAR(100)  NULL,
    last_name        VARCHAR(100)  NULL,
    full_name        VARCHAR(201)  NULL,
    credential       VARCHAR(20)   NULL,
    specialty_key    INT           NOT NULL,     -- tracked attribute (Type 2)
    specialty_name   VARCHAR(100)  NOT NULL,
    department_key   INT           NOT NULL,     -- tracked attribute (Type 2)
    department_name  VARCHAR(100)  NOT NULL,
    effective_from   DATE          NOT NULL,
    effective_to     DATE          NOT NULL DEFAULT '9999-12-31',
    is_current       BOOLEAN       NOT NULL DEFAULT TRUE,
    PRIMARY KEY (provider_key),
    UNIQUE KEY uq_dim_provider_version (provider_id, effective_from),
    KEY idx_dim_provider_current (provider_id, is_current)
) ENGINE = InnoDB
  COMMENT = 'Provider dimension (SCD Type 2 on specialty and department)';

-- ---------------------------------------------------------------------
-- dim_encounter_type: small static list (Outpatient, Inpatient, ER).
-- is_inpatient lets queries filter index admissions without strings.
-- ---------------------------------------------------------------------
CREATE TABLE dim_encounter_type (
    encounter_type_key   INT          NOT NULL AUTO_INCREMENT,
    encounter_type_name  VARCHAR(50)  NOT NULL,
    is_inpatient         BOOLEAN      NOT NULL,
    PRIMARY KEY (encounter_type_key),
    UNIQUE KEY uq_dim_encounter_type_name (encounter_type_name)
) ENGINE = InnoDB
  COMMENT = 'Encounter type dimension';

-- ---------------------------------------------------------------------
-- dim_diagnosis: one row per ICD-10 diagnosis code.
-- icd10_category = first 3 characters (e.g. I50.9 -> I50) for roll-ups.
-- ---------------------------------------------------------------------
CREATE TABLE dim_diagnosis (
    diagnosis_key      INT           NOT NULL AUTO_INCREMENT,
    diagnosis_id       INT           NOT NULL,   -- OLTP natural key
    icd10_code         VARCHAR(10)   NOT NULL,
    icd10_description  VARCHAR(200)  NULL,
    icd10_category     VARCHAR(3)    NOT NULL,
    PRIMARY KEY (diagnosis_key),
    UNIQUE KEY uq_dim_diagnosis_id (diagnosis_id),
    KEY idx_dim_diagnosis_code (icd10_code)
) ENGINE = InnoDB
  COMMENT = 'ICD-10 diagnosis dimension';

-- ---------------------------------------------------------------------
-- dim_procedure: one row per CPT procedure code.
-- ---------------------------------------------------------------------
CREATE TABLE dim_procedure (
    procedure_key    INT           NOT NULL AUTO_INCREMENT,
    procedure_id     INT           NOT NULL,     -- OLTP natural key
    cpt_code         VARCHAR(10)   NOT NULL,
    cpt_description  VARCHAR(200)  NULL,
    PRIMARY KEY (procedure_key),
    UNIQUE KEY uq_dim_procedure_id (procedure_id),
    KEY idx_dim_procedure_code (cpt_code)
) ENGINE = InnoDB
  COMMENT = 'CPT procedure dimension';


/* =====================================================================
   FACT TABLE
   ===================================================================== */

-- ---------------------------------------------------------------------
-- fact_encounters: one row per encounter (the declared grain).
--
-- encounter_id is a degenerate dimension: the OLTP encounter number,
-- kept on the fact with no dimension table of its own. It is the
-- primary key and the link to the bridge tables.
--
-- Pre-aggregated metrics are computed once by the ETL so the four
-- business questions need no junction-table, billing or self-joins:
--   diagnosis_count, procedure_count  -> from the junction tables
--   claim_count, total_claim_amount,
--   total_allowed_amount              -> summed from billing
--   readmitted_within_30d             -> replaces the readmission self-join
--   length_of_stay_hours, patient_age_at_encounter -> derived once
--
-- specialty_key and department_key are stored directly on the fact
-- (copied from the provider and the encounter at load time), so no
-- query has to go fact -> provider -> specialty.
-- ---------------------------------------------------------------------
CREATE TABLE fact_encounters (
    encounter_id              INT            NOT NULL,   -- degenerate dimension (OLTP encounter number)

    -- Dimension foreign keys (never NULL; -1 = Unknown)
    encounter_date_key        INT            NOT NULL,   -- role: date of admission / visit
    discharge_date_key        INT            NOT NULL,   -- role: date of discharge
    patient_key               INT            NOT NULL,
    provider_key              INT            NOT NULL,
    specialty_key             INT            NOT NULL,   -- provider's specialty at encounter time
    department_key            INT            NOT NULL,
    encounter_type_key        INT            NOT NULL,

    -- Additive measures
    encounter_count           TINYINT        NOT NULL DEFAULT 1,  -- always 1; SUM() counts encounters
    diagnosis_count           SMALLINT       NOT NULL DEFAULT 0,
    procedure_count           SMALLINT       NOT NULL DEFAULT 0,
    claim_count               SMALLINT       NOT NULL DEFAULT 0,
    total_claim_amount        DECIMAL(14,2)  NOT NULL DEFAULT 0,
    total_allowed_amount      DECIMAL(14,2)  NOT NULL DEFAULT 0,
    length_of_stay_hours      DECIMAL(10,2)  NULL,       -- NULL if discharge is unknown

    -- Readmission measures (meaningful for inpatient encounters only)
    readmitted_within_30d     TINYINT        NOT NULL DEFAULT 0,  -- 1 = same patient returned <= 30 days after discharge
    days_to_next_encounter    INT            NULL,       -- days from discharge to the next encounter after it

    -- Non-additive attribute captured at encounter time
    patient_age_at_encounter  SMALLINT       NULL,

    dw_loaded_at              TIMESTAMP      NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,

    PRIMARY KEY (encounter_id),

    CONSTRAINT fk_fact_encounter_date FOREIGN KEY (encounter_date_key) REFERENCES dim_date (date_key),
    CONSTRAINT fk_fact_discharge_date FOREIGN KEY (discharge_date_key) REFERENCES dim_date (date_key),
    CONSTRAINT fk_fact_patient        FOREIGN KEY (patient_key)        REFERENCES dim_patient (patient_key),
    CONSTRAINT fk_fact_provider       FOREIGN KEY (provider_key)       REFERENCES dim_provider (provider_key),
    CONSTRAINT fk_fact_specialty      FOREIGN KEY (specialty_key)      REFERENCES dim_specialty (specialty_key),
    CONSTRAINT fk_fact_department     FOREIGN KEY (department_key)     REFERENCES dim_department (department_key),
    CONSTRAINT fk_fact_encounter_type FOREIGN KEY (encounter_type_key) REFERENCES dim_encounter_type (encounter_type_key),

    -- Covering index for Q1 (month x specialty x type, unique patients):
    -- every column the query reads is in the index, so the table itself
    -- is never touched.
    KEY idx_fact_q1_date_spec_type_patient (encounter_date_key, specialty_key, encounter_type_key, patient_key),
    -- Covering index for Q4 (allowed amount by month x specialty)
    KEY idx_fact_q4_date_spec_allowed (encounter_date_key, specialty_key, claim_count, total_allowed_amount),
    -- Covering index for Q3 (inpatient readmissions by specialty)
    KEY idx_fact_q3_type_spec_readmit (encounter_type_key, specialty_key, readmitted_within_30d),
    -- Single-column indexes for the remaining foreign keys (joins/filters)
    KEY idx_fact_discharge_date (discharge_date_key),
    KEY idx_fact_patient (patient_key),
    KEY idx_fact_provider (provider_key),
    KEY idx_fact_specialty (specialty_key),
    KEY idx_fact_department (department_key)
) ENGINE = InnoDB
  COMMENT = 'Encounter fact table, grain = one row per encounter';


/* =====================================================================
   BRIDGE TABLES (many-to-many between encounters and diagnoses/procedures)
   ===================================================================== */

-- ---------------------------------------------------------------------
-- bridge_encounter_diagnoses: one row per (encounter, diagnosis).
-- The primary key starts with encounter_id, so InnoDB stores each
-- encounter's diagnoses physically together, which makes joining the
-- two bridges on encounter_id cheap. Duplicates in the source are
-- collapsed by the ETL, so COUNT(*) per pair equals the number of
-- distinct encounters (no COUNT(DISTINCT) needed).
-- No weighting factor: allocating one encounter's revenue across its
-- diagnoses has no agreed business rule in healthcare; is_primary
-- (diagnosis_sequence = 1) is used instead when one diagnosis is needed.
-- ---------------------------------------------------------------------
CREATE TABLE bridge_encounter_diagnoses (
    encounter_id        INT       NOT NULL,
    diagnosis_key       INT       NOT NULL,
    diagnosis_sequence  SMALLINT  NULL,        -- 1 = primary diagnosis
    is_primary          BOOLEAN   NOT NULL DEFAULT FALSE,
    PRIMARY KEY (encounter_id, diagnosis_key),
    KEY idx_bridge_dx_diagnosis (diagnosis_key, encounter_id),
    CONSTRAINT fk_bridge_dx_encounter FOREIGN KEY (encounter_id)  REFERENCES fact_encounters (encounter_id),
    CONSTRAINT fk_bridge_dx_diagnosis FOREIGN KEY (diagnosis_key) REFERENCES dim_diagnosis (diagnosis_key)
) ENGINE = InnoDB
  COMMENT = 'Bridge: encounters <-> diagnoses (many-to-many)';

-- ---------------------------------------------------------------------
-- bridge_encounter_procedures: one row per (encounter, procedure).
-- If the same procedure is recorded several times in one encounter,
-- the ETL keeps one row and stores the repeat count in
-- procedure_quantity, plus the date it was first performed.
-- ---------------------------------------------------------------------
CREATE TABLE bridge_encounter_procedures (
    encounter_id              INT       NOT NULL,
    procedure_key             INT       NOT NULL,
    procedure_quantity        SMALLINT  NOT NULL DEFAULT 1,
    first_procedure_date_key  INT       NOT NULL,   -- -1 = Unknown
    PRIMARY KEY (encounter_id, procedure_key),
    KEY idx_bridge_px_procedure (procedure_key, encounter_id),
    CONSTRAINT fk_bridge_px_encounter FOREIGN KEY (encounter_id)             REFERENCES fact_encounters (encounter_id),
    CONSTRAINT fk_bridge_px_procedure FOREIGN KEY (procedure_key)            REFERENCES dim_procedure (procedure_key),
    CONSTRAINT fk_bridge_px_date      FOREIGN KEY (first_procedure_date_key) REFERENCES dim_date (date_key)
) ENGINE = InnoDB
  COMMENT = 'Bridge: encounters <-> procedures (many-to-many)';

SELECT 'Star schema created successfully in healthanalyticsdw.' AS status;
