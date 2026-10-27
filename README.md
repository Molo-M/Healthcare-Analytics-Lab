### Project Links

| Deliverable              | Link                                          |
| ------------------------ | --------------------------------------------- |
| **Project Instructions** | [View Instructions](instructions.md)          |

---


## Proposed File Structure


```text

healthcare-analytics-lab/
├── README.md                        # Overview, setup steps, where each deliverable lives
├── .gitignore
├── docker-compose.yml               # Optional: spins up MySQL 8 for a reproducible environment
│
├── query_analysis.txt               # ┐
├── design_decisions.txt             # │
├── star_schema.sql                  # │  The 6 graded deliverables,
├── star_schema_queries.txt          # │  exact names from the brief
├── etl_design.txt                   # │
├── reflection.md                    # ┘
│
├── sql/
│   ├── oltp/
│   │   ├── 01_create_schema.sql     # The 3NF tables from Part 1
│   │   ├── 02_sample_data.sql       # The provided INSERTs
│   │   └── queries/
│   │       ├── q1_monthly_encounters.sql
│   │       ├── q2_diagnosis_procedure_pairs.sql
│   │       ├── q3_readmission_rate.sql
│   │       └── q4_revenue_by_specialty.sql
│   ├── etl/
│   │   ├── 01_load_dim_date.sql
│   │   ├── 02_load_dimensions.sql
│   │   ├── 03_load_fact_encounters.sql
│   │   └── 04_load_bridges.sql
│   └── star/
│       └── queries/
│           ├── q1_monthly_encounters.sql
│           ├── q2_diagnosis_procedure_pairs.sql
│           ├── q3_readmission_rate.sql
│           └── q4_revenue_by_specialty.sql
│
├── scripts/
│   ├── generate_synthetic_data.py   # Bulk-loads realistic volumes into the OLTP tables
│   └── run_benchmarks.py            # Runs each query N times, records timings + EXPLAIN ANALYZE
│
└── results/
    ├── benchmarks.csv               # Raw timings: query, schema, run, ms
    └── explain_plans/               # Saved EXPLAIN ANALYZE output per query
        ├── oltp_q1.txt
        └── star_q1.txt ...

```

