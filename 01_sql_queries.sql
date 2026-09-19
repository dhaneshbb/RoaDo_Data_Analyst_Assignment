-- RoaDo Data Analyst Intern Assignment
-- PostgreSQL Queries
-- ------------------------------------------------------------------

-- Q1: Plan tier overview (Active customers, MRR, and support tickets)
-- I used the latest ticket date as the cutoff so we are always looking at the "last 6 months" of available data.
WITH recent_date_cutoff AS (
    SELECT MAX(created_at) AS max_date FROM nimbus.support_tickets
),
plan_metrics AS (
    SELECT 
        p.plan_name,
        p.plan_id,
        COUNT(DISTINCT s.customer_id) FILTER (WHERE s.status = 'active') AS active_customers,
        AVG(s.mrr_usd) FILTER (WHERE s.status = 'active') AS avg_monthly_revenue
    FROM nimbus.plans p
    LEFT JOIN nimbus.subscriptions s ON p.plan_id = s.plan_id
    GROUP BY p.plan_name, p.plan_id
),
ticket_volume AS (
    SELECT 
        s.plan_id,
        COUNT(t.ticket_id) AS total_tickets_6m
    FROM nimbus.support_tickets t
    JOIN nimbus.subscriptions s ON t.customer_id = s.customer_id
    CROSS JOIN recent_date_cutoff cutoff
    WHERE t.created_at >= cutoff.max_date - INTERVAL '6 months'
    GROUP BY s.plan_id
)
SELECT 
    pm.plan_name,
    pm.active_customers,
    ROUND(pm.avg_monthly_revenue, 2) AS avg_monthly_revenue,
    ROUND(COALESCE(tv.total_tickets_6m, 0)::NUMERIC / NULLIF(pm.active_customers, 0) / 6.0, 2) AS monthly_tickets_per_user
FROM plan_metrics pm
LEFT JOIN ticket_volume tv ON pm.plan_id = tv.plan_id
ORDER BY pm.avg_monthly_revenue DESC;


-- ------------------------------------------------------------------
-- Q2: Customer LTV and Tier Rankings
-- Calculates how far each customer's LTV is above or below their tier's average
WITH customer_total_ltv AS (
    SELECT 
        s.customer_id,
        p.plan_name,
        COALESCE(SUM(b.amount_usd), 0) AS lifetime_value
    FROM nimbus.subscriptions s
    JOIN nimbus.plans p ON s.plan_id = p.plan_id
    LEFT JOIN nimbus.billing_invoices b 
      ON s.subscription_id = b.subscription_id AND b.status = 'paid'
    GROUP BY s.customer_id, p.plan_name
),
tier_rankings AS (
    SELECT 
        customer_id,
        plan_name,
        ROUND(lifetime_value::NUMERIC, 2) AS ltv,
        RANK() OVER (PARTITION BY plan_name ORDER BY lifetime_value DESC) AS tier_rank,
        ROUND(AVG(lifetime_value) OVER (PARTITION BY plan_name)::NUMERIC, 2) AS avg_tier_ltv
    FROM customer_total_ltv
)
SELECT 
    customer_id,
    plan_name,
    ltv,
    tier_rank,
    avg_tier_ltv,
    ROUND(((ltv - avg_tier_ltv) / NULLIF(avg_tier_ltv, 0)) * 100, 2) AS pct_diff_from_avg
FROM tier_rankings
ORDER BY plan_name, tier_rank;


-- ------------------------------------------------------------------
-- Q3: High-friction downgrades
-- Finds customers who downgraded recently but had >3 tickets right before doing so.
WITH sub_cutoff AS (
    SELECT MAX(start_date) AS latest_sub_date FROM nimbus.subscriptions
),
recent_downgrades AS (
    SELECT 
        s1.customer_id,
        p1.plan_name AS previous_plan,
        p2.plan_name AS new_plan,
        s2.start_date AS downgrade_date
    FROM nimbus.subscriptions s1
    JOIN nimbus.subscriptions s2 
      ON s1.customer_id = s2.customer_id 
      AND s2.start_date = s1.end_date
    JOIN nimbus.plans p1 ON s1.plan_id = p1.plan_id
    JOIN nimbus.plans p2 ON s2.plan_id = p2.plan_id
    CROSS JOIN sub_cutoff c
    WHERE p2.monthly_price_usd < p1.monthly_price_usd
      AND s2.start_date >= (c.latest_sub_date - INTERVAL '90 days')
)
SELECT 
    d.customer_id,
    d.previous_plan,
    d.new_plan,
    d.downgrade_date,
    COUNT(t.ticket_id) AS support_tickets_before_downgrade
FROM recent_downgrades d
JOIN nimbus.support_tickets t 
  ON d.customer_id = t.customer_id
WHERE t.created_at BETWEEN (d.downgrade_date - INTERVAL '30 days') AND d.downgrade_date
GROUP BY d.customer_id, d.previous_plan, d.new_plan, d.downgrade_date
HAVING COUNT(t.ticket_id) > 3;


-- ------------------------------------------------------------------
-- Q4: Rolling 3-month churn rate and MoM growth
-- Flags months where the churn rate spikes to 2x the rolling average
WITH monthly_subs AS (
    SELECT 
        p.plan_tier,
        DATE_TRUNC('month', s.start_date)::DATE AS sub_month,
        COUNT(s.subscription_id) AS new_subs,
        SUM(CASE WHEN s.status IN ('cancelled', 'expired') THEN 1 ELSE 0 END) AS churned_subs,
        COUNT(s.subscription_id) + SUM(CASE WHEN s.status IN ('cancelled', 'expired') THEN 1 ELSE 0 END) AS active_base_approx
    FROM nimbus.subscriptions s
    JOIN nimbus.plans p ON s.plan_id = p.plan_id
    GROUP BY p.plan_tier, DATE_TRUNC('month', s.start_date)
),
calc_rates AS (
    SELECT 
        plan_tier,
        sub_month,
        new_subs,
        LAG(new_subs) OVER (PARTITION BY plan_tier ORDER BY sub_month) AS prev_month_subs,
        (churned_subs::NUMERIC / NULLIF(active_base_approx, 0)) AS churn_rate
    FROM monthly_subs
),
rolling_calcs AS (
    SELECT 
        plan_tier,
        sub_month,
        new_subs,
        ROUND(((new_subs - prev_month_subs)::NUMERIC / NULLIF(prev_month_subs, 0)) * 100, 2) AS mom_growth_pct,
        ROUND(churn_rate * 100, 2) AS churn_rate_pct,
        ROUND(AVG(churn_rate) OVER (
            PARTITION BY plan_tier 
            ORDER BY sub_month 
            ROWS BETWEEN 2 PRECEDING AND CURRENT ROW
        ) * 100, 2) AS rolling_3m_churn_pct
    FROM calc_rates
)
SELECT 
    *,
    CASE WHEN churn_rate_pct > (2 * rolling_3m_churn_pct) AND rolling_3m_churn_pct > 0 THEN 'Yes' ELSE 'No' END AS churn_spike_flag
FROM rolling_calcs
ORDER BY plan_tier, sub_month;


-- ------------------------------------------------------------------
-- Q5: Duplicate Account Detection
-- Checks for matching email domains (excluding public ones), exact team member emails, or identical company prefixes.
WITH company_domains AS (
    SELECT 
        customer_id,
        company_name,
        contact_email,
        SPLIT_PART(contact_email, '@', 2) AS domain
    FROM nimbus.customers
    WHERE SPLIT_PART(contact_email, '@', 2) NOT IN ('gmail.com', 'yahoo.com', 'hotmail.com', 'outlook.com')
),
domain_flags AS (
    SELECT 
        d1.customer_id AS cust1_id,
        d1.company_name AS cust1_name,
        d2.customer_id AS cust2_id,
        d2.company_name AS cust2_name,
        'Shared Business Domain (' || d1.domain || ')' AS duplicate_reason
    FROM company_domains d1
    JOIN company_domains d2 ON d1.domain = d2.domain AND d1.customer_id < d2.customer_id
),
team_flags AS (
    SELECT 
        t1.customer_id AS cust1_id,
        c1.company_name AS cust1_name,
        t2.customer_id AS cust2_id,
        c2.company_name AS cust2_name,
        'Shared Team Email (' || t1.email || ')' AS duplicate_reason
    FROM nimbus.team_members t1
    JOIN nimbus.team_members t2 ON t1.email = t2.email AND t1.customer_id < t2.customer_id
    JOIN nimbus.customers c1 ON t1.customer_id = c1.customer_id
    JOIN nimbus.customers c2 ON t2.customer_id = c2.customer_id
),
name_flags AS (
    SELECT 
        c1.customer_id AS cust1_id,
        c1.company_name AS cust1_name,
        c2.customer_id AS cust2_id,
        c2.company_name AS cust2_name,
        'Almost Identical Company Name' AS duplicate_reason
    FROM nimbus.customers c1
    JOIN nimbus.customers c2 ON c1.customer_id < c2.customer_id
    WHERE LEFT(LOWER(c1.company_name), 8) = LEFT(LOWER(c2.company_name), 8)
      AND LENGTH(c1.company_name) > 8
)
SELECT * FROM domain_flags
UNION  
SELECT * FROM team_flags
UNION 
SELECT * FROM name_flags;
