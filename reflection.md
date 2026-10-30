# Reflection: From OLTP to Star Schema

I took a normalized hospital database, measured why four analytics questions were slow, and rebuilt the data as a star schema designed for them. Both versions were loaded with the same 200,000 synthetic encounters. Every star query returns exactly the same answers as the original, and runs **about 7 to 138 times faster**.

## 1. Why Is the Star Schema Faster?

**It's not mainly about having fewer joins.** I expected fewer joins to be the answer, but the numbers tell a more interesting story:

| Question | Joins (OLTP) | Joins (Star) |
| -------- | :----------: | :----------: |
| Q1 Monthly encounters | 2 | 3 |
| Q2 Diagnosis-procedure pairs | 3 | 3 |
| Q3 Readmission rate | 3 (incl. a self-join) | 2 |
| Q4 Revenue by specialty | 3 | 2 |

Q1 actually has *more* joins in the star schema. The real difference is **when** the joins happen. In the OLTP database, every one of the 200,000 encounters had to look up its provider and then its specialty before anything could be counted, which meant hundreds of thousands of lookups per query. In the star schema, the fact table is counted first, using simple numeric keys, and the dimension tables are joined afterwards to a few hundred summary rows just to add readable names. Same joins, a tiny fraction of the work.

**Much of the work is done once, in advance.** The ETL process calculates things the OLTP queries had to recompute on every run:

- Each encounter row already carries its **specialty**, so no query walks the encounter → provider → specialty chain.
- **Billing totals** are summed per encounter, so revenue questions never touch the billing table.
- The **readmission flag** is calculated once per hospital stay. This replaced the most expensive operation in the whole project, a self-join that compared each inpatient stay against the patient's entire visit history.
- The **month** comes directly from the date key (20240510 → 202405), instead of formatting a date on every row.

**Why denormalization helps analytics.** A normalized database stores each fact once so it can record events safely, which is right for the hospital's day-to-day system. Analytics is the opposite workload: few writes, but questions that read *every* row. Copying the specialty onto each encounter breaks the "store it once" rule, but lets a report read one table instead of rebuilding the same relationships hundreds of thousands of times.

## 2. Trade-offs: What Did I Gain, and What Did I Lose?

**What I gave up:**

- **Storage.** The same data now exists twice, once in each database, and the warehouse is roughly as large as the original.
- **Simplicity.** The warehouse needs its own load process: four ETL scripts, change tracking for providers, "Unknown" rows for missing data, and rules for late-arriving claims. That's real code to build, test and maintain.
- **Freshness.** The warehouse is only as current as its last load. A visit recorded this afternoon won't appear in reports until tonight's refresh.
- **Some flexibility.** The indexes are tuned to these four questions. New kinds of questions will run correctly, but may need new indexes to be fast.

**What I gained:**

- **Speed:** 7–138 times faster on the same data (see section 4).
- **Simpler queries.** Questions are answered from one central table plus a few small lookups, which is easier to write and harder to get wrong.
- **Better history.** If a doctor changes specialty, their past visits still count under the old specialty, something the original database can't do because it only stores the current value.
- **Visible data quality.** Missing values appear as "Unknown" in reports instead of silently disappearing from totals.

**Was it worth it?** Yes, as a complement to the original database rather than a replacement. The hospital still needs its normalized system to record care accurately; the star schema is a separate copy shaped for reading. For reports that run regularly, paying the cost once a night during the load beats paying it every time someone opens a report.

## 3. Bridge Tables: Worth It?

A single encounter can have several diagnoses and several procedures. The fact table holds one row per encounter, so these lists can't fit into it directly.

**Why not put them in the fact table?** Doing so would give each encounter one row *per diagnosis*, and every encounter-level number would multiply. An inpatient stay with three diagnoses and $10,000 in revenue would show up as **$30,000**. Every revenue and encounter count would be wrong unless each query remembered to correct for it. Bridge tables keep the lists separate, so only the question that actually needs them (Q2) ever touches them, and the other three questions stay simple and correct.

**The trade-off.** Bridges keep the multiplication contained, but they don't remove it. Q2 still pairs every diagnosis with every procedure inside each encounter, producing about 758,000 rows, exactly as in the original database. That's why Q2 improved the least (6.9×) and remains the slowest query at almost two seconds.

**What I would do differently in production:**

- Keep the bridge tables. They are the correct structure.
- If the diagnosis-procedure report powered a frequently refreshed dashboard, add a **summary table** of pair counts, rebuilt during each nightly load, so the report reads about 7,500 ready-made rows instead of building 758,000 every time.
- Add a **primary diagnosis** column to the fact table. Many reports only need the main diagnosis, and a single value per encounter can sit in the fact table without any multiplication.

## 4. Performance Quantification

All four questions were measured on the same 200,000 encounters, using `EXPLAIN ANALYZE` in MySQL Workbench:

| Question | Original | Optimized | Improvement | Main reason for the speedup |
| -------- | -------: | --------: | ----------: | --------------------------- |
| Q1 Monthly encounters | 2.910 s | 0.219 s | **13.3×** | Specialty stored on each encounter; the 400,000 provider/specialty lookups disappear |
| Q2 Diagnosis-procedure pairs | 12.757 s | 1.858 s | **6.9×** | Faster bridge access and no duplicate removal; the pair explosion itself remains |
| Q3 Readmission rate | 2.672 s | 0.0193 s | **138×** | Readmission flag pre-computed; the self-join is gone entirely |
| Q4 Revenue by specialty | 2.798 s | 0.164 s | **17.1×** | Billing totals pre-summed per encounter; the four-table join chain is gone |

Two results stand out:

- **Q3 improved the most (2.672 s → 0.0193 s, 138×)** because its most expensive work didn't just get faster; it moved out of the query entirely. The ETL answers "was this patient readmitted?" once, and the query simply adds up the answers.
- **Q4 (2.798 s → 0.164 s, 17.1×)** shows the classic star schema benefit. The original had to connect each of 190,000 claims through four tables before it could add anything up. The star query reads one table that already holds both the totals and the specialty.

**A note on accuracy.** These are single runs on a laptop, so exact times would vary between machines. The amount of data each query reads doesn't: the star schema reads 3–19 times fewer rows for every question except Q2, which confirms the speedups come from the design, not from chance.

## What I Learned

The biggest lesson was that good analytical design means **doing work once instead of every time**. The fastest result (Q3) came from computing an answer in advance; the slowest (Q2) is the one place where the expensive work still happens at query time. I also learned that measuring at a realistic scale matters: on the four rows of sample data every query took a fraction of a millisecond, and the problems only became visible with 200,000 encounters.
