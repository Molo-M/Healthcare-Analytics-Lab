/* =====================================================================
   01_load_dim_date.sql
   ETL step 1: populate dim_date (one-time load).

   Generates one row per day from 2020-01-01 to 2030-12-31 with a
   recursive CTE, plus the Unknown row (date_key = -1).
   Re-runnable: INSERT IGNORE skips dates that already exist. To extend
   the calendar later, change the end date and run again.
   ===================================================================== */

USE healthanalyticsdw;

-- The CTE needs one recursion step per day (~4,000); MySQL's default
-- limit is 1,000.
SET SESSION cte_max_recursion_depth = 10000;

-- Unknown member: used when a source date is missing (e.g. no discharge)
INSERT IGNORE INTO dim_date
    (date_key, full_date, day_of_month, day_of_week, day_name, is_weekend,
     week_of_year, month_number, month_name, month_start_date, month_label,
     calendar_quarter, quarter_label, calendar_year)
VALUES
    (-1, NULL, 0, 0, 'Unknown', FALSE, 0, 0, 'Unknown', NULL, 'Unknown', 0, 'Unknown', 0);

INSERT IGNORE INTO dim_date
    (date_key, full_date, day_of_month, day_of_week, day_name, is_weekend,
     week_of_year, month_number, month_name, month_start_date, month_label,
     calendar_quarter, quarter_label, calendar_year)
WITH RECURSIVE calendar AS (
    SELECT DATE('2020-01-01') AS d
    UNION ALL
    SELECT d + INTERVAL 1 DAY FROM calendar WHERE d < '2030-12-31'
)
SELECT
    CAST(DATE_FORMAT(d, '%Y%m%d') AS UNSIGNED)       AS date_key,
    d                                                AS full_date,
    DAY(d)                                           AS day_of_month,
    DAYOFWEEK(d)                                     AS day_of_week,
    DAYNAME(d)                                       AS day_name,
    DAYOFWEEK(d) IN (1, 7)                           AS is_weekend,
    WEEK(d, 3)                                       AS week_of_year,   -- ISO week
    MONTH(d)                                         AS month_number,
    MONTHNAME(d)                                     AS month_name,
    CAST(DATE_FORMAT(d, '%Y-%m-01') AS DATE)         AS month_start_date,
    DATE_FORMAT(d, '%Y-%m')                          AS month_label,
    QUARTER(d)                                       AS calendar_quarter,
    CONCAT(YEAR(d), '-Q', QUARTER(d))                AS quarter_label,
    YEAR(d)                                          AS calendar_year
FROM calendar;

SELECT COUNT(*) AS dim_date_rows,
       MIN(full_date) AS first_date,
       MAX(full_date) AS last_date
FROM dim_date;
