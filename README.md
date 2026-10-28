# Healthcare Analytics Lab: OLTP to Star Schema

A data engineering mini project. A normalized (3NF) clinical database is analyzed for slow analytical queries, then redesigned as a star schema optimized for those queries. See the full brief in [Instructions.md](Instructions.md).

## Tech Stack

- **Database:** MySQL 8.0.18 or later (required for `EXPLAIN ANALYZE`)
- **Client:** MySQL Workbench

## Setup

1. Open `sql/oltp/01_create_schema.sql` in MySQL Workbench and run the whole script (lightning-bolt icon). It creates the `healthanalyticsdb` database and its 10 tables. It is re-runnable: existing tables are dropped and recreated.
2. Run `sql/oltp/02_sample_data.sql` to load the sample data. The row-count check at the end should return 3, 3, 3, 3, 3, 3, 4, 6, 4, 2.
3. Run any file in `sql/oltp/queries/`. Each file contains the query, followed by an `EXPLAIN ANALYZE` of the same query for performance measurement.

## Deliverables

| Part | Deliverable | Status |
| ---- | ----------- | ------ |
| 2 | [query_analysis.txt](query_analysis.txt): 4 OLTP queries with performance analysis | Done |
| 3.1 | `design_decisions.txt`: star schema design choices | To do |
| 3.2 | `star_schema.sql`: star schema DDL | To do |
| 3.3 | `star_schema_queries.txt`: optimized queries with performance comparison | To do |
| 3.4 | `etl_design.txt`: ETL pseudocode / narrative | To do |
| 4 | `reflection.md`: analysis and reflection | To do |

## Repository Structure

Items marked *(planned)* do not exist yet.

```text
Healthcare-Analytics-Lab/
├── README.md
├── Instructions.md                  # Project brief
├── .gitignore
│
├── query_analysis.txt               # Part 2 deliverable
├── design_decisions.txt             # Part 3.1 deliverable (planned)
├── star_schema.sql                  # Part 3.2 deliverable (planned)
├── star_schema_queries.txt          # Part 3.3 deliverable (planned)
├── etl_design.txt                   # Part 3.4 deliverable (planned)
├── reflection.md                    # Part 4 deliverable (planned)
│
├── sql/
│   ├── erd_diagram.png              # ERD of the OLTP schema
│   ├── oltp/
│   │   ├── 01_create_schema.sql     # 3NF schema (10 tables)
│   │   ├── 02_sample_data.sql       # Sample data from the brief
│   │   └── queries/
│   │       ├── q1_monthly_encounters.sql
│   │       ├── q2_diagnosis_procedure_pairs.sql
│   │       ├── q3_readmission_rate.sql
│   │       └── q4_revenue_by_specialty.sql
│   ├── etl/                         # (planned) dimension, fact and bridge loads
│   └── star/
│       └── queries/                 # (planned) the 4 queries rewritten for the star schema
│
├── scripts/                         # (planned) synthetic data generator, benchmark runner
│
└── results/
    └── explain_analyze/             # Saved EXPLAIN ANALYZE output per query
        ├── oltp_q1.txt
        ├── oltp_q2.txt
        ├── oltp_q3.txt
        └── oltp_q4.txt
```

## OLTP Schema (ERD)

![ERD of the OLTP schema](sql/erd_diagram.png)

## Notes

- The brief describes "8 normalized tables", but its DDL defines 10: 7 entity and lookup tables (`patients`, `providers`, `specialties`, `departments`, `encounters`, `diagnoses`, `procedures`), 2 junction tables (`encounter_diagnoses`, `encounter_procedures`), and `billing`. This project uses the DDL as written.
- The sample data's original insert order loads `billing` before `encounters`, which violates `billing`'s foreign key. `02_sample_data.sql` loads tables parents-first.
- Performance figures in `query_analysis.txt` come from the small sample data, so they are a baseline: sub-millisecond timings mostly reflect overhead and vary between runs.