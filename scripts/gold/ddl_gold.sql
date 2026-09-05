/*
===============================================================================
DDL Script: Create Gold Views  (PostgreSQL)
===============================================================================
Purpose:
    Builds the gold layer — the star schema the business actually queries.
    Two dimensions and one fact, all as VIEWS over silver: gold stores nothing
    and is computed on read, so it can never drift from silver.

Design notes:
    - Views, not tables. Per the architecture spec, gold is the only public
      interface and holds no data of its own. Rebuilding gold = re-running this
      script; there is no gold load procedure.
    - Columns are renamed to business language here, and only here. This is the
      single naming boundary in the warehouse: source names live in bronze and
      silver, friendly names start in gold.
    - Surrogate keys (customer_key, product_key) are generated with ROW_NUMBER().
      They are stable only within one read — acceptable because history is not
      kept (SCD 1, full reload) and nothing outside gold persists them.
    - Gold reads silver only. It never touches bronze.

WARNING:
    Running this drops and recreates all three gold views.
===============================================================================
*/


-- ============================================================
-- gold.dim_customers
-- ------------------------------------------------------------
-- Grain: one row per CRM customer.
-- CRM cust_info is the master; the two ERP files enrich it with birthdate,
-- gender and country. LEFT JOINs, because a CRM customer missing from ERP is
-- still a customer — 4 of them are (the junk rows dropped in silver).
--
-- Both joins are 1:1 on the normalized key, so neither can fan out the grain.
-- ============================================================
DROP VIEW IF EXISTS gold.dim_customers CASCADE;
CREATE VIEW gold.dim_customers AS
SELECT
    ROW_NUMBER() OVER (ORDER BY ci.cst_id)  AS customer_key,
    ci.cst_id                               AS customer_id,
    ci.cst_key                              AS customer_number,
    ci.cst_firstname                        AS first_name,
    ci.cst_lastname                         AS last_name,
    la.cntry                                AS country,
    ci.cst_marital_status                   AS marital_status,

    -- Gender lives in BOTH systems and they disagree. CRM is declared the
    -- master: its value wins whenever it has one, and ERP only fills the gaps.
    -- Picking a master (rather than coalescing arbitrarily) is what makes the
    -- column reproducible.
    CASE WHEN ci.cst_gndr <> 'n/a' THEN ci.cst_gndr
         ELSE COALESCE(ca.gen, 'n/a')
    END                                     AS gender,

    ca.bdate                                AS birthdate,
    ci.cst_create_date                      AS create_date
FROM silver.crm_cust_info ci
LEFT JOIN silver.erp_cust_az12 ca ON ci.cst_key = ca.cid
LEFT JOIN silver.erp_loc_a101  la ON ci.cst_key = la.cid;


-- ============================================================
-- gold.dim_products
-- ------------------------------------------------------------
-- Grain: one row per CURRENT product.
-- silver.crm_prd_info holds one row per product *version*; prd_end_dt IS NULL
-- marks the version in force today. Filtering to it is what makes this a true
-- dimension rather than a history table — the brief requires no historization,
-- so expired versions are excluded rather than modelled as SCD 2 rows.
-- ============================================================
DROP VIEW IF EXISTS gold.dim_products CASCADE;
CREATE VIEW gold.dim_products AS
SELECT
    ROW_NUMBER() OVER (ORDER BY pn.prd_start_dt, pn.prd_key) AS product_key,
    pn.prd_id        AS product_id,
    pn.prd_key       AS product_number,
    pn.prd_nm        AS product_name,
    pn.cat_id        AS category_id,

    -- COALESCE, not a bare column: 7 pedal products carry cat_id 'CO_PE', and
    -- no such row exists in the ERP category file (it ships 'CO_PD' instead).
    -- A genuine source gap, not a join bug. Silver's convention is that
    -- descriptive unknowns read 'n/a' rather than NULL, and gold keeps it, so
    -- a report never has to special-case a missing category.
    COALESCE(pc.cat, 'n/a')         AS category,
    COALESCE(pc.subcat, 'n/a')      AS subcategory,
    COALESCE(pc.maintenance, 'n/a') AS maintenance,

    pn.prd_cost      AS cost,
    pn.prd_line      AS product_line,
    pn.prd_start_dt  AS start_date
FROM silver.crm_prd_info pn
LEFT JOIN silver.erp_px_cat_g1v2 pc ON pn.cat_id = pc.id
WHERE pn.prd_end_dt IS NULL;   -- current version only


-- ============================================================
-- gold.fact_sales
-- ------------------------------------------------------------
-- Grain: one row per product line on an order — unchanged from silver.
-- The dimensions are joined purely to swap business keys for surrogate keys;
-- no measure is recomputed here (silver already fixed sales/price/quantity).
--
-- LEFT JOIN both dimensions: a sales row whose product version has expired, or
-- whose customer was dropped as junk, must still be counted. Losing revenue to
-- a failed lookup is worse than a NULL key — quality checks catch the NULLs.
-- ============================================================
DROP VIEW IF EXISTS gold.fact_sales CASCADE;
CREATE VIEW gold.fact_sales AS
SELECT
    sd.sls_ord_num   AS order_number,
    pr.product_key   AS product_key,
    cu.customer_key  AS customer_key,
    sd.sls_order_dt  AS order_date,
    sd.sls_ship_dt   AS shipping_date,
    sd.sls_due_dt    AS due_date,
    sd.sls_sales     AS sales_amount,
    sd.sls_quantity  AS quantity,
    sd.sls_price     AS price
FROM silver.crm_sales_details sd
LEFT JOIN gold.dim_products  pr ON sd.sls_prd_key = pr.product_number
LEFT JOIN gold.dim_customers cu ON sd.sls_cust_id = cu.customer_id;
