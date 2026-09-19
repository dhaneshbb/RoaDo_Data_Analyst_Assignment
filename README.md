<div align="center">

![Python](https://img.shields.io/badge/python-3.8+-blue.svg) ![PostgreSQL](https://img.shields.io/badge/PostgreSQL-316192?logo=postgresql&logoColor=white) ![MongoDB](https://img.shields.io/badge/MongoDB-4EA94B?logo=mongodb&logoColor=white) ![Pandas](https://img.shields.io/badge/pandas-%23150458.svg?logo=pandas&logoColor=white) ![PowerBI](https://img.shields.io/badge/PowerBI-F2C811?logo=powerbi&logoColor=black)

# Customer Churn & Retention Analysis for NimbusAI

Data analytics pipeline combining relational subscription data and unstructured behavioral logs to identify early warning signals for customer churn.

**Focus Area:** Customer Churn & Retention Analysis

</div>

---

## Overview

Analyzes churn and retention dynamics for NimbusAI's customer base. Integrates subscription and support ticket data from PostgreSQL with product engagement and behavioral logs from MongoDB to identify risk segments, test retention hypotheses, and provide actionable retention strategies.

**Final Deliverables:**
- Cleaned dashboard dataset: 1,204 active and cancelled subscriptions
- Cross-validation: Mann-Whitney U Test (p-value: 0.128)
- Customer Segments: High Risk, Support Risk, Disengaged, Healthy
- Presentation: Power BI Dashboard (5 core visuals, 2 interactive filters)

---

## Quick Start

### Installation

```bash
pip install -r requirements.txt
```

### Database Restoration & Data Export

Restore the provided database files to the local PostgreSQL and MongoDB servers, then extract the unified CSV files:

```bash
python scripts/export_data.py
```

### Run Full Pipeline

Execute the primary analysis notebook to generate the final dataset:
`03_churn_analysis.ipynb` - Data extraction, anomaly handling, EDA, statistical testing, and export.

## Dataset

| Property | Details |
|----------|---------|
| **Source** | NimbusAI Internal Databases (PostgreSQL, MongoDB) |
| **SQL Data** | Customers, Subscriptions, Support Tickets, Plans |
| **NoSQL Data** | User Activity Logs (100k+ events), NPS Responses, Onboarding Events |
| **Final Samples** | 1,204 unique customers |
| **Data Cleaning** | Dropped 49,000+ exact duplicate events; mapped string/float IDs to uniform schema |


## Challenges Faced & Data Quality Fixes

The unstructured nature of the MongoDB activity logs presented severe data quality issues that required advanced programmatic normalization before analysis could begin:

1. **Catastrophic Event Duplication:** 
   - **Issue:** The ctivity_clean.csv contained over 49,000 duplicated event rows. Analysis revealed this was likely caused by frontend double-fire bugs creating identical timestamps and payloads, but unique MongoDB _id hashes.
   - **Fix:** Dropped the unique MongoDB _id column locally and ran a strict drop_duplicates() pass, which successfully stripped 49,153 ghost events, ensuring session counts were mathematically accurate.
2. **Inconsistent Schema Keys:** 
   - **Issue:** NoSQL schemas resulted in the primary key being stored randomly as customerId, customer_id, or customerID. 
   - **Fix:** Handled programmatically using Pandas coalesce equivalents (fill(axis=1)) to collapse all three variations into a single, unified customer_id column.
3. **Data Type Mismatches:** 
   - **Issue:** Customer IDs were exported as floats (e.g., 229.0) in MongoDB but as strings in PostgreSQL, causing catastrophic join failures during the final dataset merge. 
   - **Fix:** Coerced all IDs using .astype(str) and stripped trailing .0 decimals via regex to guarantee a flawless 1:1 join with the SQL schema.
4. **Timestamp Parsing:** 
   - **Issue:** MongoDB timestamps contained mixed formats (ISO-8601 strings intermixed with standard datetime strings). 
   - **Fix:** Leveraged Pandas 	o_datetime(format='mixed') to normalize the entire vector into a standard timezone-naive format.

## Project Structure

**Core directories:**
- `Dashboard/` - Power BI dashboard file (`.pbix`) and exported PDF
- `Links/` - Contains URL links to the final video presentation
- `scripts/` - Database extraction and processing scripts (`export_data.py`)
- `output/raw/` - Raw CSV files extracted from local databases (Git-ignored)
- `/` - Root directory contains SQL queries, MongoDB pipelines, and the Python analysis notebook

## Query Processing

**PostgreSQL Requirements (01_sql_queries.sql):**
- Joins and Aggregation: Calculates active customers, MRR, and support ticket rates per tier using dynamic date windows.
- Window Functions: Calculates customer LTV and generates percentage variance against tier averages.
- Subqueries: Detects high-friction downgrades within 90-day rolling windows.
- Time Series: Generates month-over-month growth and rolling 3-month churn rate flags.
- Advanced Matching: Identifies duplicate accounts via domain exclusion, overlapping team emails, and string manipulation.

**MongoDB Requirements (02_mongodb_queries.js):**
- Aggregation Pipeline: Calculates average weekly sessions and duration percentiles.
- Event Analysis: Computes DAU and exact 7-day retention rates per feature.
- Funnel Analysis: Tracks stage-to-stage conversion and median time-to-convert across the 5-step onboarding funnel.
- Cross-Reference: Generates weighted engagement scores to identify top free-tier upsell targets.

## Key Findings

### 1. Engagement Trends vs. Cancellation
- **Metric:** Median Active Days
- **Active Customers:** 40.0 days
- **Cancelled Customers:** 39.0 days
- **Statistical Significance:** Mann-Whitney U test p-value = 0.128 (Fail to reject null hypothesis)
- **Analysis:** Platform engagement does not correlate with churn. Cancelled accounts exhibit identical login frequency to retained accounts prior to cancellation.

### 2. Product Friction vs. Cancellation
- **Metric:** Average Support Tickets
- **Active Customers:** 5.00 tickets
- **Cancelled Customers:** 5.01 tickets
- **Analysis:** Support volume distributions show no significant skew between active and cancelled users. Support friction alone is not the primary catalyst for churn.

### 3. Revenue Scaling
- **Metric:** Plan Tier vs. MRR (Correlation Matrix)
- **Correlation Coefficient:** 0.89
- **Analysis:** Pricing models operate exactly as intended without discount anomalies. MRR scales predictably with tier upgrades.

## Strategic Recommendations

1. **Pivot Retention Operations:**
   - **Action:** Shift retention focus away from automated product-usage alerts.
   - **Target:** High-value enterprise accounts nearing renewal.
   - **Purpose:** Engagement does not predict cancellation. Account Management teams must conduct executive ROI reviews to address external cancellation drivers (e.g., budget cuts) rather than relying on login frequency alerts.

2. **Aggressive Free-Tier Upselling:**
   - **Action:** Target highly engaged Free and Starter users for immediate tier upgrades.
   - **Target:** Top 20 Free-tier users (identified in `02_mongodb_queries.js`).
   - **Purpose:** The 0.89 MRR correlation proves that upgrades scale revenue predictably.

3. **Product UX Audit:**
   - **Action:** Investigate the features generating 5+ support tickets across the active customer base.
   - **Target:** "Support Risk" segmented accounts.
   - **Purpose:** While support volume is not currently causing immediate churn, over 80% of the active customer base falls into high-risk support categories. This represents an unsustainable operational bottleneck.

---

MIT License - Copyright (c) 2026

## Custom Libraries Used

This project heavily utilizes **insightfulpy** (insightfulpy==0.1.7), a custom Python package developed specifically for advanced Exploratory Data Analysis (EDA) and batch plotting. 

The source code and documentation for insightfulpy can be inspected at:
- **PyPI:** [pypi.org/project/insightfulpy/](https://pypi.org/project/insightfulpy/)
- **GitHub:** [github.com/dhaneshbb/insightfulpy](https://github.com/dhaneshbb/insightfulpy)

---

**Author:** Dhanesh B. B.  
**GitHub:** [@dhaneshbb](https://github.com/dhaneshbb)
