/*
===============================================================================
Load Script: Bronze Layer  (PostgreSQL)
===============================================================================
Purpose:
    Loads all six source CSVs into the bronze layer.

    Full load, truncate & insert: every run wipes each table and reloads it from
    the source file. No incremental logic — the brief requires no historization.

Usage (from the repo root, so the relative CSV paths resolve):
    psql -d datawarehouse -f scripts/bronze/proc_load_bronze.sql

Notes:
    - \copy runs on the CLIENT (psql), so it reads files from your machine and
      needs no superuser rights or server-side file access. Paths are relative
      to the directory psql is started from — the repo root.
    - FORMAT csv turns empty unquoted fields into NULL, so blank numerics stay
      NULL rather than being fabricated as 0 (asserted in the quality checks).
    - The whole load is one transaction: if any file fails, nothing is
      half-loaded and the previous bronze data is kept.
    - \timing prints each statement's duration, so a slow file is visible.
===============================================================================
*/

\set ON_ERROR_STOP on
\timing on

BEGIN;

\echo '=========================================================='
\echo 'Loading Bronze Layer'
\echo '=========================================================='

\echo ''
\echo '--- CRM Tables ---'

\echo '>> bronze.crm_cust_info'
TRUNCATE TABLE bronze.crm_cust_info;
\copy bronze.crm_cust_info FROM 'datasets/source_crm/cust_info.csv' WITH (FORMAT csv, HEADER true)

\echo '>> bronze.crm_prd_info'
TRUNCATE TABLE bronze.crm_prd_info;
\copy bronze.crm_prd_info FROM 'datasets/source_crm/prd_info.csv' WITH (FORMAT csv, HEADER true)

\echo '>> bronze.crm_sales_details'
TRUNCATE TABLE bronze.crm_sales_details;
\copy bronze.crm_sales_details FROM 'datasets/source_crm/sales_details.csv' WITH (FORMAT csv, HEADER true)

\echo ''
\echo '--- ERP Tables ---'

\echo '>> bronze.erp_cust_az12'
TRUNCATE TABLE bronze.erp_cust_az12;
\copy bronze.erp_cust_az12 FROM 'datasets/source_erp/CUST_AZ12.csv' WITH (FORMAT csv, HEADER true)

\echo '>> bronze.erp_loc_a101'
TRUNCATE TABLE bronze.erp_loc_a101;
\copy bronze.erp_loc_a101 FROM 'datasets/source_erp/LOC_A101.csv' WITH (FORMAT csv, HEADER true)

\echo '>> bronze.erp_px_cat_g1v2'
TRUNCATE TABLE bronze.erp_px_cat_g1v2;
\copy bronze.erp_px_cat_g1v2 FROM 'datasets/source_erp/PX_CAT_G1V2.csv' WITH (FORMAT csv, HEADER true)

COMMIT;

\echo ''
\echo '=========================================================='
\echo 'Bronze Layer loaded successfully'
\echo '=========================================================='
